extends CommandHandler
class_name ReturnToTitleHandler
## Handler for RETURN_TO_TITLE command
## TODO: 返回标题画面。后续完善。


func _init() -> void:
	super._init("RETURN_TO_TITLE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Return to title screen (TODO)"
	)
	return schema


func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	push_warning("RETURN_TO_TITLE: Not yet implemented (TODO)")
	return CommandResultClass.ok()
