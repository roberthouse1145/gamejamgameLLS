class_name StreamSpecialEffect extends Resource
## 不能用三轴表达的显式规则钩子，由结算器按稳定 effect_id 解释。

@export var effect_id: StringName = &""
@export var value: float = 0.0
@export_multiline var display_text: String = ""


func is_valid() -> bool:
	return not String(effect_id).is_empty()
