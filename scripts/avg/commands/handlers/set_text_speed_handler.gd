extends CommandHandler
class_name SetTextSpeedHandler
## Handler for SET_TEXT_SPEED command
## 设置对话框打字机速度。非阻塞，立即生效。
## 参数:
##   speed: 每秒显示字符数（0=立即显示全部）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_TEXT_SPEED")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Set dialogue typewriter speed"
	)

	schema.add_param(ParamDef.float_param(
		"speed",
		"Characters per second (0 = instant display)",
		true,
		30.0,
		"速度(字/秒)"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var speed: float = _get_param(command, "speed", 30.0)

	if context.dialog_box != null and context.dialog_box.has_method("set_override_text_speed"):
		context.dialog_box.set_override_text_speed(speed)

	return CommandResultClass.ok({"speed": speed})
