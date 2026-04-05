extends CommandHandler
class_name CameraPanHandler
## Handler for CAMERA_PAN command
## 平移摄像机到指定归一化偏移，支持语义方向 target

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")

const TARGET_OFFSETS: Dictionary = {
	"left": Vector2(-0.15, 0.0),
	"right": Vector2(0.15, 0.0),
	"up": Vector2(0.0, -0.12),
	"top": Vector2(0.0, -0.12),
	"down": Vector2(0.0, 0.12),
	"bottom": Vector2(0.0, 0.12),
	"center": Vector2.ZERO,
}


func _init() -> void:
	super._init("CAMERA_PAN")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Pan camera to offset position")
	schema.add_param(ParamDef.string_param("target", "Direction preset: left/right/up/down/center", false, "", "", "方向目标"))
	schema.add_param(ParamDef.float_param("norm_x", "Offset X (normalized, negative=left)", false, 0.0, "X偏移"))
	schema.add_param(ParamDef.float_param("norm_y", "Offset Y (normalized, negative=up)", false, 0.0, "Y偏移"))
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var pan_offset: Vector2 = _resolve_pan_offset(params)
	var duration: float = float(params.get("duration", 1.0))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("CAMERA_PAN: no scene_runner")
	runner.camera_pan(pan_offset.x, pan_offset.y, duration)
	return CommandResultClass.ok({
		"norm_x": pan_offset.x,
		"norm_y": pan_offset.y,
		"duration": duration,
	})


func _resolve_pan_offset(params: Dictionary) -> Vector2:
	var target: String = str(params.get("target", "")).strip_edges().to_lower()
	if not target.is_empty() and TARGET_OFFSETS.has(target):
		return TARGET_OFFSETS[target]

	return Vector2(
		float(params.get("norm_x", 0.0)),
		float(params.get("norm_y", 0.0))
	)
