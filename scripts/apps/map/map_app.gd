class_name MapApp
extends Control

const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")

const TRANSIT_STAGES: Array[String] = [
	"正在规划路线...",
	"步行前往站点  约 2 分钟",
	"正在等待进站...",
	"列车运行中",
	"途经 3 站",
	"下一站即为目的地",
	"请准备下车",
	"已到达  步行约 1 分钟"
]

const COLOR_MAP_BG := Color("#EDE8DF")
const COLOR_MAP_ROAD := Color("#FFFFFF")
const COLOR_MAP_ROAD_MINOR := Color("#F5F1EB")
const COLOR_MAP_WATER := Color("#AADAFF")
const COLOR_MAP_GREEN := Color("#C8E6C0")
const COLOR_PIN_DEFAULT := Color("#EA4335")
const COLOR_PIN_SELECTED := Color("#1A73E8")
const COLOR_CARD_BG := Color("#FFFFFF")
const COLOR_CARD_SHADOW := Color(0, 0, 0, 0.12)
const COLOR_TEXT_DARK := Color("#202124")
const COLOR_TEXT_SECONDARY := Color("#5F6368")
const COLOR_TEXT_LINK := Color("#1A73E8")
const COLOR_BTN_ACTION := Color("#1A73E8")
const COLOR_BTN_HOVER := Color("#1765CC")
const COLOR_SEARCH_BG := Color("#FFFFFF")
const COLOR_SEARCH_BORDER := Color("#DADCE0")
const COLOR_TRANSIT_GREEN := Color("#34A853")

var _date_manager: Node = null
var _game_loop: Node = null
var _pin_buttons: Dictionary = {}
var _selected_event_id: String = ""
var _active_session_id: String = ""
var _transit_progress: float = 0.0

var _map_canvas: Control = null
var _detail_card: PanelContainer = null
var _detail_title: Label = null
var _detail_subtitle: Label = null
var _detail_body: Label = null
var _detail_footer: Label = null
var _confirm_button: Button = null

var _transit_window: Control = null
var _transit_title_label: Label = null
var _transit_stage_label: Label = null
var _transit_eta_label: Label = null
var _transit_progress_bar: ProgressBar = null


func _ready() -> void:
	_date_manager = get_node_or_null("/root/DateManager")
	_game_loop = get_node_or_null("/root/GameLoopManager")
	_build_ui()
	_connect_signals()
	_refresh_locations()


func _process(_delta: float) -> void:
	if _active_session_id.is_empty() or _transit_window == null or not is_instance_valid(_transit_window):
		set_process(false)
		return
	if _transit_stage_label != null:
		var stage_index := mini(int(floor(_transit_progress * float(TRANSIT_STAGES.size()))), TRANSIT_STAGES.size() - 1)
		_transit_stage_label.text = TRANSIT_STAGES[stage_index]
	if _transit_eta_label != null:
		_transit_eta_label.text = "即将到达" if _transit_progress > 0.9 else "前往中..."


func _build_ui() -> void:
	# --- 地图底色（暖白） ---
	var background := ColorRect.new()
	background.color = COLOR_MAP_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# --- 装饰性路网 ---
	_draw_decorative_roads(background)

	# --- 地图画布（全屏，pins 放在上面） ---
	_map_canvas = Control.new()
	_map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map_canvas)

	# --- 顶部搜索栏（装饰） ---
	var search_bar := _build_search_bar()
	add_child(search_bar)

	# --- 底部浮动详情卡片 ---
	_build_detail_card()


func _draw_decorative_roads(parent: Control) -> void:
	# 横向主干道
	var road_positions_h: Array[float] = [0.25, 0.5, 0.75]
	for y_ratio in road_positions_h:
		var road := ColorRect.new()
		road.color = COLOR_MAP_ROAD
		road.set_anchors_preset(Control.PRESET_TOP_LEFT)
		road.anchor_left = 0.0
		road.anchor_right = 1.0
		road.anchor_top = y_ratio
		road.anchor_bottom = y_ratio
		road.offset_top = -2
		road.offset_bottom = 2
		parent.add_child(road)

	# 纵向主干道
	var road_positions_v: Array[float] = [0.2, 0.45, 0.7]
	for x_ratio in road_positions_v:
		var road := ColorRect.new()
		road.color = COLOR_MAP_ROAD
		road.set_anchors_preset(Control.PRESET_TOP_LEFT)
		road.anchor_left = x_ratio
		road.anchor_right = x_ratio
		road.anchor_top = 0.0
		road.anchor_bottom = 1.0
		road.offset_left = -2
		road.offset_right = 2
		parent.add_child(road)

	# 细路
	var minor_h: Array[float] = [0.15, 0.35, 0.62, 0.88]
	for y_ratio in minor_h:
		var road := ColorRect.new()
		road.color = COLOR_MAP_ROAD_MINOR
		road.set_anchors_preset(Control.PRESET_TOP_LEFT)
		road.anchor_left = 0.0
		road.anchor_right = 1.0
		road.anchor_top = y_ratio
		road.anchor_bottom = y_ratio
		road.offset_top = -1
		road.offset_bottom = 1
		parent.add_child(road)

	var minor_v: Array[float] = [0.1, 0.33, 0.55, 0.82]
	for x_ratio in minor_v:
		var road := ColorRect.new()
		road.color = COLOR_MAP_ROAD_MINOR
		road.set_anchors_preset(Control.PRESET_TOP_LEFT)
		road.anchor_left = x_ratio
		road.anchor_right = x_ratio
		road.anchor_top = 0.0
		road.anchor_bottom = 1.0
		road.offset_left = -1
		road.offset_right = 1
		parent.add_child(road)

	# 装饰性绿地色块
	var park := ColorRect.new()
	park.color = COLOR_MAP_GREEN
	park.set_anchors_preset(Control.PRESET_TOP_LEFT)
	park.anchor_left = 0.05
	park.anchor_right = 0.15
	park.anchor_top = 0.05
	park.anchor_bottom = 0.2
	parent.add_child(park)

	# 装饰性水域
	var water := ColorRect.new()
	water.color = COLOR_MAP_WATER
	water.set_anchors_preset(Control.PRESET_TOP_LEFT)
	water.anchor_left = 0.78
	water.anchor_right = 0.98
	water.anchor_top = 0.7
	water.anchor_bottom = 0.95
	parent.add_child(water)


func _build_search_bar() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.offset_top = 12
	margin.offset_bottom = 56
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)

	var search_panel := PanelContainer.new()
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = COLOR_SEARCH_BG
	s_style.border_color = COLOR_SEARCH_BORDER
	s_style.set_border_width_all(1)
	s_style.corner_radius_top_left = 24
	s_style.corner_radius_top_right = 24
	s_style.corner_radius_bottom_left = 24
	s_style.corner_radius_bottom_right = 24
	s_style.shadow_color = Color(0, 0, 0, 0.08)
	s_style.shadow_size = 4
	s_style.shadow_offset = Vector2(0, 2)
	search_panel.add_theme_stylebox_override("panel", s_style)
	margin.add_child(search_panel)

	var search_margin := MarginContainer.new()
	search_margin.add_theme_constant_override("margin_left", 18)
	search_margin.add_theme_constant_override("margin_right", 18)
	search_margin.add_theme_constant_override("margin_top", 8)
	search_margin.add_theme_constant_override("margin_bottom", 8)
	search_panel.add_child(search_margin)

	var search_hbox := HBoxContainer.new()
	search_hbox.add_theme_constant_override("separation", 10)
	search_margin.add_child(search_hbox)

	var search_icon := Label.new()
	search_icon.text = "🔍"
	search_icon.add_theme_font_size_override("font_size", 16)
	search_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	search_hbox.add_child(search_icon)

	var search_text := Label.new()
	search_text.text = "搜索地点"
	search_text.add_theme_font_size_override("font_size", 15)
	search_text.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	search_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_hbox.add_child(search_text)

	return margin


func _build_detail_card() -> void:
	# 底部浮动白色卡片
	var card_margin := MarginContainer.new()
	card_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card_margin.offset_top = -200
	card_margin.offset_bottom = -16
	card_margin.add_theme_constant_override("margin_left", 24)
	card_margin.add_theme_constant_override("margin_right", 24)
	add_child(card_margin)

	_detail_card = PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_CARD_BG
	card_style.corner_radius_top_left = 16
	card_style.corner_radius_top_right = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card_style.shadow_color = COLOR_CARD_SHADOW
	card_style.shadow_size = 8
	card_style.shadow_offset = Vector2(0, 2)
	_detail_card.add_theme_stylebox_override("panel", card_style)
	card_margin.add_child(_detail_card)

	var inner_margin := MarginContainer.new()
	inner_margin.add_theme_constant_override("margin_left", 20)
	inner_margin.add_theme_constant_override("margin_top", 16)
	inner_margin.add_theme_constant_override("margin_right", 20)
	inner_margin.add_theme_constant_override("margin_bottom", 16)
	_detail_card.add_child(inner_margin)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	inner_margin.add_child(info)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	info.add_child(_detail_title)

	_detail_subtitle = Label.new()
	_detail_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_subtitle.add_theme_font_size_override("font_size", 13)
	_detail_subtitle.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	info.add_child(_detail_subtitle)

	_detail_body = Label.new()
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.add_theme_font_size_override("font_size", 14)
	_detail_body.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	info.add_child(_detail_body)

	_detail_footer = Label.new()
	_detail_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_footer.add_theme_font_size_override("font_size", 12)
	_detail_footer.add_theme_color_override("font_color", COLOR_TEXT_LINK)
	info.add_child(_detail_footer)

	# 行动按钮
	_confirm_button = Button.new()
	_confirm_button.text = "出发"
	_confirm_button.custom_minimum_size = Vector2(0, 40)
	var btn_style_n := StyleBoxFlat.new()
	btn_style_n.bg_color = COLOR_BTN_ACTION
	btn_style_n.corner_radius_top_left = 20
	btn_style_n.corner_radius_top_right = 20
	btn_style_n.corner_radius_bottom_left = 20
	btn_style_n.corner_radius_bottom_right = 20
	_confirm_button.add_theme_stylebox_override("normal", btn_style_n)
	var btn_style_h := btn_style_n.duplicate()
	btn_style_h.bg_color = COLOR_BTN_HOVER
	_confirm_button.add_theme_stylebox_override("hover", btn_style_h)
	_confirm_button.add_theme_stylebox_override("pressed", btn_style_h)
	var btn_style_d := btn_style_n.duplicate()
	btn_style_d.bg_color = Color("#DADCE0")
	_confirm_button.add_theme_stylebox_override("disabled", btn_style_d)
	_confirm_button.add_theme_color_override("font_color", Color.WHITE)
	_confirm_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_confirm_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_confirm_button.add_theme_color_override("font_disabled_color", COLOR_TEXT_SECONDARY)
	_confirm_button.add_theme_font_size_override("font_size", 15)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	info.add_child(_confirm_button)


func _connect_signals() -> void:
	if _date_manager != null:
		_date_manager.transit_started.connect(_on_transit_started)
		_date_manager.transit_progress_updated.connect(_on_transit_progress_updated)
		_date_manager.important_event_started.connect(_on_important_event_started)
		_date_manager.date_completed.connect(_on_date_completed)
	if _game_loop != null:
		_game_loop.ap_changed.connect(_on_action_state_changed)
		_game_loop.phase_changed.connect(_on_phase_changed)


func _refresh_locations() -> void:
	if _date_manager == null or _map_canvas == null:
		return

	for child in _map_canvas.get_children():
		child.queue_free()
	_pin_buttons.clear()

	var events: Array = _date_manager.get_available_events()
	for event in events:
		if not event is Dictionary:
			continue
		var pin := _create_map_pin(event)
		_map_canvas.add_child(pin)
		_pin_buttons[str(event.get("event_id", ""))] = {
			"button": pin,
			"event": event,
		}

	if _selected_event_id.is_empty() and not events.is_empty():
		_selected_event_id = str((events[0] as Dictionary).get("event_id", ""))

	_refresh_selection_state()


func _create_map_pin(event: Dictionary) -> Control:
	var pin_root := VBoxContainer.new()
	pin_root.add_theme_constant_override("separation", 2)

	# 圆形标记
	var dot_panel := PanelContainer.new()
	dot_panel.custom_minimum_size = Vector2(18, 18)
	dot_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var dot_style := StyleBoxFlat.new()
	var accent := str(event.get("accent_color", "#EA4335")).strip_edges()
	dot_style.bg_color = Color(accent) if not accent.is_empty() else COLOR_PIN_DEFAULT
	dot_style.corner_radius_top_left = 9
	dot_style.corner_radius_top_right = 9
	dot_style.corner_radius_bottom_left = 9
	dot_style.corner_radius_bottom_right = 9
	dot_style.shadow_color = Color(0, 0, 0, 0.2)
	dot_style.shadow_size = 2
	dot_style.shadow_offset = Vector2(0, 1)
	dot_panel.add_theme_stylebox_override("panel", dot_style)
	dot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	pin_root.add_child(dot_panel)

	# 事件名按钮
	var evt_id := str(event.get("event_id", ""))
	var name_btn := Button.new()
	name_btn.text = str(event.get("title", "活动"))
	name_btn.flat = true
	name_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	name_btn.add_theme_font_size_override("font_size", 12)
	name_btn.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	name_btn.add_theme_color_override("font_hover_color", COLOR_PIN_SELECTED)
	var name_style := StyleBoxFlat.new()
	name_style.bg_color = Color(1, 1, 1, 0.92)
	name_style.corner_radius_top_left = 4
	name_style.corner_radius_top_right = 4
	name_style.corner_radius_bottom_left = 4
	name_style.corner_radius_bottom_right = 4
	name_style.content_margin_left = 6
	name_style.content_margin_right = 6
	name_style.content_margin_top = 2
	name_style.content_margin_bottom = 2
	name_style.shadow_color = Color(0, 0, 0, 0.1)
	name_style.shadow_size = 2
	name_btn.add_theme_stylebox_override("normal", name_style)
	name_btn.add_theme_stylebox_override("hover", name_style)
	name_btn.add_theme_stylebox_override("pressed", name_style)
	name_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	name_btn.pressed.connect(_on_location_pressed.bind(evt_id))
	var hint := ActivityPreviewHintClass.new()
	hint.set_preview_payload(_build_date_preview_payload(event))
	name_btn.add_child(hint)
	pin_root.add_child(name_btn)

	# VBox 本身也接收 gui_input（处理点击圆点的情况）
	pin_root.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_location_pressed(evt_id)
			get_viewport().set_input_as_handled()
	)

	var pos := _map_to_canvas(event.get("map_position", Vector2(0.5, 0.5)))
	pin_root.position = pos

	return pin_root


func _map_to_canvas(pos: Variant) -> Vector2:
	var normalized: Vector2 = pos if pos is Vector2 else Vector2(0.5, 0.5)
	return Vector2(
		clampf(normalized.x, 0.06, 0.94) * size.x - 40.0,
		clampf(normalized.y, 0.12, 0.65) * size.y - 10.0
	)


func _build_date_preview_payload(event: Dictionary) -> Dictionary:
	var conditions: Array[String] = []
	var phases: Array = event.get("valid_phases", [])
	if not phases.is_empty():
		var phase_names: Array[String] = []
		for phase in phases:
			match str(phase):
				"MORNING":
					phase_names.append("早上")
				"AFTERNOON":
					phase_names.append("下午")
				"NIGHT":
					phase_names.append("晚上")
				_:
					phase_names.append(str(phase))
		conditions.append("可用时段：%s" % " / ".join(phase_names))

	return {
		"title": str(event.get("title", "约会")),
		"rewards": (event.get("rewards", {}) as Dictionary).duplicate(true),
		"text": str(event.get("subtitle", "")),
		"conditions": conditions,
		"accent_color": Color(str(event.get("accent_color", "#1A73E8"))),
	}


func _refresh_selection_state() -> void:
	for event_id in _pin_buttons.keys():
		var info: Dictionary = _pin_buttons[event_id]
		var pin: Control = info.get("button")
		if pin == null:
			continue
		var dot: PanelContainer = pin.get_child(0) if pin.get_child_count() > 0 else null
		if dot == null or not dot is PanelContainer:
			continue
		var is_selected: bool = (event_id == _selected_event_id)
		var dot_style := StyleBoxFlat.new()
		dot_style.bg_color = COLOR_PIN_SELECTED if is_selected else COLOR_PIN_DEFAULT
		var radius := 11 if is_selected else 9
		dot_style.corner_radius_top_left = radius
		dot_style.corner_radius_top_right = radius
		dot_style.corner_radius_bottom_left = radius
		dot_style.corner_radius_bottom_right = radius
		if is_selected:
			dot_style.border_color = Color(1, 1, 1, 0.9)
			dot_style.set_border_width_all(3)
			dot_style.shadow_color = Color(0.1, 0.45, 0.91, 0.3)
			dot_style.shadow_size = 6
		else:
			dot_style.shadow_color = Color(0, 0, 0, 0.2)
			dot_style.shadow_size = 2
			dot_style.shadow_offset = Vector2(0, 1)
		dot.custom_minimum_size = Vector2(22, 22) if is_selected else Vector2(18, 18)
		dot.add_theme_stylebox_override("panel", dot_style)

	var selected: Dictionary = _get_selected_event()
	if selected.is_empty():
		_detail_title.text = "选择约会活动"
		_detail_subtitle.text = ""
		_detail_body.text = ""
		_detail_footer.text = ""
		_confirm_button.disabled = true
		return

	_detail_title.text = str(selected.get("title", "未命名活动"))
	var location_title := str(selected.get("location_title", selected.get("subtitle", ""))).strip_edges()
	_detail_subtitle.text = location_title
	_detail_body.text = str(selected.get("description", ""))
	_detail_footer.text = ""
	_confirm_button.disabled = _active_session_id != "" or not bool(selected.get("enabled", true))


func _get_selected_event() -> Dictionary:
	if _selected_event_id.is_empty() or not _pin_buttons.has(_selected_event_id):
		return {}
	return (_pin_buttons[_selected_event_id] as Dictionary).get("event", {}).duplicate(true)


func _on_location_pressed(event_id: String) -> void:
	_selected_event_id = event_id
	_refresh_selection_state()


func _on_confirm_pressed() -> void:
	if _date_manager == null or _selected_event_id.is_empty():
		return
	var result: Dictionary = _date_manager.begin_date(_selected_event_id)
	if not bool(result.get("success", false)):
		return

	_active_session_id = str(result.get("session_id", ""))
	_transit_progress = 0.0
	_open_linkchat_dm()
	_refresh_locations()


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


func _on_transit_started(session_id: String, _payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_transit_progress = 0.0


func _on_transit_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	if session_id != _active_session_id:
		return
	_transit_progress = progress


func _on_important_event_started(session_id: String, _payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return


func _show_transit_window(location: Variant) -> void:
	_close_transit_window()

	var loc: Dictionary = location if location is Dictionary else {}
	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = null
	if app_manager != null:
		window_manager = app_manager.get("window_manager")
	if window_manager == null or not window_manager.has_method("create_window"):
		return

	# 白底导航卡片风格
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

	# 目的地大标题
	_transit_title_label = Label.new()
	_transit_title_label.text = str(loc.get("title", "目的地"))
	_transit_title_label.add_theme_font_size_override("font_size", 22)
	_transit_title_label.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	box.add_child(_transit_title_label)

	# 阶段描述
	_transit_stage_label = Label.new()
	_transit_stage_label.text = TRANSIT_STAGES[0]
	_transit_stage_label.add_theme_font_size_override("font_size", 14)
	_transit_stage_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	box.add_child(_transit_stage_label)

	# 绿色进度条
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

	# ETA 行
	var eta_hbox := HBoxContainer.new()
	box.add_child(eta_hbox)

	var eta_icon := Label.new()
	eta_icon.text = "🚇"
	eta_icon.add_theme_font_size_override("font_size", 14)
	eta_hbox.add_child(eta_icon)

	_transit_eta_label = Label.new()
	var eta_mins := 1
	_transit_eta_label.text = "%d 分钟" % maxi(eta_mins, 1)
	_transit_eta_label.add_theme_font_size_override("font_size", 14)
	_transit_eta_label.add_theme_color_override("font_color", COLOR_TRANSIT_GREEN)
	eta_hbox.add_child(_transit_eta_label)

	_transit_window = window_manager.create_window("导航", outer)
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


func _on_date_completed(session_id: String, _payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_active_session_id = ""
	_transit_progress = 0.0
	_refresh_locations()


func _on_action_state_changed(_current: int, _max: int) -> void:
	_refresh_locations()


func _on_phase_changed(_phase: int) -> void:
	_refresh_locations()
