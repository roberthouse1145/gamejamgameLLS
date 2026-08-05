class_name LiveStreamMaterialResource extends StreamContentResource
## 可被重复获得的素材定义；含量、进度、新鲜度属于实例状态。

const TYPE_CONTINUOUS: StringName = &"continuous"
const TYPE_CONSUMABLE: StringName = &"consumable"

@export var material_type: StringName = TYPE_CONTINUOUS
@export_range(0.0, 20.0, 0.5) var initial_depth: float = 4.0
@export_range(0, 99, 1) var max_progress: int = 4
@export_range(0.0, 1.0, 0.05) var freshness_decay: float = 0.2
@export_range(0.0, 10000.0, 1.0) var base_popularity: float = 100.0
@export var affinity: StreamFamilyValues = null
@export var axes: StreamAxisValues = null
@export var combo_effects: Array[StreamTagEffect] = []


func is_valid() -> bool:
	if not is_valid_base() or material_type not in [TYPE_CONTINUOUS, TYPE_CONSUMABLE]:
		return false
	if initial_depth <= 0.0 or affinity == null or axes == null:
		return false
	for combo: StreamTagEffect in combo_effects:
		if combo == null or not combo.is_valid():
			return false
	return true
