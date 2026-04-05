extends CommandHandler
class_name MoveCharacterByHandler
## Handler for MOVE_CHARACTER_BY command
## Moves a character by a relative offset (normalized coordinates).

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("MOVE_CHARACTER_BY")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "相对移动角色")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.float_param("offset_x", "X轴偏移(归一化, 0.1=屏幕10%)", true, 0.0, "X偏移"))
	schema.add_param(ParamDef.float_param("offset_y", "Y轴偏移(归一化)", false, 0.0, "Y偏移"))
	schema.add_param(ParamDef.float_param("duration", "动画时长(0=瞬移)", false, 0.3, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var offset_x: float = _get_param(command, "offset_x", 0.0)
	var offset_y: float = _get_param(command, "offset_y", 0.0)
	var duration: float = _get_param(command, "duration", 0.3)

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")

	if context.character_display != null:
		context.character_display.move_character_by(character_id, offset_x, offset_y, duration)

	return CommandResultClass.ok()
