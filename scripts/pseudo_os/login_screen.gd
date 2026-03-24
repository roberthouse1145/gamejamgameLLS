class_name LoginScreen extends Control
## 日式风格登录界面
## 新游戏：输入用户名 → 登录
## 继续游戏：显示已有存档用户 → 点击登录
## 右下角：设置、退出

signal login_requested(player_name: String, is_new_game: bool)
signal quit_requested
signal settings_requested

const MIN_NAME_LENGTH: int = 1
const MAX_NAME_LENGTH: int = 12
const PANEL_ANIM_DURATION: float = 0.3

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


func _ready() -> void:
	modulate.a = 0.0
	_connect_buttons()
	_update_clock()
	_check_saves()
	_fade_in()
	_setup_button_animations()


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


func _setup_button_animations() -> void:
	for btn: Button in [login_button, new_game_button, back_button, settings_button, quit_button]:
		if btn == null:
			continue
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
		hint.text = "点击继续游戏"
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
				login_requested.emit(player_name, false)
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
		# 按钮缩放后登录
		var tw: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(login_button, "scale", Vector2(0.95, 0.95), 0.08)
		tw.tween_property(login_button, "scale", Vector2.ONE, 0.1)
		tw.tween_callback(func() -> void: login_requested.emit(player_name, true))
	else:
		if not _selected_save.is_empty():
			login_requested.emit(_selected_save, false)


func _on_new_game_pressed() -> void:
	_show_new_user()


func _on_back_pressed() -> void:
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
