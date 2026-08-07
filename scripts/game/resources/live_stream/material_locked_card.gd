class_name MaterialLockedCard extends Resource
## 素材题面中的专属卡位置约束。position 使用玩家可见的 1-based 槽位编号。

const MODE_STRICT: StringName = &"strict"
const MODE_LOOSE: StringName = &"loose"

@export var card_id: StringName = &""
@export_range(1, 6, 1) var position: int = 1
@export var mode: StringName = MODE_STRICT
@export_range(1, 6, 1) var min_position: int = 1
@export_range(1, 6, 1) var max_position: int = 1


func is_valid(slot_count: int) -> bool:
	if card_id == &"" or position < 1 or position > slot_count:
		return false
	if mode == MODE_STRICT:
		return true
	if mode != MODE_LOOSE:
		return false
	return min_position >= 1 and max_position <= slot_count and min_position <= position and position <= max_position


func get_allowed_positions() -> PackedInt32Array:
	if mode == MODE_STRICT:
		return PackedInt32Array([position])
	var result := PackedInt32Array()
	for value: int in range(min_position, max_position + 1):
		result.append(value)
	return result
