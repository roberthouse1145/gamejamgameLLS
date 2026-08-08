class_name LiveStreamMaterialResource extends StreamContentResource
## 可被重复获得的素材定义；含量、进度、新鲜度属于实例状态。

const TYPE_CONTINUOUS: StringName = &"continuous"
const TYPE_CONSUMABLE: StringName = &"consumable"
const TYPE_SPONSOR: StringName = &"sponsor"

@export var material_type: StringName = TYPE_CONTINUOUS
@export_range(0.0, 20.0, 0.5) var initial_depth: float = 4.0
@export_range(0, 99, 1) var max_progress: int = 4
@export_range(0.0, 1.0, 0.05) var freshness_decay: float = 0.2
@export_range(0.0, 10000.0, 1.0) var base_popularity: float = 100.0
@export_range(2, 6, 1) var program_slot_count: int = 2
@export var affinity: StreamFamilyValues = null
@export var axes: StreamAxisValues = null
@export var combo_effects: Array[StreamTagEffect] = []
@export var locked_cards: Array[MaterialLockedCard] = []
@export var progress_locks: Array[MaterialProgressLocks] = []
@export var sponsor_terms: MaterialSponsorTerms = null


func is_valid() -> bool:
	if not is_valid_base() or material_type not in [TYPE_CONTINUOUS, TYPE_CONSUMABLE, TYPE_SPONSOR]:
		return false
	if initial_depth <= 0.0 or program_slot_count < 2 or program_slot_count > 6 or affinity == null or axes == null:
		return false
	for combo: StreamTagEffect in combo_effects:
		if combo == null or not combo.is_valid():
			return false
	for locked_card: MaterialLockedCard in locked_cards:
		if locked_card == null or not locked_card.is_valid(program_slot_count):
			return false
	var chapters: Dictionary = {}
	for progress_lock: MaterialProgressLocks in progress_locks:
		if progress_lock == null or not progress_lock.is_valid(program_slot_count) or chapters.has(progress_lock.chapter):
			return false
		chapters[progress_lock.chapter] = true
	if material_type == TYPE_SPONSOR and (sponsor_terms == null or not sponsor_terms.is_valid()):
		return false
	return true


func get_material_type_label() -> String:
	match material_type:
		TYPE_CONSUMABLE:
			return "消耗型"
		TYPE_SPONSOR:
			return "商单型"
	return "连续型"


func get_locked_cards_for_progress(progress: int) -> Array[MaterialLockedCard]:
	var chapter: int = progress + 1
	for progress_lock: MaterialProgressLocks in progress_locks:
		if progress_lock != null and progress_lock.chapter == chapter:
			var chapter_result: Array[MaterialLockedCard] = []
			chapter_result.assign(progress_lock.locked_cards)
			return chapter_result
	var result: Array[MaterialLockedCard] = []
	result.assign(locked_cards)
	return result
