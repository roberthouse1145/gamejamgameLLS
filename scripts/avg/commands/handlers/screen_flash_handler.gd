extends "res://scripts/avg/commands/command_handler.gd"
class_name ScreenFlashHandler
## Handler for SCREEN_FLASH command
## 屏幕闪烁效果（白闪/黑闪等）。非阻塞 — 触发后立即继续。
## 参数:
##   color: 闪烁颜色（默认白色）
##   duration: 闪烁持续时间（秒）
##   intensity: 闪烁强度 0.0-1.0

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SCREEN_FLASH")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Screen flash effect"
	)

	schema.add_param(ParamDef.color_param(
		"color",
		"Flash color",
		false,
		Color.WHITE,
		"颜色"
	))

	schema.add_param(ParamDef.float_param(
		"duration",
		"Flash duration in seconds",
		false,
		0.3,
		"时长"
	))

	schema.add_param(ParamDef.float_param(
		"intensity",
		"Flash intensity (0.0 to 1.0)",
		false,
		1.0,
		"强度"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var color: Color = _get_param(command, "color", Color.WHITE)
	var duration: float = _get_param(command, "duration", 0.3)
	var intensity: float = clampf(_get_param(command, "intensity", 1.0), 0.0, 1.0)

	if context.scene_runner != null and context.scene_runner.has_method("screen_flash"):
		context.scene_runner.screen_flash(color, duration, intensity)

	return CommandResultClass.ok({
		"color": color,
		"duration": duration,
		"intensity": intensity,
	})
