extends "res://scripts/avg/commands/command_handler.gd"
class_name SetStyleHandler
## Handler for SET_STYLE command
## 设置节点样式（内联 flat 属性），用于 hover/press 视觉反馈

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_STYLE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Set node style (flat StyleBox)")
	schema.add_param(ParamDef.string_param("node_id", "Target node ID (empty=self)", false, "", "", "节点ID", "node_ref"))
	schema.add_param(ParamDef.string_param("bg_color", "Background color hex (e.g. 335533ff)", false, "000000cc", "", "背景色"))
	schema.add_param(ParamDef.int_param("corner_radius", "Corner radius", false, 8, "圆角"))
	schema.add_param(ParamDef.int_param("border_width", "Border width", false, 0, "边框宽度"))
	schema.add_param(ParamDef.string_param("border_color", "Border color hex", false, "ffffffff", "", "边框色"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var node_id: String = params.get("node_id", "")
	var bg_color_str: String = params.get("bg_color", "000000cc")
	var corner_radius: int = int(params.get("corner_radius", 8))
	var border_width: int = int(params.get("border_width", 0))
	var border_color_str: String = params.get("border_color", "ffffffff")
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("SET_STYLE: no scene_runner")
	var bg_color: Color = Color(bg_color_str)
	var border_color: Color = Color(border_color_str)
	runner.node_set_style(node_id, bg_color, corner_radius, border_width, border_color)
	return CommandResultClass.ok()
