extends CommandHandler
class_name FlipCharacterHandler
## Handler for FLIP_CHARACTER command
## Horizontally flips a character sprite.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("FLIP_CHARACTER")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "水平翻转角色")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.choices_param("flip", ["toggle", "on", "off"], "翻转模式", false, "toggle", "翻转模式"))
	schema.add_param(ParamDef.float_param("duration", "翻转动画时长(0=瞬间)", false, 0.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var flip_mode: String = _get_param(command, "flip", "toggle")
	var duration: float = _get_param(command, "duration", 0.0)

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")

	if context.character_display != null:
		context.character_display.flip_character(character_id, flip_mode, duration)

	return CommandResultClass.ok()
