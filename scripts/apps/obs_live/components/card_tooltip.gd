class_name CardTooltipView extends PanelContainer
## 卡牌 hover 提示：沿用卡体配色与描边，替代 Godot 默认 TooltipPanel。

const MAX_TEXT_WIDTH: float = 520.0

const BODY_COLOR: Color = Color("#F9FCFF")
const BORDER_COLOR: Color = Color("#20283A")
const TEXT_COLOR: Color = Color("#1A2238")

@onready var _body_label: Label = %BodyLabel

var _text: String = ""


func configure(text: String) -> void:
	_text = text
	if is_node_ready():
		_apply_text()


func _ready() -> void:
	_apply_style()
	_apply_text()


func _apply_style() -> void:
	add_theme_stylebox_override("panel", _make_panel_style())
	_body_label.add_theme_color_override("font_color", TEXT_COLOR)
	_body_label.add_theme_font_size_override("font_size", 30)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size.x = MAX_TEXT_WIDTH


func _apply_text() -> void:
	_body_label.text = _text


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BODY_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18
	style.content_margin_left = 16
	style.content_margin_top = 12
	style.content_margin_right = 16
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.18, 0.22, 0.32, 0.12)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	return style
