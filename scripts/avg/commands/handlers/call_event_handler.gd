extends CommandHandler
class_name CallEventHandler
## Handler for CALL_EVENT command
## Calls a reusable event (command sequence).
## Validates: Requirement 10.1

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CALL_EVENT")


## Create the parameter schema for CALL_EVENT command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Calls a reusable event (command sequence)"
	)
	
	schema.add_param(ParamDef.string_param(
		"event_id",
		"The ID of the event to call",
		true,
		"",
		"",
		"事件ID",
		"event_ref"
	))
	
	return schema


## Execute the CALL_EVENT command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var event_id: String = _get_param(command, "event_id", "")
	
	if event_id.is_empty():
		return CommandResultClass.error("event_id is required for CALL_EVENT command")
	
	# Execute the event call
	if context.has_method("call_event"):
		context.call_event(event_id)
	else:
		push_warning("CallEventHandler: call_event method not available in context")
	
	return CommandResultClass.ok({"event_id": event_id})
