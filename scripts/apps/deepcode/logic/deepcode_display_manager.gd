extends RefCounted
class_name DeepCodeDisplayManager

## Block-based 消息显示管理器
## 管理 MessageItem 的创建和 block 的流式填充。
## 内置打字机效果：收到完整文本后逐字符输出。
## 注意：本类是 RefCounted，没有 _process。由外部 DeepCodeApp 驱动 tick 和 scroll。

# UI References
var _message_list: VBoxContainer
var _scroll_container: ScrollContainer

# State
var _current_message_item: MarginContainer
var _current_block: Node
var needs_scroll: bool = false

# 打字机状态
## 每秒输出字符数
var chars_per_second: float = 80.0
var _typewriter_buffer: Array = []  # [{type: "token"/"tag_open"/"tag_close", ...}]
var _typewriter_elapsed: float = 0.0
var _typewriter_active: bool = false
var _skip_requested: bool = false

const StreamParserScript = preload("res://scripts/apps/deepcode/logic/deepcode_stream_parser.gd")
var _parser: DeepCodeStreamParser

# Factory
const MessageItemScene = preload("res://scenes/apps/deepcode/components/message_item.tscn")
const ContentBlockScene = preload("res://scenes/apps/deepcode/components/content_block.tscn")
const ThinkingPanelScene = preload("res://scenes/apps/deepcode/components/thinking_panel.tscn")
const ToolStatusBlockScene = preload("res://scenes/apps/deepcode/components/tool_status_block.tscn")
const ImageBlockScene = preload("res://scenes/apps/deepcode/components/image_block.tscn")


func _init(message_list: VBoxContainer, scroll: ScrollContainer) -> void:
	_message_list = message_list
	_scroll_container = scroll

	_parser = StreamParserScript.new()
	_parser.token_received.connect(_on_token_parsed)
	_parser.tag_opened.connect(_on_tag_open_parsed)
	_parser.tag_closed.connect(_on_tag_close_parsed)


## 添加用户消息 block（立即显示，不走打字机）
func add_user_message(text: String) -> void:
	# 如果打字机正在输出，先跳过
	if _typewriter_active:
		skip_typewriter()
	_start_new_message("user")
	var block: Node = _create_block("text")
	block.set_content(text)
	_finalize_current_block()


## 开始一条新的 AI 消息（等待流式内容填充）
func start_ai_message() -> void:
	_start_new_message("assistant")


## 处理 AI 输出 — 先通过 parser 解析成 token/tag，缓存到 buffer，由 tick 逐字输出
func process_ai_chunk(chunk: String) -> void:
	_parser.parse_chunk(chunk)
	_typewriter_active = true
	_skip_requested = false


## 每帧由外部调用，驱动打字机输出。返回 true 表示仍在输出。
func tick(delta: float) -> bool:
	if not _typewriter_active or _typewriter_buffer.is_empty():
		if _typewriter_active and _typewriter_buffer.is_empty():
			_typewriter_active = false
		return false

	if _skip_requested:
		_flush_buffer()
		_typewriter_active = false
		_skip_requested = false
		return false

	_typewriter_elapsed += delta
	var chars_to_emit: int = int(_typewriter_elapsed * chars_per_second)
	if chars_to_emit <= 0:
		return true

	_typewriter_elapsed -= float(chars_to_emit) / chars_per_second

	var emitted: int = 0
	while emitted < chars_to_emit and not _typewriter_buffer.is_empty():
		var item: Dictionary = _typewriter_buffer[0]
		match item.get("type", ""):
			"token":
				# 输出一个字符
				_emit_token_char(item.get("text", ""))
				_typewriter_buffer.pop_front()
				emitted += 1
			"tag_open":
				# tag 事件立即处理，不消耗字符配额
				_execute_tag_open(item.get("tag_name", ""), item.get("attrs", {}))
				_typewriter_buffer.pop_front()
			"tag_close":
				_execute_tag_close(item.get("tag_name", ""))
				_typewriter_buffer.pop_front()

	needs_scroll = true
	return not _typewriter_buffer.is_empty()


## 跳过打字机，立即显示所有缓冲内容
func skip_typewriter() -> void:
	_skip_requested = true


## 是否正在打字输出
func is_typing() -> bool:
	return _typewriter_active


## 在当前 AI 消息中插入图片预览块
## 如果没有当前消息，会自动创建一条 AI 消息
func add_image_block(local_path: String, image_id: String = "", prompt_hint: String = "") -> void:
	if _current_message_item == null:
		_start_new_message("assistant")
	_finalize_current_block()
	var block: Node = _create_block("image")
	if block.has_method("load_image"):
		block.load_image(local_path, image_id, prompt_hint)
	_finalize_current_block()


## 重置所有内部状态（切换 session 时调用）
func reset() -> void:
	_current_message_item = null
	_current_block = null
	_typewriter_buffer.clear()
	_typewriter_active = false
	_skip_requested = false
	_typewriter_elapsed = 0.0
	needs_scroll = false
	_parser = StreamParserScript.new()
	_parser.token_received.connect(_on_token_parsed)
	_parser.tag_opened.connect(_on_tag_open_parsed)
	_parser.tag_closed.connect(_on_tag_close_parsed)


## 由外部在 _process 中调用，执行实际滚动
func do_scroll() -> void:
	if needs_scroll and _scroll_container:
		_scroll_container.scroll_vertical = int(_scroll_container.get_v_scroll_bar().max_value)
		needs_scroll = false


# --- Parser Callbacks (缓存到 buffer，不直接输出) ---

func _on_token_parsed(text: String) -> void:
	# 每个字符作为独立 token 入队（parser 已经是逐字符发的）
	_typewriter_buffer.append({"type": "token", "text": text})


func _on_tag_open_parsed(tag_name: String, attrs: Dictionary) -> void:
	_typewriter_buffer.append({"type": "tag_open", "tag_name": tag_name, "attrs": attrs})


func _on_tag_close_parsed(tag_name: String) -> void:
	_typewriter_buffer.append({"type": "tag_close", "tag_name": tag_name})


# --- 实际输出逻辑 ---

func _emit_token_char(text: String) -> void:
	if _current_block == null:
		_create_block("text")
	if _current_block.has_method("append_text"):
		_current_block.append_text(text)


func _execute_tag_open(tag_name: String, _attrs: Dictionary) -> void:
	match tag_name:
		"thinking":
			_finalize_current_block()
			_create_block("thinking")
		"tool_code":
			_finalize_current_block()
			var block: Node = _create_block("tool")
			block.set_status("running", "Preparing tool execution...")
		"tool_result":
			pass


func _execute_tag_close(tag_name: String) -> void:
	match tag_name:
		"thinking":
			_finalize_current_block()
		"tool_code":
			_finalize_current_block()


## 立即输出所有缓冲内容
func _flush_buffer() -> void:
	while not _typewriter_buffer.is_empty():
		var item: Dictionary = _typewriter_buffer.pop_front()
		match item.get("type", ""):
			"token":
				_emit_token_char(item.get("text", ""))
			"tag_open":
				_execute_tag_open(item.get("tag_name", ""), item.get("attrs", {}))
			"tag_close":
				_execute_tag_close(item.get("tag_name", ""))
	needs_scroll = true


# --- Internal ---

func _start_new_message(role: String) -> void:
	_current_message_item = MessageItemScene.instantiate()
	_message_list.add_child(_current_message_item)
	_current_message_item.set_author(role)
	_current_block = null
	needs_scroll = true


func _create_block(type: String) -> Node:
	var scene: PackedScene
	match type:
		"text": scene = ContentBlockScene
		"thinking": scene = ThinkingPanelScene
		"tool": scene = ToolStatusBlockScene
		"image": scene = ImageBlockScene
		_: scene = ContentBlockScene

	var block: Node = scene.instantiate()
	_current_message_item.add_block(block)
	_current_block = block
	needs_scroll = true
	return block


func _finalize_current_block() -> void:
	_current_block = null
