class_name StreamerSkill extends Resource
## 技能图中的一个独立节点；拓扑完全由前置节点与画布坐标描述。

@export var skill_id: StringName = &""
@export var family: StringName = &"talk"
@export_range(1, 99, 1) var level: int = 1
@export_range(0, 4, 1) var ability_level_bonus: int = 0
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var tree_position: Vector2 = Vector2.ZERO
@export_range(0, 4, 1) var point_cost: int = 0
@export var required_skill_ids: Array[StringName] = []
@export var unlocked_card_ids: Array[StringName] = []
@export var rule_effects: Array[StreamSpecialEffect] = []


func is_valid() -> bool:
	if String(skill_id).is_empty() or display_name.strip_edges().is_empty():
		return false
	if String(family).is_empty() or level < 1:
		return false
	# Check effect fields directly; avoid nested is_valid on loaded subresources.
	for i: int in range(rule_effects.size()):
		var effect_value: Variant = rule_effects[i]
		if effect_value == null or String(effect_value.get("effect_id")).is_empty():
			return false
	return true
