extends "res://scripts/avg/commands/command_handler.gd"
class_name HideCharacterHandler
## Handler for HIDE_CHARACTER command
## Hides a character from screen.
## Validates: Requirement 10.1

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("HIDE_CHARACTER")


## Create the parameter schema for HIDE_CHARACTER command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Hides a character from screen"
	)
	
	schema.add_param(ParamDef.character_ref_param(
		"character_id",
		"The character to hide",
		true,
		"角色"
	))
	
	schema.add_param(ParamDef.float_param(
		"fade_duration",
		"Duration of the fade-out animation in seconds",
		false,
		0.3,
		"淡出时长"
	))
	
	return schema


## Execute the HIDE_CHARACTER command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var fade_duration: float = _get_param(command, "fade_duration", 0.3)
	
	if character_id.is_empty():
		return CommandResultClass.error("character_id is required for HIDE_CHARACTER command")
	
	# Execute the character hide
	if context.character_display != null:
		context.character_display.hide_character(character_id, fade_duration)
	else:
		push_warning("HideCharacterHandler: character_display not available in context")
	
	return CommandResultClass.ok()
