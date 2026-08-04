class_name AVGCharacter extends Resource
## AVG Character Resource.
## Stores character info, semantic emotion slots, and optional outfit naming rules.

@export var character_id: String = ""
@export var character_key: String = ""
@export var character_name: String = "Character"
@export var display_name: String = ""
@export var sprites: Dictionary = {}
@export var default_outfit: String = ""
@export var available_outfits: Array[String] = []
@export var emotion_slots: Dictionary = {}
@export var sprite_prefix: String = ""
@export var sprite_base_dir: String = ""
@export var sprite_extension: String = "png"
## 可选路径模板。支持 {outfit}、{slot}、{character_key}；设置后优先于 prefix 规则。
@export var sprite_path_pattern: String = ""
@export var profile: String = ""
## 显示补偿：归一化偏移量（相对于设计分辨率）
## 例如 (0, -0.1) 向上偏移 10% 设计高度，用于裁掉腿部只显示上半身
@export var display_offset: Vector2 = Vector2.ZERO
## 显示补偿：缩放系数（1.0 = 原始大小）
## 例如 1.2 放大 20%，配合 offset 可调整角色在画面中的呈现
@export var display_scale: float = 1.0


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "character_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "character_key", "type": TYPE_STRING, "editable": true, "visible": true, "category": "系统"},
		{"name": "character_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "display_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "default_outfit", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "sprite_prefix", "type": TYPE_STRING, "editable": true, "category": "资源"},
		{"name": "sprite_base_dir", "type": TYPE_STRING, "editable": true, "category": "资源"},
		{"name": "sprite_extension", "type": TYPE_STRING, "editable": true, "category": "资源"},
		{"name": "sprite_path_pattern", "type": TYPE_STRING, "editable": true, "category": "资源"},
		{"name": "profile", "type": TYPE_STRING, "editable": true, "category": "基本", "multiline": true},
		{"name": "display_offset", "type": TYPE_VECTOR2, "editable": true, "category": "显示补偿", "hint": "归一化偏移 (0~1)"},
		{"name": "display_scale", "type": TYPE_FLOAT, "editable": true, "category": "显示补偿", "hint": "缩放系数 (1.0=原始)"},
	]


static func make_id(slot: int) -> String:
	return "char_%03d" % slot


static func normalize_character_key(raw_key: String) -> String:
	var lower_value: String = raw_key.strip_edges().to_lower()
	var result: String = ""
	var previous_was_separator: bool = false
	for i in lower_value.length():
		var codepoint: int = lower_value.unicode_at(i)
		var is_letter: bool = codepoint >= 97 and codepoint <= 122
		var is_digit: bool = codepoint >= 48 and codepoint <= 57
		var is_separator: bool = codepoint == 95 or codepoint == 45 or codepoint == 32 or codepoint == 46 or codepoint == 47 or codepoint == 92
		if is_letter or is_digit:
			result += char(codepoint)
			previous_was_separator = false
		elif is_separator:
			if not result.is_empty() and not previous_was_separator:
				result += "_"
				previous_was_separator = true
	return result.strip_edges().trim_suffix("_")


static func resolve_outfit_sprite_path(character: Variant, emotion: String, outfit: String = "") -> String:
	var resolved_emotion: String = str(emotion).strip_edges()
	if resolved_emotion.is_empty():
		resolved_emotion = "default"

	var resolved_outfit: String = resolve_outfit_name(character, outfit)
	var slot: String = _resolve_emotion_slot(character, resolved_emotion)
	if resolved_outfit.is_empty() or slot.is_empty():
		return ""

	var path_pattern: String = _resolve_sprite_path_pattern(character)
	if not path_pattern.is_empty():
		return path_pattern \
			.replace("{outfit}", resolved_outfit) \
			.replace("{slot}", slot) \
			.replace("{character_key}", _resolve_character_key(character))

	var prefix: String = _resolve_sprite_prefix(character)
	var base_dir: String = _resolve_sprite_base_dir(character)
	var extension: String = _resolve_sprite_extension(character)
	if prefix.is_empty() or base_dir.is_empty() or extension.is_empty():
		return ""

	return "%s%s_%s%s.%s" % [base_dir, prefix, resolved_outfit, slot, extension]


static func resolve_outfit_name(character: Variant, requested_outfit: String = "") -> String:
	var trimmed_requested: String = str(requested_outfit).strip_edges()
	var outfits: Array[String] = _collect_outfits(character)
	if not trimmed_requested.is_empty():
		if outfits.is_empty() or outfits.has(trimmed_requested):
			return trimmed_requested

	if character is Resource:
		var resource_default_outfit: String = str(character.default_outfit if "default_outfit" in character else "").strip_edges()
		if outfits.is_empty() or outfits.has(resource_default_outfit):
			return resource_default_outfit
	if character is Dictionary:
		var dictionary_default_outfit: String = str(character.get("default_outfit", "")).strip_edges()
		if outfits.is_empty() or outfits.has(dictionary_default_outfit):
			return dictionary_default_outfit
	if not outfits.is_empty():
		return outfits[0]
	return ""


static func resolve_texture_from_character(character: Variant, emotion: String, outfit: String = "") -> Texture2D:
	var path: String = resolve_outfit_sprite_path(character, emotion, outfit)
	if path.is_empty():
		return null

	# res:// 资源必须优先走导入后的 Texture2D，避免直接读取源图片导致导出不可用。
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var resource: Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource as Texture2D
		return null

	var global_path: String = path
	if path.begins_with("user://"):
		global_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(global_path):
		return null

	var extension: String = path.get_extension().to_lower()
	var raw_image_extensions: Array[String] = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
	if raw_image_extensions.has(extension):
		var image := Image.new()
		if image.load(global_path) == OK:
			return ImageTexture.create_from_image(image)

	if ResourceLoader.exists(path):
		var fallback_resource: Resource = ResourceLoader.load(path)
		if fallback_resource is Texture2D:
			return fallback_resource as Texture2D
	return null


static func _resolve_emotion_slot(character: Variant, emotion: String) -> String:
	var slots: Dictionary = {}
	if character is Resource:
		slots = character.emotion_slots if "emotion_slots" in character else {}
	elif character is Dictionary:
		slots = character.get("emotion_slots", {})

	var slot: String = str(slots.get(emotion, "")).strip_edges()
	if slot.is_empty() and emotion != "default":
		slot = str(slots.get("default", "")).strip_edges()
	return slot


static func _resolve_sprite_prefix(character: Variant) -> String:
	if character is Resource:
		return str(character.sprite_prefix if "sprite_prefix" in character else "").strip_edges()
	if character is Dictionary:
		return str(character.get("sprite_prefix", "")).strip_edges()
	return ""


static func _resolve_sprite_base_dir(character: Variant) -> String:
	var base_dir: String = ""
	if character is Resource:
		base_dir = str(character.sprite_base_dir if "sprite_base_dir" in character else "").strip_edges()
	elif character is Dictionary:
		base_dir = str(character.get("sprite_base_dir", "")).strip_edges()

	if base_dir.is_empty():
		return ""
	return base_dir if base_dir.ends_with("/") else base_dir + "/"


static func _resolve_sprite_extension(character: Variant) -> String:
	var extension: String = ""
	if character is Resource:
		extension = str(character.sprite_extension if "sprite_extension" in character else "").strip_edges()
	elif character is Dictionary:
		extension = str(character.get("sprite_extension", "")).strip_edges()
	if extension.is_empty():
		return "png"
	return extension.trim_prefix(".")


static func _resolve_sprite_path_pattern(character: Variant) -> String:
	if character is Resource:
		return str(character.sprite_path_pattern if "sprite_path_pattern" in character else "").strip_edges()
	if character is Dictionary:
		return str(character.get("sprite_path_pattern", "")).strip_edges()
	return ""


static func _resolve_character_key(character: Variant) -> String:
	if character is Resource:
		return str(character.character_key if "character_key" in character else "").strip_edges()
	if character is Dictionary:
		return str(character.get("character_key", "")).strip_edges()
	return ""


static func _collect_outfits(character: Variant) -> Array[String]:
	var outfits: Array[String] = []
	var raw_outfits: Array = []
	var fallback_outfit: String = ""

	if character is Resource:
		raw_outfits = character.available_outfits if "available_outfits" in character and character.available_outfits is Array else []
		fallback_outfit = str(character.default_outfit if "default_outfit" in character else "").strip_edges()
	elif character is Dictionary:
		raw_outfits = character.get("available_outfits", [])
		fallback_outfit = str(character.get("default_outfit", "")).strip_edges()

	for entry in raw_outfits:
		var outfit_name: String = str(entry).strip_edges()
		if outfit_name.is_empty() or outfits.has(outfit_name):
			continue
		outfits.append(outfit_name)

	if not fallback_outfit.is_empty() and not outfits.has(fallback_outfit):
		outfits.append(fallback_outfit)
	return outfits
