extends "res://autoload/activity_session_manager.gd"

# =============================================================================
# DateManager — 约会活动管理器
#
# 继承 ActivitySessionManager，额外提供：
# - 地点数据加载（date_locations.json）
# - Important Event 双轨系统（DateEventBuilder）
# =============================================================================

signal date_started(session_id: String, payload: Dictionary)
signal transit_started(session_id: String, payload: Dictionary)
signal transit_progress_updated(session_id: String, progress: float, scene_ready: bool)
signal important_event_started(session_id: String, payload: Dictionary)
signal date_completed(session_id: String, payload: Dictionary)

const DateEventBuilderClass = preload("res://scripts/date_events/date_event_builder.gd")
const DATE_EVENT_PLAYER_SCENE: PackedScene = preload("res://scenes/date_events/date_event_player.tscn")

const DATE_LOCATIONS_PATH: String = "res://resources/data/date_locations.json"
const DEFAULT_TRANSIT_DURATION: float = 8.0
const MAP_CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _locations_by_id: Dictionary = {}
var _location_list: Array[Dictionary] = []
var _date_event_builder: RefCounted = null
var _played_important_events: Dictionary = {}


# =============================================================================
# Overrides
# =============================================================================

func _on_manager_ready() -> void:
	_load_locations()
	_date_event_builder = DateEventBuilderClass.new()


func _get_activity_type() -> String:
	return "date"


func _get_chat_stage_key() -> String:
	return "date_stage"


func _find_entry(entry_id: String) -> Dictionary:
	if _locations_by_id.has(entry_id):
		return (_locations_by_id[entry_id] as Dictionary).duplicate(true)
	return {}


func _build_session(_session_id: String, entry_id: String, entry: Dictionary) -> Dictionary:
	var session: Dictionary = {
		"location_id": entry_id,
		"location": entry.duplicate(true),
		"important_event_available": false,
		"important_event_active": false,
		"important_event_done": false,
		"important_event_id": "",
		"important_event_result": {},
		"important_event_outline": "",
		"important_event_window": null,
		"scene_window_title": "约会中: %s" % str(entry.get("title", "Date")),
	}
	if _date_event_builder != null and _supports_interactive_date_events():
		session["important_event_available"] = _date_event_builder.has_event_for_session(session, _played_important_events)
	return session


func _on_session_begin(session: Dictionary) -> void:
	_send_player_location_card(session.get("location", {}))


func _should_generate_scene_extra(session: Dictionary) -> bool:
	if not _supports_interactive_date_events():
		return false
	if bool(session.get("important_event_available", false)):
		return false
	return true


func _on_progress_completed_hook(session_id: String) -> bool:
	if _should_start_important_event(session_id):
		if _start_important_event(session_id):
			return true
	return false


func _get_display_label(session: Dictionary) -> String:
	return str(session.get("location", {}).get("title", "date"))


func _get_moment_hint(session: Dictionary) -> String:
	return str(session.get("location", {}).get("moment_hint", ""))


func _build_completed_payload(session: Dictionary) -> Dictionary:
	return {
		"location": session.get("location", {}),
		"important_event_result": session.get("important_event_result", {}),
		"reward_money": int(session.get("reward_money", 0)),
	}


# =============================================================================
# Public API (backward compatibility)
# =============================================================================

func get_available_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var can_act: bool = glm != null and glm.can_consume_ap(1)
	for location in _location_list:
		var loc_entry: Dictionary = location.duplicate(true)
		loc_entry["enabled"] = can_act
		result.append(loc_entry)
	return result


func begin_date(location_id: String, transit_duration: float = DEFAULT_TRANSIT_DURATION) -> Dictionary:
	var result := begin_session(location_id, transit_duration)
	if result.get("success", false):
		var sid: String = str(result.get("session_id", ""))
		date_started.emit(sid, result)
	return result


func is_important_event_active(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	return bool((_pending_sessions[session_id] as Dictionary).get("important_event_active", false))


func get_run_state() -> Dictionary:
	return {
		"played_important_events": _played_important_events.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_played_important_events.clear()
	var events_state: Variant = data.get("played_important_events", {})
	if events_state is Dictionary:
		_played_important_events = (events_state as Dictionary).duplicate(true)
	return true


func _on_reset_runtime_state() -> void:
	_played_important_events.clear()


# =============================================================================
# Signal Bridges (emit legacy signals from base class signals)
# =============================================================================

func _ready() -> void:
	super._ready()
	progress_phase_started.connect(_on_base_progress_started)
	progress_updated.connect(_on_base_progress_updated)
	session_completed.connect(_on_base_session_completed)


func _on_base_progress_started(session_id: String, payload: Dictionary) -> void:
	transit_started.emit(session_id, payload)


func _on_base_progress_updated(session_id: String, progress: float, scene_ready: bool) -> void:
	transit_progress_updated.emit(session_id, progress, scene_ready)


func _on_base_session_completed(session_id: String, payload: Dictionary) -> void:
	date_completed.emit(session_id, payload)


# =============================================================================
# Important Event (Dual-Track) — DateManager exclusive
# =============================================================================

func _supports_interactive_date_events() -> bool:
	return not ActivityUtilsClass.is_test_scene()


func _should_start_important_event(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	if not _supports_interactive_date_events():
		return false
	var session: Dictionary = _pending_sessions[session_id]
	if not bool(session.get("important_event_available", false)):
		return false
	if bool(session.get("important_event_active", false)):
		return false
	if bool(session.get("important_event_done", false)):
		return false
	return true


func _start_important_event(session_id: String) -> bool:
	if not _pending_sessions.has(session_id) or _date_event_builder == null:
		return false

	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	var request: Dictionary = _date_event_builder.build_event_request(session, _played_important_events)
	if not bool(request.get("success", false)):
		return false

	var player: Control = DATE_EVENT_PLAYER_SCENE.instantiate() as Control
	if player == null:
		return false

	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		player.queue_free()
		return false
	var window_manager: Node = app_manager.get("window_manager")
	if window_manager == null or not window_manager.has_method("create_window"):
		player.queue_free()
		return false

	var window: Control = window_manager.create_window(str(request.get("window_title", "重要约会")), player)
	if window == null:
		player.queue_free()
		return false

	window.size = Vector2(1280, 720)
	call_deferred("_center_event_window", window)

	var close_button := window.get_node_or_null("TitleBar/ButtonContainer/CloseButton") as Button
	if close_button != null:
		close_button.visible = false
	var minimize_button := window.get_node_or_null("TitleBar/ButtonContainer/MinimizeButton") as Button
	if minimize_button != null:
		minimize_button.visible = false
	var maximize_button := window.get_node_or_null("TitleBar/ButtonContainer/MaximizeButton") as Button
	if maximize_button != null:
		maximize_button.visible = false
	window.set("resizable", false)

	session["important_event_active"] = true
	session["important_event_id"] = str(request.get("event_id", ""))
	session["important_event_outline"] = AVGSceneGeneratorClass.build_narrative_outline_from_scene(request.get("scene", null))
	session["important_event_window"] = window
	_pending_sessions[session_id] = session

	if player.has_signal("playback_finished"):
		player.connect("playback_finished", Callable(self, "_on_important_event_finished"))
	if player.has_method("play_event"):
		player.call("play_event", session_id, request)

	important_event_started.emit(session_id, {
		"session_id": session_id,
		"event_id": str(request.get("event_id", "")),
		"title": str(request.get("title", "重要约会")),
	})
	return true


func _center_event_window(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	await get_tree().process_frame
	var parent := window.get_parent_control()
	if parent != null:
		window.position = (parent.size - window.size) / 2.0


func _on_important_event_finished(session_id: String, outcome: Dictionary) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["important_event_active"] = false
	session["important_event_done"] = true
	session["important_event_result"] = outcome.duplicate(true)
	_pending_sessions[session_id] = session

	var event_id := str(session.get("important_event_id", ""))
	if not event_id.is_empty():
		_played_important_events[event_id] = true

	SceneWindowClass.close(session.get("important_event_window", null))
	session["important_event_window"] = null
	_pending_sessions[session_id] = session

	var game_manager: Node = get_node_or_null("/root/GameManager")
	var affection_delta := int(outcome.get("affection_delta", 0))
	if game_manager != null and affection_delta != 0 and game_manager.has_method("modify_stat"):
		game_manager.modify_stat("affection", affection_delta)

	_start_followup_phase(session_id)


# =============================================================================
# Topic / Prompt Building
# =============================================================================

func _build_topic_prompt(session: Dictionary, stage: String) -> String:
	var location: Dictionary = session.get("location", {})
	var title := str(location.get("title", "未命名地点")).strip_edges()
	var detail_prompt := str(session.get("detail_prompt", "")).strip_edges()
	var important_result: Dictionary = session.get("important_event_result", {})
	var important_event_outline := str(session.get("important_event_outline", "")).strip_edges()
	var normal_scene_result: Dictionary = session.get("scene_result", {})
	var normal_scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var parts: Array[String] = [
		"你是林夏。",
		"约会地点: %s" % title,
	]
	if not detail_prompt.is_empty():
		parts.append("地点设定: %s" % detail_prompt)
	if not important_result.is_empty():
		parts.append("重要约会里的玩家选择: %s" % str(important_result.get("choice_text", "")))
		parts.append("重要约会结果摘要: %s" % str(important_result.get("summary", "")))
	if not normal_scene_result.is_empty():
		parts.append("这次约会场景里的玩家选择: %s" % str(normal_scene_result.get("choice_text", "")))
	if not important_event_outline.is_empty():
		parts.append("重要约会 AVG 文本摘要:\n%s" % important_event_outline)
	if not normal_scene_outline.is_empty():
		parts.append("这次约会 AVG 文本摘要:\n%s" % normal_scene_outline)
	parts.append("请根据地点信息、人物状态和 AVG 文本自然续写，不要套预设模板。")
	match stage:
		"departure":
			parts.append("当前时刻: 玩家刚刚在 LinkChat 发来地点卡，邀请你去这个地方。")
			parts.append("你现在只需要发送一条出发前的即时短消息。")
			parts.append("不要提前描写到达后发生的事，也不要总结整次约会。")
		"followup":
			parts.append("当前时刻: 这次约会已经结束，你正在回程或刚回到宿舍。")
			parts.append("你现在只需要发送一条约会后的 followup 短消息。")
			parts.append("让语气自然延续前面的场景，不要写成总结报告。")
		_:
			parts.append("请发送一条自然的短消息。")
	return "\n".join(parts)


func _build_topic_goal(stage: String) -> String:
	if stage == "departure":
		return "发送出发前短消息"
	if stage == "followup":
		return "发送约会后的 followup"
	return "发送一条自然短消息"


func _build_seed_message(stage: String) -> String:
	if stage == "departure":
		return "请根据当前话题直接发送出发前回复。"
	if stage == "followup":
		return "请根据当前话题直接发送约会后的回复。"
	return "请直接回复。"


func _build_moment_system_prompt() -> String:
	return "你是林夏。你要发一条刚结束约会后的朋友圈。只返回一条中文纯文本动态，不要 JSON，不要解释，不要加引号，不要超过 36 字。"


func _build_moment_user_prompt(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title := str(location.get("title", "未命名地点")).strip_edges()
	var detail_prompt := str(session.get("detail_prompt", "")).strip_edges()
	var important_result: Dictionary = session.get("important_event_result", {})
	var important_event_outline := str(session.get("important_event_outline", "")).strip_edges()
	var normal_scene_result: Dictionary = session.get("scene_result", {})
	var normal_scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var parts: Array[String] = [
		"地点: %s" % title,
	]
	if not detail_prompt.is_empty():
		parts.append("地点设定: %s" % detail_prompt)
	if not important_result.is_empty():
		parts.append("重要约会结果摘要: %s" % str(important_result.get("summary", "")))
	if not normal_scene_result.is_empty():
		parts.append("这次约会场景里的玩家选择: %s" % str(normal_scene_result.get("choice_text", "")))
	if not important_event_outline.is_empty():
		parts.append("重要约会 AVG 文本摘要:\n%s" % important_event_outline)
	if not normal_scene_outline.is_empty():
		parts.append("这次约会 AVG 文本摘要:\n%s" % normal_scene_outline)
	parts.append("请根据上面的约会信息和 AVG 文本，自行判断最自然的朋友圈语气。")
	parts.append("输出一条像随手发出的朋友圈，不要提系统，不要写成长文。")
	return "\n".join(parts)


# =============================================================================
# Local Fallback Text
# =============================================================================

func _build_local_departure_reply(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "这里")).strip_edges()
	var transit_label: String = str(location.get("transit_label", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_depart")), 3)
	match variant:
		0:
			if not transit_label.is_empty():
				return "好，等我一下。去%s的路上别把我落下。" % title
			return "好，那就去%s。你先别走太快。" % title
		1:
			return "行，今晚就去%s。见面再说。" % title
		_:
			return "可以，去%s吧。和你一起出门至少不会无聊。" % title


func _build_local_followup_reply(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "今晚")).strip_edges()
	var important_result: Dictionary = session.get("important_event_result", {})
	var normal_scene_result: Dictionary = session.get("scene_result", {})
	var choice_text: String = str(normal_scene_result.get("choice_text", important_result.get("choice_text", ""))).strip_edges()
	var summary_text: String = str(important_result.get("summary", "")).strip_edges()
	var outline_hint: String = _extract_outline_hint([
		session.get("scene_outline", ""),
		session.get("important_event_outline", ""),
	])
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_follow")), 3)
	if not choice_text.is_empty():
		return "刚才你接那句「%s」的时候，我一下子就不想太快结束今晚了。" % choice_text
	if not summary_text.is_empty():
		return "回来的路上还在想%s。今晚去%s，值了。" % [summary_text, title]
	if not outline_hint.is_empty():
		return "回来的路上还在回味%s。今晚去%s，挺好。" % [outline_hint, title]
	match variant:
		0:
			return "今晚和你一起去%s，整个人都慢慢松下来了。" % title
		1:
			return "刚才有些话在路上没说完，不过今晚去%s这件事本身就挺好。" % title
		_:
			return "今晚去%s之后，回来的路都显得安静了一点。" % title


func _build_local_moment_text(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "今晚")).strip_edges()
	var outline_hint: String = _extract_outline_hint([
		session.get("scene_outline", ""),
		session.get("important_event_outline", ""),
	])
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_moment")), 3)
	if not outline_hint.is_empty():
		return "今晚的%s，好像还停在%s里。" % [title, outline_hint]
	match variant:
		0:
			return "今晚去%s，回来的风都慢了一点。" % title
		1:
			return "关于%s，还是想再回味一下。" % title
		_:
			return "今晚的%s，像被我偷偷留住了一会儿。" % title


# =============================================================================
# Player Activity Card
# =============================================================================

func _send_player_location_card(location: Dictionary) -> void:
	var chat: Node = ActivityUtilsClass.get_chat_manager()
	if chat == null or not chat.has_method("store_player_message_data"):
		return
	chat.store_player_message_data(ActivityChatClass.DM_CHANNEL_ID, {
		"speaker": "player",
		"card": {
			"type": "location",
			"title": str(location.get("title", "未命名地点")),
			"subtitle": str(location.get("subtitle", "")),
			"body": str(location.get("description", "")),
			"footer": str(location.get("transit_label", "")),
			"badge": "位置共享",
			"accent_color": str(location.get("accent_color", "#5AA9FF")),
		}
	})


# =============================================================================
# Location Loading
# =============================================================================

func _load_locations() -> void:
	_locations_by_id.clear()
	_location_list.clear()

	if not FileAccess.file_exists(DATE_LOCATIONS_PATH):
		push_warning("[DateManager] Missing location data: %s" % DATE_LOCATIONS_PATH)
		return

	var file := FileAccess.open(DATE_LOCATIONS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[DateManager] Failed to open location data")
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		push_warning("[DateManager] Invalid location data format")
		return

	for item in parsed:
		if not item is Dictionary:
			continue
		var location := _build_location_entry(item)
		var loc_id := str(location.get("location_id", ""))
		if loc_id.is_empty():
			continue
		_locations_by_id[loc_id] = location
		_location_list.append(location)

	_location_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 999)) < int(b.get("order", 999))
	)
	print("[DateManager] Loaded %d date locations" % _location_list.size())


func _build_location_entry(raw: Dictionary) -> Dictionary:
	var loc_entry: Dictionary = raw.duplicate(true)
	var zone_path := str(raw.get("zone_path", "")).strip_edges()
	if not zone_path.is_empty() and ResourceLoader.exists(zone_path):
		var zone: Resource = load(zone_path)
		if zone != null:
			if loc_entry.get("location_id", "").is_empty() and "zone_id" in zone:
				loc_entry["location_id"] = zone.zone_id
			if loc_entry.get("title", "").is_empty() and "zone_name" in zone:
				loc_entry["title"] = zone.zone_name
			if "center_position" in zone:
				var center: Vector2 = zone.center_position
				loc_entry["map_position"] = Vector2(
					clampf(center.x / MAP_CANVAS_SIZE.x, 0.0, 1.0),
					clampf(center.y / MAP_CANVAS_SIZE.y, 0.0, 1.0)
				)

	if not loc_entry.has("map_position"):
		loc_entry["map_position"] = Vector2(0.5, 0.5)
	return loc_entry
