extends "res://scripts/avg/commands/command_handler.gd"
class_name CameraPanHandler
## Handler for CAMERA_PAN command
## 平移摄像机到指定归一化偏移

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CAMERA_PAN")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Pan camera to offset position")
	schema.add_param(ParamDef.float_param("norm_x", "Offset X (normalized, negative=left)", true, 0.0, "X偏移"))
	schema.add_param(ParamDef.float_param("norm_y", "Offset Y (normalized, negative=up)", true, 0.0, "Y偏移"))
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var norm_x: float = float(params.get("norm_x", 0.0))
	var norm_y: float = float(params.get("norm_y", 0.0))
	var duration: float = float(params.get("duration", 1.0))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("CAMERA_PAN: no scene_runner")
	runner.camera_pan(norm_x, norm_y, duration)
	return CommandResultClass.ok()
