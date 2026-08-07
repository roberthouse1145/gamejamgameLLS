class_name ModifierCardResource extends LiveStreamCardResource
## 全场滤镜卡：不参与节目接缝，作用于整场规则。

const KIND_TONE: StringName = &"tone"
const KIND_PROJECT: StringName = &"project"

@export var modifier_kind: StringName = KIND_TONE
@export var axis_multiplier_bonus: StreamAxisValues = null
@export var target_family: StringName = &""


func get_card_kind() -> StringName:
	return &"modifier"


func is_valid() -> bool:
	if not super.is_valid() or modifier_kind not in [KIND_TONE, KIND_PROJECT] or axis_multiplier_bonus == null:
		return false
	if target_family != &"" and target_family not in FAMILIES:
		return false
	return true
