extends Control
## V-Stream 直播姬：选素材 → 选临时直播构思 → 确认开播 → 演出 → LinkPosta。

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

enum AppState { WIZARD, ENTRANCE, LIVE, FINISHING }

const OBS_APP_ID: String = "obs_live"
const POST_STREAM_REST_SECONDS: float = 1.0
const SKILL_FAMILY_LABELS: Dictionary = {
	"game": "游戏",
	"talk": "杂谈",
	"song": "歌唱",
	"act": "演出",
	"tech": "杂项",
}

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

func _ready() -> void:
	_manager = get_node_or_null("/root/LiveStreamManager")
	_setup_drag_system()
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	wizard_tab_bar.tab_pressed.connect(_on_tab_pressed)
	fast_button.pressed.connect(_on_fast_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	entrance_overlay.entrance_finished.connect(_on_entrance_finished)
	stream_stage.show_finished.connect(_on_show_finished)
	stream_stage.live_chat_event.connect(_on_live_chat_event)
	stream_chat.screen_chat_toggled.connect(_on_screen_chat_toggled)
	stream_chat.donation_animation_toggled.connect(_on_donation_animation_toggled)
	_apply_live_reaction_preferences()
	_apply_primary_button_style(next_button)
	if _manager == null:
		_render_manager_error()
		return
	_manager.step_changed.connect(_on_manager_step_changed)
	_manager.draft_changed.connect(_on_manager_draft_changed)
	_manager.catalogs_changed.connect(_on_catalogs_changed)
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
	if persona == null and _manager != null and _manager.has_method("get_catalog"):
		var catalog = _manager.get_catalog()
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

	left_body.add_child(_make_desk_heading("1", "本场标题", "开播后会按素材和选定构思自然拟定"))
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

	left_body.add_child(_make_desk_heading("3", "选择素材", "选一份今晚想播的内容"))
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
	var tooltip: String = "一次性素材 · 播一场消耗一份\n%s" % material_resource.description
	var skill_rewards: String = _format_skill_exp_rewards(material_resource.skill_exp_rewards)
	if not skill_rewards.is_empty():
		tooltip += "\n熟练度：%s" % skill_rewards
	card.configure(
		material_resource,
		selected,
		false,
		material_resource.get_material_type_label(),
		"一次性",
		tooltip
	)
	if draggable:
		card.drag_payload = {
			"kind": "material",
			"id": String(instance_id),
			"title": material_resource.display_name,
		}
	return card


func _format_skill_exp_rewards(rewards: StreamSkillExperience) -> String:
	if rewards == null:
		return ""
	var parts: Array[String] = []
	for family: StringName in GameState.SKILL_FAMILIES:
		var amount: int = rewards.get_value(family)
		if amount > 0:
			parts.append("%s +%d" % [SKILL_FAMILY_LABELS.get(String(family), String(family)), amount])
	return " · ".join(parts)


func _build_script_step() -> void:
	var draft: Dictionary = _manager.get_draft()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_attach_desk_root(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	scroll.add_child(body)
	body.add_child(_make_desk_heading("2", "今晚怎么播", "从她整理出的构思里选一个"))
	var material: LiveStreamMaterialResource = _manager.get_material_definition()
	if material != null:
		body.add_child(_make_label("素材　%s" % material.display_name, 22, COLOR_TEXT_SECONDARY))
	var approach_state: String = str(draft.get("approach_state", "idle"))
	var approaches: Array[Dictionary] = _manager.get_approaches()
	if approaches.is_empty():
		var waiting_panel := _make_desk_panel(COLOR_SURFACE_ALT)
		waiting_panel.custom_minimum_size.y = 180
		body.add_child(waiting_panel)
		var waiting_body: VBoxContainer = waiting_panel.get_meta("body")
		waiting_body.alignment = BoxContainer.ALIGNMENT_CENTER
		waiting_body.add_child(_make_label("她正在整理今晚从哪里讲起……", 25, COLOR_TEXT))
		waiting_body.add_child(_make_label("先把素材翻一翻，很快就好。", 19, COLOR_TEXT_MUTED))
		return
	var selected_id: String = str(draft.get("selected_approach_id", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	for approach: Dictionary in approaches:
		row.add_child(_make_approach_choice(approach, str(approach.get("approach_id", "")) == selected_id))


func _make_approach_choice(approach: Dictionary, selected: bool) -> Button:
	var approach_type := StringName(str(approach.get("approach_type", "")))
	var profile: Dictionary = LiveStreamBalance.new().get_approach_profile(approach_type)
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 260)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s\n\n%s\n\n%s" % [
		str(approach.get("display_name", "")),
		str(approach.get("display_description", "")),
		str(profile.get("player_hint", "")),
	]
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT)
	var base_color: Color = Color("#FFF0F4") if selected else COLOR_SURFACE
	var border_color: Color = COLOR_ACCENT if selected else COLOR_BORDER
	button.add_theme_stylebox_override("normal", _make_style(base_color, border_color, 16, selected))
	button.add_theme_stylebox_override("hover", _make_style(Color("#FFF6F8"), COLOR_ACCENT, 16, true))
	button.add_theme_stylebox_override("pressed", _make_style(Color("#FFE8EF"), COLOR_ACCENT_HOVER, 16))
	button.add_theme_stylebox_override("focus", _make_style(base_color, COLOR_ACCENT, 16))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_approach_selected.bind(approach_type, StringName(str(approach.get("approach_id", "")))))
	return button


func _build_confirm_step() -> void:
	var draft: Dictionary = _manager.get_draft()
	var persona: StreamPersonaResource = _manager.get_active_persona()
	var selected_material: LiveStreamMaterialResource = _manager.get_material_definition()
	var selected_approach: Dictionary = _manager.get_selected_approach()

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

	var approach_panel := _make_desk_panel(Color("#FFF6F8"))
	body.add_child(approach_panel)
	var approach_body: VBoxContainer = approach_panel.get_meta("body")
	approach_body.add_child(_make_label("直播构思", 20, COLOR_ACCENT))
	approach_body.add_child(_make_label(
		str(selected_approach.get("display_name", "—")), 26, COLOR_TEXT
	))
	approach_body.add_child(_make_label(
		str(selected_approach.get("display_description", "")), 20, COLOR_TEXT_SECONDARY
	))

	var preview: StreamSettlementResult = _manager.get_preview_result()
	var preview_panel := _make_desk_panel(COLOR_SURFACE_ALT)
	body.add_child(preview_panel)
	var preview_body: VBoxContainer = preview_panel.get_meta("body")
	preview_body.add_child(_make_label("预结算", 24, COLOR_FAMILY))
	preview_body.add_child(_make_label(
		"峰值在线 %d　·　涨粉 %d　·　收益 ¥%d" % [
			preview.peak_viewers if preview != null else 0,
			preview.fan_delta if preview != null else 0,
			preview.revenue if preview != null else 0,
		],
		24,
		COLOR_TEXT
	))
	if preview != null:
		preview_body.add_child(_make_label(
			"压力 %+.0f　·　熟练度 +%d" % [preview.stress_delta, preview.streamer_exp_gain],
			20,
			COLOR_TEXT_MUTED
		))

	var confirm_button := Button.new()
	confirm_button.custom_minimum_size = Vector2(520, 80)
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_button.text = "直播已提交" if _manager.is_broadcast_pending() else "确认开播（占用 1 时段）"
	confirm_button.disabled = _manager.is_broadcast_pending()
	_apply_primary_button_style(confirm_button)
	confirm_button.pressed.connect(_on_confirm_broadcast)
	body.add_child(confirm_button)


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
	if not target is CardSlot or String(payload.get("kind", "")) != "material":
		_render()
		return
	_manager.select_material(StringName(str(payload.get("id", ""))))


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
		_manager.get_catalog(),
		stream_stage.get_model_resource()
	)
	_generator.show_ready.connect(_on_show_ready)
	_generator.generation_failed.connect(_on_generation_failed)
	_generator.title_ready.connect(_on_stream_title_ready)
	_generator.summary_ready.connect(_on_stream_summary_ready)
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
		_manager.get_catalog() if _manager != null else null,
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
	if _manager != null and _manager.has_method("prefetch_stream_post"):
		_manager.prefetch_stream_post(_live_plan, show_data)
	if _state == AppState.LIVE and not stream_stage.is_playing():
		_begin_live_performance()


func _on_stream_summary_ready(session_id: StringName, summary: String) -> void:
	if summary.is_empty() or _manager == null or not _manager.has_method("set_pending_stream_summary"):
		return
	_manager.set_pending_stream_summary(session_id, summary)


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


func _apply_live_reaction_preferences() -> void:
	var screen_chat_enabled: bool = PlayerConfig.is_screen_chat_enabled()
	var donation_animation_enabled: bool = PlayerConfig.is_donation_animation_enabled()
	stream_stage.set_screen_chat_enabled(screen_chat_enabled)
	stream_stage.set_donation_animation_enabled(donation_animation_enabled)
	stream_chat.set_reaction_settings(screen_chat_enabled, donation_animation_enabled)


func _on_screen_chat_toggled(enabled: bool) -> void:
	stream_stage.set_screen_chat_enabled(enabled)
	var error: Error = PlayerConfig.set_screen_chat_enabled(enabled)
	if error != OK:
		push_warning("OBSLiveApp: failed to persist screen-chat preference (%s)" % error_string(error))


func _on_donation_animation_toggled(enabled: bool) -> void:
	stream_stage.set_donation_animation_enabled(enabled)
	var error: Error = PlayerConfig.set_donation_animation_enabled(enabled)
	if error != OK:
		push_warning("OBSLiveApp: failed to persist donation-animation preference (%s)" % error_string(error))


func _on_fast_pressed() -> void:
	var enabled: bool = fast_button.text == "快进"
	stream_stage.set_fast_forward(enabled)
	fast_button.text = "原速" if enabled else "快进"


func _on_skip_pressed() -> void:
	stream_stage.skip()


func _on_show_finished() -> void:
	if _state == AppState.FINISHING:
		return
	_state = AppState.FINISHING
	AudioManager.play_sfx_key("stream_end")
	fast_button.disabled = true
	skip_button.disabled = true
	if stream_stage != null:
		stream_stage.show_resting()
	await get_tree().create_timer(POST_STREAM_REST_SECONDS).timeout
	if _state != AppState.FINISHING or _live_plan == null:
		return
	var completed_session_id: StringName = _live_plan.session_id
	var needs_post_settlement: bool = (
		_manager != null and bool(_manager.call("is_broadcast_pending"))
	)
	_cleanup_live_session()
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null:
		app_manager.close_app(OBS_APP_ID)
	if needs_post_settlement and _manager.has_method("begin_post_settlement"):
		_manager.call_deferred("begin_post_settlement", completed_session_id)


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
	result.stress_delta = -2
	result.skill_exp_gains = {"talk": 18}
	result.streamer_exp_gain = 18
	result.resulting_fan_vector = {
		"r": 58.0,
		"m": 18.0,
		"w": 12.0,
		"c": 10.0,
		"b": 2.0,
	}
	result.axes = {"hook": 1.0, "quality": 0.8, "impact": 0.6}
	return result


# ---------------------------------------------------------------- 事件回调

func _on_material_selected(material_instance_id: StringName) -> void:
	_manager.select_material(material_instance_id)


func _on_approach_selected(_approach_type: StringName, approach_id: StringName) -> void:
	_manager.select_approach(approach_id)


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
	_render()


func _on_catalogs_changed() -> void:
	_render()
