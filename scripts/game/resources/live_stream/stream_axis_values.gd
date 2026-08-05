class_name StreamAxisValues extends Resource
## 四轴数值。行为卡使用加法值，修饰卡使用倍率增量。

const KEYS: Array[StringName] = [&"hook", &"quality", &"impact", &"risk"]

@export var hook: float = 0.0
@export var quality: float = 0.0
@export var impact: float = 0.0
@export var risk: float = 0.0


func get_value(axis_key: StringName) -> float:
	match axis_key:
		&"hook":
			return hook
		&"quality":
			return quality
		&"impact":
			return impact
		&"risk":
			return risk
	return 0.0


func to_dict() -> Dictionary:
	return {
		"hook": hook,
		"quality": quality,
		"impact": impact,
		"risk": risk,
	}
