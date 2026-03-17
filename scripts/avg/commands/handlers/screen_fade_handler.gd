extends "res://scripts/avg/commands/command_handler.gd"
class_name ScreenFadeHandler
## Handler for SCREEN_FADE command
## 屏幕淡入淡出转场效果。阻塞命令 — 等待淡入淡出完成后继续。
## 参数:
##   direction: "in"(淡入，从颜色到透明) / "out"(淡出，从透明到颜色)
##   color: 淡入淡出颜色（默认黑色）
##   duration: 持续时间（秒）
##   transition: 转场类型（fade, dissolve, wipe_left, wipe_right, wipe_up, wipe_down）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SCREEN_FADE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Screen fade in/out transition"
	)

	schema.add_param(ParamDef.choices_param(
		"direction",
		["in", "out"],
		"Fade direction: 'out' = screen to color, 'in' = color to screen",
		true,
		"out",
		"方向"
	))

	schema.add_param(ParamDef.color_param(
		"color",
		"Fade color",
		false,
		Color.BLACK,
		"颜色"
	))

	schema.add_param(ParamDef.float_param(
		"duration",
		"Fade duration in seconds",
		false,
		1.0,
		"时长"
	))

	schema.add_param(ParamDef.choices_param(
		"transition",
		["fade", "dissolve", "wipe_left", "wipe_right", "wipe_up", "wipe_down"],
		"Transition type",
		false,
		"fade",
		"转场类型"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var direction: String = _get_param(command, "direction", "out")
	var color: Color = _get_param(command, "color", Color.BLACK)
	var duration: float = _get_param(command, "duration", 1.0)
	var transition: String = _get_param(command, "transition", "fade")

	# screen_fade is now awaited directly in _handle_blocking_command
	# No need to call it here to avoid double execution

	return CommandResultClass.ok({
		"direction": direction,
		"color": color,
		"duration": duration,
		"transition": transition,
	})
