class_name AVGAssetManifest extends RefCounted
## 游戏本体唯一的 AVG 素材清单。

const MANIFEST_PATH: String = "res://resources/avg/asset_aliases.json"

static var _manifest_cache: Dictionary = {}


static func load_manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache.duplicate(true)
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	_manifest_cache = (parsed as Dictionary).duplicate(true)
	return _manifest_cache.duplicate(true)


static func clear_cache() -> void:
	_manifest_cache.clear()


static func resolve_texture_path(asset_ref: String) -> String:
	return _resolve_alias(asset_ref, ["backgrounds", "images", "textures"])


static func resolve_audio_path(asset_ref: String) -> String:
	return _resolve_alias(asset_ref, ["bgm", "sfx", "audio"])


static func build_llm_prompt_block(game_data: Resource = null) -> String:
	var manifest := load_manifest()
	var hidden_set := _build_hidden_set(manifest)
	var lines: Array[String] = [
		"本次可用素材清单：",
		"- 角色位置可用：far_left、left、center、right、far_right",
		"- 背景和音频只使用下列 alias",
		"- 角色立绘优先使用 emotion 语义键；如需指定服装，再额外写 outfit",
		"- 非角色图片可用 image.show(...)；全屏事件图可用 cg.show(...)",
	]

	var character_lines := _build_character_lines(game_data)
	if character_lines.is_empty():
		lines.append("- 当前没有可用角色")
	else:
		lines.append("可用角色：")
		lines.append_array(character_lines)

	lines.append(_format_alias_section("可用背景 alias：", manifest.get("backgrounds", {}), hidden_set))
	lines.append(_format_alias_section("可用 BGM alias：", manifest.get("bgm", {}), hidden_set))
	lines.append(_format_alias_section("可用 SFX alias：", manifest.get("sfx", {}), hidden_set))
	lines.append(_format_alias_section("可用图片 alias：", manifest.get("images", {}), hidden_set))
	return "\n".join(lines).strip_edges()


static func _resolve_alias(asset_ref: String, buckets: Array[String]) -> String:
	var normalized_ref := asset_ref.strip_edges()
	if normalized_ref.is_empty():
		return ""
	if normalized_ref.begins_with("res://") or normalized_ref.begins_with("user://"):
		return normalized_ref
	var manifest := load_manifest()
	for bucket_name in buckets:
		var bucket: Dictionary = manifest.get(bucket_name, {})
		if bucket.has(normalized_ref):
			return _normalize_resource_path(str(bucket.get(normalized_ref, "")))
	return ""


static func _normalize_resource_path(raw_path: String) -> String:
	var path := raw_path.strip_edges()
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return "res://" + path.trim_prefix("/")


static func _build_hidden_set(manifest: Dictionary) -> Dictionary:
	var hidden_set: Dictionary = {}
	for entry in manifest.get("hidden", []):
		var alias_name := str(entry).strip_edges()
		if not alias_name.is_empty():
			hidden_set[alias_name] = true
	return hidden_set


static func _build_character_lines(game_data: Resource) -> Array[String]:
	var lines: Array[String] = []
	if game_data == null or not "characters" in game_data:
		return lines
	for character in game_data.characters:
		if character == null:
			continue
		var character_id := str(character.character_id if "character_id" in character else "").strip_edges()
		var character_name := str(character.character_name if "character_name" in character else "").strip_edges()
		var display_name := str(character.display_name if "display_name" in character else "").strip_edges()
		var dsl_name := character_name if not character_name.is_empty() else character_id
		if dsl_name.is_empty():
			continue
		var label := display_name if not display_name.is_empty() else dsl_name
		var emotions := _collect_emotions(character)
		var outfits := _collect_outfits(character)
		lines.append("- %s（%s）可用表情：%s" % [dsl_name, label, "、".join(emotions) if not emotions.is_empty() else "无"])
		lines.append("  可用服装：%s" % ["、".join(outfits) if not outfits.is_empty() else "无"])
	return lines


static func _collect_emotions(character: Resource) -> PackedStringArray:
	var result := PackedStringArray()
	var sprites: Dictionary = character.sprites if "sprites" in character else {}
	for raw_key in sprites.keys():
		var emotion := str(raw_key).strip_edges()
		if "__" in emotion:
			var parts := emotion.split("__", false, 1)
			if parts.size() == 2:
				emotion = parts[1].strip_edges()
		if not emotion.is_empty() and not result.has(emotion):
			result.append(emotion)
	if "emotion_slots" in character and character.emotion_slots is Dictionary:
		for raw_key in character.emotion_slots.keys():
			var emotion := str(raw_key).strip_edges()
			if not emotion.is_empty() and not result.has(emotion):
				result.append(emotion)
	result.sort()
	return result


static func _collect_outfits(character: Resource) -> PackedStringArray:
	var result := PackedStringArray()
	if "available_outfits" in character and character.available_outfits is Array:
		for raw_outfit in character.available_outfits:
			var outfit := str(raw_outfit).strip_edges()
			if not outfit.is_empty() and not result.has(outfit):
				result.append(outfit)
	if "default_outfit" in character:
		var default_outfit := str(character.default_outfit).strip_edges()
		if not default_outfit.is_empty() and not result.has(default_outfit):
			result.append(default_outfit)
	result.sort()
	return result


static func _format_alias_section(title: String, bucket_value: Variant, hidden_set: Dictionary) -> String:
	var lines: Array[String] = [title]
	if not bucket_value is Dictionary:
		lines.append("- 无")
		return "\n".join(lines)
	var aliases: Array[String] = []
	for raw_key in (bucket_value as Dictionary).keys():
		var alias_name := str(raw_key).strip_edges()
		if not alias_name.is_empty() and not hidden_set.has(alias_name):
			aliases.append(alias_name)
	aliases.sort()
	if aliases.is_empty():
		lines.append("- 无")
	else:
		for alias_name in aliases:
			lines.append("- %s" % alias_name)
	return "\n".join(lines)
