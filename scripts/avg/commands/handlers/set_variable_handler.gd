extends CommandHandler
class_name SetVariableHandler
## Handler for SET_VARIABLE command
## 设置或修改变量。支持：
##   - 全局/本地变量作用域
##   - 值来源: 常量、另一个变量、随机数、游戏数据
##   - 操作: set/add/subtract/multiply/divide/modulo

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_VARIABLE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Sets or modifies a variable"
	)

	schema.add_param(ParamDef.variable_ref_param(
		"variable_id",
		"Target variable reference (usually variable ID from editor)",
		true,
		"变量ID"
	))

	schema.add_param(ParamDef.choices_param(
		"operation",
		["set", "add", "subtract", "multiply", "divide", "modulo"],
		"Operation to perform",
		false,
		"set",
		"操作"
	))

	schema.add_param(ParamDef.choices_param(
		"value_source",
		["constant", "variable", "random", "game_data"],
		"Where the operand value comes from",
		false,
		"constant",
		"值来源"
	))

	# --- constant source ---
	schema.add_param(ParamDef.new(
		"value",
		"variant",
		null,
		"Constant value (when value_source=constant)",
		false,
		[],
		"",
		"常量值"
	))
	schema.get_param("value").visible_when = "value_source == constant"

	# --- variable source ---
	schema.add_param(ParamDef.variable_ref_param(
		"source_variable_id",
		"Source variable reference to read from (when value_source=variable)",
		false,
		"源变量ID"
	))
	schema.get_param("source_variable_id").visible_when = "value_source == variable"

	# --- random source ---
	schema.add_param(ParamDef.int_param(
		"random_min",
		"Minimum random value (inclusive, when value_source=random)",
		false,
		0,
		"随机最小值"
	))
	schema.get_param("random_min").visible_when = "value_source == random"

	schema.add_param(ParamDef.int_param(
		"random_max",
		"Maximum random value (inclusive, when value_source=random)",
		false,
		100,
		"随机最大值"
	))
	schema.get_param("random_max").visible_when = "value_source == random"

	# --- game_data source ---
	schema.add_param(ParamDef.choices_param(
		"game_data_key",
		["play_time", "click_count", "scene_count", "current_scene_index"],
		"Game data key to read (when value_source=game_data)",
		false,
		"play_time",
		"游戏数据键"
	))
	schema.get_param("game_data_key").visible_when = "value_source == game_data"

	return schema


## Execute the SET_VARIABLE command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var variable_ref: String = _get_param(command, "variable_id", "")
	if variable_ref.is_empty():
		variable_ref = _get_param(command, "variable_key", "")
	if variable_ref.is_empty():
		variable_ref = _get_param(command, "variable_name", "")
	if variable_ref.is_empty():
		return CommandResultClass.error("variable reference is required")

	var operation: String = _get_param(command, "operation", "set")
	var value_source: String = _get_param(command, "value_source", "constant")

	# Resolve the operand value based on source
	var resolved_value: Variant = _resolve_value(command, context, value_source)
	if resolved_value == null and value_source != "constant":
		return CommandResultClass.error("Could not resolve value from source: " + value_source)

	# For non-set operations, value must be numeric
	if operation != "set" and resolved_value != null:
		if not (resolved_value is int or resolved_value is float):
			return CommandResultClass.error("Value must be numeric for operation: " + operation)

	if resolved_value == null:
		return CommandResultClass.error("value is required")

	if context.variable_manager != null:
		context.variable_manager.set_value_by_ref(variable_ref, resolved_value, operation)

	return CommandResultClass.ok({
		"variable_ref": variable_ref,
		"operation": operation,
		"value_source": value_source,
		"resolved_value": resolved_value,
	})


## Resolve the operand value based on value_source
func _resolve_value(command: Resource, context: RefCounted, source: String) -> Variant:
	match source:
		"constant":
			return _get_param(command, "value", null)

		"variable":
			var src_ref: String = _get_param(command, "source_variable_id", "")
			if src_ref.is_empty():
				src_ref = _get_param(command, "source_variable_key", "")
			if src_ref.is_empty():
				push_warning("SET_VARIABLE: source variable ref is empty")
				return null
			if context.variable_manager != null:
				return context.variable_manager.get_value_by_ref(src_ref)
			return null

		"random":
			var rmin: int = int(_get_param(command, "random_min", 0))
			var rmax: int = int(_get_param(command, "random_max", 100))
			if rmin > rmax:
				var tmp: int = rmin
				rmin = rmax
				rmax = tmp
			return randi_range(rmin, rmax)

		"game_data":
			var key: String = _get_param(command, "game_data_key", "")
			return _get_game_data(key, context)

		_:
			return _get_param(command, "value", null)


## Get game data value by key
func _get_game_data(key: String, context: RefCounted) -> Variant:
	match key:
		"play_time":
			return int(Time.get_ticks_msec() / 1000.0)
		"click_count":
			# From command context if tracked
			if context != null and "click_count" in context:
				return context.click_count
			return 0
		"scene_count":
			if context.scene_runner != null and context.scene_runner.current_project != null:
				var scenes = context.scene_runner.current_project.scenes
				return scenes.size() if scenes != null else 0
			return 0
		"current_scene_index":
			if context.scene_runner != null and context.scene_runner.current_project != null:
				var current = context.scene_runner.current_scene
				var scenes = context.scene_runner.current_project.scenes
				if current != null and scenes != null:
					for i in range(scenes.size()):
						if scenes[i] == current:
							return i
			return 0
		_:
			push_warning("SET_VARIABLE: Unknown game_data_key '%s'" % key)
			return 0
