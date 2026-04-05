extends CommandHandler
class_name WaitClickHandler
## Handler for WAIT_CLICK command
## Waits for player click to continue.
## Validates: Requirement 10.1


func _init() -> void:
	super._init("WAIT_CLICK")


## Create the parameter schema for WAIT_CLICK command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Waits for player click to continue"
	)
	# No parameters for this command
	return schema


## Execute the WAIT_CLICK command
func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	# No-op: Scene runner handles the actual wait after this command executes
	return CommandResultClass.ok()
