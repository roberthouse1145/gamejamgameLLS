class_name SettingsPanel extends VBoxContainer
## 设置面板 - 作为 PseudoWindow 的内容显示

const LABEL_FONT_SIZE: int = 20
const VALUE_FONT_SIZE: int = 18
const SECTION_FONT_SIZE: int = 22
const TEXT_COLOR: Color = Color("#1A1D27")
const TEXT_DIM: Color = Color("#6B7086")
const ACCENT: Color = Color("#4A7CFF")
const BG_COLOR: Color = Color("#FFFFFF")

var _sfx_slider: HSlider
var _bgm_slider: HSlider
var _audio_manager: Node


func _ready() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	_build_ui()


func _build_ui() -> void:
	add_theme_constant_override("separation", 16)

	# 背景
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	bg.content_margin_left = 32
	bg.content_margin_right = 32
	bg.content_margin_top = 28
	bg.content_margin_bottom = 28
	var panel_wrap := PanelContainer.new()
	panel_wrap.add_theme_stylebox_override("panel", bg)
	panel_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(panel_wrap)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 20)
	panel_wrap.add_child(inner)

	# --- 音频设置 ---
	_add_section_label("🔊 音频", inner)

	_sfx_slider = _add_slider_row("音效音量", inner, -20.0, 6.0, 0.0)
	_bgm_slider = _add_slider_row("音乐音量", inner, -20.0, 6.0, 0.0)

	if _audio_manager:
		_sfx_slider.value = _audio_manager.sfx_volume_db
		_bgm_slider.value = _audio_manager.bgm_volume_db
		_sfx_slider.value_changed.connect(func(val: float) -> void:
			_audio_manager.sfx_volume_db = val
		)
		_bgm_slider.value_changed.connect(func(val: float) -> void:
			_audio_manager.bgm_volume_db = val
		)

	# --- 分隔 ---
	var sep := HSeparator.new()
	inner.add_child(sep)

	# --- 关于 ---
	_add_section_label("ℹ 关于", inner)
	var about_label := Label.new()
	about_label.text = "LLM AI 游戏 + 虚拟 AVG 引擎\nVersion 0.1.0"
	about_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	about_label.add_theme_color_override("font_color", TEXT_DIM)
	inner.add_child(about_label)


func _add_section_label(text: String, parent: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)
	return label


func _add_slider_row(label_text: String, parent: Control, min_val: float, max_val: float, default_val: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120.0
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.5
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 200.0
	slider.custom_minimum_size.y = 32.0
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = str(default_val) + " dB"
	value_label.custom_minimum_size.x = 72.0
	value_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	value_label.add_theme_color_override("font_color", TEXT_DIM)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	slider.value_changed.connect(func(val: float) -> void:
		value_label.text = str(snapped(val, 0.5)) + " dB"
	)

	return slider
