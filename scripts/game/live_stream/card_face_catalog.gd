class_name CardFaceCatalog
extends RefCounted
## 卡面 texture 按卡种/族解析；与技能树小 icon 分离。

const BEHAVIOR_GAME: Texture2D = preload("res://Assets/images/live_stream/cards/faces/behavior/face_game.png")
const BEHAVIOR_TALK: Texture2D = preload("res://Assets/images/live_stream/cards/faces/behavior/face_talk.png")
const BEHAVIOR_SONG: Texture2D = preload("res://Assets/images/live_stream/cards/faces/behavior/face_song.png")
const BEHAVIOR_ACT: Texture2D = preload("res://Assets/images/live_stream/cards/faces/behavior/face_act.png")
const BEHAVIOR_TECH: Texture2D = preload("res://Assets/images/live_stream/cards/faces/behavior/face_tech.png")

const MATERIAL_GAME: Texture2D = preload("res://Assets/images/live_stream/cards/faces/material/face_game.png")
const MATERIAL_TALK: Texture2D = preload("res://Assets/images/live_stream/cards/faces/material/face_talk.png")
const MATERIAL_SONG: Texture2D = preload("res://Assets/images/live_stream/cards/faces/material/face_song.png")

const MODIFIER_TONE: Texture2D = preload("res://Assets/images/live_stream/cards/faces/modifier/face_tone.png")
const MODIFIER_PROJECT: Texture2D = preload("res://Assets/images/live_stream/cards/faces/modifier/face_project.png")

const PERSONA_DEFAULT: Texture2D = preload("res://Assets/images/live_stream/cards/faces/persona/face_persona_default.png")


static func face_for(resource: StreamContentResource) -> Texture2D:
	if resource == null:
		return null
	if resource is BehaviorCardResource:
		return _behavior_face((resource as BehaviorCardResource).family)
	if resource is ModifierCardResource:
		var modifier := resource as ModifierCardResource
		if modifier.modifier_kind == ModifierCardResource.KIND_PROJECT:
			return MODIFIER_PROJECT
		return MODIFIER_TONE
	if resource is StreamPersonaResource:
		return PERSONA_DEFAULT
	if resource is LiveStreamMaterialResource:
		return _material_face(resource as LiveStreamMaterialResource)
	return resource.icon


static func _behavior_face(family: StringName) -> Texture2D:
	match family:
		LiveStreamCardResource.FAMILY_GAME:
			return BEHAVIOR_GAME
		LiveStreamCardResource.FAMILY_SONG:
			return BEHAVIOR_SONG
		LiveStreamCardResource.FAMILY_ACT:
			return BEHAVIOR_ACT
		LiveStreamCardResource.FAMILY_TECH:
			return BEHAVIOR_TECH
		_:
			return BEHAVIOR_TALK


static func _material_face(material_res: LiveStreamMaterialResource) -> Texture2D:
	var theme := _material_theme(material_res)
	match theme:
		&"game":
			return MATERIAL_GAME
		&"song":
			return MATERIAL_SONG
		_:
			return MATERIAL_TALK


static func _material_theme(material_res: LiveStreamMaterialResource) -> StringName:
	for tag: StringName in material_res.tags:
		var tag_text := String(tag)
		if tag_text.contains("game") or tag_text.contains("boss"):
			return &"game"
		if tag_text.contains("music") or tag_text.contains("song"):
			return &"song"
	var affinity: StreamFamilyValues = material_res.affinity
	if affinity == null:
		return &"talk"
	var best_theme := &"talk"
	var best_value: float = affinity.talk
	if affinity.game > best_value:
		best_theme = &"game"
		best_value = affinity.game
	if affinity.song > best_value:
		best_theme = &"song"
	return best_theme
