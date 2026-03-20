extends "res://scripts/avg/commands/command_handler.gd"
class_name HideCharacterHandler
## Handler for HIDE_CHARACTER command
## Hides a character from screen.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("HIDE_CHARACTER")


## Create the parameter schema for HIDE_CHARACTER command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Hide character"
	)

	schema.add_param(ParamDef.character_ref_param(
		"character_id",
		"The character to hide",
		true,
		"Character"
	))

	schema.add_param(ParamDef.float_param(
		"fade_duration",
		"Exit animation duration in seconds",
		false,
		0.3,
		"Duration"
	))
	schema.add_param(ParamDef.choices_param(
		"exit_effect",
		["fade", "slide_to_left", "slide_to_right", "slide_to_top", "slide_to_bottom", "pop_out", "none"],
		"Shortcut exit effect",
		false,
		"fade",
		"Exit"
	))
	schema.add_param(ParamDef.float_param(
		"exit_distance",
		"Exit travel distance (normalized)",
		false,
		0.08,
		"Distance"
	))
	schema.add_param(ParamDef.choices_param(
		"exit_easing",
		["linear", "ease_in", "ease_out", "ease_in_out"],
		"Exit easing",
		false,
		"ease_in",
		"Easing"
	))

	return schema


## Execute the HIDE_CHARACTER command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var fade_duration: float = _get_param(command, "fade_duration", 0.3)
	var exit_effect: String = _get_param(command, "exit_effect", "fade")
	var exit_distance: float = _get_param(command, "exit_distance", 0.08)
	var exit_easing: String = _get_param(command, "exit_easing", "ease_in")

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required for HIDE_CHARACTER command")

	# Execute the character hide
	if context.character_display != null:
		context.character_display.hide_character(character_id, fade_duration, exit_effect, exit_distance, exit_easing)
	else:
		push_warning("HideCharacterHandler: character_display not available in context")

	return CommandResultClass.ok()
