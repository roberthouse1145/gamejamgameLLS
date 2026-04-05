extends CommandHandler
class_name ShowNotificationHandler
## Handler for SHOW_NOTIFICATION command
## 显示通知/提示信息。非阻塞 — 显示后自动消失。
## 参数:
##   text: 通知文本
##   duration: 显示持续时间（秒）
##   position: 显示位置 top/center/bottom

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SHOW_NOTIFICATION")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Show a notification/toast message"
	)

	schema.add_param(ParamDef.string_param(
		"text",
		"Notification text",
		true,
		"",
		"",
		"文本"
	))

	schema.add_param(ParamDef.float_param(
		"duration",
		"Display duration in seconds",
		false,
		3.0,
		"显示时长"
	))

	schema.add_param(ParamDef.choices_param(
		"position",
		["top", "center", "bottom"],
		"Notification position on screen",
		false,
		"top",
		"位置"
	))

	schema.add_param(ParamDef.int_param(
		"font_size",
		"Font size (0 = use default)",
		false,
		0,
		"字号"
	))

	schema.add_param(ParamDef.color_param(
		"color",
		"Text color",
		false,
		Color.WHITE,
		"颜色"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var text: String = _get_param(command, "text", "")
	if text.is_empty():
		return CommandResultClass.error("text is required")

	var duration: float = _get_param(command, "duration", 3.0)
	var pos: String = _get_param(command, "position", "top")
	var font_size: int = _get_param(command, "font_size", 0)
	var color: Color = _get_param(command, "color", Color.WHITE)

	if context.scene_runner != null and context.scene_runner.has_method("show_notification"):
		context.scene_runner.show_notification(text, duration, pos, font_size, color)

	return CommandResultClass.ok({
		"text": text,
		"duration": duration,
		"position": pos,
	})
