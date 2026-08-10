class_name WizardTabBar extends HBoxContainer
## 开播向导紧凑进度条：已完成的步骤可点击回跳，未达成的置灰。

signal tab_pressed(step: int)

const TAB_TITLES: Array[String] = ["素材", "剧本编排", "确认开播"]

const COLOR_CURRENT_BG: Color = Color("#496BB9")
const COLOR_DONE_BG: Color = Color("#E8F0FB")
const COLOR_TODO_BG: Color = Color("#F4F7FC")
const COLOR_CURRENT_TEXT: Color = Color("#FFFFFF")
const COLOR_DONE_TEXT: Color = Color("#3A5FA8")
const COLOR_TODO_TEXT: Color = Color("#8793A5")
const COLOR_BORDER: Color = Color("#C8D6EA")

var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	for step: int in range(TAB_TITLES.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%d  %s" % [step + 1, TAB_TITLES[step]]
		button.add_theme_font_size_override("font_size", 22)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_tab_pressed.bind(step))
		add_child(button)
		_buttons.append(button)


## current_step 当前步骤；max_step 当前可达的最远步骤（之后的置灰）。
func refresh(current_step: int, max_step: int) -> void:
	for step: int in range(_buttons.size()):
		var button: Button = _buttons[step]
		button.disabled = step > max_step or step == current_step
		var bg: Color = COLOR_TODO_BG
		var fg: Color = COLOR_TODO_TEXT
		var border: Color = COLOR_BORDER
		if step == current_step:
			bg = COLOR_CURRENT_BG
			fg = COLOR_CURRENT_TEXT
			border = COLOR_CURRENT_BG
		elif step < max_step or step < current_step:
			bg = COLOR_DONE_BG
			fg = COLOR_DONE_TEXT
		button.add_theme_stylebox_override("normal", _make_style(bg, border))
		button.add_theme_stylebox_override("hover", _make_style(bg.lightened(0.04), border))
		button.add_theme_stylebox_override("pressed", _make_style(bg.darkened(0.05), border))
		button.add_theme_stylebox_override("disabled", _make_style(COLOR_TODO_BG.darkened(0.02), COLOR_BORDER))
		button.add_theme_color_override("font_color", fg)
		button.add_theme_color_override("font_hover_color", fg)
		button.add_theme_color_override("font_pressed_color", fg)
		button.add_theme_color_override("font_disabled_color", COLOR_TODO_TEXT)


func _on_tab_pressed(step: int) -> void:
	tab_pressed.emit(step)


func _make_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style
