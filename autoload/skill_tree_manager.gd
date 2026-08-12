extends Node
## 数据驱动技能图与公共成长点的唯一业务入口。

signal skill_tree_changed()
signal skill_unlocked(skill: StreamerSkill)
signal skill_points_changed(value: int)

const SKILL_TREE_PATH: String = "res://resources/live_stream/skills/vertical_slice_skill_tree.tres"
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")

var _skill_tree: StreamerSkillTree = null


func _ready() -> void:
	_skill_tree = _hydrate_skill_tree(load(SKILL_TREE_PATH))
	if _skill_tree == null or not _skill_tree.is_valid():
		push_error("SkillTreeManager: invalid skill graph")
	GameState.streamer_progress_changed.connect(_on_progress_changed)
	GameState.skill_levels_changed.connect(_on_skill_level_changed)
	_ensure_state()


func get_skill_tree() -> StreamerSkillTree:
	return _skill_tree


func get_skills() -> Array[StreamerSkill]:
	return _skill_tree.get_skills()


func get_skill(skill_id: StringName) -> StreamerSkill:
	return _skill_tree.find_skill(skill_id)


func get_skill_points() -> int:
	return GameState.growth_points


func get_family_level(family: StringName) -> int:
	return GameState.get_skill_level(family)


func get_unlocked_skill_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for skill: StreamerSkill in get_skills():
		if is_unlocked(skill.skill_id):
			result.append(skill.skill_id)
	return result


func is_unlocked(skill_id: StringName) -> bool:
	return get_skill(skill_id) != null and skill_id in GameState.unlocked_skill_ids


func can_unlock(skill_id: StringName) -> bool:
	var skill: StreamerSkill = get_skill(skill_id)
	if skill == null or is_unlocked(skill_id):
		return false
	for required_id: StringName in skill.required_skill_ids:
		if not is_unlocked(required_id):
			return false
	return GameState.growth_points >= skill.point_cost


func get_unlock_reason(skill_id: StringName) -> String:
	var skill: StreamerSkill = get_skill(skill_id)
	if skill == null:
		return "成长节点不存在"
	if is_unlocked(skill_id):
		return "已掌握"
	var missing_names: Array[String] = []
	for required_id: StringName in skill.required_skill_ids:
		if is_unlocked(required_id):
			continue
		var required_skill: StreamerSkill = get_skill(required_id)
		missing_names.append(required_skill.display_name if required_skill != null else String(required_id))
	if not missing_names.is_empty():
		return "需要先掌握：%s" % "、".join(missing_names)
	if GameState.growth_points < skill.point_cost:
		return "成长点不足"
	return "可以解锁"


func unlock_skill(skill_id: StringName) -> bool:
	if not can_unlock(skill_id):
		return false
	var skill: StreamerSkill = get_skill(skill_id)
	GameState.set_growth_points(GameState.growth_points - skill.point_cost)
	GameState.add_unlocked_skill_id(skill.skill_id)
	skill_unlocked.emit(skill)
	skill_points_changed.emit(GameState.growth_points)
	skill_tree_changed.emit()
	return true


func grant_skill_points(amount: int) -> void:
	if amount <= 0:
		return
	GameState.set_growth_points(GameState.growth_points + amount)
	skill_points_changed.emit(GameState.growth_points)
	skill_tree_changed.emit()


func reset_to_defaults() -> void:
	GameState.set_unlocked_skill_ids(_skill_tree.initially_unlocked_skill_ids)
	GameState.set_growth_points(_skill_tree.starting_skill_points)
	skill_points_changed.emit(GameState.growth_points)
	skill_tree_changed.emit()


func get_run_state() -> Dictionary:
	return {
		"growth_points": GameState.growth_points,
		"unlocked_skill_ids": GameState.unlocked_skill_ids.duplicate(),
	}


func load_run_state(data: Dictionary) -> void:
	GameState.growth_points = maxi(int(data.get("growth_points", _skill_tree.starting_skill_points)), 0)
	var loaded_ids: Array[StringName] = []
	for skill_id: Variant in data.get("unlocked_skill_ids", []):
		var normalized_id := StringName(str(skill_id))
		if _skill_tree.find_skill(normalized_id) != null and normalized_id not in loaded_ids:
			loaded_ids.append(normalized_id)
	GameState.set_unlocked_skill_ids(_normalize_unlocked_ids(loaded_ids))
	skill_points_changed.emit(GameState.growth_points)
	skill_tree_changed.emit()


func _hydrate_skill_tree(source: Resource) -> StreamerSkillTree:
	# Disk-loaded StreamerSkillTree instances can crash when their own methods
	# touch exported arrays; rebuild a runtime instance and keep the skill refs.
	if source == null:
		return null
	var tree := StreamerSkillTree.new()
	tree.starting_skill_points = int(source.get("starting_skill_points"))
	var initial_ids: Array[StringName] = []
	var raw_initial: Variant = source.get("initially_unlocked_skill_ids")
	if raw_initial != null:
		for skill_id_value in raw_initial as Array:
			initial_ids.append(skill_id_value as StringName)
	tree.initially_unlocked_skill_ids = initial_ids
	var skills: Array = []
	var raw_skills: Variant = source.get("skills")
	if raw_skills != null:
		for skill_value in raw_skills as Array:
			skills.append(skill_value)
	tree.skills = skills
	return tree


func _ensure_state() -> void:
	GameState.set_unlocked_skill_ids(_normalize_unlocked_ids(GameState.unlocked_skill_ids))


func _normalize_unlocked_ids(candidate_ids: Array[StringName]) -> Array[StringName]:
	var normalized_ids: Array[StringName] = []
	for initial_id: StringName in _skill_tree.initially_unlocked_skill_ids:
		if initial_id not in normalized_ids:
			normalized_ids.append(initial_id)
	var changed: bool = true
	while changed:
		changed = false
		for skill: StreamerSkill in get_skills():
			if skill.skill_id not in candidate_ids or skill.skill_id in normalized_ids:
				continue
			var prerequisites_met: bool = true
			for required_id: StringName in skill.required_skill_ids:
				if required_id not in normalized_ids:
					prerequisites_met = false
					break
			if prerequisites_met:
				normalized_ids.append(skill.skill_id)
				changed = true
	return normalized_ids


func _on_progress_changed(_level: int, _exp: int, points: int) -> void:
	skill_points_changed.emit(points)
	skill_tree_changed.emit()


func _on_skill_level_changed(_family: StringName, _level: int) -> void:
	skill_tree_changed.emit()
