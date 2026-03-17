extends RefCounted
class_name DeepCodeStreamParser

signal token_received(token: String)
signal tag_opened(tag_name: String, attributes: Dictionary)
signal tag_closed(tag_name: String)

## 已知标签白名单 — 不在此列表中的 <xxx> 当纯文本处理
const KNOWN_TAGS: Array[String] = ["thinking", "result", "error", "tool_call", "tool_code", "tool_result"]

# Buffer for partial tags
var _buffer: String = ""
var _in_tag_def: bool = false

# Regex for tag parsing
var _tag_open_regex: RegEx
var _tag_close_regex: RegEx

func _init() -> void:
	_tag_open_regex = RegEx.new()
	_tag_open_regex.compile("^<([a-zA-Z0-9_]+)([^>]*)>$")

	_tag_close_regex = RegEx.new()
	_tag_close_regex.compile("^</([a-zA-Z0-9_]+)>$")

func parse_chunk(chunk: String) -> void:
	if chunk.is_empty():
		return

	for i in range(chunk.length()):
		var character: String = chunk[i]
		_process_char(character)

func _process_char(character: String) -> void:
	if _in_tag_def:
		_buffer += character
		if character == ">":
			_in_tag_def = false
			_process_tag(_buffer)
			_buffer = ""
	else:
		if character == "<":
			_in_tag_def = true
			_buffer = "<"
		else:
			token_received.emit(character)

func _process_tag(tag_str: String) -> void:
	# Check close tag first
	var close_match: RegExMatch = _tag_close_regex.search(tag_str)
	if close_match:
		var tag_name: String = close_match.get_string(1)
		if tag_name in KNOWN_TAGS:
			tag_closed.emit(tag_name)
			return
		# 不认识的关闭标签当纯文本
		token_received.emit(tag_str)
		return

	# Check open tag
	var open_match: RegExMatch = _tag_open_regex.search(tag_str)
	if open_match:
		var tag_name: String = open_match.get_string(1)
		if tag_name in KNOWN_TAGS:
			var attr_str: String = open_match.get_string(2)
			var attrs: Dictionary = _parse_attributes(attr_str)
			tag_opened.emit(tag_name, attrs)
			return
		# 不认识的开放标签当纯文本
		token_received.emit(tag_str)
		return

	# If not a valid tag, emit as raw text
	token_received.emit(tag_str)

func _parse_attributes(_attr_str: String) -> Dictionary:
	# TODO: Implement robust attribute parsing if needed
	return {}
