extends Node

# =============================================================================
# ActivitySessionManager — 活动会话状态机基类
#
# 提供统一的 departure → progress → scene → followup → moment → settlement 流程。
# 子类只需 override 标记为 "virtual" 的方法来提供活动特有的行为。
# =============================================================================

signal session_started(session_id: String, payload: Dictionary)
signal progress_phase_started(session_id: String, payload: Dictionary)
signal progress_updated(session_id: String, progress: float, scene_ready: bool)
signal session_completed(session_id: String, payload: Dictionary)
signal session_failed(error_message: String)

const AVGSceneGeneratorClass = preload("res://scripts/activity/avg_scene_generator.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const ActivityUtilsClass = preload("res://scripts/activity/activity_utils.gd")
const ElasticProgressClass = preload("res://scripts/activity/elastic_progress.gd")
const ActivityChatClass = preload("res://scripts/activity/activity_chat.gd")
const MomentGeneratorClass = preload("res://scripts/activity/moment_generator.gd")
const SceneWindowClass = preload("res://scripts/activity/scene_window.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")

const DEFAULT_PROGRESS_DURATION: float = 8.0
const PROGRESS_REACTION_DELAY: float = 0.5

var _pending_sessions: Dictionary = {}
var _session_counter: int = 0
var _scene_generator: Node = null
var _elastic: Node = null
var _chat: RefCounted = null
var _moment_gen: Node = null


func _ready() -> void:
	_setup_scene_generator()
	_setup_components()
	_on_manager_ready()
	ActivityLockUtilsClass.register_busy_source(name, self)


func _exit_tree() -> void:
	ActivityLockUtilsClass.unregister_busy_source(name)


# =============================================================================
# Virtual Methods — 子类必须或可以 override
# =============================================================================

## 子类在 _ready 之后的额外初始化
func _on_manager_ready() -> void:
	pass


## 返回活动类型标识符，如 "date", "sbeam", "part_time"
func _get_activity_type() -> String:
	return "activity"


## 返回 ActivityChat 的 stage_key，如 "date_stage", "sbeam_stage"
func _get_chat_stage_key() -> String:
	return "%s_stage" % _get_activity_type()


## 从子类的 catalog/数据源中查找条目。entry_id 是传入 begin 的 ID。
func _find_entry(_entry_id: String) -> Dictionary:
	return {}


## 构建 session 字典。子类在此添加活动特有字段。
func _build_session(_session_id: String, _entry_id: String, _entry: Dictionary) -> Dictionary:
	return {}


## 在 begin 开始后、状态机启动前的额外处理（如发送玩家卡片）
func _on_session_begin(_session: Dictionary) -> void:
	pass


## 判断是否应该生成 AVG 场景（子类可增加额外条件）
func _should_generate_scene_extra(_session: Dictionary) -> bool:
	return true


## 在进度完成后、场景启动前的钩子。返回 true 表示子类已接管流程（如 DateManager 的 important event）。
func _on_progress_completed_hook(_session_id: String) -> bool:
	return false


## 构建聊天 topic prompt
func _build_topic_prompt(_session: Dictionary, _stage: String) -> String:
	return ""


## 构建聊天 topic goal
func _build_topic_goal(_stage: String) -> String:
	if _stage == "departure":
		return "发送出发前短消息"
	if _stage == "followup":
		return "发送活动后的短消息"
	return "发送短消息"


## 构建聊天 seed message
func _build_seed_message(_stage: String, _session: Dictionary = {}) -> String:
	if _stage == "departure":
		return "请根据当前话题直接发送出发前回复。"
	if _stage == "followup":
		return "请根据当前话题直接发送活动后回复。"
	return "请直接回复。"


## 构建 moment 系统 prompt
func _build_moment_system_prompt() -> String:
	return "你是林夏。你要发一条刚结束活动后的朋友圈。只返回一条中文纯文本动态，不要 JSON，不要解释，不要加引号，不要超过 36 字。"


## 构建 moment 用户 prompt
func _build_moment_user_prompt(_session: Dictionary) -> String:
	return ""


## 构建本地 fallback departure 回复
func _build_local_departure_reply(_session: Dictionary) -> String:
	return "好，走吧。"


## 构建本地 fallback followup 回复
func _build_local_followup_reply(_session: Dictionary) -> String:
	return "结束了，回去吧。"


## 构建本地 fallback moment 文本
func _build_local_moment_text(_session: Dictionary) -> String:
	return "今晚的事，还在回味。"


## 结算逻辑（如加钱、改属性等）
func _apply_session_settlement(_session_id: String) -> void:
	if not _pending_sessions.has(_session_id):
		return
	var session: Dictionary = (_pending_sessions[_session_id] as Dictionary).duplicate(true)
	if bool(session.get("settlement_done", false)):
		return
	var rewards: Dictionary = _collect_session_rewards(session)
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if not rewards.is_empty() and game_manager != null and game_manager.has_method("modify_stats"):
		game_manager.modify_stats(rewards)
	session["applied_rewards"] = rewards.duplicate(true)
	session["settlement_done"] = true
	_pending_sessions[_session_id] = session


## 构建完成 payload（子类可在此添加额外字段）
func _build_completed_payload(_session: Dictionary) -> Dictionary:
	return {}


func _collect_session_rewards(session: Dictionary) -> Dictionary:
	return _merge_reward_sources([
		session.get("rewards", {}),
		session.get("outcome_rewards", {}),
	])


func _merge_reward_sources(sources: Array) -> Dictionary:
	var merged: Dictionary = {}
	for source in sources:
		if not source is Dictionary:
			continue
		for key in (source as Dictionary).keys():
			var stat_name := str(key).strip_edges()
			if stat_name.is_empty():
				continue
			merged[stat_name] = int(merged.get(stat_name, 0)) + int((source as Dictionary).get(key, 0))
	return merged


## 获取 session 中实体的显示名称（用于 chat display_label）
func _get_display_label(session: Dictionary) -> String:
	return str(session.get("location", {}).get("title", _get_activity_type()))


## 获取 moment hint
func _get_moment_hint(_session: Dictionary) -> String:
	return ""


func _on_reset_runtime_state() -> void:
	pass


## 收集同一地点最近用过的 event_seed，子类可 override
func _collect_used_seeds(_entry_id: String) -> Array:
	return []


# =============================================================================
# Public API
# =============================================================================

func begin_session(entry_id: String, progress_duration: float = DEFAULT_PROGRESS_DURATION, skip_departure: bool = false) -> Dictionary:
	var normalized_id := entry_id.strip_edges()
	var entry: Dictionary = _find_entry(normalized_id)
	if entry.is_empty():
		var err := "未找到对应条目"
		session_failed.emit(err)
		return {"success": false, "error": err}

	if not _pending_sessions.is_empty():
		var err := "当前有活动正在进行中"
		session_failed.emit(err)
		return {"success": false, "error": err}

	var blocking_reason := ActivityLockUtilsClass.get_blocking_reason(self)
	if not blocking_reason.is_empty():
		ActivityLockUtilsClass.notify_blocked(self, blocking_reason)
		session_failed.emit(blocking_reason)
		return {"success": false, "error": blocking_reason}

	var narrative_reason := ActivityLockUtilsClass.get_narrative_blocking_reason(_get_activity_type())
	if not narrative_reason.is_empty():
		ActivityLockUtilsClass.notify_blocked(self, narrative_reason)
		session_failed.emit(narrative_reason)
		return {"success": false, "error": narrative_reason}

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		var err := "GameLoopManager 不可用"
		session_failed.emit(err)
		return {"success": false, "error": err}
	if not glm.can_consume_ap(1):
		var err := "本时段已经行动过了"
		session_failed.emit(err)
		return {"success": false, "error": err}

	_session_counter += 1
	var session_id := "%s_%04d" % [_get_activity_type(), _session_counter]
	var use_fallback: bool = _is_fallback_mode()

	var session: Dictionary = _build_base_session(
		session_id,
		normalized_id,
		entry,
		use_fallback,
		progress_duration,
		skip_departure
	)
	var extra: Dictionary = _build_session(session_id, normalized_id, entry)
	session.merge(extra, true)
	_pending_sessions[session_id] = session

	print("[%s] Session started: %s -> %s" % [name, session_id, normalized_id])

	_on_session_begin(session)

	if skip_departure:
		# 跳过 departure 阶段，直接进入 progress（邀约对话已充当 departure）
		call_deferred("_handle_departure_finished", session_id)
	elif use_fallback:
		call_deferred("_send_local_departure_and_finish", session_id)
	else:
		if not _start_departure_topic(session_id):
			call_deferred("_send_local_departure_and_finish", session_id)

	var payload: Dictionary = {
		"success": true,
		"session_id": session_id,
	}
	payload.merge(session.duplicate(true))
	session_started.emit(session_id, payload)
	return payload


# 拒绝分支：和 begin_session 同形态，但走 refusal topic，结束后不消耗 AP / 不结算 / 不发 progress。
# refusal_data 约定字段：refusal_id, warning_desc, fallback, short
func begin_refusal_session(entry_id: String, refusal_data: Dictionary) -> Dictionary:
	var normalized_id := entry_id.strip_edges()
	var entry: Dictionary = _find_entry(normalized_id)
	if entry.is_empty():
		return _legacy_trigger_refusal(refusal_data)

	if not _pending_sessions.is_empty():
		return _legacy_trigger_refusal(refusal_data)

	_session_counter += 1
	var session_id := "%s_refusal_%04d" % [_get_activity_type(), _session_counter]
	var session: Dictionary = _build_base_session(session_id, normalized_id, entry, false, 0.0, false)
	# 合并子类的 entry-specific 字段（如 part_time 的 job、date 的 location），
	# 让 _on_session_begin 的卡片钩子能复用同一份字段。
	var extra: Dictionary = _build_session(session_id, normalized_id, entry)
	session.merge(extra, true)
	session["is_refusal"] = true
	session["refusal_data"] = refusal_data.duplicate(true)
	# 拒绝流程不会走到 progress / followup / moment / settlement
	# 把这些状态置为已完成防止误触发
	session["departure_done"] = true
	session["progress_phase_started"] = true
	session["progress_phase_complete"] = true
	session["followup_done"] = true
	session["moment_done"] = true
	session["settlement_done"] = true
	_pending_sessions[session_id] = session

	print("[%s] Refusal session started: %s -> %s" % [name, session_id, normalized_id])

	# 复用 _on_session_begin 钩子：子类用 session.is_refusal 判断是否要在拒绝时发卡片
	_on_session_begin(session)

	if not _start_refusal_topic(session_id):
		_pending_sessions.erase(session_id)
		return _legacy_trigger_refusal(refusal_data)

	var payload: Dictionary = {
		"success": false,
		"refused": true,
		"session_id": session_id,
		"error": str(refusal_data.get("short", "")),
	}
	return payload


# entry 不存在 / session 占用 / topic 启动失败时的兜底：保留旧 NpcRefusalCenter 行为。
func _legacy_trigger_refusal(refusal_data: Dictionary) -> Dictionary:
	var refusal_center: Node = get_node_or_null("/root/NpcRefusalCenter")
	if refusal_center != null and refusal_center.has_method("trigger_refusal"):
		refusal_center.trigger_refusal(
			str(refusal_data.get("refusal_id", "")),
			str(refusal_data.get("warning_desc", "")),
			str(refusal_data.get("fallback", "")),
		)
	return {
		"success": false,
		"refused": true,
		"error": str(refusal_data.get("short", "")),
	}


func has_pending_session(session_id: String) -> bool:
	return _pending_sessions.has(session_id)


func has_any_pending_sessions() -> bool:
	return not _pending_sessions.is_empty()


func reset_runtime_state() -> void:
	SceneWindowClass.force_close()
	_pending_sessions.clear()
	_session_counter = 0
	if _elastic != null and _elastic.has_method("stop"):
		_elastic.stop()
	if _moment_gen != null and _moment_gen.has_method("reset_runtime_state"):
		_moment_gen.reset_runtime_state()
	_on_reset_runtime_state()


func get_session_snapshot(session_id: String) -> Dictionary:
	if not _pending_sessions.has(session_id):
		return {}
	return (_pending_sessions[session_id] as Dictionary).duplicate(true)


# =============================================================================
# Setup
# =============================================================================

func _setup_scene_generator() -> void:
	_scene_generator = AVGSceneGeneratorClass.new()
	_scene_generator.name = "%sSceneGenerator" % _get_activity_type().capitalize()
	add_child(_scene_generator)
	_scene_generator.scene_generated.connect(_on_scene_generated)
	_scene_generator.scene_failed.connect(_on_scene_failed)


func _setup_components() -> void:
	_elastic = ElasticProgressClass.new()
	_elastic.name = "%sElasticProgress" % _get_activity_type().capitalize()
	add_child(_elastic)
	_elastic.progress_updated.connect(_on_progress_updated)
	_elastic.progress_completed.connect(_on_progress_completed)

	_chat = ActivityChatClass.new(_get_activity_type(), _get_chat_stage_key())
	_chat.stage_completed.connect(_on_chat_stage_completed)
	_chat.stage_timeout.connect(_on_chat_stage_timeout)
	call_deferred("_connect_chat_deferred")

	_moment_gen = MomentGeneratorClass.new()
	_moment_gen.name = "%sMomentGenerator" % _get_activity_type().capitalize()
	add_child(_moment_gen)
	_moment_gen.moment_completed.connect(_on_moment_completed)


func _connect_chat_deferred() -> void:
	_chat.connect_signals()


# =============================================================================
# Session Template
# =============================================================================

func _build_base_session(
		session_id: String,
		entry_id: String,
		entry: Dictionary,
		use_fallback: bool,
		progress_duration: float,
		skip_departure: bool
) -> Dictionary:
	var activity_type := _get_activity_type()
	var used_seeds: Array = _collect_used_seeds(entry_id)
	var story_guidance_prompt := _consume_story_guidance(activity_type)
	var session_origin: String = "npc_initiative" if skip_departure else "player"
	return {
		"session_id": session_id,
		"activity_type": activity_type,
		"entry_id": entry_id,
		"session_origin": session_origin,
		"entry": entry.duplicate(true),
		"start_day": ActivityUtilsClass.get_current_day(),
		"phase_after_action": ActivityUtilsClass.get_phase_name(),
		"detail_prompt": str(entry.get("detail_prompt", "")),
		"event_seed": ActivityUtilsClass.pick_random_event_seed(entry, used_seeds),
		"activity_variant": ActivityUtilsClass.pick_activity_variant(entry),
		"story_guidance_prompt": story_guidance_prompt,
		"progress_duration": maxf(progress_duration, 0.01),
		"use_local_fallback": use_fallback,
		"departure_done": false,
		"progress_phase_started": false,
		"progress_phase_complete": false,
		"scene_requested": false,
		"scene_ready": false,
		"scene_active": false,
		"scene_failed": false,
		"scene_package": {},
		"scene_outline": "",
		"scene_result": {},
		"scene_window": null,
		"scene_error": "",
		"followup_done": false,
		"moment_done": false,
		"followup_text": "",
		"moment": {},
		"settlement_done": false,
		"scene_preview_prompt_key": "%s_scene_dsl_preview" % activity_type,
		"scene_preview_source_key": "%s_scene_preview_source" % activity_type,
		"scene_window_title": activity_type,
		"scene_project_prefix": "%s_scene" % activity_type,
		"scene_review_label": "%s scene" % activity_type,
	}


func _consume_story_guidance(activity_type: String) -> String:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director == null or not story_director.has_method("consume_activity_guidance"):
		return ""
	return str(story_director.consume_activity_guidance(activity_type)).strip_edges()


func _is_fallback_mode() -> bool:
	return ActivityUtilsClass.is_test_scene() or _scene_generator == null or not _scene_generator.has_method("is_available") or not _scene_generator.is_available()


# =============================================================================
# Scene Generation
# =============================================================================

func _should_generate_scene_check(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	if _scene_generator == null or not _scene_generator.has_method("generate_for_session"):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	if bool(session.get("use_local_fallback", false)):
		return false
	if bool(session.get("scene_requested", false)) or bool(session.get("scene_ready", false)):
		return false
	return _should_generate_scene_extra(session)


func _request_scene_generation(session_id: String) -> bool:
	if not _should_generate_scene_check(session_id):
		return false
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if not _scene_generator.generate_for_session(session_id, session):
		print("[%s] Scene generation request failed: %s" % [name, session_id])
		return false
	session["scene_requested"] = true
	_pending_sessions[session_id] = session
	print("[%s] Scene generation requested: %s" % [name, session_id])
	return true


func _on_scene_generated(session_id: String, package: Dictionary) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["scene_ready"] = true
	session["scene_failed"] = false
	session["scene_package"] = package.duplicate(true)
	session["scene_outline"] = str(package.get("scene_outline", "")).strip_edges()
	session["scene_error"] = ""
	_pending_sessions[session_id] = session
	_persist_generated_snapshot(session_id, "scene_package", {
		"session_id": session_id,
		"activity_type": str(session.get("activity_type", _get_activity_type())),
		"entry_id": str(session.get("entry_id", "")),
		"title": str(package.get("title", "")),
		"scene_outline": str(package.get("scene_outline", "")).strip_edges(),
		"choice_labels": (package.get("choice_labels", {}) as Dictionary).duplicate(true),
		"choice_var_id": str(package.get("choice_var_id", "")),
	}, {
		"entry_id": str(session.get("entry_id", "")),
	})
	print("[%s] Scene generated: %s" % [name, session_id])
	_sync_progress_state_from_session(session_id)


func _on_scene_failed(session_id: String, error: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["scene_failed"] = true
	session["scene_error"] = error
	session["scene_package"] = {}
	session["scene_outline"] = ""
	_pending_sessions[session_id] = session
	print("[%s] Scene failed: %s | %s" % [name, session_id, error])
	_sync_progress_state_from_session(session_id)


# =============================================================================
# Departure → Progress → Scene → Followup → Moment → Settlement
# =============================================================================

func _start_departure_topic(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	var result = _chat.start_topic(session_id, "departure", {
		"display_label": _get_display_label(session),
		"system_prompt": _build_topic_prompt(session, "departure"),
		"goal": _build_topic_goal("departure"),
		"seed_message": _build_seed_message("departure", session),
		"extra_context": {"entry_id": str(session.get("entry_id", ""))},
	})
	return result


func _send_local_departure_reply(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if bool(session.get("departure_done", false)):
		return
	_chat.send_local_message(_build_local_departure_reply(session))
	session["departure_done"] = true
	_pending_sessions[session_id] = session


func _send_local_departure_and_finish(session_id: String) -> void:
	_send_local_departure_reply(session_id)
	_handle_departure_finished(session_id)


func _handle_departure_finished(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if bool(session.get("progress_phase_started", false)):
		return

	session["departure_done"] = true
	session["progress_phase_started"] = true
	_pending_sessions[session_id] = session

	# Scene generation is deferred until after departure so the prompt
	# builder can include the departure chat history.
	if _should_generate_scene_check(session_id):
		_request_scene_generation(session_id)

	if bool(session.get("use_local_fallback", false)):
		_emit_progress_started(session_id)
		return

	call_deferred("_emit_progress_started_after_delay", session_id, PROGRESS_REACTION_DELAY)


func _emit_progress_started_after_delay(session_id: String, delay_seconds: float) -> void:
	await get_tree().create_timer(maxf(delay_seconds, 0.0)).timeout
	_emit_progress_started(session_id)


func _emit_progress_started(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = _pending_sessions[session_id]
	var duration: float = float(session.get("progress_duration", DEFAULT_PROGRESS_DURATION))

	_elastic.start(session_id, duration)
	_sync_progress_state_from_session(session_id)

	progress_phase_started.emit(session_id, {
		"session_id": session_id,
		"progress_duration": duration,
	})


func _on_progress_updated(session_id: String, progress: float, scene_ready: bool) -> void:
	progress_updated.emit(session_id, progress, scene_ready)


func _sync_progress_state_from_session(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	if _elastic == null or not _elastic.is_active():
		return
	if _elastic.get_active_session_id() != session_id:
		return

	var session: Dictionary = _pending_sessions[session_id]
	if bool(session.get("scene_ready", false)):
		_elastic.mark_scene_ready()
		return
	if bool(session.get("scene_failed", false)):
		_elastic.mark_scene_failed()
		return
	if _can_finish_progress_without_scene(session_id, session):
		_elastic.mark_can_finish()


func _can_finish_progress_without_scene(session_id: String, session: Dictionary = {}) -> bool:
	var effective_session: Dictionary = session
	if effective_session.is_empty():
		if not _pending_sessions.has(session_id):
			return false
		effective_session = _pending_sessions[session_id]

	if bool(effective_session.get("use_local_fallback", false)):
		return true
	if bool(effective_session.get("scene_failed", false)):
		return true
	return not _should_start_scene(session_id)


func _on_progress_completed(session_id: String, scene_ready: bool) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["progress_phase_complete"] = true
	_pending_sessions[session_id] = session

	if _on_progress_completed_hook(session_id):
		return

	if _should_start_scene(session_id):
		if scene_ready or bool(session.get("scene_ready", false)):
			if _start_scene(session_id):
				return
		elif not bool(session.get("scene_failed", false)):
			return

	_start_followup_phase(session_id)


func _should_start_scene(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	if bool(session.get("use_local_fallback", false)):
		return false
	if bool(session.get("scene_active", false)):
		return false
	if not (session.get("scene_result", {}) as Dictionary).is_empty():
		return false
	return bool(session.get("scene_requested", false)) or bool(session.get("scene_ready", false))


func _start_scene(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	var scene_package: Dictionary = session.get("scene_package", {})
	if scene_package.is_empty():
		print("[%s] Scene package missing: %s" % [name, session_id])
		return false

	var title: String = str(session.get("scene_window_title", _get_activity_type()))
	var result: Dictionary = SceneWindowClass.open(title, scene_package, _on_scene_playback_finished)
	if result.is_empty():
		return false

	var session_dup: Dictionary = session.duplicate(true)
	session_dup["scene_active"] = true
	session_dup["scene_window"] = result.get("window")
	_pending_sessions[session_id] = session_dup
	print("[%s] Scene playback started: %s" % [name, session_id])
	return true


func _on_scene_playback_finished(session_id: String, outcome: Dictionary) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["scene_active"] = false
	session["scene_result"] = outcome.duplicate(true)
	session["scene_window"] = null
	_pending_sessions[session_id] = session
	print("[%s] Scene playback finished: %s" % [name, session_id])
	_schedule_scene_window_minimize(session_id)


func _schedule_scene_window_minimize(session_id: String) -> void:
	_begin_scene_window_minimize(session_id)


func _begin_scene_window_minimize(session_id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var finished_callback := Callable(self, "_on_scene_window_minimized").bind(session_id)
	var started: bool = SceneWindowClass.minimize(finished_callback)
	if not started:
		finished_callback.call_deferred()


func _on_scene_window_minimized(session_id: String) -> void:
	_start_followup_phase(session_id)


# =============================================================================
# Followup → Moment
# =============================================================================

func _start_followup_phase(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = _pending_sessions[session_id]
	if bool(session.get("use_local_fallback", false)):
		_store_local_followup(session_id)
		_store_local_moment(session_id)
		_try_finish_session(session_id)
		return

	if not _start_followup_topic(session_id):
		_store_local_followup(session_id)
	if not _start_moment(session_id):
		_store_local_moment(session_id)
	_try_finish_session(session_id)


func _start_followup_topic(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	var result = _chat.start_topic(session_id, "followup", {
		"display_label": _get_display_label(session),
		"system_prompt": _build_topic_prompt(session, "followup"),
		"goal": _build_topic_goal("followup"),
		"seed_message": _build_seed_message("followup", session),
		"extra_context": {"entry_id": str(session.get("entry_id", ""))},
	})
	return result


func _store_local_followup(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if bool(session.get("followup_done", false)):
		return
	var reply := _build_local_followup_reply(session)
	_chat.send_local_message(reply)
	session["followup_text"] = reply
	session["followup_done"] = true
	_pending_sessions[session_id] = session


func _start_moment(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	return _moment_gen.start(session_id, {
		"system_prompt": _build_moment_system_prompt(),
		"user_prompt": _build_moment_user_prompt(session),
		"local_fallback_text": _build_local_moment_text(session),
		"image_hint": _get_moment_hint(session),
		"source": "ActivityMoment:%s" % _get_activity_type(),
		"prompt_key": "activity_moment_system",
	})


func _store_local_moment(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if bool(session.get("moment_done", false)):
		return
	var moment: Dictionary = _moment_gen.store_local(
		session_id, _build_local_moment_text(session), _get_moment_hint(session)
	)
	session["moment"] = moment
	session["moment_done"] = true
	_pending_sessions[session_id] = session


# =============================================================================
# Chat / Moment Callbacks
# =============================================================================

func _on_chat_stage_completed(session_id: String, stage: String, summary: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if stage == "departure":
		session["departure_done"] = true
		_pending_sessions[session_id] = session
		_handle_departure_finished(session_id)
	elif stage == "followup":
		session["followup_done"] = true
		session["followup_text"] = summary
		_pending_sessions[session_id] = session
		_try_finish_session(session_id)
	elif stage == "refusal":
		_on_refusal_topic_completed(session_id)


func _on_chat_stage_timeout(session_id: String, stage: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	if stage == "departure":
		_send_local_departure_reply(session_id)
		_handle_departure_finished(session_id)
	elif stage == "followup":
		_store_local_followup(session_id)
		_try_finish_session(session_id)
	elif stage == "refusal":
		# 拒绝 topic 取消：本地兜底文本 + 清理 session
		_send_local_refusal_fallback(session_id)
		_on_refusal_topic_completed(session_id)


# Refusal topic：直接通过 ChatManager 激活一个 casual_interaction topic，
# 借助 ActivityChat 的 stage 路由（context_data 写入 _stage_key=refusal）回到本管理器。
func _start_refusal_topic(session_id: String) -> bool:
	if not _pending_sessions.has(session_id):
		return false
	var session: Dictionary = _pending_sessions[session_id]
	var refusal_data: Dictionary = session.get("refusal_data", {}) if session.get("refusal_data") is Dictionary else {}
	var entry: Dictionary = session.get("entry", {}) if session.get("entry") is Dictionary else {}

	var refusal_center: Node = get_node_or_null("/root/NpcRefusalCenter")
	if refusal_center == null or not refusal_center.has_method("build_refusal_prompt"):
		return false
	var prompt_text: String = str(refusal_center.build_refusal_prompt(str(refusal_data.get("warning_desc", "")))).strip_edges()
	if prompt_text.is_empty():
		return false

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("activate_topic") or not chat.has_method("request_topic_npc_reply"):
		return false
	if chat.has_method("has_active_topic") and chat.has_active_topic(ActivityChatClass.DM_CHANNEL_ID):
		return false

	var refusal_id: String = str(refusal_data.get("refusal_id", _get_activity_type()))
	var topic := ChatTopicClass.new()
	topic.topic_id = "%s_refusal_%s_%d" % [_get_activity_type(), refusal_id, int(Time.get_unix_time_from_system())]
	topic.topic_type = "casual_interaction"
	topic.display_title = "林夏的拒绝（%s）" % str(entry.get("title", _get_activity_type()))
	topic.npc_id = ActivityChatClass.NPC_ID
	topic.channel_id = ActivityChatClass.DM_CHANNEL_ID
	topic.system_prompt = prompt_text
	topic.goal_description = "拒绝玩家本次行动：%s" % refusal_id
	topic.timeout_seconds = 0
	topic.context_data = {
		"session_id": session_id,
		_get_chat_stage_key(): "refusal",
		"activity_type": _get_activity_type(),
		"activity_stage": "refusal",
		"entry_id": str(session.get("entry_id", "")),
		"is_refusal": true,
		"npc_refusal": true,
		"refusal_id": refusal_id,
		"linkchat_open_mode": "force",
		"complete_after_first_reply": true,
		"suppress_system_notice": true,
	}

	if not chat.activate_topic(topic):
		push_warning("[%s] activate refusal topic failed: %s" % [name, refusal_id])
		return false
	if not chat.request_topic_npc_reply(ActivityChatClass.DM_CHANNEL_ID, "", false, true):
		var topic_mgr: Variant = chat.get("topic_manager")
		if topic_mgr != null:
			var active_topic: ChatTopic = chat.get_active_topic(ActivityChatClass.DM_CHANNEL_ID)
			if active_topic != null and active_topic.topic_id == topic.topic_id:
				topic_mgr.cancel_topic(active_topic, "refusal_initial_reply_failed")
		return false
	print("[%s] Refusal topic activated: %s" % [name, refusal_id])
	return true


# Refusal topic 完成 / 取消后的统一清理：不消耗 AP / 不结算。
func _on_refusal_topic_completed(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	var refusal_data: Dictionary = session.get("refusal_data", {}) if session.get("refusal_data") is Dictionary else {}
	_pending_sessions.erase(session_id)
	print("[%s] Refusal session finished: %s" % [name, session_id])
	var error_msg: String = str(refusal_data.get("short", ""))
	if not error_msg.is_empty():
		session_failed.emit(error_msg)


func _send_local_refusal_fallback(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = _pending_sessions[session_id]
	var refusal_data: Dictionary = session.get("refusal_data", {}) if session.get("refusal_data") is Dictionary else {}
	var fallback_text: String = str(refusal_data.get("fallback", "")).strip_edges()
	if fallback_text.is_empty():
		return
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.has_method("store_npc_message"):
		chat.store_npc_message(ActivityChatClass.DM_CHANNEL_ID, ActivityChatClass.NPC_ID, fallback_text)


func _on_moment_completed(session_id: String, moment: Dictionary) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	session["moment"] = moment
	session["moment_done"] = true
	_pending_sessions[session_id] = session
	_try_finish_session(session_id)


# =============================================================================
# Settlement
# =============================================================================

func _try_finish_session(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if not bool(session.get("followup_done", false)):
		return
	if not bool(session.get("moment_done", false)):
		return

	_apply_session_settlement(session_id)
	session = (_pending_sessions[session_id] as Dictionary).duplicate(true)

	# 活动全部完成后才消耗 AP，触发时间段推进
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		var entry_title: String = ""
		if session.get("entry") is Dictionary:
			entry_title = str((session["entry"] as Dictionary).get("title", "")).strip_edges()
		glm.consume_ap(
			1,
			str(session.get("activity_type", _get_activity_type())),
			str(session.get("entry_id", "")),
			entry_title,
		)

	var payload: Dictionary = {
		"success": true,
		"session_id": session_id,
		"activity_type": str(session.get("activity_type", _get_activity_type())),
		"reply": str(session.get("followup_text", "")),
		"moment": session.get("moment", {}),
		"phase_after_action": session.get("phase_after_action", ""),
		"scene_result": session.get("scene_result", {}),
	}
	var extra: Dictionary = _build_completed_payload(session)
	payload.merge(extra, true)
	_persist_generated_snapshot(session_id, "session_outcome", {
		"session_id": session_id,
		"activity_type": str(session.get("activity_type", _get_activity_type())),
		"entry_id": str(session.get("entry_id", "")),
		"scene_outline": str(session.get("scene_outline", "")).strip_edges(),
		"scene_result": (session.get("scene_result", {}) as Dictionary).duplicate(true),
		"followup_text": str(session.get("followup_text", "")),
		"moment": (session.get("moment", {}) as Dictionary).duplicate(true),
		"payload": payload.duplicate(true),
	}, {
		"entry_id": str(session.get("entry_id", "")),
	})

	_pending_sessions.erase(session_id)
	session_completed.emit(session_id, payload)


# =============================================================================
# Utility — outline hint extraction
# =============================================================================

func _extract_outline_hint(outline_sources: Array) -> String:
	for source in outline_sources:
		var text: String = str(source).strip_edges()
		if text.is_empty():
			continue
		var first_line: String = text.split("\n", false, 1)[0].strip_edges()
		if first_line.is_empty():
			continue
		if first_line.length() > 18:
			return "%s..." % first_line.substr(0, 18)
		return first_line
	return ""


func _persist_generated_snapshot(session_id: String, artifact_name: String, data: Dictionary, metadata: Dictionary = {}) -> void:
	var run_manager: Node = get_node_or_null("/root/CampaignRunManager")
	if run_manager == null or not run_manager.has_method("write_generated_activity_artifact"):
		return
	run_manager.call(
		"write_generated_activity_artifact",
		_get_activity_type(),
		session_id,
		artifact_name,
		data,
		metadata
	)
