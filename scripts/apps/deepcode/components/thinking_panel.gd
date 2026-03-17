extends MarginContainer

var _is_expanded: bool = true

@onready var header_button: Button = %HeaderButton
@onready var content_container: MarginContainer = %ContentContainer
@onready var rich_text_label: RichTextLabel = %RichTextLabel
@onready var panel_container: PanelContainer = $PanelContainer


func _ready() -> void:
	header_button.toggled.connect(_on_header_toggled)

	# Apply theme
	panel_container.add_theme_stylebox_override("panel", DeepCodeTheme.get_thinking_panel_style())
	header_button.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_MUTED)
	header_button.add_theme_color_override("font_hover_color", DeepCodeTheme.COLOR_TEXT_SECONDARY)
	header_button.add_theme_font_size_override("font_size", 13)

	if rich_text_label:
		rich_text_label.add_theme_color_override("default_color", DeepCodeTheme.COLOR_TEXT_SECONDARY)
		rich_text_label.add_theme_font_size_override("normal_font_size", 14)

	set_expanded(true)


func set_content(text: String) -> void:
	if rich_text_label:
		rich_text_label.clear()
		rich_text_label.append_text(text)


func append_text(text: String) -> void:
	if rich_text_label:
		rich_text_label.append_text(text)


func set_expanded(expanded: bool) -> void:
	_is_expanded = expanded
	header_button.set_pressed_no_signal(expanded)
	content_container.visible = expanded
	header_button.text = "▼ 思考中..." if expanded else "▶ 思考过程"


func _on_header_toggled(toggled_on: bool) -> void:
	set_expanded(toggled_on)
