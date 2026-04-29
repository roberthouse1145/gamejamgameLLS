class_name AVGVariable extends Resource
## AVG Variable Resource
## Stores game variable definition including stable key, default value, and description.
## Uses slot-based ID system: variable_id = "var_NNN" where NNN is the slot number.

const VALUE_TYPE_INT: String = "int"
const VALUE_TYPE_STRING: String = "string"

## 槽位 ID（如 var_001），由槽位号决定，不可编辑
@export var variable_id: String = ""
@export var variable_key: String = ""
@export var variable_name: String = ""  # Legacy compatibility; mirrors variable_key when available.
@export var value_type: String = VALUE_TYPE_INT:
	set(value):
		value_type = normalize_value_type(value, default_value)
		default_value = coerce_storage_value(default_value, value_type)
@export var default_value: Variant = 0:
	set(value):
		default_value = coerce_storage_value(value, value_type)
@export var description: String = ""


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "variable_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "variable_key", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "value_type", "type": TYPE_STRING, "editable": true, "category": "基本", "hint": "choices",
		 "options": [VALUE_TYPE_INT, VALUE_TYPE_STRING], "description": "变量值类型（只允许 int / string）"},
		{"name": "default_value", "type": TYPE_STRING, "editable": true, "category": "基本",
		 "description": "默认值。int 类型会自动转整数；string 类型按字符串保存。bool 会转 0/1，float 会截断为 int。"},
		{"name": "description", "type": TYPE_STRING, "editable": true, "category": "基本"},
	]


## 从槽位号生成 ID
static func make_id(slot: int) -> String:
	return "var_%03d" % slot


static func make_default_key(slot: int) -> String:
	return "variable_%03d" % slot


static func normalize_key(raw_key: String) -> String:
	return raw_key.strip_edges().to_snake_case()


static func get_key(variable: Variant) -> String:
	if variable == null:
		return ""

	var raw_key: String = ""
	if "variable_key" in variable:
		raw_key = str(variable.variable_key)
	if raw_key.strip_edges().is_empty() and "variable_name" in variable:
		raw_key = str(variable.variable_name)
	return normalize_key(raw_key)


static func apply_key(variable: Variant, raw_key: String) -> String:
	if variable == null:
		return ""

	var normalized_key: String = normalize_key(raw_key)
	if "variable_key" in variable:
		variable.variable_key = normalized_key
	if "variable_name" in variable:
		variable.variable_name = normalized_key
	return normalized_key


static func get_value_type(variable: Variant) -> String:
	if variable == null:
		return VALUE_TYPE_INT
	var raw_type: Variant = variable.value_type if "value_type" in variable else ""
	var fallback_value: Variant = variable.default_value if "default_value" in variable else 0
	return normalize_value_type(raw_type, fallback_value)


static func normalize_value_type(raw_type: Variant, fallback_value: Variant = null) -> String:
	var normalized_type: String = str(raw_type).strip_edges().to_lower()
	if normalized_type == VALUE_TYPE_STRING:
		return VALUE_TYPE_STRING
	if normalized_type == VALUE_TYPE_INT:
		return VALUE_TYPE_INT
	return infer_value_type(fallback_value)


static func infer_value_type(value: Variant) -> String:
	if value is String:
		return VALUE_TYPE_STRING
	return VALUE_TYPE_INT


static func make_default_value_for_type(raw_type: Variant) -> Variant:
	var normalized_type: String = normalize_value_type(raw_type)
	if normalized_type == VALUE_TYPE_STRING:
		return ""
	return 0


static func coerce_storage_value(value: Variant, raw_type: Variant = VALUE_TYPE_INT) -> Variant:
	var normalized_type: String = normalize_value_type(raw_type, value)
	if normalized_type == VALUE_TYPE_STRING:
		return coerce_to_string(value)
	return coerce_to_int(value)


static func coerce_to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return 0
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return int(text.to_float())
		var lowered: String = text.to_lower()
		if lowered == "true":
			return 1
		if lowered == "false":
			return 0
		return 1
	if value == null:
		return 0
	return coerce_to_int(str(value))


static func coerce_to_string(value: Variant) -> String:
	if value is String:
		return value
	if value is bool:
		return "1" if value else "0"
	if value is float:
		return str(int(value))
	if value == null:
		return ""
	return str(value)


static func coerce_mixed_comparison_number(value: Variant) -> int:
	if value is String:
		return 0 if value.is_empty() else 1
	return coerce_to_int(value)


static func normalize_script_literal(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String:
		var text: String = value.strip_edges()
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return int(text.to_float())
		var lowered: String = text.to_lower()
		if lowered == "true":
			return 1
		if lowered == "false":
			return 0
		return value
	if value == null:
		return 0
	return normalize_script_literal(str(value))


static func normalize_runtime_value(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String:
		return value
	if value == null:
		return 0
	return str(value)
