extends Node
## ChatManager — 聊天数据层 autoload
## 持有频道、消息、NPC、Topic、记忆、AI服务等所有聊天数据
## LinkChatApp 只做 UI 渲染，从此处读取数据和监听信号

# Preload classes
const NPCManagerClass = preload("res://scripts/chat/npc_manager.gd")
const ChatProjectContextBuilderClass = preload("res://scripts/chat/chat_project_context_builder.gd")
const ChatProtocolExecutorClass = preload("res://scripts/chat/chat_protocol_executor.gd")
const ChatResponseParserClass = preload("res://scripts/chat/chat_response_parser.gd")
const ChatStateStoreClass = preload("res://scripts/chat/chat_state_store.gd")
const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")
const NPCCharacterClass = preload("res://scripts/chat/resources/npc_character.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const DailyMemorySummarizerClass = preload("res://scripts/chat/daily_memory_summarizer.gd")
const InputGuardClass = preload("res://scripts/chat/input_guard.gd")
const ChatAgentScene = preload("res://scenes/llm/chat_agent.tscn")
const AVGDevKBToolsClass = preload("res://scripts/avg/dev_tools/kb_tools.gd")
const AVGDevWorkOrderToolsClass = preload("res://scripts/avg/dev_tools/work_order_tools.gd")

const LINKCHAT_IMAGE_CARD_REGISTRY_PATH: String = "res://resources/data/linkchat_image_cards.json"
const NPC_RESOURCE_PATHS: Array[String] = [
	"res://resources/characters/npc_lin_xia.tres",
	"res://resources/characters/npc_mom.tres",
]
const CHANNEL_RESOURCE_PATHS: Array[String] = [
	"res://resources/channels/dm_lin_xia.tres",
	"res://resources/channels/dm_mom.tres",
	"res://resources/channels/agj_official.tres",
	"res://resources/channels/class_group.tres",
	"res://resources/channels/hs_group.tres",
]
const PROTOCOL_DIRECT_ACTION_COMMANDS: Array[String] = [
	"open_browser",
	"focus_app",
	"launch_app",
	"post_moment",
	"lock_app_window",
	"unlock_app_window",
	"generate_work_order",
]
const REQUEST_SOURCE_AI_SERVICE: String = "ai_service"
const REQUEST_SOURCE_COLLABORATOR_AGENT: String = "collaborator_agent"
const TOPIC_TIMEOUT_CONTINUE_SEED: String = "对方在一段时间内没有回复。"
const LINKCHAT_AI_TIMEOUT: float = 30.0
const LINKCHAT_AI_MAX_RETRIES: int = 1
const LINKCHAT_AI_RETRY_DELAY: float = 0.35
## 每日开始时只对白名单频道触发摘要（对话历史非空时）
const SUMMARY_CHANNEL_WHITELIST: Array[String] = [
	"dm_lin_xia",
	"dm_mom",
]
const MOMENT_AUTHOR_PRESETS: Dictionary = {
	"npc_agj_assist": {
		"display_name": "AGJ组委会-小月",
		"avatar_mode": "seed",
		"avatar_seed": "agj_assist",
	},
	"npc_classmate_a": {
		"display_name": "战蓝哥",
		"avatar_mode": "seed",
		"avatar_seed": "classmate_zhanlange",
	},
	"npc_classmate_b": {
		"display_name": "呢喃老登",
		"avatar_mode": "seed",
		"avatar_seed": "classmate_ninan",
	},
	"npc_class_monitor": {
		"display_name": "蓝鲸小南门",
		"avatar_mode": "seed",
		"avatar_seed": "class_nanmen",
	},
	"npc_hs_zhao": {
		"display_name": "澜听雨落",
		"avatar_mode": "seed",
		"avatar_seed": "hs_zhao",
	},
	"npc_hs_sun": {
		"display_name": "考研上岸倒计时",
		"avatar_mode": "seed",
		"avatar_seed": "hs_sun",
	},
	"npc_uni_wang": {
		"display_name": "阿汪在路上",
		"avatar_mode": "seed",
		"avatar_seed": "uni_wang",
	},
	"npc_hs_liu": {
		"display_name": "嘻嘻的刘刘",
		"avatar_mode": "seed",
		"avatar_seed": "hs_liu",
	},
}

#region 信号
## 频道新增
signal channel_added(channel_id: String)
## 消息被添加到频道（无论收发、无论系统还是普通）
signal message_added(channel_id: String, msg_data: Dictionary)
## 收到 NPC/AI 的新消息流（UI 用来做打字机等长程演出）
## messages: Array[{speaker: String, content: String}]
## recommended_replies: Array[String] (大模型推测的玩家回复选项，可能为空)
signal npc_messages_received(channel_id: String, messages: Array[Dictionary], recommended_replies: Array[String])
## Topic 生命周期
signal topic_activated(topic: ChatTopic)
signal topic_completed(topic: ChatTopic, result: Dictionary)
signal topic_timeout(topic: ChatTopic)
signal topic_cancelled(topic: ChatTopic, reason: String)
signal chat_event_emitted(topic: ChatTopic, event_id: String, payload: Dictionary)
signal chat_action_requested(topic: ChatTopic, action: Dictionary)
## 批处理状态
signal batch_state_changed(is_batching: bool)
## AI 等待状态
signal waiting_for_ai_changed(is_waiting: bool)
## AI 请求失败
signal ai_request_failed(channel_id: String, error: String)
## 朋友圈新动态
signal moment_posted(moment: Dictionary)
## 持久化相关的稳定状态发生变化
signal chat_state_changed()
## 玩家消息被审核拦截
signal message_blocked(channel_id: String, text: String)
#endregion

#region 子系统
var topic_manager: TopicManager
var batch_handler: MessageBatchHandler
var memory_manager: MemoryManager
var ai_service: AIService
var collaborator_agent: ChatAgent
var npc_manager: NPCManager
var input_guard: Node
var daily_memory_summarizer: Node
var _state_store = null
var _project_context_builder = null
var _protocol_executor = null
var _response_parser = null
#endregion

#region 数据
## 是否正在等待 AI 回复
var _waiting_for_ai: bool = false
## 当前等待 AI 的频道
var _waiting_channel_id: String = ""
## 当前 pending 的 AI 请求 ID
var _pending_request_id: String = ""
var _pending_request_source: String = ""
var _pending_auto_store_response: bool = false
var _pending_complete_topic_after_response: bool = false
## channel_id -> UI presentation count
var _active_npc_message_presentations: Dictionary = {}
## channel_id -> {topic: ChatTopic, result: Dictionary}
var _pending_topic_completions: Dictionary = {}
var _pending_protocol_effects: Dictionary = {}
var _pending_timeout_followups: Dictionary = {}
## image_id -> card definition
var _image_card_registry: Dictionary = {}
## 最近一次被激活的话题频道，供 LinkChat 启动时优先选中
var _last_activated_topic_channel_id: String = ""
## Debug模式：无需Topic即可聊天，消息立即发送给AI
# debug_mode=true 时允许在无 topic 状态下自由聊天（仅调试用）。
# 正式玩法：玩家只能在 topic 激活时发言，因此默认 false。
# 编辑器内如需调试可在代码里临时改为 true 或从 remote inspector 改。
var debug_mode: bool = false
#endregion


func _ready() -> void:
	_setup_subsystems()
	_setup_connections()
	_load_linkchat_image_card_registry()
	_setup_npcs()
	_setup_default_channels()
	_setup_default_moments()
	ActivityLockUtilsClass.register_busy_source(
		name,
		self,
		"has_any_active_topics",
		ActivityLockUtilsClass.DEFAULT_CHAT_BLOCK_REASON
	)


func _exit_tree() -> void:
	ActivityLockUtilsClass.unregister_busy_source(name)


func _setup_subsystems() -> void:
	topic_manager = TopicManager.new()
	add_child(topic_manager)

	batch_handler = MessageBatchHandler.new()
	add_child(batch_handler)

	memory_manager = MemoryManager.new()
	add_child(memory_manager)

	ai_service = AIService.new()
	add_child(ai_service)
	_setup_collaborator_agent()

	npc_manager = NPCManagerClass.new()

	input_guard = InputGuardClass.new()
	add_child(input_guard)

	daily_memory_summarizer = DailyMemorySummarizerClass.new()
	daily_memory_summarizer.setup(memory_manager)
	daily_memory_summarizer.summary_channel_whitelist.assign(SUMMARY_CHANNEL_WHITELIST)
	add_child(daily_memory_summarizer)

	_state_store = ChatStateStoreClass.new()
	_state_store.setup(Callable(self, "_build_moment_author_snapshot"))

	_project_context_builder = ChatProjectContextBuilderClass.new()

	_protocol_executor = ChatProtocolExecutorClass.new()
	_protocol_executor.setup(Callable(self, "post_moment"), Callable(self, "_get_channel_messages_for_protocol"))
	add_child(_protocol_executor)

	_response_parser = ChatResponseParserClass.new()
	_response_parser.setup(Callable(self, "_sanitize_message_card"), PROTOCOL_DIRECT_ACTION_COMMANDS)

	# 加载 AI 配置
	var config_mgr := AIConfigManager.get_instance()
	config_mgr.apply_to_service(ai_service, "linkchat")
	_configure_linkchat_ai_service(ai_service)
	# 读取审核开关。优先读 [dev]，再兼容旧配置里写在 [roles] 的方式。
	var raw_enabled: Variant = config_mgr.get_dev_setting("input_guard_enabled", null)
	if raw_enabled == null:
		raw_enabled = config_mgr._roles.get("input_guard_enabled", "true")
	var normalized_enabled: String = str(raw_enabled).strip_edges().to_lower()
	input_guard.enabled = (normalized_enabled != "false" and normalized_enabled != "0")
	print("[ChatManager] AI config loaded, input_guard enabled=%s" % input_guard.enabled)


func _setup_collaborator_agent() -> void:
	var agent: ChatAgent = ChatAgentScene.instantiate()
	agent.name = "CollaboratorChatAgent"
	agent.role = "linkchat"
	add_child(agent)
	collaborator_agent = agent

	collaborator_agent.message_completed.connect(_on_collaborator_agent_message_completed)
	collaborator_agent.message_failed.connect(_on_collaborator_agent_message_failed)

	var collaborator_ai_service: Node = collaborator_agent.get_node_or_null("AIService")
	if collaborator_ai_service != null:
		_configure_linkchat_ai_service(collaborator_ai_service as AIService)
		AVGDevKBToolsClass.register_read_only(collaborator_ai_service)
		AVGDevWorkOrderToolsClass.register_summary_read_only(collaborator_ai_service)

	collaborator_agent.register_tool(
		"get_dev_cycle_snapshot",
		"获取当前开发循环的简要状态，包括当前天数、可见任务、已完成任务数量、工单队列情况、计划是否已生成。",
		{
			"type": "object",
			"properties": {},
		},
		func(args: Dictionary) -> Variant: return _collaborator_tool_get_dev_cycle_snapshot(args)
	)


func _configure_linkchat_ai_service(service: AIService) -> void:
	if service == null:
		return
	service.timeout = LINKCHAT_AI_TIMEOUT
	service.max_retries = LINKCHAT_AI_MAX_RETRIES
	service.retry_delay = LINKCHAT_AI_RETRY_DELAY


func _setup_connections() -> void:
	# 批处理
	batch_handler.batch_ready.connect(_on_batch_ready)
	batch_handler.batching_state_changed.connect(func(is_batching: bool) -> void:
		batch_state_changed.emit(is_batching)
	)

	# Topic
	topic_manager.topic_activated.connect(_on_topic_activated)
	topic_manager.topic_completed.connect(_on_topic_completed)
	topic_manager.topic_timeout.connect(_on_topic_timeout)
	topic_manager.topic_cancelled.connect(_on_topic_cancelled)

	# AI
	ai_service.request_completed.connect(_on_ai_request_completed)
	ai_service.stream_completed.connect(_on_ai_stream_completed)
	ai_service.request_failed.connect(_on_ai_request_failed)

	if _protocol_executor != null:
		_protocol_executor.event_emitted.connect(func(topic: ChatTopic, event_id: String, payload: Dictionary) -> void:
			chat_event_emitted.emit(topic, event_id, payload)
		)
		_protocol_executor.action_requested.connect(func(topic: ChatTopic, action: Dictionary) -> void:
			chat_action_requested.emit(topic, action)
		)

	if _state_store != null:
		_state_store.channel_added.connect(func(channel_id: String) -> void:
			channel_added.emit(channel_id)
		)
		_state_store.message_added.connect(func(channel_id: String, msg_data: Dictionary) -> void:
			message_added.emit(channel_id, msg_data)
		)
		_state_store.moment_posted.connect(func(moment: Dictionary) -> void:
			moment_posted.emit(moment)
		)
		_state_store.state_changed.connect(func() -> void:
			_emit_chat_state_changed()
		)

	# 日期变更：清空前一天对话历史（DailyMemorySummarizer 已先于此连接，会先收集数据）
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed"):
		glm.day_changed.connect(_on_day_changed)


func _setup_npcs() -> void:
	for resource_path in NPC_RESOURCE_PATHS:
		_register_npc_from_resource(load(resource_path) as NPCCharacter)
	print("[ChatManager] Registered %d NPCs" % npc_manager.get_all_npc_ids().size())


func _register_npc_from_resource(template: NPCCharacter) -> void:
	if template == null:
		push_error("[ChatManager] NPC resource template is null")
		return
	var npc := template.duplicate() as NPCCharacter
	# 资源内的 prompt 允许写 {{prompt_key}}，启动时统一展开。
	var pm: Node = Engine.get_main_loop().root.get_node_or_null("PromptManager")
	if pm and not npc.prompt.strip_edges().is_empty():
		npc.prompt = pm.resolve_template(npc.prompt)
	elif npc.prompt.is_empty():
		push_warning("[ChatManager] NPC prompt is empty: %s" % npc.character_id)
	npc_manager.register_npc(npc)


func _setup_default_channels() -> void:
	for resource_path in CHANNEL_RESOURCE_PATHS:
		_load_channel_from_resource(load(resource_path) as ChatChannel)


func _load_channel_from_resource(template: ChatChannel) -> void:
	if template == null:
		push_error("[ChatManager] Channel resource template is null")
		return
	var channel := template.duplicate() as ChatChannel
	var pm: Node = Engine.get_main_loop().root.get_node_or_null("PromptManager")
	if pm and not channel.channel_prompt.strip_edges().is_empty():
		channel.channel_prompt = pm.resolve_template(channel.channel_prompt)
	# 重置运行时状态
	channel.unread_count = 0
	channel.messages = []
	if _state_store != null:
		_state_store.register_channel(channel)


#region 频道 API

func add_channel(channel_id: String, display_name: String, channel_type: int, members_list: Array) -> void:
	if _state_store == null:
		return
	_state_store.add_channel(channel_id, display_name, channel_type, members_list)


func get_channel(channel_id: String) -> Resource:
	if _state_store == null:
		return null
	return _state_store.get_channel(channel_id)


func get_channel_order() -> Array[String]:
	if _state_store == null:
		return []
	return _state_store.get_channel_order()


func get_channels() -> Dictionary:
	if _state_store == null:
		return {}
	return _state_store.get_channels()

#endregion


#region 消息 API

## 玩家发送消息（进入批处理队列 + 立即存储到频道）
## debug_mode 下跳过批处理，直接触发 AI
## 返回 true 表示消息已发送，false 表示被审核拦截
func add_player_message(channel_id: String, text: String) -> bool:
	if text.strip_edges().is_empty():
		return false

	# 审核玩家输入
	var audit: Dictionary = await input_guard.analyze(text)
	var passed: bool = bool(audit.get("passed", true))
	if not passed:
		print("[ChatManager] Message blocked by InputGuard: %s" % text)
		message_blocked.emit(channel_id, text)
		return false

	var message_payload: Dictionary = {"content": text}
	if audit.get("risk_tags", null) is Array and not (audit.get("risk_tags", []) as Array).is_empty():
		message_payload["input_guard"] = {
			"source": str(audit.get("source", "")),
			"risk_tags": (audit.get("risk_tags", []) as Array).duplicate(true),
		}

	_store_message_data(channel_id, "player", message_payload)

	if debug_mode:
		_on_batch_ready_for_channel([text], channel_id)
	else:
		batch_handler.add_message(text)
	return true


func store_player_message_data(channel_id: String, message_data: Dictionary) -> Dictionary:
	return _store_message_data(channel_id, "player", message_data)


## 系统消息（直接存储）
func add_system_message(channel_id: String, text: String) -> Dictionary:
	return _store_message(channel_id, "system", text)


func add_system_message_data(channel_id: String, message_data: Dictionary) -> Dictionary:
	return _store_message_data(channel_id, "system", message_data)


func debug_send_image_card(channel_id: String = "dm_lin_xia", sender_id: String = "npc_lin_xia", image_id: String = "linxia_chibi_happy", text: String = "") -> void:
	var card := _build_image_card_from_registry(image_id)
	if card.is_empty():
		push_warning("[ChatManager] Unknown image card id: %s" % image_id)
		return
	_store_message_data(channel_id, sender_id, {
		"speaker": sender_id,
		"content": text,
		"card": card,
	})


func debug_send_mock_card(channel_id: String = "dm_lin_xia", sender_id: String = "npc_lin_xia") -> void:
	_store_message_data(channel_id, sender_id, {
		"speaker": sender_id,
		"content": "",
		"card": {
			"type": "mock_image",
			"theme": "contract",
			"title": "合作补充协议",
			"subtitle": "乙方：林夏",
			"body": "需在本周五 18:00 前补交参赛材料，并确认演示版本可正常运行。",
			"footer": "AGJ 赛事组委会",
			"hint": "像一张随手拍下来的纸质合同照片"
		}
	})


func debug_send_web_card(channel_id: String = "dm_lin_xia", sender_id: String = "npc_lin_xia") -> void:
	_store_message_data(channel_id, sender_id, {
		"speaker": sender_id,
		"content": "",
		"card": {
			"type": "web_page",
			"title": "爱情 - 百科",
			"url": "baike.com/爱情",
			"hint": "一篇介绍爱情定义、理论和相关知识的百科页面。"
		}
	})


func get_registered_image_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _image_card_registry.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func get_image_card_definition(image_id: String) -> Dictionary:
	var normalized_id := image_id.strip_edges()
	if normalized_id.is_empty() or not _image_card_registry.has(normalized_id):
		return {}
	return (_image_card_registry[normalized_id] as Dictionary).duplicate(true)


## 强制发送批处理
func force_send_batch() -> void:
	batch_handler.force_send()


## NPC 消息存储（由 UI 在打字机动画中逐条调用）
func store_npc_message(channel_id: String, npc_id: String, content: String) -> Dictionary:
	var clean_content := NPCResponseHandler.clean_message(content)
	return _store_message(channel_id, npc_id, clean_content)


func store_npc_message_data(channel_id: String, message_data: Dictionary) -> Dictionary:
	var normalized := message_data.duplicate(true)
	if normalized.has("content"):
		normalized["content"] = NPCResponseHandler.clean_message(str(normalized.get("content", "")))
	return _store_message_data(channel_id, str(normalized.get("speaker", normalized.get("sender_id", "unknown"))), normalized)


## 内部：存储消息到频道并发信号
func _store_message(channel_id: String, sender_id: String, content: String) -> Dictionary:
	return _store_message_data(channel_id, sender_id, {"content": content})


func _store_message_data(channel_id: String, sender_id: String, message_data: Dictionary) -> Dictionary:
	if _state_store == null:
		return {}
	var normalized := _normalize_message_data(sender_id, message_data)
	var actual_sender_id := str(normalized.get("speaker", sender_id)).strip_edges()
	if actual_sender_id.is_empty():
		actual_sender_id = sender_id
	actual_sender_id = _resolve_character_id(actual_sender_id)
	var sender_name := resolve_sender_name(actual_sender_id)
	var content := str(normalized.get("content", ""))
	if content.strip_edges().is_empty() and (not normalized.has("card") or (normalized["card"] as Dictionary).is_empty()):
		return {}
	return _state_store.store_message_data(channel_id, actual_sender_id, sender_name, normalized)


func _normalize_message_data(default_sender_id: String, message_data: Dictionary) -> Dictionary:
	var normalized: Dictionary = {
		"speaker": default_sender_id,
		"content": str(message_data.get("content", "")),
	}
	var speaker := str(message_data.get("speaker", message_data.get("sender_id", default_sender_id))).strip_edges()
	if not speaker.is_empty():
		normalized["speaker"] = speaker
	if message_data.has("card") and message_data["card"] is Dictionary:
		var card := _sanitize_message_card(message_data["card"])
		if not card.is_empty():
			normalized["card"] = card
	for key in message_data:
		if key in ["content", "speaker", "sender_id", "card"]:
			continue
		normalized[key] = message_data[key]
	return normalized


func _sanitize_message_card(card: Dictionary) -> Dictionary:
	var card_type := str(card.get("type", "")).strip_edges().to_lower()
	if card_type.is_empty():
		return {}
	var sanitized: Dictionary = {"type": card_type}
	var allowed_keys := [
		"title", "subtitle", "hint", "body", "footer", "badge", "image_id", "image_path",
		"texture_path", "url", "theme", "design_prompt", "caption", "alt",
		"site_name", "accent_color", "preview_width", "preview_height", "price", "salary"
	]
	for key in allowed_keys:
		if card.has(key):
			sanitized[key] = card[key]
	if card_type == "image":
		sanitized = _resolve_image_card_payload(sanitized)
	return sanitized


func _load_linkchat_image_card_registry() -> void:
	_image_card_registry.clear()
	if not FileAccess.file_exists(LINKCHAT_IMAGE_CARD_REGISTRY_PATH):
		push_warning("[ChatManager] Image card registry not found: %s" % LINKCHAT_IMAGE_CARD_REGISTRY_PATH)
		return
	var file := FileAccess.open(LINKCHAT_IMAGE_CARD_REGISTRY_PATH, FileAccess.READ)
	if file == null:
		push_warning("[ChatManager] Failed to open image card registry")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("[ChatManager] Image card registry format invalid")
		return
	var cards: Dictionary = parsed.get("cards", {})
	for raw_id in cards:
		var image_id := str(raw_id).strip_edges()
		var def: Variant = cards[raw_id]
		if image_id.is_empty() or not def is Dictionary:
			continue
		var normalized := (def as Dictionary).duplicate(true)
		normalized["image_id"] = image_id
		_image_card_registry[image_id] = normalized
	print("[ChatManager] Loaded %d image card definitions" % _image_card_registry.size())


func _build_image_card_from_registry(image_id: String) -> Dictionary:
	var resolved := get_image_card_definition(image_id)
	if resolved.is_empty():
		return {}
	resolved["type"] = "image"
	return _resolve_image_card_payload(resolved)


func _resolve_image_card_payload(card: Dictionary) -> Dictionary:
	var resolved := card.duplicate(true)
	var image_id := str(resolved.get("image_id", "")).strip_edges()
	if not image_id.is_empty():
		var reg_entry := get_image_card_definition(image_id)
		if reg_entry.is_empty():
			push_warning("[ChatManager] Unknown image card id: %s" % image_id)
		else:
			for key in reg_entry:
				resolved[key] = reg_entry[key]
			resolved["image_id"] = str(reg_entry.get("image_id", image_id)).strip_edges()
	if str(resolved.get("image_path", resolved.get("texture_path", ""))).strip_edges().is_empty():
		return {}
	return resolved

#endregion


#region NPC API

func get_npc(character_id: String) -> NPCCharacter:
	return npc_manager.get_npc(character_id)


func get_all_npc_ids() -> Array[String]:
	return npc_manager.get_all_npc_ids()


func resolve_sender_name(sender_id: String) -> String:
	if sender_id == "player":
		var story_director: Node = get_node_or_null("/root/StoryDirector")
		if story_director != null and story_director.has_method("get_variable"):
			var nickname: String = str(story_director.get_variable("player_name", "")).strip_edges()
			if not nickname.is_empty():
				return nickname
		return "玩家"
	if sender_id == "system":
		return "系统"
	var npc := npc_manager.get_npc(sender_id)
	if npc:
		return npc.display_name
	return sender_id


## 将 display_name 或 character_id 统一解析为 character_id
func _resolve_character_id(raw_id: String) -> String:
	if npc_manager.get_npc(raw_id) != null:
		return raw_id
	var npc := npc_manager.find_npc_by_display_name(raw_id)
	if npc != null:
		return npc.character_id
	return raw_id

#endregion


#region Topic API

func activate_topic(topic: ChatTopic) -> bool:
	return topic_manager.activate_topic(topic)


func get_active_topic(channel_id: String) -> ChatTopic:
	return topic_manager.get_active_topic(channel_id)


func has_active_topic(channel_id: String) -> bool:
	return topic_manager.has_active_topic(channel_id)


func has_any_active_topics() -> bool:
	return not topic_manager.active_topics.is_empty()


func cancel_pending_ai_request(channel_id: String = "", reason: String = "cancelled") -> bool:
	if not _waiting_for_ai:
		return false
	var normalized_channel_id := channel_id.strip_edges()
	if not normalized_channel_id.is_empty() and _waiting_channel_id != normalized_channel_id:
		return false

	var cancelled_channel_id := _waiting_channel_id
	_clear_pending_wait_state()
	waiting_for_ai_changed.emit(false)
	_process_pending_timeout_followups()
	print("[ChatManager] Pending AI request cancelled for channel %s: %s" % [cancelled_channel_id, reason])
	return true


func begin_npc_message_presentation(channel_id: String) -> void:
	var normalized_channel_id := channel_id.strip_edges()
	if normalized_channel_id.is_empty():
		return

	var active_count := int(_active_npc_message_presentations.get(normalized_channel_id, 0))
	_active_npc_message_presentations[normalized_channel_id] = active_count + 1


func finish_npc_message_presentation(channel_id: String) -> void:
	var normalized_channel_id := channel_id.strip_edges()
	if normalized_channel_id.is_empty():
		return

	var active_count := int(_active_npc_message_presentations.get(normalized_channel_id, 0))
	if active_count <= 1:
		_active_npc_message_presentations.erase(normalized_channel_id)
		_flush_pending_protocol_effects(normalized_channel_id)
		_flush_pending_topic_completion(normalized_channel_id)
		return

	_active_npc_message_presentations[normalized_channel_id] = active_count - 1


func get_last_activated_topic_channel_id() -> String:
	return _last_activated_topic_channel_id


func is_waiting_for_ai() -> bool:
	return _waiting_for_ai


func get_waiting_channel_id() -> String:
	return _waiting_channel_id


## 测试用：创建并激活一个 Topic
func activate_test_topic(npc_id: String, channel_id: String, title: String, prompt: String) -> bool:
	var topic := ChatTopic.new()
	topic.topic_id = "test_%d" % int(Time.get_unix_time_from_system())
	topic.topic_type = "casual_interaction"
	topic.display_title = title
	topic.npc_id = npc_id
	topic.channel_id = channel_id
	topic.system_prompt = prompt
	topic.goal_description = ""
	topic.max_turns = 0
	topic.timeout_seconds = 0
	return topic_manager.activate_topic(topic)


func request_topic_npc_reply(
	channel_id: String,
	seed_message: String = "",
	auto_store: bool = true,
	complete_after_response: bool = true
) -> bool:
	if _waiting_for_ai:
		return false
	if not topic_manager.has_active_topic(channel_id):
		return false

	var messages: Array[String] = []
	var normalized_seed := seed_message.strip_edges()
	if not normalized_seed.is_empty():
		messages.append(normalized_seed)

	_on_batch_ready_for_channel(messages, channel_id, auto_store, complete_after_response)
	return true


#endregion


#region Moments API (朋友圈)

## 发布朋友圈动态（由 NPC 通过 Topic 系统或外部调用）
func post_moment(
	npc_id: String,
	content: String,
	image_hint: String = "",
	likes: int = 0,
	author_override: Dictionary = {}
) -> Dictionary:
	var author := _build_moment_author_snapshot(npc_id, author_override)
	var npc_name: String = str(author.get("display_name", npc_id)).strip_edges()

	var tm: Node = get_node_or_null("/root/TimeManager")
	var ts: int = tm.get_game_timestamp() if tm else int(Time.get_unix_time_from_system())
	var time_str: String = tm.format_time() if tm else ""

	var moment := {
		"id": "moment_%d_%d" % [ts, get_moments().size()],
		"npc_id": npc_id,
		"npc_name": npc_name,
		"author": author,
		"content": content,
		"image_hint": image_hint,
		"timestamp": ts,
		"time": time_str,
		"likes": likes,
		"liked_by_player": false,
		"comments": [] as Array[Dictionary],
	}
	if _state_store == null:
		return moment
	return _state_store.store_moment(moment)


func _build_moment_author_snapshot(npc_id: String, author_override: Dictionary = {}) -> Dictionary:
	var author: Dictionary = {
		"id": npc_id,
		"display_name": npc_id,
		"avatar_mode": "seed",
		"avatar_seed": npc_id,
	}
	var npc := npc_manager.get_npc(npc_id)
	if npc != null:
		author["display_name"] = str(npc.display_name).strip_edges()
		author["avatar_mode"] = "npc_ref"
		author["avatar_id"] = npc_id
		author["avatar_seed"] = str(npc.display_name).strip_edges()
	elif MOMENT_AUTHOR_PRESETS.has(npc_id):
		var preset: Dictionary = MOMENT_AUTHOR_PRESETS[npc_id]
		for key in preset:
			author[key] = preset[key]
	for key in author_override:
		author[key] = author_override[key]
	var display_name := str(author.get("display_name", "")).strip_edges()
	if display_name.is_empty():
		display_name = npc_id
	author["display_name"] = display_name
	var avatar_seed := str(author.get("avatar_seed", "")).strip_edges()
	if avatar_seed.is_empty():
		author["avatar_seed"] = display_name
	return author


## 玩家点赞
func like_moment(moment_id: String) -> void:
	if _state_store == null:
		return
	_state_store.like_moment(moment_id)


## 获取所有朋友圈动态
func get_moments() -> Array[Dictionary]:
	if _state_store == null:
		return []
	return _state_store.get_moments()


## 获取未读数
func get_moments_unread() -> int:
	if _state_store == null:
		return 0
	return _state_store.get_moments_unread()


## 清除未读
func clear_moments_unread() -> void:
	if _state_store == null:
		return
	_state_store.clear_moments_unread()


## 添加示例朋友圈（初始化用）
## 注意：这些是游戏开始前就存在的朋友圈，不应包含比赛相关内容
func _setup_default_moments() -> void:
	# 按时间从旧到新排列（post_moment 会 insert 到头部，所以最后 post 的显示在最上面）

	# --- 较早的动态 ---
	post_moment("npc_hs_liu", "入职第三个月终于不用天天加班到十点了（今天只加到九点半 [狗头]）。工资到手发现交完房租也没剩多少……成年人的世界果然没有容易二字",
		"昏暗的办公室工位，电脑屏幕亮着，桌上散落着空咖啡杯和零食包装袋。窗外是城市夜景。", 8)
	post_moment("npc_uni_wang", "保研上岸后的第一个长假！海边日落太美了🌊 大学最后一段自由时光，必须好好珍惜。",
		"金色的海边日落，沙滩上留下一串脚印，远处海平面上太阳正在下沉，天空被染成橙红色。手机自拍视角能看到一只举着冰淇淋的手。", 23)
	post_moment("npc_hs_sun", "今天背了8小时英语真题，政治肖四还没开始看。二战考研如果再考不上我就去送外卖了🆘 有没有研友给点精神支持",
		"凌晨的书桌，堆满了考研英语真题集、政治大纲和荧光笔。台灯发出暖黄色的光，旁边放着一杯已经凉了的速溶咖啡。", 6)
	post_moment("npc_mom", "和老姐妹们到了度假村！泡完温泉整个人都舒坦了，拍了好多照片回来给你看😊 你在学校要好好吃饭，别老吃外卖！",
		"几位中年女性穿着度假村浴袍在温泉池边合影，大家笑得很开心。背景是竹林和冒着热气的温泉水面。手机拍摄，构图略歪。", 15)
	post_moment("npc_hs_zhao", "省考倒计时42天。行测第267天打卡，正确率终于稳定在70+了😭 申论还是一塌糊涂……这辈子就和公务员考试死磕了。",
		"手机截图：一个学习打卡App的界面，显示'连续打卡267天'，今日学习时长8小时32分钟，正确率72%。", 3)
	post_moment("npc_classmate_a", "关于把蓝鲸大学称为985的问题，我必须再次严正声明：蓝鲸大学是全国顶尖三所高校之一，不是普通985。以下三种人最喜欢这么叫：1.自己母校是非顶尖985，想抱蓝大大腿掩盖差距的；2.自己是211及以下想缩小差距的自媒体博主；3.只知道青白985211分级的无知群众……（长文预警）",
		"", 18)
	post_moment("npc_classmate_b", "学校食堂三楼的麻辣香锅今天居然涨价了 这辈子有什么意义 活着有哪些用 人生到底在追求什么 我只是想吃个15块的麻辣香锅",
		"", 11)

	# --- 最近的动态（显示在最上面）---
	post_moment("npc_class_monitor", "毕业照预约开始了！23级的同学们记得在教务系统上选时间段，过期不候。另外学位服押金200，拍完退。",
		"教务系统截图，页面标题'2027届本科毕业生毕业照预约'，下方是按院系分列的时间段表格，部分热门时段已标红'已满'。", 26)
	post_moment("npc_lin_xia", "春天的南门银杏大道好好看……趁毕业前多拍几张",
		"一条铺满嫩绿银杏叶的校园大道，两侧是老旧的教学楼，阳光透过树叶洒下斑驳光影。画面温暖明亮，有种青春即将结束的朦胧感。", 12)
	post_moment("npc_mom", "转发：十种隔夜菜千万不能吃！第三种很多人天天在吃！！ \n\n你看看这个，外卖的东西真的不卫生",
		"一篇典型的养生公众号文章截图，标题用大红色加粗字体，配了一张食物图片。", 4)
	post_moment("npc_hs_sun", "凌晨3点 背完最后一套政治模拟题 窗外已经有鸟叫了 突然不知道自己为什么要这么拼",
		"深夜窗边，台灯照亮一摞书和笔记本。窗帘缝隙透出一丝灰蓝色的天光，桌面上有一个倒空的泡面桶。", 2)
	post_moment("npc_classmate_a", "转发一下：蓝鲸大学2027届本科生初次就业率达98.7%，位列全省高校第一。这是学校就业指导中心刚发布的数据。有些人总质疑我们学校的就业质量，数据摆在这里，请自行查阅。顶一个。",
		"一张蓝鲸大学官网就业数据统计图的截图，柱状图显示各年度就业率对比，蓝大始终在最高位。", 31)
	if _state_store != null:
		_state_store.set_moments_unread(12)


func _get_channel_messages_for_protocol(channel_id: String) -> Array[Dictionary]:
	if _state_store == null:
		return []
	return _state_store.get_channel_messages_copy(channel_id)

#endregion


#region Collaborator Project Context

func _should_use_collaborator_agent(channel: ChatChannel, npcs: Array[NPCCharacter]) -> bool:
	if collaborator_agent == null or not is_instance_valid(collaborator_agent):
		return false
	if channel == null:
		return false
	if npcs.size() != 1:
		return false
	var npc: NPCCharacter = npcs[0]
	return npc != null and npc.can_access_project_context()


func _build_project_context_for_channel(_channel: ChatChannel, npcs: Array[NPCCharacter], scan_text: String = "") -> String:
	if _project_context_builder == null or npcs.size() != 1:
		return ""
	return _project_context_builder.build_for_channel(_channel, npcs, scan_text)


func _build_project_context_for_chat(raw_npc: Variant, scan_text: String = "") -> String:
	if _project_context_builder == null:
		return ""
	return _project_context_builder.build_for_chat(raw_npc, scan_text)


func _build_dev_cycle_context_for_chat() -> String:
	if _project_context_builder == null:
		return "- 开发循环信息当前不可用"
	return _project_context_builder.build_dev_cycle_context()


func _build_work_order_context_for_chat() -> String:
	if _project_context_builder == null:
		return "- 当前无法读取工单摘要"
	return _project_context_builder.build_work_order_context()


func _build_kb_context_for_chat(scan_text: String = "") -> String:
	if _project_context_builder == null:
		return "- 当前知识库不可用"
	return _project_context_builder.build_kb_context(scan_text)


func _send_collaborator_agent_request(channel_id: String, prompt_data: Dictionary) -> bool:
	if collaborator_agent == null or not is_instance_valid(collaborator_agent):
		return false
	if collaborator_agent.is_busy():
		return false

	var prompt_messages: Variant = prompt_data.get("messages", [])
	if not (prompt_messages is Array) or (prompt_messages as Array).size() < 2:
		return false

	var messages: Array = prompt_messages
	var system_prompt: String = str((messages[0] as Dictionary).get("content", "")).strip_edges()
	var user_prompt: String = str((messages[1] as Dictionary).get("content", "")).strip_edges()
	if system_prompt.is_empty():
		return false

	collaborator_agent.reset()
	collaborator_agent.set_system_prompt_override(system_prompt)
	_pending_request_source = REQUEST_SOURCE_COLLABORATOR_AGENT
	_pending_request_id = collaborator_agent.send_message(user_prompt)
	if _pending_request_id.is_empty():
		_pending_request_source = ""
		return false

	print("[ChatManager] Sent request %s for channel %s via collaborator agent" % [_pending_request_id, channel_id])
	return true


func _collaborator_tool_get_dev_cycle_snapshot(_args: Dictionary) -> Dictionary:
	if _project_context_builder == null:
		return {"success": false, "error": "Project context builder not available."}
	return _project_context_builder.build_dev_cycle_snapshot()

#endregion


#region AI 调用流程

func _on_batch_ready(messages: Array[String]) -> void:
	var channel_id := _find_active_input_channel()
	if channel_id.is_empty():
		return
	_on_batch_ready_for_channel(messages, channel_id)


## 实际的 AI 调用逻辑（batch_ready 和 debug_mode 共用）
func _on_batch_ready_for_channel(
	messages: Array[String],
	channel_id: String,
	auto_store: bool = false,
	complete_after_response: bool = false
) -> void:
	var topic := topic_manager.get_active_topic(channel_id)

	# 非 debug 模式下必须有 topic
	if topic == null and not debug_mode:
		return

	# 记录轮数，仅用于展示与调试
	if topic:
		var _exceeded := topic_manager.increment_turn(topic)
		topic_manager.pause_topic_timeout(topic)

	# 收集频道内所有 NPC
	var channel_res: Resource = get_channel(channel_id)
	var channel: ChatChannel = channel_res as ChatChannel
	var npcs: Array[NPCCharacter] = []
	var primary_npc_id: String = topic.npc_id if topic else ""
	if channel:
		for member_id in channel.members:
			if member_id != "player" and member_id != "system":
				var npc := npc_manager.get_npc(member_id)
				if npc:
					npcs.append(npc)
				if primary_npc_id.is_empty():
					primary_npc_id = member_id

	# 构建 prompt（通过 PromptManager 模板）
	var chat_history: Array[Dictionary] = []
	if channel:
		chat_history.assign(channel.get_recent_messages(20))

	var relevant_memories := memory_manager.retrieve_memories(primary_npc_id, " ".join(messages), 5)
	# 给 KB 命中匹配用的扫描文本：玩家本轮消息 + 最近 chat_history + topic 文本
	var kb_scan_text := ChatProjectContextBuilderClass.build_chat_scan_text(chat_history, messages, topic)
	var project_shared_context := _build_project_context_for_channel(channel, npcs, kb_scan_text)
	var prompt_data := ChatPromptBuilder.build(
		channel,
		npcs,
		chat_history,
		messages,
		relevant_memories,
		topic,
		project_shared_context
	)

	# 设置等待状态
	_waiting_for_ai = true
	_waiting_channel_id = channel_id
	waiting_for_ai_changed.emit(true)

	# 调用 AI（传入 response_format）
	var options: Dictionary = {
		"source": "ChatManager",
		"role": "linkchat",
		"prompt_key": "linkchat_system",
	}
	if prompt_data.has("response_format"):
		options["response_format"] = prompt_data.response_format
	if topic != null:
		var meta: Dictionary = topic.context_data
		for key in ["source", "role", "prompt_key"]:
			var value := str(meta.get(key, "")).strip_edges()
			if not value.is_empty():
				options[key] = value
	_pending_auto_store_response = auto_store
	_pending_complete_topic_after_response = complete_after_response

	if _should_use_collaborator_agent(channel, npcs):
		if _send_collaborator_agent_request(channel_id, prompt_data):
			return
		push_warning("[ChatManager] Collaborator agent request setup failed, falling back to direct AIService")

	_pending_request_source = REQUEST_SOURCE_AI_SERVICE
	_pending_request_id = ai_service.chat(prompt_data.messages, options)
	print("[ChatManager] Sent request %s for channel %s via AIService" % [_pending_request_id, channel_id])


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if _pending_request_source != REQUEST_SOURCE_AI_SERVICE:
		return
	if request_id != _pending_request_id:
		return
	_handle_pending_ai_response(response)


func _on_ai_stream_completed(request_id: String, _full_content: String, response: Dictionary) -> void:
	if _pending_request_source != REQUEST_SOURCE_AI_SERVICE:
		return
	if request_id != _pending_request_id:
		return
	_handle_pending_ai_response(response)


func _handle_pending_ai_response(response: Dictionary) -> void:

	var channel_id := _waiting_channel_id
	var auto_store: bool = _pending_auto_store_response
	var complete_after_response: bool = _pending_complete_topic_after_response
	_pending_request_id = ""

	print("[ChatManager] AI full response BEGIN (%s)" % channel_id)
	print(JSON.stringify(response, "  "))
	print("[ChatManager] AI full response END (%s)" % channel_id)

	var extracted := _extract_ai_response_texts(response)
	var content_text: String = str(extracted.get("content", "")).strip_edges()
	var reasoning_text: String = str(extracted.get("thinking", "")).strip_edges()

	if content_text.is_empty():
		push_warning("[ChatManager] Empty AI response")
		var topic := topic_manager.get_active_topic(channel_id)
		_clear_pending_wait_state()
		waiting_for_ai_changed.emit(false)
		_restore_topic_timeout(topic)
		_process_pending_timeout_followups()
		return

	_finalize_ai_response(channel_id, content_text, reasoning_text, auto_store, complete_after_response)


func _extract_ai_response_texts(response: Dictionary) -> Dictionary:
	var content_text: String = ""
	var reasoning_text: String = ""
	var raw_content_text: String = ""
	if response.has("choices") and response.choices is Array and response.choices.size() > 0:
		var message: Dictionary = response.choices[0].get("message", {})
		raw_content_text = _content_value_to_text(message.get("content", null))
		content_text = AIService.extract_content(response)
		reasoning_text = AIService.extract_reasoning_content(response)
		if reasoning_text.is_empty() and not raw_content_text.is_empty():
			var raw_split := _strip_thinking_tags(raw_content_text)
			reasoning_text = str(raw_split.get("thinking", "")).strip_edges()
			if content_text.is_empty():
				content_text = str(raw_split.get("body", "")).strip_edges()
	return {
		"content": content_text,
		"thinking": reasoning_text,
		"raw_content": raw_content_text,
	}


func _content_value_to_text(content_value: Variant) -> String:
	if content_value is String:
		return content_value
	if content_value is Array:
		var parts: Array[String] = []
		for part in content_value:
			if part is String:
				parts.append(part)
			elif part is Dictionary:
				var part_type: String = str(part.get("type", ""))
				if part_type == "text":
					var text_value: Variant = part.get("text", "")
					if text_value is String and not text_value.is_empty():
						parts.append(text_value)
				elif part.has("content"):
					var nested_content: Variant = part.get("content", "")
					if nested_content is String and not nested_content.is_empty():
						parts.append(nested_content)
		return "".join(parts)
	return ""


func _on_collaborator_agent_message_completed(request_id: String, content: String) -> void:
	if _pending_request_source != REQUEST_SOURCE_COLLABORATOR_AGENT:
		return
	if request_id != _pending_request_id:
		return

	var channel_id := _waiting_channel_id
	var auto_store: bool = _pending_auto_store_response
	var complete_after_response: bool = _pending_complete_topic_after_response
	_pending_request_id = ""

	var content_text := content.strip_edges()
	if content_text.is_empty():
		push_warning("[ChatManager] Collaborator agent returned empty response")
		var topic := topic_manager.get_active_topic(channel_id)
		_clear_pending_wait_state()
		waiting_for_ai_changed.emit(false)
		_restore_topic_timeout(topic)
		_process_pending_timeout_followups()
		return

	_finalize_ai_response(channel_id, content_text, "", auto_store, complete_after_response)


func _finalize_ai_response(
	channel_id: String,
	content_text: String,
	reasoning_text: String,
	auto_store: bool,
	complete_after_response: bool
) -> void:
	print("[ChatManager] AI raw content BEGIN (%s)" % channel_id)
	print(content_text)
	print("[ChatManager] AI raw content END (%s)" % channel_id)

	# 优先读取结构化 reasoning_content；兼容旧链路时再回退剥离正文
	var stripped := _strip_thinking_tags(content_text)
	if reasoning_text == "":
		reasoning_text = str(stripped.get("thinking", "")).strip_edges()
	if reasoning_text != "":
		print("[ChatManager] LLM thinking: %s" % reasoning_text)

	var topic := topic_manager.get_active_topic(channel_id)

	# fallback npc_id：私聊时从频道成员推断
	var fallback_npc_id: String = topic.npc_id if topic else ""
	if fallback_npc_id.is_empty():
		var channel: Resource = get_channel(channel_id)
		if channel:
			for member_id in channel.members:
				if member_id != "player" and member_id != "system":
					fallback_npc_id = member_id
					break
	if fallback_npc_id.is_empty():
		fallback_npc_id = "unknown"

	var clean_body: String = str(stripped.body).strip_edges()
	var parsed_response := _parse_ai_response_text(clean_body, fallback_npc_id)
	var parsed_messages: Array[Dictionary] = []
	var raw_messages: Variant = parsed_response.get("messages", [])
	if raw_messages is Array:
		parsed_messages.assign(raw_messages)
	_append_required_topic_cards(parsed_messages, topic, fallback_npc_id)
	print("[ChatManager] Parsed response flags (%s): complete=%s failed=%s auto_store=%s complete_after_response=%s" % [
		channel_id,
		str(bool(parsed_response.get("topic_complete", false))),
		str(bool(parsed_response.get("topic_failed", false))),
		str(auto_store),
		str(complete_after_response),
	])
	if not parsed_messages.is_empty():
		print("[ChatManager] Parsed messages (%s): %s" % [channel_id, str(parsed_messages)])

	# 解析推荐回复
	var recommended_replies: Array[String] = []
	var raw_replies: Variant = parsed_response.get("recommended_replies", [])
	if raw_replies is Array:
		recommended_replies.assign(raw_replies)
	var topic_complete_from_protocol: bool = bool(parsed_response.get("topic_complete", false))
	var topic_failed_from_protocol: bool = bool(parsed_response.get("topic_failed", false))
	var topic_summary_from_protocol := str(parsed_response.get("topic_summary", "")).strip_edges()
	var parsed_events: Array[Dictionary] = []
	var raw_events: Variant = parsed_response.get("events", [])
	if raw_events is Array:
		parsed_events.assign(raw_events)
	var parsed_actions: Array[Dictionary] = []
	var raw_actions: Variant = parsed_response.get("actions", [])
	if raw_actions is Array:
		parsed_actions.assign(raw_actions)

	var stored_messages: Array[Dictionary] = []

	# ChatManager 始终负责存储消息（业务逻辑不依赖 UI）
	for msg in parsed_messages:
		var stored_message := store_npc_message_data(channel_id, msg)
		if not stored_message.is_empty():
			stored_messages.append(stored_message)

	# 通知 UI 做打字机动画（纯展示信号，无业务逻辑）
	# auto_store 路径的调用方不需要 UI 动画，跳过 emit
	if not auto_store:
		npc_messages_received.emit(channel_id, stored_messages, recommended_replies)

	if topic:
		var immediate_effects := _split_protocol_effects_by_timing(parsed_events, parsed_actions, "immediate")
		var immediate_events: Array[Dictionary] = []
		var raw_immediate_events: Variant = immediate_effects.get("events", [])
		if raw_immediate_events is Array:
			immediate_events.assign(raw_immediate_events)
		var immediate_actions: Array[Dictionary] = []
		var raw_immediate_actions: Variant = immediate_effects.get("actions", [])
		if raw_immediate_actions is Array:
			immediate_actions.assign(raw_immediate_actions)
		_execute_protocol_effects(topic, immediate_events, immediate_actions)

		var deferred_effects := _split_protocol_effects_by_timing(parsed_events, parsed_actions, "after_messages")
		var deferred_events: Array[Dictionary] = []
		var raw_deferred_events: Variant = deferred_effects.get("events", [])
		if raw_deferred_events is Array:
			deferred_events.assign(raw_deferred_events)
		var deferred_actions: Array[Dictionary] = []
		var raw_deferred_actions: Variant = deferred_effects.get("actions", [])
		if raw_deferred_actions is Array:
			deferred_actions.assign(raw_deferred_actions)
		_request_protocol_effects(channel_id, topic, deferred_events, deferred_actions)

	var completion_requested: bool = false

	# 结束等待
	_clear_pending_wait_state()
	waiting_for_ai_changed.emit(false)

	# 检查 Topic 完成
	if topic and complete_after_response:
		var topic_result := {"messages": parsed_messages}
		if not topic_summary_from_protocol.is_empty():
			topic_result["summary"] = topic_summary_from_protocol
		if topic_failed_from_protocol:
			topic_result["topic_failed"] = true
		_request_topic_completion(channel_id, topic, topic_result)
		completion_requested = true
		_process_pending_timeout_followups()
		return

	if topic:
		var has_complete_marker := topic_complete_from_protocol or _messages_have_complete_marker(parsed_messages)
		if has_complete_marker:
			var topic_result := {"messages": parsed_messages}
			if not topic_summary_from_protocol.is_empty():
				topic_result["summary"] = topic_summary_from_protocol
			if topic_failed_from_protocol:
				topic_result["topic_failed"] = true
			_request_topic_completion(channel_id, topic, topic_result)
			completion_requested = true

	if topic and not completion_requested:
		_restore_topic_timeout(topic)

	_process_pending_timeout_followups()

func _clear_pending_wait_state() -> void:
	_waiting_for_ai = false
	_waiting_channel_id = ""
	_pending_request_id = ""
	_pending_request_source = ""
	_pending_auto_store_response = false
	_pending_complete_topic_after_response = false


func _restore_topic_timeout(topic: ChatTopic) -> void:
	if topic == null or not topic.is_active:
		return
	topic_manager.restart_topic_timeout(topic)


func _queue_timeout_followup(topic: ChatTopic) -> void:
	if topic == null or not topic.is_active:
		return
	_pending_timeout_followups[topic.channel_id] = topic.topic_id


func _process_pending_timeout_followups() -> void:
	if _waiting_for_ai:
		return

	var pending_channels: Array = _pending_timeout_followups.keys()
	for channel_id_variant in pending_channels:
		if _waiting_for_ai:
			return
		var channel_id := str(channel_id_variant).strip_edges()
		var topic_id := str(_pending_timeout_followups.get(channel_id, "")).strip_edges()
		var topic: ChatTopic = topic_manager.get_active_topic(channel_id)
		if topic == null or not topic.is_active or topic.topic_id != topic_id:
			_pending_timeout_followups.erase(channel_id)
			continue
		if _request_timeout_followup(topic):
			_pending_timeout_followups.erase(channel_id)


func _request_timeout_followup(topic: ChatTopic) -> bool:
	if topic == null or not topic.is_active:
		return false
	var context_data: Dictionary = topic.context_data.duplicate(true)
	context_data["timeout_followup_count"] = int(context_data.get("timeout_followup_count", 0)) + 1
	topic.context_data = context_data
	# 向频道历史注入 AI 可见的沉默标记（UI 不渲染）
	var channel: Resource = get_channel(topic.channel_id)
	if channel:
		var ch := channel as ChatChannel
		if ch:
			ch.add_message("system", "系统", "[玩家较长时间未回复]", {"ai_only": true})
	var seed_message := str(topic.context_data.get("timeout_seed_message", TOPIC_TIMEOUT_CONTINUE_SEED)).strip_edges()
	return request_topic_npc_reply(topic.channel_id, seed_message, false, false)


func _request_topic_completion(channel_id: String, topic: ChatTopic, result: Dictionary) -> void:
	if topic == null or not topic.is_active:
		return

	var normalized_channel_id := channel_id.strip_edges()
	if _is_npc_message_presentation_active(normalized_channel_id):
		_pending_topic_completions[normalized_channel_id] = {
			"topic": topic,
			"result": result.duplicate(true),
		}
		return

	topic_manager.complete_topic(topic, result)


func _is_npc_message_presentation_active(channel_id: String) -> bool:
	return int(_active_npc_message_presentations.get(channel_id, 0)) > 0


func _flush_pending_topic_completion(channel_id: String) -> void:
	if not _pending_topic_completions.has(channel_id):
		return

	var pending: Variant = _pending_topic_completions.get(channel_id, {})
	_pending_topic_completions.erase(channel_id)
	if not pending is Dictionary:
		return

	var topic: ChatTopic = pending.get("topic", null)
	if topic == null or not topic.is_active:
		return

	var result: Dictionary = pending.get("result", {})
	topic_manager.complete_topic(topic, result)


func _request_protocol_effects(
	channel_id: String,
	topic: ChatTopic,
	events: Array[Dictionary],
	actions: Array[Dictionary]
) -> void:
	if topic == null or (events.is_empty() and actions.is_empty()):
		return

	var normalized_channel_id := channel_id.strip_edges()
	if _is_npc_message_presentation_active(normalized_channel_id):
		_pending_protocol_effects[normalized_channel_id] = {
			"topic": topic,
			"events": events.duplicate(true),
			"actions": actions.duplicate(true),
		}
		return

	_execute_protocol_effects(topic, events, actions)


func _flush_pending_protocol_effects(channel_id: String) -> void:
	if not _pending_protocol_effects.has(channel_id):
		return

	var pending: Variant = _pending_protocol_effects.get(channel_id, {})
	_pending_protocol_effects.erase(channel_id)
	if not pending is Dictionary:
		return

	var topic: ChatTopic = pending.get("topic", null)
	if topic == null or not topic.is_active:
		return

	var events: Array[Dictionary] = []
	var raw_events: Variant = pending.get("events", [])
	if raw_events is Array:
		events.assign(raw_events)

	var actions: Array[Dictionary] = []
	var raw_actions: Variant = pending.get("actions", [])
	if raw_actions is Array:
		actions.assign(raw_actions)

	_execute_protocol_effects(topic, events, actions)


func _execute_protocol_effects(topic: ChatTopic, events: Array[Dictionary], actions: Array[Dictionary]) -> void:
	if _protocol_executor == null:
		return
	_protocol_executor.execute_effects(topic, events, actions)


func _split_protocol_effects_by_timing(
	events: Array[Dictionary],
	actions: Array[Dictionary],
	timing: String
) -> Dictionary:
	var normalized_timing := _normalize_protocol_timing(timing)
	var filtered_events: Array[Dictionary] = []
	for event_data in events:
		if _normalize_protocol_timing(str(event_data.get("timing", "after_messages"))) != normalized_timing:
			continue
		filtered_events.append(event_data.duplicate(true))

	var filtered_actions: Array[Dictionary] = []
	for action in actions:
		if _normalize_protocol_timing(str(action.get("timing", "after_messages"))) != normalized_timing:
			continue
		filtered_actions.append(action.duplicate(true))

	return {
		"events": filtered_events,
		"actions": filtered_actions,
	}


func _normalize_protocol_timing(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	match normalized:
		"immediate":
			return "immediate"
		_:
			return "after_messages"


func _append_required_topic_cards(parsed_messages: Array[Dictionary], topic: ChatTopic, fallback_npc_id: String) -> void:
	if topic == null:
		return

	var raw_cards: Variant = topic.context_data.get("required_cards", [])
	if not (raw_cards is Array):
		return

	for raw_card in raw_cards:
		if not (raw_card is Dictionary):
			continue
		var sanitized_card := _sanitize_message_card(raw_card as Dictionary)
		if sanitized_card.is_empty():
			continue
		if _parsed_messages_have_card(parsed_messages, sanitized_card):
			continue
		parsed_messages.append({
			"speaker": fallback_npc_id,
			"content": "",
			"card": sanitized_card,
		})


func _parsed_messages_have_card(parsed_messages: Array[Dictionary], target_card: Dictionary) -> bool:
	for message in parsed_messages:
		if not message.has("card"):
			continue
		var existing_card: Variant = message.get("card", {})
		if not (existing_card is Dictionary):
			continue
		if _cards_match(existing_card as Dictionary, target_card):
			return true
	return false


func _cards_match(left: Dictionary, right: Dictionary) -> bool:
	if str(left.get("type", "")) != str(right.get("type", "")):
		return false

	var left_url := str(left.get("url", "")).strip_edges()
	var right_url := str(right.get("url", "")).strip_edges()
	if not left_url.is_empty() or not right_url.is_empty():
		return left_url == right_url

	var left_image := str(left.get("image_id", "")).strip_edges()
	var right_image := str(right.get("image_id", "")).strip_edges()
	if not left_image.is_empty() or not right_image.is_empty():
		return left_image == right_image

	return str(left.get("title", "")).strip_edges() == str(right.get("title", "")).strip_edges()


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if _pending_request_source != REQUEST_SOURCE_AI_SERVICE:
		return
	if request_id != _pending_request_id:
		return

	_fail_pending_ai_request(request_id, error)


func _on_collaborator_agent_message_failed(request_id: String, error: String) -> void:
	if _pending_request_source != REQUEST_SOURCE_COLLABORATOR_AGENT:
		return
	if request_id != _pending_request_id:
		return

	_fail_pending_ai_request(request_id, error)


func _fail_pending_ai_request(_request_id: String, error: String) -> void:
	_pending_request_id = ""
	var channel_id := _waiting_channel_id
	var complete_after_response: bool = _pending_complete_topic_after_response
	var failed_topic: ChatTopic = topic_manager.get_active_topic(channel_id)

	_clear_pending_wait_state()
	waiting_for_ai_changed.emit(false)

	if complete_after_response and failed_topic != null:
		topic_manager.cancel_topic(failed_topic, "ai_request_failed")
	elif failed_topic != null:
		_restore_topic_timeout(failed_topic)

	_process_pending_timeout_followups()

	add_system_message(channel_id, "[错误] AI请求失败: %s" % error)
	ai_request_failed.emit(channel_id, error)
	push_warning("[ChatManager] AI request failed: %s" % error)

#endregion


#region Topic 信号转发

func _on_topic_activated(topic: ChatTopic) -> void:
	_last_activated_topic_channel_id = topic.channel_id
	var suppress_notice: bool = bool(topic.context_data.get("suppress_system_notice", false))
	if not suppress_notice:
		add_system_message(topic.channel_id, "[话题开始] %s" % topic.display_title)
	_emit_chat_state_changed()
	topic_activated.emit(topic)


func _on_topic_completed(topic: ChatTopic, result: Dictionary) -> void:
	_pending_topic_completions.erase(topic.channel_id)
	_pending_protocol_effects.erase(topic.channel_id)
	_pending_timeout_followups.erase(topic.channel_id)
	var suppress_notice: bool = bool(topic.context_data.get("suppress_system_notice", false))
	if not suppress_notice:
		add_system_message(topic.channel_id, "[话题结束] %s" % topic.display_title)

	# 记忆整合已移至每日结束时的 DailyMemorySummarizer，不再在 topic 完成时即时存储

	_emit_chat_state_changed()
	topic_completed.emit(topic, result)


func _on_topic_timeout(topic: ChatTopic) -> void:
	_queue_timeout_followup(topic)
	_process_pending_timeout_followups()
	_emit_chat_state_changed()
	topic_timeout.emit(topic)


func _on_topic_cancelled(topic: ChatTopic, reason: String) -> void:
	_pending_topic_completions.erase(topic.channel_id)
	_pending_protocol_effects.erase(topic.channel_id)
	_pending_timeout_followups.erase(topic.channel_id)
	var suppress_notice: bool = bool(topic.context_data.get("suppress_system_notice", false))
	if not suppress_notice:
		add_system_message(topic.channel_id, "[话题取消] %s" % topic.display_title)
	_emit_chat_state_changed()
	topic_cancelled.emit(topic, reason)

#endregion


#region 每日对话重置

func _on_day_changed(_new_day: int) -> void:
	# DailyMemorySummarizer 已先于此回调连接 day_changed，
	# 它在同步阶段就已收集完前一天的消息数据，此处可安全清空。
	_clear_all_channel_messages()


## 清空所有频道的消息历史和未读计数
func _clear_all_channel_messages() -> void:
	if _state_store == null:
		return
	var cleared_count: int = _state_store.clear_all_channel_messages()
	if cleared_count > 0:
		print("[ChatManager] Day transition: cleared messages in %d channel(s)" % cleared_count)

#endregion


#region Persistence

func get_run_state() -> Dictionary:
	if _state_store == null:
		return {}
	return _state_store.build_run_state(_last_activated_topic_channel_id, topic_manager, debug_mode)


func load_run_state(data: Dictionary) -> bool:
	if data.is_empty():
		return true
	_reset_runtime_transients()
	if memory_manager != null and memory_manager.has_method("reset_runtime_state"):
		memory_manager.reset_runtime_state(false)
	if _state_store != null:
		var restored: Dictionary = _state_store.load_run_state(data, debug_mode, topic_manager)
		_last_activated_topic_channel_id = str(restored.get("last_activated_topic_channel_id", "")).strip_edges()
		debug_mode = bool(restored.get("debug_mode", debug_mode))
	return true


func reset_runtime_state(reset_memory: bool = false) -> void:
	_reset_runtime_transients()
	if topic_manager != null and topic_manager.has_method("reset_runtime_state"):
		topic_manager.reset_runtime_state(true)
	if reset_memory and memory_manager != null and memory_manager.has_method("reset_runtime_state"):
		memory_manager.reset_runtime_state(true)
	if _state_store != null:
		_state_store.reset_runtime_state(false)
	_last_activated_topic_channel_id = ""
	debug_mode = false
	_setup_default_channels()
	_setup_default_moments()


func _serialize_channels() -> Array[Dictionary]:
	if _state_store == null:
		return []
	return _state_store.serialize_channels()


func _restore_channels(channels_state: Variant) -> void:
	if _state_store == null:
		return
	_state_store.restore_channels(channels_state, debug_mode)


func _restore_moments(moments_state: Variant) -> void:
	if _state_store == null:
		return
	_state_store.restore_moments(moments_state, debug_mode)


func _reset_runtime_transients() -> void:
	_waiting_for_ai = false
	_waiting_channel_id = ""
	_pending_request_id = ""
	_pending_request_source = ""
	_pending_auto_store_response = false
	_pending_complete_topic_after_response = false
	_active_npc_message_presentations.clear()
	_pending_topic_completions.clear()
	_pending_protocol_effects.clear()
	_pending_timeout_followups.clear()
	if collaborator_agent != null and is_instance_valid(collaborator_agent):
		collaborator_agent.reset()


func _emit_chat_state_changed() -> void:
	chat_state_changed.emit()

#endregion


#region 辅助

## 找到当前有 active topic 的频道（用于 batch_ready 时确定目标频道）
## 简单策略：遍历所有频道，返回第一个有 active topic 的
## 实际使用中同一时间通常只有一个频道在活跃对话
func _find_active_input_channel() -> String:
	for cid in get_channel_order():
		if topic_manager.has_active_topic(cid):
			return cid
	return ""

#endregion


#region AI 响应解析辅助

## 剥离 <thinking>...</thinking> 标签，返回 {thinking: String, body: String}
func _strip_thinking_tags(text: String) -> Dictionary:
	if _response_parser == null:
		return {"thinking": "", "body": text}
	return _response_parser.strip_thinking_tags(text)


func _parse_ai_response_text(text: String, fallback_npc_id: String) -> Dictionary:
	if _response_parser == null:
		return {
			"messages": [],
			"recommended_replies": [],
			"topic_complete": false,
			"topic_summary": "",
			"events": [],
			"actions": [],
		}
	return _response_parser.parse_ai_response_text(text, fallback_npc_id)


func _parse_line_protocol_response(text: String, fallback_npc_id: String) -> Dictionary:
	if _response_parser == null:
		return {
			"valid": false,
			"messages": [],
			"recommended_replies": [],
			"topic_complete": false,
			"topic_failed": false,
			"topic_summary": "",
			"events": [],
			"actions": [],
		}
	return _response_parser.parse_line_protocol_response(text, fallback_npc_id)


func _messages_have_complete_marker(messages: Array[Dictionary]) -> bool:
	if _response_parser == null:
		return false
	return _response_parser.messages_have_complete_marker(messages)


#endregion
