extends CommandHandler
class_name CheckVarHandler
## Handler for CHECK_VAR command
## 条件专用命令 — 检查变量是否满足条件
## 支持：
##   - 全局/本地/自动作用域
##   - 比较对象: 常量、另一个变量、游戏数据
## 由 AVGSceneRunner._evaluate_condition_commands() 直接处理

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHECK_VAR")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Check variable condition"
	)

	schema.add_param(ParamDef.variable_ref_param(
		"variable_id",
		"Variable ID to check (e.g., var_001)",
		true,
		"变量ID"
	))

	schema.add_param(ParamDef.choices_param(
		"operator",
		["==", "!=", ">", ">=", "<", "<="],
		"Comparison operator",
		true,
		">=",
		"运算符"
	))

	schema.add_param(ParamDef.choices_param(
		"value_source",
		["constant", "variable", "game_data"],
		"What to compare against",
		false,
		"constant",
		"比较来源"
	))

	# --- constant ---
	schema.add_param(ParamDef.string_param(
		"value",
		"Constant value to compare against (when value_source=constant)",
		false,
		"0",
		"",
		"比较值"
	))
	schema.get_param("value").visible_when = "value_source == constant"

	# --- variable ---
	schema.add_param(ParamDef.variable_ref_param(
		"source_variable_id",
		"Variable ID to compare against (when value_source=variable)",
		false,
		"源变量ID"
	))
	schema.get_param("source_variable_id").visible_when = "value_source == variable"

	# --- game_data ---
	schema.add_param(ParamDef.choices_param(
		"game_data_key",
		["play_time", "click_count", "scene_count", "current_scene_index"],
		"Game data key to compare against (when value_source=game_data)",
		false,
		"play_time",
		"游戏数据键"
	))
	schema.get_param("game_data_key").visible_when = "value_source == game_data"

	return schema


## No-op — evaluated directly by scene runner
func execute(_command: Resource, _context: RefCounted) -> CommandResultClass:
	return CommandResultClass.ok()
