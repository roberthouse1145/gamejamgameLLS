extends CommandHandler
class_name WaitTimeHandler
## Handler for WAIT_TIME command
## Waits for specified time before continuing.
## Validates: Requirement 10.1

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("WAIT_TIME")


## Create the parameter schema for WAIT_TIME command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Waits for specified time before continuing"
	)
	
	schema.add_param(ParamDef.float_param(
		"duration",
		"Time to wait in seconds",
		true,
		1.0,
		"等待时长"
	))
	
	return schema


## Execute the WAIT_TIME command
func execute(command: Resource, _context: RefCounted) -> CommandResultClass:
	var duration: float = _get_param(command, "duration", 1.0)
	
	if duration < 0:
		return CommandResultClass.error("duration must be a positive number for WAIT_TIME command")
	
	# No-op: Scene runner handles the actual wait after this command executes
	return CommandResultClass.ok({"duration": duration})
