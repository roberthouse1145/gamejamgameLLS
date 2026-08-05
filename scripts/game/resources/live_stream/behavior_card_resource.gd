class_name BehaviorCardResource extends LiveStreamCardResource
## 节目单上的行为卡：有左右情绪槽，向四轴注入数值。

const MOOD_OPEN: StringName = &"open"
const MOOD_HOT: StringName = &"hot"
const MOOD_CALM: StringName = &"calm"
const MOOD_WARM: StringName = &"warm"
const MOOD_GLOOM: StringName = &"gloom"
const MOODS: Array[StringName] = [MOOD_OPEN, MOOD_HOT, MOOD_CALM, MOOD_WARM, MOOD_GLOOM]

@export var mood_in: StringName = MOOD_OPEN
@export var mood_out: StringName = MOOD_WARM
@export var axes: StreamAxisValues = null
@export var material_require: Array[StringName] = []
@export var material_boosts: Array[StreamTagEffect] = []


func get_card_kind() -> StringName:
	return &"behavior"


func is_valid() -> bool:
	if not super.is_valid() or mood_in not in MOODS or mood_out not in MOODS or axes == null:
		return false
	if mood_in == MOOD_OPEN and mood_out == MOOD_OPEN:
		return false
	for boost: StreamTagEffect in material_boosts:
		if boost == null or not boost.is_valid():
			return false
	return true


func is_compatible_with(material_tags: Array[StringName]) -> bool:
	for required_tag: StringName in material_require:
		if required_tag not in material_tags:
			return false
	return true
