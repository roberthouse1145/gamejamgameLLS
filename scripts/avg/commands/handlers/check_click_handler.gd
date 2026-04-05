extends CommandHandler
class_name CheckClickHandler
## Handler for CHECK_CLICK command
## 条件命令 — 检查鼠标是否正在按下指定节点
## 主要用于并行模式，实现按钮 press 效果
## 由 ParallelExecutor 直接评估，不走 handler.execute()

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHECK_CLICK")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Check if mouse is pressing a node"
	)

	schema.add_param(ParamDef.string_param(
		"node_id",
		"Target node ID (empty = self)",
		false,
		"",
		"",
		"节点ID",
		"node_ref"
	))

	return schema


## No-op — evaluated directly by ParallelExecutor
func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	return CommandResultClass.ok()
