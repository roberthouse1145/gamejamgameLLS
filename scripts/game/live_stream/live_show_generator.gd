class_name LiveShowGenerator extends Node
## 生成整场直播：标题 → DSL → 解析校验 → 工具修复 → 播放交付 → 连续性摘要。

signal show_ready(show: Dictionary)
signal generation_failed(reason: String)
signal summary_ready(session_id: StringName, summary: String)
## 标题中途生成完成（策划案 §10.2 第 1 步）：UI 用它刷新直播间标题。
signal title_ready(title: String)

const LiveDSLParserClass = preload("res://scripts/game/live_stream/live_dsl_parser.gd")
const LIVE_DSL_REPAIR_AGENT_SCENE: PackedScene = preload(
	"res://scenes/game/live_stream/live_dsl_repair_agent.tscn"
)
const SKILL_DOMAIN_CATALOG: StreamerSkillDomainCatalog = preload(
	"res://resources/live_stream/skills/streamer_skill_domains.tres"
)
const StreamHistoryStoreClass = preload("res://scripts/game/live_stream/stream_history_store.gd")
const PROMPT_KEY: String = "live_stream/live_show"
const SUMMARY_PROMPT_KEY: String = "live_stream/live_summary"
const REQUEST_TIMEOUT_MSEC: int = 30000
const TITLE_REQUEST_TIMEOUT_MSEC: int = 10000
const SUMMARY_REQUEST_TIMEOUT_MSEC: int = 20000
const MAX_ATTEMPTS: int = 2
const MAX_SUMMARY_ATTEMPTS: int = 2
const MAX_TITLE_LENGTH: int = 48
const MAX_SUMMARY_LINES: int = 2
const MAX_SUMMARY_LINE_LENGTH: int = 140

const TITLE_SYSTEM_PROMPT: String = "你正在替主播填写开播前的直播间标题。它是主播此刻挂在房间门口的一句话，不是直播结束后制作的视频标题。根据人设、本场素材、选定的直播构思与近期直播上下文取名：可以口语化、玩梗、夸张、使用感叹号、网络语、角色口癖或故意随手的短句；可以只抓住主播此刻最想拿来招呼观众的一个点，不必规整概括内容，也不固定使用分隔符。近期记录只在本场素材或直播构思本身已经明确延续同一内容、为旧约定提供对应主题时用于续播语感；旧承诺本身不能改变本场主题，与当前内容无关时完全忽略。不能仅因记录里出现过某个醒目名词或物件就把它带入标题。标题可以承诺本场计划做的事，但不能预知随机结果或尚未发生的剧情。只输出标题：单行、不加引号、不加解释、不超过 48 字。"

enum Phase { NONE, TITLE, SHOW, REPAIR, SUMMARY }

@export var llm_enabled: bool = true
@export var summary_enabled: bool = true

var _plan: StreamPlanSnapshot = null
var _result: StreamSettlementResult = null
var _catalog: LiveStreamCatalog = null
var _model: StreamerModelResource = null
var _llm: AIService = null
var _repair_agent: LiveDSLRepairAgent = null
var _pending_request_id: String = ""
var _pending_started_msec: int = 0
var _phase: int = Phase.NONE
var _attempt: int = 0
var _repair_session_id: StringName = &""
var _summary_attempt: int = 0
var _summary_source_dsl: String = ""
var _summary_errors: Array[String] = []
var _finished: bool = false


func setup(
	plan: StreamPlanSnapshot,
	result: StreamSettlementResult,
	catalog: LiveStreamCatalog,
	model: StreamerModelResource
) -> void:
	_cancel_active_repair()
	_plan = plan
	_result = result
	_catalog = catalog
	_model = model
	_finished = false
	_phase = Phase.NONE
	_attempt = 0
	_repair_session_id = &""
	_summary_attempt = 0
	_summary_source_dsl = ""
	_summary_errors.clear()


func generate() -> void:
	if _finished:
		return
	_cancel_active_repair()
	_attempt = 0
	_repair_session_id = &""
	_summary_attempt = 0
	_summary_source_dsl = ""
	_summary_errors.clear()
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
	_pending_request_id = _llm.chat_simple(prompt, TITLE_SYSTEM_PROMPT, {
		"temperature": 0.85,
		"max_tokens": 128,
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
	})
	_pending_started_msec = Time.get_ticks_msec()


func _build_title_prompt() -> String:
	if _plan == null or _catalog == null:
		return ""
	var vars: Dictionary = _build_vars()
	return "\n".join([
		"主播与频道：\n%s" % vars.get("persona_block", ""),
		"这是该人设第 %s 场直播。" % vars.get("stream_count", "1"),
		"本场素材与内容：\n%s" % vars.get("material_block", ""),
		"选定的直播构思：\n%s" % vars.get("approach_block", ""),
		"主播当前状态：%s" % vars.get("state_block", ""),
		"该人设近期直播记录：\n%s" % vars.get("history_block", ""),
		"本场内容锚点：%s" % vars.get("current_content_anchor", ""),
		"根据这些开播前已经知道的内容，写一个像主播本人会使用的直播间标题。",
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
	var timeout_msec: int = REQUEST_TIMEOUT_MSEC
	if _phase == Phase.TITLE:
		timeout_msec = TITLE_REQUEST_TIMEOUT_MSEC
	elif _phase == Phase.SUMMARY:
		timeout_msec = SUMMARY_REQUEST_TIMEOUT_MSEC
	if Time.get_ticks_msec() - _pending_started_msec > timeout_msec:
		_pending_request_id = ""
		if _phase == Phase.TITLE:
			_apply_fallback_title()
			_request_generation()
		elif _phase == Phase.SUMMARY:
			_finish_summary("")
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


func _ensure_repair_agent() -> bool:
	if _repair_agent != null:
		return _repair_agent.is_available()
	_repair_agent = LIVE_DSL_REPAIR_AGENT_SCENE.instantiate() as LiveDSLRepairAgent
	if _repair_agent == null:
		return false
	add_child(_repair_agent)
	_repair_agent.repair_completed.connect(_on_repair_completed)
	_repair_agent.repair_failed.connect(_on_repair_failed)
	return _repair_agent.is_available()


func _request_generation() -> void:
	_phase = Phase.SHOW
	_attempt += 1
	var prompt: String = _build_prompt()
	if prompt.is_empty():
		_finish_failed("empty_prompt")
		return
	var system_prompt: String = "你是直播台本写手。根据素材与本场构思写出一件有开端、变化和回报的直播现场事件。每条 say 都是逐字显示的直播字幕，必须包含主播真正说出或唱出的正文；歌词优先写成成对音符包围的实际唱词，开头可以有简短演出提示，但不能整句只有旁白式说明。只输出可播放的直播 DSL 文本。"
	print("[LLM:live_show] ---- system prompt ----")
	print(system_prompt)
	print("[LLM:live_show] ---- prompt ----")
	print(prompt)
	_pending_request_id = _llm.chat_simple(prompt, system_prompt, {
		"temperature": 0.85,
		"max_tokens": 3072,
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
	})
	_pending_started_msec = Time.get_ticks_msec()


func _start_repair(dsl_text: String, validation_errors: Array) -> bool:
	if _plan == null or dsl_text.strip_edges().is_empty() or validation_errors.is_empty():
		return false
	if not _ensure_repair_agent():
		return false
	_phase = Phase.REPAIR
	_pending_request_id = ""
	_repair_session_id = _plan.session_id
	_repair_agent.attempt_repair(
		_repair_session_id,
		dsl_text,
		validation_errors,
		Callable(self, "compile_dsl"),
		_build_repair_hints(validation_errors),
	)
	return true


func _build_repair_hints(validation_errors: Array) -> Dictionary:
	var error_text: String = "\n".join(validation_errors)
	var hints: Dictionary = {}
	if "表情" in error_text:
		hints["expression"] = _format_expression_list()
	if "手臂姿势" in error_text:
		hints["arm_pose"] = _format_name_list(_model.supported_arm_poses if _model != null else [])
	if "头部姿势" in error_text:
		hints["head_pose"] = _format_name_list(_model.supported_head_poses if _model != null else [])
	if "姿态" in error_text:
		hints["posture"] = _format_name_list(_model.supported_postures if _model != null else [])
	if "手势" in error_text:
		hints["gesture"] = _format_name_list(_model.supported_gestures if _model != null else [])
	if "服装" in error_text:
		hints["costume"] = _format_name_list(_model.supported_costumes if _model != null else [])
	if "未知语句" in error_text:
		hints["command"] = "expression, posture, arm_pose, head_pose, gesture, costume, say, chat [数量], sc [数量], wait"
	return hints


func _retry_generation_after_repair() -> void:
	_repair_session_id = &""
	if _attempt < MAX_ATTEMPTS:
		_request_generation()
	else:
		_finish_failed("compile_failed")


func _cancel_active_repair() -> void:
	if _repair_agent != null and _repair_agent.is_busy():
		_repair_agent.cancel_repair()
	_repair_session_id = &""


func _request_summary() -> void:
	_phase = Phase.SUMMARY
	_summary_attempt += 1
	var prompt: String = _build_summary_prompt()
	if prompt.is_empty():
		_finish_summary("")
		return
	if not _summary_errors.is_empty():
		prompt += "\n\n## 上次格式错误\n\n只修正以下格式错误并重新输出摘要正文：\n- " + "\n- ".join(_summary_errors)
	var system_prompt: String = "你是直播连续性记录员。只根据已通过校验的直播 DSL 写一至两行事实摘要。"
	print("[LLM:live_summary] ---- system prompt ----")
	print(system_prompt)
	print("[LLM:live_summary] ---- prompt ----")
	print(prompt)
	_pending_request_id = _llm.chat_simple(prompt, system_prompt, {
		"temperature": 0.2,
		"max_tokens": 256,
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
	})
	_pending_started_msec = Time.get_ticks_msec()


func _build_summary_prompt() -> String:
	if _plan == null or _summary_source_dsl.is_empty():
		return ""
	var persona: StreamPersonaResource = _catalog.get_persona(_plan.persona_id) if _catalog != null else null
	var vars: Dictionary = {
		"persona_name": persona.display_name if persona != null else String(_plan.persona_id),
		"stream_title": _plan.title,
		"dsl_text": _summary_source_dsl,
	}
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager != null and prompt_manager.has_method("resolve_with_vars"):
		return str(prompt_manager.resolve_with_vars(SUMMARY_PROMPT_KEY, vars)).strip_edges()
	return "人设：%s\n标题：%s\n直播 DSL：\n%s\n\n请只输出一至两行事实摘要。" % [
		vars.get("persona_name", ""),
		vars.get("stream_title", ""),
		vars.get("dsl_text", ""),
	]


func _validate_summary(raw: String) -> Dictionary:
	var normalized: String = raw.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	var lines: Array[String] = []
	for raw_line: String in normalized.split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.is_empty():
			lines.append(line)
	var errors: Array[String] = []
	if lines.is_empty():
		errors.append("摘要不能为空")
	if lines.size() > MAX_SUMMARY_LINES:
		errors.append("摘要只能有一至两行")
	for line: String in lines:
		if line.length() > MAX_SUMMARY_LINE_LENGTH:
			errors.append("每行摘要不能超过 %d 字" % MAX_SUMMARY_LINE_LENGTH)
	return {
		"success": errors.is_empty(),
		"summary": "\n".join(lines),
		"errors": errors,
	}


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
	var persona_stream_count: int = 1
	if game_state != null and _plan != null:
		var history_store = StreamHistoryStoreClass.new(game_state)
		persona_stream_count = history_store.get_record_count_for_persona(_plan.persona_id) + 1
	return {
		"persona_block": _format_persona(persona),
		"skill_block": _format_skills(material, snapshot),
		"expression_list": _format_expression_list(),
		"posture_list": _format_name_list(_model.supported_postures if _model != null else []),
		"arm_pose_list": _format_name_list(_model.supported_arm_poses if _model != null else []),
		"head_pose_list": _format_name_list(_model.supported_head_poses if _model != null else []),
		"gesture_list": _format_name_list(_model.supported_gestures if _model != null else []),
		"stream_count": str(persona_stream_count),
		"fans": str(int(snapshot.get("fans", 0))),
		"state_block": "压力 %d / 宅欲 %d / 孤独 %d" % [
			int(snapshot.get("stress", 0)),
			int(snapshot.get("otaku_desire", 0)),
			int(snapshot.get("loneliness", 0)),
		],
		"material_block": _format_material(material),
		"current_content_anchor": _format_current_content_anchor(material),
		"approach_block": _format_approach(),
		"history_block": _format_history(game_state),
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
	if not fragment.is_empty():
		var prompt_manager: Node = get_node_or_null("/root/PromptManager")
		if prompt_manager != null and prompt_manager.has_method("resolve_template"):
			fragment = str(prompt_manager.resolve_template(fragment)).strip_edges()
	if fragment.is_empty():
		return persona.display_name
	return fragment


func _format_history(game_state: Node) -> String:
	if game_state == null or _plan == null or _plan.persona_id == &"":
		return "暂无已完成的直播记录。"
	var history_store = StreamHistoryStoreClass.new(game_state)
	var records: Array[StreamSessionRecord] = history_store.get_recent_records_for_persona(
		_plan.persona_id,
		3
	)
	if records.is_empty():
		return "暂无已完成的直播记录。"
	var lines: Array[String] = []
	for record: StreamSessionRecord in records:
		var summary: String = record.summary.strip_edges().replace("\n", "\n  ")
		lines.append("- 第 %d 天《%s》\n  %s" % [record.day, record.title, summary])
	return "\n".join(lines)


func _format_current_content_anchor(material: LiveStreamMaterialResource) -> String:
	var parts: Array[String] = []
	if material != null:
		parts.append("素材《%s》" % material.display_name)
	if _plan != null and not _plan.approach.is_empty():
		parts.append("构思：%s" % str(_plan.approach.get("display_name", "")))
	return "；".join(parts) if not parts.is_empty() else "当前素材与直播构思"


func _format_skills(material: LiveStreamMaterialResource, snapshot: Dictionary) -> String:
	var relevant_families: Array[StringName] = []
	if material != null and material.skill_exp_rewards != null:
		for family: StringName in GameState.SKILL_FAMILIES:
			if material.skill_exp_rewards.get_value(family) > 0:
				relevant_families.append(family)
	if _plan != null:
		var profile: Dictionary = LiveStreamBalance.new().get_approach_profile(
			StringName(str(_plan.approach.get("approach_type", "")))
		)
		for family_value: Variant in profile.get("support_families", []):
			var family := StringName(str(family_value))
			if family not in relevant_families:
				relevant_families.append(family)
	if relevant_families.is_empty():
		relevant_families.assign(GameState.SKILL_FAMILIES)
	var levels: Dictionary = snapshot.get("skill_levels", {})
	var lines: Array[String] = []
	for family: StringName in GameState.SKILL_FAMILIES:
		if family not in relevant_families:
			continue
		var domain: StreamerSkillDomainResource = SKILL_DOMAIN_CATALOG.get_domain(family)
		if domain == null:
			continue
		var level: int = clampi(int(levels.get(String(family), 1)), 1, 5)
		lines.append("%s Lv.%d：%s" % [domain.display_name, level, domain.get_level_prompt(level)])
	return "\n".join(lines)


func _format_material(material: LiveStreamMaterialResource) -> String:
	if material == null:
		return "无特定素材"
	var fragment: String = material.prompt_fragment.strip_edges()
	if fragment.is_empty():
		return material.display_name
	return "素材：%s\n导演提示：%s" % [material.display_name, fragment]


func _format_approach() -> String:
	if _plan == null or _plan.approach.is_empty():
		return "围绕本场素材自然展开"
	return "名称：%s\n导演指令：%s" % [
		str(_plan.approach.get("display_name", "")),
		str(_plan.approach.get("director_prompt", "")),
	]


func _format_outcome() -> String:
	if _result == null:
		return "直播正常完成。"
	var hints: Array[String] = []
	hints.append("观众反响参考：峰值观看 %d，新增粉丝 %d" % [_result.peak_viewers, _result.fan_delta])
	if _result.sponsor_satisfied:
		hints.append("赞助要求最终达成")
	else:
		hints.append("赞助要求最终未达成")
	return "\n- " + "\n- ".join(hints)


func _build_inline_prompt(vars: Dictionary) -> String:
	return "\n".join([
		"输出直播 DSL。",
		"语法：expression: 表情；posture: 姿态；arm_pose: 手臂姿势；head_pose: 头部姿势；gesture: 手势；say: 台词；chat [数量]: 消息 | 消息；sc [数量]: 消息 | 消息；wait: 秒数。",
		"持续状态（姿态、手臂姿势、头部姿势、表情）在情绪回落和整场收尾时显式归位 idle/default。",
		"可用表情：%s" % vars.get("expression_list", ""),
		"可用姿态：%s" % vars.get("posture_list", ""),
		"可用手臂姿势：%s" % vars.get("arm_pose_list", ""),
		"可用头部姿势：%s" % vars.get("head_pose_list", ""),
		"可用手势：%s" % vars.get("gesture_list", ""),
		"主播人设：%s" % vars.get("persona_block", ""),
		"中之人能力：\n%s" % vars.get("skill_block", ""),
		"行动、判断、演唱、主持和制作表现必须符合对应领域的能力描述。",
		"该人设开播序号：第 %s 场；这是连续性元数据，不是本场内容数量；粉丝 %s" % [
			vars.get("stream_count", "1"), vars.get("fans", "0"),
		],
		"主播状态：%s" % vars.get("state_block", ""),
		"本场素材：%s" % vars.get("material_block", ""),
		"直播构思：\n%s" % vars.get("approach_block", ""),
		"历史记录只提供本场可以引用的既往事实上限，不是必须回收的素材池。只有本场素材或直播构思本身已经延续同一内容、为旧约定提供对应主题，或当前行动必须依赖该事实时才能引用。旧承诺本身不能改变本场主题；若本场素材和直播构思没有指向它，就留待以后。历史里的孤立名词、物件、语气、单次笑点和告别用语与本场不构成关联；无关时完全忽略，不得把它们带入台词、弹幕或收尾。忽略的内容不能用否定句提及，也不能让弹幕追问后再拒绝。\n%s\n\n输出前以本场素材和直播构思筛选历史：无法直接说明关联的条目视为本次没有提供，最后一句和告别弹幕也不例外。\n本场内容锚点：%s" % [
			vars.get("history_block", ""),
			vars.get("current_content_anchor", ""),
		],
		"本场走向：%s" % vars.get("outcome_block", ""),
	])


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_request_id or _finished:
		return
	_pending_request_id = ""
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _pending_started_msec) / 1000.0
	var reasoning_text: String = AIService.extract_reasoning_content(response).strip_edges()
	var phase_label: String = "title" if _phase == Phase.TITLE else ("summary" if _phase == Phase.SUMMARY else "show")
	print("[LiveShowGenerator] phase=%s elapsed=%.2fs reasoning_lines=%d reasoning_chars=%d" % [
		phase_label,
		elapsed_seconds,
		0 if reasoning_text.is_empty() else reasoning_text.split("\n").size(),
		reasoning_text.length(),
	])
	if _phase == Phase.TITLE:
		_apply_title(AIService.extract_content(response))
		return
	if _phase == Phase.SUMMARY:
		var summary_validation: Dictionary = _validate_summary(AIService.extract_content(response))
		if bool(summary_validation.get("success", false)):
			_finish_summary(str(summary_validation.get("summary", "")))
			return
		_summary_errors.assign(summary_validation.get("errors", []))
		if _summary_attempt < MAX_SUMMARY_ATTEMPTS:
			_request_summary()
		else:
			_finish_summary("")
		return
	var content: String = AIService.extract_content(response)
	var compiled: Dictionary = compile_dsl(content)
	if bool(compiled.get("success", false)):
		_begin_summary(compiled.get("show", {}))
		return
	var validation_errors: Array = compiled.get("errors", ["compile_failed"])
	if not _start_repair(content, validation_errors):
		_retry_generation_after_repair()


func _on_repair_completed(session_id: StringName, dsl_text: String) -> void:
	if _finished or session_id != _repair_session_id:
		return
	_repair_session_id = &""
	var compiled: Dictionary = compile_dsl(dsl_text)
	if bool(compiled.get("success", false)):
		_begin_summary(compiled.get("show", {}))
		return
	_retry_generation_after_repair()


func _on_repair_failed(session_id: StringName, _error: String) -> void:
	if _finished or session_id != _repair_session_id:
		return
	_retry_generation_after_repair()


func _on_request_failed(request_id: String, _error: String, _error_code: int) -> void:
	if request_id != _pending_request_id or _finished:
		return
	_pending_request_id = ""
	if _phase == Phase.TITLE:
		_apply_fallback_title()
		_request_generation()
		return
	if _phase == Phase.SUMMARY:
		_finish_summary("")
		return
	_finish_failed("request_failed")


func _finish_failed(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_pending_request_id = ""
	_cancel_active_repair()
	generation_failed.emit(reason)


func _begin_summary(show: Dictionary) -> void:
	if _finished:
		return
	_pending_request_id = ""
	show_ready.emit(show)
	_summary_source_dsl = str(show.get("dsl_text", ""))
	_summary_attempt = 0
	_summary_errors.clear()
	if not summary_enabled:
		_finish_summary("")
		return
	_request_summary()


func _finish_summary(summary: String) -> void:
	if _finished:
		return
	_finished = true
	_pending_request_id = ""
	summary_ready.emit(_plan.session_id if _plan != null else &"", summary)
