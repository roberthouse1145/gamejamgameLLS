extends CommandHandler
class_name SaveGameHandler
## Handler for SAVE_GAME command
## TODO: 保存游戏。后续完善。


func _init() -> void:
	super._init("SAVE_GAME")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Save game (TODO)"
	)
	return schema


func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	push_warning("SAVE_GAME: Not yet implemented (TODO)")
	return CommandResultClass.ok()
