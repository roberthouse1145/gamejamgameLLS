class_name DailyMemorySummarizer extends Node
## 每日记忆整合器
## 在每天结束（day_changed）时，按频道独立收集当天聊天记录，
## 并行调用轻量 LLM 生成结构化摘要，存入 MemoryManager。
## LLM 只负责摘要内容，npc_id 由程序根据频道成员自动分发。

const SUMMARIZER_ROLE: String = "memory_summarizer"
const FALLBACK_ROLE: String = "doubao-mini"
const MAX_MESSAGES_PER_CHANNEL: int = 50

signal summarize_completed(day: int, memory_count: int)
signal summarize_failed(day: int, error: String)

var _ai_service: AIService
var _memory_manager: MemoryManager
var _llm_ready: bool = false
var _pending_day: int = -1
var _system_prompt: String = ""

## 并行请求追踪：request_id -> channel_info { channel_id, channel_name, members }
var _pending_requests: Dictionary = {}
## 本轮累计存储的记忆数
var _day_stored_count: int = 0


func _ready() -> void:
	_ai_service = AIService.new()
	_ai_service.default_max_tokens = 1024
	_ai_service.default_temperature = 0.3
	_ai_service.max_retries = 1
	add_child(_ai_service)

	_ai_service.request_completed.connect(_on_request_completed)
	_ai_service.request_failed.connect(_on_request_failed)

	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		_llm_ready = config_mgr.apply_to_service(_ai_service, SUMMARIZER_ROLE)
		if not _llm_ready:
			_llm_ready = config_mgr.apply_to_service(_ai_service, FALLBACK_ROLE)

	# 连接 day_changed 信号
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed"):
		if not glm.day_changed.is_connected(_on_day_changed):
			glm.day_changed.connect(_on_day_changed)


func setup(memory_manager: MemoryManager) -> void:
	_memory_manager = memory_manager


func _on_day_changed(_new_day: int) -> void:
	# day_changed 触发时 current_day 已经是新的一天，所以要整合的是前一天
	var completed_day: int = _new_day - 1
	if completed_day < 1:
		return
	summarize_day(completed_day)


func summarize_day(day: int) -> void:
	if not _llm_ready:
		print("[DailyMemorySummarizer] LLM not configured, skipping day %d" % day)
		summarize_failed.emit(day, "LLM not configured")
		return
	if _memory_manager == null:
		print("[DailyMemorySummarizer] MemoryManager not set, skipping day %d" % day)
		summarize_failed.emit(day, "MemoryManager not set")
		return
	if not _pending_requests.is_empty():
		print("[DailyMemorySummarizer] Already processing day %d, skipping day %d" % [_pending_day, day])
		return

	var tasks := _collect_channel_tasks(day)
	if tasks.is_empty():
		print("[DailyMemorySummarizer] No messages for day %d, skipping" % day)
		summarize_completed.emit(day, 0)
		return

	_pending_day = day
	_day_stored_count = 0
	_pending_requests.clear()

	# 并行发送所有频道的摘要请求
	var system_prompt := _get_system_prompt()
	for task in tasks:
		var user_content := "频道：%s\n比赛第 %d 天的聊天记录：\n\n%s" % [
			task.channel_name,
			day,
			task.chat_log,
		]
		var request_id := _ai_service.chat_simple(user_content, system_prompt)
		_pending_requests[request_id] = task
		print("[DailyMemorySummarizer] Sent request %s for day %d, channel '%s'" % [request_id, day, task.channel_id])


## 收集每个频道的独立摘要任务
func _collect_channel_tasks(day: int) -> Array[Dictionary]:
	var chat_manager: Node = get_node_or_null("/root/ChatManager")
	if chat_manager == null:
		return []

	var channels: Dictionary = chat_manager.get_channels()
	var tasks: Array[Dictionary] = []

	for channel_id in channels:
		var channel: ChatChannel = channels[channel_id] as ChatChannel
		if channel == null:
			continue

		var day_messages := _filter_messages_by_day(channel.messages, day)
		if day_messages.is_empty():
			continue

		var chat_log := _format_channel_log(channel, day_messages)
		if chat_log.is_empty():
			continue

		# 收集频道内非 player/system 的成员列表
		var npc_members: Array[String] = []
		for member_id in channel.members:
			if member_id != "player" and member_id != "system":
				npc_members.append(member_id)

		tasks.append({
			"channel_id": channel.channel_id,
			"channel_name": channel.display_name,
			"members": npc_members,
			"chat_log": chat_log,
		})

	return tasks


## 格式化单个频道的聊天记录
func _format_channel_log(channel: ChatChannel, day_messages: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for msg in day_messages.slice(-MAX_MESSAGES_PER_CHANNEL):
		var sender: String = msg.get("sender_name", msg.get("sender_id", "未知"))
		var time_str: String = msg.get("time", "")
		var content: String = msg.get("content", "")
		if content.strip_edges().is_empty():
			continue
		if msg.get("sender_id", "") == "system":
			continue
		lines.append("[%s] %s: %s" % [time_str, sender, content])
	return "\n".join(lines)


func _filter_messages_by_day(messages: Array[Dictionary], day: int) -> Array[Dictionary]:
	## 通过 GameLoopManager 的天数信息过滤消息
	## 由于消息没有直接存储 game_day，我们用 topic_history 的时间戳来推断
	## 简化方案：取所有消息中属于当天的（基于消息在数组中的位置和 day boundary）
	##
	## 更可靠的方案：在消息中记录 game_day。但目前先用时间戳近似。
	## 由于游戏内一天的消息是连续的，我们可以用 day boundary markers 来分割。
	##
	## 最简单的做法：如果消息里有 game_day 字段就用它，否则返回所有消息（兜底）
	var result: Array[Dictionary] = []
	for msg in messages:
		var msg_day: int = int(msg.get("game_day", 0))
		if msg_day == day:
			result.append(msg)
	return result


func _get_system_prompt() -> String:
	if not _system_prompt.is_empty():
		return _system_prompt
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("resolve") and pm.has_method("has_prompt"):
		if pm.has_prompt("memory_summarizer"):
			_system_prompt = pm.resolve("memory_summarizer")
	if _system_prompt.is_empty():
		_system_prompt = "将聊天记录压缩为JSON记忆数组。每条记忆包含 content, tags, importance, emotional_valence。不需要输出 npc_id。只输出JSON。"
	return _system_prompt


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if not _pending_requests.has(request_id):
		return

	var channel_info: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)

	var day: int = _pending_day
	var channel_id: String = str(channel_info.get("channel_id", ""))
	var npc_members: Array = channel_info.get("members", [])

	var content: String = AIService.extract_content(response).strip_edges()
	if content.is_empty():
		print("[DailyMemorySummarizer] Empty response for day %d, channel '%s'" % [day, channel_id])
		_check_all_done()
		return

	var memories := _parse_memories(content, day)
	var stored_count: int = 0

	for mem_dict in memories:
		var mem_content: String = str(mem_dict.get("content", "")).strip_edges()
		if mem_content.is_empty():
			continue

		var importance: float = clampf(float(mem_dict.get("importance", 0.5)), 0.0, 1.0)
		var emotional_valence: float = clampf(float(mem_dict.get("emotional_valence", 0.0)), -1.0, 1.0)
		var tags: Array[String] = []
		var tags_raw: Variant = mem_dict.get("tags", [])
		if tags_raw is Array:
			for tag in tags_raw:
				tags.append(str(tag))

		if npc_members.is_empty():
			# 无 NPC 成员的频道（如公共群），跳过——这些记忆没有归属主体
			print("[DailyMemorySummarizer] Skipping memory for channel '%s' (no NPC members): %s" % [channel_id, mem_content])
			continue

		# 将记忆分发给频道内每一位 NPC 成员
		for npc_id in npc_members:
			var entry := MemoryEntry.new()
			entry.npc_id = npc_id
			entry.memory_type = MemoryEntry.MemoryType.EPISODIC
			entry.content = "【第%d天】%s" % [day, mem_content]
			entry.importance = importance
			entry.emotional_valence = emotional_valence
			entry.source_type = "daily_summary"
			entry.source_topic_id = "day_%d" % day
			entry.source_channel_id = channel_id
			entry.tags = tags.duplicate()
			_memory_manager.store_memory(entry)
			stored_count += 1

	_day_stored_count += stored_count
	print("[DailyMemorySummarizer] Day %d, channel '%s': stored %d memories (%d NPC members)" % [day, channel_id, stored_count, npc_members.size()])
	_check_all_done()


func _on_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _pending_requests.has(request_id):
		return

	var channel_info: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)
	var channel_id: String = str(channel_info.get("channel_id", ""))
	print("[DailyMemorySummarizer] Failed for day %d, channel '%s': %s" % [_pending_day, channel_id, error])
	_check_all_done()


## 检查是否所有并行请求都已完成
func _check_all_done() -> void:
	if not _pending_requests.is_empty():
		return

	var day := _pending_day
	var count := _day_stored_count
	_pending_day = -1
	print("[DailyMemorySummarizer] Day %d: total stored %d memories" % [day, count])
	if count > 0:
		summarize_completed.emit(day, count)
	else:
		summarize_failed.emit(day, "No memories stored")


func _parse_memories(content: String, _day: int) -> Array[Dictionary]:
	# 尝试从响应中提取 JSON 数组
	var json_text := content.strip_edges()

	# 如果被 markdown 代码块包裹，剥离
	if json_text.begins_with("```"):
		var first_newline := json_text.find("\n")
		if first_newline >= 0:
			json_text = json_text.substr(first_newline + 1)
		if json_text.ends_with("```"):
			json_text = json_text.substr(0, json_text.length() - 3).strip_edges()

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Array):
		push_warning("[DailyMemorySummarizer] Failed to parse JSON: %s" % json_text.left(200))
		return []

	var result: Array[Dictionary] = []
	for item in parsed:
		if item is Dictionary:
			result.append(item)
	return result
