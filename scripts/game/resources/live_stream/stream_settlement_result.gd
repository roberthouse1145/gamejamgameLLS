class_name StreamSettlementResult extends Resource
## 代码预结算产生的结果；提交前不修改任何运行时状态。

@export var session_id: StringName = &""
@export var axes: Dictionary = {}
@export var peak_viewers: int = 0
@export var fan_delta: int = 0
@export var revenue: int = 0
@export var sponsor_payout: int = 0
@export var sponsor_satisfied: bool = true
@export var stress_delta: int = 0
@export var skill_exp_gains: Dictionary = {}
## 本场各领域熟练度之和，同时用于推进中之人总等级。
@export var streamer_exp_gain: int = 0
@export var resulting_fan_vector: Dictionary = {}
@export var material_use: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"session_id": String(session_id),
		"axes": axes.duplicate(true),
		"peak_viewers": peak_viewers,
		"fan_delta": fan_delta,
		"revenue": revenue,
		"sponsor_payout": sponsor_payout,
		"sponsor_satisfied": sponsor_satisfied,
		"stress_delta": stress_delta,
		"skill_exp_gains": skill_exp_gains.duplicate(true),
		"streamer_exp_gain": streamer_exp_gain,
		"resulting_fan_vector": resulting_fan_vector.duplicate(true),
		"material_use": material_use.duplicate(true),
	}
