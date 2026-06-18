extends Node

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const ActivityChatClass = preload("res://scripts/activity/activity_chat.gd")
const CommunityPostParserClass = preload("res://scripts/apps/community/community_post_parser.gd")
const AIServiceClass = preload("res://scripts/llm/AIService.gd")

signal community_action_started(action_id: String, request_id: String)
signal community_action_completed(action_id: String, entry: Dictionary)
signal community_action_failed(action_id: String, error: String)
signal community_feed_updated()

const PAGE_PROMPT_KEY: String = "community_feed"
const COMMUNITY_DATA_PATH: String = "res://prompts/community_seeds.json"
const LIN_XIA_CHANNEL_ID: String = "dm_lin_xia"
const FREE_SEARCH_ACTION_ID: String = "free_search"
const RANDOM_SEARCH_ACTION_ID: String = "random_search"
const FEED_LIMIT: int = 18
const DEFAULT_TOPIC_SEED_COUNT: int = 1
const RECENT_TOPIC_SEED_LIMIT: int = 9
const DEFAULT_TIME_TEXTS: PackedStringArray = ["刚刚", "12分钟前", "35分钟前", "1小时前", "3小时前", "昨天"]
const DEFAULT_AUTHORS: PackedStringArray = [
	"像素熬夜人",
	"代码锅王",
	"切片吐槽机",
	"匿名评委学",
	"宿舍楼观察员",
	"凌晨四点的IDE",
	"纸杯咖啡续命",
	"排版完蛋了",
	"剧情拧巴症",
	"临门一脚又改需求",
]
const SUPPORT_REPLIES: PackedStringArray = [
	"这条我认同，至少不是空喊口号。",
	"你这么一说我也开始焦虑了。",
	"先别慌，这类问题一般都有人踩过坑。",
	"说得挺真实的，我刚刚也是这个状态。",
]
const SKEPTIC_REPLIES: PackedStringArray = [
	"也可能只是当下热度高，过一会儿就没人提了。",
	"听起来厉害，但落到成品未必成立。",
	"我保留意见，论坛里经常把话说太满。",
	"先等更多人实测吧，现在下结论太早。",
]

@onready var _ai_service: Node = $AIService

var _pending_requests: Dictionary = {}
var _action_definitions: Dictionary = {}
var _community_content: Dictionary = {}
var _action_counter: int = 0
var _entry_counter: int = 0
var _chat: RefCounted = null
var _pending_followups: Dictionary = {}
var _feed_entries: Array = []
var _recent_topic_seeds: Array = []


func _ready() -> void:
	if _ai_service == null:
		push_error("CommunityActionManager: AIService not found")
		return

	_setup_ai_service()
	_ai_service.request_completed.connect(_on_ai_request_completed)
	_ai_service.request_failed.connect(_on_ai_request_failed)
	_load_community_content()
	_chat = ActivityChatClass.new("community", "community_stage")
	_chat.connect_signals()
	_chat.stage_completed.connect(_on_chat_stage_completed)
	_chat.stage_timeout.connect(_on_chat_stage_timeout)
	ActivityLockUtilsClass.register_free_period_blocker(
		name,
		self,
		"has_pending_requests",
		"当前社区动态还在刷新，请先等待反馈。"
	)


func _exit_tree() -> void:
	ActivityLockUtilsClass.unregister_free_period_blocker(name)


func _setup_ai_service() -> void:
	var cfg := AIConfigManager.get_instance()
	if not cfg.apply_to_service(_ai_service, "browser"):
		cfg.apply_to_service(_ai_service, "chat_default")

	_ai_service.auto_execute_tools = false
	_ai_service.stream_enabled = false
	_ai_service.max_concurrent_requests = max(_ai_service.max_concurrent_requests, 5)
	_ai_service.default_temperature = 0.8


func get_available_actions() -> Array:
	var actions: Array = []
	var glm: Node = _get_root_node("GameLoopManager")
	for action_id in _action_definitions.keys():
		if bool(_action_definitions[action_id].get("ui_hidden", false)):
			continue
		var data: Dictionary = _action_definitions[action_id].duplicate(true)
		var ap_cost: int = int(data.get("ap_cost", 1))
		var blocked_reason: String = _get_activity_blocking_reason(action_id, data)
		if blocked_reason.is_empty():
			data["enabled"] = glm != null and glm.can_consume_ap(ap_cost)
			if not bool(data.get("enabled", false)) and glm != null:
				data["blocked_reason"] = "这个时间段已经安排过事情了"
		else:
			data["enabled"] = false
			data["blocked_reason"] = blocked_reason
		actions.append(data)

	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0))
	)
	return actions


func perform_action(action_id: String) -> Dictionary:
	return _perform_action_with_seeds(action_id, [])


func search_feed(query: String, mode: String = "free_search") -> Dictionary:
	var normalized_query: String = query.strip_edges()
	if normalized_query.is_empty():
		return {"success": false, "error": "先输入想搜的内容"}
	var action_id := FREE_SEARCH_ACTION_ID
	if mode.strip_edges() == RANDOM_SEARCH_ACTION_ID:
		action_id = RANDOM_SEARCH_ACTION_ID
	return _perform_action_with_seeds(action_id, [normalized_query], normalized_query)


func random_feed() -> Dictionary:
	var seed_text: String = _pick_random_search_seed()
	if seed_text.is_empty():
		seed_text = "今天社区都在聊什么"
	return _perform_action_with_seeds(RANDOM_SEARCH_ACTION_ID, [seed_text], seed_text)


func get_search_blocking_reason() -> String:
	var action: Dictionary = _action_definitions.get(FREE_SEARCH_ACTION_ID, _build_search_action_definition(FREE_SEARCH_ACTION_ID))
	var reason: String = _get_activity_blocking_reason(FREE_SEARCH_ACTION_ID, action)
	if not reason.is_empty():
		return reason
	var glm: Node = _get_root_node("GameLoopManager")
	if glm == null:
		return "GameLoopManager 不可用"
	if not glm.can_consume_ap(int(action.get("ap_cost", 1))):
		return "当前无法执行这个行动"
	return ""


func _perform_action_with_seeds(action_id: String, seed_override: Array, query_text: String = "") -> Dictionary:
	var normalized_id := action_id.strip_edges()
	if normalized_id.is_empty() or not _action_definitions.has(normalized_id):
		return {"success": false, "error": "未知的社区行动"}

	var action: Dictionary = _action_definitions[normalized_id]
	var blocking_reason: String = _get_activity_blocking_reason(normalized_id, action)
	if not blocking_reason.is_empty():
		return {"success": false, "error": blocking_reason}

	var ap_cost: int = int(action.get("ap_cost", 1))
	var glm: Node = _get_root_node("GameLoopManager")
	if glm == null:
		return {"success": false, "error": "GameLoopManager 不可用"}
	if not glm.can_consume_ap(ap_cost):
		return {"success": false, "error": "当前无法执行这个行动"}

	_action_counter += 1
	var day: int = _get_current_day()
	var selected_seeds: Array = seed_override.duplicate()
	if selected_seeds.is_empty():
		selected_seeds = _pick_topic_seeds(normalized_id, day)
	else:
		_remember_topic_seeds(selected_seeds)
	var action_meta := {
		"action_id": normalized_id,
		"action": action.duplicate(true),
		"day": day,
		"phase": _get_current_phase_display_name(),
		"selected_seeds": selected_seeds.duplicate(),
		"query": query_text.strip_edges(),
		"url": _build_entry_url(normalized_id, day),
	}

	var messages := _build_action_feed_messages(action_meta)
	var request_id: String = _ai_service.chat(messages, {
		"temperature": 0.8,
	})
	if request_id.is_empty():
		var entry := _build_fallback_entry(action_meta)
		_finalize_action_entry(normalized_id, entry, action_meta)
		return {
			"success": true,
			"entry_id": entry.get("entry_id", ""),
			"title": entry.get("title", ""),
			"async": false,
		}

	_pending_requests[request_id] = {
		"kind": "community_feed",
		"action_meta": action_meta,
	}
	community_action_started.emit(normalized_id, request_id)
	return {
		"success": true,
		"title": str(action.get("title", "社区行动")),
		"async": true,
		"request_id": request_id,
	}


func get_recent_entries(limit: int = 8) -> Array:
	var entries: Array = _feed_entries.duplicate(true)
	if limit > 0 and entries.size() > limit:
		return entries.slice(0, limit)
	return entries


func get_run_state() -> Dictionary:
	return {
		"action_counter": _action_counter,
		"entry_counter": _entry_counter,
		"feed_entries": _feed_entries.duplicate(true),
		"recent_topic_seeds": _recent_topic_seeds.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_pending_requests.clear()
	_pending_followups.clear()
	_action_counter = int(data.get("action_counter", 0))
	_entry_counter = int(data.get("entry_counter", 0))
	_feed_entries.clear()
	var feed_entries: Variant = data.get("feed_entries", [])
	if feed_entries is Array:
		_feed_entries = (feed_entries as Array).duplicate(true)
	_recent_topic_seeds.clear()
	var recent_seeds: Variant = data.get("recent_topic_seeds", [])
	if recent_seeds is Array:
		_recent_topic_seeds = (recent_seeds as Array).duplicate(true)
	community_feed_updated.emit()
	return true


func reset_runtime_state() -> void:
	_pending_requests.clear()
	_pending_followups.clear()
	_feed_entries.clear()
	_action_counter = 0
	_entry_counter = 0
	_recent_topic_seeds.clear()
	community_feed_updated.emit()


func has_pending_requests() -> bool:
	return not _pending_requests.is_empty() or not _pending_followups.is_empty()


func _build_activity_aliases(action_id: String, action: Dictionary) -> Array[String]:
	var aliases: Array[String] = ["community", action_id]
	var action_type: String = str(action.get("action_type", "")).strip_edges()
	if not action_type.is_empty() and action_type not in aliases:
		aliases.append(action_type)
	return aliases


func _get_activity_blocking_reason(action_id: String, action: Dictionary) -> String:
	var free_period_reason: String = ActivityLockUtilsClass.get_free_period_block_reason()
	if not free_period_reason.is_empty():
		return free_period_reason
	var aliases: Array[String] = _build_activity_aliases(action_id, action)
	return ActivityLockUtilsClass.get_narrative_blocking_reason_for_any(aliases)


func _load_community_content() -> void:
	_community_content.clear()
	_action_definitions.clear()
	if not FileAccess.file_exists(COMMUNITY_DATA_PATH):
		push_warning("CommunityActionManager: community content file missing: %s" % COMMUNITY_DATA_PATH)
		_load_default_actions()
		return

	var file := FileAccess.open(COMMUNITY_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("CommunityActionManager: failed to open community content file")
		_load_default_actions()
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not parsed is Dictionary:
		push_warning("CommunityActionManager: invalid community content json")
		_load_default_actions()
		return

	_community_content = parsed
	for action in _community_content.get("actions", []):
		if not action is Dictionary:
			continue
		var normalized: Dictionary = _normalize_action_definition(action)
		if not normalized.is_empty():
			_action_definitions[str(normalized.get("action_id", ""))] = normalized

	if _action_definitions.is_empty():
		_load_default_actions()
	_ensure_search_actions()


func _load_default_actions() -> void:
	for action in [
		{"id": "chill", "label": "划水摸鱼", "ap": 1, "stat": {"stress": -2, "passion": -1}},
		{"id": "learn", "label": "学习开发", "ap": 1, "stat": {"stress": 1, "passion": 3}},
		{"id": "contest", "label": "发帖宣传", "ap": 1, "stat": {"hype": 8, "stress": 2}},
	]:
		var normalized: Dictionary = _normalize_action_definition(action)
		if not normalized.is_empty():
			_action_definitions[str(normalized.get("action_id", ""))] = normalized
	_ensure_search_actions()


func _ensure_search_actions() -> void:
	_action_definitions[FREE_SEARCH_ACTION_ID] = _build_search_action_definition(FREE_SEARCH_ACTION_ID)
	_action_definitions[RANDOM_SEARCH_ACTION_ID] = _build_search_action_definition(RANDOM_SEARCH_ACTION_ID)


func _build_search_action_definition(action_id: String) -> Dictionary:
	match action_id:
		RANDOM_SEARCH_ACTION_ID:
			return {
				"action_id": RANDOM_SEARCH_ACTION_ID,
				"title": "随心一搜",
				"description": "随手刷一条社区正在讨论的帖子。",
				"action_type": "community",
				"ap_cost": 1,
				"stat_changes": {"stress": -1, "hype": 1},
				"tags": ["社区", "随机"],
				"sort_order": 2,
				"ui_hidden": true,
			}
		_:
			return {
				"action_id": FREE_SEARCH_ACTION_ID,
				"title": "自由搜索",
				"description": "按关键词搜索社区帖子。",
				"action_type": "community",
				"ap_cost": 1,
				"stat_changes": {"stress": 1, "passion": 1},
				"tags": ["社区", "搜索"],
				"sort_order": 1,
				"ui_hidden": true,
			}


func _normalize_action_definition(raw: Dictionary) -> Dictionary:
	var source_id: String = str(raw.get("action_id", raw.get("id", ""))).strip_edges()
	var title: String = str(raw.get("title", raw.get("label", "社区行动"))).strip_edges()
	var ap_cost: int = int(raw.get("ap_cost", raw.get("ap", 1)))
	var stat_changes: Dictionary = raw.get("stat_changes", raw.get("stat", {}))
	var result := {
		"action_type": "community",
		"ap_cost": max(1, ap_cost),
		"stat_changes": stat_changes.duplicate(true),
	}

	match source_id:
		"chill", "chill_browse":
			result.merge({
				"action_id": "chill_browse",
				"title": title if not title.is_empty() else "划水摸鱼",
				"description": "刷点有意思的帖子放松一下，和比赛无关的闲聊。",
				"tags": ["摸鱼", "闲聊"],
				"sort_order": 10,
			}, true)
		"learn", "learn_dev":
			result.merge({
				"action_id": "learn_dev",
				"title": title if not title.is_empty() else "学习开发",
				"description": "翻翻游戏开发教程和经验贴，说不定有能用上的技巧。",
				"tags": ["教程", "学习"],
				"sort_order": 20,
			}, true)
		"contest", "follow_contest":
			result.merge({
				"action_id": "follow_contest",
				"title": title if not title.is_empty() else "发帖宣传",
				"description": "让你的项目出现在信息流里，观察路人的第一波反应。",
				"tags": ["宣传", "曝光"],
				"sort_order": 30,
			}, true)
		_:
			return {}
	return result


func _resolve_prompt(key: String, vars: Dictionary = {}) -> String:
	var pm: Node = _get_root_node("PromptManager")
	if pm == null:
		return ""
	if vars.is_empty():
		if pm.has_method("resolve"):
			return str(pm.resolve(key))
		return ""
	if pm.has_method("resolve_with_vars"):
		return str(pm.resolve_with_vars(key, vars))
	if pm.has_method("resolve"):
		return str(pm.resolve(key))
	return ""


func _extract_content(response: Dictionary) -> String:
	return AIServiceClass.extract_content(response).strip_edges()


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if not _pending_requests.has(request_id):
		return

	var meta: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)
	var content: String = _extract_content(response)
	if content.is_empty():
		_handle_action_feed_failed(meta, "LLM 返回为空")
		return
	_handle_action_feed_completed(meta, content)


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _pending_requests.has(request_id):
		return
	var meta: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)
	_handle_action_feed_failed(meta, error)


func _handle_action_feed_completed(meta: Dictionary, content: String) -> void:
	var action_meta: Dictionary = meta.get("action_meta", {})
	var action_id: String = str(action_meta.get("action_id", ""))
	var posts: Array = CommunityPostParserClass.parse(content)
	if posts.is_empty():
		push_warning("[CommunityActionManager] Parsed 0 posts from LLM response for action '%s'. Falling back. Content preview: %s" % [
			action_id,
			_summarize_text(content, 120)
		])
		_handle_action_feed_fallback(action_meta)
		return
	var entry := _build_feed_entry(action_meta, _sanitize_posts(posts), "llm")
	_finalize_action_entry(action_id, entry, action_meta)


func _handle_action_feed_failed(meta: Dictionary, error: String) -> void:
	var action_meta: Dictionary = meta.get("action_meta", {})
	var action_id: String = str(action_meta.get("action_id", ""))
	community_action_failed.emit(action_id, error)
	_handle_action_feed_fallback(action_meta)


func _handle_action_feed_fallback(action_meta: Dictionary) -> void:
	var action_id: String = str(action_meta.get("action_id", ""))
	push_warning("[CommunityActionManager] Using fallback community feed for action '%s'" % action_id)
	var entry := _build_fallback_entry(action_meta)
	_finalize_action_entry(action_id, entry, action_meta)


func _finalize_action_entry(action_id: String, entry: Dictionary, action_meta: Dictionary) -> void:
	var stored_entry: Dictionary = _register_entry(entry)
	_consume_ap_and_stats(action_id, action_meta)
	_share_entry_with_lin_xia(action_id, stored_entry, action_meta)
	community_action_completed.emit(action_id, stored_entry.duplicate(true))


func _consume_ap_and_stats(action_id: String, action_meta: Dictionary) -> void:
	var action: Dictionary = action_meta.get("action", {})
	var ap_cost: int = int(action.get("ap_cost", 1))
	var action_type: String = str(action.get("action_type", "community"))
	var glm: Node = _get_root_node("GameLoopManager")
	if glm != null:
		glm.consume_ap(ap_cost, action_type, action_id)

	var stat_changes: Dictionary = action.get("stat_changes", {})
	if not stat_changes.is_empty():
		var gm: Node = _get_root_node("GameManager")
		if gm != null and gm.has_method("modify_stats"):
			gm.modify_stats(stat_changes)


func _share_entry_with_lin_xia(action_id: String, entry: Dictionary, action_meta: Dictionary) -> void:
	if entry.is_empty():
		return
	var chat: Node = _get_root_node("ChatManager")
	if chat == null:
		return

	var share_card: Dictionary = _build_followup_card(entry, action_meta)
	if chat.has_method("store_player_message_data"):
		chat.store_player_message_data(LIN_XIA_CHANNEL_ID, {
			"speaker": "player",
			"content": "我刚刷到这个帖子，发给你看看。",
			"card": share_card,
		})

	var session_id: String = "community_%d" % _action_counter
	var system_prompt: String = _build_followup_prompt(entry, action_meta)
	var started: bool = _chat.start_topic(session_id, "followup", {
		"display_label": "社区行动",
		"system_prompt": system_prompt,
		"goal": "发送社区行动后的短消息",
		"seed_message": "请根据当前话题直接发送活动后回复。",
		"timeout_seconds": 60,
	})
	if started:
		_pending_followups[session_id] = {
			"entry": entry.duplicate(true),
			"action_meta": action_meta.duplicate(true),
			"action_id": action_id,
		}
	else:
		push_warning("[CommunityActionManager] Falling back to local followup reply for action '%s': topic start failed" % action_id)
		var local_reply: String = _build_local_followup_reply(entry, action_meta)
		_chat.send_local_message(local_reply)


func _on_chat_stage_completed(session_id: String, _stage: String, _summary: String) -> void:
	if _pending_followups.has(session_id):
		_pending_followups.erase(session_id)


func _on_chat_stage_timeout(session_id: String, stage: String) -> void:
	if stage != "followup":
		return
	if _pending_followups.has(session_id):
		var data: Dictionary = _pending_followups[session_id]
		push_warning("[CommunityActionManager] Falling back to local followup reply for action '%s': topic timed out" % str(data.get("action_id", "")))
		var reply: String = _build_local_followup_reply(data.get("entry", {}), data.get("action_meta", {}))
		_chat.send_local_message(reply)
		_pending_followups.erase(session_id)


func _build_followup_prompt(entry: Dictionary, action_meta: Dictionary) -> String:
	var action: Dictionary = action_meta.get("action", {})
	var summary: String = str(entry.get("summary", "")).strip_edges()
	var first_post: Dictionary = _get_first_post(entry)
	var resolved := _resolve_prompt("community_followup_reply", {
		"action_title": str(action.get("title", "社区帖子")),
		"entry_title": str(entry.get("title", "")),
		"summary": summary,
		"first_author": str(first_post.get("author", "匿名用户")).strip_edges(),
		"first_content": str(first_post.get("content", "")).strip_edges(),
	}).strip_edges()
	if not resolved.is_empty():
		return resolved

	var parts: Array[String] = [
		"你是林夏。",
		"玩家刚把社区里刷到的一条帖子分享给你看。",
		"重要：这条帖子不是玩家自己写的，主楼作者/LZ也不是玩家；不要把帖子内容当成玩家本人的发言。",
		"社区入口：%s" % str(action.get("title", "社区帖子")),
		"社区条目标题：%s" % str(entry.get("title", "")),
	]
	if not summary.is_empty():
		parts.append("讨论摘要：%s" % summary)
	if not first_post.is_empty():
		parts.append("主楼作者：%s" % str(first_post.get("author", "匿名用户")).strip_edges())
		parts.append("最上面的帖文（社区用户原文，不是玩家发言）：%s" % str(first_post.get("content", "")).strip_edges())
	parts.append("用一句自然的中文聊天短消息回复，像是在回应玩家转发来的帖子。只输出回复正文。")
	return "\n".join(parts)


func _build_followup_card(entry: Dictionary, _action_meta: Dictionary) -> Dictionary:
	var summary: String = str(entry.get("summary", "")).strip_edges()
	var first_post: Dictionary = _get_first_post(entry)
	return {
		"type": "web_page",
		"title": str(entry.get("title", "社区帖子")),
		"subtitle": "社区帖子",
		"hint": summary,
		"body": summary,
		"badge": "转发帖子",
		"source_kind": "community_thread",
		"source_author": str(first_post.get("author", "")).strip_edges(),
		"url": str(entry.get("url", "")),
	}


func _build_local_followup_reply(entry: Dictionary, _action_meta: Dictionary) -> String:
	var summary: String = str(entry.get("summary", "")).strip_edges()
	if not summary.is_empty():
		return "我看完了，这个帖子底下的反应还挺值得记一下。"
	return "我看到了，这条帖子先记下来。"


func _build_action_feed_messages(action_meta: Dictionary) -> Array:
	var action: Dictionary = action_meta.get("action", {})
	var day: int = int(action_meta.get("day", 0))
	if day <= 0:
		day = _get_current_day()
	var selected_seeds: Array = action_meta.get("selected_seeds", [])
	var gm: Node = _get_root_node("GameManager")
	var state_prompt: String = ""
	if gm != null and gm.has_method("get_llm_state_prompt"):
		state_prompt = str(gm.get_llm_state_prompt()).strip_edges()

	var system_prompt: String = _resolve_prompt(PAGE_PROMPT_KEY, {
		"action_type": str(action.get("title", "社区行动")),
		"topic_seeds": ", ".join(PackedStringArray(selected_seeds)),
		"current_day": str(day),
		"game_state": "当前游戏状态：%s" % state_prompt if not state_prompt.is_empty() else "",
	})
	if system_prompt.is_empty():
		system_prompt = "你是一个虚拟社交平台的帖子生成器。只输出帖子 DSL，不要解释。"
	var user_prompt: String = _build_action_feed_user_prompt(action_meta)

	return [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt},
	]


func _build_action_feed_user_prompt(action_meta: Dictionary) -> String:
	var action: Dictionary = action_meta.get("action", {})
	var day: int = int(action_meta.get("day", 0))
	if day <= 0:
		day = _get_current_day()
	var selected_seeds: Array = action_meta.get("selected_seeds", [])

	var user_parts: PackedStringArray = []
	user_parts.append("这次要生成的是社区论坛里的 1 条完整帖子串。")
	user_parts.append("行动：%s" % str(action.get("title", "社区行动")))
	user_parts.append("今天是 Day %d。" % day)
	var primary_seed: String = str(selected_seeds[0]) if not selected_seeds.is_empty() else "比赛进度"
	user_parts.append("这次只围绕这一个主题展开：%s" % primary_seed)
	match str(action_meta.get("action_id", "")):
		FREE_SEARCH_ACTION_ID:
			user_parts.append("这是玩家主动搜索社区得到的一条论坛帖。主楼和楼层都要紧扣搜索词，不要写成搜索结果列表。")
		RANDOM_SEARCH_ACTION_ID:
			user_parts.append("这是玩家随手刷到的一条社区热帖。主题可以轻松发散，但整串楼仍然只能围绕当前主题。")
		"chill_browse":
			user_parts.append("这是一条和比赛无关的闲聊帖，内容可以是情感、萌宠、游戏、校园生活等轻松话题。整体像玩家随手刷到的贴吧热帖，允许有争议、歪楼和楼中楼互呛。不要涉及比赛和游戏开发。")
		"learn_dev":
			user_parts.append("这是一条游戏开发相关的教程或经验帖，可以涉及引擎使用技巧、美术流程、剧本写法、项目管理等。整体像论坛里的干货帖或经验分享，楼层可以补充、质疑或追问。")
		"follow_contest":
			user_parts.append("主楼必须明显围绕玩家项目或项目宣传点展开，但主楼作者是社区用户/路人，不是玩家或林夏。可以写成有人看到、转发、讨论玩家项目的宣传点；不要用第一人称替玩家发宣传帖，也不要让 NPC 误以为帖子是玩家自己写的。后续楼层是路人围观、质疑、支持和转评。")
	user_parts.append("楼层之间要有温差，不要所有人都一个态度。")
	return "\n".join(user_parts)


func _pick_random_search_seed() -> String:
	var pools: Variant = _community_content.get("topic_seeds", {})
	var candidates: Array = []
	if pools is Dictionary:
		for pool_value in (pools as Dictionary).values():
			if not pool_value is Array:
				continue
			for raw_seed in pool_value:
				var seed_text: String = str(raw_seed).strip_edges()
				if seed_text.is_empty() or candidates.has(seed_text):
					continue
				candidates.append(seed_text)
	if candidates.is_empty():
		candidates = [
			"今天社区都在聊什么",
			"大家怎么看这次比赛",
			"有没有适合摸鱼看的帖子",
		]
	var fresh_candidates: Array = []
	for seed_text in candidates:
		if not _recent_topic_seeds.has(seed_text):
			fresh_candidates.append(seed_text)
	var working_pool: Array = fresh_candidates if not fresh_candidates.is_empty() else candidates
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ abs(hash("community_random_%d" % _action_counter))
	return str(working_pool[rng.randi_range(0, working_pool.size() - 1)])


func _pick_topic_seeds(action_id: String, day: int, count: int = DEFAULT_TOPIC_SEED_COUNT) -> Array:
	var seeds_dict: Variant = _community_content.get("topic_seeds", {})
	var pool: Array = []
	if seeds_dict is Dictionary and seeds_dict.has(action_id):
		pool = seeds_dict[action_id]
	if pool.is_empty():
		var fallback_map: Dictionary = {
			"chill_browse": ["深夜emo了发个帖", "今天的猫又把键盘踩了", "推荐一部冷门番剧"],
			"learn_dev": ["新手如何学会拆解游戏设计", "对话系统怎么写才不会乱成一团", "UI布局的几个常见坑"],
			"follow_contest": ["画面风格到底该走什么路线", "玩法创新还是稳妥复刻经典", "宣传文案怎么写才抓人"],
		}
		return fallback_map.get(action_id, ["社区围观", "深夜讨论", "比赛进度"])

	var normalized_pool: Array = []
	for raw_seed in pool:
		var seed_text: String = str(raw_seed).strip_edges()
		if seed_text.is_empty() or normalized_pool.has(seed_text):
			continue
		normalized_pool.append(seed_text)
	if normalized_pool.is_empty():
		return ["比赛进度", "社区围观", "深夜讨论"]

	var target_count: int = mini(count, normalized_pool.size())
	var recent_lookup: Dictionary = {}
	for raw_recent_seed in _recent_topic_seeds:
		var recent_seed: String = str(raw_recent_seed).strip_edges()
		if recent_seed.is_empty():
			continue
		recent_lookup[recent_seed] = true

	var fresh_pool: Array = []
	for seed_text in normalized_pool:
		if recent_lookup.has(seed_text):
			continue
		fresh_pool.append(seed_text)

	var working_pool: Array = fresh_pool.duplicate()
	if working_pool.size() < target_count:
		working_pool = normalized_pool.duplicate()

	_shuffle_topic_seeds(working_pool, action_id, day)

	var picks: Array = []
	for seed_text in working_pool:
		if picks.size() >= target_count:
			break
		picks.append(seed_text)

	if picks.size() < target_count:
		var fallback_pool: Array = normalized_pool.duplicate()
		_shuffle_topic_seeds(fallback_pool, "%s_retry" % action_id, day + 1)
		for seed_text in fallback_pool:
			if picks.has(seed_text):
				continue
			picks.append(seed_text)
			if picks.size() >= target_count:
				break

	_remember_topic_seeds(picks)
	return picks


func _shuffle_topic_seeds(pool: Array, action_id: String, day: int) -> void:
	if pool.size() <= 1:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ abs(hash("%s_%d_%d" % [action_id, day, _action_counter]))
	for index in range(pool.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var current: Variant = pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = current


func _remember_topic_seeds(seeds: Array) -> void:
	for raw_seed in seeds:
		var seed_text: String = str(raw_seed).strip_edges()
		if seed_text.is_empty():
			continue
		_recent_topic_seeds.append(seed_text)
	while _recent_topic_seeds.size() > RECENT_TOPIC_SEED_LIMIT:
		_recent_topic_seeds.pop_front()


func _build_entry_url(action_id: String, day: int) -> String:
	return "community://feed/%s/day-%d/%d" % [action_id, day, _action_counter]


func _build_feed_entry(action_meta: Dictionary, posts: Array, source_type: String = "llm") -> Dictionary:
	_entry_counter += 1
	var action: Dictionary = action_meta.get("action", {})
	var selected_seeds: Array = action_meta.get("selected_seeds", [])
	return {
		"entry_id": "community_feed_%d" % _entry_counter,
		"url": str(action_meta.get("url", "")),
		"action_id": str(action_meta.get("action_id", "")),
		"action_title": str(action.get("title", "社区行动")),
		"title": _build_entry_title(action_meta, posts),
		"summary": _build_entry_summary(action_meta, posts),
		"day": int(action_meta.get("day", 1)),
		"phase": str(action_meta.get("phase", "")),
		"topic_seeds": selected_seeds.duplicate(),
		"posts": posts.duplicate(true),
		"source_type": source_type,
		"created_at": Time.get_unix_time_from_system(),
	}


func _build_entry_title(action_meta: Dictionary, posts: Array) -> String:
	var first_post: Dictionary = _get_lead_post(posts)
	var post_title: String = str(first_post.get("title", "")).strip_edges()
	if not post_title.is_empty():
		return post_title
	var post_content: String = str(first_post.get("content", "")).strip_edges()
	if not post_content.is_empty():
		return _summarize_text(post_content, 32)
	var selected_seeds: Array = action_meta.get("selected_seeds", [])
	if not selected_seeds.is_empty():
		return str(selected_seeds[0])
	return str(action_meta.get("action_id", "社区帖子"))


func _build_entry_summary(action_meta: Dictionary, posts: Array) -> String:
	var first_post: Dictionary = _get_lead_post(posts)
	var post_content: String = str(first_post.get("content", "")).strip_edges()
	if not post_content.is_empty():
		return _summarize_text(post_content, 72)
	var post_title: String = str(first_post.get("title", "")).strip_edges()
	if not post_title.is_empty():
		return post_title
	var selected_seeds: Array = action_meta.get("selected_seeds", [])
	var summary_text: String = " / ".join(PackedStringArray(selected_seeds))
	if not summary_text.is_empty():
		return summary_text
	return str(action_meta.get("action_id", "社区动态"))


func _build_fallback_entry(action_meta: Dictionary) -> Dictionary:
	return _build_feed_entry(action_meta, _build_fallback_posts(action_meta), "fallback")


func _build_fallback_posts(action_meta: Dictionary) -> Array:
	var action_id: String = str(action_meta.get("action_id", ""))
	var selected_seeds: Array = action_meta.get("selected_seeds", [])
	var primary_seed: String = str(selected_seeds[0]) if not selected_seeds.is_empty() else "比赛进度"
	return _sanitize_posts([
		{
			"author": _pick_author("%s_author_0" % action_id),
			"time": _pick_time_text("%s_time_0" % action_id),
			"likes": _pick_metric("%s_like_0" % action_id, 45, 320),
			"title": _build_optional_post_title(action_id, primary_seed),
			"content": _build_fallback_post_text(action_id, primary_seed, 0),
			"reply_list": _build_fallback_replies(primary_seed, 4, "%s_reply_0" % action_id),
		},
	])


func _build_optional_post_title(action_id: String, seed_text: String) -> String:
	match action_id:
		FREE_SEARCH_ACTION_ID:
			return "搜 %s 的时候刷到这串" % seed_text
		RANDOM_SEARCH_ACTION_ID:
			return "随手一刷居然看到：%s" % seed_text
		"follow_contest":
			return "有人开始讨论这个宣传点了"
		"learn_dev":
			return "经验帖｜%s" % seed_text
		_:
			return ""


func _build_fallback_post_text(action_id: String, primary_seed: String, index: int) -> String:
	match action_id:
		FREE_SEARCH_ACTION_ID:
			match index:
				0:
					return "刚搜 %s，首页就跳出这串。楼主说得不一定全对，但底下的讨论还挺像那么回事。" % primary_seed
				1:
					return "搜 %s 的时候看到不少人都在吵这个点，先码住慢慢看。" % primary_seed
				_:
					return "%s 这个关键词下面的讨论比想象中热闹。" % primary_seed
		RANDOM_SEARCH_ACTION_ID:
			match index:
				0:
					return "随手一刷就看到 %s，原本想划走，结果评论区开始认真起来了。" % primary_seed
				1:
					return "今天首页给我推了 %s，这串楼的走向有点出乎意料。" % primary_seed
				_:
					return "%s 这类帖子每次都能把潜水的人炸出来。" % primary_seed
		"chill_browse":
			match index:
				0:
					return "%s 这个话题今天又被顶上来了。我本来只想随手刷两眼，结果一口气翻了十几楼。" % primary_seed
				1:
					return "看到大家都在聊 %s，笑得根本停不下来。" % primary_seed
				_:
					return "说真的，%s 这种帖子就是纯粹的快乐源泉。" % primary_seed
		"learn_dev":
			match index:
				0:
					return "关于 %s，我总结了几个自己踩过的坑，希望能帮到后来人。" % primary_seed
				1:
					return "最近在研究 %s，发现很多新手都会忽略这几个关键点。" % primary_seed
				_:
					return "%s 这块其实门道挺深的，分享一个我最近刚学到的技巧。" % primary_seed
		"follow_contest":
			match index:
				0:
					return "刚刷到一条开发宣传，居然把 %s 当成主卖点。我先记个关注，至少比空喊理想强。" % primary_seed
				1:
					return "有人拿 %s 做切口宣传，其实还挺聪明的，但最后还是得看内容能不能接住。" % primary_seed
				_:
					return "宣传文案里提到 %s，我的第一反应是别把这个卖点讲得太轻飘。" % primary_seed
		_:
			return "%s 这件事现在已经有人开始认真聊了。" % primary_seed


func _build_fallback_replies(seed_text: String, count: int, seed_key: String) -> Array:
	var replies: Array = []
	for index in range(count):
		var pool: PackedStringArray = SUPPORT_REPLIES if index % 2 == 0 else SKEPTIC_REPLIES
		replies.append({
			"author": _pick_author("%s_author_%d" % [seed_key, index]),
			"time": _pick_time_text("%s_time_%d" % [seed_key, index]),
			"likes": _pick_metric("%s_like_%d" % [seed_key, index], 1, 28),
			"content": "%s %s" % [seed_text, _pick_from_pool(pool, "%s_text_%d" % [seed_key, index])],
			"sub_reply_list": _build_fallback_sub_replies(seed_text, 1 + (index % 2), "%s_sub_%d" % [seed_key, index]),
		})
	return replies


func _build_fallback_sub_replies(seed_text: String, count: int, seed_key: String) -> Array:
	var replies: Array = []
	for index in range(count):
		replies.append({
			"author": _pick_author("%s_author_%d" % [seed_key, index]),
			"time": _pick_time_text("%s_time_%d" % [seed_key, index]),
			"likes": _pick_metric("%s_like_%d" % [seed_key, index], 0, 12),
			"content": "%s %s" % [seed_text, _pick_from_pool(SUPPORT_REPLIES if index % 2 == 0 else SKEPTIC_REPLIES, "%s_text_%d" % [seed_key, index])],
		})
	return replies


func _sanitize_posts(posts: Array) -> Array:
	var normalized: Array = []
	for raw_post in posts:
		if not raw_post is Dictionary:
			continue
		var post: Dictionary = raw_post.duplicate(true)
		var replies: Array = []
		for raw_reply in post.get("reply_list", []):
			if not raw_reply is Dictionary:
				continue
			var reply: Dictionary = raw_reply.duplicate(true)
			var sub_replies: Array = []
			for raw_sub_reply in reply.get("sub_reply_list", []):
				if not raw_sub_reply is Dictionary:
					continue
				var sub_reply: Dictionary = raw_sub_reply.duplicate(true)
				sub_reply["author"] = str(sub_reply.get("author", "匿名用户")).strip_edges()
				sub_reply["time"] = str(sub_reply.get("time", "")).strip_edges()
				sub_reply["likes"] = int(sub_reply.get("likes", 0))
				sub_reply["content"] = str(sub_reply.get("content", "")).strip_edges()
				if not str(sub_reply.get("content", "")).strip_edges().is_empty():
					sub_replies.append(sub_reply)
			reply["author"] = str(reply.get("author", "匿名用户")).strip_edges()
			reply["time"] = str(reply.get("time", "")).strip_edges()
			reply["likes"] = int(reply.get("likes", 0))
			reply["content"] = str(reply.get("content", "")).strip_edges()
			reply["sub_reply_list"] = sub_replies
			reply["replies"] = sub_replies.size()
			if not str(reply.get("content", "")).strip_edges().is_empty():
				replies.append(reply)
		post["author"] = str(post.get("author", "匿名用户")).strip_edges()
		post["time"] = str(post.get("time", "刚刚")).strip_edges()
		post["likes"] = int(post.get("likes", 0))
		post["content"] = str(post.get("content", "")).strip_edges()
		post["title"] = str(post.get("title", "")).strip_edges()
		post["reply_list"] = replies
		post["replies"] = replies.size()
		if not str(post.get("content", "")).strip_edges().is_empty():
			normalized.append(post)
	return normalized


func _register_entry(entry: Dictionary) -> Dictionary:
	_feed_entries.push_front(entry.duplicate(true))
	while _feed_entries.size() > FEED_LIMIT:
		_feed_entries.pop_back()
	community_feed_updated.emit()
	return entry.duplicate(true)


func _get_first_post(entry: Dictionary) -> Dictionary:
	return _get_lead_post(entry.get("posts", []))


func _get_lead_post(posts: Array) -> Dictionary:
	if posts.is_empty() or not posts[0] is Dictionary:
		return {}
	return posts[0].duplicate(true)


func _summarize_text(text: String, limit: int = 48) -> String:
	var cleaned: String = text.strip_edges().replace("\n", " ")
	if cleaned.length() <= limit:
		return cleaned
	return cleaned.substr(0, limit) + "..."


func _pick_author(seed_key: String) -> String:
	return _pick_from_pool(DEFAULT_AUTHORS, seed_key)


func _pick_time_text(seed_key: String) -> String:
	return _pick_from_pool(DEFAULT_TIME_TEXTS, seed_key)


func _pick_metric(seed_key: String, min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	return min_value + abs(hash(seed_key)) % (max_value - min_value + 1)


func _pick_from_pool(pool: PackedStringArray, seed_key: String) -> String:
	if pool.is_empty():
		return ""
	return str(pool[abs(hash(seed_key)) % pool.size()])


func _get_current_day() -> int:
	var glm: Node = _get_root_node("GameLoopManager")
	if glm != null:
		return int(glm.get("current_day"))
	var tm: Node = _get_root_node("TimeManager")
	if tm != null and tm.has_method("get_day"):
		return tm.get_day()
	return 1


func _get_current_phase_display_name() -> String:
	var glm: Node = _get_root_node("GameLoopManager")
	if glm != null and glm.has_method("get_phase_display_name"):
		return str(glm.get_phase_display_name(glm.get("time_phase")))
	return "当前时段"


func _get_root_node(node_name: String) -> Node:
	var normalized_name: String = node_name.strip_edges()
	if normalized_name.is_empty():
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(normalized_name)
