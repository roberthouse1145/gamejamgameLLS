extends Node
## 素材定义与可变实例状态的唯一业务入口。

signal inventory_changed()
signal material_granted(instance_id: StringName)
signal material_consumed(instance_id: StringName)

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")


func _ready() -> void:
	_ensure_default_inventory()


func get_material_definition(material_id: StringName) -> LiveStreamMaterialResource:
	return CATALOG.get_material(material_id)


func get_definition_for_instance(instance_id: StringName) -> LiveStreamMaterialResource:
	var instance: Dictionary = get_instance(instance_id)
	return get_material_definition(StringName(str(instance.get("definition_id", ""))))


func get_instance(instance_id: StringName) -> Dictionary:
	return (GameState.material_instances.get(String(instance_id), {}) as Dictionary).duplicate(true)


func get_instances() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance_id: String in GameState.material_instances:
		var instance: Dictionary = (GameState.material_instances[instance_id] as Dictionary).duplicate(true)
		instance["instance_id"] = instance_id
		result.append(instance)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("instance_id", "")) < str(b.get("instance_id", "")))
	return result


func grant_material(material_id: StringName) -> StringName:
	var definition: LiveStreamMaterialResource = get_material_definition(material_id)
	if definition == null:
		return &""
	GameState.material_serial += 1
	var instance_id := StringName("%s_%03d" % [String(material_id), GameState.material_serial])
	GameState.material_instances[String(instance_id)] = {
		"definition_id": String(material_id),
	}
	inventory_changed.emit()
	material_granted.emit(instance_id)
	return instance_id


func preview_use(instance_id: StringName) -> Dictionary:
	var instance: Dictionary = get_instance(instance_id)
	var definition: LiveStreamMaterialResource = get_definition_for_instance(instance_id)
	if instance.is_empty() or definition == null:
		return {}
	return {
		"instance_id": String(instance_id),
		"material_type": String(definition.material_type),
	}


## 一次性素材：播一场烧一张（策划案 §6.1），统一从库存删除。
func commit_use(use_delta: Dictionary) -> bool:
	var instance_id: String = str(use_delta.get("instance_id", ""))
	if instance_id.is_empty() or not GameState.material_instances.has(instance_id):
		return false
	GameState.material_instances.erase(instance_id)
	inventory_changed.emit()
	material_consumed.emit(StringName(instance_id))
	return true


func reset_to_defaults() -> void:
	GameState.material_instances.clear()
	GameState.material_serial = 0
	for material: LiveStreamMaterialResource in CATALOG.materials:
		if material != null:
			grant_material(material.content_id)
	inventory_changed.emit()


func _ensure_default_inventory() -> void:
	if GameState.material_instances.is_empty():
		reset_to_defaults()
