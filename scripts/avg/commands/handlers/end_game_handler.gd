extends "res://scripts/avg/commands/command_handler.gd"
class_name EndGameHandler
## Handler for END_GAME command
## TODO: 结束游戏。后续完善。


func _init() -> void:
	super._init("END_GAME")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"End the game (TODO)"
	)
	return schema


func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	push_warning("END_GAME: Not yet implemented (TODO)")
	return CommandResultClass.ok()
