class_name VariableManager extends RefCounted
## Manages AVG runtime variables.
## Runtime state is stored by stable variable_id, while human/LLM-facing APIs use variable_key.

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

## Emitted when a variable value changes
signal variable_changed(variable_key: String, old_value: Variant, new_value: Variant)

## Runtime values/defaults are keyed by stable variable_id to survive key renames.
var _values_by_id: Dictionary = {}
var _defaults_by_id: Dictionary = {}
var _types_by_id: Dictionary = {}

## Lookup tables
var _id_to_key: Dictionary = {}
var _key_to_id: Dictionary = {}


## Initialize variables from AVGVariable resources
func initialize(variables: Array) -> void:
	_values_by_id.clear()
	_defaults_by_id.clear()
	_types_by_id.clear()
	_id_to_key.clear()
	_key_to_id.clear()

	for variable in variables:
		if variable == null:
			continue

		var variable_id: String = str(variable.variable_id if "variable_id" in variable else "").strip_edges()
		var variable_key: String = AVGVariableClass.get_key(variable)
		var value_type: String = AVGVariableClass.get_value_type(variable)
		var default_val: Variant = AVGVariableClass.coerce_storage_value(
			variable.default_value if "default_value" in variable else AVGVariableClass.make_default_value_for_type(value_type),
			value_type
		)

		if variable_id.is_empty():
			push_warning("VariableManager: Skipping variable with empty id")
			continue
		if variable_key.is_empty():
			push_warning("VariableManager: Skipping variable '%s' with empty key" % variable_id)
			continue
		if _values_by_id.has(variable_id):
			push_warning("VariableManager: Duplicate variable id '%s' skipped" % variable_id)
			continue
		if _key_to_id.has(variable_key):
			push_warning("VariableManager: Duplicate variable key '%s' skipped" % variable_key)
			continue

		AVGVariableClass.apply_key(variable, variable_key)
		_values_by_id[variable_id] = default_val
		_defaults_by_id[variable_id] = default_val
		_types_by_id[variable_id] = value_type
		_id_to_key[variable_id] = variable_key
		_key_to_id[variable_key] = variable_id


## Get the value of a variable by key
func get_value(variable_key: String) -> Variant:
	var variable_id: String = get_id_by_key(variable_key)
	if variable_id.is_empty():
		push_warning("VariableManager: Variable key '%s' not found" % variable_key)
		return null
	return _values_by_id.get(variable_id)


## Get the value of a variable by ID
func get_value_by_id(variable_id: String) -> Variant:
	if not _values_by_id.has(variable_id):
		push_warning("VariableManager: Variable ID '%s' not found" % variable_id)
		return null
	return _values_by_id.get(variable_id)


## Resolve either a variable ID or variable key
func get_value_by_ref(variable_ref: String) -> Variant:
	var variable_id: String = _resolve_variable_id(variable_ref)
	if variable_id.is_empty():
		push_warning("VariableManager: Variable ref '%s' not found" % variable_ref)
		return null
	return _values_by_id.get(variable_id)


## Set the value of a variable by key
func set_value(variable_key: String, value: Variant, operation: String = "set") -> void:
	var variable_id: String = get_id_by_key(variable_key)
	if variable_id.is_empty():
		push_warning("VariableManager: Variable key '%s' not found" % variable_key)
		return
	_set_value_by_id_internal(variable_id, value, operation)


## Set the value of a variable by ID
func set_value_by_id(variable_id: String, value: Variant, operation: String = "set") -> void:
	if not _values_by_id.has(variable_id):
		push_warning("VariableManager: Variable ID '%s' not found" % variable_id)
		return
	_set_value_by_id_internal(variable_id, value, operation)


## Set the value of a variable by variable ID or key
func set_value_by_ref(variable_ref: String, value: Variant, operation: String = "set") -> void:
	var variable_id: String = _resolve_variable_id(variable_ref)
	if variable_id.is_empty():
		push_warning("VariableManager: Variable ref '%s' not found" % variable_ref)
		return
	_set_value_by_id_internal(variable_id, value, operation)


func _set_value_by_id_internal(variable_id: String, value: Variant, operation: String) -> void:
	var value_type: String = str(_types_by_id.get(variable_id, AVGVariableClass.VALUE_TYPE_INT))
	var old_value: Variant = _values_by_id.get(variable_id, AVGVariableClass.make_default_value_for_type(value_type))
	var new_value: Variant = _apply_operation(old_value, value, operation, value_type)
	_values_by_id[variable_id] = new_value

	if old_value != new_value:
		variable_changed.emit(get_key_by_id(variable_id), old_value, new_value)


## Get variable key by ID
func get_key_by_id(variable_id: String) -> String:
	return str(_id_to_key.get(variable_id, ""))


## Legacy alias for older callers
func get_name_by_id(variable_id: String) -> String:
	return get_key_by_id(variable_id)


## Get variable ID by key
func get_id_by_key(variable_key: String) -> String:
	return str(_key_to_id.get(AVGVariableClass.normalize_key(variable_key), ""))


## Legacy alias for older callers
func get_id_by_name(variable_name: String) -> String:
	return get_id_by_key(variable_name)


## Reset all variables to their default values
func reset_to_defaults() -> void:
	for variable_id in _defaults_by_id.keys():
		var old_value: Variant = _values_by_id.get(variable_id)
		var new_value: Variant = _defaults_by_id.get(variable_id)
		_values_by_id[variable_id] = new_value
		if old_value != new_value:
			variable_changed.emit(get_key_by_id(variable_id), old_value, new_value)


## Check if a variable exists by key
func has_variable(variable_key: String) -> bool:
	return _key_to_id.has(AVGVariableClass.normalize_key(variable_key))


## Check if a variable exists by key or ID
func has_variable_ref(variable_ref: String) -> bool:
	return not _resolve_variable_id(variable_ref).is_empty()


## Get all variable keys
func get_all_variable_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in _key_to_id.keys():
		keys.append(str(key))
	keys.sort()
	return keys


## Legacy alias used by debug UI
func get_all_variable_names() -> Array[String]:
	return get_all_variable_keys()


## Get runtime values for save/load.
## New format is a flat dictionary keyed by variable_id.
func get_all_values() -> Dictionary:
	return _values_by_id.duplicate()


## Load variables from save data.
## Supports:
##   1. New flat id-keyed dictionaries
##   2. {"by_id": {...}}
##   3. Legacy {"global": {...}, "local": {...}} and name-keyed dictionaries
func load_values(values: Dictionary) -> void:
	if values.is_empty():
		return

	if values.has("by_id") and values["by_id"] is Dictionary:
		_apply_values_by_id(values["by_id"])
		return

	if values.has("global") and values["global"] is Dictionary:
		_apply_legacy_keyed_values(values["global"])
		return

	var is_flat_id_dict: bool = false
	for key in values.keys():
		if _values_by_id.has(str(key)):
			is_flat_id_dict = true
			break

	if is_flat_id_dict:
		_apply_values_by_id(values)
	else:
		_apply_legacy_keyed_values(values)


func _apply_values_by_id(values_by_id: Dictionary) -> void:
	for variable_id in values_by_id.keys():
		var id_text: String = str(variable_id)
		if not _values_by_id.has(id_text):
			continue
		var old_value: Variant = _values_by_id[id_text]
		var value_type: String = str(_types_by_id.get(id_text, AVGVariableClass.VALUE_TYPE_INT))
		var new_value: Variant = AVGVariableClass.coerce_storage_value(values_by_id[variable_id], value_type)
		_values_by_id[id_text] = new_value
		if old_value != new_value:
			variable_changed.emit(get_key_by_id(id_text), old_value, new_value)


func _apply_legacy_keyed_values(values_by_key: Dictionary) -> void:
	for variable_key in values_by_key.keys():
		var normalized_key: String = AVGVariableClass.normalize_key(str(variable_key))
		var variable_id: String = get_id_by_key(normalized_key)
		if variable_id.is_empty():
			continue
		var old_value: Variant = _values_by_id[variable_id]
		var value_type: String = str(_types_by_id.get(variable_id, AVGVariableClass.VALUE_TYPE_INT))
		var new_value: Variant = AVGVariableClass.coerce_storage_value(values_by_key[variable_key], value_type)
		_values_by_id[variable_id] = new_value
		if old_value != new_value:
			variable_changed.emit(normalized_key, old_value, new_value)


func _resolve_variable_id(variable_ref: String) -> String:
	var normalized_ref: String = str(variable_ref).strip_edges()
	if normalized_ref.is_empty():
		return ""
	if _values_by_id.has(normalized_ref):
		return normalized_ref
	return get_id_by_key(normalized_ref)


## Apply an operation to a value
func _apply_operation(current: Variant, operand: Variant, operation: String, value_type: String) -> Variant:
	if operation == "set":
		return AVGVariableClass.coerce_storage_value(operand, value_type)

	var current_numeric: int = AVGVariableClass.coerce_to_int(current)
	var operand_numeric: int = AVGVariableClass.coerce_to_int(operand)
	var result_numeric: int = current_numeric
	match operation:
		"add":
			result_numeric = current_numeric + operand_numeric
		"subtract":
			result_numeric = current_numeric - operand_numeric
		"multiply":
			result_numeric = current_numeric * operand_numeric
		"divide":
			if operand_numeric == 0:
				push_warning("VariableManager: Division by zero")
				return _coerce_operation_result(current_numeric, value_type)
			@warning_ignore("integer_division")
			result_numeric = current_numeric / operand_numeric
		"modulo":
			if operand_numeric == 0:
				push_warning("VariableManager: Modulo by zero")
				return _coerce_operation_result(current_numeric, value_type)
			result_numeric = current_numeric % operand_numeric
		"and":
			result_numeric = current_numeric & operand_numeric
		"or":
			result_numeric = current_numeric | operand_numeric
		"not":
			result_numeric = 1 if current_numeric == 0 else 0
		_:
			push_warning("VariableManager: Unknown operation '%s'" % operation)
			return AVGVariableClass.coerce_storage_value(operand, value_type)
	return _coerce_operation_result(result_numeric, value_type)


func _coerce_operation_result(value: int, value_type: String) -> Variant:
	if value_type == AVGVariableClass.VALUE_TYPE_STRING:
		push_warning("VariableManager: Numeric operation applied to string variable, result stored as string")
		return AVGVariableClass.coerce_to_string(value)
	return value


# =============================================================================
# Compatibility wrappers for older scoped/local APIs
# =============================================================================

func initialize_local(_variables: Array) -> void:
	push_warning("VariableManager: scene-local variables are deprecated and ignored")


func clear_local() -> void:
	pass


func get_value_by_id_scoped(variable_id: String, _scope: String = "auto") -> Variant:
	return get_value_by_id(variable_id)


func set_value_by_id_scoped(variable_id: String, value: Variant, operation: String = "set", _scope: String = "auto") -> void:
	set_value_by_id(variable_id, value, operation)
