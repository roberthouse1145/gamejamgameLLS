class_name MagicalGirlData
extends Resource

@export var girl_id: String = ""
@export var display_name: String = ""
@export var portrait: Texture2D
@export var strength: int = 5
@export var agility: int = 5
@export var charisma: int = 5
@export var intelligence: int = 5
@export var willpower: int = 5
@export var base_move_speed: float = 100.0
@export_multiline var prompt: String = ""


## 返回完整prompt = 基础设定 + AttributeDescriptor生成的属性描述
func get_full_prompt() -> String:
	var full: String = prompt
	var attributes_prompt: String = AttributeDescriptor.get_all_attributes_prompt(self)
	if attributes_prompt.length() > 0:
		full += "\n" + attributes_prompt
	return full
