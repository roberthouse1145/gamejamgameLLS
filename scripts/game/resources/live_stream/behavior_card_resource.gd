class_name BehaviorCardResource extends LiveStreamCardResource
## 节目单上的行为卡：有左右情绪槽，向四轴注入数值。

const MOOD_OPEN: StringName = &"open"
const MOOD_HOT: StringName = &"hot"
const MOOD_CALM: StringName = &"calm"
const MOOD_WARM: StringName = &"warm"
const MOOD_GLOOM: StringName = &"gloom"
const MOODS: Array[StringName] = [MOOD_HOT, MOOD_CALM, MOOD_WARM, MOOD_GLOOM]

@export var mood_inputs: Array[StringName] = []
@export var mood_outputs: Array[StringName] = [MOOD_WARM]
@export var axes: StreamAxisValues = null
@export var material_require: Array[StringName] = []
@export var material_boosts: Array[StreamTagEffect] = []


func get_card_kind() -> StringName:
	return &"behavior"


func is_valid() -> bool:
	if not super.is_valid() or axes == null:
		return false
	if mood_inputs.is_empty() and mood_outputs.is_empty():
		return false
	if not _are_moods_valid(mood_inputs) or not _are_moods_valid(mood_outputs):
		return false
	for boost: StreamTagEffect in material_boosts:
		if boost == null or not boost.is_valid():
			return false
	return true


func is_opening_card() -> bool:
	return mood_inputs.is_empty()


func is_closing_card() -> bool:
	return mood_outputs.is_empty()


func has_mood(mood: StringName) -> bool:
	return mood in mood_inputs or mood in mood_outputs


func _are_moods_valid(values: Array[StringName]) -> bool:
	var seen: Dictionary = {}
	for mood: StringName in values:
		if mood not in MOODS or seen.has(mood):
			return false
		seen[mood] = true
	return true


func is_compatible_with(material_tags: Array[StringName]) -> bool:
	for required_tag: StringName in material_require:
		if required_tag not in material_tags:
			return false
	return true
