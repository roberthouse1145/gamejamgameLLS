class_name StreamPlanSnapshot extends Resource
## 一场直播在开播瞬间冻结的不可变输入快照。

@export var session_id: StringName = &""
@export var title: String = ""
@export var persona_id: StringName = &""
@export var material_instance_id: StringName = &""
@export var approach: Dictionary = {}
@export var rng_seed: int = 0
@export var state_snapshot: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"session_id": String(session_id),
		"title": title,
		"persona_id": String(persona_id),
		"material_instance_id": String(material_instance_id),
		"approach": approach.duplicate(true),
		"rng_seed": rng_seed,
		"state_snapshot": state_snapshot.duplicate(true),
	}
