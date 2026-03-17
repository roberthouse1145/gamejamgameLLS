extends "res://scripts/avg/commands/command_handler.gd"
class_name ShowNodeHandler
## Handler for SHOW_NODE command
## 显示节点（淡入）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SHOW_NODE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Show node with fade-in")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.float_param("fade_duration", "Fade-in duration (0=instant)", false, 0.0, "淡入时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var node_id: String = params.get("node_id", "")
	var fade_duration: float = float(params.get("fade_duration", 0.0))
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("SHOW_NODE: no scene_runner")
	runner.node_show(node_id, fade_duration)
	return CommandResultClass.ok()
