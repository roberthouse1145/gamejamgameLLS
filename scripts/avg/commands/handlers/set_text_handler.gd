extends CommandHandler
class_name SetTextHandler
## Handler for SET_TEXT command
## 设置节点文本内容，支持 {{var_001}} 变量插值
## node_id 为空时使用自身节点（并行/点击模式）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_TEXT")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Set node text with variable interpolation")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.string_param("text", "Text content, supports {{var_id}} interpolation", true, "", "", "文本"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var node_id: String = params.get("node_id", "")
	var text: String = params.get("text", "")
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("SET_TEXT: no scene_runner")
	runner.node_set_text(node_id, text)
	return CommandResultClass.ok()
