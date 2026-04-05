class_name VariableManager extends RefCounted
## Manages game variables during AVG runtime
## Stores and manipulates variables with support for various operations.
## Validates: Requirement 7.1

## Emitted when a variable value changes
signal variable_changed(variable_name: String, old_value: Variant, new_value: Variant)

## Global variable storage
var _variables: Dictionary = {}

## Default values for reset functionality
var _defaults: Dictionary = {}

## ID -> name mapping for variable_id lookup
var _id_to_name: Dictionary = {}

## name -> ID mapping for reverse lookup
var _name_to_id: Dictionary = {}

## ---- 场景独立变量层 ----
## 查询时优先查 local，再查 global（遮蔽机制）
var _local_variables: Dictionary = {}
var _local_defaults: Dictionary = {}
var _local_id_to_name: Dictionary = {}
var _local_name_to_id: Dictionary = {}


## Initialize global variables from an array of AVGVariable resources
## @param variables: Array of AVGVariable resources
func initialize(variables: Array) -> void:
	_variables.clear()
	_defaults.clear()
	_id_to_name.clear()
	_name_to_id.clear()
	
	for variable in variables:
		if variable == null:
			continue
		
		var var_name: String = variable.variable_name
		var default_val: int = int(variable.default_value)
		var var_id: String = variable.variable_id if "variable_id" in variable else ""
		
		if var_name.is_empty():
			push_warning("VariableManager: Skipping variable with empty name")
			continue
		
		_variables[var_name] = default_val
		_defaults[var_name] = default_val
		
		# Build ID mappings
		if not var_id.is_empty():
			_id_to_name[var_id] = var_name
			_name_to_id[var_name] = var_id


## Initialize scene-local variables (called on scene load, cleared on scene switch)
## @param variables: Array of AVGVariable resources
func initialize_local(variables: Array) -> void:
	_local_variables.clear()
	_local_defaults.clear()
	_local_id_to_name.clear()
	_local_name_to_id.clear()

	for variable in variables:
		if variable == null:
			continue

		var var_name: String = variable.variable_name
		var default_val: int = int(variable.default_value)
		var var_id: String = variable.variable_id if "variable_id" in variable else ""

		if var_name.is_empty():
			push_warning("VariableManager: Skipping local variable with empty name")
			continue

		_local_variables[var_name] = default_val
		_local_defaults[var_name] = default_val

		if not var_id.is_empty():
			_local_id_to_name[var_id] = var_name
			_local_name_to_id[var_name] = var_id


## Clear scene-local variables (called on scene switch)
func clear_local() -> void:
	_local_variables.clear()
	_local_defaults.clear()
	_local_id_to_name.clear()
	_local_name_to_id.clear()


## Get the value of a variable (local first, then global)
## @param variable_name: Name of the variable to get
## @return: The variable value, or null if not found
func get_value(variable_name: String) -> Variant:
	# Local layer takes priority (shadowing)
	if _local_variables.has(variable_name):
		return _local_variables[variable_name]
	if not _variables.has(variable_name):
		push_warning("VariableManager: Variable '%s' not found" % variable_name)
		return null
	return _variables[variable_name]


## Get the value of a variable by ID (local first, then global)
## @param variable_id: ID of the variable (e.g., "var_001")
## @return: The variable value, or null if not found
func get_value_by_id(variable_id: String) -> Variant:
	# Check local layer first
	if _local_id_to_name.has(variable_id):
		var local_name: String = _local_id_to_name[variable_id]
		return _local_variables.get(local_name)
	if not _id_to_name.has(variable_id):
		push_warning("VariableManager: Variable ID '%s' not found" % variable_id)
		return null
	var var_name: String = _id_to_name[variable_id]
	return _variables.get(var_name)


## Set the value of a variable with optional operation
## Writes to local layer if the variable exists there, otherwise global.
## @param variable_name: Name of the variable to set
## @param value: The value to apply
## @param operation: Operation to perform ("set", "add", "subtract", "multiply", "divide")
func set_value(variable_name: String, value: Variant, operation: String = "set") -> void:
	# Check local layer first
	if _local_variables.has(variable_name):
		var local_old: int = _local_variables[variable_name] as int
		var local_new: int = _apply_operation(local_old, _convert_value(value), operation)
		_local_variables[variable_name] = local_new
		variable_changed.emit(variable_name, local_old, local_new)
		return

	if not _variables.has(variable_name):
		# Auto-create in global layer
		var int_val: int = _convert_value(value)
		_variables[variable_name] = int_val
		_defaults[variable_name] = int_val
		variable_changed.emit(variable_name, null, int_val)
		return
	
	var old_value: int = _variables[variable_name] as int
	var new_value: int = _apply_operation(old_value, _convert_value(value), operation)
	
	_variables[variable_name] = new_value
	variable_changed.emit(variable_name, old_value, new_value)


## Set the value of a variable by ID with optional operation
## Checks local layer first, then global.
## @param variable_id: ID of the variable (e.g., "var_001")
## @param value: The value to apply
## @param operation: Operation to perform ("set", "add", "subtract", "multiply", "divide")
func set_value_by_id(variable_id: String, value: Variant, operation: String = "set") -> void:
	# Check local layer first
	if _local_id_to_name.has(variable_id):
		var local_name: String = _local_id_to_name[variable_id]
		set_value(local_name, value, operation)
		return
	if not _id_to_name.has(variable_id):
		push_warning("VariableManager: Variable ID '%s' not found" % variable_id)
		return
	var var_name: String = _id_to_name[variable_id]
	set_value(var_name, value, operation)


## Get variable name by ID
## @param variable_id: ID of the variable
## @return: Variable name, or empty string if not found
func get_name_by_id(variable_id: String) -> String:
	return _id_to_name.get(variable_id, "")


## Get variable ID by name
## @param variable_name: Name of the variable
## @return: Variable ID, or empty string if not found
func get_id_by_name(variable_name: String) -> String:
	return _name_to_id.get(variable_name, "")


## Reset all variables to their default values
func reset_to_defaults() -> void:
	for var_name in _defaults.keys():
		var old_value: Variant = _variables[var_name]
		var new_value: Variant = _defaults[var_name]
		_variables[var_name] = new_value
		if old_value != new_value:
			variable_changed.emit(var_name, old_value, new_value)


## Check if a variable exists (local or global)
## @param variable_name: Name of the variable to check
## @return: True if the variable exists
func has_variable(variable_name: String) -> bool:
	return _local_variables.has(variable_name) or _variables.has(variable_name)


## Get all variable names
## @return: Array of variable names
func get_all_variable_names() -> Array[String]:
	var names: Array[String] = []
	for key in _variables.keys():
		names.append(key)
	return names


## Get all variables as a dictionary (for save/load)
## @return: Dictionary with "global" and "local" keys
func get_all_values() -> Dictionary:
	return {
		"global": _variables.duplicate(),
		"local": _local_variables.duplicate(),
	}


## Load variables from a dictionary (for save/load)
## @param values: Dictionary with "global" and "local" keys (or legacy flat dict)
func load_values(values: Dictionary) -> void:
	# 支持新格式 {"global": {...}, "local": {...}}
	if values.has("global") and values["global"] is Dictionary:
		var global_vals: Dictionary = values["global"]
		for var_name in global_vals.keys():
			if _variables.has(var_name):
				var old_value: Variant = _variables[var_name]
				_variables[var_name] = global_vals[var_name]
				if old_value != global_vals[var_name]:
					variable_changed.emit(var_name, old_value, global_vals[var_name])
	else:
		# 兼容旧格式（flat dict = global only）
		for var_name in values.keys():
			if _variables.has(var_name):
				var old_value: Variant = _variables[var_name]
				_variables[var_name] = values[var_name]
				if old_value != values[var_name]:
					variable_changed.emit(var_name, old_value, values[var_name])

	# 加载本地变量
	if values.has("local") and values["local"] is Dictionary:
		var local_vals: Dictionary = values["local"]
		for var_name in local_vals.keys():
			if _local_variables.has(var_name):
				var old_value: int = _local_variables[var_name] as int
				var new_val: int = int(local_vals[var_name])
				_local_variables[var_name] = new_val
				if old_value != new_val:
					variable_changed.emit(var_name, old_value, new_val)


## 根据值推断并转换出对应的整数值
func _convert_value(value_str: Variant) -> int:
	if typeof(value_str) == TYPE_INT:
		return value_str
	if typeof(value_str) == TYPE_FLOAT:
		return int(value_str)
	if typeof(value_str) == TYPE_BOOL:
		return 1 if value_str else 0
	if typeof(value_str) == TYPE_STRING:
		return value_str.to_int()
	return 0


## Apply an operation to a value
## @param current: Current value
## @param operand: Value to apply
## @param operation: Operation type
## @return: Result of the operation
func _apply_operation(current: int, operand: int, operation: String) -> int:
	match operation:
		"set":
			return operand
		"add":
			return current + operand
		"subtract":
			return current - operand
		"multiply":
			return current * operand
		"divide":
			if operand == 0:
				push_warning("VariableManager: Division by zero")
				return current
			@warning_ignore("integer_division")
			return current / operand
		"modulo":
			if operand == 0:
				push_warning("VariableManager: Modulo by zero")
				return current
			return current % operand
		"and":
			return current & operand
		"or":
			return current | operand
		"not":
			return 1 if current == 0 else 0
		_:
			push_warning("VariableManager: Unknown operation '%s'" % operation)
			return operand


# =============================================================================
# Scope-aware API (for SET_VARIABLE / CHECK_VAR with explicit scope)
# =============================================================================

## Get value by ID with explicit scope
## scope: "global", "local", "auto" (auto = local first, then global)
func get_value_by_id_scoped(variable_id: String, scope: String = "auto") -> Variant:
	match scope:
		"local":
			if _local_id_to_name.has(variable_id):
				var vname: String = _local_id_to_name[variable_id]
				return _local_variables.get(vname)
			push_warning("VariableManager: Local variable ID '%s' not found" % variable_id)
			return null
		"global":
			if _id_to_name.has(variable_id):
				var vname: String = _id_to_name[variable_id]
				return _variables.get(vname)
			push_warning("VariableManager: Global variable ID '%s' not found" % variable_id)
			return null
		_: # "auto"
			return get_value_by_id(variable_id)


## Set value by ID with explicit scope
## scope: "global", "local", "auto" (auto = local first if exists, then global)
func set_value_by_id_scoped(variable_id: String, value: Variant, operation: String = "set", scope: String = "auto") -> void:
	match scope:
		"local":
			if _local_id_to_name.has(variable_id):
				var vname: String = _local_id_to_name[variable_id]
				var old_val: int = _local_variables.get(vname, 0) as int
				var new_val: int = _apply_operation(old_val, _convert_value(value), operation)
				_local_variables[vname] = new_val
				variable_changed.emit(vname, old_val, new_val)
			else:
				push_warning("VariableManager: Local variable ID '%s' not found" % variable_id)
		"global":
			if _id_to_name.has(variable_id):
				var vname: String = _id_to_name[variable_id]
				var old_val: int = _variables.get(vname, 0) as int
				var new_val: int = _apply_operation(old_val, _convert_value(value), operation)
				_variables[vname] = new_val
				variable_changed.emit(vname, old_val, new_val)
			else:
				push_warning("VariableManager: Global variable ID '%s' not found" % variable_id)
		_: # "auto"
			set_value_by_id(variable_id, value, operation)
