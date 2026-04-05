extends CommandHandler
class_name CameraResetHandler
## Handler for CAMERA_RESET command
## 重置摄像机到默认状态（zoom=1, offset=0）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CAMERA_RESET")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Reset camera to default state")
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var duration: float = float(params.get("duration", 1.0))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("CAMERA_RESET: no scene_runner")
	runner.camera_reset(duration)
	return CommandResultClass.ok()
