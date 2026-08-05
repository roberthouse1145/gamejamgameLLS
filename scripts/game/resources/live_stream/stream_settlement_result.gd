class_name StreamSettlementResult extends Resource
## 代码预结算产生的结果；提交前不修改任何运行时状态。

@export var session_id: StringName = &""
@export var axes: Dictionary = {}
@export var peak_viewers: int = 0
@export var fan_delta: int = 0
@export var revenue: int = 0
@export var accident_probability: float = 0.0
@export var accident_occurred: bool = false
@export var stress_delta: int = 0
@export var streamer_exp_gain: int = 0
@export var resulting_fan_vector: Dictionary = {}
@export var material_use: Dictionary = {}
@export var mood_flow: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {
		"session_id": String(session_id),
		"axes": axes.duplicate(true),
		"peak_viewers": peak_viewers,
		"fan_delta": fan_delta,
		"revenue": revenue,
		"accident_probability": accident_probability,
		"accident_occurred": accident_occurred,
		"stress_delta": stress_delta,
		"streamer_exp_gain": streamer_exp_gain,
		"resulting_fan_vector": resulting_fan_vector.duplicate(true),
		"material_use": material_use.duplicate(true),
		"mood_flow": mood_flow.duplicate(true),
	}
