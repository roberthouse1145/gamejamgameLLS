extends CommandHandler
class_name MoveCharacterHandler
## Handler for MOVE_CHARACTER command
## Moves a character to a predefined position or custom normalized coords.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("MOVE_CHARACTER")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "移动角色到指定位置")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.string_param("target", "目标位置(left/center/right/far_left/far_right 或 x,y)", true, "center", "", "目标位置"))
	schema.add_param(ParamDef.float_param("duration", "动画时长(0=瞬移)", false, 0.3, "时长"))
	schema.add_param(ParamDef.choices_param("easing", ["linear", "ease_in", "ease_out", "ease_in_out"], "缓动类型", false, "ease_in_out", "缓动"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var target: String = _get_param(command, "target", "center")
	var duration: float = _get_param(command, "duration", 0.3)
	var easing: String = _get_param(command, "easing", "ease_in_out")

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")

	if context.character_display != null:
		context.character_display.move_character(character_id, target, duration, easing)

	return CommandResultClass.ok()
