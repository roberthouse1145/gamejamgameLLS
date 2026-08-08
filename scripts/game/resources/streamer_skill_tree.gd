class_name StreamerSkillTree extends Resource
## 可扩展技能图目录：主干数量、分支层级和合流关系均由资源数据决定。

@export_range(0, 99, 1) var starting_skill_points: int = 2
@export var initially_unlocked_skill_ids: Array[StringName] = []
## 使用非严格 Array，避免磁盘序列化成 Array[ExtResource(script)] 后在方法内访问崩溃。
@export var skills: Array = []


func get_skills() -> Array[StreamerSkill]:
	var result: Array[StreamerSkill] = []
	for skill_value in _raw_skills():
		var skill: StreamerSkill = skill_value as StreamerSkill
		if skill != null:
			result.append(skill)
	return result


func find_skill(skill_id: StringName) -> StreamerSkill:
	for skill_value in _raw_skills():
		var skill: StreamerSkill = skill_value as StreamerSkill
		if skill != null and skill.skill_id == skill_id:
			return skill
	return null


func find_skill_unlocking_card(card_id: StringName) -> StreamerSkill:
	for skill_value in _raw_skills():
		var skill: StreamerSkill = skill_value as StreamerSkill
		if skill != null and card_id in skill.unlocked_card_ids:
			return skill
	return null


func is_valid() -> bool:
	var known_ids: Dictionary = {}
	var indegrees: Dictionary = {}
	var dependents: Dictionary = {}
	var skill_list: Array[StreamerSkill] = get_skills()
	for skill in skill_list:
		if skill == null or not _skill_fields_valid(skill) or known_ids.has(skill.skill_id):
			return false
		known_ids[skill.skill_id] = true
		indegrees[skill.skill_id] = 0
		dependents[skill.skill_id] = []
	if known_ids.is_empty():
		return false
	for skill in skill_list:
		for required_id_value in skill.required_skill_ids:
			var required_id: StringName = required_id_value as StringName
			if required_id == skill.skill_id or not known_ids.has(required_id):
				return false
			indegrees[skill.skill_id] = int(indegrees[skill.skill_id]) + 1
			var children: Array = dependents[required_id]
			children.append(skill.skill_id)
			dependents[required_id] = children
	var initial_ids: Variant = get("initially_unlocked_skill_ids")
	if initial_ids != null:
		for skill_id_value in initial_ids as Array:
			var skill_id: StringName = skill_id_value as StringName
			var initial_skill: StreamerSkill = find_skill(skill_id)
			if initial_skill == null or not initial_skill.required_skill_ids.is_empty():
				return false

	var ready_ids: Array[StringName] = []
	for skill in skill_list:
		if int(indegrees[skill.skill_id]) == 0:
			ready_ids.append(skill.skill_id)
	var visited_count: int = 0
	while not ready_ids.is_empty():
		var current_id: StringName = ready_ids.pop_back()
		visited_count += 1
		for child_id_value in dependents[current_id]:
			var child_id: StringName = child_id_value as StringName
			indegrees[child_id] = int(indegrees[child_id]) - 1
			if int(indegrees[child_id]) == 0:
				ready_ids.append(child_id)
	return visited_count == skill_list.size()


func _raw_skills() -> Array:
	var raw: Variant = get("skills")
	if raw == null:
		return []
	var copied: Array = []
	for skill_value in raw as Array:
		copied.append(skill_value)
	return copied


func _skill_fields_valid(skill: StreamerSkill) -> bool:
	if skill == null:
		return false
	if String(skill.skill_id).is_empty() or skill.display_name.strip_edges().is_empty():
		return false
	if String(skill.family).is_empty() or skill.level < 1:
		return false
	var effects: Variant = skill.get("rule_effects")
	if effects == null:
		return true
	for effect_value in effects as Array:
		if effect_value == null or String(effect_value.get("effect_id")).is_empty():
			return false
	return true
