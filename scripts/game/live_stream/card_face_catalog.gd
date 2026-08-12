class_name CardFaceCatalog
extends RefCounted
## 素材与人设的卡面 texture；与技能树小 icon 分离。

const MATERIAL_GAME: Texture2D = preload("res://Assets/images/live_stream/cards/faces/material/face_game.png")
const MATERIAL_TALK: Texture2D = preload("res://Assets/images/live_stream/cards/faces/material/face_talk.png")
const MATERIAL_SONG: Texture2D = preload("res://Assets/images/live_stream/cards/faces/material/face_song.png")

const PERSONA_DEFAULT: Texture2D = preload("res://Assets/images/live_stream/cards/faces/persona/face_persona_default.png")


static func face_for(resource: StreamContentResource) -> Texture2D:
	if resource == null:
		return null
	if resource is StreamPersonaResource:
		return PERSONA_DEFAULT
	if resource is LiveStreamMaterialResource:
		return _material_face(resource as LiveStreamMaterialResource)
	return resource.icon


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
	if &"play" in material_res.activities or &"challenge" in material_res.activities:
		return &"game"
	if &"sing" in material_res.activities:
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
