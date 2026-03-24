class_name ShopItemBlockParser
extends RefCounted

## 通用块式 DSL 解析器。
## 支持 [TAG] key=value [/TAG] 格式，TAG 可以是任意名称。
## 竖线 | 分隔的值会被解析为数组。
## 用于商店商品（LLM 输出）、效果定义、蓝图、核心商品等。

## 解析指定标签的所有块
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
		current[key] = _auto_parse_value(key, value)

	if in_block and not current.is_empty():
		blocks.append(current.duplicate(true))

	return blocks


## 兼容旧接口：解析 [ITEM] 块
static func parse_items(raw_text: String) -> Array[Dictionary]:
	return parse_blocks(raw_text, "ITEM")


## 解析多种标签，返回 { "TAG": [blocks], ... }
static func parse_multi(raw_text: String, tags: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for tag in tags:
		result[tag] = parse_blocks(raw_text, tag)
	return result


## 从文件路径加载并解析指定标签
static func load_blocks_from_file(path: String, tag: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		push_warning("ShopItemBlockParser: 文件不存在 %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ShopItemBlockParser: 无法打开 %s" % path)
		return []
	var text: String = file.get_as_text()
	return parse_blocks(text, tag)


## 从文件路径加载并解析多种标签
static func load_multi_from_file(path: String, tags: PackedStringArray) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ShopItemBlockParser: 文件不存在 %s" % path)
		var empty: Dictionary = {}
		for tag in tags:
			empty[tag] = []
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ShopItemBlockParser: 无法打开 %s" % path)
		var empty: Dictionary = {}
		for tag in tags:
			empty[tag] = []
		return empty
	var text: String = file.get_as_text()
	return parse_multi(text, tags)


# ── 内部工具 ──────────────────────────────────────────

## 自动类型推断
static func _auto_parse_value(_key: String, value: String) -> Variant:
	# 布尔
	if value.to_lower() == "true":
		return true
	if value.to_lower() == "false":
		return false

	# 包含 || 的值保留为原始字符串（由上层按需解析分组）
	if value.find("||") >= 0:
		return value

	# 竖线分隔 → 数组
	if value.find("|") >= 0:
		return _parse_pipe_array(value)

	# 纯整数
	if value.is_valid_int():
		return int(value)

	# 纯浮点
	if value.is_valid_float():
		return float(value)

	return value


## 竖线分隔值解析为数组（支持嵌套键值对）
static func _parse_pipe_array(value: String) -> Array:
	var parts: Array = []
	for raw_part in value.split("|"):
		var part: String = raw_part.strip_edges()
		if part.is_empty():
			continue
		# 检查是否是 key:value 对（用于 instant_stats 等）
		if part.find(":") >= 0 and not part.begins_with("#"):
			parts.append(part)
		elif part.is_valid_int():
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
