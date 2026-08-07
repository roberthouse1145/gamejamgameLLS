class_name EntranceOverlay extends Control
## 确认开播后的入场动画与加载等待：固定短动画后停留在加载态，
## 直到首拍内容就绪（set_ready）才发出 entrance_finished。

signal entrance_finished()

const MIN_DURATION: float = 2.0
const STATUS_LINES: Array[String] = [
	"正在连接直播间…",
	"推流已建立，正在同步节目单…",
	"观众正在进入…",
]

const COLOR_BG: Color = Color("#F0F4F8")
const COLOR_TEXT: Color = Color("#1A2238")
const COLOR_ACCENT: Color = Color("#E5486D")

var _elapsed: float = 0.0
var _content_ready: bool = false
var _playing: bool = false
var _finished_emitted: bool = false
var _status_label: Label = null
var _dots_label: Label = null
var _title_label: Label = null


func _ready() -> void:
	visible = false
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 36)
	center.add_child(column)
	_dots_label = _make_label("", 54, COLOR_ACCENT)
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_dots_label)
	_status_label = _make_label("", 32, COLOR_TEXT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)
	_title_label = _make_label("", 26, Color("#8793A5"))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)


func play(stream_title: String) -> void:
	_elapsed = 0.0
	_content_ready = false
	_playing = true
	_finished_emitted = false
	_title_label.text = "《%s》" % stream_title
	_status_label.text = STATUS_LINES[0]
	visible = true
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)


func set_ready() -> void:
	_content_ready = true


func _process(delta: float) -> void:
	if not _playing or _finished_emitted:
		return
	_elapsed += delta
	var status_index: int = clampi(int(_elapsed / 0.8), 0, STATUS_LINES.size() - 1)
	_status_label.text = STATUS_LINES[status_index]
	var dot_count: int = int(_elapsed * 3.0) % 4
	_dots_label.text = "● ".repeat(dot_count + 1)
	if _elapsed >= MIN_DURATION and _content_ready:
		_finished_emitted = true
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.35)
		tween.tween_callback(func() -> void: visible = false)
		entrance_finished.emit()


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
