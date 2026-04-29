extends CommandHandler
class_name HideNodeHandler
## Handler for HIDE_NODE command
## 隐藏节点（淡出）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("HIDE_NODE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Hide node with fade-out")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.float_param("fade_duration", "Fade-out duration (0=instant)", false, 0.0, "淡出时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var node_id: String = _get_param(command, "node_id", "")
	var fade_duration: float = _get_param(command, "fade_duration", 0.0)
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("HIDE_NODE: no scene_runner")
	runner.node_hide(node_id, fade_duration)
	return CommandResultClass.ok()
