extends "res://scripts/avg/commands/command_handler.gd"
class_name ChangeOutfitHandler
## Handler for CHANGE_OUTFIT command.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHANGE_OUTFIT")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Change character outfit")
	schema.add_param(ParamDef.character_ref_param("character_id", "Character ID", true, "Character"))
	schema.add_param(ParamDef.string_param("outfit", "Outfit name", true, "", "", "Outfit"))
	schema.add_param(ParamDef.string_param("emotion", "Expression override", false, "", "", "Expression"))
	schema.add_param(ParamDef.choices_param("transition", ["", "crossfade", "instant", "fade_through_black"], "Transition", false, "", "Transition"))
	schema.add_param(ParamDef.float_param("duration", "Transition duration", false, -1.0, "Duration"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var outfit: String = _get_param(command, "outfit", "")
	var emotion: String = _get_param(command, "emotion", "")
	var transition: String = _get_param(command, "transition", "")
	var duration: float = _get_param(command, "duration", -1.0)

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")
	if outfit.is_empty():
		return CommandResultClass.error("outfit is required")

	if context.character_display != null:
		context.character_display.change_outfit(character_id, outfit, transition, duration, emotion)

	return CommandResultClass.ok()
