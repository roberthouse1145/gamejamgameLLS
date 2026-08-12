class_name TimeStatusBar
extends PseudoWindow
## 可拖拽的桌面状态挂件。视觉状态只映射 GameState 权威数据。

const TIME_SLOT_NAMES: Array[String] = ["上午", "下午", "晚上"]
const DANGER_THRESHOLD: int = 80
const NORMAL_VALUE_COLOR: Color = Color(0.055, 0.06, 0.08, 1)
const DANGER_VALUE_COLOR: Color = Color(0.91, 0.13, 0.17, 1)
const TIME_TEXTURES: Array[Texture2D] = [
	preload("res://Assets/images/ui/time_status/time_morning.png"),
	preload("res://Assets/images/ui/time_status/time_afternoon.png"),
	preload("res://Assets/images/ui/time_status/time_night.png"),
]

@onready var day_label: Label = %DayLabel
@onready var time_image_current: TextureRect = %TimeImageCurrent
@onready var time_image_next: TextureRect = %TimeImageNext
@onready var time_slot_label: Label = %TimeSlotLabel
@onready var time_dots: Array[PanelContainer] = [
	%MorningDot,
	%AfternoonDot,
	%NightDot,
]
@onready var fans_value: Label = %FansValue
@onready var money_value: Label = %MoneyValue
@onready var stress_value: Label = %StressValue
@onready var stress_icon: TextureRect = %StressIcon
@onready var otaku_desire_value: Label = %OtakuDesireValue
@onready var otaku_desire_icon: TextureRect = %OtakuDesireIcon
@onready var loneliness_value: Label = %LonelinessValue
@onready var loneliness_icon: TextureRect = %LonelinessIcon

var _displayed_day: int = -1
var _displayed_slot: int = -1
var _time_transition: Tween
var _last_attribute_values: Dictionary = {}
var _danger_shake_tweens: Dictionary = {}


func _ready() -> void:
	super._ready()
	window_title = "今日状态"
	resizable = false
	min_size = size
	max_size = size
	_hide_window_actions()
	time_image_current.resized.connect(_update_time_clip_geometry)
	_update_time_clip_geometry.call_deferred()
	_connect_game_state_signals()
	_refresh_all()


func _hide_window_actions() -> void:
	set_close_locked(true)
	set_minimize_locked(true)
	if minimize_button:
		minimize_button.hide()
	if maximize_button:
		maximize_button.hide()
	if close_button:
		close_button.hide()


func _update_time_clip_geometry() -> void:
	var clip_material: ShaderMaterial = time_image_current.material as ShaderMaterial
	if clip_material == null:
		return
	clip_material.set_shader_parameter("rect_size", time_image_current.size)


func _connect_game_state_signals() -> void:
	GameState.attribute_changed.connect(_on_attribute_changed)
	GameState.money_changed.connect(_on_money_changed)
	GameState.fans_changed.connect(_on_fans_changed)
	GameState.day_changed.connect(_on_day_changed)
	GameState.time_slot_changed.connect(_on_time_slot_changed)
	GameState.state_loaded.connect(_refresh_all)


func _refresh_all() -> void:
	_update_day(GameState.day)
	_update_time_slot(GameState.time_slot)
	_on_money_changed(GameState.money)
	_on_fans_changed(GameState.fans)
	_update_attribute(GameState.ATTR_STRESS, GameState.stress)
	_update_attribute(GameState.ATTR_OTAKU_DESIRE, GameState.otaku_desire)
	_update_attribute(GameState.ATTR_LONELINESS, GameState.loneliness)


func _on_attribute_changed(attr_name: String, value: int) -> void:
	_update_attribute(attr_name, value)


func _update_attribute(attr_name: String, value: int) -> void:
	var normalized_value: int = clampi(value, 0, 100)
	var value_label: Label
	var icon: TextureRect
	match attr_name:
		GameState.ATTR_STRESS:
			value_label = stress_value
			icon = stress_icon
		GameState.ATTR_OTAKU_DESIRE:
			value_label = otaku_desire_value
			icon = otaku_desire_icon
		GameState.ATTR_LONELINESS:
			value_label = loneliness_value
			icon = loneliness_icon
		_:
			return

	value_label.text = "%d%%" % normalized_value
	var is_dangerous: bool = normalized_value > DANGER_THRESHOLD
	value_label.add_theme_color_override("font_color", DANGER_VALUE_COLOR if is_dangerous else NORMAL_VALUE_COLOR)
	var previous_value: int = int(_last_attribute_values.get(attr_name, normalized_value))
	_last_attribute_values[attr_name] = normalized_value
	if is_dangerous:
		_ensure_value_shake(value_label)
	else:
		_stop_value_shake(value_label)
	if previous_value == normalized_value:
		return

	_pulse_control(icon)


func _ensure_value_shake(value_label: Label) -> void:
	var control_id: int = value_label.get_instance_id()
	var running_tween: Variant = _danger_shake_tweens.get(control_id)
	if running_tween is Tween and running_tween.is_valid():
		return
	value_label.position = Vector2.ZERO
	var shake_tween: Tween = create_tween()
	shake_tween.set_loops()
	_danger_shake_tweens[control_id] = shake_tween
	shake_tween.tween_property(value_label, "position:x", -4.0, 0.055)
	shake_tween.tween_property(value_label, "position:x", 4.0, 0.075)
	shake_tween.tween_property(value_label, "position:x", -3.0, 0.065)
	shake_tween.tween_property(value_label, "position:x", 3.0, 0.065)
	shake_tween.tween_property(value_label, "position:x", 0.0, 0.07)


func _stop_value_shake(value_label: Label) -> void:
	var control_id: int = value_label.get_instance_id()
	var running_tween: Variant = _danger_shake_tweens.get(control_id)
	if running_tween is Tween and running_tween.is_valid():
		running_tween.kill()
	_danger_shake_tweens.erase(control_id)
	value_label.position = Vector2.ZERO


func _on_money_changed(value: int) -> void:
	money_value.text = _format_integer(value)


func _on_fans_changed(value: int) -> void:
	fans_value.text = _format_integer(maxi(value, 0))


func _on_day_changed(value: int) -> void:
	_update_day(value)
	# 跨日时 GameState 同时回到上午，只发 day_changed。
	_update_time_slot(GameState.time_slot)


func _update_day(value: int) -> void:
	var safe_day: int = maxi(value, 1)
	day_label.text = "第 %d 天" % safe_day
	if _displayed_day >= 0 and _displayed_day != safe_day:
		_pulse_control(day_label, 1.04)
	_displayed_day = safe_day


func _on_time_slot_changed(value: int) -> void:
	_update_time_slot(value)


func _update_time_slot(value: int) -> void:
	var slot_index: int = clampi(value, 0, TIME_SLOT_NAMES.size() - 1)
	_update_time_text(slot_index)
	if _displayed_slot < 0:
		_displayed_slot = slot_index
		time_image_current.texture = TIME_TEXTURES[slot_index]
		time_image_next.texture = TIME_TEXTURES[slot_index]
		return
	if _displayed_slot == slot_index:
		return

	if _time_transition and _time_transition.is_valid():
		_time_transition.kill()
	time_image_current.position = Vector2.ZERO
	time_image_current.modulate = Color.WHITE
	time_image_next.texture = TIME_TEXTURES[slot_index]
	time_image_next.position = Vector2(52.0, 0.0)
	time_image_next.modulate = Color(1, 1, 1, 0)

	_time_transition = create_tween()
	_time_transition.set_parallel(true)
	_time_transition.tween_property(time_image_current, "position:x", -52.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_time_transition.tween_property(time_image_current, "modulate:a", 0.0, 0.18)
	_time_transition.tween_property(time_image_next, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_time_transition.tween_property(time_image_next, "modulate:a", 1.0, 0.22)
	_time_transition.chain().tween_callback(_commit_time_texture.bind(slot_index))
	_displayed_slot = slot_index


func _update_time_text(slot_index: int) -> void:
	time_slot_label.text = TIME_SLOT_NAMES[slot_index]
	for index: int in range(time_dots.size()):
		var dot: PanelContainer = time_dots[index]
		dot.modulate = Color.WHITE if index == slot_index else Color(1, 1, 1, 0.35)


func _commit_time_texture(slot_index: int) -> void:
	time_image_current.texture = TIME_TEXTURES[slot_index]
	time_image_current.position = Vector2.ZERO
	time_image_current.modulate = Color.WHITE
	time_image_next.position = Vector2.ZERO
	time_image_next.modulate = Color(1, 1, 1, 0)


func _pulse_control(control: Control, peak_scale: float = 1.06) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE
	var tween: Tween = create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * peak_scale, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _format_integer(value: int) -> String:
	var is_negative: bool = value < 0
	var digits: String = str(absi(value))
	var formatted: String = ""
	var cursor: int = digits.length()
	while cursor > 3:
		formatted = ",%s%s" % [digits.substr(cursor - 3, 3), formatted]
		cursor -= 3
	formatted = "%s%s" % [digits.left(cursor), formatted]
	return "-%s" % formatted if is_negative else formatted
