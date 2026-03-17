extends "res://scripts/avg/commands/command_handler.gd"
class_name LabelHandler
## Handler for LABEL command
## Marks a position in the command list for jumping.
## Labels are processed by scene runner, execute is a no-op.
## Validates: Requirement 10.1

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("LABEL")


## Create the parameter schema for LABEL command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Marks a position in the command list for jumping"
	)
	
	schema.add_param(ParamDef.string_param(
		"name",
		"The label name for jump targets",
		true,
		"",
		"",
		"标签名"
	))
	
	return schema


## Execute the LABEL command
## Labels are processed by scene runner, this is a no-op
func execute(command: Resource, _context: RefCounted) -> CommandResultClass:
	var label_name: String = _get_param(command, "name", "")
	
	if label_name.is_empty():
		return CommandResultClass.error("name is required for LABEL command")
	
	# No-op: Labels are processed by scene runner during initialization
	# The scene runner builds a label index before execution
	return CommandResultClass.ok({"label_name": label_name})
