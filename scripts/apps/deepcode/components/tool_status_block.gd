extends MarginContainer

@onready var status_icon: Label = %StatusIcon
@onready var status_label: Label = %StatusLabel
@onready var panel_container: PanelContainer = $PanelContainer


func _ready() -> void:
	panel_container.add_theme_stylebox_override("panel", DeepCodeTheme.get_tool_block_style())
	if status_label:
		status_label.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_SECONDARY)
		status_label.add_theme_font_size_override("font_size", 13)
	if status_icon:
		status_icon.add_theme_font_size_override("font_size", 13)


func set_tool_info(tool_name: String, _args: Dictionary) -> void:
	status_label.text = "执行 %s..." % tool_name


func set_status(status: String, message: String = "") -> void:
	match status:
		"running":
			status_icon.text = "⚙"
			status_label.text = message if not message.is_empty() else "执行中..."
		"success":
			status_icon.text = "✓"
			status_label.text = message if not message.is_empty() else "完成"
		"error":
			status_icon.text = "✗"
			status_label.text = message if not message.is_empty() else "失败"
