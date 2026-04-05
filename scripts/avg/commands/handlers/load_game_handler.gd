extends CommandHandler
class_name LoadGameHandler
## Handler for LOAD_GAME command
## TODO: 加载游戏。后续完善。


func _init() -> void:
	super._init("LOAD_GAME")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Load game (TODO)"
	)
	return schema


func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	push_warning("LOAD_GAME: Not yet implemented (TODO)")
	return CommandResultClass.ok()
