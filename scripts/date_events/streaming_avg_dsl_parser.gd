class_name StreamingAVGDSLParser
extends RefCounted

const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")

const DEFAULT_SAY_SPEED: float = 30.0
const DEFAULT_SAY_HOLD: float = 0.8
const DEFAULT_CHAT_DELAY: float = 0.25
const DEFAULT_HOST_DURATION: float = 0.2
const DEFAULT_HOST_X: float = 0.5
const DEFAULT_HOST_Y: float = 0.8
const DEFAULT_HOST_SCALE: float = 1.0

const STREAM_KEYS: Array[String] = ["host", "viewers", "day"]
const SAY_KEYS: Array[String] = ["speed", "hold"]
const CHAT_KEYS: Array[String] = ["delay"]


func parse(script_text: String) -> Dictionary:
	var events: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var meta: Dictionary = {}
	var has_end := false

	var lines: PackedStringArray = script_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for i in range(lines.size()):
		var line_number := i + 1
		var line := _strip_comment(str(lines[i])).strip_edges()
		if line.is_empty():
			continue
		var parsed := _parse_command(line)
		if not str(parsed.get("error", "")).is_empty():
			errors.append(_error(line_number, str(parsed.get("error", ""))))
			continue

		var command := str(parsed.get("command", ""))
		var args: Array = parsed.get("args", [])
		var kwargs: Dictionary = parsed.get("kwargs", {})
		match command:
			"@stream":
				var stream_event := _parse_stream_meta(line_number, args, kwargs, meta, errors)
				if not stream_event.is_empty():
					events.append(stream_event)
			"bg":
				var bg_event := _parse_background(line_number, args, kwargs, errors)
				if not bg_event.is_empty():
					events.append(bg_event)
			"host":
				var host_event := _parse_host(line_number, args, kwargs, errors)
				if not host_event.is_empty():
					events.append(host_event)
			"emotion":
				var emotion_event := _parse_emotion(line_number, args, kwargs, errors)
				if not emotion_event.is_empty():
					events.append(emotion_event)
			"say":
				var say_event := _parse_say(line_number, args, kwargs, errors)
				if not say_event.is_empty():
					events.append(say_event)
			"chat":
				var chat_event := _parse_chat(line_number, args, kwargs, errors)
				if not chat_event.is_empty():
					events.append(chat_event)
			"wait":
				var wait_event := _parse_wait(line_number, args, kwargs, errors)
				if not wait_event.is_empty():
					events.append(wait_event)
			"end":
				if not args.is_empty():
					errors.append(_error(line_number, "end does not accept positional arguments"))
					continue
				if not kwargs.is_empty():
					_append_unknown_key_errors(errors, line_number, kwargs, [])
					continue
				has_end = true
				events.append({"type": "end"})
			_:
				errors.append(_error(line_number, "unknown streaming command: %s" % command))

	if not has_end:
		errors.append(_error(lines.size(), "stream script must end with end"))

	return {
		"success": errors.is_empty(),
		"events": events,
		"meta": meta,
		"errors": errors,
	}


func validate_assets(events: Array, project: Resource = null, project_root_path: String = "") -> Dictionary:
	var errors: Array[Dictionary] = []
	var current_character: Resource = null
	for i in range(events.size()):
		var event: Dictionary = events[i]
		match str(event.get("type", "")):
			"background":
				var asset_ref := str(event.get("asset_ref", "")).strip_edges()
				if not _is_background_alias(asset_ref, project_root_path):
					errors.append(_error(i + 1, "missing background alias: %s" % asset_ref))
			"host_show":
				var character_ref := str(event.get("character", "")).strip_edges()
				current_character = _find_character_by_name(project, character_ref)
				if current_character == null:
					errors.append(_error(i + 1, "missing host character_name: %s" % character_ref))
					continue
				_validate_character_event(i + 1, current_character, event, errors)
			"host_emotion":
				if current_character == null:
					errors.append(_error(i + 1, "emotion requires a preceding host command"))
					continue
				_validate_character_event(i + 1, current_character, event, errors)
	return {
		"success": errors.is_empty(),
		"errors": errors,
	}


func build_package(session_id: String, script_text: String, title: String = "", project: Resource = null, project_root_path: String = "") -> Dictionary:
	var parse_result: Dictionary = parse(script_text)
	if not bool(parse_result.get("success", false)):
		return {}
	var meta: Dictionary = parse_result.get("meta", {})
	var resolved_title := title.strip_edges()
	if resolved_title.is_empty():
		resolved_title = str(meta.get("title", "直播")).strip_edges()
	return {
		"session_id": session_id,
		"title": resolved_title if not resolved_title.is_empty() else "直播",
		"stream_script": script_text,
		"events": parse_result.get("events", []),
		"meta": meta,
		"project": project,
		"project_root_path": project_root_path,
	}


func errors_to_text(errors: Array) -> String:
	var messages: Array[String] = []
	for entry in errors:
		if entry is Dictionary:
			var line := int((entry as Dictionary).get("line", 0))
			var message := str((entry as Dictionary).get("message", ""))
			if line > 0:
				messages.append("line %d: %s" % [line, message])
			else:
				messages.append(message)
		else:
			messages.append(str(entry))
	return "\n".join(PackedStringArray(messages))


func _parse_stream_meta(line_number: int, args: Array, kwargs: Dictionary, meta: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	var error_count := errors.size()
	_append_unknown_key_errors(errors, line_number, kwargs, STREAM_KEYS)
	if errors.size() > error_count:
		return {}
	if args.size() != 1 or str(args[0]).strip_edges().is_empty():
		errors.append(_error(line_number, "@stream requires exactly one quoted title"))
		return {}
	var host_ref := str(kwargs.get("host", "")).strip_edges()
	if host_ref.is_empty():
		errors.append(_error(line_number, "@stream requires host=<character_name>"))
		return {}
	if _looks_like_character_id(host_ref):
		errors.append(_error(line_number, "@stream host must use character_name, not character_id: %s" % host_ref))
		return {}
	if kwargs.has("viewers") and not _is_number(kwargs["viewers"]):
		errors.append(_error(line_number, "@stream viewers must be a number"))
		return {}

	meta["title"] = str(args[0]).strip_edges()
	meta["host"] = host_ref
	if kwargs.has("viewers"):
		meta["viewers"] = maxi(0, int(kwargs["viewers"]))
	if kwargs.has("day"):
		meta["day_label"] = str(kwargs["day"]).strip_edges()
	return {
		"type": "stream_meta",
		"meta": meta.duplicate(true),
	}


func _parse_background(line_number: int, args: Array, kwargs: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	if not kwargs.is_empty():
		_append_unknown_key_errors(errors, line_number, kwargs, [])
		return {}
	if args.size() != 1 or str(args[0]).strip_edges().is_empty():
		errors.append(_error(line_number, "bg requires one background alias"))
		return {}
	var asset_ref := str(args[0]).strip_edges()
	if _looks_like_path_reference(asset_ref):
		errors.append(_error(line_number, "bg must use a background alias, not a path: %s" % asset_ref))
		return {}
	return {
		"type": "background",
		"asset_ref": asset_ref,
	}


func _parse_host(line_number: int, args: Array, kwargs: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	if not kwargs.is_empty():
		_append_unknown_key_errors(errors, line_number, kwargs, [])
		return {}
	if args.size() < 1 or args.size() > 3 or str(args[0]).strip_edges().is_empty():
		errors.append(_error(line_number, "host requires: host <character_name> [emotion] [outfit]"))
		return {}
	var character_ref := str(args[0]).strip_edges()
	if _looks_like_character_id(character_ref):
		errors.append(_error(line_number, "host must use character_name, not character_id: %s" % character_ref))
		return {}
	return {
		"type": "host_show",
		"character": character_ref,
		"emotion": str(args[1]).strip_edges() if args.size() >= 2 else "default",
		"outfit": str(args[2]).strip_edges() if args.size() >= 3 else "",
		"x": DEFAULT_HOST_X,
		"y": DEFAULT_HOST_Y,
		"scale": DEFAULT_HOST_SCALE,
		"duration": DEFAULT_HOST_DURATION,
	}


func _parse_emotion(line_number: int, args: Array, kwargs: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	if not kwargs.is_empty():
		_append_unknown_key_errors(errors, line_number, kwargs, [])
		return {}
	if args.size() != 1 or str(args[0]).strip_edges().is_empty():
		errors.append(_error(line_number, "emotion requires one emotion name"))
		return {}
	return {
		"type": "host_emotion",
		"emotion": str(args[0]).strip_edges(),
		"outfit": "",
		"duration": DEFAULT_HOST_DURATION,
	}


func _parse_say(line_number: int, args: Array, kwargs: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	var error_count := errors.size()
	_append_unknown_key_errors(errors, line_number, kwargs, SAY_KEYS)
	if errors.size() > error_count:
		return {}
	if args.is_empty() or str(args[0]).strip_edges().is_empty():
		errors.append(_error(line_number, "say requires subtitle text"))
		return {}
	if _has_bad_numeric(kwargs, ["speed", "hold"]):
		errors.append(_error(line_number, "say timing parameters must be valid numbers"))
		return {}
	var text := str(args[0])
	var speed := maxf(float(kwargs.get("speed", DEFAULT_SAY_SPEED)), 1.0)
	var hold := maxf(float(kwargs.get("hold", DEFAULT_SAY_HOLD)), 0.0)
	var duration := float(text.length()) / speed + hold
	return {
		"type": "subtitle",
		"text": text,
		"speed": speed,
		"hold": hold,
		"duration": maxf(duration, 0.0),
	}


func _parse_chat(line_number: int, args: Array, kwargs: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	var error_count := errors.size()
	_append_unknown_key_errors(errors, line_number, kwargs, CHAT_KEYS)
	if errors.size() > error_count:
		return {}
	if args.is_empty() or str(args[0]).strip_edges().is_empty():
		errors.append(_error(line_number, "chat requires message text"))
		return {}
	if _has_bad_numeric(kwargs, ["delay"]):
		errors.append(_error(line_number, "chat delay must be a valid number"))
		return {}
	return {
		"type": "chat",
		"text": str(args[0]),
		"delay": maxf(float(kwargs.get("delay", DEFAULT_CHAT_DELAY)), 0.0),
	}


func _parse_wait(line_number: int, args: Array, kwargs: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	if not kwargs.is_empty():
		_append_unknown_key_errors(errors, line_number, kwargs, [])
		return {}
	if args.is_empty() or not _is_number(args[0]):
		errors.append(_error(line_number, "wait requires a numeric duration"))
		return {}
	return {
		"type": "wait",
		"duration": maxf(float(args[0]), 0.0),
	}


func _parse_command(line: String) -> Dictionary:
	var first_space: int = _find_first_whitespace(line)
	var command: String = line
	var rest: String = ""
	if first_space >= 0:
		command = line.substr(0, first_space).strip_edges()
		rest = line.substr(first_space + 1).strip_edges()

	var scan_result: Dictionary = _scan_tokens(rest)
	if not str(scan_result.get("error", "")).is_empty():
		return {"error": scan_result.get("error", "")}

	var args: Array = []
	var kwargs: Dictionary = {}
	for token in scan_result.get("tokens", []):
		var token_text := str(token)
		var eq := token_text.find("=")
		if eq > 0:
			var key := token_text.substr(0, eq).strip_edges()
			var value := token_text.substr(eq + 1)
			kwargs[key] = _parse_scalar(value)
		else:
			args.append(_parse_scalar(token_text))

	return {
		"command": command,
		"args": args,
		"kwargs": kwargs,
	}


func _scan_tokens(text: String) -> Dictionary:
	var tokens: Array[String] = []
	var current := ""
	var in_quote := false
	var quote_char := ""
	var escaped := false

	for i in range(text.length()):
		var ch := text.substr(i, 1)
		if escaped:
			current += _decode_escape(ch)
			escaped = false
			continue
		if in_quote:
			if ch == "\\":
				escaped = true
			elif ch == quote_char:
				in_quote = false
			else:
				current += ch
			continue
		if ch == "\"" or ch == "'":
			in_quote = true
			quote_char = ch
		elif _is_whitespace(ch):
			if not current.is_empty():
				tokens.append(current)
				current = ""
		else:
			current += ch

	if escaped:
		current += "\\"
	if in_quote:
		return {"error": "unterminated quoted string"}
	if not current.is_empty():
		tokens.append(current)
	return {"tokens": tokens}


func _strip_comment(line: String) -> String:
	var in_quote := false
	var quote_char := ""
	var escaped := false
	for i in range(line.length()):
		var ch := line.substr(i, 1)
		if escaped:
			escaped = false
			continue
		if in_quote:
			if ch == "\\":
				escaped = true
			elif ch == quote_char:
				in_quote = false
			continue
		if ch == "\"" or ch == "'":
			in_quote = true
			quote_char = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _append_unknown_key_errors(errors: Array[Dictionary], line_number: int, kwargs: Dictionary, allowed_keys: Array[String]) -> void:
	for key in kwargs.keys():
		if not allowed_keys.has(str(key)):
			errors.append(_error(line_number, "unknown parameter: %s" % str(key)))


func _find_first_whitespace(text: String) -> int:
	for i in range(text.length()):
		if _is_whitespace(text.substr(i, 1)):
			return i
	return -1


func _parse_scalar(raw_value: String) -> Variant:
	var value: String = raw_value.strip_edges()
	var lower: String = value.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	if value.is_valid_int():
		return int(value)
	if value.is_valid_float():
		return float(value)
	return value


func _has_bad_numeric(kwargs: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if kwargs.has(key) and not _is_number(kwargs[key]):
			return true
	return false


func _is_number(value: Variant) -> bool:
	return value is int or value is float or str(value).strip_edges().is_valid_float()


func _is_whitespace(ch: String) -> bool:
	return ch == " " or ch == "\t"


func _decode_escape(ch: String) -> String:
	match ch:
		"n":
			return "\n"
		"t":
			return "\t"
		"r":
			return "\r"
		_:
			return ch


func _error(line_number: int, message: String) -> Dictionary:
	return {
		"line": line_number,
		"message": message,
	}


func _looks_like_path_reference(asset_ref: String) -> bool:
	var normalized := asset_ref.strip_edges()
	return normalized.begins_with("res://") \
		or normalized.begins_with("user://") \
		or normalized.find("/") >= 0 \
		or normalized.find("\\") >= 0


func _looks_like_character_id(character_ref: String) -> bool:
	var normalized := character_ref.strip_edges()
	if not normalized.begins_with("char_") or normalized.length() <= 5:
		return false
	for i in range(5, normalized.length()):
		var ch := normalized.substr(i, 1)
		if not ch.is_valid_int():
			return false
	return true


func _is_background_alias(asset_ref: String, project_root_path: String) -> bool:
	var normalized := asset_ref.strip_edges()
	if normalized.is_empty() or _looks_like_path_reference(normalized):
		return false
	var manifest: Dictionary = AVGAssetManifestClass.load_manifest(project_root_path)
	var backgrounds: Dictionary = manifest.get("backgrounds", {})
	return backgrounds.has(normalized)


func _find_character_by_name(project: Resource, character_name: String) -> Resource:
	if project == null or character_name.strip_edges().is_empty():
		return null
	if not ("characters" in project):
		return null
	for character in project.characters:
		if character == null:
			continue
		var char_name := str(character.character_name if "character_name" in character else "").strip_edges()
		if character_name == char_name:
			return character
	return null


func _validate_character_event(line_number: int, character: Resource, event: Dictionary, errors: Array[Dictionary]) -> void:
	var character_name := str(character.character_name if "character_name" in character else "").strip_edges()
	var emotion := str(event.get("emotion", "")).strip_edges()
	if not emotion.is_empty() and not _character_has_emotion(character, emotion):
		errors.append(_error(line_number, "missing emotion '%s' for character_name: %s" % [emotion, character_name]))
	var outfit := str(event.get("outfit", "")).strip_edges()
	if not outfit.is_empty() and not _character_has_outfit(character, outfit):
		errors.append(_error(line_number, "missing outfit '%s' for character_name: %s" % [outfit, character_name]))


func _character_has_emotion(character: Resource, emotion: String) -> bool:
	if character == null:
		return false
	if "sprites" in character and character.sprites is Dictionary and character.sprites.has(emotion):
		return true
	if "emotion_slots" in character and character.emotion_slots is Dictionary and character.emotion_slots.has(emotion):
		return true
	return false


func _character_has_outfit(character: Resource, outfit: String) -> bool:
	if character == null:
		return false
	if "available_outfits" in character and character.available_outfits is Array:
		for entry in character.available_outfits:
			if outfit == str(entry).strip_edges():
				return true
	if "default_outfit" in character and outfit == str(character.default_outfit).strip_edges():
		return true
	return false
