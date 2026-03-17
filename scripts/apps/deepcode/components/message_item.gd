extends MarginContainer

@onready var author_label: Label = %AuthorLabel
@onready var blocks_container: VBoxContainer = %BlocksContainer
@onready var separator: HSeparator = %Separator


func set_author(role_name: String) -> void:
	if role_name == "user":
		author_label.text = "你"
		author_label.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_PRIMARY)
	else:
		author_label.text = "DeepCode"
		author_label.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_ACCENT)

	# Subtle separator line
	if separator:
		var sep_style := StyleBoxFlat.new()
		sep_style.bg_color = DeepCodeTheme.COLOR_BORDER
		separator.add_theme_stylebox_override("separator", sep_style)
		separator.add_theme_constant_override("separation", 1)


func add_block(block_node: Control) -> void:
	blocks_container.add_child(block_node)
