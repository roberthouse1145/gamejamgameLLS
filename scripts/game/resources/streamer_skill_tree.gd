class_name StreamerSkillTree extends Resource
## 五条线性技能分支的静态目录。首批内容只编写到 Lv3。

@export_range(0, 99, 1) var starting_skill_points: int = 2
@export_range(1, 5, 1) var authored_max_level: int = 3
@export var skills: Array[StreamerSkill] = []


func get_skills() -> Array[StreamerSkill]:
	var result: Array[StreamerSkill] = []
	result.assign(skills)
	return result


func find_skill(skill_id: StringName) -> StreamerSkill:
	for skill: StreamerSkill in skills:
		if skill != null and skill.skill_id == skill_id:
			return skill
	return null


func find_skill_unlocking_card(card_id: StringName) -> StreamerSkill:
	for skill: StreamerSkill in skills:
		if skill != null and card_id in skill.unlocked_card_ids:
			return skill
	return null


func find_family_level(family: StringName, level: int) -> StreamerSkill:
	for skill: StreamerSkill in skills:
		if skill != null and skill.family == family and skill.level == level:
			return skill
	return null


func is_valid() -> bool:
	var known_ids: Dictionary = {}
	var known_family_levels: Dictionary = {}
	for skill: StreamerSkill in skills:
		if skill == null or not skill.is_valid() or known_ids.has(skill.skill_id):
			return false
		known_ids[skill.skill_id] = true
		var family_level_key: String = "%s:%d" % [String(skill.family), skill.level]
		if known_family_levels.has(family_level_key):
			return false
		known_family_levels[family_level_key] = true
	for skill: StreamerSkill in skills:
		for required_id: StringName in skill.required_skill_ids:
			if not known_ids.has(required_id):
				return false
	for family: StringName in LiveStreamCardResource.FAMILIES:
		for level: int in range(1, authored_max_level + 1):
			if find_family_level(family, level) == null:
				return false
	return skills.size() == LiveStreamCardResource.FAMILIES.size() * authored_max_level
