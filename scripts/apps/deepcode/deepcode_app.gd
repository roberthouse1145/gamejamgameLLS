class_name DeepCodeApp extends Control
## DeepCode — AI-powered scene creation assistant
## Session-based chat with sidebar, input locking during AI response.

# Node references
@onready var message_list: VBoxContainer = %MessageList
@onready var input_field: LineEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var chat_agent: ChatAgent = $ChatAgent
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var session_sidebar: PanelContainer = %SessionSidebar
@onready var debug_panel: PanelContainer = %DebugPanel

# Logic
const DisplayManagerScript = preload("res://scripts/apps/deepcode/logic/deepcode_display_manager.gd")
var _display_manager: DeepCodeDisplayManager

# Session state: session_id -> {messages: Array}
var _session_cache: Dictionary = {}
var _active_session_id: String = ""
var _input_locked: bool = false


func _ready() -> void:
	_apply_theme()
	_setup_connections()
	_setup_agent()

	if message_list and message_scroll:
		_display_manager = DisplayManagerScript.new(message_list, message_scroll)
	else:
		push_error("DeepCodeApp: Missing MessageList or MessageScroll nodes.")

	# 创建初始 session
	if session_sidebar:
		session_sidebar.create_session()


func _process(delta: float) -> void:
	if _display_manager == null:
		return
	if _display_manager.is_typing():
		_display_manager.tick(delta)
	if _display_manager.needs_scroll:
		_display_manager.do_scroll()


# ============ Theme ============

func _apply_theme() -> void:
	# input_field 和 send_button 的样式由 deepcode_dark.tres Theme 提供
	# font_size=15 (input) 与 Theme LineEdit font_size=15 一致，可删
	# font_size=14 (button) 与 Theme Button font_size=14 一致，可删
	# 以下 color override 与 Theme 定义一致，全部删除
	pass


# ============ Connections ============

func _setup_connections() -> void:
	if input_field:
		input_field.text_submitted.connect(_on_input_submitted)
	if send_button:
		send_button.pressed.connect(_on_send_pressed)
	if session_sidebar:
		session_sidebar.session_selected.connect(_on_session_selected)
		session_sidebar.session_deleted.connect(_on_session_deleted)


func _setup_agent() -> void:
	if chat_agent == null:
		push_error("DeepCodeApp: ChatAgent not found")
		return
	chat_agent.message_completed.connect(_on_message_completed)
	chat_agent.message_failed.connect(_on_message_failed)
	chat_agent.log_entry.connect(_on_log_entry)
	chat_agent.tool_executed.connect(_on_tool_executed)


# ============ Input Locking ============

func _lock_input() -> void:
	_input_locked = true
	if input_field:
		input_field.editable = false
		input_field.placeholder_text = "等待回复中..."
	if send_button:
		send_button.disabled = true


func _unlock_input() -> void:
	_input_locked = false
	if input_field:
		input_field.editable = true
		input_field.placeholder_text = "给 DeepCode 发送消息..."
	if send_button:
		send_button.disabled = false


# ============ Input Handling ============

func _on_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	if _input_locked:
		return

	# 如果打字机正在输出，先跳过
	if _display_manager and _display_manager.is_typing():
		_display_manager.skip_typewriter()

	if input_field:
		input_field.clear()

	if _display_manager:
		_display_manager.add_user_message(text)

	# 锁定输入
	_lock_input()

	if chat_agent:
		var req_id: String = chat_agent.send_message(text)
		if not req_id.is_empty() and _display_manager:
			_display_manager.start_ai_message()
			_update_debug_prompt()
		elif req_id.is_empty():
			# 发送失败（agent busy 等），解锁
			_unlock_input()

	# 更新 sidebar 标题
	if session_sidebar and not _active_session_id.is_empty():
		session_sidebar.update_session_messages(_active_session_id, chat_agent.get_messages() if chat_agent else [])



func _on_send_pressed() -> void:
	if input_field:
		_on_input_submitted(input_field.text)


# ============ Agent Signal Handlers ============

func _on_message_completed(_request_id: String, content: String) -> void:
	print("[DeepCode] _on_message_completed: req=%s content_len=%d is_empty=%s" % [_request_id, content.length(), str(content.is_empty())])
	if content.length() < 200:
		print("[DeepCode] content: %s" % content)
	else:
		print("[DeepCode] content (first 200): %s" % content.left(200))

	if _display_manager and not content.is_empty():
		_display_manager.process_ai_chunk(content)
	else:
		print("[DeepCode] SKIPPED display: _display_manager=%s content_empty=%s" % [str(_display_manager != null), str(content.is_empty())])

	# 保存消息到 session cache
	_save_current_session()

	# 解锁输入
	_unlock_input()


func _on_message_failed(_request_id: String, error: String) -> void:
	if _display_manager:
		_display_manager.process_ai_chunk("\n[color=#e06c75]请求失败: " + error + "[/color]")
	_unlock_input()


func _on_log_entry(entry: Dictionary) -> void:
	var entry_type: String = entry.get("type", "")
	if entry_type == "ai_response":
		return
	# 路由到 debug panel
	if debug_panel:
		var content: String = entry.get("content", "")
		match entry_type:
			"tool_call":
				debug_panel.add_log(content, "#d4a574")
			"tool_result":
				debug_panel.add_log(content, "#98c379")
			"error":
				debug_panel.add_log(content, "#e06c75")
			"progress":
				debug_panel.add_log(content, "#a0a0a0")
			_:
				debug_panel.add_log(content)


func _on_tool_executed(_request_id: String, tool_name: String, args: Dictionary, result: Variant) -> void:
	if debug_panel:
		debug_panel.add_tool_log(tool_name, str(args).left(300), str(result).left(300))
	# tool 执行后 prompt 可能变化（如 skill 激活/停用）
	_update_debug_prompt()

	# 图片生成完成 — 在聊天流中插入图片预览
	if tool_name == "generate_image" and result is Dictionary and result.get("success", false):
		var data: Dictionary = result.get("data", {})
		var images: Array = data.get("images", [])
		for img in images:
			if img is Dictionary:
				var local_path: String = img.get("saved_to", "")
				var image_id: String = img.get("image_id", "")
				var prompt_hint: String = data.get("prompt_used", "")
				if not local_path.is_empty() and _display_manager:
					_display_manager.add_image_block(local_path, image_id, prompt_hint)


func _update_debug_prompt() -> void:
	if debug_panel and chat_agent:
		debug_panel.update_prompt(chat_agent.get_effective_system_prompt())


# ============ Session Management ============

func _on_session_selected(session_id: String) -> void:
	if session_id == _active_session_id:
		return

	# 保存当前 session
	_save_current_session()

	# 切换
	_active_session_id = session_id

	# 清空聊天区域
	_clear_chat_area()

	# 恢复 agent 状态
	if chat_agent:
		chat_agent.reset()

	# 加载 session 消息
	var cached: Dictionary = _session_cache.get(session_id, {})
	var messages: Array = cached.get("messages", [])

	if messages.is_empty():
		# 新 session — 显示欢迎消息
		if _display_manager:
			_display_manager.start_ai_message()
			_display_manager.process_ai_chunk("你好，我是 DeepCode AI 场景创作助手。告诉我你想创建什么样的场景吧。")
	else:
		# 恢复历史消息到 agent 和 UI
		_restore_session(messages)

	_unlock_input()
	_update_debug_prompt()


func _on_session_deleted(session_id: String) -> void:
	_session_cache.erase(session_id)


func _save_current_session() -> void:
	if _active_session_id.is_empty() or chat_agent == null:
		return
	var messages: Array = chat_agent.get_messages()
	_session_cache[_active_session_id] = {"messages": messages}
	if session_sidebar:
		session_sidebar.update_session_messages(_active_session_id, messages)


func _restore_session(messages: Array) -> void:
	if chat_agent == null or _display_manager == null:
		return

	# 恢复 agent 历史
	for msg in messages:
		chat_agent.add_message(msg.get("role", "user"), msg.get("content", ""))

	# 恢复 UI 显示
	for msg in messages:
		var role_name: String = msg.get("role", "")
		var content: String = msg.get("content", "")
		if role_name == "user":
			_display_manager.add_user_message(content)
		elif role_name == "assistant" and not content.is_empty():
			_display_manager.start_ai_message()
			# 恢复时直接显示，不走打字机
			_display_manager.skip_typewriter()
			_display_manager.process_ai_chunk(content)
			_display_manager.skip_typewriter()


func _clear_chat_area() -> void:
	if message_list == null:
		return
	for child in message_list.get_children():
		child.queue_free()
	if _display_manager:
		_display_manager.reset()
