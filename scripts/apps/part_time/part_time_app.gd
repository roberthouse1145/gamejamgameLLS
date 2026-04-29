class_name PartTimeApp
extends Control

const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")

const COLOR_BG: Color = Color("#F5F7FA")
const COLOR_BRAND: Color = Color("#00BE6E")
const COLOR_BRAND_DARK: Color = Color("#00A862")
const COLOR_TEXT: Color = Color("#1F2329")
const COLOR_SUBTEXT: Color = Color("#6B7280")
const COLOR_PANEL: Color = Color("#FFFFFF")
const COLOR_BORDER: Color = Color("#E5E7EB")
const COLOR_SALARY: Color = Color("#0E9F6E")
const COLOR_TAG_BG: Color = Color("#E7F8F1")
const COLOR_TAG_TEXT: Color = Color("#0D9A62")
const COLOR_DISABLED: Color = Color("#D1D5DB")
const COLOR_TRANSIT_GREEN := Color("#00BE6E")
const TRANSIT_STAGES: Array[String] = [
	"订单已确认，正在呼叫车辆...",
	"司机正在赶来  预计 3 分钟",
	"已上车，前往目的地",
	"途经城市快速路",
	"预计还剩 8 分钟",
	"即将驶离快速路",
	"距目的地不足 1 公里",
	"已到达目的地附近"
]

var _part_time_manager: Node = null
var _game_manager: Node = null
var _game_loop: Node = null

var _all_jobs: Array[Dictionary] = []
var _filtered_jobs: Array[Dictionary] = []
var _selected_job_id: String = ""
var _active_session_id: String = ""
var _transit_progress: float = 0.0

var _transit_window: Control = null
var _transit_title_label: Label = null
var _transit_stage_label: Label = null
var _transit_eta_label: Label = null
var _transit_progress_bar: ProgressBar = null

var _wallet_label: Label = null
var _search_input: LineEdit = null
var _result_label: Label = null
var _job_list: VBoxContainer = null
var _detail_title: Label = null
var _detail_company: Label = null
var _detail_salary: Label = null
var _detail_meta: Label = null
var _detail_desc: Label = null
var _detail_status: Label = null
var _detail_boss: Label = null
var _tags_flow: HFlowContainer = null
var _apply_button: Button = null


func _ready() -> void:
	_part_time_manager = get_node_or_null("/root/PartTimeJobManager")
	_game_manager = get_node_or_null("/root/GameManager")
	_game_loop = get_node_or_null("/root/GameLoopManager")
	_build_ui()
	_connect_signals()
	_reload_jobs()
	_update_wallet()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_body())


func _build_header() -> Control:
	var header_bg := ColorRect.new()
	header_bg.color = COLOR_BRAND
	header_bg.custom_minimum_size = Vector2(0, 108)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 16)
	header_bg.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	margin.add_child(hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	hbox.add_child(left)

	var brand := Label.new()
	brand.text = "BOSS直兼"
	brand.add_theme_font_size_override("font_size", 30)
	brand.add_theme_color_override("font_color", Color.WHITE)
	left.add_child(brand)

	var subtitle := Label.new()
	subtitle.text = "和林夏一起找今晚能做的双人兼职"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	left.add_child(subtitle)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(180, 0)
	hbox.add_child(right)

	var wallet_hint := Label.new()
	wallet_hint.text = "当前余额"
	wallet_hint.add_theme_font_size_override("font_size", 13)
	wallet_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	right.add_child(wallet_hint)

	_wallet_label = Label.new()
	_wallet_label.text = "￥0"
	_wallet_label.add_theme_font_size_override("font_size", 24)
	_wallet_label.add_theme_color_override("font_color", Color.WHITE)
	right.add_child(_wallet_label)

	return header_bg


func _build_body() -> Control:
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)

	var outer := HSplitContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.split_offset = 540
	margin.add_child(outer)

	outer.add_child(_build_list_panel())
	outer.add_child(_build_detail_panel())
	return margin


func _build_list_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "推荐岗位"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(title)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "搜索岗位 / 店名 / 区域"
	_search_input.custom_minimum_size = Vector2(0, 42)
	_search_input.add_theme_stylebox_override("normal", _input_style())
	_search_input.add_theme_stylebox_override("focus", _input_focus_style())
	_search_input.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_search_input)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 13)
	_result_label.add_theme_color_override("font_color", COLOR_SUBTEXT)
	vbox.add_child(_result_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_job_list = VBoxContainer.new()
	_job_list.add_theme_constant_override("separation", 10)
	_job_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_job_list)

	return panel


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	_detail_title = Label.new()
	_detail_title.text = "选择一个岗位"
	_detail_title.add_theme_font_size_override("font_size", 26)
	_detail_title.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_detail_title)

	_detail_company = Label.new()
	_detail_company.add_theme_font_size_override("font_size", 16)
	_detail_company.add_theme_color_override("font_color", COLOR_SUBTEXT)
	vbox.add_child(_detail_company)

	_detail_salary = Label.new()
	_detail_salary.add_theme_font_size_override("font_size", 28)
	_detail_salary.add_theme_color_override("font_color", COLOR_SALARY)
	vbox.add_child(_detail_salary)

	_detail_meta = Label.new()
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_meta.add_theme_font_size_override("font_size", 14)
	_detail_meta.add_theme_color_override("font_color", COLOR_SUBTEXT)
	vbox.add_child(_detail_meta)

	_tags_flow = HFlowContainer.new()
	_tags_flow.add_theme_constant_override("h_separation", 8)
	_tags_flow.add_theme_constant_override("v_separation", 8)
	vbox.add_child(_tags_flow)

	_detail_desc = _create_block_label(15)
	vbox.add_child(_wrap_block("工作内容", _detail_desc))


	_detail_status = Label.new()
	_detail_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_status.add_theme_font_size_override("font_size", 14)
	_detail_status.add_theme_color_override("font_color", COLOR_SUBTEXT)
	vbox.add_child(_detail_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_apply_button = Button.new()
	_apply_button.text = "和林夏一起报名"
	_apply_button.custom_minimum_size = Vector2(0, 48)
	_apply_button.add_theme_stylebox_override("normal", _action_button_style(COLOR_BRAND))
	_apply_button.add_theme_stylebox_override("hover", _action_button_style(COLOR_BRAND_DARK))
	_apply_button.add_theme_stylebox_override("pressed", _action_button_style(COLOR_BRAND_DARK))
	_apply_button.add_theme_stylebox_override("disabled", _action_button_style(COLOR_DISABLED))
	_apply_button.add_theme_color_override("font_color", Color.WHITE)
	_apply_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_apply_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_apply_button.add_theme_color_override("font_disabled_color", Color("#6B7280"))
	_apply_button.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_apply_button)

	return panel


func _connect_signals() -> void:
	if _search_input != null:
		_search_input.text_changed.connect(_on_search_changed)
	if _apply_button != null:
		_apply_button.pressed.connect(_on_apply_pressed)
	if _game_manager != null and _game_manager.has_signal("money_changed"):
		_game_manager.money_changed.connect(_on_money_changed)
	if _game_loop != null:
		if _game_loop.has_signal("ap_changed"):
			_game_loop.ap_changed.connect(_on_action_state_changed)
		if _game_loop.has_signal("phase_changed"):
			_game_loop.phase_changed.connect(_on_phase_changed)
	if _part_time_manager != null:
		if _part_time_manager.has_signal("transit_started"):
			_part_time_manager.transit_started.connect(_on_transit_started)
		if _part_time_manager.has_signal("transit_progress_updated"):
			_part_time_manager.transit_progress_updated.connect(_on_transit_progress_updated)
		if _part_time_manager.has_signal("job_completed"):
			_part_time_manager.job_completed.connect(_on_job_completed)
		if _part_time_manager.has_signal("catalog_refreshed"):
			_part_time_manager.catalog_refreshed.connect(_on_catalog_refreshed)
			
func _on_catalog_refreshed(_catalog: Array) -> void:
	_do_reload_jobs()


func _reload_jobs() -> void:
	if _part_time_manager != null and _part_time_manager.has_method("refresh_weekly_catalog"):
		_part_time_manager.refresh_weekly_catalog()
	_do_reload_jobs()

func _do_reload_jobs() -> void:
	if _part_time_manager == null or not _part_time_manager.has_method("get_catalog"):
		_all_jobs.clear()
		_filtered_jobs.clear()
		_rebuild_job_cards()
		_update_detail_panel({})
		return

	var loaded: Variant = _part_time_manager.get_catalog()
	_all_jobs.clear()
	if loaded is Array:
		for entry in loaded:
			if entry is Dictionary:
				_all_jobs.append(entry)

	_apply_search_filter()


func _apply_search_filter() -> void:
	var keyword: String = ""
	if _search_input != null:
		keyword = _search_input.text.strip_edges().to_lower()

	_filtered_jobs.clear()
	for job in _all_jobs:
		if keyword.is_empty() or _job_matches_keyword(job, keyword):
			_filtered_jobs.append(job)

	if _selected_job_id.is_empty() or _find_job_by_id(_selected_job_id).is_empty():
		if _filtered_jobs.is_empty():
			_selected_job_id = ""
		else:
			_selected_job_id = str(_filtered_jobs[0].get("job_id", ""))

	_rebuild_job_cards()
	_update_detail_panel(_find_job_by_id(_selected_job_id))


func _job_matches_keyword(job: Dictionary, keyword: String) -> bool:
	var haystack := PackedStringArray([
		str(job.get("job_title", "")),
		str(job.get("company_name", "")),
		str(job.get("district", "")),
		str(job.get("subtitle", "")),
		str(job.get("description", "")),
	])
	var combined_text: String = " ".join(haystack)
	var haystack_text := combined_text.to_lower()
	return haystack_text.contains(keyword)


func _rebuild_job_cards() -> void:
	if _job_list == null:
		return

	for child in _job_list.get_children():
		child.queue_free()

	if _result_label != null:
		_result_label.text = "共 %d 个可选岗位" % _filtered_jobs.size()

	if _filtered_jobs.is_empty():
		var empty := Label.new()
		empty.text = "没有匹配到岗位。"
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", COLOR_SUBTEXT)
		_job_list.add_child(empty)
		return

	for job in _filtered_jobs:
		_job_list.add_child(_build_job_card(job))


func _build_job_card(job: Dictionary) -> Button:
	var button := Button.new()
	button.flat = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 118)
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_job_selected.bind(str(job.get("job_id", ""))))

	var hint := ActivityPreviewHintClass.new()
	hint.set_preview_payload(_build_job_preview_payload(job))
	button.add_child(hint)

	var selected: bool = str(job.get("job_id", "")) == _selected_job_id
	var enabled: bool = bool(job.get("enabled", true)) and _active_session_id.is_empty()
	button.add_theme_stylebox_override("normal", _card_style(selected, enabled))
	button.add_theme_stylebox_override("hover", _card_style(true, enabled))
	button.add_theme_stylebox_override("pressed", _card_style(true, enabled))
	button.disabled = false

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	button.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)

	var title := Label.new()
	title.text = str(job.get("job_title", "未命名岗位"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_TEXT if enabled else COLOR_SUBTEXT)
	top.add_child(title)

	var salary := Label.new()
	salary.text = "%d元 / 班" % _get_money_reward(job)
	salary.add_theme_font_size_override("font_size", 18)
	salary.add_theme_color_override("font_color", COLOR_SALARY if enabled else COLOR_SUBTEXT)
	top.add_child(salary)

	var company := Label.new()
	company.text = "%s · %s" % [
		str(job.get("company_name", "双人兼职")),
		str(job.get("district", ""))
	]
	company.add_theme_font_size_override("font_size", 14)
	company.add_theme_color_override("font_color", COLOR_SUBTEXT)
	content.add_child(company)

	var subtitle := Label.new()
	subtitle.text = str(job.get("subtitle", ""))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#4B5563"))
	content.add_child(subtitle)


	return button


func _update_detail_panel(job: Dictionary) -> void:
	if job.is_empty():
		if _detail_title != null:
			_detail_title.text = "选择一个岗位"
		if _detail_company != null:
			_detail_company.text = "今晚和林夏一起去做什么兼职？"
		if _detail_salary != null:
			_detail_salary.text = ""
		if _detail_meta != null:
			_detail_meta.text = ""
		if _detail_desc != null:
			_detail_desc.text = ""

		if _detail_boss != null:
			_detail_boss.text = ""
		if _detail_status != null:
			_detail_status.text = "左侧职位会触发一场和林夏一起完成的兼职事件。"
		if _apply_button != null:
			_apply_button.disabled = true
		if _tags_flow != null:
			for child in _tags_flow.get_children():
				child.queue_free()
		return

	_detail_title.text = str(job.get("job_title", "未命名岗位"))
	_detail_company.text = "%s · %s" % [
		str(job.get("company_name", "双人兼职")),
		str(job.get("district", ""))
	]
	_detail_salary.text = "%d元 / 班" % _get_money_reward(job)
	_detail_meta.text = str(job.get("subtitle", ""))
	_detail_desc.text = str(job.get("description", ""))
	if _detail_boss != null:
		_detail_boss.text = ""

	for child in _tags_flow.get_children():
		child.queue_free()

	var can_apply: bool = bool(job.get("enabled", true)) and _active_session_id.is_empty()
	if _active_session_id.is_empty():
		_detail_status.text = "这是一次双人兼职事件。投递后会通过 LinkChat 和约会场景链路推进。"
	else:
		_detail_status.text = "当前已有一份兼职正在进行，先完成这一班。"
	_apply_button.disabled = not can_apply


func _create_tag(text: String) -> Control:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", COLOR_TAG_TEXT)

	var wrapper := PanelContainer.new()
	wrapper.add_theme_stylebox_override("panel", _tag_style())
	wrapper.add_child(tag)
	return wrapper


func _create_block_label(font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	return label


func _wrap_block(title_text: String, body: Control) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sub_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COLOR_SUBTEXT)
	vbox.add_child(title)
	vbox.add_child(body)
	return panel


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.shadow_color = Color(0, 0, 0, 0.06)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	return style


func _sub_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#F9FAFB")
	style.border_color = Color("#EEF2F7")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	return style


func _card_style(selected: bool, enabled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#F7FFFB") if selected else Color.WHITE
	style.border_color = COLOR_BRAND if selected else COLOR_BORDER
	style.set_border_width_all(2 if selected else 1)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	if not enabled:
		style.bg_color = Color("#F3F4F6")
		style.border_color = Color("#E5E7EB")
	return style


func _tag_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TAG_BG
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 10
	style.content_margin_top = 4
	style.content_margin_right = 10
	style.content_margin_bottom = 4
	return style


func _input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color("#D1D5DB")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style


func _input_focus_style() -> StyleBoxFlat:
	var style := _input_style()
	style.border_color = COLOR_BRAND
	style.set_border_width_all(2)
	return style


func _action_button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	return style


func _find_job_by_id(job_id: String) -> Dictionary:
	for job in _filtered_jobs:
		if str(job.get("job_id", "")) == job_id:
			return job
	for job in _all_jobs:
		if str(job.get("job_id", "")) == job_id:
			return job
	return {}


func _update_wallet() -> void:
	if _wallet_label == null:
		return
	var money: int = int(_game_manager.get("money")) if _game_manager != null else 0
	_wallet_label.text = "￥%d" % money


func _open_linkchat_dm() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("launch_app"):
		return
	var window: Control = app_manager.launch_app("linkchat")
	if window == null:
		return
	call_deferred("_select_linkchat_dm", window)


func _select_linkchat_dm(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	var content: Variant = window.get("content")
	if content != null and content.has_method("select_channel"):
		content.select_channel("dm_lin_xia")


func _on_search_changed(_text: String) -> void:
	_apply_search_filter()


func _on_job_selected(job_id: String) -> void:
	_selected_job_id = job_id
	_rebuild_job_cards()
	_update_detail_panel(_find_job_by_id(job_id))


func _on_apply_pressed() -> void:
	if _part_time_manager == null or _selected_job_id.is_empty():
		return

	var result: Dictionary = _part_time_manager.begin_part_time(_selected_job_id)
	if not bool(result.get("success", false)):
		if _detail_status != null:
			_detail_status.text = str(result.get("error", "兼职启动失败"))
		return

	_active_session_id = str(result.get("session_id", ""))
	var reward_money: int = _get_money_reward(result)
	if _detail_status != null:
		_detail_status.text = "已投递成功。今晚和林夏一起去上班，预计到账 %d 元。" % reward_money
	_open_linkchat_dm()
	_reload_jobs()


func _on_transit_started(session_id: String, _payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_transit_progress = 0.0


func _on_transit_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	if session_id != _active_session_id:
		return
	_transit_progress = progress


func _process(_delta: float) -> void:
	if _active_session_id.is_empty() or _transit_window == null or not is_instance_valid(_transit_window):
		set_process(false)
		return
	if _transit_stage_label != null:
		var stage_index := mini(int(floor(_transit_progress * float(TRANSIT_STAGES.size()))), TRANSIT_STAGES.size() - 1)
		_transit_stage_label.text = TRANSIT_STAGES[stage_index]
	if _transit_eta_label != null:
		_transit_eta_label.text = "即将到达" if _transit_progress > 0.9 else "前往中..."


func _show_transit_window(location: Variant) -> void:
	_close_transit_window()

	var loc: Dictionary = location if location is Dictionary else {}
	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = null
	if app_manager != null:
		window_manager = app_manager.get("window_manager")
	if window_manager == null or not window_manager.has_method("create_window"):
		return

	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color("#FFFFFF")
	outer_style.corner_radius_top_left = 16
	outer_style.corner_radius_top_right = 16
	outer_style.corner_radius_bottom_left = 16
	outer_style.corner_radius_bottom_right = 16
	outer.add_theme_stylebox_override("panel", outer_style)
	outer.custom_minimum_size = Vector2(420, 200)

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	content.add_child(box)

	_transit_title_label = Label.new()
	_transit_title_label.text = str(loc.get("title", "兼职地点"))
	_transit_title_label.add_theme_font_size_override("font_size", 22)
	_transit_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(_transit_title_label)

	_transit_stage_label = Label.new()
	_transit_stage_label.text = TRANSIT_STAGES[0]
	_transit_stage_label.add_theme_font_size_override("font_size", 14)
	_transit_stage_label.add_theme_color_override("font_color", COLOR_SUBTEXT)
	box.add_child(_transit_stage_label)

	_transit_progress_bar = ProgressBar.new()
	_transit_progress_bar.min_value = 0.0
	_transit_progress_bar.max_value = 100.0
	_transit_progress_bar.value = 0.0
	_transit_progress_bar.show_percentage = false
	_transit_progress_bar.custom_minimum_size = Vector2(0, 6)
	var progress_bg_style := StyleBoxFlat.new()
	progress_bg_style.bg_color = Color("#E8EAED")
	progress_bg_style.corner_radius_top_left = 3
	progress_bg_style.corner_radius_top_right = 3
	progress_bg_style.corner_radius_bottom_left = 3
	progress_bg_style.corner_radius_bottom_right = 3
	_transit_progress_bar.add_theme_stylebox_override("background", progress_bg_style)
	var progress_fill_style := StyleBoxFlat.new()
	progress_fill_style.bg_color = COLOR_TRANSIT_GREEN
	progress_fill_style.corner_radius_top_left = 3
	progress_fill_style.corner_radius_top_right = 3
	progress_fill_style.corner_radius_bottom_left = 3
	progress_fill_style.corner_radius_bottom_right = 3
	_transit_progress_bar.add_theme_stylebox_override("fill", progress_fill_style)
	box.add_child(_transit_progress_bar)

	var eta_hbox := HBoxContainer.new()
	box.add_child(eta_hbox)

	var eta_icon := Label.new()
	eta_icon.text = "🚌"
	eta_icon.add_theme_font_size_override("font_size", 14)
	eta_hbox.add_child(eta_icon)

	_transit_eta_label = Label.new()
	_transit_eta_label.text = "前往中..."
	_transit_eta_label.add_theme_font_size_override("font_size", 14)
	_transit_eta_label.add_theme_color_override("font_color", COLOR_TRANSIT_GREEN)
	eta_hbox.add_child(_transit_eta_label)

	_transit_window = window_manager.create_window("前往兼职", outer)
	if _transit_window != null:
		_transit_window.size = Vector2(460, 240)


func _close_transit_window() -> void:
	if _transit_window == null or not is_instance_valid(_transit_window):
		_transit_window = null
		_transit_title_label = null
		_transit_stage_label = null
		_transit_progress_bar = null
		_transit_eta_label = null
		return

	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = null
	if app_manager != null:
		window_manager = app_manager.get("window_manager")
	if window_manager != null and window_manager.has_method("close_window"):
		window_manager.close_window(_transit_window)
	else:
		_transit_window.queue_free()

	_transit_window = null
	_transit_title_label = null
	_transit_stage_label = null
	_transit_progress_bar = null
	_transit_eta_label = null


func _on_job_completed(session_id: String, payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	if str(payload.get("activity_type", "")) != "part_time":
		return

	_active_session_id = ""
	_transit_progress = 0.0
	var reward_money: int = _get_money_reward(payload)
	if _detail_status != null:
		_detail_status.text = "这班结束了，到手 %d 元。林夏应该也已经在 LinkChat 那边有后续反应了。" % reward_money
	_update_wallet()
	_reload_jobs()


func _get_money_reward(source: Dictionary) -> int:
	var rewards: Dictionary = source.get("rewards", {}) as Dictionary
	return int(rewards.get("money", 0))


func _build_job_preview_payload(job: Dictionary) -> Dictionary:
	return {
		"title": str(job.get("job_title", "兼职")),
		"rewards": (job.get("rewards", {}) as Dictionary).duplicate(true),
		"text": str(job.get("subtitle", "")),
		"disabled_reason": str(job.get("disabled_reason", "")),
		"accent_color": Color(str(job.get("accent_color", "#10B981"))),
	}


func _on_money_changed(_old_val: int, _new_val: int) -> void:
	_update_wallet()


func _on_action_state_changed(_current: int, _max: int) -> void:
	_do_reload_jobs()


func _on_phase_changed(_phase: int) -> void:
	_do_reload_jobs()
