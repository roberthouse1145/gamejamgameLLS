extends Node
## ChatManager — 聊天数据层 autoload
## 持有频道、消息、NPC、Topic、记忆、AI服务等所有聊天数据
## LinkChatApp 只做 UI 渲染，从此处读取数据和监听信号

# Preload classes
const NPCManagerClass = preload("res://scripts/chat/npc_manager.gd")
const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")
const NPCCharacterClass = preload("res://scripts/chat/resources/npc_character.gd")

const LINKCHAT_IMAGE_CARD_REGISTRY_PATH: String = "res://resources/data/linkchat_image_cards.json"

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
#endregion

#region 子系统
var topic_manager: TopicManager
var batch_handler: MessageBatchHandler
var memory_manager: MemoryManager
var ai_service: AIService
var npc_manager: NPCManager
#endregion

#region 数据
## channel_id -> ChatChannel
var _channels: Dictionary = {}
## 频道顺序
var _channel_order: Array[String] = []
## 是否正在等待 AI 回复
var _waiting_for_ai: bool = false
## 当前等待 AI 的频道
var _waiting_channel_id: String = ""
## 当前 pending 的 AI 请求 ID
var _pending_request_id: String = ""
var _pending_auto_store_response: bool = false
var _pending_complete_topic_after_response: bool = false
## channel_id -> UI presentation count
var _active_npc_message_presentations: Dictionary = {}
## channel_id -> {topic: ChatTopic, result: Dictionary}
var _pending_topic_completions: Dictionary = {}
var _pending_protocol_effects: Dictionary = {}
## 朋友圈动态列表
var _moments: Array[Dictionary] = []
## 朋友圈未读数
var _moments_unread: int = 0
## image_id -> card definition
var _image_card_registry: Dictionary = {}
## 最近一次被激活的话题频道，供 LinkChat 启动时优先选中
var _last_activated_topic_channel_id: String = ""
## Debug模式：无需Topic即可聊天，消息立即发送给AI
var debug_mode: bool = true
#endregion


func _ready() -> void:
	_setup_subsystems()
	_setup_connections()
	_load_linkchat_image_card_registry()
	_setup_npcs()
	_setup_default_channels()
	_setup_default_moments()


func _setup_subsystems() -> void:
	topic_manager = TopicManager.new()
	add_child(topic_manager)

	batch_handler = MessageBatchHandler.new()
	add_child(batch_handler)

	memory_manager = MemoryManager.new()
	add_child(memory_manager)

	ai_service = AIService.new()
	add_child(ai_service)

	npc_manager = NPCManagerClass.new()

	# 加载 AI 配置
	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		config_mgr.apply_to_service(ai_service, "linkchat")
		print("[ChatManager] AI config loaded")
	else:
		push_warning("[ChatManager] Failed to load AI config")


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

	# AI
	ai_service.request_completed.connect(_on_ai_request_completed)
	ai_service.request_failed.connect(_on_ai_request_failed)


func _setup_npcs() -> void:
	# 1. 注册核心角色 林夏
	var lin_xia := NPCCharacterClass.new()
	lin_xia.character_id = "npc_lin_xia"
	lin_xia.display_name = "林夏"
	lin_xia.initial_affection = 75
	
	# 利用 PromptManager 获取人设文本
	var pm: Node = Engine.get_main_loop().root.get_node_or_null("PromptManager")
	if pm and pm.has_prompt("npc/lin_xia"):
		lin_xia.prompt = pm.resolve("npc/lin_xia")
	else:
		push_warning("[ChatManager] Lin Xia prompt not found in PromptManager")
		
	npc_manager.register_npc(lin_xia)
	print("[ChatManager] Registered %d NPCs" % npc_manager.get_all_npc_ids().size())


func _setup_default_channels() -> void:
	add_channel("dm_lin_xia", "林夏", ChatChannelClass.ChannelType.DM,
		["player", "npc_lin_xia"])
	add_channel("agj_official", "AGJ2025线上官方交流群", ChatChannelClass.ChannelType.SYSTEM,
		["player"])
	add_channel("class_group", "22软工吃喝拉撒群", ChatChannelClass.ChannelType.SOCIAL,
		["player"])
		
	# 读取频道背景设定并赋值
	var file := FileAccess.open("res://resources/data/channel_contexts.json", FileAccess.READ)
	if file:
		var json_str := file.get_as_text()
		var json_data: Variant = JSON.parse_string(json_str)
		if json_data is Array:
			for item in json_data:
				var cid: String = item.get("channel_id", "")
				var channel = _channels.get(cid)
				if channel:
					channel.channel_prompt = item.get("channel_prompt", "")
		else:
			push_error("[ChatManager] Error parsing channel_contexts.json")
		file.close()


#region 频道 API

func add_channel(channel_id: String, display_name: String, channel_type: int, members_list: Array) -> void:
	var channel := ChatChannelClass.new()
	channel.channel_id = channel_id
	channel.display_name = display_name
	channel.channel_type = channel_type as ChatChannelClass.ChannelType
	channel.members.assign(members_list)

	_channels[channel_id] = channel
	_channel_order.append(channel_id)
	channel_added.emit(channel_id)
	_emit_chat_state_changed()


func get_channel(channel_id: String) -> Resource:
	return _channels.get(channel_id)


func get_channel_order() -> Array[String]:
	return _channel_order


func get_channels() -> Dictionary:
	return _channels

#endregion


#region 消息 API

## 玩家发送消息（进入批处理队列 + 立即存储到频道）
## debug_mode 下跳过批处理，直接触发 AI
func add_player_message(channel_id: String, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_store_message(channel_id, "player", text)
	if debug_mode:
		_on_batch_ready_for_channel([text], channel_id)
	else:
		batch_handler.add_message(text)


func store_player_message_data(channel_id: String, message_data: Dictionary) -> void:
	_store_message_data(channel_id, "player", message_data)


## 系统消息（直接存储）
func add_system_message(channel_id: String, text: String) -> void:
	_store_message(channel_id, "system", text)


func add_system_message_data(channel_id: String, message_data: Dictionary) -> void:
	_store_message_data(channel_id, "system", message_data)


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
		"content": "我拍给你看。",
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
		"content": "你先看这个页面。",
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
func store_npc_message(channel_id: String, npc_id: String, content: String) -> void:
	var clean_content := NPCResponseHandler.clean_message(content)
	_store_message(channel_id, npc_id, clean_content)


func store_npc_message_data(channel_id: String, message_data: Dictionary) -> void:
	var normalized := message_data.duplicate(true)
	if normalized.has("content"):
		normalized["content"] = NPCResponseHandler.clean_message(str(normalized.get("content", "")))
	_store_message_data(channel_id, str(normalized.get("speaker", normalized.get("sender_id", "unknown"))), normalized)


## 内部：存储消息到频道并发信号
func _store_message(channel_id: String, sender_id: String, content: String) -> void:
	_store_message_data(channel_id, sender_id, {"content": content})


func _store_message_data(channel_id: String, sender_id: String, message_data: Dictionary) -> void:
	var channel: Resource = _channels.get(channel_id)
	if channel == null:
		return
	var normalized := _normalize_message_data(sender_id, message_data)
	var actual_sender_id := str(normalized.get("speaker", sender_id)).strip_edges()
	if actual_sender_id.is_empty():
		actual_sender_id = sender_id
	var sender_name := resolve_sender_name(actual_sender_id)
	var content := str(normalized.get("content", ""))
	if content.strip_edges().is_empty() and (not normalized.has("card") or (normalized["card"] as Dictionary).is_empty()):
		return
	var extras := normalized.duplicate(true)
	extras.erase("speaker")
	extras.erase("content")
	var msg: Dictionary = channel.add_message(actual_sender_id, sender_name, content, extras)
	message_added.emit(channel_id, msg)
	_emit_chat_state_changed()


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
	return normalized


func _sanitize_message_card(card: Dictionary) -> Dictionary:
	var card_type := str(card.get("type", "")).strip_edges().to_lower()
	if card_type.is_empty():
		return {}
	var sanitized: Dictionary = {"type": card_type}
	var allowed_keys := [
		"title", "subtitle", "hint", "body", "footer", "badge", "image_id", "image_path",
		"texture_path", "url", "theme", "design_prompt", "caption", "alt",
		"site_name", "accent_color", "preview_width", "preview_height"
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
		return "玩家"
	if sender_id == "system":
		return "系统"
	var npc := npc_manager.get_npc(sender_id)
	if npc:
		return npc.display_name
	return sender_id

#endregion


#region Topic API

func activate_topic(topic: ChatTopic) -> bool:
	return topic_manager.activate_topic(topic)


func get_active_topic(channel_id: String) -> ChatTopic:
	return topic_manager.get_active_topic(channel_id)


func has_active_topic(channel_id: String) -> bool:
	return topic_manager.has_active_topic(channel_id)


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
func post_moment(npc_id: String, content: String, image_hint: String = "", likes: int = 0) -> Dictionary:
	var npc := npc_manager.get_npc(npc_id)
	var npc_name: String = npc.display_name if npc else npc_id

	var tm: Node = get_node_or_null("/root/TimeManager")
	var ts: int = tm.get_game_timestamp() if tm else int(Time.get_unix_time_from_system())
	var time_str: String = tm.format_time() if tm else ""

	var moment := {
		"id": "moment_%d_%d" % [ts, _moments.size()],
		"npc_id": npc_id,
		"npc_name": npc_name,
		"content": content,
		"image_hint": image_hint,
		"timestamp": ts,
		"time": time_str,
		"likes": likes,
		"liked_by_player": false,
		"comments": [] as Array[Dictionary],
	}
	_moments.insert(0, moment) # 最新的在前面
	_moments_unread += 1
	moment_posted.emit(moment)
	_emit_chat_state_changed()
	return moment


## 玩家点赞
func like_moment(moment_id: String) -> void:
	for m in _moments:
		if m.id == moment_id:
			if not m.liked_by_player:
				m.liked_by_player = true
				m.likes += 1
				_emit_chat_state_changed()
			return


## 获取所有朋友圈动态
func get_moments() -> Array[Dictionary]:
	return _moments


## 获取未读数
func get_moments_unread() -> int:
	return _moments_unread


## 清除未读
func clear_moments_unread() -> void:
	_moments_unread = 0
	_emit_chat_state_changed()


## 添加示例朋友圈（初始化用）
func _setup_default_moments() -> void:
	post_moment("npc_lin_xia", "报名了！AGJ 2025 新星赛道，两个人的队伍，冲冲冲💪", "", 8)
	post_moment("npc_agj_assist", "【赛事公告】Lumina Engine v3.2 已正式下发至各参赛队伍工作流！祝各位好运！", "", 128)
	post_moment("npc_classmate_a", "绝望了，剧本写了三版都被策划毙了，我这头发还能留到毕业吗...", "", 5)
	post_moment("npc_classmate_b", "兄弟们听说最近很火的那个克苏鲁缝合消除游戏没？感觉有搞头，我准备在这次jam里抄一个 [狗头]", "", 2)
	post_moment("npc_class_monitor", "明天老李的软件原理课要点名，选了这门课的兄弟别睡过头了。", "", 32)
	post_moment("npc_lin_xia", "Lumina Engine 的文档好厚……今晚先啃完官方教程再说", "", 3)
	_moments_unread = 6

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

	# 增加轮数
	if topic:
		var _exceeded := topic_manager.increment_turn(topic)

	# 收集频道内所有 NPC
	var channel_res: Resource = _channels.get(channel_id)
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
	var prompt_data := ChatPromptBuilder.build(channel, npcs, chat_history, messages, relevant_memories, topic)

	# 设置等待状态
	_waiting_for_ai = true
	_waiting_channel_id = channel_id
	waiting_for_ai_changed.emit(true)

	# 调用 AI（传入 response_format）
	var options: Dictionary = {}
	if prompt_data.has("response_format"):
		options["response_format"] = prompt_data.response_format
	_pending_auto_store_response = auto_store
	_pending_complete_topic_after_response = complete_after_response
	_pending_request_id = ai_service.chat(prompt_data.messages, options)
	print("[ChatManager] Sent request %s for channel %s" % [_pending_request_id, channel_id])


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_request_id:
		return

	_pending_request_id = ""
	var channel_id := _waiting_channel_id

	# 提取 content
	var content_text: String = ""
	if response.has("choices") and response.choices is Array and response.choices.size() > 0:
		var message_data: Dictionary = response.choices[0].get("message", {})
		var raw_content: Variant = message_data.get("content", null)
		if raw_content != null:
			content_text = str(raw_content)

	if content_text.is_empty():
		push_warning("[ChatManager] Empty AI response")
		_waiting_for_ai = false
		_waiting_channel_id = ""
		_pending_auto_store_response = false
		_pending_complete_topic_after_response = false
		waiting_for_ai_changed.emit(false)
		return

	print("[ChatManager] AI response: %s" % content_text)

	# 剥离 <thinking> 标签并记录思考内容
	var stripped := _strip_thinking_tags(content_text)
	if stripped.thinking != "":
		print("[ChatManager] LLM thinking: %s" % stripped.thinking)

	var topic := topic_manager.get_active_topic(channel_id)

	# fallback npc_id：私聊时从频道成员推断
	var fallback_npc_id: String = topic.npc_id if topic else ""
	if fallback_npc_id.is_empty():
		var channel: Resource = _channels.get(channel_id)
		if channel:
			for member_id in channel.members:
				if member_id != "player" and member_id != "system":
					fallback_npc_id = member_id
					break
	if fallback_npc_id.is_empty():
		fallback_npc_id = "unknown"

	var clean_body: String = str(stripped.body).strip_edges()
	var parsed_response := _parse_ai_response_text(clean_body, fallback_npc_id)
	var parsed_messages: Array[Dictionary] = parsed_response.get("messages", [])
	_append_required_topic_cards(parsed_messages, topic, fallback_npc_id)

	# 解析推荐回复
	var recommended_replies: Array[String] = parsed_response.get("recommended_replies", [])
	var topic_complete_from_protocol: bool = bool(parsed_response.get("topic_complete", false))
	var topic_summary_from_protocol := str(parsed_response.get("topic_summary", "")).strip_edges()
	var parsed_events: Array[Dictionary] = []
	var raw_events: Variant = parsed_response.get("events", [])
	if raw_events is Array:
		parsed_events.assign(raw_events)
	var parsed_actions: Array[Dictionary] = []
	var raw_actions: Variant = parsed_response.get("actions", [])
	if raw_actions is Array:
		parsed_actions.assign(raw_actions)

	# 发信号给 UI 做打字机动画
	var auto_store: bool = _pending_auto_store_response
	var complete_after_response: bool = _pending_complete_topic_after_response
	_pending_auto_store_response = false
	_pending_complete_topic_after_response = false

	# ChatManager 始终负责存储消息（业务逻辑不依赖 UI）
	for msg in parsed_messages:
		store_npc_message_data(channel_id, msg)

	# 通知 UI 做打字机动画（纯展示信号，无业务逻辑）
	# auto_store 路径的调用方不需要 UI 动画，跳过 emit
	if not auto_store:
		npc_messages_received.emit(channel_id, parsed_messages, recommended_replies)

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

	# 结束等待
	_waiting_for_ai = false
	_waiting_channel_id = ""
	_pending_auto_store_response = false
	_pending_complete_topic_after_response = false
	waiting_for_ai_changed.emit(false)

	# 检查 Topic 完成
	if topic and complete_after_response:
		var summary := topic_summary_from_protocol
		if summary.is_empty():
			summary = _extract_topic_summary_from_messages(parsed_messages)
		var topic_result := {"messages": parsed_messages, "summary": summary}
		_request_topic_completion(channel_id, topic, topic_result)
		return

	if topic and not debug_mode:
		var has_complete_marker := topic_complete_from_protocol or _messages_have_complete_marker(parsed_messages)
		if has_complete_marker:
			var topic_result := {"messages": parsed_messages}
			if not topic_summary_from_protocol.is_empty():
				topic_result["summary"] = topic_summary_from_protocol
			_request_topic_completion(channel_id, topic, topic_result)

	# 检查轮数超限
	if topic and not debug_mode and topic.max_turns > 0 and topic.turn_count >= topic.max_turns:
		topic_manager.timeout_topic(topic)


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
	if topic == null:
		return

	for event_data in events:
		var event_id := str(event_data.get("id", "")).strip_edges()
		if event_id.is_empty():
			continue

		var payload: Dictionary = event_data.get("payload", {})
		chat_event_emitted.emit(topic, event_id, payload)

		var story_director: Node = get_node_or_null("/root/StoryDirector")
		if story_director != null and story_director.has_method("notify_condition_met"):
			story_director.notify_condition_met(event_id, payload)

	for action in actions:
		var action_type := str(action.get("type", "")).strip_edges().to_lower()
		if action_type.is_empty():
			continue

		chat_action_requested.emit(topic, action)
		_execute_protocol_action(topic, action)


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


func _execute_protocol_action(topic: ChatTopic, action: Dictionary) -> void:
	var action_type := str(action.get("type", "")).strip_edges().to_lower()
	match action_type:
		"open_browser":
			_execute_protocol_open_browser(action)
		"focus_app":
			_execute_protocol_focus_app(action)
		"launch_app":
			_execute_protocol_launch_app(action)
		"post_moment":
			_execute_protocol_post_moment(topic, action)
		"lock_app_window":
			_execute_protocol_lock_app_window(action)
		"unlock_app_window":
			_execute_protocol_unlock_app_window(action)
		_:
			push_warning("[ChatManager] Unsupported protocol action: %s" % action_type)


func _execute_protocol_open_browser(action: Dictionary) -> void:
	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser == null or not browser.has_method("request_open_url"):
		return

	var url := str(action.get("url", "")).strip_edges()
	if url.is_empty():
		return

	browser.request_open_url(
		url,
		str(action.get("design_prompt", "")),
		str(action.get("page_context", ""))
	)


func _execute_protocol_focus_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	var force_launch: bool = bool(action.get("force_launch", true))
	var window: Control = null
	if app_mgr.has_method("focus_app"):
		window = app_mgr.focus_app(app_id, force_launch)
	elif force_launch and app_mgr.has_method("launch_app"):
		window = app_mgr.launch_app(app_id, true)

	_focus_protocol_window_channel(window, app_id, str(action.get("channel_id", "")))


func _execute_protocol_launch_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("launch_app"):
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	var window: Control = app_mgr.launch_app(app_id, bool(action.get("force", false)))
	_focus_protocol_window_channel(window, app_id, str(action.get("channel_id", "")))


func _execute_protocol_post_moment(topic: ChatTopic, action: Dictionary) -> void:
	var npc_id := str(action.get("npc_id", topic.npc_id)).strip_edges()
	var content := str(action.get("content", "")).strip_edges()
	if npc_id.is_empty() or content.is_empty():
		return

	post_moment(npc_id, content, str(action.get("image_hint", "")), int(action.get("likes", 0)))


func _execute_protocol_lock_app_window(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("lock_app_window"):
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	app_mgr.lock_app_window(
		app_id,
		bool(action.get("close_locked", true)),
		bool(action.get("minimize_locked", true))
	)
	if bool(action.get("focus", true)) and app_mgr.has_method("focus_app"):
		app_mgr.focus_app(app_id, false)


func _execute_protocol_unlock_app_window(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("unlock_app_window"):
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	app_mgr.unlock_app_window(app_id)


func _focus_protocol_window_channel(window: Control, app_id: String, channel_id: String) -> void:
	var normalized_channel_id := channel_id.strip_edges()
	if app_id != "linkchat" or normalized_channel_id.is_empty():
		return
	if window == null or not is_instance_valid(window):
		return
	if not ("content" in window):
		return

	var content: Variant = window.content
	if not (content is Node):
		return

	var app: Node = content as Node
	if app.has_method("open_topic_channel"):
		app.call_deferred("open_topic_channel", normalized_channel_id)
	elif app.has_method("select_channel"):
		app.call_deferred("select_channel", normalized_channel_id)


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
	if request_id != _pending_request_id:
		return

	_pending_request_id = ""
	var channel_id := _waiting_channel_id
	var complete_after_response: bool = _pending_complete_topic_after_response
	var failed_topic: ChatTopic = topic_manager.get_active_topic(channel_id)

	_waiting_for_ai = false
	_waiting_channel_id = ""
	_pending_auto_store_response = false
	_pending_complete_topic_after_response = false
	waiting_for_ai_changed.emit(false)

	if complete_after_response and failed_topic != null:
		topic_manager.timeout_topic(failed_topic)

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
	var suppress_notice: bool = bool(topic.context_data.get("suppress_system_notice", false))
	if not suppress_notice:
		add_system_message(topic.channel_id, "[话题结束] %s" % topic.display_title)

	# 存储记忆
	var summary: String = result.get("summary", "")
	if summary.is_empty():
		summary = "对话完成：%s" % topic.display_title
	memory_manager.store_topic_memory(topic.topic_id, topic.npc_id, summary)

	_emit_chat_state_changed()
	topic_completed.emit(topic, result)


func _on_topic_timeout(topic: ChatTopic) -> void:
	_pending_topic_completions.erase(topic.channel_id)
	_pending_protocol_effects.erase(topic.channel_id)
	var suppress_notice: bool = bool(topic.context_data.get("suppress_system_notice", false))
	if not suppress_notice:
		add_system_message(topic.channel_id, "[话题超时] %s" % topic.display_title)
	_emit_chat_state_changed()
	topic_timeout.emit(topic)

#endregion


#region Persistence

func get_run_state() -> Dictionary:
	return {
		"channels": _serialize_channels(),
		"moments": _moments.duplicate(true),
		"moments_unread": _moments_unread,
		"last_activated_topic_channel_id": _last_activated_topic_channel_id,
		"topic_history": topic_manager.topic_history.duplicate(true) if topic_manager != null else [],
		"debug_mode": debug_mode,
	}


func load_run_state(data: Dictionary) -> bool:
	if data.is_empty():
		return true
	_reset_runtime_transients()
	_restore_channels(data.get("channels", []))
	_restore_moments(data.get("moments", []))
	_moments_unread = max(0, int(data.get("moments_unread", 0)))
	_last_activated_topic_channel_id = str(data.get("last_activated_topic_channel_id", "")).strip_edges()
	debug_mode = bool(data.get("debug_mode", debug_mode))

	if topic_manager != null:
		if topic_manager.has_method("reset_runtime_state"):
			topic_manager.reset_runtime_state(true)
		topic_manager.topic_history = []
		for item in data.get("topic_history", []):
			if item is Dictionary:
				topic_manager.topic_history.append((item as Dictionary).duplicate(true))

	_emit_chat_state_changed()
	return true


func reset_runtime_state(reset_memory: bool = false) -> void:
	_reset_runtime_transients()
	if topic_manager != null and topic_manager.has_method("reset_runtime_state"):
		topic_manager.reset_runtime_state(true)
	if reset_memory and memory_manager != null and memory_manager.has_method("reset_runtime_state"):
		memory_manager.reset_runtime_state(true)
	_channels.clear()
	_channel_order.clear()
	_moments.clear()
	_moments_unread = 0
	_last_activated_topic_channel_id = ""
	debug_mode = true
	_setup_default_channels()
	_setup_default_moments()
	_emit_chat_state_changed()


func _serialize_channels() -> Array[Dictionary]:
	var channels_state: Array[Dictionary] = []
	for channel_id in _channel_order:
		var channel: ChatChannel = _channels.get(channel_id) as ChatChannel
		if channel == null:
			continue
		channels_state.append({
			"channel_id": channel.channel_id,
			"display_name": channel.display_name,
			"channel_prompt": channel.channel_prompt,
			"channel_type": int(channel.channel_type),
			"members": channel.members.duplicate(),
			"pinned": channel.pinned,
			"unread_count": channel.unread_count,
			"messages": channel.messages.duplicate(true),
		})
	return channels_state


func _restore_channels(channels_state: Variant) -> void:
	_channels.clear()
	_channel_order.clear()
	if not (channels_state is Array):
		return

	for item in channels_state:
		if not item is Dictionary:
			continue
		var channel_data: Dictionary = item
		var channel_id: String = str(channel_data.get("channel_id", "")).strip_edges()
		if channel_id.is_empty():
			continue
		add_channel(
			channel_id,
			str(channel_data.get("display_name", channel_id)),
			int(channel_data.get("channel_type", ChatChannelClass.ChannelType.SOCIAL)),
			channel_data.get("members", [])
		)
		var channel: ChatChannel = _channels.get(channel_id) as ChatChannel
		if channel == null:
			continue
		channel.channel_prompt = str(channel_data.get("channel_prompt", ""))
		channel.pinned = bool(channel_data.get("pinned", false))
		channel.unread_count = max(0, int(channel_data.get("unread_count", 0)))
		channel.messages = []
		for msg in channel_data.get("messages", []):
			if msg is Dictionary:
				channel.messages.append((msg as Dictionary).duplicate(true))


func _restore_moments(moments_state: Variant) -> void:
	_moments.clear()
	if not (moments_state is Array):
		return
	for item in moments_state:
		if item is Dictionary:
			_moments.append((item as Dictionary).duplicate(true))


func _reset_runtime_transients() -> void:
	_waiting_for_ai = false
	_waiting_channel_id = ""
	_pending_request_id = ""
	_pending_auto_store_response = false
	_pending_complete_topic_after_response = false
	_active_npc_message_presentations.clear()
	_pending_topic_completions.clear()
	_pending_protocol_effects.clear()


func _emit_chat_state_changed() -> void:
	chat_state_changed.emit()

#endregion


#region 辅助

## 找到当前有 active topic 的频道（用于 batch_ready 时确定目标频道）
## 简单策略：遍历所有频道，返回第一个有 active topic 的
## 实际使用中同一时间通常只有一个频道在活跃对话
func _find_active_input_channel() -> String:
	for cid in _channel_order:
		if topic_manager.has_active_topic(cid):
			return cid
	return ""

#endregion


#region AI 响应解析辅助

## 剥离 <thinking>...</thinking> 标签，返回 {thinking: String, body: String}
func _strip_thinking_tags(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("<(thinking|think)>([\\s\\S]*?)</(thinking|think)>")
	var match := regex.search(text)
	if match:
		var opening_tag := match.get_string(1).strip_edges().to_lower()
		var closing_tag := match.get_string(3).strip_edges().to_lower()
		if opening_tag == closing_tag or (opening_tag == "thinking" and closing_tag == "think"):
			var thinking := match.get_string(2).strip_edges()
			var body := text.substr(match.get_end()).strip_edges()
			return {"thinking": thinking, "body": body}
	var fallback_regex := RegEx.new()
	fallback_regex.compile("<thinking>([\\s\\S]*?)</think>")
	var fallback_match := fallback_regex.search(text)
	if fallback_match:
		var fallback_thinking := fallback_match.get_string(1).strip_edges()
		var fallback_body := text.substr(fallback_match.get_end()).strip_edges()
		return {"thinking": fallback_thinking, "body": fallback_body}
	return {"thinking": "", "body": text}

## 从带有 markdown 包裹或前后附加说明的文本中提取真正的 JSON 字符串
func _extract_json_from_text(text: String) -> String:
	var clean_text := text.strip_edges()
	
	# 如果本身就是合法的 JSON 字典格式
	if clean_text.begins_with("{") and clean_text.ends_with("}"):
		return clean_text

	# 尝试提取 markdown ```json 包裹的部分
	var regex := RegEx.new()
	regex.compile("```(?:json)?\\n?([\\s\\S]*?)\\n?```")
	var match := regex.search(clean_text)
	if match:
		var extracted := match.get_string(1).strip_edges()
		if extracted.begins_with("{") and extracted.ends_with("}"):
			return extracted

	# 暴力寻找第一个 { 和 最后一个 }
	var first_brace := clean_text.find("{")
	var last_brace := clean_text.rfind("}")
	if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
		return clean_text.substr(first_brace, last_brace - first_brace + 1)
		
	return clean_text


func _parse_ai_response_text(text: String, fallback_npc_id: String) -> Dictionary:
	var clean_text := _strip_response_code_fence(text.strip_edges())
	if clean_text.is_empty():
		return {
			"messages": [],
			"recommended_replies": [],
			"topic_complete": false,
			"topic_summary": "",
			"events": [],
			"actions": [],
		}

	var line_protocol_result := _parse_line_protocol_response(clean_text, fallback_npc_id)
	if bool(line_protocol_result.get("valid", false)):
		line_protocol_result.erase("valid")
		return line_protocol_result

	var parse_source: String = clean_text.replace("[TOPIC_COMPLETE]", "")
	var json_str := _extract_json_from_text(parse_source)
	var response_json: Variant = JSON.parse_string(json_str)
	if response_json != null and response_json is Dictionary:
		return _parse_json_response_dict(response_json as Dictionary, fallback_npc_id, "[TOPIC_COMPLETE]" in clean_text)

	push_warning("[ChatManager] Failed to parse structured AI response. Fallback to raw text message.")
	return {
		"messages": [{
			"speaker": fallback_npc_id,
			"content": _build_fallback_ai_message(clean_text),
		}],
		"recommended_replies": [],
		"topic_complete": false,
		"topic_summary": "",
		"events": [],
		"actions": [],
	}


func _parse_json_response_dict(response_json: Dictionary, fallback_npc_id: String, has_complete_marker: bool) -> Dictionary:
	var parsed_messages := _parse_response_messages_array(response_json.get("messages", []), fallback_npc_id)
	var topic_complete: bool = has_complete_marker or bool(response_json.get("topic_complete", false))
	var topic_summary: String = str(response_json.get("topic_summary", response_json.get("summary", ""))).strip_edges()
	if topic_complete:
		_attach_complete_marker_to_messages(parsed_messages)

	var recommended_replies: Array[String] = []
	var raw_replies: Variant = response_json.get("recommended_replies", [])
	if raw_replies is Array:
		for reply in raw_replies:
			if reply is String and not reply.is_empty():
				recommended_replies.append(str(reply))

	var parsed_events := _parse_response_events_array(response_json.get("events", []))
	var parsed_actions := _parse_response_actions_array(response_json.get("actions", []))

	return {
		"messages": parsed_messages,
		"recommended_replies": recommended_replies,
		"topic_complete": topic_complete,
		"topic_summary": topic_summary,
		"events": parsed_events,
		"actions": parsed_actions,
	}


func _parse_response_messages_array(raw_messages: Variant, fallback_npc_id: String) -> Array[Dictionary]:
	var parsed_messages: Array[Dictionary] = []
	if not (raw_messages is Array):
		return parsed_messages

	for msg in raw_messages:
		if msg is Dictionary and (msg.has("content") or msg.has("card")):
			var parsed_msg := {
				"speaker": msg.get("speaker", fallback_npc_id),
				"content": str(msg.get("content", "")),
			}
			if msg.has("card") and msg["card"] is Dictionary:
				var card := _sanitize_message_card(msg["card"])
				if not card.is_empty():
					parsed_msg["card"] = card
			parsed_messages.append(parsed_msg)
		elif msg is String:
			parsed_messages.append({
				"speaker": fallback_npc_id,
				"content": str(msg),
			})
	return parsed_messages


func _parse_response_events_array(raw_events: Variant) -> Array[Dictionary]:
	var parsed_events: Array[Dictionary] = []
	if not (raw_events is Array):
		return parsed_events

	for raw_event in raw_events:
		if not (raw_event is Dictionary):
			continue
		var event_data := _parse_protocol_event(raw_event as Dictionary)
		if event_data.is_empty():
			continue
		parsed_events.append(event_data)

	return parsed_events


func _parse_response_actions_array(raw_actions: Variant) -> Array[Dictionary]:
	var parsed_actions: Array[Dictionary] = []
	if not (raw_actions is Array):
		return parsed_actions

	for raw_action in raw_actions:
		if not (raw_action is Dictionary):
			continue
		var action_data := _parse_protocol_action(raw_action as Dictionary)
		if action_data.is_empty():
			continue
		parsed_actions.append(action_data)

	return parsed_actions


func _parse_line_protocol_response(text: String, fallback_npc_id: String) -> Dictionary:
	var parsed_messages: Array[Dictionary] = []
	var recommended_replies: Array[String] = []
	var has_complete_marker: bool = false
	var has_explicit_complete_command: bool = false
	var complete_summary: String = ""
	var parsed_events: Array[Dictionary] = []
	var parsed_actions: Array[Dictionary] = []
	var saw_protocol_line: bool = false
	var saw_message_line: bool = false

	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line == "[TOPIC_COMPLETE]":
			has_complete_marker = true
			saw_protocol_line = true
			continue
		if line.begins_with("!"):
			var command := _parse_line_protocol_command(line)
			var command_name := str(command.get("name", ""))
			var command_params: Dictionary = command.get("params", {})
			match command_name:
				"complete":
					has_complete_marker = true
					has_explicit_complete_command = true
					complete_summary = str(command_params.get("summary", command_params.get("text", ""))).strip_edges()
					saw_protocol_line = true
				"event":
					var parsed_event := _parse_protocol_event(command_params)
					if not parsed_event.is_empty():
						parsed_events.append(parsed_event)
						saw_protocol_line = true
				"action":
					var parsed_action := _parse_protocol_action(command_params)
					if not parsed_action.is_empty():
						parsed_actions.append(parsed_action)
						saw_protocol_line = true
			continue
		if line.begins_with(">"):
			var reply := line.trim_prefix("> ").trim_prefix(">\t").trim_prefix(">")
			reply = reply.strip_edges()
			if not reply.is_empty():
				recommended_replies.append(reply)
				saw_protocol_line = true
			continue
		if line.begins_with("@"):
			var parsed_message := _parse_line_protocol_message(line, fallback_npc_id)
			if parsed_message.is_empty():
				continue
			parsed_messages.append(parsed_message)
			saw_protocol_line = true
			saw_message_line = true
			continue
		if saw_message_line and _attach_standalone_card_line(parsed_messages, line):
			saw_protocol_line = true
			continue
		if saw_message_line and not parsed_messages.is_empty():
			var last_message := parsed_messages[parsed_messages.size() - 1]
			var last_content := str(last_message.get("content", ""))
			last_message["content"] = line if last_content.is_empty() else "%s\n%s" % [last_content, line]
			parsed_messages[parsed_messages.size() - 1] = last_message

	if has_complete_marker:
		_attach_complete_marker_to_messages(parsed_messages)

	return {
		"valid": saw_protocol_line and (
			saw_message_line
			or not recommended_replies.is_empty()
			or has_explicit_complete_command
			or not parsed_events.is_empty()
			or not parsed_actions.is_empty()
		),
		"messages": parsed_messages,
		"recommended_replies": recommended_replies,
		"topic_complete": has_complete_marker,
		"topic_summary": complete_summary,
		"events": parsed_events,
		"actions": parsed_actions,
	}


func _parse_line_protocol_command(line: String) -> Dictionary:
	if not line.begins_with("!"):
		return {}

	var content := line.substr(1).strip_edges()
	if content.is_empty():
		return {}

	var first_space := content.find(" ")
	var command_name := content
	var params_text := ""
	if first_space != -1:
		command_name = content.substr(0, first_space).strip_edges()
		params_text = content.substr(first_space + 1).strip_edges()

	return {
		"name": command_name.to_lower(),
		"params": _parse_protocol_key_values(params_text),
	}


func _parse_protocol_event(raw_data: Dictionary) -> Dictionary:
	var event_id := str(raw_data.get("id", raw_data.get("event_id", ""))).strip_edges()
	if event_id.is_empty():
		return {}

	var payload := raw_data.duplicate(true)
	payload.erase("id")
	payload.erase("event_id")
	var timing := _normalize_protocol_timing(str(payload.get("timing", "after_messages")))
	payload.erase("timing")

	return {
		"id": event_id,
		"timing": timing,
		"payload": payload,
	}


func _parse_protocol_action(raw_data: Dictionary) -> Dictionary:
	var action_type := str(raw_data.get("type", "")).strip_edges().to_lower()
	if action_type.is_empty():
		return {}

	var action := raw_data.duplicate(true)
	action["type"] = action_type
	action["timing"] = _normalize_protocol_timing(str(action.get("timing", "after_messages")))
	return action


func _parse_line_protocol_message(line: String, fallback_npc_id: String) -> Dictionary:
	var colon_index := line.find(":")
	if colon_index <= 1:
		return {}

	var speaker := line.substr(1, colon_index - 1).strip_edges()
	if speaker.is_empty():
		speaker = fallback_npc_id

	var body := line.substr(colon_index + 1).strip_edges()
	var card_payload := _extract_inline_card_from_text(body)
	var content := str(card_payload.get("content", "")).strip_edges()
	var card: Dictionary = card_payload.get("card", {})
	if content.is_empty() and card.is_empty():
		return {}

	var parsed_message := {
		"speaker": speaker,
		"content": content,
	}
	if not card.is_empty():
		parsed_message["card"] = card
	return parsed_message


func _attach_standalone_card_line(parsed_messages: Array[Dictionary], line: String) -> bool:
	if parsed_messages.is_empty():
		return false

	var card_payload := _extract_inline_card_from_text(line)
	var card: Dictionary = card_payload.get("card", {})
	if card.is_empty():
		return false

	var last_message := parsed_messages[parsed_messages.size() - 1]
	if last_message.has("card") and last_message["card"] is Dictionary and not (last_message["card"] as Dictionary).is_empty():
		return false

	var content := str(card_payload.get("content", "")).strip_edges()
	var last_content := str(last_message.get("content", "")).strip_edges()
	if not content.is_empty():
		last_message["content"] = content if last_content.is_empty() else "%s\n%s" % [last_content, content]
	last_message["card"] = card
	parsed_messages[parsed_messages.size() - 1] = last_message
	return true


func _extract_inline_card_from_text(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("\\[card:([a-zA-Z0-9_]+)([^\\]]*)\\]")
	var match := regex.search(text)
	if match == null:
		return {"content": text.strip_edges(), "card": {}}

	var card_type := match.get_string(1).strip_edges().to_lower()
	var params_text := match.get_string(2).strip_edges()
	var card: Dictionary = {"type": card_type}
	var parsed_params := _parse_protocol_key_values(params_text)
	for key in parsed_params.keys():
		card[key] = parsed_params[key]

	var remaining := "%s%s" % [
		text.substr(0, match.get_start()),
		text.substr(match.get_end()),
	]
	var sanitized_card := _sanitize_message_card(card)
	return {
		"content": remaining.strip_edges(),
		"card": sanitized_card,
	}


func _parse_protocol_key_values(text: String) -> Dictionary:
	var values: Dictionary = {}
	if text.is_empty():
		return values

	var regex := RegEx.new()
	regex.compile("([a-zA-Z0-9_]+)=(\"(?:\\\\.|[^\"])*\"|'(?:\\\\.|[^'])*'|\\S+)")
	for match in regex.search_all(text):
		var key := match.get_string(1).strip_edges()
		var raw_value := match.get_string(2)
		values[key] = _coerce_protocol_value(raw_value)
	return values


func _coerce_protocol_value(raw_value: String) -> Variant:
	var value := raw_value.strip_edges()
	if value.length() >= 2:
		var first_char := value.substr(0, 1)
		var last_char := value.substr(value.length() - 1, 1)
		if (first_char == '"' and last_char == '"') or (first_char == "'" and last_char == "'"):
			value = value.substr(1, value.length() - 2)
			value = value.replace("\\n", "\n")
			value = value.replace('\\"', '"')
			value = value.replace("\\'", "'")

	var lower_value := value.to_lower()
	if lower_value == "true":
		return true
	if lower_value == "false":
		return false
	if value.is_valid_int():
		return int(value)
	if value.is_valid_float():
		return float(value)
	return value


func _strip_response_code_fence(text: String) -> String:
	var clean_text := text.strip_edges()
	var regex := RegEx.new()
	regex.compile("```(?:[a-zA-Z0-9_+-]+)?\\n?([\\s\\S]*?)\\n?```")
	var match := regex.search(clean_text)
	if match:
		return match.get_string(1).strip_edges()
	return clean_text


func _build_fallback_ai_message(text: String) -> String:
	var cleaned_text := _strip_response_code_fence(text.strip_edges())
	cleaned_text = _strip_protocol_control_lines(cleaned_text)

	return cleaned_text


func _strip_protocol_control_lines(text: String) -> String:
	var kept_lines: Array[String] = []
	for raw_line in text.split("\n"):
		var line := str(raw_line)
		var stripped := line.strip_edges()
		if stripped == "[TOPIC_COMPLETE]" or stripped.begins_with("!"):
			continue
		kept_lines.append(line)
	return "\n".join(kept_lines).strip_edges()


func _attach_complete_marker_to_messages(messages: Array[Dictionary]) -> void:
	if messages.is_empty():
		return
	for i in range(messages.size() - 1, -1, -1):
		var message := messages[i]
		var content := str(message.get("content", ""))
		if "[TOPIC_COMPLETE]" in content:
			return
		message["content"] = "%s[TOPIC_COMPLETE]" % content
		messages[i] = message
		return


func _messages_have_complete_marker(messages: Array[Dictionary]) -> bool:
	for i in range(messages.size() - 1, -1, -1):
		var content_text := str(messages[i].get("content", ""))
		if "[TOPIC_COMPLETE]" in content_text:
			return true
	return false


func _extract_topic_summary_from_messages(messages: Array[Dictionary]) -> String:
	for i in range(messages.size() - 1, -1, -1):
		var content_text := str(messages[i].get("content", "")).replace("[TOPIC_COMPLETE]", "").strip_edges()
		if not content_text.is_empty():
			return content_text
	return ""

#endregion
