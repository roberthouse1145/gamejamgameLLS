extends "res://autoload/activity_session_manager.gd"

# =============================================================================
# PartTimeJobManager — 兼职活动管理器
#
# 继承 ActivitySessionManager，额外提供：
# - LLM / fallback catalog 生成
# - reward_money 结算
# =============================================================================

signal catalog_refreshed(catalog: Array)
signal catalog_generation_failed(error_msg: String)
signal job_started(session_id: String, payload: Dictionary)
signal transit_started(session_id: String, payload: Dictionary)
signal transit_progress_updated(session_id: String, progress: float, scene_ready: bool)
signal job_scene_generated(session_id: String, package: Dictionary)
signal job_scene_failed(session_id: String, error_msg: String)
signal job_completed(session_id: String, payload: Dictionary)

const DEFAULT_TRANSIT_DURATION: float = 8.0
const CATALOG_SIZE: int = 3
const CATALOG_ROLE: String = "part_time_generator"
const FALLBACK_CATALOG_ROLE: String = "chat_default"

var _catalog: Array[Dictionary] = []
var _catalog_week_index: int = -1
var _is_generating_catalog: bool = false
var _ai_service: AIService = null
var _catalog_request_id: String = ""
var _catalog_llm_enabled: bool = false


# =============================================================================
# Overrides
# =============================================================================

func _on_manager_ready() -> void:
	name = "PartTimeJobManager"
	_setup_ai_service()
	_load_fallback_catalog_if_empty()


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
		"reward_money": int(entry.get("reward_money", 0)),
		"scene_window_title": "一起兼职：%s" % str(entry.get("job_title", entry.get("title", "兼职"))),
		"scene_review_label": "part-time shift",
	}


func _on_session_begin(session: Dictionary) -> void:
	_send_player_activity_card(session)


func _get_display_label(session: Dictionary) -> String:
	return str(session.get("job", {}).get("job_title", "part_time"))


func _get_moment_hint(session: Dictionary) -> String:
	return str(session.get("job", {}).get("moment_hint", ""))


func _apply_session_settlement(session_id: String) -> void:
	if not _pending_sessions.has(session_id):
		return
	var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
	if bool(session.get("settlement_done", false)):
		return
	var reward_money: int = int(session.get("reward_money", 0))
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager != null and reward_money != 0 and game_manager.has_method("modify_stat"):
		game_manager.modify_stat("money", reward_money)
	session["settlement_done"] = true
	_pending_sessions[session_id] = session


func _build_completed_payload(session: Dictionary) -> Dictionary:
	return {
		"location": session.get("location", {}),
		"reward_money": int(session.get("reward_money", 0)),
	}


# =============================================================================
# Signal Bridges
# =============================================================================

func _ready() -> void:
	super._ready()
	progress_phase_started.connect(func(sid: String, p: Dictionary) -> void: transit_started.emit(sid, p))
	progress_updated.connect(func(sid: String, prog: float, sr: bool) -> void: transit_progress_updated.emit(sid, prog, sr))
	session_completed.connect(func(sid: String, p: Dictionary) -> void: job_completed.emit(sid, p))


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
	return _catalog.duplicate(true)


func refresh_weekly_catalog(force: bool = false) -> void:
	var week_index := _get_current_week_index()
	if not force and week_index == _catalog_week_index and not _catalog.is_empty():
		catalog_refreshed.emit(get_catalog())
		return
	if _is_generating_catalog:
		return
	_generate_weekly_catalog(week_index)


func begin_part_time(job_id: String, transit_duration: float = DEFAULT_TRANSIT_DURATION) -> Dictionary:
	var result := begin_session(job_id, transit_duration)
	if result.get("success", false):
		var sid: String = str(result.get("session_id", ""))
		job_started.emit(sid, result)
	return result


func get_run_state() -> Dictionary:
	return {
		"catalog_week_index": _catalog_week_index,
		"catalog": _catalog.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_catalog.clear()
	for item in data.get("catalog", []):
		if item is Dictionary:
			_catalog.append((item as Dictionary).duplicate(true))
	_catalog_week_index = int(data.get("catalog_week_index", -1))
	_is_generating_catalog = false
	_catalog_request_id = ""
	if _catalog.is_empty():
		_load_fallback_catalog_if_empty()
	catalog_refreshed.emit(get_catalog())
	return true


func _on_reset_runtime_state() -> void:
	_catalog.clear()
	_catalog_week_index = -1
	_is_generating_catalog = false
	_catalog_request_id = ""
	_load_fallback_catalog_if_empty()


# =============================================================================
# Topic / Prompt Building
# =============================================================================

func _build_topic_prompt(session: Dictionary, stage: String) -> String:
	var job: Dictionary = session.get("job", {})
	var title := str(job.get("job_title", job.get("title", ""))).strip_edges()
	if title.is_empty():
		title = "兼职"
	var company_name := str(job.get("company_name", job.get("title", ""))).strip_edges()
	var detail_prompt := str(session.get("detail_prompt", "")).strip_edges()
	var include_scene_context: bool = stage != "departure"
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = [
		"你是林夏。",
		"今晚玩家发来了一份一起兼职的邀约。",
		"兼职岗位: %s" % title,
	]
	if not company_name.is_empty():
		parts.append("店铺 / 公司: %s" % company_name)
	if not detail_prompt.is_empty():
		parts.append("工作设定: %s" % detail_prompt)
	if include_scene_context and not scene_result.is_empty():
		parts.append("刚才场景里的玩家选择: %s" % str(scene_result.get("choice_text", "")))
	if include_scene_context and not scene_outline.is_empty():
		parts.append("刚才 AVG 场景的文本摘要:\n%s" % scene_outline)
	parts.append("请根据兼职信息和 AVG 文本自然续写，不要套预设模板。")
	if stage == "departure":
		parts.append("当前时刻: 玩家刚把兼职卡片发到 LinkChat，准备和你一起出门上班。")
		parts.append("你现在只需要发一条出发前的即时短消息。")
		parts.append("不要提前总结兼职结果，也不要写成正式工作回复。")
	elif stage == "followup":
		parts.append("当前时刻: 这次兼职已经结束，你正在回宿舍路上或刚刚下班。")
		parts.append("你现在只需要发一条下班后的 followup 短消息。")
		parts.append("让语气自然延续前面的场景，不要写成工作总结。")
	else:
		parts.append("请发送一条自然的短消息。")
	return "\n".join(parts)


func _build_topic_goal(stage: String) -> String:
	if stage == "departure":
		return "发送出发前短消息"
	if stage == "followup":
		return "发送下班后的短消息"
	return "发送短消息"


func _build_seed_message(stage: String) -> String:
	if stage == "departure":
		return "请根据当前话题直接发送出发前回复。"
	if stage == "followup":
		return "请根据当前话题直接发送下班后回复。"
	return "请直接回复。"


func _build_moment_system_prompt() -> String:
	return "你是林夏。你要发一条刚结束兼职后的朋友圈。只返回一条中文纯文本动态，不要 JSON，不要解释，不要加引号，不要超过 36 字。"


func _build_moment_user_prompt(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {})
	var title := str(job.get("job_title", job.get("title", ""))).strip_edges()
	var company_name := str(job.get("company_name", job.get("title", ""))).strip_edges()
	var detail_prompt := str(session.get("detail_prompt", "")).strip_edges()
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = [
		"今晚的兼职岗位: %s" % title,
	]
	if not company_name.is_empty():
		parts.append("店铺 / 公司: %s" % company_name)
	if not detail_prompt.is_empty():
		parts.append("工作环境设定: %s" % detail_prompt)
	if not scene_result.is_empty():
		parts.append("兼职场景里的玩家选择: %s" % str(scene_result.get("choice_text", "")))
	if not scene_outline.is_empty():
		parts.append("兼职 AVG 场景的文本摘要:\n%s" % scene_outline)
	parts.append("请根据上面的兼职信息和 AVG 文本，自行判断最自然的朋友圈语气。")
	parts.append("输出一条像随手发出的朋友圈，不要提系统，不要写成长文。")
	return "\n".join(parts)


# =============================================================================
# Local Fallback Text
# =============================================================================

func _build_local_departure_reply(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {}) as Dictionary
	var job_title: String = str(job.get("job_title", job.get("title", "兼职"))).strip_edges()
	var company_name: String = str(job.get("company_name", "")).strip_edges()
	var district: String = str(job.get("district", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_dept")), 3)
	match variant:
		0:
			if not company_name.is_empty():
				return "行，那我收拾一下就过去。今晚这班在%s，对吧？" % company_name
			return "行，那我收拾一下就过去。今晚这班我们一起顶掉。"
		1:
			if not district.is_empty():
				return "好啊，等我一下。去%s之前记得提醒我别迟到。" % district
			return "好啊，等我一下。今晚这班至少不是你一个人扛。"
		_:
			return "可以，%s听起来还行。走吧，今晚一起上班。" % job_title


func _build_local_followup_reply(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {}) as Dictionary
	var job_title: String = str(job.get("job_title", job.get("title", "兼职"))).strip_edges()
	var choice_text: String = str((session.get("scene_result", {}) as Dictionary).get("choice_text", "")).strip_edges()
	var scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_follow")), 3)
	if not choice_text.is_empty():
		return "刚才你那句\"%s\"接得还挺自然。做完%s之后，累是累，但心情没那么糟。" % [choice_text, job_title]
	if not scene_outline.is_empty() and variant == 0:
		return "今晚那段配合，现在回头想想还挺像我们会碰上的事。"
	match variant:
		0:
			return "下班以后整个人都松下来了。%s这种事，果然还是两个人一起扛比较像样。" % job_title
		1:
			return "刚才忙的时候没顾上说话，现在回头想想，今晚跟你配合得还挺顺。"
		_:
			return "累归累，但今晚不是那种空掉的累。至少一起把这班撑下来了。"


func _build_local_moment_text(session: Dictionary) -> String:
	var job: Dictionary = session.get("job", {}) as Dictionary
	var company_name: String = str(job.get("company_name", job.get("title", "今晚这班"))).strip_edges()
	var detail_prompt: String = str(session.get("detail_prompt", "")).strip_edges()
	var scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_moment")), 3)
	if not scene_outline.is_empty() and variant == 0:
		return "忙完这一班，回头想想还是觉得有点好笑。"
	match variant:
		0:
			return "今晚在%s忙完，风一吹才发现自己已经累麻了。" % company_name
		1:
			if not detail_prompt.is_empty():
				return "忙了一晚，脑子里还留着%s的味道。" % detail_prompt.substr(0, mini(12, detail_prompt.length()))
			return "忙完一整班以后，夜风和安静都变得很珍贵。"
		_:
			return "有些兼职做完只想躺平，但今晚居然还留了点余温。"


# =============================================================================
# Player Activity Card
# =============================================================================

func _send_player_activity_card(session: Dictionary) -> void:
	var chat: Node = ActivityUtilsClass.get_chat_manager()
	if chat == null or not chat.has_method("store_player_message_data"):
		return
	var job: Dictionary = session.get("job", {}) as Dictionary
	var subtitle_parts: Array[String] = []
	var company_name: String = str(job.get("company_name", "")).strip_edges()
	var district: String = str(job.get("district", "")).strip_edges()
	if not company_name.is_empty():
		subtitle_parts.append(company_name)
	if not district.is_empty():
		subtitle_parts.append(district)
	var footer: String = str(job.get("transit_label", "")).strip_edges()
	if footer.is_empty():
		footer = str(job.get("salary_text", "")).strip_edges()
	chat.store_player_message_data(ActivityChatClass.DM_CHANNEL_ID, {
		"speaker": "player",
		"card": {
			"type": "location",
			"title": str(job.get("job_title", job.get("title", "兼职"))),
			"subtitle": " · ".join(subtitle_parts),
			"body": str(job.get("description", "")),
			"footer": footer,
			"badge": "兼职邀约",
			"accent_color": str(job.get("accent_color", "#10B981")),
		}
	})


# =============================================================================
# Catalog (LLM / Fallback)
# =============================================================================

func _setup_ai_service() -> void:
	_ai_service = AIService.new()
	_ai_service.name = "PartTimeAIService"
	_ai_service.max_history_messages = 0
	_ai_service.auto_execute_tools = false
	add_child(_ai_service)
	if not _ai_service.request_completed.is_connected(_on_ai_request_completed):
		_ai_service.request_completed.connect(_on_ai_request_completed)
	if not _ai_service.request_failed.is_connected(_on_ai_request_failed):
		_ai_service.request_failed.connect(_on_ai_request_failed)

	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		if not config_mgr.get_config_for_role(CATALOG_ROLE).is_empty():
			_catalog_llm_enabled = config_mgr.apply_to_service(_ai_service, CATALOG_ROLE)
		if not _catalog_llm_enabled and not config_mgr.get_config_for_role(FALLBACK_CATALOG_ROLE).is_empty():
			_catalog_llm_enabled = config_mgr.apply_to_service(_ai_service, FALLBACK_CATALOG_ROLE)
	else:
		_catalog_llm_enabled = false


func _generate_weekly_catalog(_week_index: int) -> void:
	if _ai_service == null or not _catalog_llm_enabled:
		_load_fallback_catalog_if_empty()
		return
	_is_generating_catalog = true
	var prompt := _load_generation_prompt()
	var sys_prompt := "你是一个严格输出中文 JSON 的游戏策划助手。所有字段内容必须使用中文。"
	_catalog_request_id = _ai_service.chat_simple(prompt, sys_prompt)


func _load_generation_prompt() -> String:
	var path := "res://prompts/part_time_jobs_generation.md"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var text := file.get_as_text()
		return text.replace("{count}", str(CATALOG_SIZE))
	return "Generate %d part time jobs as JSON array." % CATALOG_SIZE


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _catalog_request_id:
		return
	_catalog_request_id = ""
	_is_generating_catalog = false
	var raw_text := AIService.extract_content(response).strip_edges()
	var json_str := _sanitize_json(raw_text)
	var json := JSON.new()
	var err := json.parse(json_str)
	if err == OK and json.data is Array and json.data.size() > 0:
		_catalog_week_index = _get_current_week_index()
		_catalog.clear()
		for item in json.data:
			if item is Dictionary:
				item["enabled"] = true
				_catalog.append(item)
		catalog_refreshed.emit(get_catalog())
	else:
		_load_fallback_catalog_if_empty()
		catalog_generation_failed.emit("Failed to parse LLM job catalog JSON.")


func _on_ai_request_failed(request_id: String, error_msg: String, _error_code: int) -> void:
	if request_id != _catalog_request_id:
		return
	_catalog_request_id = ""
	_is_generating_catalog = false
	_load_fallback_catalog_if_empty()
	catalog_generation_failed.emit(error_msg)


func _sanitize_json(text: String) -> String:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```json"):
		cleaned = cleaned.trim_prefix("```json").strip_edges()
	elif cleaned.begins_with("```"):
		cleaned = cleaned.trim_prefix("```").strip_edges()
	if cleaned.ends_with("```"):
		cleaned = cleaned.trim_suffix("```").strip_edges()
	return cleaned


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
					_catalog.append(item)
	catalog_refreshed.emit(get_catalog())


func _get_current_week_index() -> int:
	return int((ActivityUtilsClass.get_current_day() - 1) / 7.0)
