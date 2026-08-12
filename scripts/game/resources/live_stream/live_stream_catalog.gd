class_name LiveStreamCatalog extends Resource
## 纵切内容目录与静态审计入口。

@export var allowed_tags: Array[StringName] = []
@export var materials: Array[LiveStreamMaterialResource] = []
@export var personas: Array[StreamPersonaResource] = []


func get_material(material_id: StringName) -> LiveStreamMaterialResource:
	for material: LiveStreamMaterialResource in materials:
		if material != null and material.content_id == material_id:
			return material
	return null


func get_persona(persona_id: StringName) -> StreamPersonaResource:
	for persona: StreamPersonaResource in personas:
		if persona != null and persona.content_id == persona_id:
			return persona
	return null


func validate_content() -> PackedStringArray:
	var errors: PackedStringArray = []
	var known_ids: Dictionary = {}
	for material: LiveStreamMaterialResource in materials:
		_validate_content_entry(material, known_ids, errors)
	for persona: StreamPersonaResource in personas:
		_validate_content_entry(persona, known_ids, errors)
	return errors


func _validate_content_entry(entry: StreamContentResource, known_ids: Dictionary, errors: PackedStringArray) -> void:
	if entry == null:
		errors.append("目录包含空 Resource")
		return
	if not entry.is_valid_base():
		errors.append("内容 %s 的公共字段无效" % String(entry.content_id))
	if known_ids.has(entry.content_id):
		errors.append("重复内容 ID：%s" % String(entry.content_id))
	known_ids[entry.content_id] = true
	_validate_tags(entry.tags, entry.content_id, errors)
	if entry is LiveStreamMaterialResource and not (entry as LiveStreamMaterialResource).is_valid():
		errors.append("素材 %s 的业务字段无效" % String(entry.content_id))
	if entry is StreamPersonaResource and not (entry as StreamPersonaResource).is_valid():
		errors.append("人设 %s 的业务字段无效" % String(entry.content_id))


func _validate_tags(values: Array[StringName], owner_id: StringName, errors: PackedStringArray) -> void:
	for tag: StringName in values:
		if tag not in allowed_tags:
			errors.append("内容 %s 引用了未登记 tag：%s" % [String(owner_id), String(tag)])
