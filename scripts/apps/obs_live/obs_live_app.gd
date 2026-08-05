extends Control
## V-Stream 直播姬：三步开播向导。

const CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/live_stream_card.tscn")

const COLOR_BG: Color = Color("#F7F2F7")
const COLOR_SURFACE: Color = Color("#FFFFFF")
const COLOR_SURFACE_ALT: Color = Color("#FFF5F7")
const COLOR_BORDER: Color = Color("#DCCFD9")
const COLOR_TEXT: Color = Color("#2A2030")
const COLOR_TEXT_SECONDARY: Color = Color("#776375")
const COLOR_TEXT_MUTED: Color = Color("#9A8997")
const COLOR_ACCENT: Color = Color("#E5486D")
const COLOR_ACCENT_HOVER: Color = Color("#CB3159")
const COLOR_ACCENT_SOFT: Color = Color("#FFE4EA")
const COLOR_PLUM: Color = Color("#321E30")
const COLOR_SUCCESS: Color = Color("#63C2A0")
const COLOR_SUCCESS_SOFT: Color = Color("#234A3E")

@onready var step_counter: Label = %StepCounter
@onready var content_scroll: ScrollContainer = %ContentScroll
@onready var step_content: VBoxContainer = %StepContent
@onready var footer_status: Label = %FooterStatus
@onready var back_button: Button = %BackButton
@onready var next_button: Button = %NextButton

var _manager: Node = null
var _card_library_manager: Node = null
var _step_panels: Array[PanelContainer] = []
var _step_titles: Array[Label] = []
var _step_states: Array[Label] = []
var _title_edit: LineEdit = null


func _ready() -> void:
	_step_panels = [%Step1Panel, %Step2Panel, %Step3Panel]
	_step_titles = [%Step1Title, %Step2Title, %Step3Title]
	_step_states = [%Step1State, %Step2State, %Step3State]
	_manager = get_node_or_null("/root/LiveStreamManager")
	_card_library_manager = get_node_or_null("/root/CardLibraryManager")
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	_apply_primary_button_style(next_button)
	if _manager == null or _card_library_manager == null:
		_render_manager_error()
		return
	_manager.step_changed.connect(_on_manager_step_changed)
	_manager.draft_changed.connect(_on_manager_draft_changed)
	_manager.catalogs_changed.connect(_on_catalogs_changed)
	_card_library_manager.library_changed.connect(_on_catalogs_changed)
	_render()


func _render() -> void:
	if _manager == null:
		return
	_clear_step_content()
	_title_edit = null
	var step: int = int(_manager.get_current_step())
	step_counter.text = "第 %d / 3 步" % (step + 1)
	_update_step_sidebar(step)
	match step:
		0:
			_build_setup_step()
		1:
			_build_script_step()
		2:
			_build_confirm_step()
	_update_footer(step)
	content_scroll.scroll_vertical = 0


func _clear_step_content() -> void:
	for child: Node in step_content.get_children():
		step_content.remove_child(child)
		child.queue_free()


func _render_manager_error() -> void:
	_clear_step_content()
	var title := _make_label("直播准备服务暂不可用", 38, COLOR_TEXT)
	step_content.add_child(title)
	var detail := _make_label("直播准备服务尚未载入，请重新打开应用。", 27, COLOR_TEXT_SECONDARY)
	step_content.add_child(detail)
	back_button.disabled = true
	next_button.disabled = true
	footer_status.text = "无法读取开播草稿"


func _update_step_sidebar(current_step: int) -> void:
	for index: int in range(_step_panels.size()):
		var panel: PanelContainer = _step_panels[index]
		var title: Label = _step_titles[index]
		var state: Label = _step_states[index]
		if index < current_step:
			panel.add_theme_stylebox_override("panel", _make_style(COLOR_SUCCESS_SOFT, Color("#39745F"), 18))
			title.add_theme_color_override("font_color", Color("#F2FFF9"))
			state.add_theme_color_override("font_color", COLOR_SUCCESS)
			state.text = "已完成"
		elif index == current_step:
			panel.add_theme_stylebox_override("panel", _make_style(Color("#4B2945"), Color("#9C527B"), 18, true))
			title.add_theme_color_override("font_color", Color.WHITE)
			state.add_theme_color_override("font_color", Color("#FF9EB4"))
			state.text = "当前"
		else:
			panel.add_theme_stylebox_override("panel", _make_style(Color("#392437"), Color.TRANSPARENT, 18))
			title.add_theme_color_override("font_color", Color("#D7CAD4"))
			state.add_theme_color_override("font_color", Color("#9F8B9B"))
			state.text = "待完成"


func _build_setup_step() -> void:
	_add_page_heading(
		"素材与形象",
		"确定直播标题、人设和本场使用的素材。"
	)
	var draft: Dictionary = _manager.get_draft()

	_add_section_heading("直播间标题", "标题会出现在观众进入直播间前。最多 48 个字。")
	_title_edit = LineEdit.new()
	_title_edit.custom_minimum_size = Vector2(0, 76)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.max_length = 48
	_title_edit.placeholder_text = "例如：第一次开播，先从自我介绍开始"
	_title_edit.text = str(draft.get("title", ""))
	_title_edit.text_changed.connect(_on_title_changed)
	step_content.add_child(_title_edit)

	_add_section_heading("直播人设", "当前剧情阶段使用默认人设。")
	var persona_grid := GridContainer.new()
	persona_grid.columns = 3
	persona_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	persona_grid.add_theme_constant_override("h_separation", 20)
	persona_grid.add_theme_constant_override("v_separation", 20)
	step_content.add_child(persona_grid)
	var selected_persona: String = str(draft.get("persona_id", ""))
	for persona: StreamPersonaResource in _manager.get_personas():
		var persona_button := Button.new()
		persona_button.custom_minimum_size = Vector2(320, 124)
		persona_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		persona_button.text = "%s\n%s" % [persona.display_name, persona.description]
		persona_button.tooltip_text = persona.description
		_style_choice_button(persona_button, String(persona.content_id) == selected_persona)
		persona_button.pressed.connect(_on_persona_selected.bind(persona.content_id))
		persona_grid.add_child(persona_button)

	_add_section_heading("素材实例", "同一种素材可以有多份；含量、进度和新鲜度各自结算。")
	var material_list := VBoxContainer.new()
	material_list.add_theme_constant_override("separation", 16)
	step_content.add_child(material_list)
	var selected_material: String = str(draft.get("material_instance_id", ""))
	for instance: Dictionary in _manager.get_material_instances():
		var instance_id := StringName(str(instance.get("instance_id", "")))
		var material: LiveStreamMaterialResource = _manager.get_material_definition(instance_id)
		if material == null:
			continue
		var material_button := Button.new()
		material_button.custom_minimum_size = Vector2(0, 126)
		material_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		material_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		material_button.text = "%s\n含量 %.0f　·　进度 %d/%d　·　新鲜度 %d%%　·　%s" % [
			material.display_name,
			float(instance.get("depth", 0.0)),
			int(instance.get("progress", 0)),
			material.max_progress,
			int(round(float(instance.get("freshness", 1.0)) * 100.0)),
			"消耗型" if material.material_type == LiveStreamMaterialResource.TYPE_CONSUMABLE else "连续型",
		]
		material_button.tooltip_text = material.description
		_style_choice_button(material_button, String(instance_id) == selected_material)
		material_button.pressed.connect(_on_material_selected.bind(instance_id))
		material_list.add_child(material_button)


func _build_script_step() -> void:
	_add_page_heading(
		"剧本编排",
		"按顺序排入行为卡；卡牌边缘的真实凹凸与颜色就是情绪接口。"
	)
	var draft: Dictionary = _manager.get_draft()
	var selected_slots: Array = draft.get("behavior_slots", [])
	var selected_modifiers: Array = draft.get("modifier_slots", [])

	_add_section_heading(
		"节目单 · 演出预算 %d / %d" % [_manager.get_budget_used(), _manager.get_budget_limit()],
		"第一张使用左端平齐的开场卡；右端平齐的收尾卡只能放在最后。"
	)
	var slot_row := HFlowContainer.new()
	slot_row.add_theme_constant_override("separation", 20)
	step_content.add_child(slot_row)
	for slot_index: int in range(selected_slots.size()):
		var card_id: String = str(selected_slots[slot_index]) if slot_index < selected_slots.size() else ""
		var card: LiveStreamCardResource = _card_library_manager.get_card(StringName(card_id))
		var slot_box := VBoxContainer.new()
		slot_box.custom_minimum_size.x = 440
		slot_box.add_theme_constant_override("separation", 8)
		var slot_title: String = "%02d　%s" % [slot_index + 1, "开场位" if slot_index == 0 else "节目位"]
		slot_box.add_child(_make_label(slot_title, 24, COLOR_TEXT_SECONDARY))
		if card != null:
			var selected_view: LiveStreamCardView = CARD_SCENE.instantiate()
			selected_view.configure(card, true)
			selected_view.tooltip_text = "点击移出节目单"
			selected_view.pressed.connect(_on_behavior_slot_clear.bind(slot_index))
			slot_box.add_child(selected_view)
		else:
			var empty_slot := Button.new()
			empty_slot.custom_minimum_size = Vector2(440, 300)
			empty_slot.disabled = true
			empty_slot.text = "等待安排"
			_style_slot_button(empty_slot, false)
			slot_box.add_child(empty_slot)
		slot_row.add_child(slot_box)

	var material_instance_id := StringName(str(draft.get("material_instance_id", "")))
	var compatible_cards: Array[BehaviorCardResource] = _card_library_manager.get_compatible_behavior_cards(material_instance_id, false)
	_add_card_collection("可用行为卡", compatible_cards, selected_slots, false, &"behavior")

	var incompatible_cards: Array[LiveStreamCardResource] = []
	var locked_cards: Array[LiveStreamCardResource] = []
	for behavior: BehaviorCardResource in _card_library_manager.get_behavior_cards():
		if not _card_library_manager.is_card_unlocked(behavior.content_id):
			locked_cards.append(behavior)
		elif behavior not in compatible_cards:
			incompatible_cards.append(behavior)
	_add_card_collection("素材不兼容", incompatible_cards, [], true)
	_add_card_collection("尚未解锁", locked_cards, [], true)

	if selected_modifiers.size() > 0:
		_add_section_heading("修饰槽", "修饰卡作用于整场，不参与左右情绪接缝。")
		var modifiers: Array[LiveStreamCardResource] = []
		for modifier: ModifierCardResource in _card_library_manager.get_modifier_cards():
			modifiers.append(modifier)
		_add_card_collection("可用修饰卡", modifiers, selected_modifiers, false, &"modifier")
	else:
		_add_section_heading("修饰槽", "主播 Lv.3 开放第一个修饰槽。")


func _build_confirm_step() -> void:
	_add_page_heading(
		"确认开播",
		"节目单由当前选择生成。确认后交给直播预结算与演出流程。"
	)
	var draft: Dictionary = _manager.get_draft()
	var persona: StreamPersonaResource = _manager.get_persona()
	var material: LiveStreamMaterialResource = _manager.get_material_definition()

	var summary_body: VBoxContainer = _add_surface_panel(COLOR_SURFACE)
	summary_body.add_child(_make_label("本场节目单", 34, COLOR_TEXT))
	summary_body.add_child(_make_label("标题　%s" % str(draft.get("title", "")), 29, COLOR_TEXT))
	summary_body.add_child(_make_label(
		"人设　%s　　素材　%s" % [persona.display_name, material.display_name],
		27,
		COLOR_TEXT_SECONDARY
	))
	var slots: Array = draft.get("behavior_slots", [])
	for index: int in range(slots.size()):
		var card: LiveStreamCardResource = _card_library_manager.get_card(StringName(str(slots[index])))
		if card == null:
			continue
		var card_line := "%02d　%s　·　预算 %d　·　压力 %+.0f" % [
			index + 1,
			card.display_name,
			card.budget_cost,
			card.stress_cost,
		]
		summary_body.add_child(_make_label(card_line, 27, COLOR_TEXT))
	for modifier_id: Variant in draft.get("modifier_slots", []):
		var modifier: ModifierCardResource = _card_library_manager.get_card(StringName(str(modifier_id))) as ModifierCardResource
		if modifier != null:
			summary_body.add_child(_make_label("修饰　%s" % modifier.display_name, 27, COLOR_TEXT_SECONDARY))

	var preview: StreamSettlementResult = _manager.get_preview_result()
	var preview_body: VBoxContainer = _add_surface_panel(COLOR_SURFACE_ALT, Color("#F2BCC9"))
	preview_body.add_child(_make_label("预结算", 32, COLOR_TEXT))
	var risk: float = preview.accident_probability if preview != null else 0.0
	preview_body.add_child(_make_label(
		"预计峰值在线 %d　·　涨粉 %d　·　收益 ¥%d　·　事故风险 %.0f%%" % [
			preview.peak_viewers if preview != null else 0,
			preview.fan_delta if preview != null else 0,
			preview.revenue if preview != null else 0,
			risk * 100.0,
		],
		28,
		COLOR_TEXT
	))
	if preview != null:
		preview_body.add_child(_make_label("压力 %+.0f　·　主播 EXP +%d" % [preview.stress_delta, preview.streamer_exp_gain], 24, COLOR_TEXT_MUTED))

	var confirm_button := Button.new()
	confirm_button.custom_minimum_size = Vector2(620, 96)
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_button.text = "节目单已提交" if _manager.is_broadcast_pending() else "确认开播（占用 1 时段）"
	confirm_button.disabled = _manager.is_broadcast_pending()
	_apply_primary_button_style(confirm_button)
	confirm_button.pressed.connect(_on_confirm_broadcast)
	step_content.add_child(confirm_button)


func _add_card_collection(
	title_text: String,
	cards: Array,
	selected_ids: Array,
	force_locked: bool,
	select_kind: StringName = &""
) -> void:
	if cards.is_empty():
		return
	_add_section_heading(title_text, "%d 张" % cards.size())
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 20)
	flow.add_theme_constant_override("v_separation", 20)
	step_content.add_child(flow)
	for card_value: Variant in cards:
		var card: LiveStreamCardResource = card_value as LiveStreamCardResource
		if card == null:
			continue
		var is_locked: bool = force_locked or not _card_library_manager.is_card_unlocked(card.content_id)
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, String(card.content_id) in selected_ids, is_locked)
		if is_locked:
			card_view.tooltip_text = _card_library_manager.get_unlock_reason(card.content_id) if not _card_library_manager.is_card_unlocked(card.content_id) else "与当前素材不兼容"
		elif select_kind == &"behavior":
			card_view.pressed.connect(_on_behavior_card_selected.bind(card.content_id))
		elif select_kind == &"modifier":
			card_view.pressed.connect(_on_modifier_card_selected.bind(card.content_id))
		flow.add_child(card_view)


func _add_page_heading(title_text: String, description: String) -> void:
	var title := _make_label(title_text, 46, COLOR_TEXT)
	step_content.add_child(title)
	var subtitle := _make_label(description, 27, COLOR_TEXT_SECONDARY)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_content.add_child(subtitle)


func _add_section_heading(title_text: String, helper_text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	step_content.add_child(spacer)
	step_content.add_child(_make_label(title_text, 34, COLOR_TEXT))
	var helper := _make_label(helper_text, 24, COLOR_TEXT_SECONDARY)
	helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_content.add_child(helper)


func _add_surface_panel(bg_color: Color, border_color: Color = COLOR_BORDER) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(bg_color, border_color, 22, true))
	step_content.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	margin.add_child(body)
	return body


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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
		style.shadow_color = Color(0.18, 0.07, 0.15, 0.12)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 4)
	return style


func _style_choice_button(button: Button, selected: bool) -> void:
	var normal_style := _make_style(COLOR_ACCENT_SOFT, COLOR_ACCENT, 18, true) if selected else _make_style(COLOR_SURFACE, COLOR_BORDER, 18)
	var hover_style := _make_style(Color("#FFF0F3"), COLOR_ACCENT, 18, true)
	var pressed_style := _make_style(Color("#FAD9E2"), COLOR_ACCENT_HOVER, 18)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", hover_style)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_font_size_override("font_size", 26)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _style_slot_button(button: Button, filled: bool) -> void:
	var bg_color: Color = Color("#FFF3F6") if filled else Color("#FBF8FB")
	var border_color: Color = COLOR_ACCENT if filled else COLOR_BORDER
	button.add_theme_stylebox_override("normal", _make_style(bg_color, border_color, 18, filled))
	button.add_theme_stylebox_override("hover", _make_style(Color("#FFE8EE"), COLOR_ACCENT, 18, true))
	button.add_theme_stylebox_override("pressed", _make_style(Color("#FAD9E2"), COLOR_ACCENT_HOVER, 18))
	button.add_theme_color_override("font_color", COLOR_TEXT if filled else COLOR_TEXT_MUTED)
	button.add_theme_font_size_override("font_size", 27)
	if filled:
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _apply_primary_button_style(button: Button) -> void:
	var normal := _make_style(COLOR_ACCENT, COLOR_ACCENT_HOVER, 20, true)
	var hover := _make_style(Color("#F05D7E"), COLOR_ACCENT_HOVER, 20, true)
	var pressed := _make_style(COLOR_ACCENT_HOVER, Color("#A52448"), 20)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 29)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _risk_label(risk: float) -> String:
	if risk < 0.04:
		return "低"
	if risk < 0.10:
		return "中"
	return "高"


func _update_footer(step: int) -> void:
	back_button.visible = step > 0
	back_button.disabled = step <= 0 or _manager.is_broadcast_pending()
	next_button.visible = step < 2
	next_button.disabled = not _manager.can_advance(step)
	footer_status.text = _manager.get_validation_message(step)


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


func _on_back_pressed() -> void:
	_manager.previous_step()


func _on_next_pressed() -> void:
	_manager.advance_step()


func _on_confirm_broadcast() -> void:
	var plan: StreamPlanSnapshot = _manager.request_broadcast()
	if plan == null:
		footer_status.text = _manager.get_validation_message(2)


func _on_manager_step_changed(_step: int) -> void:
	_render()


func _on_manager_draft_changed(_draft: Dictionary) -> void:
	if _title_edit != null and is_instance_valid(_title_edit) and _title_edit.has_focus():
		_update_footer(int(_manager.get_current_step()))
		return
	_render()


func _on_catalogs_changed() -> void:
	_render()
