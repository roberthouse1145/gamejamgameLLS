class_name LoreSystem extends RefCounted
## 按生成上下文选择并注入剧情事实与约束。Lore 文件只提供候选内容；
## 运行时按照显式元数据、关键词、优先级和预算确定最终注入项。

const LORE_INDEX_PATH: String = "res://resources/avg/lore/index.txt"
const MAX_TOTAL_COST: int = 640
const MAX_TOTAL_ENTRIES: int = 6
const MAX_FACT_ENTRIES: int = 2
const MAX_CONSTRAINT_ENTRIES: int = 4
const MAX_EXPANDED_ENTRIES: int = 2
const MAX_EXPANSION_COST: int = 140
const MAX_EXPANSION_DEPTH: int = 2
const ALLOWED_EXPANSION_RELATIONS: Dictionary = {
	"alias_of": true,
	"located_in": true,
	"near": true,
	"part_of": true,
	"related_to": true,
}

static var _entries_cache: Array[Dictionary] = []
static var _entry_map_cache: Dictionary = {}
static var _loaded_index_path: String = ""


static func resolve_avg_scene(session: Dictionary, pre_resolved_prompt: String = "") -> Dictionary:
	var scan_parts: PackedStringArray = []
	for key: String in [
		"title",
		"scene_prompt",
		"story_scene_prompt",
		"scene_brief",
		"prompt",
		"context",
		"setting_context",
		"constraints",
		"story_guidance_prompt",
	]:
		_append_scan_value(scan_parts, session.get(key, ""))
	if not pre_resolved_prompt.strip_edges().is_empty():
		scan_parts.append(pre_resolved_prompt.strip_edges())

	return resolve_context({
		"generation_type": "avg",
		"scan_text": "\n".join(scan_parts),
		"character_ids": session.get("character_ids", []),
	})


static func resolve_context(context: Dictionary, index_path: String = LORE_INDEX_PATH,
		force_reload: bool = false) -> Dictionary:
	_ensure_entries_loaded(index_path, force_reload)
	return resolve_entries(_entries_cache, context)


static func resolve_entries(raw_entries: Array, context: Dictionary) -> Dictionary:
	var entries: Array[Dictionary] = []
	var entry_map: Dictionary = {}
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = _normalize_entry_schema(raw_entry)
		var entry_id: String = str(entry.get("id", "")).strip_edges()
		if entry_id.is_empty():
			continue
		entries.append(entry)
		entry_map[entry_id] = entry
	return _resolve(entries, entry_map, context)


static func build_prompt_block(lines: Array) -> String:
	var parts: PackedStringArray = []
	for raw_line: Variant in lines:
		var line: String = str(raw_line).strip_edges()
		if not line.is_empty():
			parts.append("- %s" % line)
	return "\n".join(parts)


static func _resolve(entries: Array[Dictionary], entry_map: Dictionary,
		context: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var matched_ids: Array[String] = []
	var generation_type: String = str(context.get("generation_type", "")).strip_edges()
	var scan_text: String = str(context.get("scan_text", ""))

	for entry: Dictionary in entries:
		if not _matches_scope(entry, generation_type):
			continue
		if not _matches_filters(entry, context):
			continue
		var trigger: Dictionary = _evaluate_trigger(entry, scan_text)
		if not bool(trigger.get("matched", false)):
			continue
		var candidate: Dictionary = {
			"id": str(entry.get("id", "")),
			"entry": entry,
			"priority": int(entry.get("priority", 0)),
			"score": int(trigger.get("score", 0)),
			"group": str(entry.get("group", "")).strip_edges(),
			"cost": _get_entry_cost(entry),
			"kind": str(entry.get("kind", "fact")),
			"prompt": str(entry.get("prompt", "")).strip_edges(),
		}
		candidates.append(candidate)
		matched_ids.append(str(candidate.get("id", "")))

	candidates.sort_custom(_sort_candidates)
	var facts: Array[String] = []
	var constraints: Array[String] = []
	var selected_ids: Array[String] = []
	var selected_candidates: Array[Dictionary] = []
	var selected_groups: Dictionary = {}
	var skipped_by_group: Array[String] = []
	var skipped_by_budget: Array[String] = []
	var total_cost: int = 0

	for candidate: Dictionary in candidates:
		var candidate_id: String = str(candidate.get("id", ""))
		var group: String = str(candidate.get("group", ""))
		if not group.is_empty() and selected_groups.has(group):
			skipped_by_group.append(candidate_id)
			continue
		if selected_ids.size() >= MAX_TOTAL_ENTRIES:
			skipped_by_budget.append(candidate_id)
			continue
		var cost: int = int(candidate.get("cost", 0))
		if not selected_ids.is_empty() and total_cost + cost > MAX_TOTAL_COST:
			skipped_by_budget.append(candidate_id)
			continue
		var kind: String = str(candidate.get("kind", "fact"))
		if kind == "constraint" and constraints.size() >= MAX_CONSTRAINT_ENTRIES:
			skipped_by_budget.append(candidate_id)
			continue
		if kind != "constraint" and facts.size() >= MAX_FACT_ENTRIES:
			skipped_by_budget.append(candidate_id)
			continue
		var prompt: String = str(candidate.get("prompt", ""))
		if prompt.is_empty():
			continue
		if kind == "constraint":
			constraints.append(prompt)
		else:
			facts.append(prompt)
		selected_ids.append(candidate_id)
		selected_candidates.append(candidate)
		total_cost += cost
		if not group.is_empty():
			selected_groups[group] = true

	var expansion: Dictionary = _expand_candidates(
		selected_candidates,
		entry_map,
		context,
		selected_groups,
		total_cost,
		selected_ids.size(),
		matched_ids
	)
	var expanded_facts: Array[String] = []
	expanded_facts.assign(expansion.get("facts", []))
	facts.append_array(expanded_facts)
	var expanded_ids: Array[String] = []
	expanded_ids.assign(expansion.get("expanded_ids", []))
	var final_ids: Array[String] = selected_ids.duplicate()
	final_ids.append_array(expanded_ids)

	return {
		"facts": facts,
		"constraints": constraints,
		"matched_ids": final_ids,
		"seed_ids": selected_ids,
		"expanded_ids": expanded_ids,
		"skipped_by_group": skipped_by_group,
		"skipped_by_budget": skipped_by_budget,
	}


static func _expand_candidates(seed_candidates: Array[Dictionary], entry_map: Dictionary,
		context: Dictionary, selected_groups: Dictionary, current_cost: int,
		current_count: int, direct_matched_ids: Array[String]) -> Dictionary:
	var facts: Array[String] = []
	var expanded_ids: Array[String] = []
	var queued_ids: Dictionary = {}
	var direct_lookup: Dictionary = _build_id_lookup(direct_matched_ids)
	var queue: Array[Dictionary] = []
	var total_cost: int = current_cost
	var total_count: int = current_count
	var expansion_cost: int = 0

	for candidate: Dictionary in seed_candidates:
		var entry: Dictionary = candidate.get("entry", {})
		_enqueue_expansion_links(queue, queued_ids, entry, 1)

	var queue_index: int = 0
	while queue_index < queue.size():
		if expanded_ids.size() >= MAX_EXPANDED_ENTRIES or total_count >= MAX_TOTAL_ENTRIES + MAX_EXPANDED_ENTRIES:
			break
		var queued: Dictionary = queue[queue_index]
		queue_index += 1
		var target_id: String = str(queued.get("id", ""))
		if target_id.is_empty() or direct_lookup.has(target_id) or expanded_ids.has(target_id):
			continue
		var entry: Dictionary = entry_map.get(target_id, {})
		if entry.is_empty() or str(entry.get("kind", "fact")) == "constraint":
			continue
		if not _matches_scope(entry, str(context.get("generation_type", ""))):
			continue
		if not _matches_filters(entry, context):
			continue
		var group: String = str(entry.get("group", ""))
		if not group.is_empty() and selected_groups.has(group):
			continue
		var prompt: String = str(entry.get("prompt", "")).strip_edges()
		var cost: int = _get_entry_cost(entry)
		if prompt.is_empty() or total_cost + cost > MAX_TOTAL_COST or expansion_cost + cost > MAX_EXPANSION_COST:
			continue
		facts.append(prompt)
		expanded_ids.append(target_id)
		total_cost += cost
		total_count += 1
		expansion_cost += cost
		if not group.is_empty():
			selected_groups[group] = true
		var depth: int = int(queued.get("depth", 1))
		if depth < MAX_EXPANSION_DEPTH:
			_enqueue_expansion_links(queue, queued_ids, entry, depth + 1)

	return {"facts": facts, "expanded_ids": expanded_ids}


static func _enqueue_expansion_links(queue: Array[Dictionary], queued_ids: Dictionary,
		entry: Dictionary, depth: int) -> void:
	var links: Array[Dictionary] = []
	links.assign(entry.get("expands_to", []))
	for link: Dictionary in links:
		var target_id: String = str(link.get("id", "")).strip_edges()
		var relation: String = str(link.get("relation", "")).strip_edges().to_lower()
		if target_id.is_empty() or not ALLOWED_EXPANSION_RELATIONS.has(relation):
			continue
		var queue_key: String = "%s::%d" % [target_id, depth]
		if queued_ids.has(queue_key):
			continue
		queued_ids[queue_key] = true
		queue.append({"id": target_id, "depth": depth})


static func _ensure_entries_loaded(index_path: String, force_reload: bool) -> void:
	if not force_reload and _loaded_index_path == index_path:
		return
	_entries_cache.clear()
	_entry_map_cache.clear()
	_loaded_index_path = index_path
	for file_path: String in _read_index(index_path):
		for entry: Dictionary in _read_entry_file(file_path):
			var entry_id: String = str(entry.get("id", "")).strip_edges()
			if entry_id.is_empty():
				continue
			_entries_cache.append(entry)
			_entry_map_cache[entry_id] = entry


static func _read_index(index_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var file: FileAccess = FileAccess.open(index_path, FileAccess.READ)
	if file == null:
		push_warning("[LoreSystem] Failed to open lore index: %s" % index_path)
		return result
	for raw_line: String in file.get_as_text().split("\n", false):
		var line: String = raw_line.strip_edges()
		if not line.is_empty() and not line.begins_with("#"):
			result.append(line)
	file.close()
	return result


static func _read_entry_file(file_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[LoreSystem] Failed to open lore file: %s" % file_path)
		return result
	var text: String = file.get_as_text()
	file.close()
	if file_path.get_extension().to_lower() == "json":
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var raw_entries: Variant = parsed.get("entries", [])
			if raw_entries is Array:
				for raw_entry: Variant in raw_entries:
					if raw_entry is Dictionary:
						result.append(_normalize_entry_schema(raw_entry))
		return result
	for entry: Dictionary in _parse_lore_text(text, file_path):
		result.append(_normalize_entry_schema(entry))
	return result


static func _parse_lore_text(text: String, file_path: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var current: Dictionary = {}
	var prompt_lines: PackedStringArray = []
	var in_prompt: bool = false
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.trim_suffix("\r")
		var stripped: String = line.strip_edges()
		if current.is_empty() and (stripped.is_empty() or stripped.begins_with("#")):
			continue
		if stripped.begins_with("@lore "):
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
		var separator: int = line.find(":")
		if separator < 0:
			push_warning("[LoreSystem] Invalid metadata in %s: %s" % [file_path, line])
			continue
		_apply_metadata(current, line.substr(0, separator).strip_edges().to_lower(),
			line.substr(separator + 1).strip_edges())
	if not current.is_empty():
		current["prompt"] = "\n".join(prompt_lines).strip_edges()
		entries.append(current)
	return entries


static func _apply_metadata(entry: Dictionary, key: String, value: String) -> void:
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
			var parts: PackedStringArray = value.split("|", false)
			if parts.is_empty():
				return
			var links: Array = entry.get("expands_to", [])
			links.append({
				"id": str(parts[0]).strip_edges(),
				"relation": str(parts[1]).strip_edges().to_lower() if parts.size() > 1 else "related_to",
			})
			entry["expands_to"] = links
		_:
			entry[key] = value


static func _normalize_entry_schema(entry: Dictionary) -> Dictionary:
	var links: Array[Dictionary] = []
	var raw_links: Variant = entry.get("expands_to", [])
	if raw_links is Array:
		for raw_link: Variant in raw_links:
			if raw_link is Dictionary:
				var target_id: String = str(raw_link.get("id", "")).strip_edges()
				if not target_id.is_empty():
					links.append({
						"id": target_id,
						"relation": str(raw_link.get("relation", "related_to")).strip_edges().to_lower(),
					})
	return {
		"id": str(entry.get("id", "")).strip_edges(),
		"scope": _string_array(entry.get("scope", ["shared"])),
		"kind": str(entry.get("kind", "fact")).strip_edges().to_lower(),
		"priority": int(entry.get("priority", 0)),
		"group": str(entry.get("group", "")).strip_edges(),
		"always": bool(entry.get("always", false)),
		"keys": _string_array(entry.get("keys", [])),
		"when": str(entry.get("when", "")).strip_edges().to_lower(),
		"characters": _string_array(entry.get("characters", [])),
		"channels": _string_array(entry.get("channels", [])),
		"prompt": str(entry.get("prompt", "")).strip_edges(),
		"cost": int(entry.get("cost", 0)),
		"expands_to": links,
	}


static func _matches_scope(entry: Dictionary, generation_type: String) -> bool:
	var scopes: PackedStringArray = _string_array(entry.get("scope", []))
	return scopes.is_empty() or scopes.has("shared") or scopes.has(generation_type)


static func _matches_filters(entry: Dictionary, context: Dictionary) -> bool:
	var when: String = str(entry.get("when", ""))
	var has_topic: bool = bool(context.get("has_topic", false))
	if (when == "topic" and not has_topic) or (when == "no_topic" and has_topic):
		return false
	var wanted_channels: PackedStringArray = _string_array(entry.get("channels", []))
	var channel_id: String = str(context.get("channel_id", "")).strip_edges()
	if not wanted_channels.is_empty() and not wanted_channels.has(channel_id):
		return false
	var wanted_characters: PackedStringArray = _string_array(entry.get("characters", []))
	var context_characters: PackedStringArray = _string_array(context.get("character_ids", []))
	if not wanted_characters.is_empty() and not _shares_any(wanted_characters, context_characters):
		return false
	return true


static func _evaluate_trigger(entry: Dictionary, scan_text: String) -> Dictionary:
	if bool(entry.get("always", false)):
		return {"matched": true, "score": 1}
	var score: int = 0
	for key: String in _string_array(entry.get("keys", [])):
		if scan_text.to_lower().contains(key.to_lower()):
			score += 1
	return {"matched": score > 0, "score": score}


static func _sort_candidates(left: Dictionary, right: Dictionary) -> bool:
	var left_priority: int = int(left.get("priority", 0))
	var right_priority: int = int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	var left_score: int = int(left.get("score", 0))
	var right_score: int = int(right.get("score", 0))
	if left_score != right_score:
		return left_score > right_score
	return str(left.get("id", "")) < str(right.get("id", ""))


static func _get_entry_cost(entry: Dictionary) -> int:
	var explicit_cost: int = int(entry.get("cost", 0))
	if explicit_cost > 0:
		return explicit_cost
	return clampi(int(str(entry.get("prompt", "")).length() * 0.5), 40, 80)


static func _build_id_lookup(ids: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for id: String in ids:
		result[id] = true
	return result


static func _append_scan_value(parts: PackedStringArray, raw_value: Variant) -> void:
	if raw_value is Dictionary or raw_value is Array:
		var encoded: String = JSON.stringify(raw_value).strip_edges()
		if not encoded.is_empty():
			parts.append(encoded)
		return
	var value: String = str(raw_value).strip_edges()
	if not value.is_empty():
		parts.append(value)


static func _split_text_list(value: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for raw_part: String in value.split("|", false):
		var part: String = raw_part.strip_edges()
		if not part.is_empty():
			result.append(part)
	return result


static func _string_array(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if value is String:
		var single: String = value.strip_edges()
		if not single.is_empty():
			result.append(single)
		return result
	if value is PackedStringArray:
		return value
	if value is Array:
		for item: Variant in value:
			var text: String = str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	return result


static func _shares_any(left: PackedStringArray, right: PackedStringArray) -> bool:
	for item: String in left:
		if right.has(item):
			return true
	return false
