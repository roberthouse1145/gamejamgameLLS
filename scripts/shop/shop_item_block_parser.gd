class_name ShopItemBlockParser
extends RefCounted

const ActivityBlockParserClass = preload("res://scripts/activity/activity_block_parser.gd")

## 兼容旧接口，内部委托给通用 ActivityBlockParser。

static func parse_blocks(raw_text: String, tag: String) -> Array[Dictionary]:
	return ActivityBlockParserClass.parse_blocks(raw_text, tag)


static func parse_items(raw_text: String) -> Array[Dictionary]:
	return parse_blocks(raw_text, "ITEM")


static func parse_multi(raw_text: String, tags: PackedStringArray) -> Dictionary:
	return ActivityBlockParserClass.parse_multi(raw_text, tags)


static func load_blocks_from_file(path: String, tag: String) -> Array[Dictionary]:
	return ActivityBlockParserClass.load_blocks_from_file(path, tag)


static func load_multi_from_file(path: String, tags: PackedStringArray) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ShopItemBlockParser: file missing %s" % path)
		var empty: Dictionary = {}
		for tag in tags:
			empty[tag] = []
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ShopItemBlockParser: failed to open %s" % path)
		var empty: Dictionary = {}
		for tag in tags:
			empty[tag] = []
		return empty
	var text: String = file.get_as_text()
	file.close()
	return parse_multi(text, tags)
