class_name LiveShowGenerator extends Node
## 生成整场直播：先生成直播标题（按人设/卡组/状态微调）→ 再生成 DSL → 解析校验 → 重试或明确失败。

signal show_ready(show: Dictionary)
signal generation_failed(reason: String)
## 标题中途生成完成（策划案 §10.2 第 1 步）：UI 用它刷新直播间标题。
signal title_ready(title: String)

const LiveDSLParserClass = preload("res://scripts/game/live_stream/live_dsl_parser.gd")
const PROMPT_KEY: String = "live_stream/live_show"
const REQUEST_TIMEOUT_MSEC: int = 30000
const TITLE_REQUEST_TIMEOUT_MSEC: int = 10000
const MAX_ATTEMPTS: int = 2
const MAX_TITLE_LENGTH: int = 48

const TITLE_SYSTEM_PROMPT: String = "你是直播平台的标题策划。根据直播人设、素材、节目单与主播状态，只输出一句直播标题：单行、不加引号、不加解释、不超过 48 字；可以夸张但不能与素材事实冲突。"

enum Phase { NONE, TITLE, SHOW }

@export var llm_enabled: bool = true

var _plan: StreamPlanSnapshot = null
var _result: StreamSettlementResult = null
var _catalog: LiveStreamCatalog = null
var _model: StreamerModelResource = null
var _llm: AIService = null
var _pending_request_id: String = ""
var _pending_started_msec: int = 0
var _phase: int = Phase.NONE
var _attempt: int = 0
var _last_errors: Array = []
var _finished: bool = false


func setup(
	plan: StreamPlanSnapshot,
	result: StreamSettlementResult,
	catalog: LiveStreamCatalog,
	model: StreamerModelResource
) -> void:
	_plan = plan
	_result = result
	_catalog = catalog
	_model = model
	_finished = false
	_phase = Phase.NONE
	_attempt = 0
	_last_errors.clear()


func generate() -> void:
	if _finished:
		return
	_attempt = 0
	_last_errors.clear()
	if not llm_enabled:
		_finish_failed("llm_disabled")
		return
	if not _ensure_llm():
		_finish_failed("llm_unavailable")
		return
	_request_title()


## 第 1 阶段：中途生成直播标题（人设/素材/卡组/状态微调，见策划案 §10.2 第 1 步）。
func _request_title() -> void:
	_phase = Phase.TITLE
	_attempt = 0
	var prompt: String = _build_title_prompt()
	if prompt.is_empty():
		_apply_fallback_title()
		_request_generation()
		return
	_pending_request_id = _llm.chat_simple(prompt, TITLE_SYSTEM_PROMPT)
	_pending_started_msec = Time.get_ticks_msec()


func _build_title_prompt() -> String:
	if _plan == null or _catalog == null:
		return ""
	var vars: Dictionary = _build_vars()
	return "\n".join([
		"主播人设：%s" % vars.get("persona_block", ""),
		"本场素材：%s" % vars.get("material_block", ""),
		"节目单：\n%s" % vars.get("program_block", ""),
		"主播状态：%s" % vars.get("state_block", ""),
	])


func _validate_title(raw: String) -> Dictionary:
	var title: String = str(raw).replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	var errors: Array[String] = []
	if title.is_empty():
		errors.append("title is empty")
	if title.contains("\n"):
		errors.append("title must be a single line")
	if title.length() > MAX_TITLE_LENGTH:
		errors.append("title exceeds %d characters" % MAX_TITLE_LENGTH)
	if title.begins_with('"') or title.ends_with('"') or title.begins_with("「") or title.ends_with("」"):
		errors.append("title must not be wrapped in quotation marks")
	return {
		"success": errors.is_empty(),
		"title": title,
		"errors": errors,
	}


## 标题兜底：当前占位（素材名）非空则沿用，否则用素材名/通用名。
func _fallback_title() -> String:
	if _plan != null and not _plan.title.is_empty():
		return _plan.title
	if _plan != null and _catalog != null:
		var material_state: Dictionary = _plan.state_snapshot.get("material_instance", {})
		var material: LiveStreamMaterialResource = _catalog.get_material(StringName(str(material_state.get("definition_id", ""))))
		if material != null:
			return material.display_name
	return "直播"


func _apply_fallback_title() -> void:
	if _plan == null:
		return
	_plan.title = _fallback_title()
	title_ready.emit(_plan.title)


func _apply_title(raw: String) -> void:
	if _plan == null:
		return
	var validation: Dictionary = _validate_title(raw)
	if not bool(validation.get("success", false)):
		_last_errors = validation.get("errors", [])
		_finish_failed("invalid_title")
		return
	_plan.title = str(validation.get("title", ""))
	title_ready.emit(_plan.title)
	_request_generation()


func compile_dsl(dsl_text: String, title: String = "") -> Dictionary:
	var parser := LiveDSLParserClass.new()
	var scene_title: String = title
	if scene_title.is_empty():
		scene_title = _plan.title if _plan != null else "直播"
	var expression_names: Array = _model.get_expression_names() if _model != null else []
	var posture_names: Array = _model.supported_postures if _model != null else []
	var gesture_names: Array = _model.supported_gestures if _model != null else []
	var costume_names: Array = _model.supported_costumes if _model != null else []
	var arm_pose_names: Array = _model.supported_arm_poses if _model != null else []
	var head_pose_names: Array = _model.supported_head_poses if _model != null else []
	var parsed: Dictionary = parser.parse(
		dsl_text,
		expression_names,
		posture_names,
		gesture_names,
		costume_names,
		arm_pose_names,
		head_pose_names
	)
	if not bool(parsed.get("success", false)):
		return parsed
	return {
		"success": true,
		"show": {
			"title": scene_title,
			"dsl_text": dsl_text,
			"ops": parsed.get("ops", []),
		},
		"errors": [],
	}


func _process(_delta: float) -> void:
	if _pending_request_id.is_empty() or _finished:
		return
	var timeout_msec: int = TITLE_REQUEST_TIMEOUT_MSEC if _phase == Phase.TITLE else REQUEST_TIMEOUT_MSEC
	if Time.get_ticks_msec() - _pending_started_msec > timeout_msec:
		_pending_request_id = ""
		if _phase == Phase.TITLE:
			_apply_fallback_title()
			_request_generation()
		else:
			_finish_failed("timeout")


func _ensure_llm() -> bool:
	if _llm != null:
		return true
	_llm = AIService.new()
	_llm.request_completed.connect(_on_request_completed)
	_llm.request_failed.connect(_on_request_failed)
	add_child(_llm)
	var config_mgr := AIConfigManager.get_instance()
	if not config_mgr.apply_to_service(_llm, "chat_default"):
		_llm.queue_free()
		_llm = null
		return false
	return true


func _request_generation() -> void:
	_phase = Phase.SHOW
	_attempt += 1
	var prompt: String = _build_prompt()
	if prompt.is_empty():
		_finish_failed("empty_prompt")
		return
	var system_prompt: String = "你是直播台本写手。只输出可播放的直播 DSL 文本。"
	if not _last_errors.is_empty():
		system_prompt += "\n上次校验失败，请按错误修正后重新输出完整 DSL：\n- " + "\n- ".join(_last_errors)
	print("[LLM:live_show] ---- system prompt ----")
	print(system_prompt)
	print("[LLM:live_show] ---- prompt ----")
	print(prompt)
	_pending_request_id = _llm.chat_simple(prompt, system_prompt)
	_pending_started_msec = Time.get_ticks_msec()


func _build_prompt() -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	var vars: Dictionary = _build_vars()
	if prompt_manager != null and prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(PROMPT_KEY):
		return str(prompt_manager.resolve_with_vars(PROMPT_KEY, vars))
	return _build_inline_prompt(vars)


func _build_vars() -> Dictionary:
	var snapshot: Dictionary = _plan.state_snapshot if _plan != null else {}
	var persona: StreamPersonaResource = null
	if _catalog != null and _plan != null:
		persona = _catalog.get_persona(_plan.persona_id)
	var material_state: Dictionary = snapshot.get("material_instance", {})
	var material: LiveStreamMaterialResource = null
	if _catalog != null:
		material = _catalog.get_material(StringName(str(material_state.get("definition_id", ""))))
	var game_state: Node = get_node_or_null("/root/GameState")
	var stream_count: int = 1
	if game_state != null and "completed_stream_sessions" in game_state:
		stream_count = int(game_state.completed_stream_sessions.size()) + 1
	return {
		"persona_block": _format_persona(persona),
		"expression_list": _format_expression_list(),
		"posture_list": _format_name_list(_model.supported_postures if _model != null else []),
		"arm_pose_list": _format_name_list(_model.supported_arm_poses if _model != null else []),
		"head_pose_list": _format_name_list(_model.supported_head_poses if _model != null else []),
		"gesture_list": _format_name_list(_model.supported_gestures if _model != null else []),
		"stream_title": _plan.title if _plan != null else "",
		"stream_count": str(stream_count),
		"fans": str(int(snapshot.get("fans", 0))),
		"state_block": "压力 %d / 宅欲 %d / 孤独 %d" % [
			int(snapshot.get("stress", 0)),
			int(snapshot.get("otaku_desire", 0)),
			int(snapshot.get("loneliness", 0)),
		],
		"material_block": _format_material(material),
		"program_block": _format_program(),
		"outcome_block": _format_outcome(),
	}


func _format_expression_list() -> String:
	if _model == null:
		return ""
	return _format_name_list(_model.get_expression_names())


func _format_name_list(values: Array) -> String:
	var names: Array[String] = []
	for value: Variant in values:
		names.append(str(value))
	return ", ".join(names)


func _format_persona(persona: StreamPersonaResource) -> String:
	if persona == null:
		return "默认直播人设"
	var fragment: String = persona.prompt_fragment.strip_edges() if "prompt_fragment" in persona else ""
	if fragment.is_empty():
		fragment = persona.description
	return "%s（%s）" % [persona.display_name, fragment]


func _format_material(material: LiveStreamMaterialResource) -> String:
	if material == null:
		return "无特定素材"
	var fragment: String = material.prompt_fragment.strip_edges()
	if fragment.is_empty():
		fragment = material.description
	return "%s（%s）" % [material.display_name, fragment]


func _format_program() -> String:
	if _plan == null or _catalog == null:
		return "无节目单"
	var parts: Array[String] = []
	for card_id: StringName in _plan.behavior_card_ids:
		var card: LiveStreamCardResource = _catalog.get_card(card_id)
		if card == null:
			continue
		var fragment: String = card.prompt_fragment.strip_edges()
		if fragment.is_empty():
			fragment = card.description
		parts.append("- %s｜%s｜%s" % [card.display_name, String(card.family), fragment])
	return "\n".join(parts) if not parts.is_empty() else "无节目单"


func _format_outcome() -> String:
	if _result == null:
		return "平稳进行"
	var hints: Array[String] = []
	hints.append("峰值人气 %d" % _result.peak_viewers)
	hints.append("涨粉 %+d" % _result.fan_delta)
	if _result.accident_occurred:
		hints.append("中途出了一次直播事故")
	else:
		hints.append("无事故")
	if _result.sponsor_satisfied:
		hints.append("赞助要求达成")
	else:
		hints.append("赞助要求未达成")
	return "；".join(hints)


func _build_inline_prompt(vars: Dictionary) -> String:
	return "\n".join([
		"输出直播 DSL。",
		"语法：expression: 表情；posture: 姿态；arm_pose: 手臂姿势；head_pose: 头部姿势；gesture: 手势；say: 台词；chat [数量]: 消息 | 消息；sc [数量]: 消息 | 消息；wait: 秒数。",
		"持续状态（姿态、手臂姿势、头部姿势、表情）在情绪回落时显式归位 idle/default，每张节目卡结束和整场收尾时全部归位。",
		"可用表情：%s" % vars.get("expression_list", ""),
		"可用姿态：%s" % vars.get("posture_list", ""),
		"可用手臂姿势：%s" % vars.get("arm_pose_list", ""),
		"可用头部姿势：%s" % vars.get("head_pose_list", ""),
		"可用手势：%s" % vars.get("gesture_list", ""),
		"主播人设：%s" % vars.get("persona_block", ""),
		"直播背景：标题 %s；第 %s 次直播；粉丝 %s" % [
			vars.get("stream_title", ""), vars.get("stream_count", "1"), vars.get("fans", "0"),
		],
		"主播状态：%s" % vars.get("state_block", ""),
		"本场素材：%s" % vars.get("material_block", ""),
		"节目单：\n%s" % vars.get("program_block", ""),
		"本场走向：%s" % vars.get("outcome_block", ""),
	])


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_request_id or _finished:
		return
	_pending_request_id = ""
	if _phase == Phase.TITLE:
		_apply_title(AIService.extract_content(response))
		return
	var content: String = AIService.extract_content(response)
	var compiled: Dictionary = compile_dsl(content)
	if bool(compiled.get("success", false)):
		_finish_ready(compiled.get("show", {}))
		return
	_last_errors = compiled.get("errors", ["compile_failed"])
	if _attempt < MAX_ATTEMPTS:
		_request_generation()
	else:
		_finish_failed("compile_failed")


func _on_request_failed(request_id: String, _error: String, _error_code: int) -> void:
	if request_id != _pending_request_id or _finished:
		return
	_pending_request_id = ""
	if _phase == Phase.TITLE:
		_apply_fallback_title()
		_request_generation()
		return
	_finish_failed("request_failed")


func _finish_failed(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_pending_request_id = ""
	generation_failed.emit(reason)


func _finish_ready(show: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_pending_request_id = ""
	show_ready.emit(show)
