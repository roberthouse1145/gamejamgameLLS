extends "res://autoload/activity_session_manager.gd"

const ActivityCatalogProtocolClass = preload("res://scripts/activity/activity_catalog_protocol.gd")
const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")

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

const DATE_LOCATIONS_PATH: String = "res://resources/data/date_locations.json"
const DATE_EVENTS_INITIAL_PATH: String = "res://resources/data/date_events_initial.json"
const DEFAULT_TRANSIT_DURATION: float = 20.0
const MAP_CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _locations_by_id: Dictionary = {}
var _location_list: Array[Dictionary] = []
var _daily_events: Array[Dictionary] = []
var _events_by_id: Dictionary = {}
var _date_event_builder: RefCounted = null
var _played_important_events: Dictionary = {}
var _avg_history: Array = []
var _avg_history_replay_payloads: Dictionary = {}


# =============================================================================
# Overrides
# =============================================================================

func _on_manager_ready() -> void:
	_load_locations()
	_date_event_builder = DateEventBuilderClass.new()
	_load_initial_events()


func _get_activity_type() -> String:
	return "date"


func _get_chat_stage_key() -> String:
	return "date_stage"


func _find_entry(entry_id: String) -> Dictionary:
	if _events_by_id.has(entry_id):
		return (_events_by_id[entry_id] as Dictionary).duplicate(true)
	# Fallback to locations for backward compat (important events)
	if _locations_by_id.has(entry_id):
		return (_locations_by_id[entry_id] as Dictionary).duplicate(true)
	return {}


func _build_session(_session_id: String, entry_id: String, entry: Dictionary) -> Dictionary:
	var session: Dictionary = {
		"event_id": str(entry.get("event_id", entry_id)),
		"location_id": str(entry.get("location_id", entry_id)),
		"location": entry.duplicate(true),
		"rewards": (entry.get("rewards", {}) as Dictionary).duplicate(true),
		"important_event_available": false,
		"important_event_active": false,
		"important_event_done": false,
		"important_event_id": "",
		"important_event_result": {},
		"important_event_outline": "",
		"important_event_window": null,
		"scene_window_title": "约会中：%s" % str(entry.get("title", "Date")),
	}
	if _date_event_builder != null and _supports_interactive_date_events():
		session["important_event_available"] = _date_event_builder.has_event_for_session(session, _played_important_events)
	return session


func _on_session_begin(session: Dictionary) -> void:
	if str(session.get("session_origin", "")).strip_edges() == "npc_initiative":
		return
	_send_player_event_card(session.get("location", {}))


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


func _build_completed_payload(session: Dictionary) -> Dictionary:
	return {
		"location": session.get("location", {}),
		"important_event_result": session.get("important_event_result", {}),
		"rewards": _collect_session_rewards(session),
		"event_id": str(session.get("event_id", "")),
	}


# =============================================================================
# Public API (backward compatibility)
# =============================================================================

func get_available_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var can_act: bool = glm != null and glm.can_consume_ap(1)
	var current_phase := _get_current_phase()
	for evt in _daily_events:
		var valid_phases: Array = evt.get("valid_phases", [])
		if not valid_phases.is_empty() and not valid_phases.has(current_phase):
			continue
		var entry: Dictionary = evt.duplicate(true)
		entry["enabled"] = can_act
		result.append(entry)
	return result


## Backward compat wrapper
func get_available_locations() -> Array[Dictionary]:
	return get_available_events()


func begin_date(event_id: String, transit_duration: float = DEFAULT_TRANSIT_DURATION, skip_departure: bool = false) -> Dictionary:
	var result := begin_session(event_id, transit_duration, skip_departure)
	if result.get("success", false):
		var sid: String = str(result.get("session_id", ""))
		date_started.emit(sid, result)
	return result


func is_important_event_active(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	return bool((_pending_sessions[session_id] as Dictionary).get("important_event_active", false))


func get_run_state() -> Dictionary:
	# Serialize daily events with map_position as arrays for JSON compat
	var serialized_events: Array = []
	for evt in _daily_events:
		var s_evt: Dictionary = evt.duplicate(true)
		var pos: Variant = s_evt.get("map_position", null)
		if pos is Vector2:
			s_evt["map_position"] = [pos.x, pos.y]
		serialized_events.append(s_evt)
	var serialized_pending: Array = []
	for evt in _pending_next_day_events:
		var s_evt: Dictionary = evt.duplicate(true)
		var ppos: Variant = s_evt.get("map_position", null)
		if ppos is Vector2:
			s_evt["map_position"] = [ppos.x, ppos.y]
		serialized_pending.append(s_evt)
	return {
		"played_important_events": _played_important_events.duplicate(true),
		"avg_history": _avg_history.duplicate(true),
		"daily_events": serialized_events,
		"pending_next_day_events": serialized_pending,
	}


func load_run_state(data: Dictionary) -> bool:
	_played_important_events.clear()
	var events_state: Variant = data.get("played_important_events", {})
	if events_state is Dictionary:
		_played_important_events = (events_state as Dictionary).duplicate(true)
	var history_state: Variant = data.get("avg_history", [])
	if history_state is Array:
		_avg_history = (history_state as Array).duplicate(true)
	else:
		_avg_history = []
	var saved_events: Variant = data.get("daily_events", [])
	if saved_events is Array and (saved_events as Array).size() > 0:
		set_daily_events(saved_events as Array)
	_pending_next_day_events.clear()
	var saved_pending: Variant = data.get("pending_next_day_events", [])
	if saved_pending is Array:
		for item in (saved_pending as Array):
			if item is Dictionary:
				_pending_next_day_events.append(item as Dictionary)
	return true


func get_avg_history() -> Array:
	var result: Array = _avg_history.duplicate(true)
	for i in range(result.size()):
		if not result[i] is Dictionary:
			continue
		var entry: Dictionary = (result[i] as Dictionary).duplicate(true)
		var session_id := str(entry.get("session_id", "")).strip_edges()
		entry["has_replay"] = _avg_history_replay_payloads.has(session_id)
		if entry["has_replay"]:
			entry["replay_type"] = str((_avg_history_replay_payloads[session_id] as Dictionary).get("type", ""))
		result[i] = entry
	return result


func add_avg_history_entry(entry: Dictionary) -> void:
	_avg_history.insert(0, _sanitize_avg_history_entry(entry))
	if _avg_history.size() > 50:
		_avg_history.resize(50)


func register_avg_history_replay(session_id: String, replay_type: String, payload: Dictionary) -> void:
	var normalized_session_id := session_id.strip_edges()
	var normalized_type := replay_type.strip_edges()
	if normalized_session_id.is_empty() or normalized_type.is_empty() or payload.is_empty():
		return
	_avg_history_replay_payloads[normalized_session_id] = {
		"type": normalized_type,
		"payload": payload.duplicate(true),
	}


func get_avg_history_replay(session_id: String) -> Dictionary:
	var normalized_session_id := session_id.strip_edges()
	if normalized_session_id.is_empty() or not _avg_history_replay_payloads.has(normalized_session_id):
		return {}
	return (_avg_history_replay_payloads[normalized_session_id] as Dictionary).duplicate(true)


func _sanitize_avg_history_entry(entry: Dictionary) -> Dictionary:
	var sanitized := entry.duplicate(true)
	sanitized.erase("has_replay")
	sanitized.erase("replay_type")
	sanitized.erase("replay_payload")
	return sanitized


func _on_reset_runtime_state() -> void:
	_played_important_events.clear()
	_avg_history.clear()
	_avg_history_replay_payloads.clear()
	_event_request_id = ""
	_is_generating_events = false
	if _event_generator != null and _event_generator.has_method("clear_pending_requests"):
		_event_generator.clear_pending_requests()
	_pending_next_day_events.clear()
	_load_initial_events()


func _collect_used_seeds(entry_id: String) -> Array:
	var used: Array = []
	for h in _avg_history:
		if h is Dictionary and str(h.get("location_id", "")) == entry_id:
			var seed_text := str(h.get("event_seed", "")).strip_edges()
			if not seed_text.is_empty() and not used.has(seed_text):
				used.append(seed_text)
	return used


func get_recent_history_for_location(location_id: String, max_count: int = 3) -> Array:
	var result: Array = []
	for h in _avg_history:
		if h is Dictionary and str(h.get("location_id", "")) == location_id:
			result.append(h)
			if result.size() >= max_count:
				break
	return result


func _get_recent_followup_texts(max_count: int = 3) -> Array[String]:
	var texts: Array[String] = []
	for h in _avg_history:
		if not h is Dictionary:
			continue
		var ft := str(h.get("followup_text", "")).strip_edges()
		if ft.is_empty():
			continue
		texts.append(ft)
		if texts.size() >= max_count:
			break
	return texts


func get_recent_history_summaries(max_count: int = 5) -> Array[String]:
	var summaries: Array[String] = []
	for h in _avg_history:
		if not h is Dictionary:
			continue
		var loc := str(h.get("location_title", h.get("title", ""))).strip_edges()
		var outline := str(h.get("outline", h.get("outcome_summary", ""))).strip_edges()
		if loc.is_empty() and outline.is_empty():
			continue
		var line := loc
		if not outline.is_empty():
			line += ": " + outline
		summaries.append(line)
		if summaries.size() >= max_count:
			break
	return summaries


# =============================================================================
# Signal Bridges (emit legacy signals from base class signals)
# =============================================================================

const EVENT_GEN_ROLE: String = "date_event"
const EVENT_GEN_FALLBACK_ROLE: String = "chat_default"

var _event_generator: Node = null
var _event_gen_enabled: bool = false
var _event_request_id: String = ""
var _is_generating_events: bool = false
## Pre-generated next-day events, activated on day change.
var _pending_next_day_events: Array[Dictionary] = []


func _is_background_llm_disabled() -> bool:
	return AIConfigManager.get_instance().is_background_llm_disabled()


func _log_debug(message: String) -> void:
	if AIConfigManager.get_instance().is_quiet_logs_enabled():
		return
	print(message)

func _ready() -> void:
	super._ready()
	progress_phase_started.connect(_on_base_progress_started)
	progress_updated.connect(_on_base_progress_updated)
	session_completed.connect(_on_base_session_completed)
	_setup_event_ai_service()
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed"):
		glm.day_changed.connect(_on_day_changed)


func _on_base_progress_started(session_id: String, payload: Dictionary) -> void:
	transit_started.emit(session_id, payload)


func _on_base_progress_updated(session_id: String, progress: float, scene_ready: bool) -> void:
	transit_progress_updated.emit(session_id, progress, scene_ready)


func _on_base_session_completed(session_id: String, payload: Dictionary) -> void:
	# Record scene history for diversity dedup
	var location: Dictionary = payload.get("location", {})
	var event_id := str(location.get("event_id", payload.get("event_id", ""))).strip_edges()
	var loc_id := str(location.get("location_id", payload.get("entry_id", ""))).strip_edges()
	var loc_title := str(location.get("title", "")).strip_edges()
	var outline := str(payload.get("scene_outline", "")).strip_edges()
	var followup := str(payload.get("followup_text", payload.get("reply", ""))).strip_edges()
	if not event_id.is_empty() or not loc_id.is_empty():
		add_avg_history_entry({
			"session_id": session_id,
			"event_id": event_id,
			"location_id": loc_id,
			"location_title": loc_title,
			"outline": outline,
			"followup_text": followup,
			"timestamp": int(Time.get_unix_time_from_system()),
		})
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
	var window_title := str(request.get("window_title", "重要约会"))
	var result: Dictionary = SceneWindowClass.open_event(window_title, session_id, request, Callable(self, "_on_important_event_finished"))
	if result.is_empty():
		return false

	session["important_event_active"] = true
	session["important_event_id"] = str(request.get("event_id", ""))
	session["important_event_outline"] = AVGSceneGeneratorClass.build_narrative_outline_from_scene(request.get("scene", null))
	session["important_event_window"] = result.get("window")
	_pending_sessions[session_id] = session

	important_event_started.emit(session_id, {
		"session_id": session_id,
		"event_id": str(request.get("event_id", "")),
		"title": str(request.get("title", "重要约会")),
	})
	return true


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
	var affection_delta := int(outcome.get("affection_delta", 0))
	var extra_rewards: Dictionary = outcome.get("rewards", {}) as Dictionary
	if affection_delta != 0:
		extra_rewards["affection"] = int(extra_rewards.get("affection", 0)) + affection_delta
	session["outcome_rewards"] = _merge_reward_sources([
		session.get("outcome_rewards", {}),
		extra_rewards,
	])
	_pending_sessions[session_id] = session

	_start_followup_phase(session_id)


# =============================================================================
# Topic / Prompt Building
# =============================================================================

func _build_topic_prompt(_session: Dictionary, stage: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		return ""
	var key := ""
	if stage == "departure":
		key = "activity_topic_departure"
	elif stage == "followup":
		key = "activity_topic_followup"
	else:
		return ""
	return str(pm.resolve_with_vars(key, {
		"activity_type_label": "约会",
	})).strip_edges()


func _build_topic_goal(stage: String) -> String:
	if stage == "departure":
		return "Send a departure message"
	if stage == "followup":
		return "Send a followup message"
	return "Send a short natural message"


func _build_seed_message(stage: String, session: Dictionary = {}) -> String:
	if stage == "departure":
		return _build_departure_seed_message(session)
	if stage == "followup":
		return _build_followup_seed_message(session)
	return "请直接回复。"


func _build_departure_seed_message(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "")).strip_edges()
	var location_title: String = str(location.get("location_title", "")).strip_edges()
	var subtitle: String = str(location.get("subtitle", "")).strip_edges()
	var description: String = str(location.get("description", "")).strip_edges()
	var parts: Array[String] = ["[本次约会卡片的公开信息]"]
	if not title.is_empty():
		parts.append("- 事件标题：%s" % title)
	if not location_title.is_empty():
		parts.append("- 地点：%s" % location_title)
	if not subtitle.is_empty():
		parts.append("- 卡片副标题：%s" % subtitle)
	if not description.is_empty():
		parts.append("- 卡片简介：%s" % description)
	parts.append("")
	parts.append("请按 departure 规则回一条出发前的短消息。")
	return "\n".join(parts)


func _build_followup_seed_message(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "")).strip_edges()
	var location_title: String = str(location.get("location_title", "")).strip_edges()
	var important_result: Dictionary = session.get("important_event_result", {})
	var important_event_outline: String = str(session.get("important_event_outline", "")).strip_edges()
	var normal_scene_result: Dictionary = session.get("scene_result", {})
	var normal_scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var parts: Array[String] = ["[本次刚结束的约会]"]
	if not title.is_empty():
		parts.append("- 事件标题：%s" % title)
	if not location_title.is_empty():
		parts.append("- 地点：%s" % location_title)
	if not important_result.is_empty():
		var imp_choice: String = str(important_result.get("choice_text", "")).strip_edges()
		if not imp_choice.is_empty():
			parts.append("- 重要事件中你的关键回应：%s" % imp_choice)
		var imp_summary: String = str(important_result.get("summary", "")).strip_edges()
		if not imp_summary.is_empty():
			parts.append("- 重要事件总结：%s" % imp_summary)
	if not important_event_outline.is_empty():
		parts.append("- 重要事件实际过程：")
		parts.append(important_event_outline)
	if not normal_scene_result.is_empty():
		var scn_choice: String = str(normal_scene_result.get("choice_text", "")).strip_edges()
		if not scn_choice.is_empty():
			parts.append("- 约会场景中你的关键回应：%s" % scn_choice)
	if not normal_scene_outline.is_empty():
		parts.append("- 约会场景实际过程：")
		parts.append(normal_scene_outline)
	parts.append("")
	parts.append("请按 followup 规则回一条事后短消息。")
	return "\n".join(parts)


func _build_moment_system_prompt() -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		return "你是林夏。你要发一条刚结束约会后的朋友圈。只返回一条中文纯文本动态，不超过 36 字。"
	return str(pm.resolve_with_vars("activity_moment_system", {
		"activity_type_label": "约会",
	})).strip_edges()


func _build_moment_user_prompt(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "")).strip_edges()
	var location_title: String = str(location.get("location_title", "")).strip_edges()
	var important_result: Dictionary = session.get("important_event_result", {})
	var important_event_outline: String = str(session.get("important_event_outline", "")).strip_edges()
	var normal_scene_result: Dictionary = session.get("scene_result", {})
	var normal_scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var parts: Array[String] = []
	if not title.is_empty():
		parts.append("刚结束的约会：%s" % title)
	if not location_title.is_empty():
		parts.append("地点：%s" % location_title)
	if not important_result.is_empty():
		var imp_summary: String = str(important_result.get("summary", "")).strip_edges()
		if not imp_summary.is_empty():
			parts.append("重要事件总结：%s" % imp_summary)
	if not normal_scene_result.is_empty():
		var scn_choice: String = str(normal_scene_result.get("choice_text", "")).strip_edges()
		if not scn_choice.is_empty():
			parts.append("约会场景关键回应：%s" % scn_choice)
	if not important_event_outline.is_empty():
		parts.append("重要事件实际过程：\n%s" % important_event_outline)
	if not normal_scene_outline.is_empty():
		parts.append("约会场景实际过程：\n%s" % normal_scene_outline)
	parts.append("写一条像随手发出的朋友圈，不超过 36 字。")
	return "\n".join(parts)


# =============================================================================
# Local Fallback Text
# =============================================================================

func _build_local_departure_reply(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "this place")).strip_edges()
	return "Okay. Let's go to %s." % title


func _build_local_followup_reply(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "tonight")).strip_edges()
	var choice_text: String = str((session.get("scene_result", {}) as Dictionary).get("choice_text", "")).strip_edges()
	if not choice_text.is_empty():
		return "That line you said at %s was pretty natural: %s" % [title, choice_text]
	return "%s was better than I expected." % title


func _build_local_moment_text(session: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var title: String = str(location.get("title", "tonight")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_moment")), 3)
	match variant:
		0:
			return "%s, keep this night for later." % title
		1:
			return "Going to %s together felt different." % title
		_:
			return "%s ended, but the feeling stayed." % title


# =============================================================================
# Player Activity Card
# =============================================================================

func _send_player_event_card(event: Dictionary) -> void:
	var chat: Node = ActivityUtilsClass.get_chat_manager()
	if chat == null or not chat.has_method("store_player_message_data"):
		return
	var location_title := str(event.get("location_title", event.get("title", "date"))).strip_edges()
	chat.store_player_message_data(ActivityChatClass.DM_CHANNEL_ID, {
		"speaker": "player",
		"card": {
			"type": "location",
			"title": str(event.get("title", "date")),
			"subtitle": location_title,
			"body": str(event.get("description", "")),
			"footer": "",
			"badge": "date invite",
			"accent_color": str(event.get("accent_color", "#5AA9FF")),
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


# =============================================================================
# Event System — 事件驱动的约会系统
# =============================================================================

func _load_initial_events() -> void:
	if not FileAccess.file_exists(DATE_EVENTS_INITIAL_PATH):
		push_warning("[DateManager] Missing initial event data: %s" % DATE_EVENTS_INITIAL_PATH)
		return
	var file := FileAccess.open(DATE_EVENTS_INITIAL_PATH, FileAccess.READ)
	if file == null:
		push_warning("[DateManager] Failed to open initial event data")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		set_daily_events(parsed as Array)
		print("[DateManager] Loaded %d initial date events" % _daily_events.size())


## 设置当日可选的约会事件列表（由 LLM 生成或初始数据提供）
func set_daily_events(events: Array) -> void:
	_daily_events.clear()
	_events_by_id.clear()
	for item in events:
		if not item is Dictionary:
			continue
		var evt: Dictionary = (item as Dictionary).duplicate(true)
		var eid := str(evt.get("event_id", "")).strip_edges()
		if eid.is_empty():
			continue
		# Normalize map_position from JSON array to Vector2
		var raw_pos: Variant = evt.get("map_position", null)
		if raw_pos is Array and (raw_pos as Array).size() >= 2:
			evt["map_position"] = Vector2(float(raw_pos[0]), float(raw_pos[1]))
		elif not raw_pos is Vector2:
			evt["map_position"] = Vector2(0.5, 0.5)
		_events_by_id[eid] = evt
		_daily_events.append(evt)


func get_daily_events() -> Array[Dictionary]:
	return _daily_events


func _get_current_phase() -> String:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_phase_name"):
		return str(glm.get_phase_name(glm.get("time_phase"))).strip_edges().to_upper()
	return "AFTERNOON"


# =============================================================================
# LLM Event Generation — 为次日异步生成约会事件
# =============================================================================

func _setup_event_ai_service() -> void:
	if _is_background_llm_disabled():
		_event_gen_enabled = false
		return
	_event_generator = ActivityOptionLLMServiceClass.new()
	add_child(_event_generator)
	_event_generator.request_completed.connect(_on_event_gen_completed)
	_event_generator.request_failed.connect(_on_event_gen_failed)
	_event_gen_enabled = _event_generator.configure(
		"DateEventAIService",
		EVENT_GEN_ROLE,
		[EVENT_GEN_FALLBACK_ROLE] as Array[String]
	)


func _on_day_changed(new_day: int) -> void:
	# 激活预生成的事件（如果有的话）
	if not _pending_next_day_events.is_empty():
		set_daily_events(_pending_next_day_events)
		_pending_next_day_events.clear()
		_log_debug("[DateManager] Activated %d pre-generated events for day %d" % [_daily_events.size(), new_day])
	# 异步为下一天预生成事件（Day 1 不需要，初始事件已在 _ready 中加载）
	if new_day >= 1:
		generate_next_day_events(new_day + 1)


func generate_next_day_events(target_day: int) -> void:
	if _is_background_llm_disabled():
		return
	if _is_generating_events:
		return
	if _event_generator == null or not _event_gen_enabled:
		push_warning("[DateManager] Event AI service not available, keeping current events")
		return
	_is_generating_events = true
	var prompt := _build_event_generation_prompt(target_day)
	var sys_prompt := "Output only [DATE_EVENT] ... [/DATE_EVENT] blocks. No JSON. No markdown. No explanations."
	_event_request_id = _event_generator.request_text(prompt, sys_prompt, {
		"target_day": target_day,
	}, {
		"prompt_key": "date_event_generation",
	})
	if _event_request_id.is_empty():
		_is_generating_events = false
		push_warning("[DateManager] Failed to send event generation request")
		return
	_log_debug("[DateManager] Generating date events for day %d..." % target_day)


func pre_generate_next_day_events() -> void:
	generate_next_day_events(ActivityUtilsClass.get_current_day() + 1)

func _build_event_generation_prompt(target_day: int) -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager != null and prompt_manager.has_method("resolve_with_vars"):
		var ctx: Dictionary = {
			"next_day": str(target_day),
			"game_state": _build_game_state_for_event_gen(),
			"recent_history": _build_recent_history_for_event_gen(),
		}
		var resolved: String = str(prompt_manager.resolve_with_vars("date_event_generation", ctx)).strip_edges()
		if not resolved.is_empty():
			return resolved
	# Inline fallback
	return "Output 3 to 4 next-day date events using [DATE_EVENT] ... [/DATE_EVENT] blocks. Target day: %d." % target_day


func _build_game_state_for_event_gen() -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_llm_state_prompt"):
		return str(gm.get_llm_state_prompt()).strip_edges()
	return "No state info."


func _build_recent_history_for_event_gen() -> String:
	var summaries := get_recent_history_summaries(5)
	if summaries.is_empty():
		return "暂无约会历史"
	var lines: Array[String] = []
	for s in summaries:
		lines.append("- %s" % s)
	return "\n".join(lines)


func _on_event_gen_completed(request_id: String, context: Dictionary, raw_text: String, _response: Dictionary) -> void:
	if request_id != _event_request_id:
		return
	_event_request_id = ""
	_is_generating_events = false
	var target_day: int = int(context.get("target_day", ActivityUtilsClass.get_current_day() + 1))
	var parsed_events: Array[Dictionary] = ActivityCatalogProtocolClass.parse_date_events(raw_text, target_day, 9)
	if not parsed_events.is_empty():
		_pending_next_day_events.clear()
		for item in parsed_events:
			_pending_next_day_events.append(item.duplicate(true))
		_log_debug("[DateManager] Pre-generated %d date events (pending activation on next day)" % _pending_next_day_events.size())
		return
	push_warning("[DateManager] Failed to parse LLM date events, keeping current daily pool")

func _on_event_gen_failed(request_id: String, _context: Dictionary, error_message: String, _error_code: int) -> void:
	if request_id != _event_request_id:
		return
	_event_request_id = ""
	_is_generating_events = false
	push_warning("[DateManager] Event generation failed: %s" % error_message)
