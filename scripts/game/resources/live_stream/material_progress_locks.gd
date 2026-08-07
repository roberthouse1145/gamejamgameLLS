class_name MaterialProgressLocks extends Resource
## 连续素材在指定章节替换出的锁定题面；chapter 从 1 开始。

@export_range(1, 99, 1) var chapter: int = 1
@export var locked_cards: Array[MaterialLockedCard] = []


func is_valid(slot_count: int) -> bool:
	if chapter < 1:
		return false
	for locked_card: MaterialLockedCard in locked_cards:
		if locked_card == null or not locked_card.is_valid(slot_count):
			return false
	return true
