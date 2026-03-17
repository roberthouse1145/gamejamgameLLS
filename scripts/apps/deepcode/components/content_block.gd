extends MarginContainer

@onready var rich_text_label: RichTextLabel = %RichTextLabel


func _ready() -> void:
	if rich_text_label:
		rich_text_label.add_theme_color_override("default_color", DeepCodeTheme.COLOR_TEXT_AI)
		rich_text_label.add_theme_font_size_override("normal_font_size", 15)


func set_content(text: String) -> void:
	if rich_text_label:
		rich_text_label.clear()
		rich_text_label.append_text(text)


func append_text(text: String) -> void:
	if rich_text_label:
		rich_text_label.append_text(text)
