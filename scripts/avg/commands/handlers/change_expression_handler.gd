extends "res://scripts/avg/commands/command_handler.gd"
class_name ChangeExpressionHandler
## Handler for CHANGE_EXPRESSION command.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHANGE_EXPRESSION")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "切换角色表情")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.string_param("expression", "表情名", true, "", "", "表情"))
	schema.add_param(ParamDef.string_param("outfit", "服装名", false, "", "", "服装"))
	schema.add_param(ParamDef.choices_param("transition", ["", "crossfade", "instant", "fade_through_black"], "切换方式", false, "", "切换"))
	schema.add_param(ParamDef.float_param("duration", "切换时长(-1为默认)", false, -1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var expression: String = _get_param(command, "expression", "")
	var outfit: String = _get_param(command, "outfit", "")
	var transition: String = _get_param(command, "transition", "")
	var duration: float = _get_param(command, "duration", -1.0)

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")
	if expression.is_empty():
		return CommandResultClass.error("expression is required")

	if context.character_display != null:
		context.character_display.change_expression(character_id, expression, transition, duration, outfit)

	return CommandResultClass.ok()
