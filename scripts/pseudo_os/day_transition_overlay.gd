extends CanvasLayer
## 天数过渡动画 —— 换天时播放全屏遮罩 + 时间轴滑动动画。

const FONT_PATH: String = "res://Assets/fonts/AlibabaHealthFont2.0CN-85B.ttf"

# ── 颜色 ──
const BG_COLOR: Color = Color(0.05, 0.05, 0.12, 0.95)
const TEXT_COLOR: Color = Color(0.92, 0.93, 0.97, 1.0)
const TRACK_COLOR: Color = Color(0.2, 0.2, 0.3, 0.5)
const FILL_COLOR: Color = Color(0.65, 0.7, 0.85, 0.9)
const MARKER_COLOR: Color = Color(0.9, 0.92, 1.0, 1.0)
const DAY_NUM_COLOR: Color = Color(0.55, 0.58, 0.68, 0.8)

# ── 时长（秒）──
const FADE_IN_DURATION: float = 0.5
const TEXT_APPEAR_DURATION: float = 0.3
const HOLD_BEFORE_SLIDE: float = 0.5
const SLIDE_DURATION: float = 0.8
const HOLD_AFTER_SLIDE: float = 0.6
const FADE_OUT_DURATION: float = 0.5

# ── 布局 ──
const TRACK_HEIGHT: float = 4.0
const TRACK_RADIUS: int = 2
const MARKER_SIZE: float = 16.0
const TIMELINE_Y_RATIO: float = 0.72
const TIMELINE_WIDTH_RATIO: float = 0.4
const DAY_FONT_SIZE: int = 96
const NUM_FONT_SIZE: int = 28

## 过渡动画开始（遮罩淡入前）—— old_day, new_day
signal transition_started(old_day: int, new_day: int)
## 遮罩已完全覆盖屏幕（可安全切换场景/刷新 UI）—— new_day
signal screen_covered(new_day: int)
## 过渡动画全部结束（遮罩消失，可以开始叙事）—— new_day
signal transition_finished(new_day: int)

var _root: Control
var _bg: ColorRect
var _day_label: Label
var _timeline_track: Panel
var _timeline_fill: Panel
var _timeline_marker: Panel
var _old_day_label: Label
var _new_day_label: Label

var _font: Font
var _is_playing: bool = false
var _last_known_day: int = -1

var _track_x: float = 0.0
var _track_y: float = 0.0
var _track_width: float = 0.0


func _ready() -> void:
	layer = 100
	_font = load(FONT_PATH) as Font
	_build_ui()
	_root.visible = false

	var glm := get_node_or_null("/root/GameLoopManager")
	if glm:
		_last_known_day = glm.current_day
		glm.day_changed.connect(_on_day_changed)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "TransitionRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# 深色背景
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = BG_COLOR
	_root.add_child(_bg)

	# 中央天数文本（占上方 62%，垂直居中 → 略偏上）
	_day_label = Label.new()
	_day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_day_label.anchor_bottom = 0.62
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		_day_label.add_theme_font_override("font", _font)
	_day_label.add_theme_font_size_override("font_size", DAY_FONT_SIZE)
	_day_label.add_theme_color_override("font_color", TEXT_COLOR)
	_root.add_child(_day_label)

	# 时间轴 - 轨道
	_timeline_track = _create_styled_panel(TRACK_COLOR, TRACK_RADIUS)
	_root.add_child(_timeline_track)

	# 时间轴 - 填充条
	_timeline_fill = _create_styled_panel(FILL_COLOR, TRACK_RADIUS)
	_root.add_child(_timeline_fill)

	# 时间轴 - 圆形标记
	var marker_radius: int = int(MARKER_SIZE * 0.5)
	_timeline_marker = _create_styled_panel(MARKER_COLOR, marker_radius)
	_root.add_child(_timeline_marker)

	# 时间轴两端的天数标签
	_old_day_label = _create_num_label()
	_root.add_child(_old_day_label)
	_new_day_label = _create_num_label()
	_root.add_child(_new_day_label)


func _create_styled_panel(color: Color, radius: int) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", style)
	return p


func _create_num_label() -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", NUM_FONT_SIZE)
	lbl.add_theme_color_override("font_color", DAY_NUM_COLOR)
	lbl.size = Vector2(60, 40)
	return lbl


func _layout_timeline() -> void:
	var screen_size: Vector2 = _root.size
	if screen_size == Vector2.ZERO:
		screen_size = Vector2(1920, 1080)

	_track_width = screen_size.x * TIMELINE_WIDTH_RATIO
	_track_x = (screen_size.x - _track_width) * 0.5
	_track_y = screen_size.y * TIMELINE_Y_RATIO

	_timeline_track.position = Vector2(_track_x, _track_y)
	_timeline_track.size = Vector2(_track_width, TRACK_HEIGHT)

	_timeline_fill.position = Vector2(_track_x, _track_y)
	_timeline_fill.size = Vector2(0, TRACK_HEIGHT)

	_timeline_marker.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	_timeline_marker.position = Vector2(
		_track_x - MARKER_SIZE * 0.5,
		_track_y - (MARKER_SIZE - TRACK_HEIGHT) * 0.5
	)

	_old_day_label.position = Vector2(_track_x - 30, _track_y + TRACK_HEIGHT + 14)
	_new_day_label.position = Vector2(
		_track_x + _track_width - 30, _track_y + TRACK_HEIGHT + 14
	)


func _on_day_changed(new_day: int) -> void:
	if _is_playing:
		return
	# 仅在自然推进（+1）时播放过渡动画；载入存档 / 重置不播放
	if _last_known_day >= 1 and new_day == _last_known_day + 1:
		play_transition(_last_known_day, new_day)
	_last_known_day = new_day


func play_transition(old_day: int, new_day: int) -> void:
	_is_playing = true
	_layout_timeline()

	# ── 初始状态 ──
	_day_label.text = "第 %d 天" % old_day
	_old_day_label.text = "%d" % old_day
	_new_day_label.text = "%d" % new_day

	_root.modulate.a = 0.0
	_day_label.modulate.a = 0.0
	_timeline_track.modulate.a = 0.0
	_timeline_fill.size.x = 0.0
	_timeline_marker.modulate.a = 0.0
	_old_day_label.modulate.a = 0.0
	_new_day_label.modulate.a = 0.0

	var start_marker_x: float = _track_x - MARKER_SIZE * 0.5
	_timeline_marker.position.x = start_marker_x

	_root.visible = true
	transition_started.emit(old_day, new_day)

	# ① 淡入背景
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_IN_DURATION)
	await tw.finished

	screen_covered.emit(new_day)

	# ② 显示天数文本
	tw = create_tween()
	tw.tween_property(_day_label, "modulate:a", 1.0, TEXT_APPEAR_DURATION)
	await tw.finished

	# ③ 显示时间轴
	tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_timeline_track, "modulate:a", 1.0, 0.25)
	tw.tween_property(_timeline_marker, "modulate:a", 1.0, 0.25)
	tw.tween_property(_old_day_label, "modulate:a", 1.0, 0.25)
	tw.tween_property(_new_day_label, "modulate:a", 1.0, 0.25)
	await tw.finished

	# ④ 短暂停留
	await get_tree().create_timer(HOLD_BEFORE_SLIDE).timeout

	# ⑤ 滑动标记 + 填充条；在中间时刻切换文本
	var target_marker_x: float = _track_x + _track_width - MARKER_SIZE * 0.5
	tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_timeline_fill, "size:x", _track_width, SLIDE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_timeline_marker, "position:x", target_marker_x, SLIDE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(_swap_day_text.bind(new_day)).set_delay(SLIDE_DURATION * 0.5)
	await tw.finished

	# ⑥ 新天数停留
	await get_tree().create_timer(HOLD_AFTER_SLIDE).timeout

	# ⑦ 整体淡出
	tw = create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT_DURATION)
	await tw.finished

	_root.visible = false
	_is_playing = false
	transition_finished.emit(new_day)


func _swap_day_text(new_day: int) -> void:
	var tw := create_tween()
	tw.tween_property(_day_label, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func() -> void: _day_label.text = "第 %d 天" % new_day)
	tw.tween_property(_day_label, "modulate:a", 1.0, 0.12)
