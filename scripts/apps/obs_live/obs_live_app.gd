extends Control
## V-Stream 直播姬：开播向导（纯卡牌操作台，无左侧静态预监）→ 入场 → 演出 → 结算。
## Step0 左右分栏；Step1 主区+右侧预计结算面板；Step2 确认单。

const CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/live_stream_card.tscn")
const DROP_SLOT_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/card_drop_slot.tscn")
const DRAG_CONTROLLER_SCENE: PackedScene = preload("res://scenes/ui/cards/card_drag_controller.tscn")
const DECK_SCENE: PackedScene = preload("res://scenes/ui/cards/card_deck.tscn")
const LIVE_SHOW_GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")

const COLOR_TEXT: Color = Color("#1A2238")
const COLOR_TEXT_SECONDARY: Color = Color("#5A6885")
const COLOR_TEXT_MUTED: Color = Color("#8793A5")
const COLOR_ACCENT: Color = Color("#E5486D")
const COLOR_ACCENT_HOVER: Color = Color("#CB3159")
const COLOR_SURFACE: Color = Color("#FFFFFF")
const COLOR_SURFACE_ALT: Color = Color("#E8F0FB")
const COLOR_BORDER: Color = Color("#C8D6EA")
const COLOR_FAMILY: Color = Color("#3A5FA8")
const COLOR_OK: Color = Color("#3FA37A")
const COLOR_DASHBOARD_BG: Color = Color("#EAF1FA")

enum AppState { WIZARD, ENTRANCE, LIVE, SETTLEMENT }

const OBS_APP_ID: String = "obs_live"
const POST_STREAM_REST_SECONDS: float = 0.85

@onready var wizard_root: VBoxContainer = %WizardRoot
@onready var wizard_tab_bar: WizardTabBar = %WizardTabBar
@onready var brand_status: Label = %BrandStatus
@onready var desk_host: Control = %DeskHost
@onready var footer_status: Label = %FooterStatus
@onready var back_button: Button = %BackButton
@onready var next_button: Button = %NextButton
@onready var live_root: Control = %LiveRoot
@onready var stream_stage: StreamStage = %StreamStage
@onready var stream_chat: StreamChat = %StreamChat
@onready var entrance_overlay: EntranceOverlay = %StreamStage.entrance_overlay
@onready var settlement_panel: SettlementPanel = %SettlementPanel

var live_title: Label:
	get: return stream_stage.live_title if stream_stage != null else null
var live_viewers: Label:
	get: return stream_stage.live_viewers if stream_stage != null else null
var live_clock: Label:
	get: return stream_stage.live_clock if stream_stage != null else null
var avatar_rect: RoundedAvatar:
	get: return stream_stage.avatar_rect if stream_stage != null else null
var channel_name: Label:
	get: return stream_stage.channel_name if stream_stage != null else null
var channel_tag: Label:
	get: return stream_stage.channel_tag if stream_stage != null else null
var fast_button: Button:
	get: return stream_stage.fast_button if stream_stage != null else null
var skip_button: Button:
	get: return stream_stage.skip_button if stream_stage != null else null

var _manager: Node = null
var _card_library_manager: Node = null
var _state: int = AppState.WIZARD
var _max_step_reached: int = 0
var _generator: Node = null
var _live_plan: StreamPlanSnapshot = null
var _live_result: StreamSettlementResult = null
var _live_elapsed: float = 0.0
var _drag_controller: CardDragController = null
var _deck: CardDeck = null
var _live_show: Dictionary = {}
var _generation_failed: bool = false

## 拖放增量更新状态：节目槽 / 接缝提示 / 修饰槽 / 预计结算网格的运行时引用。
var _suppress_render: bool = false
var _program_slots: Array[CardDropSlot] = []
var _modifier_slots: Array[CardDropSlot] = []
var _seam_labels: Array[Label] = []
var _metrics_grid: GridContainer = null


func _ready() -> void:
	_manager = get_node_or_null("/root/LiveStreamManager")
	_card_library_manager = get_node_or_null("/root/CardLibraryManager")
	_setup_drag_system()
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	wizard_tab_bar.tab_pressed.connect(_on_tab_pressed)
	fast_button.pressed.connect(_on_fast_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	entrance_overlay.entrance_finished.connect(_on_entrance_finished)
	settlement_panel.finish_pressed.connect(_on_settlement_finish)
	settlement_panel.crisis_choice_made.connect(_on_crisis_choice_made)
	stream_stage.show_finished.connect(_on_show_finished)
	stream_stage.live_chat_event.connect(_on_live_chat_event)
	_apply_primary_button_style(next_button)
	if _manager == null or _card_library_manager == null:
		_render_manager_error()
		return
	_manager.step_changed.connect(_on_manager_step_changed)
	_manager.draft_changed.connect(_on_manager_draft_changed)
	_manager.catalogs_changed.connect(_on_catalogs_changed)
	_card_library_manager.library_changed.connect(_on_catalogs_changed)
	if _manager.load_saved_run_state():
		_max_step_reached = maxi(_max_step_reached, int(_manager.get_current_step()))
	_render()


func _setup_drag_system() -> void:
	_drag_controller = DRAG_CONTROLLER_SCENE.instantiate() as CardDragController
	add_child(_drag_controller)
	_drag_controller.move_committed.connect(_on_card_move_committed)


func _process(delta: float) -> void:
	if _state != AppState.LIVE or _live_result == null:
		return
	_live_elapsed += delta
	var total_seconds: int = int(_live_elapsed)
	var elapsed_minutes: int = floori(float(total_seconds) / 60.0)
	stream_stage.set_elapsed_text("%02d:%02d" % [elapsed_minutes, total_seconds % 60])


func _update_channel_info() -> void:
	var persona: StreamPersonaResource = null
	if _manager != null and _live_plan != null:
		persona = _manager.get_persona(_live_plan.persona_id)
	if persona == null and _card_library_manager != null and _card_library_manager.has_method("get_catalog"):
		var catalog = _card_library_manager.get_catalog()
		if catalog != null and catalog.has_method("get_persona"):
			persona = catalog.get_persona(_live_plan.persona_id)
	if persona != null:
		if channel_name != null:
			channel_name.text = persona.channel_name
		if avatar_rect != null:
			avatar_rect.set_avatar(persona.channel_avatar, persona.channel_name)


# ---------------------------------------------------------------- 向导

func _render() -> void:
	if _manager == null or _state != AppState.WIZARD:
		return
	_clear_desk()
	var step: int = int(_manager.get_current_step())
	wizard_tab_bar.refresh(step, _max_step_reached)
	brand_status.text = "● 推流准备中" if step < 2 else "● 待推流"
	match step:
		0:
			_build_setup_step()
		1:
			_build_script_step()
		2:
			_build_confirm_step()
	_update_footer(step)


func _clear_desk() -> void:
	if _drag_controller != null:
		_drag_controller.clear_containers_except()
	_deck = null
	_program_slots.clear()
	_modifier_slots.clear()
	_seam_labels.clear()
	_metrics_grid = null
	for child: Node in desk_host.get_children():
		desk_host.remove_child(child)
		child.queue_free()


func _attach_desk_root(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.anchor_right = 1.0
	node.anchor_bottom = 1.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desk_host.add_child(node)


func _make_wizard_split() -> HBoxContainer:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return split


func _make_card_library_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	return scroll


func _populate_card_deck(accepted_kinds: Array[String]) -> CardDeck:
	_deck = DECK_SCENE.instantiate() as CardDeck
	_deck.auto_wrap = true
	_deck.card_size = CardDisplayMetrics.hand_size()
	_deck.normal_gap = 16.0
	_deck.row_separation = 16.0
	_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_drag_controller.register_container(_deck)
	_deck.accepted_kinds = accepted_kinds
	return _deck


func _render_manager_error() -> void:
	_clear_desk()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.add_child(_make_label("直播准备服务暂不可用", 30, COLOR_TEXT))
	body.add_child(_make_label("直播准备服务尚未载入，请重新打开应用。", 22, COLOR_TEXT_SECONDARY))
	_attach_desk_root(body)
	back_button.disabled = true
	next_button.disabled = true
	footer_status.text = "无法读取开播草稿"


func _build_setup_step() -> void:
	var draft: Dictionary = _manager.get_draft()
	var active_material: LiveStreamMaterialResource = _manager.get_material_definition()
	var material_instance: Dictionary = _manager.get_material_instance()

	var split := _make_wizard_split()
	_attach_desk_root(split)

	var left_panel := _make_desk_panel()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 2.0
	split.add_child(left_panel)
	var left_body: VBoxContainer = left_panel.get_meta("body")
	left_body.add_theme_constant_override("separation", 12)

	left_body.add_child(_make_desk_heading("1", "本场标题", "占位为素材名，开播时按人设与节目单生成"))
	var title_info := _make_label(
		"📌　%s" % str(draft.get("title", "")),
		24,
		COLOR_TEXT
	)
	title_info.custom_minimum_size.y = 36
	left_body.add_child(title_info)

	var active_persona: StreamPersonaResource = _manager.get_active_persona()
	var persona_state: Dictionary = GameState.persona_progress.get(
		String(GameState.active_persona_id), {}
	)
	left_body.add_child(_make_desk_heading("2", "当前形象", "扮演中不可切换，切换走毕业转生"))
	var persona_info := _make_label(
		"%s　·　熟练 %d　·　固化 %d" % [
			active_persona.display_name if active_persona != null else "—",
			int(persona_state.get("proficiency", 0.0)),
			int(persona_state.get("fixation", 0.0)),
		],
		22,
		COLOR_TEXT
	)
	persona_info.custom_minimum_size.y = 36
	left_body.add_child(persona_info)

	left_body.add_child(_make_desk_heading("3", "素材装载", "从右侧卡库拖入，或点击卡牌直接装载"))
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 20)
	slot_row.custom_minimum_size.y = CardDisplayMetrics.FULL_SIZE.y
	slot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_body.add_child(slot_row)

	var material_slot: CardDropSlot = DROP_SLOT_SCENE.instantiate()
	var material_kinds: Array[String] = ["material"]
	material_slot.setup("material", material_kinds, "素材槽\n拖入素材卡")
	material_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	material_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot_row.add_child(material_slot)
	_register_slot(material_slot)
	if active_material != null:
		var stage_material: LiveStreamCardView = _make_material_card(active_material, material_instance, true, false)
		_bind_card(stage_material)
		material_slot.set_content(stage_material)

	var right_panel := _make_desk_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 3.0
	split.add_child(right_panel)
	var right_body: VBoxContainer = right_panel.get_meta("body")
	right_body.add_theme_constant_override("separation", 10)
	right_body.add_child(_make_label("素材库", 24, COLOR_FAMILY))
	right_body.add_child(_make_label("点击或拖到左侧槽位", 18, COLOR_TEXT_MUTED))

	var scroll := _make_card_library_scroll()
	right_body.add_child(scroll)
	var deck := _populate_card_deck(["material"])
	scroll.add_child(deck)

	var selected_material: String = str(draft.get("material_instance_id", ""))
	for instance: Dictionary in _manager.get_material_instances():
		var instance_id := StringName(str(instance.get("instance_id", "")))
		var instance_material: LiveStreamMaterialResource = _manager.get_material_definition(instance_id)
		if instance_material == null or String(instance_id) == selected_material:
			continue
		var material_card: LiveStreamCardView = _make_material_card(
			instance_material, instance, false, true
		)
		material_card.pressed.connect(_on_material_selected.bind(instance_id))
		_bind_card(material_card)
		deck.add_card(material_card)


func _make_material_card(
	material_resource: LiveStreamMaterialResource,
	instance: Dictionary,
	selected: bool,
	draggable: bool
) -> LiveStreamCardView:
	var card: LiveStreamCardView = CARD_SCENE.instantiate()
	var instance_id := StringName(str(instance.get("instance_id", "")))
	var tooltip: String = "一次性素材 · 播一场烧一张\n节目 %d 槽　·　锁定 %d 张" % [
		material_resource.program_slot_count,
		material_resource.locked_cards.size(),
	]
	card.configure(
		material_resource,
		selected,
		false,
		"槽 %d" % material_resource.program_slot_count,
		"锁 %d 张" % material_resource.locked_cards.size(),
		tooltip
	)
	if draggable:
		card.drag_payload = {
			"kind": "material",
			"id": String(instance_id),
			"title": material_resource.display_name,
		}
	return card


func _build_script_step() -> void:
	var draft: Dictionary = _manager.get_draft()
	var selected_slots: Array = draft.get("behavior_slots", [])
	var selected_modifiers: Array = draft.get("modifier_slots", [])
	var material_instance_id := StringName(str(draft.get("material_instance_id", "")))
	var compatible_cards: Array[BehaviorCardResource] = _card_library_manager.get_compatible_behavior_cards(material_instance_id, false)
	var budget_used: int = _manager.get_budget_used()
	var budget_limit: int = _manager.get_budget_limit()
	var preview: StreamSettlementResult = _manager.get_preview_result()

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_attach_desk_root(outer_vbox)

	# --- 1. 上半部分：节目编排 (左) + 预计结算 (右) ---
	var top_panel := _make_desk_panel()
	top_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	outer_vbox.add_child(top_panel)
	var top_body: VBoxContainer = top_panel.get_meta("body")
	top_body.add_theme_constant_override("separation", 12)

	top_body.add_child(_make_desk_heading("●", "节目编排", "把行为卡拖入节目槽，拼出本场的接口链"))

	var top_split := HBoxContainer.new()
	top_split.add_theme_constant_override("separation", 24)
	top_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_body.add_child(top_split)

	# 节目槽滚动区
	var slot_scroll := ScrollContainer.new()
	slot_scroll.custom_minimum_size.y = CardDisplayMetrics.FULL_SIZE.y + 56.0
	slot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_scroll.size_flags_stretch_ratio = 3.0
	slot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	top_split.add_child(slot_scroll)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 16)
	slot_scroll.add_child(slot_row)
	var over_budget: bool = budget_used > budget_limit
	for slot_index: int in range(selected_slots.size()):
		slot_row.add_child(_make_program_slot(selected_slots, slot_index, over_budget))

	# 预计结算仪表盘卡片 (右上角)
	var result_panel := _make_desk_panel(COLOR_DASHBOARD_BG)
	result_panel.custom_minimum_size.x = 280
	result_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_panel.size_flags_stretch_ratio = 1.0
	top_split.add_child(result_panel)
	var result_body: VBoxContainer = result_panel.get_meta("body")
	result_body.add_theme_constant_override("separation", 8)
	result_body.add_child(_make_label("预计结算", 20, COLOR_FAMILY))

	var metrics_grid := GridContainer.new()
	metrics_grid.columns = 2
	metrics_grid.add_theme_constant_override("h_separation", 14)
	metrics_grid.add_theme_constant_override("v_separation", 14)
	result_body.add_child(metrics_grid)
	_metrics_grid = metrics_grid
	_build_metrics_grid(metrics_grid, budget_used, budget_limit, preview)

	# --- 2. 修饰槽（如果有） ---
	if selected_modifiers.size() > 0:
		var mod_panel := _make_desk_panel()
		mod_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mod_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		outer_vbox.add_child(mod_panel)
		var mod_body: VBoxContainer = mod_panel.get_meta("body")
		mod_body.add_child(_make_label("修饰槽", 20, COLOR_FAMILY))
		var modifier_scroll := ScrollContainer.new()
		modifier_scroll.custom_minimum_size.y = CardDisplayMetrics.FULL_SIZE.y + 16.0
		modifier_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modifier_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		modifier_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		mod_body.add_child(modifier_scroll)
		var modifier_row := HBoxContainer.new()
		modifier_row.add_theme_constant_override("separation", 16)
		modifier_scroll.add_child(modifier_row)
		for modifier_index: int in range(selected_modifiers.size()):
			modifier_row.add_child(_make_modifier_slot(selected_modifiers, modifier_index))

	# --- 3. 下半部分：卡牌库 Panel ---
	var bottom_panel := _make_desk_panel()
	bottom_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(bottom_panel)
	var bottom_body: VBoxContainer = bottom_panel.get_meta("body")
	bottom_body.add_theme_constant_override("separation", 12)

	bottom_body.add_child(_make_label("行为卡库（%d 张兼容）" % compatible_cards.size(), 22, COLOR_FAMILY))
	var library_scroll := _make_card_library_scroll()
	bottom_body.add_child(library_scroll)
	var deck := _populate_card_deck(["behavior", "modifier", "program_card"])
	library_scroll.add_child(deck)
	_add_hand_cards(compatible_cards, selected_slots, false, &"behavior")

	var incompatible: Array[BehaviorCardResource] = _get_incompatible_behavior_cards()
	if not incompatible.is_empty():
		bottom_body.add_child(_make_incompatible_section(incompatible))

	if selected_modifiers.size() > 0:
		var modifiers: Array[LiveStreamCardResource] = []
		for modifier: ModifierCardResource in _card_library_manager.get_modifier_cards():
			modifiers.append(modifier)
		_add_hand_cards(modifiers, selected_modifiers, false, &"modifier")


func _make_program_slot(slots: Array, slot_index: int, over_budget: bool) -> Control:
	var slot_locked: bool = _manager.is_behavior_slot_locked(slot_index)
	var card_id: String = str(slots[slot_index])
	var card: LiveStreamCardResource = _card_library_manager.get_card(StringName(card_id))
	var slot: CardDropSlot = DROP_SLOT_SCENE.instantiate()
	var accepts: Array = []
	if not slot_locked:
		accepts.append("behavior")
		accepts.append("program_card")
	var placeholder: String = "%02d\n素材题面" % (slot_index + 1) if slot_locked else "%02d\n拖入行为卡" % (slot_index + 1)
	slot.setup(slot_index, accepts, placeholder)
	slot.locked = slot_locked
	slot.set_accept_filter(func(_incoming: Control, payload: Dictionary) -> bool:
		var kind: String = String(payload.get("kind", ""))
		if kind == "behavior":
			return not slot.has_card()
		return kind == "program_card"
	)
	_register_slot(slot)
	_program_slots.append(slot)
	var seam_label := _make_seam_label(slots, slot_index)
	_seam_labels.append(seam_label)
	if card == null:
		slot.set_over_budget(over_budget and not slot_locked)
		return _wrap_program_slot(slot, seam_label)
	var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
	card_view.configure(card, true, slot_locked)
	var state: Dictionary = _connection_state_of(slots, slot_index)
	card_view.configure_connection_state(state["left"] as Array[int], state["right"] as Array[int])
	card_view.set_over_budget(over_budget and not slot_locked)
	if not slot_locked:
		card_view.drag_payload = {
			"kind": "program_card",
			"card_id": card_id,
			"from_slot": slot_index,
			"title": card.display_name,
		}
		_reconnect_pressed(card_view, _on_behavior_slot_clear.bind(slot_index))
	_bind_card(card_view)
	slot.set_content(card_view)
	return _wrap_program_slot(slot, seam_label)


## 槽卡左右接缝的连接状态（构建与拖放增量刷新共用）。
func _connection_state_of(slots: Array, slot_index: int) -> Dictionary:
	var left_connected: Array[int] = []
	var right_connected: Array[int] = []
	var card_id: String = str(slots[slot_index])
	var card: BehaviorCardResource = _card_library_manager.get_card(StringName(card_id)) as BehaviorCardResource
	if card == null:
		return {"left": left_connected, "right": right_connected}
	if slot_index > 0:
		var previous_card: BehaviorCardResource = _find_neighbor_behavior(slots, slot_index, -1)
		if previous_card != null:
			left_connected = BehaviorCardResource.intersect_slots(previous_card.right_slots, card.left_slots)
		else:
			left_connected.assign(card.left_slots)
	if slot_index + 1 < slots.size():
		var next_card: BehaviorCardResource = _find_neighbor_behavior(slots, slot_index, 1)
		if next_card != null:
			right_connected = BehaviorCardResource.intersect_slots(card.right_slots, next_card.left_slots)
		else:
			right_connected.assign(card.right_slots)
	return {"left": left_connected, "right": right_connected}


## 先断开卡上所有 pressed 连接再连新目标（实例在容器间流动时需要换绑）。
func _reconnect_pressed(card: LiveStreamCardView, callable: Callable) -> void:
	for connection: Dictionary in card.pressed.get_connections():
		card.pressed.disconnect(connection["callable"])
	card.pressed.connect(callable)


func _wrap_program_slot(slot: CardDropSlot, seam_label: Label) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(slot)
	wrapper.add_child(seam_label)
	return wrapper


## 节目槽下方的接缝提示：填充率档位 / 空接风险 / 空槽惩罚（策划 §10.2 第 2 步）。
func _make_seam_label(slots: Array, slot_index: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 32
	label.add_theme_font_size_override("font_size", 20)
	_apply_seam_label(label, slots, slot_index)
	return label


func _apply_seam_label(label: Label, slots: Array, slot_index: int) -> void:
	var card_id: String = str(slots[slot_index])
	if card_id.is_empty():
		label.text = "空槽 ×0.9"
		label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		return
	var card: BehaviorCardResource = _card_library_manager.get_card(StringName(card_id)) as BehaviorCardResource
	var previous_index: int = _find_previous_occupied_slot(slots, slot_index)
	if card == null:
		label.text = ""
		return
	if previous_index < 0:
		label.text = "开场卡 · 无需填充"
		label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		return
	if card.left_slots.is_empty():
		label.text = ""
		return
	var previous_card: BehaviorCardResource = _card_library_manager.get_card(
		StringName(str(slots[previous_index]))
	) as BehaviorCardResource
	if previous_card == null:
		label.text = ""
		return
	var connected: Array[int] = BehaviorCardResource.intersect_slots(previous_card.right_slots, card.left_slots)
	var fill_ratio: float = float(connected.size()) / float(card.left_slots.size())
	var multiplier: float = _card_library_manager.get_balance().get_fill_multiplier(fill_ratio)
	if is_zero_approx(fill_ratio):
		label.text = "空接 ×%.1f　·　风险 +10%%" % multiplier
		label.add_theme_color_override("font_color", COLOR_ACCENT)
	elif fill_ratio >= 1.0:
		label.text = "满填充 ×%.1f" % multiplier
		label.add_theme_color_override("font_color", COLOR_OK)
	elif fill_ratio >= 0.5:
		label.text = "填充 ×%.1f" % multiplier
		label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	else:
		label.text = "部分填充 ×%.1f" % multiplier
		label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)


func _find_previous_occupied_slot(slots: Array, origin: int) -> int:
	for index: int in range(origin - 1, -1, -1):
		if not str(slots[index]).is_empty():
			return index
	return -1


func _make_modifier_slot(modifier_slots: Array, modifier_index: int) -> CardDropSlot:
	var card_id: String = str(modifier_slots[modifier_index])
	var card: LiveStreamCardResource = _card_library_manager.get_card(StringName(card_id))
	var slot: CardDropSlot = DROP_SLOT_SCENE.instantiate()
	var modifier_kinds: Array[String] = ["modifier"]
	slot.setup(modifier_index, modifier_kinds, "修饰槽 %d\n拖入修饰卡" % (modifier_index + 1))
	slot.set_accept_filter(func(_incoming: Control, _payload: Dictionary) -> bool:
		return not slot.has_card()
	)
	_register_slot(slot)
	_modifier_slots.append(slot)
	if card != null:
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, true)
		card_view.drag_payload = {
			"kind": "modifier",
			"card_id": String(card.content_id),
			"from_slot": modifier_index,
			"title": card.display_name,
		}
		_reconnect_pressed(card_view, _on_modifier_slot_clear.bind(modifier_index))
		_bind_card(card_view)
		slot.set_content(card_view)
	return slot


func _build_confirm_step() -> void:
	var draft: Dictionary = _manager.get_draft()
	var persona: StreamPersonaResource = _manager.get_active_persona()
	var selected_material: LiveStreamMaterialResource = _manager.get_material_definition()
	var selected_slots: Array = draft.get("behavior_slots", [])
	var selected_modifiers: Array = draft.get("modifier_slots", [])

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_attach_desk_root(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)

	body.add_child(_make_desk_heading("●", "本场开播确认单", "确认后进入直播间，消耗 1 时段"))

	var summary := _make_desk_panel()
	body.add_child(summary)
	var summary_body: VBoxContainer = summary.get_meta("body")
	summary_body.add_child(_make_label("标题　%s" % str(draft.get("title", "")), 24, COLOR_TEXT))
	summary_body.add_child(_make_label(
		"当前形象　%s　×　素材　%s" % [
			persona.display_name if persona != null else "—",
			selected_material.display_name if selected_material != null else "—"
		],
		22,
		COLOR_TEXT_SECONDARY
	))

	var preview_scroll := ScrollContainer.new()
	preview_scroll.custom_minimum_size.y = CardDisplayMetrics.FULL_SIZE.y + 24.0
	preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(preview_scroll)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 14)
	preview_scroll.add_child(preview_row)
	for index: int in range(selected_slots.size()):
		var card: LiveStreamCardResource = _card_library_manager.get_card(StringName(str(selected_slots[index])))
		if card == null:
			continue
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, false, _manager.is_behavior_slot_locked(index))
		preview_row.add_child(_wrap_sized_card(card_view, CardDisplayMetrics.FULL_SIZE))
	for modifier_id: Variant in selected_modifiers:
		var modifier: ModifierCardResource = _card_library_manager.get_card(StringName(str(modifier_id))) as ModifierCardResource
		if modifier == null:
			continue
		var modifier_view: LiveStreamCardView = CARD_SCENE.instantiate()
		modifier_view.configure(modifier, false)
		preview_row.add_child(_wrap_sized_card(modifier_view, CardDisplayMetrics.FULL_SIZE))

	var preview: StreamSettlementResult = _manager.get_preview_result()
	var preview_panel := _make_desk_panel(COLOR_SURFACE_ALT)
	body.add_child(preview_panel)
	var preview_body: VBoxContainer = preview_panel.get_meta("body")
	preview_body.add_child(_make_label("预结算", 24, COLOR_FAMILY))
	var risk: float = preview.accident_probability if preview != null else 0.0
	preview_body.add_child(_make_label(
		"峰值在线 %d　·　涨粉 %d　·　收益 ¥%d　·　事故风险 %.0f%%" % [
			preview.peak_viewers if preview != null else 0,
			preview.fan_delta if preview != null else 0,
			preview.revenue if preview != null else 0,
			risk * 100.0,
		],
		24,
		COLOR_TEXT
	))
	if preview != null:
		preview_body.add_child(_make_label(
			"压力 %+.0f　·　主播 EXP +%d" % [preview.stress_delta, preview.streamer_exp_gain],
			20,
			COLOR_TEXT_MUTED
		))

	var confirm_button := Button.new()
	confirm_button.custom_minimum_size = Vector2(520, 80)
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_button.text = "节目单已提交" if _manager.is_broadcast_pending() else "确认开播（占用 1 时段）"
	confirm_button.disabled = _manager.is_broadcast_pending()
	_apply_primary_button_style(confirm_button)
	confirm_button.pressed.connect(_on_confirm_broadcast)
	body.add_child(confirm_button)


func _add_hand_cards(
	cards: Array,
	selected_ids: Array,
	force_locked: bool,
	select_kind: StringName = &""
) -> void:
	for card_value: Variant in cards:
		var card: LiveStreamCardResource = card_value as LiveStreamCardResource
		if card == null:
			continue
		if String(card.content_id) in selected_ids:
			continue
		var is_locked: bool = force_locked or not _card_library_manager.is_card_unlocked(card.content_id)
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, false, is_locked)
		if not is_locked:
			if select_kind == &"behavior":
				card_view.drag_payload = {
					"kind": "behavior",
					"card_id": String(card.content_id),
					"title": card.display_name,
				}
				card_view.pressed.connect(_on_behavior_card_selected.bind(card.content_id))
			elif select_kind == &"modifier":
				card_view.drag_payload = {
					"kind": "modifier",
					"card_id": String(card.content_id),
					"title": card.display_name,
				}
				card_view.pressed.connect(_on_modifier_card_selected.bind(card.content_id))
		_bind_card(card_view)
		_deck.add_card(card_view)


## 已解锁但不兼容当前素材的行为卡（策划 §10.2 第 2 步：折叠在不兼容区）。
func _get_incompatible_behavior_cards() -> Array[BehaviorCardResource]:
	var result: Array[BehaviorCardResource] = []
	var material_instance_id := StringName(str(_manager.get_draft().get("material_instance_id", "")))
	var selected_material: LiveStreamMaterialResource = _manager.get_material_definition(material_instance_id)
	if selected_material == null:
		return result
	for card: BehaviorCardResource in _card_library_manager.get_behavior_cards():
		if not _card_library_manager.is_card_unlocked(card.content_id):
			continue
		if _card_library_manager.get_catalog().is_material_behavior_card(card.content_id):
			continue
		if not card.is_compatible_with(selected_material.tags):
			result.append(card)
	return result


func _make_incompatible_section(cards: Array[BehaviorCardResource]) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = "▸ 不兼容（%d 张）" % cards.size()
	toggle.add_theme_font_size_override("font_size", 20)
	toggle.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	toggle.add_theme_color_override("font_hover_color", COLOR_TEXT_SECONDARY)
	section.add_child(toggle)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = CardDisplayMetrics.hand_size().y + 24.0
	scroll.visible = false
	section.add_child(scroll)
	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 12)
	scroll.add_child(flow)
	for card: BehaviorCardResource in cards:
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, false, false)
		card_view.unavailable = true
		card_view.override_tooltip("本场素材不兼容\n无法编入节目单")
		flow.add_child(_wrap_sized_card(card_view, CardDisplayMetrics.hand_size()))
	toggle.toggled.connect(func(is_on: bool) -> void:
		scroll.visible = is_on
		toggle.text = ("▾" if is_on else "▸") + " 不兼容（%d 张）" % cards.size()
	)
	return section


func _bind_card(card: Control) -> void:
	if _drag_controller == null or card == null:
		return
	_drag_controller.bind_card(card)


func _register_slot(slot: CardSlot) -> void:
	if _drag_controller == null or slot == null:
		return
	_drag_controller.register_container(slot)


func _on_card_move_committed(_card: Control, payload: Dictionary, _source: Node, target: Node) -> void:
	if _manager == null:
		return
	# manager 方法是同步 emit draft_changed 的，必须在调用前就声明"本次由增量更新接管"。
	_suppress_render = true
	var ok: bool = false
	var kind: String = String(payload.get("kind", ""))
	if target is CardDeck:
		# 槽卡拖回牌库 = 从槽位取下（牌库内重排的负载没有 from_slot，直接放行）。
		var from_slot: int = int(payload.get("from_slot", -1))
		if from_slot < 0:
			_suppress_render = false
			return
		match kind:
			"program_card":
				ok = _manager.clear_behavior_slot(from_slot)
			"modifier":
				ok = _manager.clear_modifier_slot(from_slot)
		if not ok:
			_suppress_render = false
			_render()
			return
		_after_slot_card_removed(_card, kind)
		return
	if not (target is CardSlot):
		_suppress_render = false
		return
	var slot := target as CardSlot
	match kind:
		"material":
			ok = bool(_manager.select_material(StringName(str(payload.get("id", "")))))
		"behavior":
			ok = bool(_manager.place_behavior_card_at(StringName(str(payload.get("card_id", ""))), int(slot.slot_key)))
		"program_card":
			var from_slot: int = int(payload.get("from_slot", -1))
			var to_slot: int = int(slot.slot_key)
			if from_slot == to_slot:
				_suppress_render = false
				return
			var slots: Array = _manager.get_draft().get("behavior_slots", [])
			if to_slot < slots.size() and str(slots[to_slot]).is_empty():
				ok = bool(_manager.move_behavior_card(from_slot, to_slot))
			else:
				ok = bool(_manager.place_behavior_card_at(StringName(str(payload.get("card_id", ""))), to_slot))
		"modifier":
			var modifier_from_slot: int = int(payload.get("from_slot", -1))
			if modifier_from_slot >= 0 and modifier_from_slot != int(slot.slot_key):
				ok = bool(_manager.move_modifier_card(modifier_from_slot, int(slot.slot_key)))
			else:
				ok = bool(_manager.select_modifier_card(StringName(str(payload.get("card_id", "")))))
	if not ok:
		_suppress_render = false
		_render()
		return
	# 素材走全量重建（低频路径）；行为卡与修饰卡走增量更新。
	if kind == "material":
		_suppress_render = false
		_render()
		return
	_after_program_card_placed(_card, kind, slot)


## 拖放落点增量更新：给流动的卡实例换绑定（payload / pressed / 接缝态）。
func _after_program_card_placed(card: Control, kind: String, slot: CardSlot) -> void:
	var card_view := card as LiveStreamCardView
	if card_view == null or _manager.get_current_step() != 1:
		_suppress_render = false
		_render()
		return
	var slot_index: int = int(slot.slot_key)
	match kind:
		"behavior":
			var card_id: String = String(card_view.drag_payload.get("card_id", ""))
			card_view.drag_payload = {
				"kind": "program_card",
				"card_id": card_id,
				"from_slot": slot_index,
				"title": card_view.content_resource.display_name if card_view.content_resource != null else "",
			}
			_reconnect_pressed(card_view, _on_behavior_slot_clear.bind(slot_index))
		"program_card":
			var from_slot: int = int(card_view.drag_payload.get("from_slot", -1))
			if from_slot != slot_index:
				card_view.drag_payload["from_slot"] = slot_index
				_reconnect_pressed(card_view, _on_behavior_slot_clear.bind(slot_index))
		"modifier":
			var modifier_id: String = String(card_view.drag_payload.get("card_id", ""))
			card_view.drag_payload = {
				"kind": "modifier",
				"card_id": modifier_id,
				"from_slot": slot_index,
				"title": card_view.content_resource.display_name if card_view.content_resource != null else "",
			}
			_reconnect_pressed(card_view, _on_modifier_slot_clear.bind(slot_index))
	var slots: Array = _manager.get_draft().get("behavior_slots", [])
	if kind == "behavior" or kind == "program_card":
		var state: Dictionary = _connection_state_of(slots, slot_index)
		card_view.configure_connection_state(state["left"] as Array[int], state["right"] as Array[int])
	else:
		card_view.clear_connection_state()
	card_view.selected = true
	_refresh_program_view()


## 槽卡拖回牌库：恢复牌库身份（payload / pressed / 无接缝态）。
func _after_slot_card_removed(card: Control, kind: String) -> void:
	var card_view := card as LiveStreamCardView
	if card_view == null or _manager.get_current_step() != 1:
		_suppress_render = false
		_render()
		return
	if kind == "program_card":
		var card_id: String = String(card_view.drag_payload.get("card_id", ""))
		card_view.drag_payload = {
			"kind": "behavior",
			"card_id": card_id,
			"title": card_view.content_resource.display_name if card_view.content_resource != null else "",
		}
		_reconnect_pressed(card_view, _on_behavior_card_selected.bind(StringName(card_id)))
		card_view.clear_connection_state()
	else:
		var modifier_id: String = String(card_view.drag_payload.get("card_id", ""))
		card_view.drag_payload = {
			"kind": "modifier",
			"card_id": modifier_id,
			"title": card_view.content_resource.display_name if card_view.content_resource != null else "",
		}
		_reconnect_pressed(card_view, _on_modifier_card_selected.bind(StringName(modifier_id)))
		card_view.clear_connection_state()
	card_view.selected = false
	_refresh_program_view()


## 拖放增量刷新：接缝提示 / 超支红框 / 预计结算 / 底部按钮状态。
func _refresh_program_view() -> void:
	_refresh_seam_labels()
	_refresh_program_slots_over_budget()
	_refresh_preview_panel()
	_update_footer(int(_manager.get_current_step()))


func _refresh_seam_labels() -> void:
	var slots: Array = _manager.get_draft().get("behavior_slots", [])
	for index: int in range(_seam_labels.size()):
		if not is_instance_valid(_seam_labels[index]):
			continue
		_apply_seam_label(_seam_labels[index], slots, index)


func _refresh_program_slots_over_budget() -> void:
	var over: bool = _manager.get_budget_used() > _manager.get_budget_limit()
	for slot: CardDropSlot in _program_slots:
		if not is_instance_valid(slot):
			continue
		var applies: bool = over and not slot.locked
		slot.set_over_budget(applies)
		if slot.has_card() and slot.get_card() is LiveStreamCardView:
			(slot.get_card() as LiveStreamCardView).set_over_budget(applies)


func _refresh_preview_panel() -> void:
	if _metrics_grid == null or not is_instance_valid(_metrics_grid):
		return
	for child: Node in _metrics_grid.get_children():
		child.queue_free()
	_build_metrics_grid(
		_metrics_grid,
		_manager.get_budget_used(),
		_manager.get_budget_limit(),
		_manager.get_preview_result()
	)


func _wrap_sized_card(card: Control, target_size: Vector2) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = target_size
	wrapper.size = wrapper.custom_minimum_size
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2.ZERO
	card.custom_minimum_size = target_size
	card.size = target_size
	card.pivot_offset = card.size * 0.5
	wrapper.add_child(card)
	return wrapper


func _make_desk_panel(bg_color: Color = COLOR_SURFACE) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(bg_color, COLOR_BORDER, 16, true))
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	panel.set_meta("body", body)
	return panel


func _make_desk_heading(badge: String, title: String, helper: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var badge_label := Label.new()
	badge_label.text = badge
	badge_label.custom_minimum_size = Vector2(40, 40)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 22)
	badge_label.add_theme_color_override("font_color", Color.WHITE)
	var badge_panel := PanelContainer.new()
	badge_panel.custom_minimum_size = Vector2(40, 40)
	badge_panel.add_theme_stylebox_override("panel", _make_style(COLOR_FAMILY, COLOR_FAMILY, 20, false))
	badge_panel.add_child(badge_label)
	row.add_child(badge_panel)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	var title_label := _make_label(title, 24, COLOR_TEXT)
	text_col.add_child(title_label)
	var helper_label := _make_label(helper, 18, COLOR_TEXT_MUTED)
	text_col.add_child(helper_label)
	row.add_child(text_col)
	return row


func _make_dashboard_metric_card(label_text: String, value_text: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 104)
	card.add_theme_stylebox_override("panel", _make_style(Color("#FFFFFF"), COLOR_BORDER, 16, true))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 32)
	value.add_theme_color_override("font_color", value_color)
	column.add_child(value)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	column.add_child(label)
	return card


## 预计结算网格内容（构建与拖放增量刷新共用）。
func _build_metrics_grid(grid: GridContainer, budget_used: int, budget_limit: int, preview: StreamSettlementResult) -> void:
	var budget_color: Color = COLOR_ACCENT if budget_used > budget_limit else COLOR_FAMILY
	grid.add_child(_make_dashboard_metric_card("演出预算", "%d / %d" % [budget_used, budget_limit], budget_color))
	if preview == null:
		grid.add_child(_make_dashboard_metric_card("预计结算", "放入行为卡后自动估算", COLOR_TEXT_MUTED))
		return
	grid.add_child(_make_dashboard_metric_card("峰值在线", "%d" % preview.peak_viewers, COLOR_TEXT))
	grid.add_child(_make_dashboard_metric_card("涨粉", "%d" % preview.fan_delta, COLOR_TEXT))
	grid.add_child(_make_dashboard_metric_card("收益", "¥%d" % preview.revenue, COLOR_TEXT))
	grid.add_child(_make_dashboard_metric_card("事故风险", "%.0f%%" % (preview.accident_probability * 100.0), COLOR_ACCENT))
	grid.add_child(_make_dashboard_metric_card("压力", "%+.0f" % preview.stress_delta, COLOR_TEXT_SECONDARY))
	grid.add_child(_make_dashboard_metric_card("EXP", "+%d" % preview.streamer_exp_gain, COLOR_OK))


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_style(bg_color: Color, border_color: Color, radius: int, with_shadow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border_color != Color.TRANSPARENT:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = border_color
	if with_shadow:
		style.shadow_color = Color(0.18, 0.22, 0.32, 0.10)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 3)
	return style


func _apply_primary_button_style(button: Button) -> void:
	var normal := _make_style(COLOR_ACCENT, COLOR_ACCENT_HOVER, 18, true)
	var hover := _make_style(Color("#F05D7E"), COLOR_ACCENT_HOVER, 18, true)
	var pressed := _make_style(COLOR_ACCENT_HOVER, Color("#A52448"), 18)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 26)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _find_neighbor_behavior(slots: Array, origin_index: int, direction: int) -> BehaviorCardResource:
	var index: int = origin_index + direction
	while index >= 0 and index < slots.size():
		var card: BehaviorCardResource = _card_library_manager.get_card(StringName(str(slots[index]))) as BehaviorCardResource
		if card != null:
			return card
		index += direction
	return null


func _update_footer(step: int) -> void:
	back_button.visible = step > 0
	back_button.disabled = step <= 0 or _manager.is_broadcast_pending()
	next_button.visible = step < 2
	next_button.disabled = not _manager.can_advance(step)
	footer_status.text = _manager.get_validation_message(step)


# ---------------------------------------------------------------- 直播流程

func _enter_entrance(plan: StreamPlanSnapshot) -> void:
	_state = AppState.ENTRANCE
	_live_plan = plan
	_live_result = _manager.get_pending_result()
	_live_show.clear()
	_generation_failed = false
	wizard_root.visible = false
	live_root.visible = true
	stream_chat.clear()
	live_title.text = plan.title
	stream_stage.set_elapsed_text("00:00")
	var viewer_count: int = _live_result.peak_viewers if _live_result != null else 0
	live_viewers.text = "%d 人在线" % viewer_count
	fast_button.text = "快进"
	_set_playback_controls_enabled(false)
	_update_channel_info()
	var room_theme: StreamRoomThemeResource = _manager.get_room_theme()
	var persona: StreamPersonaResource = _manager.get_persona(plan.persona_id)
	if stream_stage != null:
		stream_stage.viewers_target = viewer_count
		stream_stage.setup_persona(persona)
		stream_stage.apply_room_theme(room_theme)
		stream_stage.show_resting()
	entrance_overlay.play(room_theme.entrance_video if room_theme != null else null)

	_generator = LIVE_SHOW_GENERATOR_SCRIPT.new()
	add_child(_generator)
	_generator.setup(
		plan,
		_live_result,
		_card_library_manager.get_catalog(),
		stream_stage.get_model_resource()
	)
	_generator.show_ready.connect(_on_show_ready)
	_generator.generation_failed.connect(_on_generation_failed)
	_generator.title_ready.connect(_on_stream_title_ready)
	_generator.generate()


## Playtest / 调试：跳过向导与 LLM，直接播放注入的 DSL。
func play_test_show(dsl_text: String, plan: StreamPlanSnapshot = null, result: StreamSettlementResult = null) -> bool:
	_cleanup_live_session()
	_live_plan = plan if plan != null else _make_demo_plan()
	_live_result = result if result != null else _make_demo_result(_live_plan)
	_state = AppState.ENTRANCE
	_live_show.clear()
	wizard_root.visible = false
	live_root.visible = true
	settlement_panel.visible = false
	stream_chat.clear()
	live_title.text = _live_plan.title
	stream_stage.set_elapsed_text("00:00")
	var viewer_count: int = _live_result.peak_viewers
	live_viewers.text = "%d 人在线" % viewer_count
	fast_button.text = "快进"
	_set_playback_controls_enabled(false)
	_update_channel_info()
	var room_theme: StreamRoomThemeResource = (
		_manager.get_room_theme() if _manager != null else null
	)
	var persona: StreamPersonaResource = (
		_manager.get_persona(_live_plan.persona_id)
		if _manager != null
		else null
	)
	if stream_stage != null:
		stream_stage.viewers_target = viewer_count
		stream_stage.setup_persona(persona)
		stream_stage.apply_room_theme(room_theme)
		stream_stage.show_resting()
	entrance_overlay.play(room_theme.entrance_video if room_theme != null else null)

	_generator = LIVE_SHOW_GENERATOR_SCRIPT.new()
	add_child(_generator)
	_generator.setup(
		_live_plan,
		_live_result,
		_card_library_manager.get_catalog() if _card_library_manager != null else null,
		stream_stage.get_model_resource()
	)
	var compiled: Dictionary = _generator.compile_dsl(dsl_text, _live_plan.title)
	if not bool(compiled.get("success", false)):
		push_error("play_test_show compile failed: %s" % str(compiled.get("errors", [])))
		return false
	_on_show_ready(compiled.get("show", {}))
	return true


func _on_show_ready(show_data: Dictionary) -> void:
	_generation_failed = false
	_live_show = show_data
	if _state == AppState.LIVE and not stream_stage.is_playing():
		_begin_live_performance()


func _on_generation_failed(reason: String) -> void:
	push_warning("LiveShowGenerator failed: %s" % reason)
	_generation_failed = true
	if _state == AppState.LIVE:
		stream_chat.push_system("直播连接中断，请检查网络后重试。")
	fast_button.disabled = true
	skip_button.disabled = true


## 标题中途生成完成：刷新直播间标题（策划案 §10.2 第 1 步）。
func _on_stream_title_ready(title: String) -> void:
	live_title.text = title


func _on_entrance_finished() -> void:
	if _state != AppState.ENTRANCE:
		return
	_state = AppState.LIVE
	_set_playback_controls_enabled(false)
	_live_elapsed = 0.0
	if stream_stage != null:
		stream_stage.show_resting()
	if _generation_failed:
		stream_chat.push_system("直播连接中断，请检查网络后重试。")
		return
	stream_chat.push_system("直播开始了")
	if not _live_show.is_empty() and not stream_stage.is_playing():
		_begin_live_performance()


func _begin_live_performance() -> void:
	if _live_show.is_empty() or stream_stage == null or stream_stage.is_playing():
		return
	if not stream_stage.play_show(_live_show, _live_plan.rng_seed if _live_plan != null else 1):
		_set_playback_controls_enabled(false)
		push_error("Live show playback failed")
		stream_chat.push_system("直播内容无法播放，请重新开播。")
		return
	_set_playback_controls_enabled(true)


func _set_playback_controls_enabled(enabled: bool) -> void:
	fast_button.disabled = not enabled
	skip_button.disabled = not enabled


func _on_live_chat_event(event: Dictionary) -> void:
	stream_chat.handle_live_chat_event(event)


func _on_fast_pressed() -> void:
	var enabled: bool = fast_button.text == "快进"
	stream_stage.set_fast_forward(enabled)
	fast_button.text = "原速" if enabled else "快进"


func _on_skip_pressed() -> void:
	stream_stage.skip()


func _on_show_finished() -> void:
	if _state == AppState.SETTLEMENT:
		return
	_state = AppState.SETTLEMENT
	AudioManager.play_sfx_key("stream_end")
	fast_button.disabled = true
	skip_button.disabled = true
	if stream_stage != null:
		stream_stage.show_resting()
	await get_tree().create_timer(POST_STREAM_REST_SECONDS).timeout
	if _state != AppState.SETTLEMENT or _live_result == null:
		return
	settlement_panel.show_result(_live_plan, _live_result)


## 下播舆情（策划 §7.5）：4 个选项影响压力与粉丝构成。数值为基准，待测试。
func _on_crisis_choice_made(choice_id: String) -> void:
	match choice_id:
		"respond":
			GameState.adjust_attribute(GameState.ATTR_STRESS, 6)
			_shift_fan_vector({"b": -2.0, "r": 2.0})
		"cold":
			GameState.adjust_attribute(GameState.ATTR_STRESS, 2)
			_shift_fan_vector({"b": 1.0})
		"ignore":
			GameState.adjust_attribute(GameState.ATTR_STRESS, -2)
			_shift_fan_vector({"b": 3.0})
		"apologize":
			GameState.adjust_attribute(GameState.ATTR_STRESS, 8)
			_shift_fan_vector({"b": -4.0, "r": -2.0})


func _shift_fan_vector(delta: Dictionary) -> void:
	var vector: Dictionary = (
		_live_result.resulting_fan_vector.duplicate(true)
		if _live_result != null and not _live_result.resulting_fan_vector.is_empty()
		else GameState.fan_vector.duplicate(true)
	)
	for key: String in delta:
		vector[key] = maxf(float(vector.get(key, 0.0)) + float(delta[key]), 0.0)
	if _live_result != null:
		_live_result.resulting_fan_vector = vector
	else:
		GameState.set_fan_vector(vector)


func _on_settlement_finish() -> void:
	if _live_plan != null and _manager != null and _manager.has_method("commit_broadcast"):
		# playtest 假 session 可能未 pending，忽略失败
		_manager.commit_broadcast(_live_plan.session_id)
	_cleanup_live_session()
	if _manager != null and _manager.has_method("reset_draft"):
		_manager.reset_draft()
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null:
		app_manager.close_app(OBS_APP_ID)


func _cleanup_live_session() -> void:
	if _generator != null:
		_generator.queue_free()
		_generator = null
	_live_plan = null
	_live_result = null
	_live_show.clear()
	_generation_failed = false
	_state = AppState.WIZARD
	live_root.visible = false
	settlement_panel.visible = false
	wizard_root.visible = true


func _make_demo_plan() -> StreamPlanSnapshot:
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"playtest_live_show"
	plan.title = "【验收】直播 DSL 放映"
	plan.rng_seed = 20260807
	plan.state_snapshot = {
		"stress": 40,
		"otaku_desire": 55,
		"loneliness": 30,
		"fans": 1200,
	}
	var active_persona: StreamPersonaResource = _manager.get_active_persona() if _manager != null else null
	if active_persona != null:
		plan.persona_id = active_persona.content_id
	return plan


func _make_demo_result(plan: StreamPlanSnapshot) -> StreamSettlementResult:
	var result := StreamSettlementResult.new()
	result.session_id = plan.session_id
	result.peak_viewers = 800
	result.fan_delta = 12
	result.revenue = 320
	result.sponsor_payout = 80
	result.sponsor_satisfied = true
	result.accident_occurred = false
	result.stress_delta = -2
	result.streamer_exp_gain = 18
	result.resulting_fan_vector = {
		"r": 58.0,
		"m": 18.0,
		"w": 12.0,
		"c": 10.0,
		"b": 2.0,
	}
	result.axes = {"hook": 1.0, "quality": 0.8, "impact": 0.6, "risk": 0.1}
	return result


# ---------------------------------------------------------------- 事件回调

func _on_material_selected(material_instance_id: StringName) -> void:
	_manager.select_material(material_instance_id)


func _on_behavior_card_selected(card_id: StringName) -> void:
	_manager.select_behavior_card(card_id)


func _on_behavior_slot_clear(slot_index: int) -> void:
	_manager.clear_behavior_slot(slot_index)


func _on_modifier_card_selected(card_id: StringName) -> void:
	_manager.select_modifier_card(card_id)


func _on_modifier_slot_clear(slot_index: int) -> void:
	_manager.clear_modifier_slot(slot_index)


func _on_back_pressed() -> void:
	_manager.previous_step()


func _on_next_pressed() -> void:
	_manager.advance_step()


func _on_tab_pressed(step: int) -> void:
	_manager.goto_step(step)


func _on_confirm_broadcast() -> void:
	var plan: StreamPlanSnapshot = _manager.request_broadcast()
	if plan == null:
		footer_status.text = _manager.get_validation_message(2)
		return
	_enter_entrance(plan)


func _on_manager_step_changed(step: int) -> void:
	_max_step_reached = maxi(_max_step_reached, step)
	_render()


func _on_manager_draft_changed(_draft: Dictionary) -> void:
	if _suppress_render:
		# 拖放路径已由增量更新同步 UI，跳过全量重建。
		_suppress_render = false
		return
	_render()


func _on_catalogs_changed() -> void:
	_render()
