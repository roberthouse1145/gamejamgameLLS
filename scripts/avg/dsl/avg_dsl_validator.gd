class_name AVGDSLValidator extends RefCounted

const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")
const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")

const DEFAULT_ALLOWED_POSITIONS: Array[String] = [
	"left",
	"center",
	"right",
	"far_left",
	"far_right",
	"custom",
]
const DEFAULT_ALLOWED_ENTER_EFFECTS: Array[String] = [
	"fade",
	"slide_from_left",
	"slide_from_right",
	"slide_from_top",
	"slide_from_bottom",
	"pop_in",
	"none",
]
const DEFAULT_ALLOWED_EXIT_EFFECTS: Array[String] = [
	"fade",
	"slide_to_left",
	"slide_to_right",
	"slide_to_top",
	"slide_to_bottom",
	"pop_out",
	"none",
]
const DEFAULT_ALLOWED_EASINGS: Array[String] = [
	"linear",
	"ease_in",
	"ease_out",
	"ease_in_out",
]
const MAX_STAGE_CHARACTERS: int = 5


func validate_commands(commands: Array, project: Resource, project_root_path: String, options: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var _allowed_commands: Array[String] = _to_string_array(options.get("allowed_commands", []))
	var allowed_positions: Array[String] = _to_string_array(options.get("allowed_positions", DEFAULT_ALLOWED_POSITIONS))
	var min_choices: int = int(options.get("min_choice_count", 0))
	var max_choices: int = int(options.get("max_choice_count", 0))
	var character_map: Dictionary = _build_character_map(project)
	var project_root: String = AVGAssetManifestClass.get_project_root_from_project(project)
	if project_root.is_empty():
		project_root = project_root_path.strip_edges()

	for index in range(commands.size()):
		var command = commands[index]
		if command == null:
			errors.append("Command %d is null" % (index + 1))
			continue

		var command_type: String = _normalize_token(command.command_type)
		var params: Dictionary = command.params if command.params is Dictionary else {}
		if command_type.is_empty():
			errors.append("Command %d is missing command_type" % (index + 1))
			continue

		match command_type:
			"DIALOGUE":
				_validate_dialogue(index, params, character_map, errors)
			"SHOW_CHARACTER":
				_validate_show_character(index, params, character_map, allowed_positions, errors)
			"HIDE_CHARACTER":
				_validate_hide_character(index, params, character_map, errors)
			"STAGE_SET":
				_validate_stage_set(index, params, character_map, errors)
			"CHANGE_EXPRESSION":
				_validate_change_expression(index, params, character_map, errors)
			"CHANGE_OUTFIT":
				_validate_change_outfit(index, params, character_map, errors)
			"CHANGE_BACKGROUND":
				_validate_asset_ref(index, params, "texture_path", "background", project_root, ["backgrounds", "images", "textures"], errors)
			"SHOW_IMAGE":
				_validate_show_image(index, params, project_root, errors)
			"HIDE_IMAGE":
				_validate_hide_image(index, params, errors)
			"PLAY_BGM":
				_validate_asset_ref(index, params, "audio_path", "bgm", project_root, ["bgm", "audio"], errors)
			"PLAY_SFX":
				_validate_asset_ref(index, params, "audio_path", "sfx", project_root, ["sfx", "audio"], errors)
			"CHOICE":
				_validate_choice(index, params, min_choices, max_choices, errors, warnings)

	var summary_lines: Array[String] = []
	if errors.is_empty():
		summary_lines.append("DSL semantic validation passed")
	else:
		summary_lines.append("DSL semantic validation failed with %d issues" % errors.size())
	if not warnings.is_empty():
		summary_lines.append("Warnings: %s" % " | ".join(warnings))
	if not errors.is_empty():
		summary_lines.append("Errors:")
		for entry in errors:
			summary_lines.append("- %s" % entry)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"summary": "\n".join(summary_lines).strip_edges(),
	}


func _validate_dialogue(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String]) -> void:
	var emotion: String = _normalize_token(params.get("emotion", ""))
	if emotion.is_empty():
		return
	var speaker: String = _normalize_token(params.get("speaker", ""))
	if speaker.is_empty():
		return
	var character_entry: Dictionary = _resolve_character_entry(character_map, speaker)
	if character_entry.is_empty():
		return
	var character_label: String = str(character_entry.get("character_id", speaker))
	var emotions: Array[String] = character_entry.get("emotions", [])
	if not emotions.has(emotion):
		errors.append("DIALOGUE %d uses missing emotion on %s: %s" % [index + 1, character_label, emotion])


func _validate_show_character(index: int, params: Dictionary, character_map: Dictionary, allowed_positions: Array[String], errors: Array[String]) -> void:
	_validate_character_reference(index, params, character_map, "character_id", "SHOW_CHARACTER", errors)

	var position: String = _normalize_token(params.get("position", "center"))
	if position.is_empty():
		position = "center"
	if not allowed_positions.is_empty() and not allowed_positions.has(position):
		errors.append("SHOW_CHARACTER %d uses disallowed position: %s" % [index + 1, position])

	var enter_effect: String = _normalize_token(params.get("enter_effect", "fade")).to_lower()
	if enter_effect.is_empty():
		enter_effect = "fade"
	if not DEFAULT_ALLOWED_ENTER_EFFECTS.has(enter_effect):
		errors.append("SHOW_CHARACTER %d uses unsupported enter_effect: %s" % [index + 1, enter_effect])

	var character_ref: String = _normalize_token(params.get("character_id", ""))
	var character_entry: Dictionary = _resolve_character_entry(character_map, character_ref)
	if character_entry.is_empty():
		return
	var character_label: String = str(character_entry.get("character_id", character_ref))

	var emotion: String = _normalize_token(params.get("emotion", ""))
	if not emotion.is_empty():
		var emotions: Array[String] = character_entry.get("emotions", [])
		if not emotions.has(emotion):
			errors.append("SHOW_CHARACTER %d uses missing emotion on %s: %s" % [index + 1, character_label, emotion])
			return

	var outfit: String = _normalize_token(params.get("outfit", ""))
	if not _validate_outfit_name(index, character_entry, character_label, outfit, "SHOW_CHARACTER", errors):
		return

	_validate_dynamic_sprite(index, character_entry, emotion, outfit, "SHOW_CHARACTER", errors)


func _validate_hide_character(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String]) -> void:
	_validate_character_reference(index, params, character_map, "character_id", "HIDE_CHARACTER", errors)

	var exit_effect: String = _normalize_token(params.get("exit_effect", "fade")).to_lower()
	if exit_effect.is_empty():
		exit_effect = "fade"
	if not DEFAULT_ALLOWED_EXIT_EFFECTS.has(exit_effect):
		errors.append("HIDE_CHARACTER %d uses unsupported exit_effect: %s" % [index + 1, exit_effect])


func _validate_stage_set(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String]) -> void:
	var stage_characters: Array[String] = _extract_stage_characters(params)
	if stage_characters.size() > MAX_STAGE_CHARACTERS:
		errors.append("STAGE_SET %d supports at most %d characters, got %d" % [index + 1, MAX_STAGE_CHARACTERS, stage_characters.size()])

	var resolved_character_entries: Array[Dictionary] = []
	var seen_character_ids: Dictionary = {}
	for character_ref in stage_characters:
		if character_ref.is_empty():
			errors.append("STAGE_SET %d contains an empty character reference" % (index + 1))
			continue
		var character_entry: Dictionary = _resolve_character_entry(character_map, character_ref)
		if character_entry.is_empty():
			errors.append("STAGE_SET %d references missing character: %s" % [index + 1, character_ref])
			continue
		var resolved_character_id: String = str(character_entry.get("character_id", character_ref))
		if seen_character_ids.has(resolved_character_id):
			errors.append("STAGE_SET %d repeats character: %s" % [index + 1, resolved_character_id])
			continue
		seen_character_ids[resolved_character_id] = true
		resolved_character_entries.append(character_entry)

	var emotion_overrides: Array[String] = _parse_stage_override_list(params.get("emotions", ""))
	var outfit_overrides: Array[String] = _parse_stage_override_list(params.get("outfits", ""))

	if not emotion_overrides.is_empty() and emotion_overrides.size() != stage_characters.size():
		errors.append("STAGE_SET %d emotions count must match characters count" % (index + 1))
	if not outfit_overrides.is_empty() and outfit_overrides.size() != stage_characters.size():
		errors.append("STAGE_SET %d outfits count must match characters count" % (index + 1))

	var enter_effect: String = _normalize_token(params.get("enter_effect", "fade")).to_lower()
	if enter_effect.is_empty():
		enter_effect = "fade"
	if not DEFAULT_ALLOWED_ENTER_EFFECTS.has(enter_effect):
		errors.append("STAGE_SET %d uses unsupported enter_effect: %s" % [index + 1, enter_effect])

	var exit_effect: String = _normalize_token(params.get("exit_effect", "fade")).to_lower()
	if exit_effect.is_empty():
		exit_effect = "fade"
	if not DEFAULT_ALLOWED_EXIT_EFFECTS.has(exit_effect):
		errors.append("STAGE_SET %d uses unsupported exit_effect: %s" % [index + 1, exit_effect])

	for easing_param in ["move_easing", "enter_easing", "exit_easing"]:
		var easing_name: String = _normalize_token(params.get(easing_param, ""))
		if easing_name.is_empty():
			continue
		if not DEFAULT_ALLOWED_EASINGS.has(easing_name):
			errors.append("STAGE_SET %d uses unsupported %s: %s" % [index + 1, easing_param, easing_name])

	for character_index in range(resolved_character_entries.size()):
		var character_entry: Dictionary = resolved_character_entries[character_index]
		var character_label: String = str(character_entry.get("character_id", stage_characters[character_index]))

		if character_index < emotion_overrides.size():
			var emotion_name: String = emotion_overrides[character_index]
			if not emotion_name.is_empty():
				var emotions: Array[String] = character_entry.get("emotions", [])
				if not emotions.has(emotion_name):
					errors.append("STAGE_SET %d uses missing emotion on %s: %s" % [index + 1, character_label, emotion_name])

		if character_index < outfit_overrides.size():
			var outfit_name: String = outfit_overrides[character_index]
			_validate_outfit_name(index, character_entry, character_label, outfit_name, "STAGE_SET", errors)


func _validate_change_expression(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String]) -> void:
	_validate_character_reference(index, params, character_map, "character_id", "CHANGE_EXPRESSION", errors)

	var character_ref: String = _normalize_token(params.get("character_id", ""))
	var expression: String = _normalize_token(params.get("expression", ""))
	if expression.is_empty():
		errors.append("CHANGE_EXPRESSION %d missing expression" % (index + 1))
		return

	var character_entry: Dictionary = _resolve_character_entry(character_map, character_ref)
	if character_entry.is_empty():
		return
	var character_label: String = str(character_entry.get("character_id", character_ref))

	var emotions: Array[String] = character_entry.get("emotions", [])
	if not emotions.has(expression):
		errors.append("CHANGE_EXPRESSION %d uses missing emotion on %s: %s" % [index + 1, character_label, expression])
		return

	var outfit: String = _normalize_token(params.get("outfit", ""))
	if not _validate_outfit_name(index, character_entry, character_label, outfit, "CHANGE_EXPRESSION", errors):
		return

	_validate_dynamic_sprite(index, character_entry, expression, outfit, "CHANGE_EXPRESSION", errors)


func _validate_change_outfit(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String]) -> void:
	_validate_character_reference(index, params, character_map, "character_id", "CHANGE_OUTFIT", errors)

	var character_ref: String = _normalize_token(params.get("character_id", ""))
	var outfit: String = _normalize_token(params.get("outfit", ""))
	if outfit.is_empty():
		errors.append("CHANGE_OUTFIT %d missing outfit" % (index + 1))
		return

	var character_entry: Dictionary = _resolve_character_entry(character_map, character_ref)
	if character_entry.is_empty():
		return
	var character_label: String = str(character_entry.get("character_id", character_ref))

	if not _validate_outfit_name(index, character_entry, character_label, outfit, "CHANGE_OUTFIT", errors):
		return

	var emotion: String = _normalize_token(params.get("emotion", ""))
	if emotion.is_empty():
		emotion = "default"
	_validate_dynamic_sprite(index, character_entry, emotion, outfit, "CHANGE_OUTFIT", errors)


func _validate_choice(index: int, params: Dictionary, min_choices: int, max_choices: int, errors: Array[String], warnings: Array[String]) -> void:
	var choices: Array = params.get("choices", [])
	if choices.is_empty():
		errors.append("CHOICE %d has no options" % (index + 1))
		return
	if min_choices > 0 and choices.size() < min_choices:
		errors.append("CHOICE %d has too few options: %d" % [index + 1, choices.size()])
	if max_choices > 0 and choices.size() > max_choices:
		errors.append("CHOICE %d has too many options: %d" % [index + 1, choices.size()])

	for choice_index in range(choices.size()):
		var choice: Dictionary = choices[choice_index] if choices[choice_index] is Dictionary else {}
		var text: String = _normalize_token(choice.get("text", ""))
		if text.is_empty():
			errors.append("CHOICE %d option %d is missing text" % [index + 1, choice_index + 1])
		var choice_commands: Array = choice.get("commands", [])
		if choice_commands.is_empty():
			warnings.append("CHOICE %d option %d has no follow-up commands" % [index + 1, choice_index + 1])


func _validate_show_image(index: int, params: Dictionary, project_root: String, errors: Array[String]) -> void:
	var image_id: String = _normalize_token(params.get("image_id", ""))
	if image_id.is_empty():
		errors.append("SHOW_IMAGE %d missing image_id" % (index + 1))
	_validate_asset_ref(index, params, "image_path", "image", project_root, ["images", "textures", "backgrounds"], errors)


func _validate_hide_image(index: int, params: Dictionary, errors: Array[String]) -> void:
	var image_id: String = _normalize_token(params.get("image_id", ""))
	if image_id.is_empty():
		errors.append("HIDE_IMAGE %d missing image_id" % (index + 1))


func _validate_character_reference(index: int, params: Dictionary, character_map: Dictionary, param_name: String, command_type: String, errors: Array[String]) -> void:
	var character_ref: String = _normalize_token(params.get(param_name, ""))
	if character_ref.is_empty():
		errors.append("%s %d missing %s" % [command_type, index + 1, param_name])
		return
	if _resolve_character_entry(character_map, character_ref).is_empty():
		errors.append("%s %d references missing character: %s" % [command_type, index + 1, character_ref])


func _validate_asset_ref(index: int, params: Dictionary, param_name: String, asset_label: String, project_root_path: String, buckets: Array[String], errors: Array[String]) -> void:
	var asset_ref: String = _normalize_token(params.get(param_name, ""))
	var direct_resource_key: String = param_name.replace("_path", "")
	var direct_resource: Variant = params.get(direct_resource_key, null)
	if asset_ref.is_empty() and direct_resource == null:
		errors.append("Command %d is missing %s reference" % [index + 1, asset_label])
		return
	if asset_ref.is_empty():
		return
	if not _asset_ref_exists(asset_ref, project_root_path, buckets):
		errors.append("Command %d references missing %s: %s" % [index + 1, asset_label, asset_ref])


func _asset_ref_exists(asset_ref: String, project_root_path: String, buckets: Array[String]) -> bool:
	var trimmed_ref: String = _normalize_token(asset_ref)
	if trimmed_ref.is_empty():
		return false

	if trimmed_ref.begins_with("res://") or trimmed_ref.begins_with("user://"):
		return _resource_ref_exists(trimmed_ref)

	if _is_texture_bucket_request(buckets):
		var resolved_texture: String = AVGAssetManifestClass.resolve_texture_path(trimmed_ref, project_root_path)
		if _resource_ref_exists(resolved_texture):
			return true
	if _is_audio_bucket_request(buckets):
		var resolved_audio: String = AVGAssetManifestClass.resolve_audio_path(trimmed_ref, project_root_path)
		if _resource_ref_exists(resolved_audio):
			return true

	var manifest: Dictionary = AVGAssetManifestClass.load_manifest(project_root_path)
	for bucket_name in buckets:
		var bucket: Dictionary = manifest.get(bucket_name, {})
		if bucket.has(trimmed_ref):
			var resolved: String = _resolve_manifest_value(str(bucket.get(trimmed_ref, "")), project_root_path)
			return _resource_ref_exists(resolved)

	return false


func _is_texture_bucket_request(buckets: Array[String]) -> bool:
	for bucket in buckets:
		if bucket in ["backgrounds", "images", "textures", "cg"]:
			return true
	return false


func _is_audio_bucket_request(buckets: Array[String]) -> bool:
	for bucket in buckets:
		if bucket in ["bgm", "sfx", "audio"]:
			return true
	return false


func _resource_ref_exists(resource_path: String) -> bool:
	var trimmed_path: String = _normalize_token(resource_path)
	if trimmed_path.is_empty():
		return false
	return ResourceLoader.exists(trimmed_path) or FileAccess.file_exists(trimmed_path)


func _resolve_manifest_value(value: String, project_root_path: String) -> String:
	var trimmed_value: String = _normalize_token(value)
	if trimmed_value.is_empty():
		return ""
	if trimmed_value.begins_with("res://") or trimmed_value.begins_with("user://"):
		return trimmed_value
	var normalized_root: String = project_root_path if project_root_path.ends_with("/") else project_root_path + "/"
	return normalized_root + trimmed_value


func _build_character_map(project: Resource) -> Dictionary:
	var character_map: Dictionary = {}
	if project == null or not "characters" in project:
		return character_map

	for character in project.characters:
		if character == null:
			continue
		var character_id: String = _normalize_token(character.character_id if "character_id" in character else "")
		if character_id.is_empty():
			continue

		var character_name: String = _normalize_token(character.character_name if "character_name" in character else "")
		var display_name: String = _normalize_token(character.display_name if "display_name" in character else "")
		var entry: Dictionary = {
			"character": character,
			"character_id": character_id,
			"character_name": character_name,
			"display_name": display_name,
			"emotions": _collect_character_emotions(character),
			"outfits": _collect_character_outfits(character),
		}
		character_map[character_id] = entry

		if not character_name.is_empty() and not character_map.has(character_name):
			character_map[character_name] = entry
		if not display_name.is_empty() and not character_map.has(display_name):
			character_map[display_name] = entry

	return character_map


func _collect_character_emotions(character: Resource) -> Array[String]:
	var emotions: Array[String] = []
	if character == null:
		return emotions

	var sprites: Dictionary = character.sprites if "sprites" in character else {}
	for key in sprites.keys():
		var emotion_name: String = _normalize_token(key)
		if emotion_name.is_empty():
			continue
		if "__" in emotion_name:
			var parts: PackedStringArray = emotion_name.split("__", false, 1)
			if parts.size() == 2:
				emotion_name = _normalize_token(parts[1])
		if emotion_name.is_empty() or emotions.has(emotion_name):
			continue
		emotions.append(emotion_name)

	if "emotion_slots" in character and character.emotion_slots is Dictionary:
		for key in character.emotion_slots.keys():
			var slot_emotion: String = _normalize_token(key)
			if slot_emotion.is_empty() or emotions.has(slot_emotion):
				continue
			emotions.append(slot_emotion)

	emotions.sort()
	return emotions


func _collect_character_outfits(character: Resource) -> Array[String]:
	var outfits: Array[String] = []
	if character == null:
		return outfits

	if "available_outfits" in character and character.available_outfits is Array:
		for entry in character.available_outfits:
			var outfit_name: String = _normalize_token(entry)
			if outfit_name.is_empty() or outfits.has(outfit_name):
				continue
			outfits.append(outfit_name)

	if "default_outfit" in character:
		var default_outfit: String = _normalize_token(character.default_outfit)
		if not default_outfit.is_empty() and not outfits.has(default_outfit):
			outfits.append(default_outfit)

	outfits.sort()
	return outfits


func _resolve_character_entry(character_map: Dictionary, character_ref: String) -> Dictionary:
	var normalized_ref: String = _normalize_token(character_ref)
	if normalized_ref.is_empty():
		return {}
	return character_map.get(normalized_ref, {})


func _validate_outfit_name(index: int, character_entry: Dictionary, character_label: String, outfit: String, command_type: String, errors: Array[String]) -> bool:
	if outfit.is_empty():
		return true
	var outfits: Array[String] = character_entry.get("outfits", [])
	if not outfits.is_empty() and not outfits.has(outfit):
		errors.append("%s %d uses missing outfit on %s: %s" % [command_type, index + 1, character_label, outfit])
		return false
	return true


func _validate_dynamic_sprite(index: int, character_entry: Dictionary, emotion: String, outfit: String, command_type: String, errors: Array[String]) -> void:
	if character_entry.is_empty():
		return
	var character: Resource = character_entry.get("character", null)
	if character == null:
		return

	var normalized_emotion: String = _normalize_token(emotion)
	if normalized_emotion.is_empty():
		normalized_emotion = "default"
	var resolved_outfit: String = AVGCharacterClass.resolve_outfit_name(character, outfit)
	var dynamic_path: String = AVGCharacterClass.resolve_outfit_sprite_path(character, normalized_emotion, resolved_outfit)
	if dynamic_path.is_empty():
		return
	if not _resource_ref_exists(dynamic_path):
		errors.append("%s %d needs missing sprite: %s" % [command_type, index + 1, dynamic_path])


func _extract_stage_characters(params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw_characters: Variant = params.get("characters", [])
	if raw_characters is Array:
		for entry in raw_characters:
			var character_ref: String = _normalize_token(entry)
			if character_ref.is_empty():
				continue
			result.append(character_ref)
		if not result.is_empty():
			return result

	return _parse_stage_override_list(params.get("characters_csv", ""))


func _parse_stage_override_list(value: Variant) -> Array[String]:
	var raw_text: String = _normalize_token(value)
	var result: Array[String] = []
	if raw_text.is_empty():
		return result

	for entry in raw_text.split(","):
		var trimmed: String = entry.strip_edges()
		if trimmed == "_":
			result.append("")
			continue
		result.append(trimmed)
	return result


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for entry in value:
		var text: String = _normalize_token(entry)
		if text.is_empty():
			continue
		result.append(text)
	return result


func _normalize_token(value: Variant) -> String:
	var text: String = str(value).strip_edges()
	if text.length() >= 2:
		if text.begins_with("\"") and text.ends_with("\""):
			text = text.substr(1, text.length() - 2)
		elif text.begins_with("'") and text.ends_with("'"):
			text = text.substr(1, text.length() - 2)
	return text.strip_edges()
