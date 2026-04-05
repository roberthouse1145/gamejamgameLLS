extends CommandHandler
class_name RemoveNodeHandler
## Handler for REMOVE_NODE command
## 移除节点（淡出后从场景删除）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("REMOVE_NODE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Remove node from scene")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.float_param("fade_duration", "Fade-out before removal (0=instant)", false, 0.0, "淡出时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var node_id: String = params.get("node_id", "")
	var fade_duration: float = float(params.get("fade_duration", 0.0))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("REMOVE_NODE: no scene_runner")
	runner.node_remove(node_id, fade_duration)
	return CommandResultClass.ok()
