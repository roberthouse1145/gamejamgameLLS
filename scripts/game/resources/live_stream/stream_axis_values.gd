class_name StreamAxisValues extends Resource
## 三轴数值：噱头、质量与效果。

const KEYS: Array[StringName] = [&"hook", &"quality", &"impact"]

@export var hook: float = 0.0
@export var quality: float = 0.0
@export var impact: float = 0.0


func get_value(axis_key: StringName) -> float:
	match axis_key:
		&"hook":
			return hook
		&"quality":
			return quality
		&"impact":
			return impact
	return 0.0


func to_dict() -> Dictionary:
	return {
		"hook": hook,
		"quality": quality,
		"impact": impact,
	}
