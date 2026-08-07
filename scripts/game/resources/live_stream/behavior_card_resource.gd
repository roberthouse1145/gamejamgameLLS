class_name BehaviorCardResource extends LiveStreamCardResource
## 节目单上的行为卡：左右接口使用 1~4 号纯位置槽，不承载情绪语义。

const SLOT_MIN: int = 1
const SLOT_MAX: int = 4

@export var left_slots: Array[int] = []
@export var right_slots: Array[int] = [1]
@export var axes: StreamAxisValues = null
@export var material_require: Array[StringName] = []
@export var material_boosts: Array[StreamTagEffect] = []


func get_card_kind() -> StringName:
	return &"behavior"


func is_valid() -> bool:
	if not super.is_valid() or axes == null:
		return false
	if left_slots.is_empty() and right_slots.is_empty():
		return false
	if not _are_slots_valid(left_slots) or not _are_slots_valid(right_slots):
		return false
	for boost: StreamTagEffect in material_boosts:
		if boost == null or not boost.is_valid():
			return false
	return true


func is_opening_card() -> bool:
	return left_slots.is_empty()


func is_closing_card() -> bool:
	return right_slots.is_empty()


func get_left_width() -> int:
	return left_slots.size()


func get_fill_ratio(previous_right_slots: Array[int]) -> float:
	if left_slots.is_empty():
		return 1.0
	return float(intersect_slots(previous_right_slots, left_slots).size()) / float(left_slots.size())


static func intersect_slots(first: Array[int], second: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for slot: int in range(SLOT_MIN, SLOT_MAX + 1):
		if slot in first and slot in second:
			result.append(slot)
	return result


func _are_slots_valid(values: Array[int]) -> bool:
	var seen: Dictionary = {}
	for slot: int in values:
		if slot < SLOT_MIN or slot > SLOT_MAX or seen.has(slot):
			return false
		seen[slot] = true
	return true


func is_compatible_with(material_tags: Array[StringName]) -> bool:
	for required_tag: StringName in material_require:
		if required_tag not in material_tags:
			return false
	return true
