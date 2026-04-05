extends "res://autoload/activity_session_manager.gd"

const ActivityCatalogProtocolClass = preload("res://scripts/activity/activity_catalog_protocol.gd")
const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")

# =============================================================================
# PartTimeJobManager 鈥?鍏艰亴娲诲姩绠＄悊鍣?
#
# 缁ф壙 ActivitySessionManager锛岄澶栨彁渚涳細
# - LLM / fallback catalog 鐢熸垚
# - rewards 鏁版嵁椹卞姩缁撶畻
# =============================================================================

signal catalog_refreshed(catalog: Array)
signal catalog_generation_failed(error_msg: String)
signal job_started(session_id: String, payload: Dictionary)
signal transit_started(session_id: String, payload: Dictionary)
signal transit_progress_updated(session_id: String, progress: float, scene_ready: bool)
signal job_scene_generated(session_id: String, package: Dictionary)
signal job_scene_failed(session_id: String, error_msg: String)
signal job_completed(session_id: String, payload: Dictionary)

const DEFAULT_TRANSIT_DURATION: float = 20.0
const CATALOG_SIZE: int = 8
const CATALOG_ROLE: String = "part_time_generator"
const FALLBACK_CATALOG_ROLE: String = "chat_default"
const GENERATION_PROMPT_KEY: String = "part_time_jobs_generation"

var _catalog: Array[Dictionary] = []
var _pending_next_day_catalog: Array[Dictionary] = []
var _is_generating_catalog: bool = false
var _catalog_generator: Node = null
var _catalog_request_id: String = ""
var _catalog_llm_enabled: bool = false


func _is_background_llm_disabled() -> bool:
	return AIConfigManager.get_instance().is_background_llm_disabled()


func _log_debug(message: String) -> void:
	if AIConfigManager.get_instance().is_quiet_logs_enabled():
		return
	print(message)


# =============================================================================
# Overrides
# =============================================================================

func _on_manager_ready() -> void:
	name = "PartTimeJobManager"
	_setup_ai_service()
	_load_fallback_catalog_if_empty()
	# Async pre-generate Day 2 catalog
	var current_day: int = ActivityUtilsClass.get_current_day()
	_generate_next_day_catalog(current_day + 1)


func _get_activity_type() -> String:
	return "part_time"


func _get_chat_stage_key() -> String:
	return "part_time_stage"


func _find_entry(entry_id: String) -> Dictionary:
	for job in _catalog:
		if str(job.get("job_id", "")) == entry_id:
			return job
	return {}


func _build_session(_session_id: String, entry_id: String, entry: Dictionary) -> Dictionary:
	return {
		"job_id": entry_id,
		"job": entry.duplicate(true),
		"location_id": entry_id,
		"location": entry.duplicate(true),
		"rewards": (entry.get("rewards", {}) as Dictionary).duplicate(true),
		"scene_window_title": "涓€璧峰吋鑱岋細%s" % str(entry.get("job_title", "鍏艰亴")),
		"scene_review_label": "part-time shift",
	}


func _on_session_begin(session: Dictionary) -> void:
	_send_player_activity_card(session)


func _get_display_label(session: Dictionary) -> String:
	return str(session.get("job", {}).get("job_title", "part_time"))


func _build_completed_payload(session: Dictionary) -> Dictionary:
	return {
		"location": session.get("location", {}),
		"rewards": _collect_session_rewards(session),
	}


# =============================================================================
# Signal Bridges
# =============================================================================

func _ready() -> void:
	super._ready()
	progress_phase_started.connect(func(sid: String, p: Dictionary) -> void: transit_started.emit(sid, p))
	progress_updated.connect(func(sid: String, prog: float, sr: bool) -> void: transit_progress_updated.emit(sid, prog, sr))
	session_completed.connect(func(sid: String, p: Dictionary) -> void: job_completed.emit(sid, p))
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed"):
		glm.day_changed.connect(_on_day_changed)


# Override to also emit legacy signals on scene events
func _on_scene_generated(sid: String, package: Dictionary) -> void:
	super._on_scene_generated(sid, package)
	job_scene_generated.emit(sid, package)


func _on_scene_failed(sid: String, error: String) -> void:
	super._on_scene_failed(sid, error)
	job_scene_failed.emit(sid, error)


# =============================================================================
# Public API (backward compatibility)
# =============================================================================

func get_catalog() -> Array[Dictionary]:
	var current_phase := _get_current_phase()
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var can_act: bool = glm != null and glm.can_consume_ap(1)
	var result: Array[Dictionary] = []
	for job in _catalog:
		var valid_phases: Array = job.get("valid_phases", [])
		if not valid_phases.is_empty() and not valid_phases.has(current_phase):
			continue
		var entry: Dictionary = job.duplicate(true)
		entry["enabled"] = can_act
		result.append(entry)
	return result


func _get_current_phase() -> String:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_phase_name"):
		return str(glm.get_phase_name(glm.get("time_phase"))).strip_edges().to_upper()
	return "AFTERNOON"


func refresh_catalog(force: bool = false) -> void:
	if not force and not _catalog.is_empty():
		catalog_refreshed.emit(get_catalog())
		return
	if _is_generating_catalog:
		return
	_load_fallback_catalog_if_empty()


## Backward-compatible alias
func refresh_weekly_catalog(force: bool = false) -> void:
	refresh_catalog(force)


func begin_part_time(job_id: String, transit_duration: float = DEFAULT_TRANSIT_DURATION) -> Dictionary:
	var result := begin_session(job_id, transit_duration)
	if result.get("success", false):
		var sid: String = str(result.get("session_id", ""))
		job_started.emit(sid, result)
	return result


func get_run_state() -> Dictionary:
	return {
		"catalog": _catalog.duplicate(true),
		"pending_next_day_catalog": _pending_next_day_catalog.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_catalog.clear()
	for item in data.get("catalog", []):
		if item is Dictionary:
			_catalog.append((item as Dictionary).duplicate(true))
	_pending_next_day_catalog.clear()
	var saved_pending: Variant = data.get("pending_next_day_catalog", [])
	if saved_pending is Array:
		for item in (saved_pending as Array):
			if item is Dictionary:
				_pending_next_day_catalog.append((item as Dictionary).duplicate(true))
	_is_generating_catalog = false
	_catalog_request_id = ""
	if _catalog_generator != null and _catalog_generator.has_method("clear_pending_requests"):
		_catalog_generator.clear_pending_requests()
	if _catalog.is_empty():
		_load_fallback_catalog_if_empty()
	catalog_refreshed.emit(get_catalog())
	return true


func _on_reset_runtime_state() -> void:
	_catalog.clear()
	_pending_next_day_catalog.clear()
	_is_generating_catalog = false
	_catalog_request_id = ""
	if _catalog_generator != null and _catalog_generator.has_method("clear_pending_requests"):
		_catalog_generator.clear_pending_requests()
	_load_fallback_catalog_if_empty()


# =============================================================================
# Topic / Prompt Building
# =============================================================================

func _build_topic_prompt(session: Dictionary, stage: String) -> String:
	var job: Dictionary = session.get("job", {})
	var title := str(job.get("job_title", job.get("title", ""))).strip_edges()
	if title.is_empty():
		title = "part-time shift"
	var company_name := str(job.get("company_name", "")).strip_edges()
	var detail_prompt := str(session.get("detail_prompt", "")).strip_edges()
	var include_scene_context: bool = stage != "departure"
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = [
		"You are Lin Xia.",
		"The player invited you to join a part-time shift tonight.",
		"Job title: %s" % title,
	]
	if not company_name.is_empty():
		parts.append("Company: %s" % company_name)
	if not detail_prompt.is_empty():
		parts.append("Work details: %s" % detail_prompt)
	if include_scene_context and not scene_result.is_empty():
		parts.append("Recent scene choice: %s" % str(scene_result.get("choice_text", "")))
	if include_scene_context and not scene_outline.is_empty():
		parts.append("Recent scene outline:\n%s" % scene_outline)
	parts.append("Continue naturally from the part-time setup and prior scene. Avoid template-sounding lines.")
	if stage == "departure":
		parts.append("Current moment: the player just sent the job card in chat and you are about to head out together.")
		parts.append("Reply with one short departure message only.")
		parts.append("Do not summarize the shift result yet.")
	elif stage == "followup":
		parts.append("Current moment: the shift already ended and you are on the way back or just got home.")
		parts.append("Reply with one short followup message only.")
		parts.append("Keep the tone personal instead of writing a work report.")
	else:
		parts.append("Reply with one short natural message.")
	return "\n".join(parts)


func _build_topic_goal(stage: String) -> String:
	if stage == "departure":
		return "Send a departure message"
	if stage == "followup":
		return "Send a followup message"
	return "Send a short message"


func _build_seed_message(stage: String) -> String:
	if stage == "departure":
		return "Send the departure reply directly."
	if stage == "followup":
		return "Send the followup reply directly."
	return "Reply directly."


func _build_moment_system_prompt() -> String:
	return "You are Lin Xia. Write one short Chinese social post after a part-time shift. Output plain text only. No JSON. No explanations. No quotes. Max 36 Chinese characters."


func _build_moment_user_prompt(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {})
	var title := str(job.get("job_title", job.get("title", ""))).strip_edges()
	var company_name := str(job.get("company_name", "")).strip_edges()
	var detail_prompt := str(session.get("detail_prompt", "")).strip_edges()
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = ["Job title: %s" % title]
	if not company_name.is_empty():
		parts.append("Company: %s" % company_name)
	if not detail_prompt.is_empty():
		parts.append("Work details: %s" % detail_prompt)
	if not scene_result.is_empty():
		parts.append("Scene choice: %s" % str(scene_result.get("choice_text", "")))
	if not scene_outline.is_empty():
		parts.append("Scene outline:\n%s" % scene_outline)
	parts.append("Write one short social post that feels casual and personal.")
	return "\n".join(parts)


# =============================================================================
# Local Fallback Text
# =============================================================================

func _build_local_departure_reply(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {}) as Dictionary
	var job_title: String = str(job.get("job_title", job.get("title", "part-time shift"))).strip_edges()
	var company_name: String = str(job.get("company_name", "")).strip_edges()
	var district: String = str(job.get("district", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_dept")), 3)
	match variant:
		0:
			if not company_name.is_empty():
				return "Okay. I'll get ready and head to %s." % company_name
			return "Okay. I'll get ready and head out with you."
		1:
			if not district.is_empty():
				return "Sure. Give me a minute. Remind me not to be late before we go to %s." % district
			return "Sure. Give me a minute. At least you are not doing this shift alone."
		_:
			return "%s sounds manageable. Let's go." % job_title


func _build_local_followup_reply(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {}) as Dictionary
	var job_title: String = str(job.get("job_title", job.get("title", "part-time shift"))).strip_edges()
	var choice_text: String = str((session.get("scene_result", {}) as Dictionary).get("choice_text", "")).strip_edges()
	var scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_follow")), 3)
	if not choice_text.is_empty():
		return "That line you used felt natural: %s. %s was tiring, but not in a bad way." % [choice_text, job_title]
	if not scene_outline.is_empty() and variant == 0:
		return "That little stretch of teamwork tonight still feels like something that would happen to us."
	match variant:
		0:
			return "Now that the shift is over, I can finally breathe. %s really is easier with two people." % job_title
		1:
			return "We barely had time to talk while we were busy, but we worked together pretty smoothly tonight."
		_:
			return "I am tired, but not empty-tired. At least we got through the shift together."


func _build_local_moment_text(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {}) as Dictionary
	var company_name: String = str(job.get("company_name", job.get("title", "tonight's shift"))).strip_edges()
	var detail_prompt: String = str(session.get("detail_prompt", "")).strip_edges()
	var scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_moment")), 3)
	if not scene_outline.is_empty() and variant == 0:
		return "忙完这一班，回头想想还是有点想笑"
	match variant:
		0:
			return "在%s忙完，吹到夜风才发现自己累麻了" % company_name
		1:
			if not detail_prompt.is_empty():
				return "忙了一晚，脑子里还留着%s的味道" % detail_prompt.substr(0, min(12, detail_prompt.length()))
			return "忙完整班以后，夜风和安静都变珍贵了"
		_:
			return "有些兼职做完只想躺平，但今晚还留了点余温"


# =============================================================================
# Player Activity Card
# =============================================================================

func _send_player_activity_card(session: Dictionary) -> void:
	var chat: Node = ActivityUtilsClass.get_chat_manager()
	if chat == null or not chat.has_method("store_player_message_data"):
		return
	var job: Dictionary = session.get("job", {}) as Dictionary
	var money_reward: int = _get_money_reward(job)
	var subtitle_parts: Array[String] = []
	var company_name: String = str(job.get("company_name", "")).strip_edges()
	var district: String = str(job.get("district", "")).strip_edges()
	if not company_name.is_empty():
		subtitle_parts.append(company_name)
	if not district.is_empty():
		subtitle_parts.append(district)
	var footer: String = str(job.get("salary_text", "")).strip_edges()
	if footer.is_empty():
		if money_reward > 0:
			footer = "%d / shift" % money_reward
		else:
			footer = str(job.get("transit_label", "")).strip_edges()
	chat.store_player_message_data(ActivityChatClass.DM_CHANNEL_ID, {
		"speaker": "player",
		"card": {
			"type": "job_posting",
			"title": str(job.get("job_title", job.get("title", "Part-time"))),
			"subtitle": " | ".join(subtitle_parts),
			"body": str(job.get("description", "")),
			"footer": footer,
			"salary": footer,
			"badge": "Part-time invite",
			"accent_color": str(job.get("accent_color", "#00BFA5")),
		}
	})


func _get_money_reward(job: Dictionary) -> int:
	var rewards: Dictionary = job.get("rewards", {}) as Dictionary
	return int(rewards.get("money", 0))


# =============================================================================
# Catalog (LLM / Fallback)
# =============================================================================

func _setup_ai_service() -> void:
	if _is_background_llm_disabled():
		_catalog_llm_enabled = false
		return
	_catalog_generator = ActivityOptionLLMServiceClass.new()
	add_child(_catalog_generator)
	_catalog_generator.request_completed.connect(_on_ai_request_completed)
	_catalog_generator.request_failed.connect(_on_ai_request_failed)
	_catalog_llm_enabled = _catalog_generator.configure(
		"PartTimeAIService",
		CATALOG_ROLE,
		[FALLBACK_CATALOG_ROLE] as Array[String],
		{
			"max_history_messages": 0,
			"auto_execute_tools": false,
		}
	)


func _generate_next_day_catalog(target_day: int) -> void:
	if _is_background_llm_disabled():
		return
	if _catalog_generator == null or not _catalog_llm_enabled:
		return
	if _is_generating_catalog:
		return
	_is_generating_catalog = true
	var prompt := _load_generation_prompt()
	var sys_prompt := "Output only [JOB] ... [/JOB] blocks. No JSON. No markdown. No explanations."
	_catalog_request_id = _catalog_generator.request_text(prompt, sys_prompt, {
		"target_day": target_day,
	})
	if _catalog_request_id.is_empty():
		_is_generating_catalog = false
		push_warning("[PartTimeJobManager] Failed to send LLM catalog request for day %d" % target_day)

func _load_generation_prompt() -> String:
	var pm := get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_prompt(GENERATION_PROMPT_KEY) and pm.has_method("resolve_with_vars"):
		return str(pm.resolve_with_vars(GENERATION_PROMPT_KEY, {
			"count": str(CATALOG_SIZE),
		})).strip_edges()
	return "Output %d part-time jobs using [JOB] ... [/JOB] blocks." % CATALOG_SIZE


func _on_ai_request_completed(request_id: String, context: Dictionary, raw_text: String, _response: Dictionary) -> void:
	if request_id != _catalog_request_id:
		return
	_catalog_request_id = ""
	_is_generating_catalog = false
	var target_day: int = int(context.get("target_day", ActivityUtilsClass.get_current_day() + 1))
	var parsed_jobs: Array[Dictionary] = ActivityCatalogProtocolClass.parse_part_time_catalog(
		raw_text,
		CATALOG_SIZE,
		target_day
	)
	if not parsed_jobs.is_empty():
		_pending_next_day_catalog.clear()
		for item in parsed_jobs:
			_pending_next_day_catalog.append(item.duplicate(true))
		_log_debug("[PartTimeJobManager] Pre-generated %d jobs (pending activation on next day)" % _pending_next_day_catalog.size())
		return
	push_warning("[PartTimeJobManager] Failed to parse LLM part-time catalog for day %d" % target_day)
	catalog_generation_failed.emit("Failed to parse LLM part-time catalog.")

func _on_ai_request_failed(request_id: String, _context: Dictionary, error_msg: String, _error_code: int) -> void:
	if request_id != _catalog_request_id:
		return
	_catalog_request_id = ""
	_is_generating_catalog = false
	_load_fallback_catalog_if_empty()
	catalog_generation_failed.emit(error_msg)


func _on_day_changed(new_day: int) -> void:
	if not _pending_next_day_catalog.is_empty():
		_catalog.clear()
		for item in _pending_next_day_catalog:
			_catalog.append(item.duplicate(true))
		_pending_next_day_catalog.clear()
		_log_debug("[PartTimeJobManager] Activated %d pre-generated jobs for day %d" % [_catalog.size(), new_day])
		catalog_refreshed.emit(get_catalog())
	if new_day >= 1:
		_generate_next_day_catalog(new_day + 1)


func _load_fallback_catalog_if_empty() -> void:
	if not _catalog.is_empty():
		return
	var path := "res://resources/data/part_time_jobs.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Array:
			for item in json.data:
				if item is Dictionary:
					item["enabled"] = true
					if not item.has("valid_phases") or (item["valid_phases"] as Array).is_empty():
						item["valid_phases"] = ["AFTERNOON", "NIGHT"]
					_catalog.append(item)
	catalog_refreshed.emit(get_catalog())





