class_name LoreSystem
extends RefCounted

const LORE_INDEX_PATH := "res://resources/data/lore/index.txt"
const MAX_TOTAL_COST := 640
const MAX_TOTAL_ENTRIES := 6
const MAX_EXPANSION_DEPTH := 2
const MAX_EXPANDED_ENTRIES := 2
const MAX_EXPANSION_COST := 140
const MAX_FINAL_ENTRIES := MAX_TOTAL_ENTRIES + MAX_EXPANDED_ENTRIES
const CHAT_SCAN_MESSAGE_COUNT := 10
const ALLOWED_EXPANSION_RELATIONS := {
	"alias_of": true,
	"located_in": true,
	"near": true,
	"part_of": true,
	"studies_at": true,
}

static var _entries_cache: Array[Dictionary] = []
static var _entry_map_cache: Dictionary = {}
static var _cache_loaded := false


static func resolve_chat(
	channel: ChatChannel,
	npcs: Array,
	chat_history: Array[Dictionary],
	player_messages: Array[String],
	topic: ChatTopic,
	extra_scan_text: String = "",
) -> Dictionary:
	_ensure_entries_loaded(OS.has_feature("editor"))
	var scan := _build_chat_scan_text(chat_history, player_messages, topic)
	if not extra_scan_text.is_empty():
		scan += "\n" + extra_scan_text
	var context := {
		"generation_type": "chat",
		"channel_id": channel.channel_id if channel else "",
		"character_ids": _collect_npc_ids(npcs),
		"has_topic": topic != null,
		"topic_text": _build_topic_text(topic),
		"scan_text": scan,
	}
	return _resolve(context)


static func resolve_browser(url: String, design_prompt: String = "", page_context: String = "", extra_scan_text: String = "") -> Dictionary:
	_ensure_entries_loaded(OS.has_feature("editor"))
	var scan := _build_browser_scan_text(url, design_prompt, page_context)
	if not extra_scan_text.is_empty():
		scan += "\n" + extra_scan_text
	var context := {
		"generation_type": "browser",
		"channel_id": "",
		"character_ids": PackedStringArray(),
		"has_topic": false,
		"topic_text": "",
		"scan_text": scan,
	}
	return _resolve(context)


static func resolve_avg_scene(session: Dictionary, pre_resolved_prompt: String = "") -> Dictionary:
	_ensure_entries_loaded(OS.has_feature("editor"))
	var scan_text := _build_avg_scan_text(session)
	if not pre_resolved_prompt.is_empty():
		scan_text += "\n" + pre_resolved_prompt
	var context := {
		"generation_type": "avg",
		"channel_id": "",
		"character_ids": PackedStringArray(["npc_lin_xia"]),
		"has_topic": false,
		"topic_text": "",
		"scan_text": scan_text,
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
			"cost": _get_entry_cost(entry),
			"kind": _get_entry_kind(entry),
			"prompt": str(entry.get("prompt", "")).strip_edges(),
		}
		matched_candidates.append(candidate)
		matched_ids.append(candidate.id)

	matched_candidates.sort_custom(_sort_candidates)

	var matched_group_winners: Dictionary = {}
	var deduped_candidates: Array[Dictionary] = []
	var skipped_by_group: Array[String] = []
	for candidate in matched_candidates:
		var group := str(candidate.get("group", "")).strip_edges()
		if not group.is_empty() and matched_group_winners.has(group):
			skipped_by_group.append(str(candidate.get("id", "")))
			continue
		if not group.is_empty():
			matched_group_winners[group] = true
		deduped_candidates.append(candidate)

	var facts: Array[String] = []
	var constraints: Array[String] = []
	var seed_ids: Array[String] = []
	var skipped_by_budget: Array[String] = []
	var total_cost := 0
	var total_entries := 0
	var selected_candidates: Array[Dictionary] = []
	var selected_groups: Dictionary = {}
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
		var position := _get_insert_position(str(candidate.get("kind", "fact")))
		if _position_limit_reached(position_counts, position):
			skipped_by_budget.append(str(candidate.get("id", "")))
			continue

		var prompt := str(candidate.get("prompt", "")).strip_edges()
		if prompt.is_empty():
			continue

		if position == "lore_constraints":
			constraints.append(prompt)
		else:
			facts.append(prompt)
		position_counts[position] = int(position_counts.get(position, 0)) + 1
		total_cost += candidate_cost
		total_entries += 1
		var accepted_id := str(candidate.get("id", ""))
		seed_ids.append(accepted_id)
		selected_candidates.append(candidate)
		var accepted_group := str(candidate.get("group", "")).strip_edges()
		if not accepted_group.is_empty():
			selected_groups[accepted_group] = true

	var expansion_result := _expand_candidates(
		selected_candidates,
		context,
		selected_groups,
		position_counts,
		total_cost,
		total_entries,
		matched_ids
	)
	facts.append_array(expansion_result.get("facts", []))
	constraints.append_array(expansion_result.get("constraints", []))
	var expanded_ids: Array[String] = expansion_result.get("expanded_ids", [])
	var final_ids: Array[String] = seed_ids.duplicate()
	final_ids.append_array(expanded_ids)

	print(
		"[LoreSystem] type=%s matched=%s skipped_group=%s skipped_budget=%s seed=%s expanded=%s final=%s facts=%d constraints=%d" % [
			str(context.get("generation_type", "")),
			matched_ids,
			skipped_by_group,
			skipped_by_budget,
			seed_ids,
			expanded_ids,
			final_ids,
			facts.size(),
			constraints.size(),
		]
	)

	return {
		"facts": facts,
		"constraints": constraints,
		"matched_ids": final_ids,
		"seed_ids": seed_ids,
		"expanded_ids": expanded_ids,
	}


static func _expand_candidates(
	seed_candidates: Array[Dictionary],
	context: Dictionary,
	selected_groups: Dictionary,
	position_counts: Dictionary,
	current_total_cost: int,
	current_total_entries: int,
	direct_matched_ids: Array[String],
) -> Dictionary:
	var result_facts: Array[String] = []
	var result_constraints: Array[String] = []
	var expanded_ids: Array[String] = []
	var total_cost := current_total_cost
	var total_entries := current_total_entries
	var expansion_cost := 0
	var expansion_entries := 0
	var queued_ids: Dictionary = {}
	var direct_match_lookup := _build_id_lookup(direct_matched_ids)
	var queue: Array[Dictionary] = []

	for seed_candidate in seed_candidates:
		_enqueue_expansion_links(
			queue,
			queued_ids,
			seed_candidate.get("entry", {}),
			1
		)

	var queue_index := 0
	while queue_index < queue.size():
		if expansion_entries >= MAX_EXPANDED_ENTRIES:
			break
		if total_entries >= MAX_FINAL_ENTRIES:
			break
		var queued := queue[queue_index]
		queue_index += 1

		var target_id := str(queued.get("id", "")).strip_edges()
		if target_id.is_empty():
			continue
		if direct_match_lookup.has(target_id):
			continue
		if expanded_ids.has(target_id):
			continue

		var entry: Dictionary = _entry_map_cache.get(target_id, {})
		if entry.is_empty():
			continue
		if not _matches_scope(entry, str(context.get("generation_type", ""))):
			continue
		if not _matches_filters(entry, context):
			continue

		var position := _get_insert_position(_get_entry_kind(entry))
		if position != "lore_facts":
			continue

		var group := str(entry.get("group", "")).strip_edges()
		if not group.is_empty() and selected_groups.has(group):
			continue

		var prompt := str(entry.get("prompt", "")).strip_edges()
		if prompt.is_empty():
			continue

		var candidate_cost := _get_entry_cost(entry)
		if total_cost + candidate_cost > MAX_TOTAL_COST:
			continue
		if expansion_cost + candidate_cost > MAX_EXPANSION_COST:
			continue

		result_facts.append(prompt)
		position_counts[position] = int(position_counts.get(position, 0)) + 1
		total_cost += candidate_cost
		total_entries += 1
		expansion_cost += candidate_cost
		expansion_entries += 1
		expanded_ids.append(target_id)
		if not group.is_empty():
			selected_groups[group] = true

		var depth := int(queued.get("depth", 1))
		if depth < MAX_EXPANSION_DEPTH:
			_enqueue_expansion_links(queue, queued_ids, entry, depth + 1)

	return {
		"facts": result_facts,
		"constraints": result_constraints,
		"expanded_ids": expanded_ids,
	}


static func _enqueue_expansion_links(
	queue: Array[Dictionary],
	queued_ids: Dictionary,
	entry: Dictionary,
	depth: int,
) -> void:
	var links := _get_expansion_links(entry)
	for link in links:
		var target_id := str(link.get("id", "")).strip_edges()
		if target_id.is_empty():
			continue
		var relation := str(link.get("relation", "")).strip_edges().to_lower()
		if not ALLOWED_EXPANSION_RELATIONS.has(relation):
			continue
		var queue_key := "%s::%d" % [target_id, depth]
		if queued_ids.has(queue_key):
			continue
		queued_ids[queue_key] = true
		queue.append({
			"id": target_id,
			"depth": depth,
			"relation": relation,
		})


static func _get_expansion_links(entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_links: Variant = entry.get("expands_to", [])
	if not raw_links is Array:
		return result
	for raw_link in raw_links:
		if raw_link is Dictionary:
			var link := (raw_link as Dictionary).duplicate(true)
			var target_id := str(link.get("id", "")).strip_edges()
			if target_id.is_empty():
				continue
			link["id"] = target_id
			link["relation"] = str(link.get("relation", "")).strip_edges().to_lower()
			result.append(link)
			continue
		var raw_target_id := str(raw_link).strip_edges()
		if raw_target_id.is_empty():
			continue
		result.append({
			"id": raw_target_id,
			"relation": "",
		})
	return result


static func _build_id_lookup(ids: Array[String]) -> Dictionary:
	var lookup: Dictionary = {}
	for id in ids:
		var normalized_id := str(id).strip_edges()
		if normalized_id.is_empty():
			continue
		lookup[normalized_id] = true
	return lookup


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
	var has_topic := bool(context.get("has_topic", false))
	var when := str(entry.get("when", "")).strip_edges().to_lower()
	if when == "topic" and not has_topic:
		return false
	if when == "no_topic" and has_topic:
		return false

	var channel_ids := _string_array(entry.get("channels", []))
	var channel_id := str(context.get("channel_id", "")).strip_edges()
	if not channel_ids.is_empty() and not channel_id.is_empty() and not channel_ids.has(channel_id):
		return false
	if not channel_ids.is_empty() and channel_id.is_empty():
		return false

	var entry_character_ids := _string_array(entry.get("characters", []))
	var context_character_ids: PackedStringArray = context.get("character_ids", PackedStringArray())
	if not entry_character_ids.is_empty() and not _shares_any(entry_character_ids, context_character_ids):
		return false

	return true


static func _evaluate_trigger(entry: Dictionary, scan_text: String) -> Dictionary:
	if bool(entry.get("always", false)):
		return {"matched": true, "score": 1}

	var keys := _string_array(entry.get("keys", []))
	if keys.is_empty():
		return {"matched": false, "score": 0}

	var score := 0
	for key in keys:
		if _matches_key(key, scan_text):
			score += 1
	if score <= 0:
		return {"matched": false, "score": 0}
	return {"matched": true, "score": score}


static func _matches_key(key: String, scan_text: String) -> bool:
	var normalized_key := key.strip_edges()
	if normalized_key.is_empty():
		return false
	return scan_text.to_lower().contains(normalized_key.to_lower())


static func _get_entry_kind(entry: Dictionary) -> String:
	return str(entry.get("kind", "fact")).strip_edges().to_lower()


static func _get_insert_position(kind: String) -> String:
	if kind == "constraint":
		return "lore_constraints"
	return "lore_facts"


static func _get_entry_cost(entry: Dictionary) -> int:
	var cost := int(entry.get("cost", 0))
	if cost > 0:
		return cost
	var text_length := str(entry.get("prompt", "")).length()
	var estimated_cost: int = max(40, int(text_length * 0.5))
	return int(min(80, estimated_cost))


static func _position_limit_reached(position_counts: Dictionary, position: String) -> bool:
	if position == "lore_constraints":
		return int(position_counts.get(position, 0)) >= 4
	return int(position_counts.get(position, 0)) >= 2


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


static func _build_avg_scan_text(session: Dictionary) -> String:
	var parts: Array[String] = []
	var location: Dictionary = session.get("location", {})
	for key in ["title", "subtitle", "description", "detail_prompt"]:
		var value := str(location.get(key, "")).strip_edges()
		if not value.is_empty():
			parts.append(value)
	var variant := str(session.get("activity_variant", "")).strip_edges()
	if not variant.is_empty():
		parts.append(variant)
	var seed_text := str(session.get("event_seed", "")).strip_edges()
	if not seed_text.is_empty():
		parts.append(seed_text)
	return "\n".join(parts)


static func _ensure_entries_loaded(force_reload: bool = false) -> void:
	if _cache_loaded and not force_reload:
		return
	_entries_cache.clear()
	_entry_map_cache.clear()
	_load_entries_from_index(LORE_INDEX_PATH)
	_cache_loaded = true


static func _load_entries_from_index(index_path: String) -> void:
	var file := FileAccess.open(index_path, FileAccess.READ)
	if file == null:
		push_warning("[LoreSystem] Failed to open lore index: %s" % index_path)
		return
	var text := file.get_as_text()
	file.close()
	var files := PackedStringArray()
	if index_path.get_extension().to_lower() == "txt":
		files = _parse_index_text(text)
	else:
		var parsed: Variant = JSON.parse_string(text)
		if parsed == null or not parsed is Dictionary:
			push_warning("[LoreSystem] Failed to parse lore index: %s" % index_path)
			return
		files = _string_array(parsed.get("files", []))
	for file_path in files:
		_load_entry_file(file_path)


static func _load_entry_file(file_path: String) -> void:
	if file_path.get_extension().to_lower() == "txt":
		_load_entry_text_file(file_path)
		return
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
		var normalized: Dictionary = _normalize_entry_schema(entry as Dictionary)
		if str(normalized.get("id", "")).strip_edges().is_empty():
			normalized["id"] = "%s::%d" % [file_path.get_file(), _entries_cache.size()]
		var normalized_id := str(normalized.get("id", "")).strip_edges()
		normalized["id"] = normalized_id
		_entries_cache.append(normalized)
		_entry_map_cache[normalized_id] = normalized


static func _load_entry_text_file(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[LoreSystem] Failed to open lore file: %s" % file_path)
		return
	var text := file.get_as_text()
	file.close()
	var entries := _parse_lore_text(text, file_path)
	for entry in entries:
		var normalized: Dictionary = _normalize_entry_schema(entry)
		var normalized_id := str(normalized.get("id", "")).strip_edges()
		if normalized_id.is_empty():
			continue
		normalized["id"] = normalized_id
		_entries_cache.append(normalized)
		_entry_map_cache[normalized_id] = normalized


static func _normalize_entry_schema(entry: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	normalized["id"] = str(entry.get("id", "")).strip_edges()
	normalized["scope"] = _string_array(entry.get("scope", ["shared"]))
	normalized["kind"] = _get_entry_kind(entry)
	normalized["priority"] = int(entry.get("priority", 0))
	normalized["group"] = str(entry.get("group", "")).strip_edges()
	normalized["always"] = bool(entry.get("always", false))
	normalized["keys"] = _string_array(entry.get("keys", []))
	normalized["when"] = str(entry.get("when", "")).strip_edges().to_lower()
	normalized["characters"] = _string_array(entry.get("characters", []))
	normalized["channels"] = _string_array(entry.get("channels", []))
	normalized["prompt"] = str(entry.get("prompt", "")).strip_edges()
	normalized["cost"] = int(entry.get("cost", 0))
	normalized["expands_to"] = _get_expansion_links(entry)
	return normalized


static func _parse_index_text(text: String) -> PackedStringArray:
	var files := PackedStringArray()
	for raw_line in text.split("\n", false):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			continue
		files.append(line)
	return files


static func _parse_lore_text(text: String, file_path: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var lines := text.split("\n", false)
	var current: Dictionary = {}
	var prompt_lines: Array[String] = []
	var in_prompt := false

	for raw_line in lines:
		var line := raw_line.trim_suffix("\r")
		var stripped := line.strip_edges()

		if not in_prompt and stripped.begins_with("#"):
			continue

		if stripped.begins_with("@lore "):
			if not current.is_empty():
				push_warning("[LoreSystem] Encountered nested @lore before @end in %s" % file_path)
			current = {"id": stripped.trim_prefix("@lore ").strip_edges()}
			prompt_lines.clear()
			in_prompt = false
			continue

		if current.is_empty():
			continue

		if stripped == "@end":
			current["prompt"] = "\n".join(prompt_lines).strip_edges()
			entries.append(current.duplicate(true))
			current.clear()
			prompt_lines.clear()
			in_prompt = false
			continue

		if in_prompt:
			prompt_lines.append(line)
			continue

		if stripped.is_empty():
			in_prompt = true
			continue

		var separator := line.find(":")
		if separator < 0:
			push_warning("[LoreSystem] Invalid lore metadata line in %s: %s" % [file_path, line])
			continue
		var key := line.substr(0, separator).strip_edges().to_lower()
		var value := line.substr(separator + 1).strip_edges()
		_apply_lore_text_metadata(current, key, value)

	if not current.is_empty():
		current["prompt"] = "\n".join(prompt_lines).strip_edges()
		entries.append(current.duplicate(true))

	return entries


static func _apply_lore_text_metadata(entry: Dictionary, key: String, value: String) -> void:
	match key:
		"scope", "keys", "characters", "channels":
			entry[key] = _split_text_list(value)
		"kind", "group", "when":
			entry[key] = value.to_lower()
		"priority", "cost":
			entry[key] = int(value)
		"always":
			entry[key] = value.to_lower() in ["1", "true", "yes"]
		"expand":
			var parts := value.split("|", false)
			if parts.is_empty():
				return
			var target_id := str(parts[0]).strip_edges()
			if target_id.is_empty():
				return
			var link: Dictionary = {"id": target_id}
			if parts.size() > 1:
				var relation := str(parts[1]).strip_edges().to_lower()
				if not relation.is_empty():
					link["relation"] = relation
			if not entry.has("expands_to"):
				entry["expands_to"] = []
			var links: Array = entry.get("expands_to", [])
			links.append(link)
			entry["expands_to"] = links
		_:
			entry[key] = value


static func _split_text_list(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_part in value.split("|", false):
		var part := raw_part.strip_edges()
		if not part.is_empty():
			result.append(part)
	return result


static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is String:
		var single := str(value).strip_edges()
		if not single.is_empty():
			result.append(single)
		return result
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
