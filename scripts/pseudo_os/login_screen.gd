class_name LoginScreen extends Control
## 日式风格登录界面
## 新游戏：输入网名 → AI审核 → 登录
## 继续游戏：显示已有存档用户 → 点击登录
## 右下角：设置、退出

const UIIconLibraryClass = preload("res://scripts/ui/ui_icon_library.gd")

signal login_requested(player_name: String, is_new_game: bool, play_mode: String)
signal quit_requested
signal settings_requested

const AIServiceClass = preload("res://scripts/llm/AIService.gd")

const MIN_NAME_LENGTH: int = 1
const MAX_NAME_LENGTH: int = 12
const PANEL_ANIM_DURATION: float = 0.3
const BOTTOM_ICON_MAX_WIDTH: int = 64
const REVIEW_PROMPT_KEY: String = "review/player_name"
const REVIEW_SYSTEM_FALLBACK: String = "审核游戏玩家网名。拒绝脏话、侮辱、色情、广告、网址、纯乱码。只输出 JSON：approved, reason, normalized_name。"
const MODE_STORY: String = "story"
const MODE_FREE: String = "free"
const MODE_INFO_PANEL_SIZE: Vector2 = Vector2(440, 340)
const MODE_INFO_PANEL_RIGHT_MARGIN: int = 96

@onready var user_list: VBoxContainer = %UserList
@onready var new_user_panel: Control = %NewUserPanel
@onready var name_input: LineEdit = %NameInput
@onready var login_button: Button = %LoginButton
@onready var new_game_button: Button = %NewGameButton
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var clock_label: Label = %ClockLabel
@onready var date_label: Label = %DateLabel

var _selected_save: String = ""
var _new_user_mode: bool = false
var _review_service: Node = null
var _review_enabled: bool = false
var _pending_review_id: String = ""
var _status_label: Label = null
var _mode_select_panel: VBoxContainer = null
var _mode_info_panel: PanelContainer = null
var _mode_player_name: String = ""
var _mode_is_new_game: bool = false


func _ready() -> void:
	modulate.a = 0.0
	_connect_buttons()
	_setup_bottom_icons()
	_update_clock()
	_check_saves()
	_fade_in()
	_setup_button_animations()
	_ensure_review_service()
	_create_status_label()
	_create_mode_select_panel()
	_create_mode_info_panel()


func _process(_delta: float) -> void:
	_update_clock()


func _connect_buttons() -> void:
	login_button.pressed.connect(_on_login_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	back_button.pressed.connect(_on_back_pressed)
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	name_input.text_submitted.connect(func(_t: String) -> void: _on_login_pressed())
	name_input.text_changed.connect(_on_name_changed)


func _setup_bottom_icons() -> void:
	var settings_tex := UIIconLibraryClass.get_icon("settings")
	if settings_tex and settings_button:
		settings_button.text = ""
		settings_button.icon = settings_tex
		settings_button.expand_icon = true
		settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		settings_button.add_theme_constant_override("icon_max_width", BOTTOM_ICON_MAX_WIDTH)
	var power_tex := UIIconLibraryClass.get_icon("power")
	if power_tex and quit_button:
		quit_button.text = ""
		quit_button.icon = power_tex
		quit_button.expand_icon = true
		quit_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quit_button.add_theme_constant_override("icon_max_width", BOTTOM_ICON_MAX_WIDTH)


func _setup_button_animations() -> void:
	for btn: Button in [login_button, new_game_button, back_button, settings_button, quit_button]:
		if btn == null:
			continue
		_setup_button_animation(btn)


func _setup_button_animation(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	btn.button_down.connect(_on_btn_down.bind(btn))
	btn.button_up.connect(_on_btn_up.bind(btn))
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size / 2.0)


func _on_btn_down(btn: Button) -> void:
	var tw: Tween = btn.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.1)


func _on_btn_up(btn: Button) -> void:
	var tw: Tween = btn.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.15)


func _fade_in() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.6)


func _check_saves() -> void:
	var has_save: bool = _has_existing_save()
	if has_save:
		_show_user_list()
	else:
		_show_new_user()


func _has_existing_save() -> bool:
	var meta_path: String = "user://run/meta.json"
	return FileAccess.file_exists(meta_path)


func _get_save_player_name() -> String:
	var meta_path: String = "user://run/meta.json"
	if not FileAccess.file_exists(meta_path):
		return ""
	var file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return str(parsed.get("player_name", "Player"))
	return "Player"


func _show_user_list() -> void:
	_new_user_mode = false
	# 淡出 new_user_panel
	if new_user_panel.visible:
		var tw: Tween = create_tween()
		tw.tween_property(new_user_panel, "modulate:a", 0.0, PANEL_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			new_user_panel.visible = false
			new_user_panel.modulate.a = 1.0
			_reveal_user_list()
		)
	else:
		_reveal_user_list()

func _reveal_user_list() -> void:
	if _mode_select_panel != null:
		_mode_select_panel.visible = false
	user_list.visible = true
	user_list.modulate.a = 0.0
	back_button.visible = false
	# 清空列表
	for child in user_list.get_children():
		child.queue_free()
	# 添加已有存档用户
	var player_name: String = _get_save_player_name()
	if not player_name.is_empty():
		var user_card: Control = _create_user_card(player_name, true)
		user_list.add_child(user_card)
	new_game_button.visible = true
	# 淡入 user_list
	var tw: Tween = create_tween()
	tw.tween_property(user_list, "modulate:a", 1.0, PANEL_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _show_new_user() -> void:
	_new_user_mode = true
	new_game_button.visible = false
	if _mode_select_panel != null:
		_mode_select_panel.visible = false
	# 淡出 user_list
	if user_list.visible:
		var tw: Tween = create_tween()
		tw.tween_property(user_list, "modulate:a", 0.0, PANEL_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			user_list.visible = false
			user_list.modulate.a = 1.0
			_reveal_new_user()
		)
	else:
		_reveal_new_user()

func _reveal_new_user() -> void:
	new_user_panel.visible = true
	new_user_panel.modulate.a = 0.0
	back_button.visible = _has_existing_save()
	name_input.text = ""
	login_button.disabled = true
	# 淡入 new_user_panel
	var tw: Tween = create_tween()
	tw.tween_property(new_user_panel, "modulate:a", 1.0, PANEL_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: name_input.grab_focus())


func _create_user_card(player_name: String, is_existing: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 80)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.5)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0, 0, 0, 0.06)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)
	# 头像 — 玻璃风圆形
	var avatar_panel := Panel.new()
	avatar_panel.custom_minimum_size = Vector2(48, 48)
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = Color(1, 1, 1, 0.4)
	avatar_style.border_width_left = 2
	avatar_style.border_width_top = 2
	avatar_style.border_width_right = 2
	avatar_style.border_width_bottom = 2
	avatar_style.border_color = Color(1, 1, 1, 0.55)
	avatar_style.corner_radius_top_left = 24
	avatar_style.corner_radius_top_right = 24
	avatar_style.corner_radius_bottom_left = 24
	avatar_style.corner_radius_bottom_right = 24
	avatar_panel.add_theme_stylebox_override("panel", avatar_style)
	hbox.add_child(avatar_panel)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(info)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97, 1))
	info.add_child(name_label)
	if is_existing:
		var hint := Label.new()
		hint.text = "点击选择入口"
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		info.add_child(hint)
	# 悬停效果
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.5)
	hover_style.border_width_left = 1
	hover_style.border_width_top = 1
	hover_style.border_width_right = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = Color(1, 1, 1, 0.65)
	hover_style.corner_radius_top_left = 14
	hover_style.corner_radius_top_right = 14
	hover_style.corner_radius_bottom_left = 14
	hover_style.corner_radius_bottom_right = 14
	card.mouse_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", hover_style)
		var tw: Tween = card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2(1.02, 1.02), 0.15)
	)
	card.mouse_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", style)
		var tw: Tween = card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2.ONE, 0.15)
	)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 点击缩放反馈
			var tw: Tween = card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "scale", Vector2(0.96, 0.96), 0.08)
			tw.tween_property(card, "scale", Vector2.ONE, 0.1)
			tw.tween_callback(func() -> void:
				_selected_save = player_name
				_show_mode_select(player_name, false)
			)
	)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.pivot_offset = card.custom_minimum_size / 2.0
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)
	return card


func _on_login_pressed() -> void:
	if _new_user_mode:
		var player_name: String = name_input.text.strip_edges()
		if player_name.length() < MIN_NAME_LENGTH:
			return
		if _review_enabled and _review_service != null:
			_submit_with_review(player_name)
		else:
			_do_login(player_name)
	else:
		if not _selected_save.is_empty():
			_show_mode_select(_selected_save, false)


func _on_new_game_pressed() -> void:
	_show_new_user()


func _on_back_pressed() -> void:
	if _mode_select_panel != null and _mode_select_panel.visible:
		if _mode_is_new_game:
			_show_new_user()
		else:
			_show_user_list()
		return
	_show_user_list()


func _on_name_changed(new_text: String) -> void:
	var trimmed: String = new_text.strip_edges()
	login_button.disabled = trimmed.length() < MIN_NAME_LENGTH
	if new_text.length() > MAX_NAME_LENGTH:
		name_input.text = new_text.substr(0, MAX_NAME_LENGTH)
		name_input.caret_column = MAX_NAME_LENGTH


func _update_clock() -> void:
	var time: Dictionary = Time.get_time_dict_from_system()
	if clock_label != null:
		clock_label.text = "%02d:%02d" % [time.get("hour", 0), time.get("minute", 0)]
	if date_label != null:
		var date: Dictionary = Time.get_date_dict_from_system()
		var weekdays: Array[String] = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
		var weekday: int = Time.get_date_dict_from_system().get("weekday", 0)
		date_label.text = "%d月%d日 %s" % [date.get("month", 1), date.get("day", 1), weekdays[weekday]]


func _do_login(player_name: String) -> void:
	var tw: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(login_button, "scale", Vector2(0.95, 0.95), 0.08)
	tw.tween_property(login_button, "scale", Vector2.ONE, 0.1)
	tw.tween_callback(func() -> void: _show_mode_select(player_name, true))


func _create_mode_select_panel() -> void:
	var parent := new_user_panel.get_parent()
	if parent == null:
		return
	_mode_select_panel = VBoxContainer.new()
	_mode_select_panel.name = "ModeSelectPanel"
	_mode_select_panel.visible = false
	_mode_select_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mode_select_panel.add_theme_constant_override("separation", 14)
	parent.add_child(_mode_select_panel)
	parent.move_child(_mode_select_panel, user_list.get_index() + 1)

	var title := Label.new()
	title.text = "选择入口"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_mode_select_panel.add_child(title)

	var story_button := _create_mode_button("故事模式")
	story_button.pressed.connect(func() -> void: _confirm_mode(MODE_STORY))
	_mode_select_panel.add_child(story_button)

	var free_button := _create_mode_button("自由模式")
	free_button.pressed.connect(func() -> void: _confirm_mode(MODE_FREE))
	_mode_select_panel.add_child(free_button)


func _create_mode_info_panel() -> void:
	_mode_info_panel = PanelContainer.new()
	_mode_info_panel.name = "ModeInfoPanel"
	_mode_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_info_panel.custom_minimum_size = MODE_INFO_PANEL_SIZE
	_mode_info_panel.anchor_left = 1.0
	_mode_info_panel.anchor_right = 1.0
	_mode_info_panel.anchor_top = 0.5
	_mode_info_panel.anchor_bottom = 0.5
	_mode_info_panel.offset_left = -MODE_INFO_PANEL_RIGHT_MARGIN - MODE_INFO_PANEL_SIZE.x
	_mode_info_panel.offset_right = -MODE_INFO_PANEL_RIGHT_MARGIN
	_mode_info_panel.offset_top = -MODE_INFO_PANEL_SIZE.y * 0.5
	_mode_info_panel.offset_bottom = MODE_INFO_PANEL_SIZE.y * 0.5

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.88, 0.94, 1.0, 0.22)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(1, 1, 1, 0.42)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.shadow_color = Color(0.08, 0.16, 0.28, 0.18)
	panel_style.shadow_size = 18
	panel_style.shadow_offset = Vector2(0, 8)
	_mode_info_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_mode_info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	_mode_info_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := Label.new()
	title.text = "入口说明"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	box.add_child(title)

	_add_mode_info_section(
		box,
		"故事模式",
		"从相遇的第一天开始，和林夏一起准备帧语大赛；日程、对话和桌面会跟着剧情推进。",
		Color(0.72, 0.88, 1.0, 0.95)
	)
	_add_mode_info_section(
		box,
		"自由模式",
		"跳过剧情节奏，直接进入桌面；自由聊天、外出、打工、购物，也可以制作和试玩 AVG。",
		Color(1.0, 0.84, 0.62, 0.95)
	)

	var tools := Label.new()
	tools.text = "自由模式开放创作工具：Scene Editor / Project Manager / Story Project Manager / Game Previewer / File Manager"
	tools.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tools.add_theme_font_size_override("font_size", 14)
	tools.add_theme_color_override("font_color", Color(1, 1, 1, 0.68))
	box.add_child(tools)


func _add_mode_info_section(parent: VBoxContainer, title_text: String, body_text: String, accent_color: Color) -> void:
	var section := HBoxContainer.new()
	section.add_theme_constant_override("separation", 10)
	parent.add_child(section)

	var marker := ColorRect.new()
	marker.color = accent_color
	marker.custom_minimum_size = Vector2(5, 52)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	section.add_child(marker)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 4)
	section.add_child(text_box)

	var heading := Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	text_box.add_child(heading)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	text_box.add_child(body)


func _create_mode_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(360, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 22)
	_setup_button_animation(btn)
	return btn


func _show_mode_select(player_name: String, is_new_game: bool) -> void:
	_mode_player_name = player_name
	_mode_is_new_game = is_new_game
	user_list.visible = false
	new_user_panel.visible = false
	new_game_button.visible = false
	back_button.visible = true
	if _mode_select_panel == null:
		_confirm_mode(MODE_STORY)
		return
	_mode_select_panel.visible = true
	_mode_select_panel.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(_mode_select_panel, "modulate:a", 1.0, PANEL_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _confirm_mode(play_mode: String) -> void:
	login_requested.emit(_mode_player_name, _mode_is_new_game, play_mode)


func _create_status_label() -> void:
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	new_user_panel.add_child(_status_label)
	# 将状态标签移到 NameInput 后面
	new_user_panel.move_child(_status_label, name_input.get_index() + 1)


func _set_status(text: String, color: Color = Color(1, 1, 1, 0.6)) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_label.visible = not text.is_empty()


func _ensure_review_service() -> void:
	var config_mgr := AIConfigManager.get_instance()
	var config: Dictionary = config_mgr.get_config_for_role("input_guard")
	if config.is_empty():
		_review_enabled = false
		return

	_review_service = AIServiceClass.new()
	if not config_mgr.apply_to_service(_review_service, "input_guard"):
		_review_enabled = false
		return

	_review_service.default_temperature = 0.3
	_review_service.request_completed.connect(_on_review_completed)
	_review_service.request_failed.connect(_on_review_failed)
	add_child(_review_service)
	_review_enabled = true


func _submit_with_review(player_name: String) -> void:
	login_button.disabled = true
	login_button.text = "审核中..."
	name_input.editable = false
	_set_status("正在审核网名...", Color(1, 1, 1, 0.5))

	var messages: Array = [
		{"role": "system", "content": _resolve_prompt(REVIEW_PROMPT_KEY, REVIEW_SYSTEM_FALLBACK)},
		{"role": "user", "content": "网名：%s" % player_name},
	]
	_pending_review_id = _review_service.chat(messages, {"temperature": 0.3})


func _on_review_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_review_id:
		return
	_pending_review_id = ""

	var content: String = ""
	var choices: Array = response.get("choices", [])
	if choices.size() > 0:
		content = str(choices[0].get("message", {}).get("content", ""))

	var clean := content.strip_edges()
	if clean.begins_with("```"):
		var first_newline := clean.find("\n")
		if first_newline >= 0:
			clean = clean.substr(first_newline + 1)
		if clean.ends_with("```"):
			clean = clean.substr(0, clean.length() - 3).strip_edges()

	var json := JSON.new()
	if json.parse(clean) != OK or not (json.data is Dictionary):
		# 解析失败，直接通过
		_finish_review(name_input.text.strip_edges())
		return

	var result: Dictionary = json.data
	if not bool(result.get("approved", true)):
		_set_status("网名不合适：%s" % str(result.get("reason", "请换一个")), Color(1.0, 0.4, 0.4))
		login_button.disabled = false
		login_button.text = "登 录"
		name_input.editable = true
		name_input.grab_focus()
		return

	var final_name: String = str(result.get("normalized_name", name_input.text.strip_edges()))
	if final_name.is_empty():
		final_name = name_input.text.strip_edges()
	name_input.text = final_name
	_finish_review(final_name)


func _on_review_failed(request_id: String, _error: String, _error_code: int) -> void:
	if request_id != _pending_review_id:
		return
	_pending_review_id = ""
	# 审核失败，直接通过
	_finish_review(name_input.text.strip_edges())


func _finish_review(player_name: String) -> void:
	_set_status("")
	login_button.text = "登 录"
	name_input.editable = true
	_do_login(player_name)


func _resolve_prompt(prompt_key: String, fallback: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_method("resolve"):
		if pm.has_prompt(prompt_key):
			var resolved := str(pm.resolve(prompt_key)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return fallback
