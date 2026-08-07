class_name StreamPlanSnapshot extends Resource
## 一场直播在开播瞬间冻结的不可变输入快照。

@export var session_id: StringName = &""
@export var title: String = ""
@export var persona_id: StringName = &""
@export var material_instance_id: StringName = &""
@export var behavior_card_ids: Array[StringName] = []
@export var locked_behavior_slot_indices: PackedInt32Array = PackedInt32Array()
@export var modifier_card_ids: Array[StringName] = []
@export var rng_seed: int = 0
@export var state_snapshot: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"session_id": String(session_id),
		"title": title,
		"persona_id": String(persona_id),
		"material_instance_id": String(material_instance_id),
		"behavior_card_ids": behavior_card_ids.map(func(value: StringName) -> String: return String(value)),
		"locked_behavior_slot_indices": Array(locked_behavior_slot_indices),
		"modifier_card_ids": modifier_card_ids.map(func(value: StringName) -> String: return String(value)),
		"rng_seed": rng_seed,
		"state_snapshot": state_snapshot.duplicate(true),
	}
