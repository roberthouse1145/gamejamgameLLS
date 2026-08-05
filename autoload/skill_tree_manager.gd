extends Node
## 五条线性技能分支与公共成长点的唯一业务入口。

signal skill_tree_changed()
signal skill_unlocked(skill: StreamerSkill)
signal skill_points_changed(value: int)

const SKILL_TREE: StreamerSkillTree = preload("res://resources/live_stream/skills/vertical_slice_skill_tree.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")


func _ready() -> void:
	if not SKILL_TREE.is_valid():
		push_error("SkillTreeManager: invalid five-family skill tree")
	GameState.streamer_progress_changed.connect(_on_progress_changed)
	GameState.skill_levels_changed.connect(_on_skill_level_changed)
	_ensure_state()


func get_skill_tree() -> StreamerSkillTree:
	return SKILL_TREE


func get_skills() -> Array[StreamerSkill]:
	return SKILL_TREE.get_skills()


func get_skill(skill_id: StringName) -> StreamerSkill:
	return SKILL_TREE.find_skill(skill_id)


func get_skill_points() -> int:
	return GameState.growth_points


func get_family_level(family: StringName) -> int:
	return GameState.get_skill_level(family)


func get_unlocked_skill_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for skill: StreamerSkill in SKILL_TREE.skills:
		if skill != null and is_unlocked(skill.skill_id):
			result.append(skill.skill_id)
	return result


func is_unlocked(skill_id: StringName) -> bool:
	var skill: StreamerSkill = get_skill(skill_id)
	return skill != null and skill.level <= GameState.get_skill_level(skill.family)


func can_unlock(skill_id: StringName) -> bool:
	var skill: StreamerSkill = get_skill(skill_id)
	if skill == null or is_unlocked(skill_id):
		return false
	if skill.level != GameState.get_skill_level(skill.family) + 1:
		return false
	return skill.level <= SKILL_TREE.authored_max_level and GameState.growth_points >= skill.point_cost


func get_unlock_reason(skill_id: StringName) -> String:
	var skill: StreamerSkill = get_skill(skill_id)
	if skill == null:
		return "成长节点不存在"
	if is_unlocked(skill_id):
		return "已掌握"
	var current_level: int = GameState.get_skill_level(skill.family)
	if skill.level > current_level + 1:
		return "需要先掌握 Lv.%d" % (skill.level - 1)
	if GameState.growth_points < skill.point_cost:
		return "成长点不足"
	return "可以解锁"


func unlock_skill(skill_id: StringName) -> bool:
	if not can_unlock(skill_id):
		return false
	var skill: StreamerSkill = get_skill(skill_id)
	GameState.set_growth_points(GameState.growth_points - skill.point_cost)
	GameState.set_skill_level(skill.family, skill.level)
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


func find_skill_unlocking_card(card_id: StringName) -> StreamerSkill:
	return SKILL_TREE.find_skill_unlocking_card(card_id)


func get_rule_effects(family: StringName) -> Array[StreamSpecialEffect]:
	var result: Array[StreamSpecialEffect] = []
	var current_level: int = GameState.get_skill_level(family)
	for level: int in range(1, current_level + 1):
		var skill: StreamerSkill = SKILL_TREE.find_family_level(family, level)
		if skill != null:
			result.append_array(skill.rule_effects)
	return result


func reset_to_defaults() -> void:
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.set_growth_points(SKILL_TREE.starting_skill_points)
	for family: StringName in GameState.SKILL_FAMILIES:
		GameState.skill_levels_changed.emit(family, 1)
	skill_points_changed.emit(GameState.growth_points)
	skill_tree_changed.emit()


func get_run_state() -> Dictionary:
	return {
		"growth_points": GameState.growth_points,
		"skill_levels": GameState.skill_levels.duplicate(true),
	}


func load_run_state(data: Dictionary) -> void:
	GameState.growth_points = maxi(int(data.get("growth_points", SKILL_TREE.starting_skill_points)), 0)
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	var loaded_levels: Variant = data.get("skill_levels", {})
	if loaded_levels is Dictionary:
		for family: StringName in GameState.SKILL_FAMILIES:
			GameState.skill_levels[String(family)] = clampi(int((loaded_levels as Dictionary).get(String(family), 1)), 1, SKILL_TREE.authored_max_level)
	skill_points_changed.emit(GameState.growth_points)
	skill_tree_changed.emit()


func _ensure_state() -> void:
	for family: StringName in GameState.SKILL_FAMILIES:
		if not GameState.skill_levels.has(String(family)):
			GameState.skill_levels[String(family)] = 1


func _on_progress_changed(_level: int, _exp: int, points: int) -> void:
	skill_points_changed.emit(points)
	skill_tree_changed.emit()


func _on_skill_level_changed(_family: StringName, _level: int) -> void:
	skill_tree_changed.emit()
