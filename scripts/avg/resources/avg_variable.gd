class_name AVGVariable extends Resource
## AVG Variable Resource
## Stores game variable definition including name, type, default value, and description.
## Uses slot-based ID system: variable_id = "var_NNN" where NNN is the slot number.

## 槽位 ID（如 var_001），由槽位号决定，不可编辑
@export var variable_id: String = ""
@export var variable_name: String = ""
@export var default_value: int = 0
@export var description: String = ""


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "variable_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "variable_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "default_value", "type": TYPE_INT, "editable": true, "category": "基本",
		 "description": "默认值（整数）"},
		{"name": "description", "type": TYPE_STRING, "editable": true, "category": "基本"},
	]


## 从槽位号生成 ID
static func make_id(slot: int) -> String:
	return "var_%03d" % slot
