extends CommandHandler
class_name ResizeNodeHandler
## Handler for RESIZE_NODE command
## 调整节点大小（归一化尺寸），支持动画

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("RESIZE_NODE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Resize node with animation")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.float_param("norm_w", "Target width (0~1)", true, 0.1, "目标宽"))
	schema.add_param(ParamDef.float_param("norm_h", "Target height (0~1)", true, 0.1, "目标高"))
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 0.3, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var node_id: String = params.get("node_id", "")
	var norm_w: float = float(params.get("norm_w", 0.1))
	var norm_h: float = float(params.get("norm_h", 0.1))
	var duration: float = float(params.get("duration", 0.3))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("RESIZE_NODE: no scene_runner")
	runner.node_resize(node_id, norm_w, norm_h, duration)
	return CommandResultClass.ok()
