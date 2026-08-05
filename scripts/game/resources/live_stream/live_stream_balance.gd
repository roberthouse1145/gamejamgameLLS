class_name LiveStreamBalance extends Resource
## 首轮纵切的集中平衡参数。

@export var level_exp_thresholds: PackedInt32Array = PackedInt32Array([0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200])
@export var performance_budgets: PackedInt32Array = PackedInt32Array([10, 11, 12, 13, 14, 16, 17, 18, 19, 20])
@export var behavior_slot_levels: PackedInt32Array = PackedInt32Array([1, 3, 5, 7])
@export var modifier_slot_levels: PackedInt32Array = PackedInt32Array([3, 8])
@export var tier_unlock_levels: PackedInt32Array = PackedInt32Array([1, 4, 7])
@export var skill_node_costs: PackedInt32Array = PackedInt32Array([0, 1, 1, 2, 3])
@export_range(0.0, 1.0, 0.01) var skill_bonus_per_level: float = 0.15
@export_range(0, 100, 1) var stream_exp_reward: int = 50
@export_range(0, 100, 1) var high_stress_threshold: int = 80
@export_range(0, 20, 1) var high_stress_budget_penalty: int = 3
@export_range(0.0, 2.0, 0.05) var perfect_seam_multiplier: float = 1.2
@export_range(0.0, 2.0, 0.05) var conflict_seam_multiplier: float = 0.8
@export_range(0.0, 1.0, 0.01) var conflict_risk_bonus: float = 0.15


func get_level_for_exp(total_exp: int) -> int:
	var resolved_level: int = 1
	for index: int in range(level_exp_thresholds.size()):
		if total_exp >= level_exp_thresholds[index]:
			resolved_level = index + 1
	return clampi(resolved_level, 1, level_exp_thresholds.size())


func get_budget(streamer_level: int, stress: int = 0) -> int:
	var index: int = clampi(streamer_level, 1, performance_budgets.size()) - 1
	var result: int = performance_budgets[index]
	if stress >= high_stress_threshold:
		result -= high_stress_budget_penalty
	return maxi(result, 0)


func get_behavior_slot_count(streamer_level: int) -> int:
	var result: int = 1
	for required_level: int in behavior_slot_levels:
		if streamer_level >= required_level:
			result += 1
	return mini(result, 5)


func get_modifier_slot_count(streamer_level: int) -> int:
	var result: int = 0
	for required_level: int in modifier_slot_levels:
		if streamer_level >= required_level:
			result += 1
	return result


func get_tier_unlock_level(tier: int) -> int:
	return tier_unlock_levels[clampi(tier, 1, tier_unlock_levels.size()) - 1]


func get_skill_node_cost(level: int) -> int:
	return skill_node_costs[clampi(level, 1, skill_node_costs.size()) - 1]
