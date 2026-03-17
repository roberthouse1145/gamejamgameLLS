extends "res://scripts/avg/commands/command_handler.gd"
class_name CameraZoomHandler
## Handler for CAMERA_ZOOM command
## 缩放摄像机，聚焦到指定归一化坐标点

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CAMERA_ZOOM")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Zoom camera to focus point")
	schema.add_param(ParamDef.float_param("zoom", "Zoom level (1.0=default, 2.0=2x)", true, 1.5, "缩放倍数"))
	schema.add_param(ParamDef.float_param("focus_x", "Focus X (0~1, 0.5=center)", false, 0.5, "焦点X"))
	schema.add_param(ParamDef.float_param("focus_y", "Focus Y (0~1, 0.5=center)", false, 0.5, "焦点Y"))
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var zoom: float = float(params.get("zoom", 1.5))
	var focus_x: float = float(params.get("focus_x", 0.5))
	var focus_y: float = float(params.get("focus_y", 0.5))
	var duration: float = float(params.get("duration", 1.0))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("CAMERA_ZOOM: no scene_runner")
	runner.camera_zoom(zoom, focus_x, focus_y, duration)
	return CommandResultClass.ok()
