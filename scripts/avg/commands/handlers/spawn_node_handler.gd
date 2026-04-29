extends CommandHandler
class_name SpawnNodeHandler
## Handler for SPAWN_NODE command
## 运行时生成公共节点实例

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SPAWN_NODE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Spawn a shared node instance at runtime")
	schema.add_param(ParamDef.string_param("shared_node_id", "Shared node template ID", true, "", "", "公共节点ID", "shared_node_ref"))
	schema.add_param(ParamDef.string_param("instance_id", "Instance ID (empty=auto)", false, "", "", "实例ID"))
	schema.add_param(ParamDef.float_param("norm_x", "Spawn X position (0~1)", false, 0.0, "X位置"))
	schema.add_param(ParamDef.float_param("norm_y", "Spawn Y position (0~1)", false, 0.0, "Y位置"))
	schema.add_param(ParamDef.string_param("parent_node_id", "Parent node ID (empty=root layer)", false, "", "", "父节点ID", "node_ref"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var shared_node_id: String = _get_param(command, "shared_node_id", "")
	var instance_id: String = _get_param(command, "instance_id", "")
	var norm_x: float = _get_param(command, "norm_x", 0.0)
	var norm_y: float = _get_param(command, "norm_y", 0.0)
	var parent_node_id: String = _get_param(command, "parent_node_id", "")
	if shared_node_id.is_empty():
		return CommandResultClass.error("SPAWN_NODE: shared_node_id is required")
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("SPAWN_NODE: no scene_runner")
	runner.node_spawn(shared_node_id, instance_id, norm_x, norm_y, parent_node_id)
	return CommandResultClass.ok()
