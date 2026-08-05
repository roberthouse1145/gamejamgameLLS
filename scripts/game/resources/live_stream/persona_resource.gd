class_name StreamPersonaResource extends StreamContentResource
## 一个人设档位的静态定义。首期只提供剧情默认人设。

@export_range(0.0, 2.0, 0.05) var base_performance_multiplier: float = 1.0
@export_range(0.0, 100.0, 1.0) var initial_proficiency: float = 0.0
@export_range(0.0, 100.0, 1.0) var initial_fixation: float = 0.0


func is_valid() -> bool:
	return is_valid_base() and base_performance_multiplier > 0.0
