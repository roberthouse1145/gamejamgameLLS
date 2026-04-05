extends CommandHandler
class_name CheckHoverHandler
## Handler for CHECK_HOVER command
## 条件命令 — 检查鼠标是否悬停在指定节点上
## 主要用于并行模式，实现按钮 hover 效果
## 由 ParallelExecutor 直接评估，不走 handler.execute()

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHECK_HOVER")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Check if mouse is hovering over a node"
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
