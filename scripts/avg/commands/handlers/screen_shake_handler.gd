extends "res://scripts/avg/commands/command_handler.gd"
class_name ScreenShakeHandler
## Handler for SCREEN_SHAKE command
## 屏幕震动效果。非阻塞 — 触发后立即继续。
## 参数:
##   intensity: 震动强度（像素偏移量）
##   duration: 震动持续时间（秒）
##   frequency: 震动频率（每秒震动次数）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SCREEN_SHAKE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Screen shake effect"
	)

	schema.add_param(ParamDef.float_param(
		"intensity",
		"Shake intensity in pixels",
		false,
		10.0,
		"强度"
	))

	schema.add_param(ParamDef.float_param(
		"duration",
		"Shake duration in seconds",
		false,
		0.5,
		"时长"
	))

	schema.add_param(ParamDef.float_param(
		"frequency",
		"Shake frequency (times per second)",
		false,
		20.0,
		"频率"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var intensity: float = _get_param(command, "intensity", 10.0)
	var duration: float = _get_param(command, "duration", 0.5)
	var frequency: float = _get_param(command, "frequency", 20.0)

	if context.scene_runner != null and context.scene_runner.has_method("screen_shake"):
		context.scene_runner.screen_shake(intensity, duration, frequency)

	return CommandResultClass.ok({
		"intensity": intensity,
		"duration": duration,
		"frequency": frequency,
	})
