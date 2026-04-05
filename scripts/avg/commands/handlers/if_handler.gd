extends CommandHandler
class_name IfHandler
## Handler for IF command
## 条件分支 — condition_commands 是条件命令列表，由运行时评估
## if_commands / else_commands 是普通命令列表
## 实际逻辑在 AVGSceneRunner._handle_if_command() 中

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("IF")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Conditional branching (if/else) with condition command list"
	)

	# condition_commands: Array of condition commands (CHECK_VAR, nested IF)
	# Not a simple string param — handled specially by editor and runtime

	return schema


## No-op — handled by scene runner
func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	return CommandResultClass.ok()
