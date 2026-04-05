class_name ActivityBlockParser
extends RefCounted

## 通用块格式 DSL 解析器。
## 支持 [TAG] key=value [/TAG] 格式，适合 LLM 生成的文本协议。

static func parse_blocks(raw_text: String, tag: String) -> Array[Dictionary]:
	var cleaned: String = _strip_fences(raw_text)
	var open_tag: String = "[%s]" % tag.to_upper()
	var close_tag: String = "[/%s]" % tag.to_upper()

	var blocks: Array[Dictionary] = []
	var current: Dictionary = {}
	var in_block: bool = false

	for raw_line in cleaned.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.to_upper() == open_tag:
			current = {}
			in_block = true
			continue
		if line.to_upper() == close_tag:
			if in_block and not current.is_empty():
				blocks.append(current.duplicate(true))
			current = {}
			in_block = false
			continue
		if not in_block:
			continue

		var sep: int = line.find("=")
		if sep <= 0:
			continue

		var key: String = line.substr(0, sep).strip_edges()
		var value: String = line.substr(sep + 1).strip_edges()
		current[key] = _auto_parse_value(value)

	if in_block and not current.is_empty():
		blocks.append(current.duplicate(true))

	return blocks


static func parse_multi(raw_text: String, tags: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for tag in tags:
		result[tag] = parse_blocks(raw_text, tag)
	return result


static func load_blocks_from_file(path: String, tag: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		push_warning("ActivityBlockParser: file missing %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ActivityBlockParser: failed to open %s" % path)
		return []
	var text: String = file.get_as_text()
	file.close()
	return parse_blocks(text, tag)


static func _auto_parse_value(value: String) -> Variant:
	var normalized: String = value.strip_edges()
	if normalized.to_lower() == "true":
		return true
	if normalized.to_lower() == "false":
		return false
	if normalized.find("||") >= 0:
		return normalized
	if normalized.find("|") >= 0:
		return _parse_pipe_array(normalized)
	if normalized.is_valid_int():
		return int(normalized)
	if normalized.is_valid_float():
		return float(normalized)
	return normalized


static func _parse_pipe_array(value: String) -> Array:
	var parts: Array = []
	for raw_part in value.split("|"):
		var part: String = raw_part.strip_edges()
		if part.is_empty():
			continue
		if part.is_valid_int():
			parts.append(int(part))
		elif part.is_valid_float():
			parts.append(float(part))
		else:
			parts.append(part)
	return parts


static func _strip_fences(source: String) -> String:
	var s: String = source.strip_edges()
	if s.begins_with("```"):
		var first_nl: int = s.find("\n")
		if first_nl >= 0:
			s = s.substr(first_nl + 1)
		else:
			return ""
	if s.ends_with("```"):
		s = s.substr(0, s.length() - 3)
	return s.strip_edges()
