class_name StreamerSkill extends Resource
## 技能图中的一个独立节点；拓扑完全由前置节点描述，UI 布局由画布按图结构推导。

@export var skill_id: StringName = &""
@export var family: StringName = &"talk"
@export_range(1, 99, 1) var level: int = 1
@export_range(0, 4, 1) var ability_level_bonus: int = 0
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export_range(0, 4, 1) var point_cost: int = 0
@export var required_skill_ids: Array[StringName] = []


func is_valid() -> bool:
	if String(skill_id).is_empty() or display_name.strip_edges().is_empty():
		return false
	if String(family).is_empty() or level < 1:
		return false
	return true
