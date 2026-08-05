class_name StreamerSkill extends Resource
## 五维技能树中的一个线性等级里程碑。

@export var skill_id: StringName = &""
@export var family: StringName = &"talk"
@export_range(1, 5, 1) var level: int = 1
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var tree_position: Vector2i = Vector2i.ZERO
@export_range(0, 4, 1) var point_cost: int = 0
@export var required_skill_ids: Array[StringName] = []
@export var unlocked_card_ids: Array[StringName] = []
@export var rule_effects: Array[StreamSpecialEffect] = []


func is_valid() -> bool:
	if String(skill_id).is_empty() or display_name.strip_edges().is_empty():
		return false
	if family not in LiveStreamCardResource.FAMILIES or level < 1 or level > 5:
		return false
	for effect: StreamSpecialEffect in rule_effects:
		if effect == null or not effect.is_valid():
			return false
	return true
