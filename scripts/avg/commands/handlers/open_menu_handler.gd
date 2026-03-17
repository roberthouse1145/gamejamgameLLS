extends "res://scripts/avg/commands/command_handler.gd"
class_name OpenMenuHandler
## Handler for OPEN_MENU command
## TODO: 打开菜单。后续完善。


func _init() -> void:
	super._init("OPEN_MENU")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Open menu (TODO)"
	)
	return schema


func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	push_warning("OPEN_MENU: Not yet implemented (TODO)")
	return CommandResultClass.ok()
