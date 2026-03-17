class_name LoreSystem
extends RefCounted

const LORE_INDEX_PATH := "res://resources/data/lore/index.json"
const MAX_TOTAL_COST := 640
const MAX_TOTAL_ENTRIES := 6
const CHAT_SCAN_MESSAGE_COUNT := 10

static var _entries_cache: Array[Dictionary] = []
static var _cache_loaded := false


static func resolve_chat(
	channel: ChatChannel,
	npcs: Array,
	chat_history: Array[Dictionary],
	player_messages: Array[String],
	topic: ChatTopic,
) -> Dictionary:
	_ensure_entries_loaded(OS.has_feature("editor"))
	var context := {
		"generation_type": "chat",
		"channel_id": channel.channel_id if channel else "",
		"character_ids": _collect_npc_ids(npcs),
		"has_topic": topic != null,
		"topic_text": _build_topic_text(topic),
		"scan_text": _build_chat_scan_text(chat_history, player_messages, topic),
	}
	return _resolve(context)


static func resolve_browser(url: String, design_prompt: String = "", page_context: String = "") -> Dictionary:
	_ensure_entries_loaded(OS.has_feature("editor"))
	var context := {
		"generation_type": "browser",
		"channel_id": "",
		"character_ids": PackedStringArray(),
		"has_topic": false,
		"topic_text": "",
		"scan_text": _build_browser_scan_text(url, design_prompt, page_context),
	}
	return _resolve(context)


static func build_prompt_block(lines: Array) -> String:
	var parts: Array[String] = []
	for line in lines:
		var text := str(line).strip_edges()
		if text.is_empty():
			continue
		parts.append("- %s" % text)
	return "\n".join(parts)


static func _resolve(context: Dictionary) -> Dictionary:
	var matched_candidates: Array[Dictionary] = []
	var matched_ids: Array[String] = []

	for entry in _entries_cache:
		if not _matches_scope(entry, str(context.get("generation_type", ""))):
			continue
		if not _matches_filters(entry, context):
			continue
		var trigger_result := _evaluate_trigger(entry, str(context.get("scan_text", "")))
		if not bool(trigger_result.get("matched", false)):
			continue
		var candidate := {
			"id": str(entry.get("id", "")).strip_edges(),
			"entry": entry,
			"priority": int(entry.get("priority", 0)),
			"score": int(trigger_result.get("score", 0)),
			"group": str(entry.get("group", "")).strip_edges(),
			"position": _get_insert_position(entry),
			"cost": _get_entry_cost(entry),
			"content": str(entry.get("content", "")).strip_edges(),
		}
		matched_candidates.append(candidate)
		matched_ids.append(candidate.id)

	matched_candidates.sort_custom(_sort_candidates)

	var group_winners: Dictionary = {}
	var deduped_candidates: Array[Dictionary] = []
	var skipped_by_group: Array[String] = []
	for candidate in matched_candidates:
		var group := str(candidate.get("group", "")).strip_edges()
		if not group.is_empty() and group_winners.has(group):
			skipped_by_group.append(str(candidate.get("id", "")))
			continue
		if not group.is_empty():
			group_winners[group] = true
		deduped_candidates.append(candidate)

	var facts: Array[String] = []
	var constraints: Array[String] = []
	var final_ids: Array[String] = []
	var skipped_by_budget: Array[String] = []
	var total_cost := 0
	var total_entries := 0
	var position_counts := {
		"lore_facts": 0,
		"lore_constraints": 0,
	}

	for candidate in deduped_candidates:
		if total_entries >= MAX_TOTAL_ENTRIES:
			skipped_by_budget.append(str(candidate.get("id", "")))
			continue
		var candidate_cost := int(candidate.get("cost", 0))
		if total_entries > 0 and total_cost + candidate_cost > MAX_TOTAL_COST:
			skipped_by_budget.append(str(candidate.get("id", "")))
			continue
		var entry: Dictionary = candidate.get("entry", {})
		var budget: Dictionary = entry.get("budget", {})
		var position := str(candidate.get("position", "lore_facts"))
		var max_scope_count := int(budget.get("max_scope_count", 0))
		if max_scope_count > 0 and int(position_counts.get(position, 0)) >= max_scope_count:
			skipped_by_budget.append(str(candidate.get("id", "")))
			continue

		var content := str(candidate.get("content", "")).strip_edges()
		if content.is_empty():
			continue

		if position == "lore_constraints":
			constraints.append(content)
		else:
			facts.append(content)
		position_counts[position] = int(position_counts.get(position, 0)) + 1
		total_cost += candidate_cost
		total_entries += 1
		final_ids.append(str(candidate.get("id", "")))

	print(
		"[LoreSystem] type=%s matched=%s skipped_group=%s skipped_budget=%s final=%s facts=%d constraints=%d" % [
			str(context.get("generation_type", "")),
			matched_ids,
			skipped_by_group,
			skipped_by_budget,
			final_ids,
			facts.size(),
			constraints.size(),
		]
	)

	return {
		"facts": facts,
		"constraints": constraints,
		"matched_ids": final_ids,
	}


static func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var a_priority := int(a.get("priority", 0))
	var b_priority := int(b.get("priority", 0))
	if a_priority != b_priority:
		return a_priority > b_priority
	var a_score := int(a.get("score", 0))
	var b_score := int(b.get("score", 0))
	if a_score != b_score:
		return a_score > b_score
	return str(a.get("id", "")) < str(b.get("id", ""))


static func _matches_scope(entry: Dictionary, generation_type: String) -> bool:
	var scopes := _string_array(entry.get("scope", []))
	if scopes.is_empty():
		return true
	return scopes.has(generation_type) or scopes.has("shared")


static func _matches_filters(entry: Dictionary, context: Dictionary) -> bool:
	var filters: Dictionary = entry.get("filters", {})
	var has_topic := bool(context.get("has_topic", false))
	if bool(filters.get("requires_topic", false)) and not has_topic:
		return false
	if bool(filters.get("requires_no_topic", false)) and has_topic:
		return false

	var channel_ids := _string_array(filters.get("channel_ids", []))
	var channel_id := str(context.get("channel_id", "")).strip_edges()
	if not channel_ids.is_empty() and not channel_id.is_empty() and not channel_ids.has(channel_id):
		return false
	if not channel_ids.is_empty() and channel_id.is_empty():
		return false

	var entry_character_ids := _string_array(filters.get("character_ids", []))
	var context_character_ids: PackedStringArray = context.get("character_ids", PackedStringArray())
	if not entry_character_ids.is_empty() and not _shares_any(entry_character_ids, context_character_ids):
		return false

	return true


static func _evaluate_trigger(entry: Dictionary, scan_text: String) -> Dictionary:
	var trigger: Dictionary = entry.get("trigger", {})
	var mode := str(trigger.get("mode", "any")).to_lower()
	var keys := _string_array(trigger.get("keys", []))
	var matched := false
	var score := 0

	match mode:
		"always":
			matched = true
			score = 1
		"all":
			if not keys.is_empty():
				matched = true
				for key in keys:
					if not _matches_key(key, scan_text):
						matched = false
						break
					score += 1
		"regex":
			for key in keys:
				if _matches_regex_key(key, scan_text):
					matched = true
					score += 1
		"any", _:
			for key in keys:
				if _matches_key(key, scan_text):
					matched = true
					score += 1

	if not matched:
		return {"matched": false, "score": 0}

	var secondary_mode := str(trigger.get("secondary_mode", "none")).to_lower()
	var secondary_keys := _string_array(trigger.get("secondary_keys", []))
	if not _matches_secondary(secondary_mode, secondary_keys, scan_text):
		return {"matched": false, "score": 0}

	return {"matched": true, "score": score}


static func _matches_secondary(mode: String, keys: PackedStringArray, scan_text: String) -> bool:
	match mode:
		"none", "":
			return true
		"and_any":
			for key in keys:
				if _matches_key(key, scan_text):
					return true
			return false
		"and_all":
			if keys.is_empty():
				return true
			for key in keys:
				if not _matches_key(key, scan_text):
					return false
			return true
		"not_any":
			for key in keys:
				if _matches_key(key, scan_text):
					return false
			return true
		_:
			return true


static func _matches_key(key: String, scan_text: String) -> bool:
	var normalized_key := key.strip_edges()
	if normalized_key.is_empty():
		return false
	return scan_text.to_lower().contains(normalized_key.to_lower())


static func _matches_regex_key(key: String, scan_text: String) -> bool:
	var pattern := key.strip_edges()
	if pattern.is_empty():
		return false
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		push_warning("[LoreSystem] Invalid regex key: %s" % pattern)
		return false
	return regex.search(scan_text) != null


static func _get_insert_position(entry: Dictionary) -> String:
	var explicit := str(entry.get("insert_position", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var behavior: Dictionary = entry.get("behavior", {})
	if str(behavior.get("kind", "fact")).to_lower() == "constraint":
		return "lore_constraints"
	return "lore_facts"


static func _get_entry_cost(entry: Dictionary) -> int:
	var budget: Dictionary = entry.get("budget", {})
	var cost := int(budget.get("cost", 0))
	if cost > 0:
		return cost
	return max(40, str(entry.get("content", "")).length())


static func _collect_npc_ids(npcs: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for npc in npcs:
		if npc == null:
			continue
		var character_id := str(npc.character_id).strip_edges()
		if not character_id.is_empty():
			ids.append(character_id)
	return ids


static func _build_topic_text(topic: ChatTopic) -> String:
	if topic == null:
		return ""
	var parts: Array[String] = []
	var system_prompt := str(topic.system_prompt).strip_edges()
	if not system_prompt.is_empty():
		parts.append(system_prompt)
	var goal_description := str(topic.goal_description).strip_edges()
	if not goal_description.is_empty():
		parts.append(goal_description)
	return "\n".join(parts)


static func _build_chat_scan_text(
	chat_history: Array[Dictionary],
	player_messages: Array[String],
	topic: ChatTopic,
) -> String:
	var parts: Array[String] = []
	for msg in player_messages:
		var text := str(msg).strip_edges()
		if not text.is_empty():
			parts.append(text)

	for msg in chat_history.slice(-CHAT_SCAN_MESSAGE_COUNT):
		if not msg is Dictionary:
			continue
		var sender := str(msg.get("sender_name", "")).strip_edges()
		var content := str(msg.get("content", "")).strip_edges()
		var line := "%s %s" % [sender, content]
		if msg.has("card") and msg["card"] is Dictionary:
			var card: Dictionary = msg["card"]
			var hint := str(card.get("hint", "")).strip_edges()
			if not hint.is_empty():
				line += " " + hint
		parts.append(line.strip_edges())

	var topic_text := _build_topic_text(topic)
	if not topic_text.is_empty():
		parts.append(topic_text)

	return "\n".join(parts)


static func _build_browser_scan_text(url: String, design_prompt: String, page_context: String) -> String:
	var parts: Array[String] = []
	for text in [url, page_context, design_prompt]:
		var value := str(text).strip_edges()
		if not value.is_empty():
			parts.append(value)
	return "\n".join(parts)


static func _ensure_entries_loaded(force_reload: bool = false) -> void:
	if _cache_loaded and not force_reload:
		return
	_entries_cache.clear()
	_load_entries_from_index(LORE_INDEX_PATH)
	_cache_loaded = true


static func _load_entries_from_index(index_path: String) -> void:
	var file := FileAccess.open(index_path, FileAccess.READ)
	if file == null:
		push_warning("[LoreSystem] Failed to open lore index: %s" % index_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not parsed is Dictionary:
		push_warning("[LoreSystem] Failed to parse lore index: %s" % index_path)
		return
	var files := _string_array(parsed.get("files", []))
	for file_path in files:
		_load_entry_file(file_path)


static func _load_entry_file(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[LoreSystem] Failed to open lore file: %s" % file_path)
		return
	var json_str := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null or not parsed is Dictionary:
		push_warning("[LoreSystem] Failed to parse lore file: %s" % file_path)
		return
	var entries: Array = parsed.get("entries", [])
	for entry in entries:
		if not entry is Dictionary:
			continue
		if not bool(entry.get("enabled", true)):
			continue
		var normalized: Dictionary = (entry as Dictionary).duplicate(true)
		if str(normalized.get("id", "")).strip_edges().is_empty():
			normalized["id"] = "%s::%d" % [file_path.get_file(), _entries_cache.size()]
		_entries_cache.append(normalized)


static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is PackedStringArray:
		return value
	if not value is Array:
		return result
	for item in value:
		var text := str(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


static func _shares_any(left: PackedStringArray, right: PackedStringArray) -> bool:
	for item in left:
		if right.has(item):
			return true
	return false
