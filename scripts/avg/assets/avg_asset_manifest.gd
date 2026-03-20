class_name AVGAssetManifest extends RefCounted

const MANIFEST_RELATIVE_PATH: String = "manifests/asset_aliases.json"
const IMAGE_ROOT_RELATIVE_PATH: String = "assets/images"
const AUDIO_ROOT_RELATIVE_PATH: String = "assets/audio"

static var _manifest_cache: Dictionary = {}


static func load_manifest(project_root_path: String) -> Dictionary:
	var normalized_root: String = _normalize_project_root(project_root_path)
	if normalized_root.is_empty():
		return {}

	if _manifest_cache.has(normalized_root):
		return (_manifest_cache[normalized_root] as Dictionary).duplicate(true)

	var manifest_path: String = normalized_root + MANIFEST_RELATIVE_PATH
	if not FileAccess.file_exists(manifest_path):
		_manifest_cache[normalized_root] = {}
		return {}

	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		_manifest_cache[normalized_root] = {}
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_manifest_cache[normalized_root] = {}
		return {}

	var manifest: Dictionary = (parsed as Dictionary).duplicate(true)
	_manifest_cache[normalized_root] = manifest.duplicate(true)
	return manifest


static func clear_cache() -> void:
	_manifest_cache.clear()


static func resolve_texture_path(asset_ref: String, project_root_path: String) -> String:
	return _resolve_alias(asset_ref, project_root_path, ["backgrounds", "images", "textures"])


static func resolve_audio_path(asset_ref: String, project_root_path: String) -> String:
	return _resolve_alias(asset_ref, project_root_path, ["bgm", "sfx", "audio"])


static func build_llm_prompt_block(project_root_path: String, project: Resource = null) -> String:
	var manifest: Dictionary = load_manifest(project_root_path)
	var lines: Array[String] = []
	var image_aliases: Array[String] = _extract_filtered_aliases(manifest, "images", false)
	var cg_aliases: Array[String] = _extract_filtered_aliases(manifest, "images", true)
	var image_assets: Array[String] = _scan_visual_asset_names(project_root_path, false)
	var cg_assets: Array[String] = _scan_visual_asset_names(project_root_path, true)

	lines.append("本次可用素材清单：")
	lines.append("- 角色位置只允许：left、center、right")
	lines.append("- 背景和音频请优先使用 alias，不要写真实路径")
	lines.append("- 角色立绘优先使用 emotion 语义键；如需指定服装，再额外写 outfit")
	lines.append("- 非角色图片可用 image.show(...)；全屏事件图可用 cg.show(...)")

	var character_lines: Array[String] = []
	for entry in _collect_character_entries(project):
		var display_name: String = str(entry.get("display_name", "")).strip_edges()
		var character_id: String = str(entry.get("character_id", "")).strip_edges()
		var emotions: Array = entry.get("emotions", [])
		var outfits: Array = entry.get("outfits", [])
		var profile: String = str(entry.get("profile", "")).strip_edges()
		if character_id.is_empty():
			continue
		var name_text: String = display_name if not display_name.is_empty() else character_id
		var emotion_text: String = "无"
		if not emotions.is_empty():
			emotion_text = "、".join(PackedStringArray(emotions))
		var outfit_text: String = "无"
		if not outfits.is_empty():
			outfit_text = "、".join(PackedStringArray(outfits))
		character_lines.append("- %s（%s）可用表情：%s" % [character_id, name_text, emotion_text])
		character_lines.append("  可用服装：%s" % outfit_text)
		if not profile.is_empty():
			character_lines.append("  备注：%s" % profile)

	if character_lines.is_empty():
		lines.append("- 当前没有可用角色")
	else:
		lines.append("可用角色：")
		lines.append_array(character_lines)

	lines.append(_format_alias_section("可用背景 alias：", manifest.get("backgrounds", {})))
	lines.append(_format_alias_section("可用 BGM alias：", manifest.get("bgm", {})))
	lines.append(_format_alias_section("可用 SFX alias：", manifest.get("sfx", {})))
	lines.append(_format_string_section("可用普通图片 alias：", image_aliases))
	lines.append(_format_string_section("可用普通图片原始名：", image_assets))
	lines.append(_format_string_section("可用 CG alias：", cg_aliases))
	lines.append(_format_string_section("可用 CG 原始名：", cg_assets))

	return "\n".join(lines).strip_edges()


static func get_project_root_from_project(project: Resource) -> String:
	if project == null:
		return ""
	if "project_root_path" in project:
		return _normalize_project_root(str(project.get("project_root_path")))
	return ""


static func _resolve_alias(asset_ref: String, project_root_path: String, buckets: Array[String]) -> String:
	var trimmed_ref: String = asset_ref.strip_edges()
	if trimmed_ref.is_empty():
		return ""
	if trimmed_ref.begins_with("res://") or trimmed_ref.begins_with("user://"):
		return trimmed_ref

	var manifest: Dictionary = load_manifest(project_root_path)
	for bucket_name in buckets:
		var bucket: Dictionary = manifest.get(bucket_name, {})
		if bucket.has(trimmed_ref):
			return _resolve_manifest_value(str(bucket.get(trimmed_ref, "")), project_root_path)

	var resolved_from_scan: String = _resolve_from_filesystem(trimmed_ref, project_root_path, buckets)
	if not resolved_from_scan.is_empty():
		return resolved_from_scan

	return trimmed_ref


static func _resolve_manifest_value(value: String, project_root_path: String) -> String:
	var trimmed_value: String = value.strip_edges()
	if trimmed_value.is_empty():
		return ""
	if trimmed_value.begins_with("res://") or trimmed_value.begins_with("user://"):
		return trimmed_value
	var normalized_root: String = _normalize_project_root(project_root_path)
	if normalized_root.is_empty():
		return trimmed_value
	return normalized_root + trimmed_value


static func _normalize_project_root(project_root_path: String) -> String:
	var trimmed_root: String = project_root_path.strip_edges()
	if trimmed_root.is_empty():
		return ""
	return trimmed_root if trimmed_root.ends_with("/") else trimmed_root + "/"


static func _collect_character_entries(project: Resource) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if project == null or not "characters" in project:
		return entries

	for character in project.characters:
		if character == null:
			continue
		var character_id: String = character.character_id if "character_id" in character else ""
		character_id = character_id.strip_edges()
		if character_id.is_empty():
			continue
		entries.append({
			"character_id": character_id,
			"display_name": (character.display_name if "display_name" in character else "").strip_edges(),
			"emotions": _collect_emotions(character),
			"outfits": _collect_outfits(character),
			"profile": (character.profile if "profile" in character else "").strip_edges(),
		})

	return entries


static func _collect_emotions(character: Resource) -> Array[String]:
	var emotions: Array[String] = []
	if character == null:
		return emotions

	var sprites: Dictionary = character.sprites if "sprites" in character else {}
	for key in sprites.keys():
		var emotion_name: String = str(key).strip_edges()
		if emotion_name.is_empty():
			continue
		if "__" in emotion_name:
			var parts: PackedStringArray = emotion_name.split("__", false, 1)
			if parts.size() == 2:
				emotion_name = str(parts[1]).strip_edges()
		if emotion_name.is_empty() or emotions.has(emotion_name):
			continue
		emotions.append(emotion_name)

	if "emotion_slots" in character and character.emotion_slots is Dictionary:
		for key in character.emotion_slots.keys():
			var slot_emotion: String = str(key).strip_edges()
			if slot_emotion.is_empty() or emotions.has(slot_emotion):
				continue
			emotions.append(slot_emotion)

	emotions.sort()
	return emotions


static func _collect_outfits(character: Resource) -> Array[String]:
	var outfits: Array[String] = []
	if character == null:
		return outfits

	if "available_outfits" in character and character.available_outfits is Array:
		for entry in character.available_outfits:
			var outfit_name: String = str(entry).strip_edges()
			if outfit_name.is_empty() or outfits.has(outfit_name):
				continue
			outfits.append(outfit_name)

	if "default_outfit" in character:
		var default_outfit: String = str(character.default_outfit).strip_edges()
		if not default_outfit.is_empty() and not outfits.has(default_outfit):
			outfits.append(default_outfit)

	outfits.sort()
	return outfits


static func _format_alias_section(title: String, bucket_value: Variant) -> String:
	var lines: Array[String] = [title]
	if not bucket_value is Dictionary or (bucket_value as Dictionary).is_empty():
		lines.append("- 无")
		return "\n".join(lines)

	var bucket: Dictionary = bucket_value
	var aliases: Array[String] = []
	for key in bucket.keys():
		aliases.append(str(key))
	aliases.sort()
	for alias in aliases:
		lines.append("- %s" % alias)
	return "\n".join(lines)


static func _format_string_section(title: String, entries: Array[String]) -> String:
	var lines: Array[String] = [title]
	if entries.is_empty():
		lines.append("- 无")
		return "\n".join(lines)
	for entry in entries:
		lines.append("- %s" % entry)
	return "\n".join(lines)


static func _extract_filtered_aliases(manifest: Dictionary, bucket_name: String, cg_only: bool) -> Array[String]:
	var aliases: Array[String] = []
	var bucket: Dictionary = manifest.get(bucket_name, {})
	for key in bucket.keys():
		var alias_name: String = str(key).strip_edges()
		var value: String = str(bucket.get(key, "")).strip_edges().to_lower()
		var is_cg_alias: bool = _looks_like_cg(alias_name) or "/cg/" in value or "/cgs/" in value
		if is_cg_alias != cg_only:
			continue
		aliases.append(alias_name)
	aliases.sort()
	return aliases


static func _scan_visual_asset_names(project_root_path: String, cg_only: bool) -> Array[String]:
	var results: Array[String] = []
	var seen: Dictionary = {}
	var root: String = _normalize_project_root(project_root_path) + IMAGE_ROOT_RELATIVE_PATH
	_scan_visual_asset_dir(root, "", cg_only, seen, results)
	results.sort()
	return results


static func _scan_visual_asset_dir(abs_dir: String, relative_dir: String, cg_only: bool, seen: Dictionary, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var child_name: String = dir.get_next()
	while child_name != "":
		if child_name == "." or child_name == ".." or child_name.begins_with("."):
			child_name = dir.get_next()
			continue
		var child_relative: String = child_name if relative_dir.is_empty() else relative_dir + "/" + child_name
		if dir.current_is_dir():
			if _should_skip_visual_dir(child_relative, cg_only):
				child_name = dir.get_next()
				continue
			_scan_visual_asset_dir(abs_dir + "/" + child_name, child_relative, cg_only, seen, out)
		else:
			if child_name.ends_with(".import") or child_name.begins_with("."):
				child_name = dir.get_next()
				continue
			var base_name: String = child_name.get_basename()
			var belongs_to_cg: bool = _looks_like_cg(child_relative)
			if belongs_to_cg != cg_only:
				child_name = dir.get_next()
				continue
			if seen.has(base_name):
				child_name = dir.get_next()
				continue
			seen[base_name] = true
			out.append(base_name)
		child_name = dir.get_next()
	dir.list_dir_end()


static func _should_skip_visual_dir(relative_dir: String, cg_only: bool) -> bool:
	var normalized: String = relative_dir.to_lower()
	if normalized.begins_with("background") or normalized.begins_with("character"):
		return true
	var is_cg_dir: bool = normalized == "cg" or normalized.begins_with("cg/") or normalized == "cgs" or normalized.begins_with("cgs/")
	if cg_only:
		return not is_cg_dir
	return is_cg_dir


static func _looks_like_cg(path_or_name: String) -> bool:
	var normalized: String = path_or_name.to_lower()
	return normalized == "cg" or normalized.begins_with("cg_") or "/cg/" in normalized or normalized == "cgs" or "/cgs/" in normalized


static func _resolve_from_filesystem(asset_ref: String, project_root_path: String, buckets: Array[String]) -> String:
	var normalized_ref: String = asset_ref.strip_edges()
	if normalized_ref.is_empty():
		return ""
	var normalized_root: String = _normalize_project_root(project_root_path)
	if normalized_root.is_empty():
		return ""
	if _is_texture_bucket_request(buckets):
		var image_match: String = _find_asset_relative_path_by_name(normalized_root + IMAGE_ROOT_RELATIVE_PATH, normalized_ref, true)
		if not image_match.is_empty():
			return normalized_root + image_match
	if _is_audio_bucket_request(buckets):
		var audio_match: String = _find_asset_relative_path_by_name(normalized_root + AUDIO_ROOT_RELATIVE_PATH, normalized_ref, false)
		if not audio_match.is_empty():
			return normalized_root + audio_match
	return ""


static func _is_texture_bucket_request(buckets: Array[String]) -> bool:
	for bucket in buckets:
		if bucket in ["backgrounds", "images", "textures", "cg"]:
			return true
	return false


static func _is_audio_bucket_request(buckets: Array[String]) -> bool:
	for bucket in buckets:
		if bucket in ["bgm", "sfx", "audio"]:
			return true
	return false


static func _find_asset_relative_path_by_name(abs_dir: String, asset_ref: String, exclude_character_dirs: bool) -> String:
	return _find_asset_relative_path_recursive(abs_dir, "", asset_ref, exclude_character_dirs)


static func _find_asset_relative_path_recursive(abs_dir: String, relative_dir: String, asset_ref: String, exclude_character_dirs: bool) -> String:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return ""
	var lower_ref: String = asset_ref.to_lower()
	dir.list_dir_begin()
	var child_name: String = dir.get_next()
	while child_name != "":
		if child_name == "." or child_name == ".." or child_name.begins_with("."):
			child_name = dir.get_next()
			continue
		var child_relative: String = child_name if relative_dir.is_empty() else relative_dir + "/" + child_name
		if dir.current_is_dir():
			var lower_dir_name: String = child_name.to_lower()
			if exclude_character_dirs and lower_dir_name == "character":
				child_name = dir.get_next()
				continue
			var nested: String = _find_asset_relative_path_recursive(abs_dir + "/" + child_name, child_relative, asset_ref, exclude_character_dirs)
			if not nested.is_empty():
				dir.list_dir_end()
				return nested
		else:
			if child_name.ends_with(".import"):
				child_name = dir.get_next()
				continue
			var base_name: String = child_name.get_basename().to_lower()
			if base_name == lower_ref or child_name.to_lower() == lower_ref:
				dir.list_dir_end()
				return child_relative
		child_name = dir.get_next()
	dir.list_dir_end()
	return ""
