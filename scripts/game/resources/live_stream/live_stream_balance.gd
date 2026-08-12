class_name LiveStreamBalance extends Resource
## 首轮纵切的集中平衡参数。

const APPROACH_TYPES: Array[StringName] = [
	&"analysis",
	&"challenge",
	&"audience_interaction",
	&"performance",
	&"personal_story",
	&"production",
]

const APPROACH_PROFILES: Dictionary = {
	"analysis": {
		"label": "深入拆解",
		"player_hint": "更重内容理解与讲解",
		"axes": {"hook": 1.0, "quality": 3.0, "impact": 1.4},
		"stress": 2.0,
		"fan_bias": {"c": 1.0},
		"support_families": [&"talk"],
	},
	"challenge": {
		"label": "目标挑战",
		"player_hint": "更重过程张力与结果",
		"axes": {"hook": 3.0, "quality": 1.5, "impact": 2.0},
		"stress": 5.0,
		"fan_bias": {"r": 2.0, "b": 0.5},
		"support_families": [&"game"],
	},
	"audience_interaction": {
		"label": "弹幕共创",
		"player_hint": "更重观众参与与临场反应",
		"axes": {"hook": 2.5, "quality": 1.5, "impact": 3.0},
		"stress": 3.0,
		"fan_bias": {"r": 1.0, "c": 2.0},
		"support_families": [&"talk", &"act"],
	},
	"performance": {
		"label": "舞台表现",
		"player_hint": "更重歌声、声线与演出完成度",
		"axes": {"hook": 2.0, "quality": 2.5, "impact": 3.2},
		"stress": 4.0,
		"fan_bias": {"c": 2.0},
		"support_families": [&"song", &"act"],
	},
	"personal_story": {
		"label": "个人切入",
		"player_hint": "更重情绪连接与人物表达",
		"axes": {"hook": 1.2, "quality": 2.6, "impact": 3.4},
		"stress": 3.0,
		"fan_bias": {"r": -0.5, "c": 3.0},
		"support_families": [&"talk", &"act"],
	},
	"production": {
		"label": "企划制作",
		"player_hint": "更重节目结构与制作感",
		"axes": {"hook": 2.2, "quality": 3.0, "impact": 2.0},
		"stress": 4.0,
		"fan_bias": {"r": 1.0, "c": 1.0},
		"support_families": [&"tech", &"talk"],
	},
}

@export var level_exp_thresholds: PackedInt32Array = PackedInt32Array([0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200])
@export var skill_exp_thresholds: PackedInt32Array = PackedInt32Array([0, 100, 300, 600, 1000])
@export var skill_node_costs: PackedInt32Array = PackedInt32Array([0, 1, 1, 2, 3])
@export_range(0.0, 1.0, 0.01) var skill_bonus_per_level: float = 0.15


func get_level_for_exp(total_exp: int) -> int:
	var resolved_level: int = 1
	for index: int in range(level_exp_thresholds.size()):
		if total_exp >= level_exp_thresholds[index]:
			resolved_level = index + 1
	return clampi(resolved_level, 1, level_exp_thresholds.size())


func get_skill_level_for_exp(total_exp: int) -> int:
	var resolved_level: int = 1
	for index: int in range(skill_exp_thresholds.size()):
		if total_exp >= skill_exp_thresholds[index]:
			resolved_level = index + 1
	return clampi(resolved_level, 1, skill_exp_thresholds.size())


func get_approach_profile(approach_type: StringName) -> Dictionary:
	var profile: Variant = APPROACH_PROFILES.get(String(approach_type), {})
	return (profile as Dictionary).duplicate(true)


func get_skill_node_cost(level: int) -> int:
	return skill_node_costs[clampi(level, 1, skill_node_costs.size()) - 1]
