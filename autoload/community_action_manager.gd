extends Node

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const ActivityChatClass = preload("res://scripts/activity/activity_chat.gd")

signal community_action_started(action_id: String, request_id: String)
signal community_action_completed(action_id: String, entry: Dictionary)
signal community_action_failed(action_id: String, error: String)

const PAGE_PROMPT_KEY: String = "browser_webpage"
const COMMUNITY_DATA_PATH: String = "res://resources/data/browser/browser_content.json"
const LIN_XIA_CHANNEL_ID: String = "dm_lin_xia"
const LIN_XIA_NPC_ID: String = "npc_lin_xia"

@onready var _ai_service: Node = $AIService

var _pending_requests: Dictionary = {}
var _action_definitions: Dictionary = {}
var _community_content: Dictionary = {}
var _action_counter: int = 0
var _chat: RefCounted = null
var _pending_followups: Dictionary = {}


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
		"当前上网活动还在进行，请先等待反馈。"
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
	_ai_service.default_temperature = 0.7


func get_available_actions() -> Array:
	var actions: Array = []
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	for action_id in _action_definitions.keys():
		var data: Dictionary = _action_definitions[action_id].duplicate(true)
		var ap_cost: int = int(data.get("ap_cost", 1))
		var aliases: Array[String] = _build_activity_aliases(action_id, data)
		var blocked_reason: String = ActivityLockUtilsClass.get_narrative_blocking_reason_for_any(aliases)
		if blocked_reason.is_empty():
			data["enabled"] = glm != null and glm.can_consume_ap(ap_cost)
			if not bool(data.get("enabled", false)) and glm != null:
				data["blocked_reason"] = "当前行动力不足"
		else:
			data["enabled"] = false
			data["blocked_reason"] = blocked_reason
		actions.append(data)

	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)
	return actions


func perform_action(action_id: String) -> Dictionary:
	var normalized_id := action_id.strip_edges()
	if normalized_id.is_empty() or not _action_definitions.has(normalized_id):
		return {"success": false, "error": "未知的社区行动"}

	var action: Dictionary = _action_definitions[normalized_id]
	var blocking_reason: String = ActivityLockUtilsClass.get_narrative_blocking_reason_for_any(_build_activity_aliases(normalized_id, action))
	if not blocking_reason.is_empty():
		return {"success": false, "error": blocking_reason}

	var ap_cost: int = int(action.get("ap_cost", 1))
	var action_type: String = str(action.get("action_type", "community"))
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return {"success": false, "error": "GameLoopManager 不可用"}
	if not glm.can_consume_ap(ap_cost):
		return {"success": false, "error": "当前无法执行这个行动"}

	_action_counter += 1
	var day: int = _get_current_day()
	var site: Dictionary = _pick_site_for_action(normalized_id, day)
	var topic: Dictionary = _pick_topic_for_action(normalized_id, day)
	var url: String = _build_action_url(site, topic, normalized_id, day)

	var action_meta := {
		"action_id": normalized_id,
		"action": action.duplicate(true),
		"site": site.duplicate(true),
		"topic": topic.duplicate(true),
		"url": url,
	}

	var messages := _build_action_page_messages(normalized_id, action, site, topic)
	var request_id: String = _ai_service.chat(messages, {
		"temperature": 0.7,
		"max_tokens": 8192
	})
	if request_id.is_empty():
		var payload := _build_web_action_page(normalized_id, action)
		var entry := _register_payload(normalized_id, payload)
		_finalize_action_entry(normalized_id, entry, action_meta)
		return {
			"success": true,
			"entry_id": entry.get("entry_id", ""),
			"url": entry.get("url", ""),
			"title": entry.get("title", ""),
			"async": false
		}

	_pending_requests[request_id] = {
		"kind": "action_page",
		"action_meta": action_meta
	}
	community_action_started.emit(normalized_id, request_id)
	return {
		"success": true,
		"url": url,
		"title": str(topic.get("direction", action.get("title", ""))),
		"async": true,
		"request_id": request_id
	}


func get_recent_entries(limit: int = 8) -> Array:
	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser == null or not browser.has_method("get_history_entries"):
		return []

	var entries: Array = browser.get_history_entries(100)
	var filtered: Array = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var action_id: String = str(entry.get("action_id", "")).strip_edges()
		if action_id.is_empty() or not _action_definitions.has(action_id):
			continue
		filtered.append((entry as Dictionary).duplicate(true))
		if limit > 0 and filtered.size() >= limit:
			break
	return filtered


func has_pending_requests() -> bool:
	return not _pending_requests.is_empty()


func _build_activity_aliases(action_id: String, action: Dictionary) -> Array[String]:
	var aliases: Array[String] = ["community", action_id]
	var action_type: String = str(action.get("action_type", "")).strip_edges()
	if not action_type.is_empty() and action_type not in aliases:
		aliases.append(action_type)
	return aliases


func _load_community_content() -> void:
	_community_content.clear()
	_action_definitions.clear()
	if not FileAccess.file_exists(COMMUNITY_DATA_PATH):
		push_warning("CommunityActionManager: community content file missing: %s" % COMMUNITY_DATA_PATH)
		return

	var file := FileAccess.open(COMMUNITY_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("CommunityActionManager: failed to open community content file")
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not parsed is Dictionary:
		push_warning("CommunityActionManager: invalid community content json")
		return

	_community_content = parsed
	for action in _community_content.get("actions", []):
		if action is Dictionary and action.has("action_id"):
			_action_definitions[str(action.get("action_id", ""))] = action


func _resolve_prompt(key: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null or not pm.has_method("resolve"):
		return ""
	return str(pm.resolve(key))


func _extract_content(response: Dictionary) -> String:
	if response.has("choices") and response["choices"] is Array and response["choices"].size() > 0:
		var choice: Dictionary = response["choices"][0]
		var message: Dictionary = choice.get("message", {})
		var message_content: Variant = message.get("content", "")
		if message_content is String:
			return message_content.strip_edges()
	return ""


func _parse_page_content(text: String) -> Dictionary:
	var stripped := text.strip_edges()
	if stripped.begins_with("```"):
		var first_nl := stripped.find("\n")
		if first_nl >= 0:
			stripped = stripped.substr(first_nl + 1)
		if stripped.ends_with("```"):
			stripped = stripped.substr(0, stripped.length() - 3)
		stripped = stripped.strip_edges()

	if stripped.begins_with("{"):
		var parsed: Variant = JSON.parse_string(stripped)
		if parsed is Dictionary:
			if parsed.has("content") and parsed["content"] is Dictionary:
				return parsed["content"]
			return parsed
		return {}

	if stripped.find("<") >= 0:
		var dsl_result := DslPageParser.parse(stripped)
		if not dsl_result.is_empty():
			return dsl_result

	var parsed_fallback: Variant = JSON.parse_string(stripped)
	if parsed_fallback is Dictionary:
		return parsed_fallback
	return {}


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if not _pending_requests.has(request_id):
		return

	var meta: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)

	var content: String = _extract_content(response)
	var _kind: String = str(meta.get("kind", ""))
	if content.is_empty():
		_handle_action_page_failed(meta, "LLM 返回为空")
		return

	_handle_action_page_completed(meta, content)


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _pending_requests.has(request_id):
		return

	var meta: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)
	var _kind: String = str(meta.get("kind", ""))
	_handle_action_page_failed(meta, error)


func _handle_action_page_completed(meta: Dictionary, content: String) -> void:
	var action_meta: Dictionary = meta.get("action_meta", {})
	var action_id: String = str(action_meta.get("action_id", ""))
	var action: Dictionary = action_meta.get("action", {})
	var site: Dictionary = action_meta.get("site", {})
	var topic: Dictionary = action_meta.get("topic", {})
	var url: String = str(action_meta.get("url", ""))

	var page_content: Dictionary = _parse_page_content(content)
	if page_content.is_empty():
		_handle_action_page_fallback(action_meta)
		return

	var title_text: String = str(page_content.get("title", topic.get("direction", action.get("title", ""))))
	var summary_text: String = str(topic.get("direction", ""))
	var payload := {
		"url": url,
		"title": title_text,
		"summary": summary_text,
		"site": site,
		"topic": topic,
		"page": page_content
	}
	var entry := _register_payload(action_id, payload)
	_finalize_action_entry(action_id, entry, action_meta)


func _handle_action_page_failed(meta: Dictionary, error: String) -> void:
	var action_meta: Dictionary = meta.get("action_meta", {})
	var action_id: String = str(action_meta.get("action_id", ""))
	community_action_failed.emit(action_id, error)
	_handle_action_page_fallback(action_meta)


func _handle_action_page_fallback(action_meta: Dictionary) -> void:
	var action_id: String = str(action_meta.get("action_id", ""))
	var action: Dictionary = action_meta.get("action", {})
	var payload := _build_web_action_page(action_id, action)
	var entry := _register_payload(action_id, payload)
	_finalize_action_entry(action_id, entry, action_meta)


func _finalize_action_entry(action_id: String, entry: Dictionary, action_meta: Dictionary) -> void:
	_share_entry_with_lin_xia(action_id, entry, action_meta)
	community_action_completed.emit(action_id, entry.duplicate(true))


func _consume_ap_and_stats(action_id: String, action_meta: Dictionary) -> void:
	var action: Dictionary = action_meta.get("action", {})
	var ap_cost: int = int(action.get("ap_cost", 1))
	var action_type: String = str(action.get("action_type", "community"))
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		glm.consume_ap(ap_cost, action_type, action_id)

	var stat_changes: Dictionary = action.get("stat_changes", {})
	if not stat_changes.is_empty():
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm != null and gm.has_method("modify_stats"):
			gm.modify_stats(stat_changes)


func _share_entry_with_lin_xia(action_id: String, entry: Dictionary, action_meta: Dictionary) -> void:
	if entry.is_empty():
		_consume_ap_and_stats(action_id, action_meta)
		return
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		_consume_ap_and_stats(action_id, action_meta)
		return

	var share_card: Dictionary = _build_followup_card(entry, action_meta)
	if chat.has_method("store_player_message_data"):
		chat.store_player_message_data(LIN_XIA_CHANNEL_ID, {
			"speaker": "player",
			"card": share_card,
		})

	var session_id: String = "community_%d" % _action_counter
	var system_prompt: String = _build_followup_prompt(entry, action_meta)
	var started: bool = _chat.start_topic(session_id, "followup", {
		"display_label": "社区行动",
		"system_prompt": system_prompt,
		"goal": "发送社区行动后的短消息",
		"seed_message": "请根据当前话题直接发送活动后回复。",
		"max_turns": 1,
		"timeout_seconds": 60,
	})
	if started:
		_pending_followups[session_id] = {
			"entry": entry.duplicate(true),
			"action_meta": action_meta.duplicate(true),
			"action_id": action_id,
		}
	else:
		var local_reply: String = _build_local_followup_reply(entry, action_meta)
		_chat.send_local_message(local_reply)
		_consume_ap_and_stats(action_id, action_meta)


func _on_chat_stage_completed(session_id: String, _stage: String, _summary: String) -> void:
	if _pending_followups.has(session_id):
		var data: Dictionary = _pending_followups[session_id]
		_consume_ap_and_stats(
			data.get("action_id", ""),
			data.get("action_meta", {}),
		)
		_pending_followups.erase(session_id)


func _on_chat_stage_timeout(session_id: String, stage: String) -> void:
	if stage != "followup":
		return
	if _pending_followups.has(session_id):
		var data: Dictionary = _pending_followups[session_id]
		var reply: String = _build_local_followup_reply(
			data.get("entry", {}), data.get("action_meta", {})
		)
		_chat.send_local_message(reply)
		_consume_ap_and_stats(
			data.get("action_id", ""),
			data.get("action_meta", {}),
		)
		_pending_followups.erase(session_id)


func _build_followup_prompt(entry: Dictionary, action_meta: Dictionary) -> String:
	var action: Dictionary = action_meta.get("action", {})
	var site: Dictionary = action_meta.get("site", {})
	var topic: Dictionary = action_meta.get("topic", {})
	var parts: Array[String] = [
		"你是林夏。",
		"玩家刚完成了一个社区行动：%s" % str(action.get("title", "社区行动")),
		"站点：%s" % str(site.get("display_name", "社区")),
		"页面标题：%s" % str(entry.get("title", "")),
	]
	var summary: String = str(entry.get("summary", "")).strip_edges()
	if not summary.is_empty():
		parts.append("内容简介：%s" % summary)
	var mood: String = str(topic.get("mood", "")).strip_edges()
	if not mood.is_empty():
		parts.append("讨论氛围：%s" % mood)
	parts.append("用一句自然的中文聊天短消息回复，表达你的第一反应。只输出回复正文。")
	return "\n".join(parts)


func _build_followup_card(entry: Dictionary, action_meta: Dictionary) -> Dictionary:
	var entry_site: Dictionary = entry.get("site", {})
	var meta_site: Dictionary = action_meta.get("site", {})
	var site_name: String = str(entry_site.get("display_name", meta_site.get("display_name", "Community"))).strip_edges()
	var summary: String = str(entry.get("summary", "")).strip_edges()
	return {
		"type": "web_page",
		"title": str(entry.get("title", "社区页面")),
		"subtitle": site_name,
		"hint": summary,
		"body": summary,
		"badge": "Community 分享",
		"url": str(entry.get("url", "")),
	}


func _build_local_followup_reply(entry: Dictionary, action_meta: Dictionary) -> String:
	var action_id: String = str(action_meta.get("action_id", "")).strip_edges()
	var summary: String = str(entry.get("summary", "")).strip_edges()
	match action_id:
		"browse_forum":
			if not summary.is_empty():
				return "这串讨论比我想的还热闹，至少不是路过点个赞就散了。"
			return "评论区已经热起来了，说明真的有人在认真看。"
		"post_promo":
			return "这个宣传页已经像回事了，下面开始有人记住你们了。"
		"watch_event":
			return "这种页面越刷越停不下来，我刚也顺着多看了几眼。"
		_:
			return "我看完了，这页起码不是空转，已经有人开始接住它了。"


func _register_payload(action_id: String, payload: Dictionary) -> Dictionary:
	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser != null and browser.has_method("register_generated_page_entry"):
		return browser.register_generated_page_entry(action_id, payload, "community")
	return {}


func _pick_site_for_action(action_id: String, day: int) -> Dictionary:
	var candidates: Array = []
	for site in _community_content.get("sites", []):
		if not site is Dictionary:
			continue
		var supported: Array = site.get("supported_actions", [])
		if supported.has(action_id):
			candidates.append(site)
	if candidates.is_empty():
		return {"site_id": "community", "display_name": "Community", "name": "Community", "url_prefix": "community://"}
	return _seeded_pick_dict(candidates, "%s_site_day_%d" % [action_id, day], candidates[0])


func _pick_topic_for_action(action_id: String, day: int) -> Dictionary:
	var candidates: Array = []
	for topic in _community_content.get("topics", []):
		if not topic is Dictionary:
			continue
		if int(topic.get("min_day", 1)) > day:
			continue
		var valid_actions: Array = topic.get("valid_actions", [])
		if valid_actions.has(action_id):
			candidates.append(topic)
	if candidates.is_empty():
		return {
			"topic_id": "fallback_topic",
			"category": "fallback",
			"direction": "日常社区闲聊",
			"mood": "mixed",
			"seeds": ["日常", "闲聊", "围观"],
			"selected_seeds": ["日常", "闲聊"],
		}
	var picked: Dictionary = _seeded_pick_weighted(candidates, "%s_topic_day_%d_%d" % [action_id, day, _action_counter])
	var result: Dictionary = picked.duplicate(true)
	var all_seeds: Array = result.get("seeds", [])
	result["selected_seeds"] = _pick_random_seeds(all_seeds, "%s_%d_%d" % [action_id, day, _action_counter])
	return result


func _pick_random_seeds(seeds: Array, seed_key: String, count: int = 3) -> Array:
	if seeds.is_empty():
		return []
	if seeds.size() <= count:
		return seeds.duplicate()
	var picked: Array = []
	var available: Array = seeds.duplicate()
	for i in range(count):
		if available.is_empty():
			break
		var idx: int = abs(hash(seed_key + str(i))) % available.size()
		picked.append(str(available[idx]))
		available.remove_at(idx)
	return picked


func _build_action_url(site: Dictionary, topic: Dictionary, action_id: String, day: int) -> String:
	var prefix := str(site.get("url_prefix", "community://"))
	return "%s%s/day-%d/%d" % [prefix, str(topic.get("topic_id", action_id)), day, _action_counter]


func _seeded_pick_weighted(items: Array, seed_key: String) -> Dictionary:
	var total_weight: int = 0
	for item in items:
		total_weight += max(1, int(item.get("weight", 1)))
	if total_weight <= 0:
		return items[0]
	var target: int = abs(hash(seed_key)) % total_weight
	var acc: int = 0
	for item in items:
		acc += max(1, int(item.get("weight", 1)))
		if target < acc:
			return item
	return items[0]


func _seeded_pick_dict(items: Array, seed_key: String, fallback: Dictionary = {}) -> Dictionary:
	if items.is_empty():
		return fallback
	return items[abs(hash(seed_key)) % items.size()]


func _seeded_pick_array(items: Array, seed_key: String, fallback: String = "") -> String:
	if items.is_empty():
		return fallback
	return str(items[abs(hash(seed_key)) % items.size()])


func _get_reply_pool(key: String) -> Array:
	var replies: Dictionary = _community_content.get("replies", {})
	return replies.get(key, [])


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		return int(glm.get("current_day"))
	var tm: Node = get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_method("get_day"):
		return tm.get_day()
	return 1


func _build_web_action_page(action_id: String, action: Dictionary) -> Dictionary:
	var day: int = _get_current_day()
	var site: Dictionary = _pick_site_for_action(action_id, day)
	var topic: Dictionary = _pick_topic_for_action(action_id, day)
	var url: String = _build_action_url(site, topic, action_id, day)
	var site_name: String = str(site.get("display_name", "Community"))
	var seeds_label: String = ", ".join(PackedStringArray(topic.get("selected_seeds", [])))
	var title_text: String = seeds_label if not seeds_label.is_empty() else str(action.get("title", site_name))
	var summary_text: String = str(topic.get("direction", ""))
	var page_content := {
		"title": title_text,
		"type": "margin",
		"margin": 18,
		"child": {
			"type": "vbox",
			"separation": 14,
			"children": [
				_build_site_header(site_name, url),
				_build_web_action_body(action_id, site, topic, title_text, summary_text)
			]
		}
	}
	return {
		"url": url,
		"title": title_text,
		"summary": summary_text,
		"site": site,
		"topic": topic,
		"page": page_content
	}


func _build_site_header(site_name: String, url: String) -> Dictionary:
	return {
		"type": "panel",
		"bg_color": "#182032",
		"padding": 12,
		"child": {
			"type": "vbox",
			"separation": 4,
			"children": [
				{"type": "label", "text": site_name, "font_size": 28, "color": "#ffffff"},
				{"type": "label", "text": url, "font_size": 13, "color": "#90a0bf"}
			]
		}
	}


func _build_web_action_body(action_id: String, site: Dictionary, topic: Dictionary, title_text: String, summary_text: String) -> Dictionary:
	match action_id:
		"post_promo":
			return _build_promo_thread_page(site, topic, title_text, summary_text)
		"watch_event":
			return _build_event_news_page(site, topic, title_text, summary_text)
		_:
			return _build_forum_thread_page(site, topic, title_text, summary_text)


func _build_forum_thread_page(site: Dictionary, topic: Dictionary, title_text: String, summary_text: String) -> Dictionary:
	var site_name: String = str(site.get("display_name", "论坛"))
	var authors: Array = _community_content.get("authors", [])
	var support_pool: Array = _get_reply_pool("support")
	var skeptic_pool: Array = _get_reply_pool("skeptic")
	var gossip_pool: Array = _get_reply_pool("gossip")
	var children: Array = [
		{
			"type": "panel",
			"bg_color": "#24314a",
			"padding": 12,
			"child": {
				"type": "vbox",
				"separation": 6,
				"children": [
					{"type": "label", "text": "[热帖] %s" % title_text, "font_size": 22, "color": "#9fd0ff"},
					{"type": "label", "text": summary_text, "font_size": 16, "color": "#d7dced"},
					{"type": "label", "text": "版块：%s 热门讨论" % site_name, "font_size": 13, "color": "#90a0bf"}
				]
			}
		}
	]
	var reply_seeds: Array = [support_pool, skeptic_pool, gossip_pool]
	for index in range(3):
		var pool: Array = reply_seeds[index]
		var author: String = _seeded_pick_array(authors, "%s_forum_author_%d" % [str(topic.get("topic_id", "topic")), index], "匿名用户")
		var reply_text: String = _seeded_pick_array(pool, "%s_forum_reply_%d" % [str(topic.get("topic_id", "topic")), index], "围观。")
		children.append({
			"type": "panel",
			"bg_color": "#151b28",
			"padding": 12,
			"child": {
				"type": "vbox",
				"separation": 4,
				"children": [
					{"type": "label", "text": author, "font_size": 16, "color": "#ffffff"},
					{"type": "label", "text": reply_text, "font_size": 15, "color": "#c6cede"}
				]
			}
		})
	return {"type": "vbox", "separation": 10, "children": children}


func _build_promo_thread_page(_site: Dictionary, topic: Dictionary, title_text: String, summary_text: String) -> Dictionary:
	var children: Array = [
		{
			"type": "panel",
			"bg_color": "#24314a",
			"padding": 12,
			"child": {
				"type": "vbox",
				"separation": 6,
				"children": [
					{"type": "label", "text": title_text, "font_size": 22, "color": "#9fd0ff"},
					{"type": "label", "text": "作者：jam_duo_studio", "font_size": 14, "color": "#ffffff"},
					{"type": "label", "text": summary_text, "font_size": 16, "color": "#d7dced"}
				]
			}
		}
	]
	var authors: Array = _community_content.get("authors", [])
	var response_pool: Array = _get_reply_pool("support") + _get_reply_pool("skeptic")
	for index in range(3):
		var author: String = _seeded_pick_array(authors, "%s_promo_author_%d" % [str(topic.get("topic_id", "promo")), index], "路人")
		var reply_text: String = _seeded_pick_array(response_pool, "%s_promo_reply_%d" % [str(topic.get("topic_id", "promo")), index], "继续观望。")
		children.append({
			"type": "panel",
			"bg_color": "#151b28",
			"padding": 12,
			"child": {
				"type": "vbox",
				"separation": 4,
				"children": [
					{"type": "label", "text": author, "font_size": 16, "color": "#ffffff"},
					{"type": "label", "text": reply_text, "font_size": 15, "color": "#c6cede"}
				]
			}
		})
	return {"type": "vbox", "separation": 10, "children": children}


func _build_event_news_page(site: Dictionary, _topic: Dictionary, title_text: String, summary_text: String) -> Dictionary:
	var news_items: Array = [
		"关注度榜单发生变化",
		"多支队伍在深夜放出了新截图",
		"讨论区对赛题尺度继续升温"
	]
	var children: Array = [
		{
			"type": "panel",
			"bg_color": "#24314a",
			"padding": 12,
			"child": {
				"type": "vbox",
				"separation": 6,
				"children": [
					{"type": "label", "text": title_text, "font_size": 24, "color": "#ffffff"},
					{"type": "label", "text": summary_text, "font_size": 16, "color": "#d7dced"},
					{"type": "label", "text": "来源：%s 编辑部" % str(site.get("display_name", "资讯站")), "font_size": 13, "color": "#90a0bf"}
				]
			}
		}
	]
	for index in range(news_items.size()):
		children.append({
			"type": "panel",
			"bg_color": "#151b28",
			"padding": 12,
			"child": {
				"type": "vbox",
				"separation": 4,
				"children": [
					{"type": "label", "text": "快讯 %d" % (index + 1), "font_size": 16, "color": "#ffffff"},
					{"type": "label", "text": news_items[index], "font_size": 15, "color": "#c6cede"}
				]
			}
		})
	return {"type": "vbox", "separation": 10, "children": children}


func _build_action_page_messages(action_id: String, action: Dictionary, site: Dictionary, topic: Dictionary) -> Array:
	var gm: Node = get_node_or_null("/root/GameManager")
	var day: int = _get_current_day()
	var state_prompt: String = ""
	if gm != null and gm.has_method("get_llm_state_prompt"):
		state_prompt = gm.get_llm_state_prompt()

	var system_prompt: String = _resolve_prompt(PAGE_PROMPT_KEY)
	if system_prompt.is_empty():
		system_prompt = "你是模拟现代互联网网页内容的生成器。只返回 JSON 对象，不要输出解释。"

	var selected_seeds: Array = topic.get("selected_seeds", [])
	var seeds_text: String = ", ".join(PackedStringArray(selected_seeds))
	var category: String = str(topic.get("category", ""))
	var mood: String = str(topic.get("mood", "mixed"))

	var user_parts: PackedStringArray = []
	user_parts.append("生成一个游戏内网页，模拟玩家在 GameJam 期间浏览社区网站的体验。")
	user_parts.append("行动类型：%s（%s）" % [str(action.get("title", "")), action_id])
	user_parts.append("站点：%s（风格：%s）" % [str(site.get("display_name", "")), str(site.get("tone", ""))])
	user_parts.append("话题类型：%s" % category)
	user_parts.append("氛围：%s" % mood)
	user_parts.append("关键词灵感：%s" % seeds_text)
	user_parts.append("当前天数：Day %d / 45" % day)
	if not state_prompt.is_empty():
		user_parts.append("当前游戏状态：%s" % state_prompt)

	match action_id:
		"browse_forum":
			user_parts.append("请生成一个论坛帖子页面，包含主帖和 3-5 条回复。")
		"post_promo":
			user_parts.append("请生成一个宣传贴页面，玩家发布了开发日志，下方有社区回复。")
		"watch_event":
			user_parts.append("请生成一个比赛资讯页面，包含赛事动态和快讯条目。")

	return [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": "\n".join(user_parts)}
	]
