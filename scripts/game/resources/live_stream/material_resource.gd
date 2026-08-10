class_name LiveStreamMaterialResource extends StreamContentResource
## 一次性素材定义；播一场烧一张，无含量/进度/新鲜度（见策划案 §6.1）。

const TYPE_CONSUMABLE: StringName = &"consumable"
const TYPE_SPONSOR: StringName = &"sponsor"

@export var material_type: StringName = TYPE_CONSUMABLE
@export_range(0.0, 10000.0, 1.0) var base_popularity: float = 100.0
@export_range(2, 6, 1) var program_slot_count: int = 2
@export var affinity: StreamFamilyValues = null
@export var axes: StreamAxisValues = null
@export var combo_effects: Array[StreamTagEffect] = []
@export var locked_cards: Array[MaterialLockedCard] = []
@export var sponsor_terms: MaterialSponsorTerms = null


func is_valid() -> bool:
	if not is_valid_base() or material_type not in [TYPE_CONSUMABLE, TYPE_SPONSOR]:
		return false
	if program_slot_count < 2 or program_slot_count > 6 or affinity == null or axes == null:
		return false
	for combo: StreamTagEffect in combo_effects:
		if combo == null or not combo.is_valid():
			return false
	for locked_card: MaterialLockedCard in locked_cards:
		if locked_card == null or not locked_card.is_valid(program_slot_count):
			return false
	if material_type == TYPE_SPONSOR and (sponsor_terms == null or not sponsor_terms.is_valid()):
		return false
	return true


func get_material_type_label() -> String:
	if material_type == TYPE_SPONSOR:
		return "商单型"
	return "消耗型"
