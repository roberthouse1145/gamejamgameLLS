class_name StreamTagEffect extends Resource
## 素材 tag 命中后，对行为卡某一轴应用的倍率。

@export var with_tag: StringName = &""
@export var axis_key: StringName = &"impact"
@export_range(0.0, 5.0, 0.05) var multiplier: float = 1.3


func is_valid() -> bool:
	return not String(with_tag).is_empty() and axis_key in StreamAxisValues.KEYS and multiplier >= 0.0
