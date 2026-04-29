extends "res://autoload/activity_session_manager.gd"

signal activity_started(activity_id: String, payload: Dictionary)
signal activity_completed(activity_id: String, payload: Dictionary)
@warning_ignore("unused_signal")
signal important_event_triggered(event_id: String, payload: Dictionary)  # P3: 条件触发 AVG
@warning_ignore("unused_signal")
signal initiative_presented(initiative: Dictionary)  # P2: 林夏主动发起
signal initiative_responded(initiative_id: String, accepted: bool)

const HOME_ACTIVITIES_PATH: String = "res://resources/data/home/home_activities.json"
const HOME_IMPORTANT_EVENTS_PATH: String = "res://resources/data/home/home_important_events.json"
const HOME_INITIATIVES_PATH: String = "res://resources/data/home/home_initiatives.json"
const HOME_WATCH_POOL_PATH: String = "res://resources/data/home/home_watch_pool.json"
const CHAT_STAGE: String = "interaction"
const REST_BEDTIME_STAGE: String = "rest_bedtime"
const REST_DURATION: float = 5.0

var _activity_catalog: Array[Dictionary] = []
var _activities_by_id: Dictionary = {}
var _important_events: Array[Dictionary] = []
var _initiative_pool: Array[Dictionary] = []
var _watch_pool: Array[Dictionary] = []
var _played_events: Dictionary = {}
var _consecutive_personal_count: int = 0
var _presented_initiative: Dictionary = {}


# =============================================================================
# Virtual Method Overrides (ActivitySessionManager)
# =============================================================================

func _get_activity_type() -> String:
	return "home"


func _get_chat_stage_key() -> String:
	return "home_stage"


func _should_generate_scene_extra(_session: Dictionary) -> bool:
	return false


func _on_manager_ready() -> void:
	_load_activity_catalog()
	_load_important_events()
	_load_initiatives()
	_load_watch_pool()


# === 公开 API ===

func get_available_activities(phase: String = "") -> Array[Dictionary]:
	var effective_phase: String = phase.strip_edges()
	if effective_phase.is_empty():
		effective_phase = ActivityUtilsClass.get_phase_name()

	var activities: Array[Dictionary] = []
	for activity_data in _activity_catalog:
		var activity: Dictionary = activity_data.duplicate(true)
		var availability: Dictionary = _evaluate_activity_availability(activity, effective_phase)
		var activity_id: String = str(activity.get("activity_id", "")).strip_edges()
		var blocking_reason: String = _get_activity_blocking_reason(activity_id)
		if not blocking_reason.is_empty():
			availability["enabled"] = false
			availability["reason"] = blocking_reason
		activity["enabled"] = bool(availability.get("enabled", false))
		activity["disabled_reason"] = str(availability.get("reason", ""))
		activities.append(activity)
	return activities


func get_activity_options(activity_id: String, phase: String = "") -> Array[Dictionary]:
	var effective_phase: String = phase.strip_edges()
	if effective_phase.is_empty():
		effective_phase = ActivityUtilsClass.get_phase_name()

	match activity_id.strip_edges():
		"watch":
			return _build_watch_options(effective_phase)
		_:
			return []


func begin_activity(activity_id: String, context: Dictionary = {}) -> Dictionary:
	var normalized_id: String = activity_id.strip_edges()
	if normalized_id.is_empty():
		return _fail("未指定在家活动")
	if not _activities_by_id.has(normalized_id):
		return _fail("未找到对应的在家活动")
	if not _pending_sessions.is_empty():
		return _fail("当前已有在家活动进行中")
	var blocking_reason := ActivityLockUtilsClass.get_blocking_reason(self)
	if not blocking_reason.is_empty():
		ActivityLockUtilsClass.notify_blocked(self, blocking_reason)
		return _fail(blocking_reason)

	# 叙事锁：先检查 "life" 整体类型，再检查具体活动 ID
	var narrative_reason := ActivityLockUtilsClass.get_narrative_blocking_reason("life")
	if narrative_reason.is_empty():
		narrative_reason = ActivityLockUtilsClass.get_narrative_blocking_reason(normalized_id)
	if not narrative_reason.is_empty():
		ActivityLockUtilsClass.notify_blocked(self, narrative_reason)
		return _fail(narrative_reason)

	var activity: Dictionary = _as_dictionary(_activities_by_id.get(normalized_id, {})).duplicate(true)
	var availability: Dictionary = _evaluate_activity_availability(activity)
	if not bool(availability.get("enabled", false)):
		return _fail(str(availability.get("reason", "当前不可进行该活动")))

	match normalized_id:
		"chat_casual", "chat_deep", "personal", "rest", "watch", "review":
			pass
		_:
			return _fail("该在家活动尚未实现")

	_session_counter += 1
	var session_id: String = "home_%04d" % _session_counter
	var session: Dictionary = {
		"session_id": session_id,
		"activity_id": normalized_id,
		"activity_type": "life",
		"activity": activity.duplicate(true),
		"context": _as_dictionary(context).duplicate(true),
		"extra_stat_effects": {},
		"start_day": ActivityUtilsClass.get_current_day(),
		"start_phase": ActivityUtilsClass.get_phase_name(),
		"chat_done": false,
		"moment_requested": false,
		"moment_done": false,
		"settlement_done": false,
		"reply_text": "",
		"moment": {},
		"use_local_chat_fallback": _should_use_local_chat_fallback(),
	}
	_pending_sessions[session_id] = session

	var payload: Dictionary = {
		"success": true,
		"session_id": session_id,
	}
	payload.merge(session.duplicate(true), true)

	session_started.emit(session_id, payload)
	activity_started.emit(normalized_id, payload)

	match normalized_id:
		"chat_casual":
			_run_chat_flow(session_id)
		"chat_deep":
			_run_chat_flow(session_id)
		"personal":
			_run_personal_flow(session_id)
		"rest":
			_run_rest_flow(session_id)
		"watch":
			_run_chat_flow(session_id)
		"review":
			_run_review_flow(session_id)

	return payload


func begin_rest() -> Dictionary:
	return begin_activity("rest")


func get_activity_preview_rewards(activity_id: String) -> Dictionary:
	var normalized_id: String = activity_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	if not _activities_by_id.has(normalized_id):
		return {}

	var activity: Dictionary = _as_dictionary(_activities_by_id.get(normalized_id, {}))
	var rewards: Dictionary = _as_dictionary(activity.get("stat_effects", {})).duplicate(true)
	if normalized_id == "rest":
		rewards["stress"] = _build_rest_stress_delta()
	return rewards


func evaluate_initiative() -> Dictionary:
	if not _presented_initiative.is_empty():
		return _presented_initiative.duplicate(true)
	return {}


func respond_to_initiative(initiative_id: String, accepted: bool) -> void:
	var normalized_id: String = initiative_id.strip_edges()
	if normalized_id.is_empty():
		return
	if normalized_id != str(_presented_initiative.get("initiative_id", "")):
		return

	initiative_responded.emit(normalized_id, accepted)
	var activity_id: String = str(_presented_initiative.get("activity_type", "")).strip_edges()
	_presented_initiative.clear()
	if accepted and not activity_id.is_empty():
		begin_activity(activity_id)


func get_run_state() -> Dictionary:
	return {
		"played_events": _played_events.duplicate(true),
		"session_counter": _session_counter,
		"consecutive_personal_count": _consecutive_personal_count,
		"presented_initiative": _presented_initiative.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_played_events = _as_dictionary(data.get("played_events", {})).duplicate(true)
	_session_counter = int(data.get("session_counter", 0))
	_consecutive_personal_count = int(data.get("consecutive_personal_count", 0))
	_presented_initiative = _as_dictionary(data.get("presented_initiative", {})).duplicate(true)
	_pending_sessions.clear()
	return true


func _on_reset_runtime_state() -> void:
	_played_events.clear()
	_consecutive_personal_count = 0
	_presented_initiative.clear()


# === 活动流程 ===

func _run_chat_flow(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _hydrate_session_context(
		_as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	)
	_pending_sessions[session_id] = session
	if bool(session.get("use_local_chat_fallback", false)):
		_store_local_chat_reply(session_id)
		_after_chat_finished(session_id)
		return

	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	var started: bool = _chat.start_topic(session_id, CHAT_STAGE, {
		"display_label": str(activity.get("title", "和她聊聊")),
		"system_prompt": _build_chat_prompt(session),
		"goal": "发一条自然的居家闲聊消息",
		"seed_message": _build_chat_seed_message(session),
		"timeout_seconds": 45,
		"extra_context": {
			"activity_id": activity_id,
		},
	})
	if not started:
		_store_local_chat_reply(session_id)
		_after_chat_finished(session_id)


func _run_personal_flow(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	var reply: String = _build_personal_reply(session)
	_pending_sessions[session_id] = session
	_complete_local_interaction(session_id, reply)


func _run_rest_flow(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _hydrate_session_context(
		_as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	)
	session["moment_done"] = true  # rest 不生成朋友圈
	_pending_sessions[session_id] = session

	# 自动唤起 LinkChat 让玩家看到对话
	_open_linkchat_dm()

	# 根据时段确定 topic 标签
	var phase: String = str(session.get("start_phase", "")).strip_edges().to_lower()
	var bedtime_label: String
	match phase:
		"morning":
			bedtime_label = "补觉"
		"afternoon":
			bedtime_label = "早休"
		_:
			bedtime_label = "晚安"

	# 睡前对话 topic（完成后启动进度条）
	if bool(session.get("use_local_chat_fallback", false)):
		_rest_bedtime_fallback(session_id)
		return

	var started: bool = _chat.start_topic(session_id, REST_BEDTIME_STAGE, {
		"display_label": bedtime_label,
		"system_prompt": _build_rest_bedtime_prompt(session),
		"goal": "林夏发一条睡前消息",
		"seed_message": "请发一条自然的睡前消息。",
		"timeout_seconds": 30,
		"extra_context": {"activity_id": "rest"},
	})
	if not started:
		_rest_bedtime_fallback(session_id)


## 睡前对话完成后启动休息进度条（使用 ActivitySessionManager 的弹性进度）
func _start_rest_progress(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["progress_duration"] = REST_DURATION
	_pending_sessions[session_id] = session
	_emit_progress_started(session_id)


## 进度条完成后直接结算休息，立刻推进到下一时段/新的一天。
func _on_progress_completed_hook(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id != "rest":
		return false
	_finish_session(session_id)
	return true


func _rest_bedtime_fallback(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	push_warning("[HomeActivityManager] Using local rest bedtime fallback for %s" % session_id)
	var bedtime_text: String = _build_rest_bedtime_message(session)
	if not bedtime_text.is_empty():
		_chat.send_local_message(bedtime_text)
		session["reply_text"] = bedtime_text
	session["chat_done"] = true
	_pending_sessions[session_id] = session
	# 对话结束后启动休息进度条
	_start_rest_progress(session_id)


func _run_review_flow(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _hydrate_session_context(
		_as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	)
	_pending_sessions[session_id] = session

	if bool(session.get("use_local_chat_fallback", false)):
		var reply: String = _build_review_local_reply(session)
		_complete_local_interaction(session_id, reply)
		return

	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	var started: bool = _chat.start_topic(session_id, CHAT_STAGE, {
		"display_label": str(activity.get("title", "一起看看作品")),
		"system_prompt": _build_review_prompt(session),
		"goal": "对当前项目进度发表看法",
		"seed_message": "请看一下当前项目的状态，然后自然地说出你的第一反应。",
		"timeout_seconds": 45,
		"extra_context": {
			"activity_id": "review",
		},
	})
	if not started:
		var reply: String = _build_review_local_reply(session)
		_complete_local_interaction(session_id, reply)


func _complete_local_interaction(session_id: String, reply_text: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	if not reply_text.is_empty():
		_chat.send_local_message(reply_text)
	session["reply_text"] = reply_text
	session["chat_done"] = true
	_pending_sessions[session_id] = session
	_after_chat_finished(session_id)


func _after_chat_finished(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	if not bool(session.get("chat_done", false)):
		return
	if bool(session.get("moment_requested", false)):
		return

	session["moment_requested"] = true
	_pending_sessions[session_id] = session

	if not _should_generate_moment(session):
		session["moment_done"] = true
		_pending_sessions[session_id] = session
		_finish_session(session_id)
		return

	if not _start_moment(session_id):
		_store_local_moment(session_id)


# === Moment 生成 ===

func _should_generate_moment(session: Dictionary) -> bool:
	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	var chance: float = clampf(float(activity.get("moment_chance", 0.0)), 0.0, 1.0)
	if chance <= 0.0:
		return false
	return randf() <= chance


func _start_moment(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {}))
	# 测试环境下不走 LLM moment，直接走 local fallback
	if bool(session.get("use_local_chat_fallback", false)):
		return false
	if _moment_gen == null or not _moment_gen.has_method("start"):
		return false

	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	return _moment_gen.start(session_id, {
		"system_prompt": _build_home_moment_system_prompt(session),
		"user_prompt": _build_moment_user_prompt(session),
		"local_fallback_text": _build_local_moment_text(session),
		"image_hint": str(activity.get("icon_hint", "")),
	})


func _store_local_moment(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	if _moment_gen == null or not _moment_gen.has_method("store_local"):
		var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
		session["moment_done"] = true
		_pending_sessions[session_id] = session
		_finish_session(session_id)
		return

	var session_data: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {}))
	var activity: Dictionary = _as_dictionary(session_data.get("activity", {}))
	_moment_gen.store_local(
		session_id,
		_build_local_moment_text(session_data),
		str(activity.get("icon_hint", ""))
	)


# === 结算 ===

func _finish_session(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	_apply_session_settlement(session_id)

	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	var ap_cost: int = int(activity.get("ap_cost", 0))

	if ap_cost > 0:
		var glm: Node = get_node_or_null("/root/GameLoopManager")
		if glm != null and glm.has_method("consume_ap"):
			glm.consume_ap(ap_cost, "life", str(session.get("activity_id", "")))

	var payload: Dictionary = {
		"success": true,
		"session_id": session_id,
		"activity_id": str(session.get("activity_id", "")),
		"activity_type": "life",
		"context": _as_dictionary(session.get("context", {})).duplicate(true),
		"reply": str(session.get("reply_text", "")),
		"moment": _as_dictionary(session.get("moment", {})).duplicate(true),
		"phase": str(session.get("start_phase", "")),
		"day": int(session.get("start_day", 1)),
		"rewards": _as_dictionary(session.get("applied_rewards", {})).duplicate(true),
	}

	_pending_sessions.erase(session_id)
	session_completed.emit(session_id, payload)
	activity_completed.emit(str(session.get("activity_id", "")), payload)


func _apply_session_settlement(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	if bool(session.get("settlement_done", false)):
		return

	var gm: Node = get_node_or_null("/root/GameManager")
	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	var stat_effects: Dictionary = _as_dictionary(activity.get("stat_effects", {})).duplicate(true)

	var activity_id: String = str(session.get("activity_id", "")).strip_edges()

	# 合并额外属性效果
	var extra_stat_effects: Dictionary = _as_dictionary(session.get("extra_stat_effects", {}))
	for stat_key in extra_stat_effects:
		stat_effects[str(stat_key)] = int(stat_effects.get(str(stat_key), 0)) + int(extra_stat_effects[stat_key])

	# rest 的压力恢复使用动态计算
	if activity_id == "rest":
		stat_effects["stress"] = _build_rest_stress_delta()

	# personal 连续使用计数和惩罚
	if activity_id == "personal":
		_consecutive_personal_count += 1
		var overuse_penalty: Dictionary = _as_dictionary(activity.get("overuse_penalty", {}))
		var threshold: int = int(overuse_penalty.get("threshold", 0))
		if threshold > 0 and _consecutive_personal_count == threshold:
			stat_effects["affection"] = int(stat_effects.get("affection", 0)) + int(overuse_penalty.get("affection_delta", 0))
	else:
		_consecutive_personal_count = 0

	if gm != null and gm.has_method("modify_stats"):
		gm.modify_stats(stat_effects)

	session["applied_rewards"] = stat_effects.duplicate(true)
	session["settlement_done"] = true
	_pending_sessions[session_id] = session


func _build_rest_stress_delta() -> int:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return -3

	var current_stress: int = int(gm.get("stress"))
	if current_stress >= 70:
		return -1

	var delta: int = -3
	if int(gm.get("affection")) >= 50:
		delta -= 2
	return delta


# === 可用性评估 ===

func _evaluate_activity_availability(activity: Dictionary, phase: String = "") -> Dictionary:
	var effective_phase: String = phase.strip_edges()
	if effective_phase.is_empty():
		effective_phase = ActivityUtilsClass.get_phase_name()

	var enabled: bool = true
	var reason: String = ""

	var available_phases: Array = activity.get("available_phases", [])
	if not available_phases.is_empty() and not available_phases.has(effective_phase):
		enabled = false
		reason = "当前时段不可进行该活动"

	var gm: Node = get_node_or_null("/root/GameManager")
	var prerequisites: Dictionary = _as_dictionary(activity.get("prerequisites", {}))
	if enabled and gm != null:
		if prerequisites.has("min_affection") and int(gm.get("affection")) < int(prerequisites.get("min_affection", 0)):
			enabled = false
			reason = "当前好感度不足"
		elif prerequisites.has("min_completion") and int(gm.get("completion")) < int(prerequisites.get("min_completion", 0)):
			enabled = false
			reason = "当前项目进度不足"

	var ap_cost: int = int(activity.get("ap_cost", 0))
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if enabled and ap_cost > 0:
		if glm == null or not glm.has_method("can_consume_ap"):
			enabled = false
			reason = "GameLoopManager 不可用"
		elif not glm.can_consume_ap(ap_cost):
			enabled = false
			reason = "本时段已经行动过了"

	return {
		"enabled": enabled,
		"reason": reason,
	}


func _get_activity_blocking_reason(activity_id: String) -> String:
	if not _pending_sessions.is_empty():
		return "当前已有在家活动进行中"

	var free_period_reason: String = ActivityLockUtilsClass.get_free_period_block_reason()
	if not free_period_reason.is_empty():
		return free_period_reason

	var narrative_reason: String = ActivityLockUtilsClass.get_narrative_blocking_reason("life")
	if narrative_reason.is_empty():
		narrative_reason = ActivityLockUtilsClass.get_narrative_blocking_reason(activity_id.strip_edges())
	return narrative_reason


# === Watch 选项 ===

func _build_watch_options(phase: String) -> Array[Dictionary]:
	var phase_options: Array[Dictionary] = []
	for item in _watch_pool:
		var option: Dictionary = item.duplicate(true)
		var available_phases: Array = option.get("available_phases", [])
		if not available_phases.is_empty() and not available_phases.has(phase):
			continue
		option["enabled"] = true
		option["disabled_reason"] = ""
		phase_options.append(option)

	return _slice_daily_options(phase_options, 3, "watch_%s" % phase)


func _slice_daily_options(options: Array[Dictionary], count: int, salt: String) -> Array[Dictionary]:
	if options.size() <= count:
		return options

	var day: int = ActivityUtilsClass.get_current_day()
	var start_index: int = abs(hash("%s_%d" % [salt, day])) % options.size()
	var result: Array[Dictionary] = []
	for i in range(count):
		var idx: int = (start_index + i) % options.size()
		result.append(options[idx].duplicate(true))
	return result


# === Session 上下文注入 ===

func _hydrate_session_context(session: Dictionary) -> Dictionary:
	var context: Dictionary = _as_dictionary(session.get("context", {})).duplicate(true)
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	var phase: String = str(session.get("start_phase", ActivityUtilsClass.get_phase_name())).strip_edges()

	match activity_id:
		"watch":
			var watch_option: Dictionary = _resolve_watch_option(phase, str(context.get("content_id", "")).strip_edges())
			if not watch_option.is_empty():
				context["content_id"] = str(watch_option.get("content_id", ""))
				context["option"] = watch_option
		_:
			pass

	session["context"] = context
	return session


func _resolve_watch_option(phase: String, requested_id: String) -> Dictionary:
	var options: Array[Dictionary] = _build_watch_options(phase)
	if options.is_empty():
		return {}

	if not requested_id.is_empty():
		for option in options:
			if str(option.get("content_id", "")).strip_edges() == requested_id and bool(option.get("enabled", true)):
				return option.duplicate(true)

	for option in options:
		if bool(option.get("enabled", true)):
			return option.duplicate(true)
	return {}


# === 数据加载 ===

func _load_activity_catalog() -> void:
	_activity_catalog = _load_json_array(HOME_ACTIVITIES_PATH)
	_activities_by_id.clear()
	for item in _activity_catalog:
		var activity_id: String = str(item.get("activity_id", "")).strip_edges()
		if activity_id.is_empty():
			continue
		_activities_by_id[activity_id] = item.duplicate(true)


func _load_important_events() -> void:
	_important_events = _load_json_array(HOME_IMPORTANT_EVENTS_PATH)


func _load_initiatives() -> void:
	_initiative_pool = _load_json_array(HOME_INITIATIVES_PATH)


func _load_watch_pool() -> void:
	_watch_pool = _load_json_array(HOME_WATCH_POOL_PATH)


func _load_json_array(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Array):
		return result

	for item in parsed:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


# === Chat Prompt 构建 ===

func _build_chat_prompt(session: Dictionary) -> String:
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id == "watch":
		return _build_watch_prompt(session)
	if activity_id == "review":
		return _build_review_prompt(session)

	var gm: Node = get_node_or_null("/root/GameManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var activity: Dictionary = _as_dictionary(session.get("activity", {}))
	var is_deep: bool = activity_id == "chat_deep"

	var parts: Array[String] = [
		"你是林夏。",
		"你和玩家现在在家里，处于同居中的日常相处状态。",
	]

	if is_deep:
		parts.append("这次互动是一段认真的谈心，你可以聊一些平时不太会主动提起的事。")
		parts.append("请回复一条自然的中文消息，可以稍微长一点，带一些真实的情绪。")
	else:
		parts.append("这次互动是一段轻松、随口的居家闲聊，不是正式讨论，也不是项目汇报。")
		parts.append("请只回复一条自然、口语化、像随手说出口的中文短消息，作为闲聊开场。")

	if gm != null and gm.has_method("get_llm_state_prompt"):
		parts.append(str(gm.call("get_llm_state_prompt")))
	if glm != null and glm.has_method("get_today_actions"):
		var today_actions: Array = glm.get_today_actions()
		if not today_actions.is_empty():
			var last_action: Dictionary = _as_dictionary(today_actions[today_actions.size() - 1])
			parts.append("今天最近的一次行动: %s / %s" % [
				str(last_action.get("action_type", "")),
				str(last_action.get("detail", "")),
			])
	parts.append("当前时段: %s" % str(session.get("start_phase", "")))
	parts.append("互动标题: %s" % str(activity.get("title", "和她聊聊")))
	parts.append("不要主动把话题拉成项目讨论，除非玩家先提。")
	return "\n".join(parts)


func _build_chat_seed_message(session: Dictionary) -> String:
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id == "watch":
		var option: Dictionary = _as_dictionary(_as_dictionary(session.get("context", {})).get("option", {}))
		return "请像刚一起看完《%s》后那样，自然地先说一句感想。" % str(option.get("title", "这个"))
	if activity_id == "chat_deep":
		return "请直接发一条认真的、想和对方谈谈的消息。"
	return "请直接发一条自然的居家闲聊消息。"


func _build_watch_prompt(session: Dictionary) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	var option: Dictionary = _as_dictionary(_as_dictionary(session.get("context", {})).get("option", {}))
	var parts: Array[String] = [
		"你是林夏。",
		"你刚刚和玩家一起在家看了一点东西，现在准备很自然地说出第一句感想。",
		"请只回复一条短短的中文消息，像两个人并排坐着时随口说出来的那种反应。",
		"看的内容: %s" % str(option.get("title", "某个片段")),
		"内容类型: %s" % str(option.get("type", "日常")),
		"整体气质: %s" % str(option.get("tone", "轻松")),
	]
	if gm != null and gm.has_method("get_llm_state_prompt"):
		parts.append(str(gm.call("get_llm_state_prompt")))
	parts.append("不要把语气写得像正式影评，也不要突然转成项目汇报。")
	return "\n".join(parts)


func _build_review_prompt(session: Dictionary) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	var parts: Array[String] = [
		"你是林夏。",
		"你和玩家刚刚一起打开了正在做的 AVG 项目，看了看当前的状态。",
		"请根据项目的完成度和质量，自然地说出你的第一反应。",
	]
	if gm != null:
		parts.append("项目完成度: %d" % int(gm.get("completion")))
		parts.append("项目质量: %d" % int(gm.get("quality")))
		parts.append("项目稳定性: %d" % int(gm.get("stability")))
		parts.append("当前激情: %d" % int(gm.get("passion")))
		if gm.has_method("get_llm_state_prompt"):
			parts.append(str(gm.call("get_llm_state_prompt")))
	parts.append("当前时段: %s" % str(session.get("start_phase", "")))
	parts.append("如果质量高，可以表达满意；如果质量低但激情高，可以提改进想法；如果都低，可以有些沮丧。")
	return "\n".join(parts)


# === Local Fallback 回复 ===

func _build_local_chat_reply(session_id: String) -> String:
	if not _pending_sessions.has(session_id):
		return ""
	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {}))
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id == "watch":
		return _build_watch_local_reply(session)
	if activity_id == "chat_deep":
		return _build_deep_local_reply(session)

	var gm: Node = get_node_or_null("/root/GameManager")
	var affection: int = int(gm.get("affection")) if gm != null else 0
	var stress: int = int(gm.get("stress")) if gm != null else 0
	if stress >= 70:
		return "今天有点累了……你要是现在有空，就陪我随便聊两句吧。"
	if affection >= 60:
		return "你忙完了吗？我想跟你待一会儿，随便说点什么都行。"
	return "现在要不要歇一下？我刚好也想跟你聊两句。"


func _store_local_chat_reply(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	if bool(session.get("chat_done", false)):
		return
	var reply: String = _build_local_chat_reply(session_id)
	_chat.send_local_message(reply)
	session["reply_text"] = reply
	session["chat_done"] = true
	_pending_sessions[session_id] = session


func _build_deep_local_reply(_session: Dictionary) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	var affection: int = int(gm.get("affection")) if gm != null else 0
	if affection >= 50:
		return "我一直想跟你说……其实有些事我自己也没完全想明白。但跟你待久了，好像慢慢能说出口了。"
	if affection >= 30:
		return "你有没有想过，我们做完这个项目以后会怎样？……算了，先不聊这个。"
	return "有些话我不太知道怎么开口。但既然你愿意听，那我就试试看。"


func _build_watch_local_reply(session: Dictionary) -> String:
	var option: Dictionary = _as_dictionary(_as_dictionary(session.get("context", {})).get("option", {}))
	var seeds: Array = option.get("reaction_seeds", [])
	if not seeds.is_empty():
		var index: int = abs(hash("%s_%s" % [
			str(option.get("content_id", "")),
			str(session.get("start_phase", ""))
		])) % seeds.size()
		return str(seeds[index])
	return "这个居然比我想的还上头……你刚刚也看到那里了吧？"


func _build_review_local_reply(_session: Dictionary) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return "打开项目看了看……嗯，继续加油吧。"
	var quality: int = int(gm.get("quality"))
	var passion: int = int(gm.get("passion"))
	var completion: int = int(gm.get("completion"))
	if quality >= 50:
		return "比我想的要好……有些地方真的挺有感觉的。继续保持这个方向吧。"
	if quality < 30 and passion >= 50:
		return "说实话现在还有点粗糙，但我觉得方向是对的。我们再打磨打磨。"
	if quality < 30 and completion >= 40:
		return "做了不少了，但质量……我们是不是该停下来想想？"
	return "嗯……看了一下，感觉还需要再努力。不过至少在往前走。"


func _build_personal_reply(session: Dictionary) -> String:
	var phase: String = str(session.get("start_phase", "")).strip_edges()
	var replies: Array[String] = [
		"你们各自安静忙了一会儿。她偶尔抬头看你一眼，又继续做自己的事。",
		"房间里只剩下零碎的翻页声和键盘声，但那种安静并不让人难受。",
		"你们没有特地说什么，只是各自待着，时间就慢慢过去了。",
	]
	if phase == "NIGHT":
		replies = [
			"夜里安静下来以后，连彼此各忙各的这件事都显得有点温柔。",
			"你们都没说话，只剩台灯和窗外的风声陪着这一小段时间。",
			"晚上各自待着的时候，反而更能感觉到对方就在旁边。",
		]
	var index: int = abs(hash("%s_%d" % [phase, int(session.get("start_day", 1))])) % replies.size()
	return replies[index]


func _build_rest_bedtime_message(session: Dictionary) -> String:
	var phase: String = str(session.get("start_phase", "")).strip_edges().to_lower()
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		if phase == "morning":
			return "去补觉呀？别睡太久。"
		if phase == "afternoon":
			return "这么早就睡？好吧，休息一下吧。"
		return "晚安。明天见。"
	var stress: int = int(gm.get("stress"))
	var affection: int = int(gm.get("affection"))
	if phase == "morning":
		if stress >= 70:
			return "你看起来很累……去睡会儿吧。"
		return "上午就睡？你是不是昨晚没睡好？"
	if phase == "afternoon":
		if stress >= 70:
			return "先休息一下吧，别硬撞了。"
		if affection >= 70:
			return "要休息了呀？我再弄一会儿。"
		return "这么早就睡？好吧，明天见。"
	# night
	if stress >= 70:
		return "我再缓一会儿，你先睡吧……晚安。"
	if affection >= 70:
		return "今天辛苦了。晚安，明天见。"
	if affection >= 45:
		return "早点睡吧，明天还要继续。晚安。"
	return "晚安。明天再说。"


func _build_rest_bedtime_prompt(session: Dictionary) -> String:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var pm: Node = get_node_or_null("/root/PromptManager")
	var phase: String = str(session.get("start_phase", "")).strip_edges().to_lower()

	# 时段感知的场景描述
	var scene_desc: String
	match phase:
		"morning":
			scene_desc = "现在是上午，玩家决定回去补觉。大白天就睡——可能是昨晚没睡好，也可能只是想偷懒。用对应的语气应答，不要说'晚安'。"
		"afternoon":
			scene_desc = "现在是下午，玩家打算提前休息。比正常睡觉时间早了不少。可以调侃、关心或者只是随口应答，不要说'晚安'。"
		_:
			scene_desc = "现在是晚上，两个人都准备睡觉了。正常的互道晚安时间。"

	# 今日行动摘要
	var today_summary: String = ""
	if glm != null and glm.has_method("get_today_actions"):
		var today_actions: Array = glm.get_today_actions()
		if not today_actions.is_empty():
			var action_descs: Array[String] = []
			for a in today_actions:
				var d: Dictionary = _as_dictionary(a)
				action_descs.append("%s/%s" % [str(d.get("action_type", "")), str(d.get("detail", ""))])
			today_summary = "今天做了: %s" % ", ".join(action_descs)

	# 通过 PromptManager 加载模板（{{game_state}} 由 provider 自动注入）
	if pm != null and pm.has_method("resolve_with_vars"):
		var ctx: Dictionary = {
			"rest_scene_desc": scene_desc,
			"today_summary": today_summary if not today_summary.is_empty() else "（今天还没有做什么特别的事情）",
		}
		var resolved: String = str(pm.resolve_with_vars("rest_bedtime", ctx)).strip_edges()
		if not resolved.is_empty():
			return resolved

	# fallback: PromptManager 不可用时的降级方案
	var parts: Array[String] = [
		scene_desc,
		today_summary,
		"发一条自然的消息。不要超过两句话。",
	]
	return "\n".join(parts)


# === Moment Prompt 构建 ===

func _build_home_moment_system_prompt(session: Dictionary) -> String:
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id == "watch":
		return "你是林夏。你要发一条刚刚和同居搭档一起看完东西后的朋友圈。只返回一条自然的中文短句，不要 JSON，不要解释，不要超过 36 字。"
	if activity_id == "chat_deep":
		return "你是林夏。你要发一条刚刚和同居搭档认真聊过以后的朋友圈。只返回一条自然的中文短句，不要 JSON，不要解释，不要超过 36 字。"
	return "你是林夏。你要发一条刚刚和同居搭档在家闲聊后的朋友圈。只返回一条自然的中文短句，不要 JSON，不要解释，不要超过 36 字。"


func _build_moment_user_prompt(session: Dictionary) -> String:
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id == "watch":
		return _build_watch_moment_prompt(session)
	if activity_id == "chat_deep":
		return _build_deep_moment_prompt(session)

	var gm: Node = get_node_or_null("/root/GameManager")
	var parts: Array[String] = [
		"刚刚在家里和搭档闲聊了一会儿。",
		"当前时段: %s" % str(session.get("start_phase", "")),
	]
	if gm != null and gm.has_method("get_mood_summary"):
		parts.append(str(gm.call("get_mood_summary")))
	parts.append("请写一条像随手发出的朋友圈，重点是同居氛围，不要写成总结。")
	return "\n".join(parts)


func _build_watch_moment_prompt(session: Dictionary) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	var option: Dictionary = _as_dictionary(_as_dictionary(session.get("context", {})).get("option", {}))
	var parts: Array[String] = [
		"刚刚在家里和搭档一起看了点东西。",
		"内容: %s" % str(option.get("title", "某个片段")),
		"氛围: %s" % str(option.get("tone", "轻松")),
	]
	if gm != null and gm.has_method("get_mood_summary"):
		parts.append(str(gm.call("get_mood_summary")))
	parts.append("请写一条像随手发出的朋友圈，重点是一起看的余味和同居感。")
	return "\n".join(parts)


func _build_deep_moment_prompt(session: Dictionary) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	var parts: Array[String] = [
		"刚刚在家里和搭档认真聊了一些事。",
		"当前时段: %s" % str(session.get("start_phase", "")),
	]
	if gm != null and gm.has_method("get_mood_summary"):
		parts.append(str(gm.call("get_mood_summary")))
	parts.append("请写一条像谈心后有感而发的朋友圈，带一点余韵，不要写成总结。")
	return "\n".join(parts)


func _build_local_moment_text(session: Dictionary) -> String:
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id == "watch":
		var option: Dictionary = _as_dictionary(_as_dictionary(session.get("context", {})).get("option", {}))
		return "和人一起看完《%s》以后，安静下来都还带着余味。" % str(option.get("title", "这个"))
	if activity_id == "chat_deep":
		return "有些话说出口以后，才发现自己一直想说很久了。"

	var phase: String = str(session.get("start_phase", "")).strip_edges()
	if phase == "NIGHT":
		return "晚上有人可以随便说两句废话，房间都没那么安静了。"
	return "家里有人在，连发呆这件事都没那么空。"


# === 信号回调 ===

func _on_chat_stage_completed(session_id: String, stage: String, summary: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	if stage == CHAT_STAGE:
		var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
		session["reply_text"] = summary
		session["chat_done"] = true
		_pending_sessions[session_id] = session
		_after_chat_finished(session_id)
	elif stage == REST_BEDTIME_STAGE:
		var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
		session["reply_text"] = summary
		session["chat_done"] = true
		_pending_sessions[session_id] = session
		# 对话结束后启动休息进度条
		_start_rest_progress(session_id)
	else:
		super._on_chat_stage_completed(session_id, stage, summary)


func _on_chat_stage_timeout(session_id: String, stage: String) -> void:
	if not _pending_sessions.has(session_id):
		return

	if stage == CHAT_STAGE:
		_store_local_chat_reply(session_id)
		_after_chat_finished(session_id)
	elif stage == REST_BEDTIME_STAGE:
		_rest_bedtime_fallback(session_id)
	else:
		super._on_chat_stage_timeout(session_id, stage)


func _on_moment_completed(session_id: String, moment: Dictionary) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = _as_dictionary(_pending_sessions.get(session_id, {})).duplicate(true)
	session["moment"] = moment.duplicate(true)
	session["moment_done"] = true
	_pending_sessions[session_id] = session
	_finish_session(session_id)


# === 工具函数 ===


## 自动唤起 LinkChat 并切到女主 DM 频道，让玩家看到对话
func _open_linkchat_dm() -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("launch_app"):
		return
	var window: Control = null
	if app_mgr.has_method("focus_app"):
		window = app_mgr.focus_app("linkchat", true)
	else:
		window = app_mgr.launch_app("linkchat", true)
	if window == null:
		return
	call_deferred("_select_linkchat_dm_channel", window)


func _select_linkchat_dm_channel(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	var content: Variant = window.get("content")
	if content != null and content is Node:
		if content.has_method("open_topic_channel"):
			content.open_topic_channel("dm_lin_xia")
		elif content.has_method("select_channel"):
			content.select_channel("dm_lin_xia")


func _should_use_local_chat_fallback() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return true
	if _matches_test_scene(tree.current_scene):
		return true
	for child in tree.root.get_children():
		if child is Node and _matches_test_scene(child):
			return true
	return false


func _matches_test_scene(node: Node) -> bool:
	if node == null:
		return false

	var scene_path: String = str(node.get("scene_file_path")).strip_edges()
	if _is_test_scene_path(scene_path):
		return true

	var script: Variant = node.get_script()
	if script is Script:
		var script_path: String = str(script.resource_path).strip_edges()
		if _is_test_scene_path(script_path):
			return true

	return false


func _is_test_scene_path(path: String) -> bool:
	return path.begins_with("res://tests/")


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _fail(error_message: String) -> Dictionary:
	session_failed.emit(error_message)
	return {
		"success": false,
		"error": error_message,
	}
