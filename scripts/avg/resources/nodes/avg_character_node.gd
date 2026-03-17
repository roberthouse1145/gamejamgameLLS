class_name AVGCharacterNode extends AVGNode
## AVG Character Node
## 角色节点，用于显示角色立绘

const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")

@export var character_ref: Resource  # AVGCharacter
@export var emotion: String = "default"
@export var flip_h: bool = false  # 水平翻转


func get_node_type() -> String:
	return "character"


func get_node_type_display() -> String:
	return "角色"


func get_avg_properties() -> Array[Dictionary]:
	var unique_props: Array[Dictionary] = [
		{"name": "character_ref", "type": TYPE_OBJECT, "editable": true, "category": "角色", "class_hint": "AVGCharacter"},
		{"name": "emotion", "type": TYPE_STRING, "editable": true, "category": "角色"},
		{"name": "flip_h", "type": TYPE_BOOL, "editable": true, "category": "角色"},
	]
	unique_props.append_array(super.get_avg_properties())
	return unique_props
