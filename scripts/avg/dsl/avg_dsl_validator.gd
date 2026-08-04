class_name AVGDSLValidator extends RefCounted

const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")
const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

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


func validate_commands(commands: Array, game_data: Resource, options: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var _allowed_commands: Array[String] = _to_string_array(options.get("allowed_commands", []))
	var allowed_positions: Array[String] = _to_string_array(options.get("allowed_positions", DEFAULT_ALLOWED_POSITIONS))
	var min_choices: int = int(options.get("min_choice_count", 0))
	var max_choices: int = int(options.get("max_choice_count", 0))
	var character_map: Dictionary = _build_character_map(game_data)
	var variable_map: Dictionary = _build_variable_map(game_data)

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
				_validate_stage_set(index, params, character_map, errors, warnings)
			"STAGE_ENTER":
				_validate_stage_enter(index, params, character_map, errors, warnings)
			"STAGE_EXIT":
				_validate_stage_exit(index, params, character_map, errors, warnings)
			"CHANGE_EXPRESSION":
				_validate_change_expression(index, params, character_map, errors)
			"CHANGE_OUTFIT":
				_validate_change_outfit(index, params, character_map, errors)
			"CHANGE_BACKGROUND":
				_validate_asset_ref(index, params, "texture_path", "background", ["backgrounds", "images", "textures"], errors)
			"SHOW_IMAGE":
				_validate_show_image(index, params, errors)
			"HIDE_IMAGE":
				_validate_hide_image(index, params, errors)
			"PLAY_BGM":
				_validate_asset_ref(index, params, "audio_path", "bgm", ["bgm", "audio"], errors)
			"PLAY_SFX":
				_validate_asset_ref(index, params, "audio_path", "sfx", ["sfx", "audio"], errors)
			"CHOICE":
				_validate_choice(index, params, min_choices, max_choices, errors, warnings)

	_validate_variable_semantics(commands, variable_map, warnings)

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
		errors.append(_format_missing_emotion_error("DIALOGUE", index, character_label, emotion, emotions))


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
			errors.append(_format_missing_emotion_error("SHOW_CHARACTER", index, character_label, emotion, emotions))
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


func _validate_stage_set(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
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
			if _looks_like_text_only_npc_reference(character_ref):
				warnings.append("STAGE_SET %d ignores text-only NPC on stage: %s" % [index + 1, character_ref])
				continue
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
					errors.append(_format_missing_emotion_error("STAGE_SET", index, character_label, emotion_name, emotions))

		if character_index < outfit_overrides.size():
			var outfit_name: String = outfit_overrides[character_index]
			_validate_outfit_name(index, character_entry, character_label, outfit_name, "STAGE_SET", errors)


func _validate_stage_enter(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var stage_characters: Array[String] = _extract_stage_characters(params)
	if stage_characters.is_empty():
		errors.append("STAGE_ENTER %d must include at least one character" % (index + 1))
		return
	if stage_characters.size() > MAX_STAGE_CHARACTERS:
		errors.append("STAGE_ENTER %d supports at most %d characters at once, got %d" % [index + 1, MAX_STAGE_CHARACTERS, stage_characters.size()])

	var resolved_character_entries: Array[Dictionary] = []
	var seen_character_ids: Dictionary = {}
	for character_ref in stage_characters:
		var character_entry: Dictionary = _resolve_character_entry(character_map, character_ref)
		if character_entry.is_empty():
			if _looks_like_text_only_npc_reference(character_ref):
				warnings.append("STAGE_ENTER %d ignores text-only NPC on stage: %s" % [index + 1, character_ref])
				continue
			errors.append("STAGE_ENTER %d references missing character: %s" % [index + 1, character_ref])
			continue
		var resolved_character_id: String = str(character_entry.get("character_id", character_ref))
		if seen_character_ids.has(resolved_character_id):
			errors.append("STAGE_ENTER %d repeats character: %s" % [index + 1, resolved_character_id])
			continue
		seen_character_ids[resolved_character_id] = true
		resolved_character_entries.append(character_entry)

	var emotion_overrides: Array[String] = _parse_stage_override_list(params.get("emotions", ""))
	var outfit_overrides: Array[String] = _parse_stage_override_list(params.get("outfits", ""))
	if not emotion_overrides.is_empty() and emotion_overrides.size() != stage_characters.size():
		errors.append("STAGE_ENTER %d emotions count must match characters count" % (index + 1))
	if not outfit_overrides.is_empty() and outfit_overrides.size() != stage_characters.size():
		errors.append("STAGE_ENTER %d outfits count must match characters count" % (index + 1))

	var enter_effect: String = _normalize_token(params.get("enter_effect", "fade")).to_lower()
	if enter_effect.is_empty():
		enter_effect = "fade"
	if not DEFAULT_ALLOWED_ENTER_EFFECTS.has(enter_effect):
		errors.append("STAGE_ENTER %d uses unsupported enter_effect: %s" % [index + 1, enter_effect])

	for easing_param in ["move_easing", "enter_easing"]:
		var easing_name: String = _normalize_token(params.get(easing_param, ""))
		if easing_name.is_empty():
			continue
		if not DEFAULT_ALLOWED_EASINGS.has(easing_name):
			errors.append("STAGE_ENTER %d uses unsupported %s: %s" % [index + 1, easing_param, easing_name])

	for character_index in range(resolved_character_entries.size()):
		var character_entry: Dictionary = resolved_character_entries[character_index]
		var character_label: String = str(character_entry.get("character_id", stage_characters[character_index]))
		if character_index < emotion_overrides.size():
			var emotion_name: String = emotion_overrides[character_index]
			if not emotion_name.is_empty():
				var emotions: Array[String] = character_entry.get("emotions", [])
				if not emotions.has(emotion_name):
					errors.append(_format_missing_emotion_error("STAGE_ENTER", index, character_label, emotion_name, emotions))
		if character_index < outfit_overrides.size():
			var outfit_name: String = outfit_overrides[character_index]
			_validate_outfit_name(index, character_entry, character_label, outfit_name, "STAGE_ENTER", errors)


func _validate_stage_exit(index: int, params: Dictionary, character_map: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var stage_characters: Array[String] = _extract_stage_characters(params)
	if stage_characters.is_empty():
		errors.append("STAGE_EXIT %d must include at least one character" % (index + 1))
		return

	var seen_character_ids: Dictionary = {}
	for character_ref in stage_characters:
		var character_entry: Dictionary = _resolve_character_entry(character_map, character_ref)
		if character_entry.is_empty():
			if _looks_like_text_only_npc_reference(character_ref):
				warnings.append("STAGE_EXIT %d ignores text-only NPC on stage: %s" % [index + 1, character_ref])
				continue
			errors.append("STAGE_EXIT %d references missing character: %s" % [index + 1, character_ref])
			continue
		var resolved_character_id: String = str(character_entry.get("character_id", character_ref))
		if seen_character_ids.has(resolved_character_id):
			errors.append("STAGE_EXIT %d repeats character: %s" % [index + 1, resolved_character_id])
			continue
		seen_character_ids[resolved_character_id] = true

	var exit_effect: String = _normalize_token(params.get("exit_effect", "fade")).to_lower()
	if exit_effect.is_empty():
		exit_effect = "fade"
	if not DEFAULT_ALLOWED_EXIT_EFFECTS.has(exit_effect):
		errors.append("STAGE_EXIT %d uses unsupported exit_effect: %s" % [index + 1, exit_effect])

	for easing_param in ["move_easing", "exit_easing"]:
		var easing_name: String = _normalize_token(params.get(easing_param, ""))
		if easing_name.is_empty():
			continue
		if not DEFAULT_ALLOWED_EASINGS.has(easing_name):
			errors.append("STAGE_EXIT %d uses unsupported %s: %s" % [index + 1, easing_param, easing_name])


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
		errors.append(_format_missing_emotion_error("CHANGE_EXPRESSION", index, character_label, expression, emotions))
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


func _format_missing_emotion_error(command_name: String, index: int, character_label: String, emotion: String, allowed_emotions: Array[String]) -> String:
	var allowed_text: String = "(none)"
	if not allowed_emotions.is_empty():
		allowed_text = ", ".join(allowed_emotions)
	return "%s %d uses missing emotion on %s: %s (allowed: [%s])" % [
		command_name,
		index + 1,
		character_label,
		emotion,
		allowed_text,
	]


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


func _validate_show_image(index: int, params: Dictionary, errors: Array[String]) -> void:
	var image_id: String = _normalize_token(params.get("image_id", ""))
	if image_id.is_empty():
		errors.append("SHOW_IMAGE %d missing image_id" % (index + 1))
	var transition: String = _normalize_token(params.get("transition", "")).to_lower()
	if not transition.is_empty() and not ["fade", "crossfade", "fade_through_black", "instant"].has(transition):
		errors.append("SHOW_IMAGE %d uses unsupported transition: %s" % [index + 1, transition])
	_validate_asset_ref(index, params, "image_path", "image", ["images", "textures", "backgrounds", "cg"], errors)


func _validate_hide_image(index: int, params: Dictionary, errors: Array[String]) -> void:
	var image_id: String = _normalize_token(params.get("image_id", ""))
	if image_id.is_empty():
		errors.append("HIDE_IMAGE %d missing image_id" % (index + 1))
	var transition: String = _normalize_token(params.get("transition", "")).to_lower()
	if not transition.is_empty() and not ["fade", "instant"].has(transition):
		errors.append("HIDE_IMAGE %d uses unsupported transition: %s" % [index + 1, transition])


func _validate_character_reference(index: int, params: Dictionary, character_map: Dictionary, param_name: String, command_type: String, errors: Array[String]) -> void:
	var character_ref: String = _normalize_token(params.get(param_name, ""))
	if character_ref.is_empty():
		errors.append("%s %d missing %s" % [command_type, index + 1, param_name])
		return
	if _resolve_character_entry(character_map, character_ref).is_empty():
		errors.append("%s %d references missing character: %s" % [command_type, index + 1, character_ref])


func _validate_asset_ref(index: int, params: Dictionary, param_name: String, asset_label: String, buckets: Array[String], errors: Array[String]) -> void:
	var asset_ref: String = _normalize_token(params.get(param_name, ""))
	var direct_resource_key: String = param_name.replace("_path", "")
	var direct_resource: Variant = params.get(direct_resource_key, null)
	if asset_ref.is_empty() and direct_resource == null:
		errors.append("Command %d is missing %s reference" % [index + 1, asset_label])
		return
	if asset_ref.is_empty():
		return
	if not _asset_ref_exists(asset_ref, buckets):
		errors.append("Command %d references missing %s: %s" % [index + 1, asset_label, asset_ref])


func _asset_ref_exists(asset_ref: String, buckets: Array[String]) -> bool:
	var trimmed_ref: String = _normalize_token(asset_ref)
	if trimmed_ref.is_empty():
		return false

	if trimmed_ref.begins_with("res://") or trimmed_ref.begins_with("user://"):
		return _resource_ref_exists(trimmed_ref)

	if _is_texture_bucket_request(buckets):
		var resolved_texture: String = AVGAssetManifestClass.resolve_texture_path(trimmed_ref)
		if _resource_ref_exists(resolved_texture):
			return true
	if _is_audio_bucket_request(buckets):
		var resolved_audio: String = AVGAssetManifestClass.resolve_audio_path(trimmed_ref)
		if _resource_ref_exists(resolved_audio):
			return true

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


func _build_character_map(game_data: Resource) -> Dictionary:
	var character_map: Dictionary = {}
	if game_data == null or not "characters" in game_data:
		return character_map

	for character in game_data.characters:
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


func _build_variable_map(game_data: Resource) -> Dictionary:
	var variable_map: Dictionary = {}
	if game_data == null or not ("variables" in game_data):
		return variable_map

	for variable in game_data.variables:
		if variable == null:
			continue
		var variable_id: String = str(variable.variable_id if "variable_id" in variable else "").strip_edges()
		var variable_key: String = AVGVariableClass.get_key(variable)
		var entry: Dictionary = {
			"variable_id": variable_id,
			"variable_key": variable_key,
			"value_type": AVGVariableClass.get_value_type(variable),
		}
		if not variable_id.is_empty():
			variable_map[variable_id] = entry
		if not variable_key.is_empty() and not variable_map.has(variable_key):
			variable_map[variable_key] = entry
	return variable_map


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


func _looks_like_text_only_npc_reference(character_ref: String) -> bool:
	var normalized_ref: String = str(character_ref).strip_edges()
	if normalized_ref.is_empty():
		return false
	for index in range(normalized_ref.length()):
		if normalized_ref.unicode_at(index) > 127:
			return true
	return false


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


func _validate_variable_semantics(commands: Array, variable_map: Dictionary, warnings: Array[String], path_prefix: String = "") -> void:
	for index in range(commands.size()):
		var cmd: Variant = commands[index]
		if cmd == null:
			continue
		var command_type: String = ""
		var params: Dictionary = {}
		if cmd is Resource and "command_type" in cmd:
			command_type = str(cmd.command_type)
			params = cmd.params if cmd.params is Dictionary else {}
		elif cmd is Dictionary:
			command_type = str(cmd.get("command_type", ""))
			params = cmd.get("params", {})
		else:
			continue

		var location: String = "%s%d" % [path_prefix, index + 1]
		match command_type:
			"SET_VARIABLE":
				_validate_set_variable_semantics(location, params, variable_map, warnings)
			"CHECK_VAR":
				_validate_check_var_semantics(location, params, variable_map, warnings)
			"IF":
				_validate_variable_semantics(params.get("condition_commands", []), variable_map, warnings, location + ".cond.")
				_validate_variable_semantics(params.get("if_condition_commands", []), variable_map, warnings, location + ".cond_if.")
				_validate_variable_semantics(params.get("else_condition_commands", []), variable_map, warnings, location + ".cond_else.")
				_validate_variable_semantics(params.get("if_commands", []), variable_map, warnings, location + ".if.")
				_validate_variable_semantics(params.get("else_commands", []), variable_map, warnings, location + ".else.")
			"CHOICE":
				var choices: Array = params.get("choices", [])
				for choice_index in range(choices.size()):
					var choice: Dictionary = choices[choice_index] if choices[choice_index] is Dictionary else {}
					_validate_variable_semantics(choice.get("condition_commands", []), variable_map, warnings, "%s.choice%d.cond." % [location, choice_index + 1])
					_validate_variable_semantics(choice.get("commands", []), variable_map, warnings, "%s.choice%d." % [location, choice_index + 1])


func _validate_set_variable_semantics(location: String, params: Dictionary, variable_map: Dictionary, warnings: Array[String]) -> void:
	var target_entry: Dictionary = _resolve_variable_entry(variable_map, params, "variable_id", "variable_key", "variable_name")
	if target_entry.is_empty():
		return

	var target_type: String = str(target_entry.get("value_type", AVGVariableClass.VALUE_TYPE_INT))
	var operation: String = str(params.get("operation", "set")).strip_edges()
	if target_type == AVGVariableClass.VALUE_TYPE_STRING and operation != "set":
		_append_warning_unique(warnings, "SET_VARIABLE %s 对 string 变量使用了数值操作 `%s`，运行时会先按 int 计算，再把结果存回字符串。" % [location, operation])

	if str(params.get("value_source", "constant")).strip_edges() != "constant":
		return

	var literal_type: String = _infer_literal_value_type(params.get("value", 0))
	if target_type != literal_type:
		_append_warning_unique(warnings, "SET_VARIABLE %s 给 %s 变量 `%s` 写入了 %s 常量，运行时会发生类型归一化。" % [
			location,
			target_type,
			str(target_entry.get("variable_key", target_entry.get("variable_id", ""))),
			literal_type,
		])


func _validate_check_var_semantics(location: String, params: Dictionary, variable_map: Dictionary, warnings: Array[String]) -> void:
	var lhs_entry: Dictionary = _resolve_variable_entry(variable_map, params, "variable_id", "variable_key", "variable_name")
	if lhs_entry.is_empty():
		return

	var lhs_type: String = str(lhs_entry.get("value_type", AVGVariableClass.VALUE_TYPE_INT))
	var rhs_type: String = AVGVariableClass.VALUE_TYPE_INT
	match str(params.get("value_source", "constant")).strip_edges():
		"variable":
			var rhs_entry: Dictionary = _resolve_variable_entry(variable_map, params, "source_variable_id", "source_variable_key", "source_variable_name")
			if rhs_entry.is_empty():
				return
			rhs_type = str(rhs_entry.get("value_type", AVGVariableClass.VALUE_TYPE_INT))
		"game_data":
			rhs_type = AVGVariableClass.VALUE_TYPE_INT
		_:
			rhs_type = _infer_literal_value_type(params.get("value", 0))

	var operator_text: String = str(params.get("operator", "==")).strip_edges()
	var variable_label: String = str(lhs_entry.get("variable_key", lhs_entry.get("variable_id", "")))
	if lhs_type != rhs_type:
		_append_warning_unique(warnings, "CHECK_VAR %s 把 %s 变量 `%s` 和 %s 做比较。运行时会把空字符串视为 0、非空字符串视为 1。" % [
			location,
			lhs_type,
			variable_label,
			rhs_type,
		])
		return

	if lhs_type == AVGVariableClass.VALUE_TYPE_STRING and operator_text in [">", ">=", "<", "<="]:
		_append_warning_unique(warnings, "CHECK_VAR %s 对 string 变量 `%s` 使用了 `%s`。字符串语义通常只建议使用 `==` / `!=`。" % [
			location,
			variable_label,
			operator_text,
		])


func _resolve_variable_entry(variable_map: Dictionary, params: Dictionary, id_field: String, key_field: String, legacy_field: String) -> Dictionary:
	var variable_id: String = str(params.get(id_field, "")).strip_edges()
	if not variable_id.is_empty() and variable_map.has(variable_id):
		return variable_map[variable_id]
	var variable_key: String = AVGVariableClass.normalize_key(str(params.get(key_field, params.get(legacy_field, ""))).strip_edges())
	if not variable_key.is_empty() and variable_map.has(variable_key):
		return variable_map[variable_key]
	return {}


func _infer_literal_value_type(value: Variant) -> String:
	if value is String:
		return AVGVariableClass.VALUE_TYPE_STRING
	return AVGVariableClass.VALUE_TYPE_INT


func _append_warning_unique(warnings: Array[String], message: String) -> void:
	if warnings.has(message):
		return
	warnings.append(message)
