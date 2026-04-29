class_name HomeApp
extends Control

const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")
const UIIconLibraryClass = preload("res://scripts/ui/ui_icon_library.gd")

## Sleep App — 结束一天的唯一入口
## 玩家点击「睡觉」后，HomeActivityManager 执行 rest 流程，推进到次日。

const COLOR_BG := Color("#161E38")
const COLOR_PANEL := Color(0.12, 0.16, 0.28, 0.8)
const COLOR_BORDER := Color(0.35, 0.44, 0.65, 0.3)
const COLOR_TITLE := Color("#FFFFFF")
const COLOR_TEXT := Color("#C4D0F0")
const COLOR_MUTED := Color("#8392BA")
const COLOR_ACTION := Color("#6B88E8")
const COLOR_ACTION_HOVER := Color("#8EA3F0")
const COLOR_DISABLED := Color("#353E60")
const COLOR_TRANSIT_FILL := Color("#6B88E8")
const COLOR_STRESS_LOW := Color("#80D8B8")
const COLOR_STRESS_MID := Color("#E9C46A")
const COLOR_STRESS_HIGH := Color("#F07178")
const TRANSIT_STAGES: Array[String] = [
	"正在入睡...",
	"进入梦乡...",
	"好梦..."
]

var _home_manager: Node = null
var _game_loop: Node = null
var _game_manager: Node = null

var _status_label: Label = null
var _stress_label: Label = null
var _stress_bar: ProgressBar = null
var _sleep_button: Button = null
var _sleep_preview_hint: Node = null
var _message_label: Label = null
var _progress_bar: ProgressBar = null
var _button_tween: Tween = null
var _active_session_id: String = ""
var _transit_progress: float = 0.0

var _transit_window: Control = null
var _transit_title_label: Label = null
var _transit_stage_label: Label = null
var _transit_eta_label: Label = null
var _transit_progress_bar: ProgressBar = null


func _ready() -> void:
	_home_manager = get_node_or_null("/root/HomeActivityManager")
	_game_loop = get_node_or_null("/root/GameLoopManager")
	_game_manager = get_node_or_null("/root/GameManager")

	_build_ui()
	_connect_signals()
	_refresh()


func _build_ui() -> void:
	var background := TextureRect.new()
	var grad_tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color("#1E274A"), Color("#0B0E1B")])
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	background.texture = grad_tex
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_PANEL
	card_style.border_color = COLOR_BORDER
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(32)
	card_style.content_margin_left = 40
	card_style.content_margin_right = 40
	card_style.content_margin_top = 40
	card_style.content_margin_bottom = 40
	card_style.shadow_color = Color(0, 0, 0, 0.3)
	card_style.shadow_size = 30
	card_style.shadow_offset = Vector2(0, 12)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var sleep_tex := load("res://Assets/images/stamps/stamp05_02.png") as Texture2D
	if sleep_tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = sleep_tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(160, 160)
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(tex_rect)
		
		var img_spacer := Control.new()
		img_spacer.custom_minimum_size = Vector2(0, 4)
		vbox.add_child(img_spacer)

	var title := Label.new()
	title.text = "Good Night"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_status_label)

	_stress_label = Label.new()
	_stress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stress_label.add_theme_font_size_override("font_size", 15)
	_stress_label.add_theme_color_override("font_color", COLOR_MUTED)
	vbox.add_child(_stress_label)

	_stress_bar = ProgressBar.new()
	_stress_bar.min_value = 0.0
	_stress_bar.max_value = 100.0
	_stress_bar.value = 0.0
	_stress_bar.show_percentage = false
	_stress_bar.custom_minimum_size = Vector2(0, 7)
	_stress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stress_bar.add_theme_stylebox_override("background", _make_meter_style(Color("#263052"), 4))
	_stress_bar.add_theme_stylebox_override("fill", _make_meter_style(COLOR_STRESS_LOW, 4))
	vbox.add_child(_stress_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	_sleep_button = Button.new()
	_sleep_button.text = "入睡"
	_sleep_button.focus_mode = Control.FOCUS_NONE
	_sleep_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sleep_button.custom_minimum_size.y = 54
	_sleep_button.add_theme_font_size_override("font_size", 20)
	_apply_button_style(_sleep_button, true)
	_sleep_button.mouse_entered.connect(_on_sleep_button_hovered.bind(true))
	_sleep_button.mouse_exited.connect(_on_sleep_button_hovered.bind(false))
	_sleep_button.pressed.connect(_on_sleep_pressed)
	_sleep_preview_hint = ActivityPreviewHintClass.new()
	_sleep_button.add_child(_sleep_preview_hint)
	_sleep_preview_hint.set_payload_resolver(Callable(self, "_build_sleep_preview_payload"))
	vbox.add_child(_sleep_button)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0, 6)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pg_bg := StyleBoxFlat.new()
	pg_bg.bg_color = Color("#1E274A")
	pg_bg.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("background", pg_bg)
	var pg_fill := StyleBoxFlat.new()
	pg_fill.bg_color = COLOR_ACTION
	pg_fill.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("fill", pg_fill)
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_font_size_override("font_size", 14)
	_message_label.add_theme_color_override("font_color", COLOR_MUTED)
	vbox.add_child(_message_label)


func _connect_signals() -> void:
	if _game_loop != null:
		if _game_loop.has_signal("ap_changed"):
			_game_loop.ap_changed.connect(func(_current: Variant, _max_ap: Variant) -> void: _refresh())
		if _game_loop.has_signal("phase_changed"):
			_game_loop.phase_changed.connect(func(_p: Variant) -> void: _refresh())
		if _game_loop.has_signal("day_changed"):
			_game_loop.day_changed.connect(func(_d: Variant) -> void: _refresh())
	if _home_manager != null:
		if _home_manager.has_signal("activity_completed"):
			_home_manager.activity_completed.connect(_on_activity_completed)
		if _home_manager.has_signal("session_failed"):
			_home_manager.session_failed.connect(_on_session_failed)
		if _home_manager.has_signal("progress_phase_started"):
			_home_manager.progress_phase_started.connect(_on_transit_started)
		if _home_manager.has_signal("progress_updated"):
			_home_manager.progress_updated.connect(_on_rest_progress_updated)


func _refresh() -> void:
	if _game_loop == null:
		_status_label.text = "系统未就绪"
		_sleep_button.disabled = true
		return

	var phase_name := _format_phase()
	var day := int(_game_loop.get("current_day"))
	_status_label.text = "Day %d · %s" % [day, phase_name]

	var stress: int = 0
	if _game_manager != null:
		stress = int(_game_manager.get("stress"))
	if stress >= 70:
		_stress_label.text = "压力偏高（%d），好好休息一下吧" % stress
	elif stress >= 40:
		_stress_label.text = "压力 %d" % stress
	else:
		_stress_label.text = "状态不错，压力 %d" % stress
	_update_stress_meter(stress)

	var availability: Dictionary = _get_rest_availability()
	var busy: bool = _home_manager != null and _home_manager.has_method("has_any_pending_sessions") and _home_manager.has_any_pending_sessions()
	var enabled: bool = bool(availability.get("enabled", false)) and not busy
	var disabled_reason: String = str(availability.get("reason", "")).strip_edges()
	_sleep_button.disabled = not enabled
	_apply_button_style(_sleep_button, enabled)
	if busy:
		_sleep_button.text = "正在入睡..."
	elif enabled:
		_sleep_button.text = "进入梦乡"
	else:
		_sleep_button.text = "暂时不能休息"

	if busy:
		_message_label.text = "休息一下，恢复精力"
	elif not disabled_reason.is_empty():
		_message_label.text = disabled_reason
	else:
		_message_label.text = "休息一下，恢复精力"


func _on_sleep_pressed() -> void:
	if _home_manager == null or not _home_manager.has_method("begin_rest"):
		_message_label.text = "无法执行：系统未就绪"
		return

	var result: Dictionary = _home_manager.begin_rest()
	if not bool(result.get("success", false)):
		_message_label.text = str(result.get("error", "无法休息"))
	else:
		_active_session_id = str(result.get("session_id", ""))
	_refresh()


func _on_activity_completed(_activity_id: String, payload: Dictionary) -> void:
	_progress_bar.visible = false
	_progress_bar.value = 0.0
	_active_session_id = ""
	_transit_progress = 0.0
	_refresh()
	_message_label.text = _build_completion_message(payload)


func _on_session_failed(error_message: String) -> void:
	_progress_bar.visible = false
	_progress_bar.value = 0.0
	_active_session_id = ""
	_message_label.text = "失败: %s" % error_message
	_refresh()


func _on_transit_started(session_id: String, _payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_transit_progress = 0.0


func _on_rest_progress_updated(session_id: String, progress: float, _scene_ready: bool = false) -> void:
	if session_id != _active_session_id:
		return
	_transit_progress = progress
	_progress_bar.visible = true
	_progress_bar.value = progress * 100.0


func _process(_delta: float) -> void:
	if _active_session_id.is_empty() or _transit_window == null or not is_instance_valid(_transit_window):
		set_process(false)
		return
	if _transit_stage_label != null:
		var stage_index := mini(int(floor(_transit_progress * float(TRANSIT_STAGES.size()))), TRANSIT_STAGES.size() - 1)
		_transit_stage_label.text = TRANSIT_STAGES[stage_index]
	if _transit_eta_label != null:
		_transit_eta_label.text = "即将醒来" if _transit_progress > 0.9 else "睡眠中..."


func _show_transit_window() -> void:
	_close_transit_window()

	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = null
	if app_manager != null:
		window_manager = app_manager.get("window_manager")
	if window_manager == null or not window_manager.has_method("create_window"):
		return

	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color("#1A1F3A")
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
	_transit_title_label.text = "Good Night"
	_transit_title_label.add_theme_font_size_override("font_size", 22)
	_transit_title_label.add_theme_color_override("font_color", COLOR_TITLE)
	box.add_child(_transit_title_label)

	_transit_stage_label = Label.new()
	_transit_stage_label.text = TRANSIT_STAGES[0]
	_transit_stage_label.add_theme_font_size_override("font_size", 14)
	_transit_stage_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(_transit_stage_label)

	_transit_progress_bar = ProgressBar.new()
	_transit_progress_bar.min_value = 0.0
	_transit_progress_bar.max_value = 100.0
	_transit_progress_bar.value = 0.0
	_transit_progress_bar.show_percentage = false
	_transit_progress_bar.custom_minimum_size = Vector2(0, 6)
	var progress_bg_style := StyleBoxFlat.new()
	progress_bg_style.bg_color = Color("#2A3158")
	progress_bg_style.corner_radius_top_left = 3
	progress_bg_style.corner_radius_top_right = 3
	progress_bg_style.corner_radius_bottom_left = 3
	progress_bg_style.corner_radius_bottom_right = 3
	_transit_progress_bar.add_theme_stylebox_override("background", progress_bg_style)
	var progress_fill_style := StyleBoxFlat.new()
	progress_fill_style.bg_color = COLOR_TRANSIT_FILL
	progress_fill_style.corner_radius_top_left = 3
	progress_fill_style.corner_radius_top_right = 3
	progress_fill_style.corner_radius_bottom_left = 3
	progress_fill_style.corner_radius_bottom_right = 3
	_transit_progress_bar.add_theme_stylebox_override("fill", progress_fill_style)
	box.add_child(_transit_progress_bar)

	var eta_hbox := HBoxContainer.new()
	box.add_child(eta_hbox)

	var eta_icon := TextureRect.new()
	eta_icon.texture = UIIconLibraryClass.get_icon("night")
	eta_icon.custom_minimum_size = Vector2(16, 16)
	eta_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	eta_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eta_icon.modulate = COLOR_ACTION
	eta_hbox.add_child(eta_icon)

	_transit_eta_label = Label.new()
	_transit_eta_label.text = "睡眠中..."
	_transit_eta_label.add_theme_font_size_override("font_size", 14)
	_transit_eta_label.add_theme_color_override("font_color", COLOR_ACTION)
	eta_hbox.add_child(_transit_eta_label)

	_transit_window = window_manager.create_window("休息", outer)
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


func _format_phase() -> String:
	if _game_loop == null:
		return "未知"
	match str(_game_loop.get_phase_name(_game_loop.time_phase)):
		"MORNING":
			return "早上"
		"AFTERNOON":
			return "下午"
		"NIGHT":
			return "晚上"
	return "未知"


func _build_completion_message(payload: Dictionary) -> String:
	var rewards: Dictionary = payload.get("rewards", {}) as Dictionary
	if rewards.is_empty():
		return "休息结束。"

	var parts: Array[String] = []
	for key in ["stress", "affection", "passion", "money", "completion", "quality", "stability", "hype"]:
		if not rewards.has(key):
			continue
		var delta: int = int(rewards.get(key, 0))
		if delta == 0:
			continue
		parts.append("%s%s" % [_get_reward_label(key), _format_signed_int(delta)])

	if parts.is_empty():
		return "休息结束。"
	return "休息结束，%s" % "，".join(parts)


func _get_reward_label(stat_name: String) -> String:
	match stat_name:
		"stress":
			return "压力"
		"affection":
			return "好感"
		"passion":
			return "激情"
		"money":
			return "金钱"
		"completion":
			return "完成度"
		"quality":
			return "质量"
		"stability":
			return "稳定"
		"hype":
			return "热度"
	return stat_name


func _format_signed_int(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)


func _build_sleep_preview_payload() -> Dictionary:
	var rewards: Dictionary = {}
	var availability: Dictionary = _get_rest_availability()
	if _home_manager != null and _home_manager.has_method("get_activity_preview_rewards"):
		rewards = _home_manager.get_activity_preview_rewards("rest")

	return {
		"title": "休息",
		"rewards": rewards,
		"text": "结束当前时段，恢复状态并推进时间。",
		"conditions": [_build_rest_condition_text()],
		"disabled_reason": str(availability.get("reason", "")).strip_edges() if not bool(availability.get("enabled", false)) else "",
	}


func _get_rest_availability() -> Dictionary:
	if _home_manager == null or not _home_manager.has_method("get_available_activities") or _game_loop == null:
		return {"enabled": false, "reason": "系统未就绪"}
	var phase_name: String = str(_game_loop.get_phase_name(_game_loop.time_phase)).strip_edges()
	var activities: Array = _home_manager.get_available_activities(phase_name)
	for activity in activities:
		if not activity is Dictionary:
			continue
		var activity_dict: Dictionary = activity
		if str(activity_dict.get("activity_id", "")).strip_edges() != "rest":
			continue
		return {
			"enabled": bool(activity_dict.get("enabled", false)),
			"reason": str(activity_dict.get("disabled_reason", "")).strip_edges(),
		}
	return {"enabled": false, "reason": "当前不可休息"}


func _apply_button_style(button: Button, enabled: bool) -> void:
	var base_color: Color = COLOR_ACTION if enabled else COLOR_DISABLED
	var hover_color: Color = COLOR_ACTION_HOVER if enabled else COLOR_DISABLED
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _make_button_style(base_color))
	button.add_theme_stylebox_override("hover", _make_button_style(hover_color))
	button.add_theme_stylebox_override("pressed", _make_button_style(hover_color.darkened(0.08)))
	button.add_theme_stylebox_override("disabled", _make_button_style(COLOR_DISABLED))


func _make_button_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(27)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _make_meter_style(bg_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(radius)
	return style


func _update_stress_meter(stress: int) -> void:
	if _stress_bar == null:
		return
	_stress_bar.value = stress
	var fill_color := COLOR_STRESS_LOW
	if stress >= 70:
		fill_color = COLOR_STRESS_HIGH
	elif stress >= 40:
		fill_color = COLOR_STRESS_MID
	_stress_bar.add_theme_stylebox_override("fill", _make_meter_style(fill_color, 4))


func _build_rest_condition_text() -> String:
	if _game_loop == null:
		return "系统未就绪"
	return "当前：第%d天 · %s" % [int(_game_loop.get("current_day")), _format_phase()]


func _on_sleep_button_hovered(is_hovered: bool) -> void:
	if _sleep_button == null or _sleep_button.disabled:
		return
	if _button_tween != null and is_instance_valid(_button_tween):
		_button_tween.kill()
	_sleep_button.pivot_offset = _sleep_button.size * 0.5
	_button_tween = create_tween()
	_button_tween.set_trans(Tween.TRANS_CUBIC)
	_button_tween.set_ease(Tween.EASE_OUT)
	_button_tween.tween_property(_sleep_button, "scale", Vector2(1.025, 1.025) if is_hovered else Vector2.ONE, 0.12)
