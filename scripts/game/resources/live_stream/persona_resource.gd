class_name StreamPersonaResource extends StreamContentResource
## 一个人设档位的静态定义：玩法、生成提示和出镜模型的组合入口。

@export var model: StreamerModelResource = null
## 保留字段：基础表现倍率。暂不参与玩法结算，仅留作后续设计的占位。
@export_range(0.0, 2.0, 0.05) var base_performance_multiplier: float = 1.0
## 保留字段：熟练度初始值。暂不参与玩法结算，仅留作后续设计的占位。
@export_range(0.0, 100.0, 1.0) var initial_proficiency: float = 0.0
## 保留字段：固化度初始值。暂不参与玩法结算，仅留作后续设计的占位。
@export_range(0.0, 100.0, 1.0) var initial_fixation: float = 0.0


func is_valid() -> bool:
	return (
		is_valid_base()
		and model != null
		and model.is_valid()
		and base_performance_multiplier > 0.0
	)
