extends "res://scripts/avg/commands/command_handler.gd"
class_name ChoiceHandler
## Handler for CHOICE command
## Shows choice buttons for player selection.
## Each choice has: text, commands (sub-command array), condition_commands, hidden_when_unmet

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHOICE")


## Create the parameter schema for CHOICE command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Shows choice buttons for player selection"
	)
	
	# choices is an array of {text, commands, condition_commands, hidden_when_unmet}
	schema.add_param(ParamDef.new(
		"choices",
		"array",
		[],
		"Array of choice options with text, commands, condition_commands, hidden_when_unmet",
		true,
		[],
		"choices_array"
	))
	
	return schema


## Execute the CHOICE command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var choices: Array = _get_param(command, "choices", [])
	
	if choices.is_empty():
		return CommandResultClass.error("choices array is required and cannot be empty for CHOICE command")
	
	# Validate choices structure
	for i in range(choices.size()):
		var choice = choices[i]
		if not choice is Dictionary:
			return CommandResultClass.error("Choice at index %d must be a Dictionary" % i)
		if not choice.has("text") or not choice["text"] is String:
			return CommandResultClass.error("Choice at index %d must have a 'text' string property" % i)
		# commands is optional (defaults to empty array)
		# condition_commands is optional (defaults to empty = always visible)
		# hidden_when_unmet is optional (defaults to false = greyed out)
		# Backward compatibility: jump_to is still accepted but deprecated
	
	# Show the choices (scene runner will await selection)
	if context.choice_display != null:
		# Pass variable_manager for condition evaluation
		var var_mgr = context.variable_manager if "variable_manager" in context else null
		var scene_runner = context.scene_runner if "scene_runner" in context else null
		context.choice_display.show_choices(choices, var_mgr, scene_runner)
	else:
		push_warning("ChoiceHandler: choice_display not available in context")
	
	return CommandResultClass.ok()
