class_name EntranceOverlay extends Control
## 确认开播后的入场视频：播完或点 Skip 即结束，不再等待 LLM。

signal entrance_finished()

const COLOR_SKIP_BG: Color = Color(0.1, 0.12, 0.18, 0.72)
const COLOR_SKIP_BORDER: Color = Color("#C8D6EA")
const COLOR_SKIP_TEXT: Color = Color("#FFFFFF")

var _player: VideoStreamPlayer = null
var _skip_button: Button = null
var _playing: bool = false
var _finished_emitted: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.finished.connect(_on_video_finished)
	add_child(_player)

	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.custom_minimum_size = Vector2(140, 56)
	_skip_button.add_theme_font_size_override("font_size", 26)
	_skip_button.add_theme_color_override("font_color", COLOR_SKIP_TEXT)
	_skip_button.add_theme_stylebox_override("normal", _make_skip_style(COLOR_SKIP_BG))
	_skip_button.add_theme_stylebox_override("hover", _make_skip_style(Color(0.18, 0.22, 0.32, 0.85)))
	_skip_button.add_theme_stylebox_override("pressed", _make_skip_style(Color(0.12, 0.15, 0.22, 0.9)))
	_skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_button.offset_left = -172.0
	_skip_button.offset_top = 24.0
	_skip_button.offset_right = -24.0
	_skip_button.offset_bottom = 80.0
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)


func play(video: VideoStream) -> void:
	_playing = true
	_finished_emitted = false
	visible = true
	modulate = Color(1, 1, 1, 1)
	_skip_button.visible = true
	_skip_button.disabled = false
	if video == null:
		call_deferred("_finish")
		return
	_player.stream = video
	_player.play()


func skip() -> void:
	if not _playing or _finished_emitted:
		return
	_finish()


func _on_video_finished() -> void:
	if not _playing or _finished_emitted:
		return
	_finish()


func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_playing = false
	if _player != null:
		_player.stop()
	_skip_button.disabled = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		visible = false
		entrance_finished.emit()
	)


func _make_skip_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = COLOR_SKIP_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
