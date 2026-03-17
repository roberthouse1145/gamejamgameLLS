extends "res://scripts/avg/commands/command_handler.gd"
class_name MoveNodeHandler
## Handler for MOVE_NODE command
## 移动节点到指定归一化坐标，支持动画

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("MOVE_NODE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Move node to normalized position with animation")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.float_param("norm_x", "Target X (0~1)", true, 0.0, "目标X"))
	schema.add_param(ParamDef.float_param("norm_y", "Target Y (0~1)", true, 0.0, "目标Y"))
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 0.3, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var node_id: String = params.get("node_id", "")
	var norm_x: float = float(params.get("norm_x", 0.0))
	var norm_y: float = float(params.get("norm_y", 0.0))
	var duration: float = float(params.get("duration", 0.3))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("MOVE_NODE: no scene_runner")
	runner.node_move(node_id, norm_x, norm_y, duration)
	return CommandResultClass.ok()
