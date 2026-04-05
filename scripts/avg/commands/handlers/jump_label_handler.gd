extends CommandHandler
class_name JumpLabelHandler
## Handler for JUMP_LABEL command
## Jumps to a label in the current scene.
## Validates: Requirement 10.1

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("JUMP_LABEL")


## Create the parameter schema for JUMP_LABEL command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Jumps to a label in the current scene"
	)
	
	schema.add_param(ParamDef.string_param(
		"target",
		"The label name to jump to",
		true,
		"",
		"",
		"目标标签",
		"label_ref"
	))
	
	return schema


## Execute the JUMP_LABEL command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var target: String = _get_param(command, "target", "")
	
	if target.is_empty():
		return CommandResultClass.error("target is required for JUMP_LABEL command")
	
	# Execute the jump to label
	if context.has_method("jump_to_label"):
		context.jump_to_label(target)
	else:
		push_warning("JumpLabelHandler: jump_to_label method not available in context")
	
	return CommandResultClass.ok({"jump_target": target})
