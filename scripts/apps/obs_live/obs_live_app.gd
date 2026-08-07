extends Control
## V-Stream 直播姬：开播向导（纯卡牌操作台，无左侧静态预监）→ 入场 → 演出 → 结算。
## Step0 左右分栏；Step1 主区+右侧预计结算面板；Step2 确认单。

const CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/live_stream_card.tscn")
const CONTENT_CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/content_card.tscn")
const DROP_SLOT_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/card_drop_slot.tscn")
const DRAG_CONTROLLER_SCENE: PackedScene = preload("res://scenes/ui/cards/card_drag_controller.tscn")
const DECK_SCENE: PackedScene = preload("res://scenes/ui/cards/card_deck.tscn")

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
const VIEWERS_START_RATIO: float = 0.05

@onready var wizard_root: VBoxContainer = %WizardRoot
@onready var wizard_tab_bar: WizardTabBar = %WizardTabBar
@onready var brand_status: Label = %BrandStatus
@onready var desk_host: Control = %DeskHost
@onready var footer_status: Label = %FooterStatus
@onready var back_button: Button = %BackButton
@onready var next_button: Button = %NextButton
@onready var live_root: Control = %LiveRoot
@onready var live_title: Label = %LiveTitle
@onready var live_viewers: Label = %LiveViewers
@onready var live_clock: Label = %LiveClock
@onready var fast_button: Button = %FastButton
@onready var skip_button: Button = %SkipButton
@onready var stream_stage: StreamStage = %StreamStage
@onready var stream_chat: StreamChat = %StreamChat
@onready var entrance_overlay: EntranceOverlay = %EntranceOverlay
@onready var settlement_panel: SettlementPanel = %SettlementPanel

var _manager: Node = null
var _card_library_manager: Node = null
var _state: int = AppState.WIZARD
var _max_step_reached: int = 0
var _title_edit: LineEdit = null
var _director: StreamShowDirector = null
var _live_plan: StreamPlanSnapshot = null
var _live_result: StreamSettlementResult = null
var _live_elapsed: float = 0.0
var _live_viewers: float = 0.0
var _drag_controller: CardDragController = null
var _deck: CardDeck = null


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
	_apply_primary_button_style(next_button)
	if _manager == null or _card_library_manager == null:
		_render_manager_error()
		return
	_manager.step_changed.connect(_on_manager_step_changed)
	_manager.draft_changed.connect(_on_manager_draft_changed)
	_manager.catalogs_changed.connect(_on_catalogs_changed)
	_card_library_manager.library_changed.connect(_on_catalogs_changed)
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
	live_clock.text = "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
	_live_viewers = lerpf(_live_viewers, float(_live_result.peak_viewers), minf(delta * 0.6, 1.0))
	live_viewers.text = "%d 人在线" % int(round(_live_viewers))


# ---------------------------------------------------------------- 向导

func _render() -> void:
	if _manager == null or _state != AppState.WIZARD:
		return
	_clear_desk()
	_title_edit = null
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
	var persona: StreamPersonaResource = _manager.get_persona()
	var material: LiveStreamMaterialResource = _manager.get_material_definition()
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

	left_body.add_child(_make_desk_heading("1", "直播间标题", "观众进入直播间前最先看到的一句话"))
	_title_edit = LineEdit.new()
	_title_edit.custom_minimum_size = Vector2(0, 48)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.max_length = 48
	_title_edit.placeholder_text = "例如：第一次开播，先从自我介绍开始"
	_title_edit.text = str(draft.get("title", ""))
	_title_edit.text_changed.connect(_on_title_changed)
	left_body.add_child(_title_edit)

	left_body.add_child(_make_desk_heading("2", "槽位装载", "从右侧卡库拖入，或点击卡牌直接装载"))
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 20)
	slot_row.custom_minimum_size.y = CardDisplayMetrics.FULL_SIZE.y
	slot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_body.add_child(slot_row)

	var persona_slot: CardDropSlot = DROP_SLOT_SCENE.instantiate()
	var persona_kinds: Array[String] = ["persona"]
	persona_slot.setup("persona", persona_kinds, "人设槽\n拖入人设卡")
	persona_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	persona_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot_row.add_child(persona_slot)
	_register_slot(persona_slot)
	if persona != null:
		var stage_persona: ContentCard = _make_persona_card(persona, true, false)
		_bind_card(stage_persona)
		persona_slot.set_content(stage_persona)

	var material_slot: CardDropSlot = DROP_SLOT_SCENE.instantiate()
	var material_kinds: Array[String] = ["material"]
	material_slot.setup("material", material_kinds, "素材槽\n拖入素材卡")
	material_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	material_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot_row.add_child(material_slot)
	_register_slot(material_slot)
	if material != null:
		var stage_material: ContentCard = _make_material_card(material, material_instance, true, false)
		_bind_card(stage_material)
		material_slot.set_content(stage_material)

	var right_panel := _make_desk_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 3.0
	split.add_child(right_panel)
	var right_body: VBoxContainer = right_panel.get_meta("body")
	right_body.add_theme_constant_override("separation", 10)
	right_body.add_child(_make_label("人设与素材库", 24, COLOR_FAMILY))
	right_body.add_child(_make_label("点击或拖到左侧槽位", 18, COLOR_TEXT_MUTED))

	var scroll := _make_card_library_scroll()
	right_body.add_child(scroll)
	var deck := _populate_card_deck(["persona", "material"])
	scroll.add_child(deck)

	var selected_material: String = str(draft.get("material_instance_id", ""))
	for persona_res: StreamPersonaResource in _manager.get_personas():
		var is_selected: bool = persona != null and persona_res.content_id == persona.content_id
		var persona_card: ContentCard = _make_persona_card(persona_res, is_selected, true)
		persona_card.pressed.connect(_on_persona_selected.bind(persona_res.content_id))
		_bind_card(persona_card)
		deck.add_card(persona_card)
	for instance: Dictionary in _manager.get_material_instances():
		var instance_id := StringName(str(instance.get("instance_id", "")))
		var instance_material: LiveStreamMaterialResource = _manager.get_material_definition(instance_id)
		if instance_material == null:
			continue
		var material_card: ContentCard = _make_material_card(
			instance_material, instance, String(instance_id) == selected_material, true
		)
		material_card.pressed.connect(_on_material_selected.bind(instance_id))
		_bind_card(material_card)
		deck.add_card(material_card)


func _make_persona_card(persona: StreamPersonaResource, selected: bool, draggable: bool) -> ContentCard:
	var card: ContentCard = CONTENT_CARD_SCENE.instantiate()
	card.configure(
		persona.display_name,
		"人设卡",
		persona.icon,
		[persona.description],
		{"kind": "persona", "id": String(persona.content_id), "title": persona.display_name},
		selected,
		"形象",
		"本场出镜"
	)
	card.drag_enabled = draggable
	return card


func _make_material_card(material: LiveStreamMaterialResource, instance: Dictionary, selected: bool, draggable: bool) -> ContentCard:
	var card: ContentCard = CONTENT_CARD_SCENE.instantiate()
	var instance_id := StringName(str(instance.get("instance_id", "")))
	var material_progress: int = int(instance.get("progress", 0))
	var info_lines: Array[String] = [
		"含量 %.0f　·　新鲜度 %d%%" % [float(instance.get("depth", 0.0)), int(round(float(instance.get("freshness", 1.0)) * 100.0))],
		"进度 %d/%d" % [material_progress, material.max_progress],
		"节目 %d 槽　·　锁定 %d 张" % [material.program_slot_count, material.get_locked_cards_for_progress(material_progress).size()],
	]
	card.configure(
		material.display_name,
		"素材 · %s" % _get_material_type_label(material.material_type),
		material.icon,
		info_lines,
		{"kind": "material", "id": String(instance_id), "title": material.display_name},
		selected,
		"槽 %d" % material.program_slot_count,
		"进度 %d/%d" % [material_progress, material.max_progress]
	)
	card.drag_enabled = draggable
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
	slot_scroll.custom_minimum_size.y = CardDisplayMetrics.FULL_SIZE.y + 16.0
	slot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_scroll.size_flags_stretch_ratio = 3.0
	slot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	top_split.add_child(slot_scroll)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 16)
	slot_scroll.add_child(slot_row)
	for slot_index: int in range(selected_slots.size()):
		slot_row.add_child(_make_program_slot(selected_slots, slot_index))

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
	metrics_grid.add_theme_constant_override("h_separation", 16)
	metrics_grid.add_theme_constant_override("v_separation", 8)
	result_body.add_child(metrics_grid)

	metrics_grid.add_child(_make_dashboard_metric("演出预算", "%d / %d" % [budget_used, budget_limit], COLOR_FAMILY))
	if preview != null:
		metrics_grid.add_child(_make_dashboard_metric("峰值在线", "%d" % preview.peak_viewers, COLOR_TEXT))
		metrics_grid.add_child(_make_dashboard_metric("涨粉", "%d" % preview.fan_delta, COLOR_TEXT))
		metrics_grid.add_child(_make_dashboard_metric("收益", "¥%d" % preview.revenue, COLOR_TEXT))
		metrics_grid.add_child(_make_dashboard_metric("事故风险", "%.0f%%" % (preview.accident_probability * 100.0), COLOR_ACCENT))
		metrics_grid.add_child(_make_dashboard_metric("压力", "%+.0f" % preview.stress_delta, COLOR_TEXT_SECONDARY))
		metrics_grid.add_child(_make_dashboard_metric("EXP", "+%d" % preview.streamer_exp_gain, COLOR_OK))
	else:
		result_body.add_child(_make_label("放入行为卡后自动估算", 16, COLOR_TEXT_MUTED))

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
	var deck := _populate_card_deck(["behavior", "modifier"])
	library_scroll.add_child(deck)
	_add_hand_cards(compatible_cards, selected_slots, false, &"behavior")

	if selected_modifiers.size() > 0:
		var modifiers: Array[LiveStreamCardResource] = []
		for modifier: ModifierCardResource in _card_library_manager.get_modifier_cards():
			modifiers.append(modifier)
		_add_hand_cards(modifiers, selected_modifiers, false, &"modifier")


func _make_program_slot(slots: Array, slot_index: int) -> CardDropSlot:
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
	if card == null:
		return slot
	var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
	card_view.configure(card, true, slot_locked)
	var behavior: BehaviorCardResource = card as BehaviorCardResource
	var left_connected: Array[int] = []
	var right_connected: Array[int] = []
	var fill_ratio: float = 1.0 if behavior != null and behavior.is_opening_card() else 0.0
	if behavior != null and slot_index > 0:
		var previous_card: BehaviorCardResource = _find_neighbor_behavior(slots, slot_index, -1)
		if previous_card != null:
			left_connected = BehaviorCardResource.intersect_slots(previous_card.right_slots, behavior.left_slots)
			fill_ratio = behavior.get_fill_ratio(previous_card.right_slots)
		else:
			left_connected.assign(behavior.left_slots)
			fill_ratio = 1.0
	if behavior != null and slot_index + 1 < slots.size():
		var next_card: BehaviorCardResource = _find_neighbor_behavior(slots, slot_index, 1)
		if next_card != null:
			right_connected = BehaviorCardResource.intersect_slots(behavior.right_slots, next_card.left_slots)
		else:
			right_connected.assign(behavior.right_slots)
	card_view.configure_connection_state(left_connected, right_connected)
	if not slot_locked:
		card_view.drag_payload = {
			"kind": "program_card",
			"card_id": card_id,
			"from_slot": slot_index,
			"title": card.display_name,
		}
		card_view.pressed.connect(_on_behavior_slot_clear.bind(slot_index))
	_bind_card(card_view)
	slot.set_content(card_view)
	return slot


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
	if card != null:
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, true)
		card_view.pressed.connect(_on_modifier_slot_clear.bind(modifier_index))
		_bind_card(card_view)
		slot.set_content(card_view)
	return slot


func _build_confirm_step() -> void:
	var draft: Dictionary = _manager.get_draft()
	var persona: StreamPersonaResource = _manager.get_persona()
	var material: LiveStreamMaterialResource = _manager.get_material_definition()
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
		"人设　%s　×　素材　%s" % [
			persona.display_name if persona != null else "—",
			material.display_name if material != null else "—"
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
		var is_locked: bool = force_locked or not _card_library_manager.is_card_unlocked(card.content_id)
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, String(card.content_id) in selected_ids, is_locked)
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


func _bind_card(card: Control) -> void:
	if _drag_controller == null or card == null:
		return
	_drag_controller.bind_card(card)


func _register_slot(slot: CardSlot) -> void:
	if _drag_controller == null or slot == null:
		return
	_drag_controller.register_container(slot)


func _on_card_move_committed(_card: Control, payload: Dictionary, _source: Node, target: Node) -> void:
	if _manager == null or not (target is CardSlot):
		return
	var slot := target as CardSlot
	var kind: String = String(payload.get("kind", ""))
	var ok: bool = false
	match kind:
		"persona":
			ok = bool(_manager.select_persona(StringName(str(payload.get("id", "")))))
		"material":
			ok = bool(_manager.select_material(StringName(str(payload.get("id", "")))))
		"behavior":
			ok = bool(_manager.place_behavior_card_at(StringName(str(payload.get("card_id", ""))), int(slot.slot_key)))
		"program_card":
			var from_slot: int = int(payload.get("from_slot", -1))
			var to_slot: int = int(slot.slot_key)
			if from_slot == to_slot:
				return
			var slots: Array = _manager.get_draft().get("behavior_slots", [])
			if to_slot < slots.size() and str(slots[to_slot]).is_empty():
				ok = bool(_manager.move_behavior_card(from_slot, to_slot))
			else:
				ok = bool(_manager.place_behavior_card_at(StringName(str(payload.get("card_id", ""))), to_slot))
		"modifier":
			ok = bool(_manager.select_modifier_card(StringName(str(payload.get("card_id", "")))))
	if not ok:
		_render()


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


func _make_dashboard_metric(label_text: String, value_text: String, value_color: Color) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	col.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 24)
	value.add_theme_color_override("font_color", value_color)
	col.add_child(value)
	return col


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


func _get_material_type_label(material_type: StringName) -> String:
	match material_type:
		LiveStreamMaterialResource.TYPE_CONSUMABLE:
			return "消耗型"
		LiveStreamMaterialResource.TYPE_SPONSOR:
			return "商单型"
	return "连续型"


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
	wizard_root.visible = false
	live_root.visible = true
	live_title.text = plan.title
	live_clock.text = "00:00"
	_live_viewers = float(_live_result.peak_viewers) * VIEWERS_START_RATIO if _live_result != null else 0.0
	live_viewers.text = "%d 人在线" % int(round(_live_viewers))
	fast_button.text = "快进"
	fast_button.disabled = false
	skip_button.disabled = false
	entrance_overlay.play(plan.title)

	_director = StreamShowDirector.new()
	add_child(_director)
	_director.setup(plan, _live_result, _card_library_manager.get_catalog())
	_director.first_beat_resolved.connect(entrance_overlay.set_ready)
	_director.beat_started.connect(_on_live_beat_started)
	_director.show_finished.connect(_on_show_finished)
	_director.start()


func _on_entrance_finished() -> void:
	if _state != AppState.ENTRANCE:
		return
	_state = AppState.LIVE
	_live_elapsed = 0.0
	stream_chat.start_ambient(_director.get_axis_hint(), _live_plan.rng_seed if _live_plan != null else 1)
	stream_chat.push_system("直播开始了")


func _on_live_beat_started(beat: Dictionary) -> void:
	stream_stage.show_beat(beat)
	stream_chat.push_entries(beat.get("danmaku", []))


func _on_fast_pressed() -> void:
	if _director == null:
		return
	var enabled: bool = fast_button.text == "快进"
	_director.set_fast_forward(enabled)
	fast_button.text = "原速" if enabled else "快进"


func _on_skip_pressed() -> void:
	if _director != null:
		_director.skip()


func _on_show_finished() -> void:
	if _state == AppState.SETTLEMENT:
		return
	_state = AppState.SETTLEMENT
	stream_chat.stop_ambient()
	fast_button.disabled = true
	skip_button.disabled = true
	settlement_panel.show_result(_live_plan, _live_result)


func _on_settlement_finish() -> void:
	if _live_plan != null:
		_manager.commit_broadcast(_live_plan.session_id)
	_cleanup_live_session()
	_manager.reset_draft()
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null:
		app_manager.close_app(OBS_APP_ID)


func _cleanup_live_session() -> void:
	if _director != null:
		_director.queue_free()
		_director = null
	_live_plan = null
	_live_result = null
	_state = AppState.WIZARD
	live_root.visible = false
	settlement_panel.visible = false
	wizard_root.visible = true


# ---------------------------------------------------------------- 事件回调

func _on_title_changed(value: String) -> void:
	_manager.set_title(value)
	_update_footer(int(_manager.get_current_step()))


func _on_persona_selected(persona_id: StringName) -> void:
	_manager.select_persona(persona_id)


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
	if _title_edit != null and is_instance_valid(_title_edit) and _title_edit.has_focus():
		_update_footer(int(_manager.get_current_step()))
		return
	_render()


func _on_catalogs_changed() -> void:
	_render()
