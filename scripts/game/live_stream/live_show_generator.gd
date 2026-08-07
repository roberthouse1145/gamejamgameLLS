class_name LiveShowGenerator extends Node
## 一次性生成整场直播 DSL：装配 prompt → LLM → 解析校验 → 重试/模板兜底。

signal show_ready(show: Dictionary)
signal generation_failed(reason: String)

const LiveDSLParserClass = preload("res://scripts/game/live_stream/live_dsl_parser.gd")
const PROMPT_KEY: String = "live_stream/live_show"
const REQUEST_TIMEOUT_MSEC: int = 30000
const MAX_ATTEMPTS: int = 2

const FALLBACK_LINES: Dictionary = {
	"opening": ["大家晚上好，今天也准时开播了。", "来了来了，今天播这个。"],
	"closing": ["今天就到这里，谢谢大家陪我。", "下播啦，下次见。"],
	"game": ["这里先这样操作……好，过了。", "等一下，这个我来过一次的。"],
	"talk": ["说起来，最近遇到一件事——", "你们有没有那种感觉，就是……"],
	"song": ["那，接下来这首，轻轻唱。", "（清了清嗓子）嗯，开始。"],
	"act": ["咳咳，今天的人家，可、可是很努力的呢。", "哼哼，看好了，这才是人家的实力。"],
	"tech": ["稍等，我调一下这边……好了。", "这个参数之前研究过，应该没问题。"],
}

@export var llm_enabled: bool = true

var _plan: StreamPlanSnapshot = null
var _result: StreamSettlementResult = null
var _catalog: LiveStreamCatalog = null
var _streamer: StreamerCharacterResource = null
var _llm: AIService = null
var _pending_request_id: String = ""
var _pending_started_msec: int = 0
var _attempt: int = 0
var _last_errors: Array = []
var _finished: bool = false
var _rng := RandomNumberGenerator.new()


func setup(
	plan: StreamPlanSnapshot,
	result: StreamSettlementResult,
	catalog: LiveStreamCatalog,
	streamer: StreamerCharacterResource
) -> void:
	_plan = plan
	_result = result
	_catalog = catalog
	_streamer = streamer
	_rng.seed = plan.rng_seed if plan != null else 1
	_finished = false
	_attempt = 0
	_last_errors.clear()


func generate() -> void:
	if _finished:
		return
	_attempt = 0
	_last_errors.clear()
	if llm_enabled:
		_ensure_llm()
		_request_generation()
	else:
		_emit_fallback("llm_disabled")


func compile_dsl(dsl_text: String, title: String = "") -> Dictionary:
	var parser := LiveDSLParserClass.new()
	var scene_title: String = title
	if scene_title.is_empty():
		scene_title = _plan.title if _plan != null else "直播"
	var expression_names: Array = _streamer.get_expression_names() if _streamer != null else []
	var parsed: Dictionary = parser.parse(dsl_text, expression_names)
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


func get_axis_hint() -> String:
	if _result == null:
		return DanmakuPool.HINT_NEUTRAL
	if _result.accident_occurred:
		return DanmakuPool.HINT_RISK
	var axes: Dictionary = _result.axes
	var best_key: String = DanmakuPool.HINT_NEUTRAL
	var best_value: float = 0.0
	for key: String in [DanmakuPool.HINT_HOOK, DanmakuPool.HINT_QUALITY, DanmakuPool.HINT_IMPACT, DanmakuPool.HINT_RISK]:
		var value: float = float(axes.get(key, 0.0))
		if value > best_value:
			best_value = value
			best_key = key
	return best_key if best_value > 0.0 else DanmakuPool.HINT_NEUTRAL


func _process(_delta: float) -> void:
	if _pending_request_id.is_empty() or _finished:
		return
	if Time.get_ticks_msec() - _pending_started_msec > REQUEST_TIMEOUT_MSEC:
		_pending_request_id = ""
		_emit_fallback("timeout")


func _ensure_llm() -> void:
	if _llm != null:
		return
	_llm = AIService.new()
	_llm.request_completed.connect(_on_request_completed)
	_llm.request_failed.connect(_on_request_failed)
	add_child(_llm)
	var config_mgr := AIConfigManager.get_instance()
	if not config_mgr.apply_to_service(_llm, "chat_default"):
		pass


func _request_generation() -> void:
	_attempt += 1
	var prompt: String = _build_prompt()
	if prompt.is_empty():
		_emit_fallback("empty_prompt")
		return
	var system_prompt: String = "你是直播台本写手。只输出可播放的直播 DSL 文本。"
	if not _last_errors.is_empty():
		system_prompt += "\n上次校验失败，请按错误修正后重新输出完整 DSL：\n- " + "\n- ".join(_last_errors)
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
	if _streamer == null:
		return ""
	var names: Array[String] = []
	for expression: StringName in _streamer.get_expression_names():
		names.append(String(expression))
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
		"语法：say [表情]: 台词；chat [数量]: 消息 | 消息；sc [数量]: 消息 | 消息；wait: 秒数。",
		"可用表情：%s" % vars.get("expression_list", ""),
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
	var content: String = AIService.extract_content(response)
	var compiled: Dictionary = compile_dsl(content)
	if bool(compiled.get("success", false)):
		_finish_ready(compiled.get("show", {}))
		return
	_last_errors = compiled.get("errors", ["compile_failed"])
	if _attempt < MAX_ATTEMPTS:
		_request_generation()
	else:
		_emit_fallback("compile_failed")


func _on_request_failed(request_id: String, _error: String, _error_code: int) -> void:
	if request_id != _pending_request_id or _finished:
		return
	_pending_request_id = ""
	_emit_fallback("request_failed")


func _emit_fallback(reason: String) -> void:
	var dsl: String = _build_fallback_dsl()
	var compiled: Dictionary = compile_dsl(dsl)
	if bool(compiled.get("success", false)):
		_finish_ready(compiled.get("show", {}))
	else:
		_finished = true
		generation_failed.emit(reason)


func _build_fallback_dsl() -> String:
	var lines: Array[String] = []
	lines.append("say: %s" % _pick_fallback("opening"))
	lines.append("chat: 来了来了 | 前排 | 打卡")
	if _plan != null and _catalog != null:
		for card_id: StringName in _plan.behavior_card_ids:
			var card: LiveStreamCardResource = _catalog.get_card(card_id)
			var family: String = String(card.family) if card != null else "talk"
			var name: String = card.display_name if card != null else "节目"
			lines.append("wait: 0.2")
			lines.append("say: %s——%s" % [name, _pick_fallback(family)])
			lines.append("chat: 不错 | 继续 | 哈哈哈")
	lines.append("sc: 今天也好看")
	lines.append("say: %s" % _pick_fallback("closing"))
	lines.append("chat: 辛苦了 | 下次见")
	return "\n".join(lines)


func _pick_fallback(key: String) -> String:
	var pool: Array = FALLBACK_LINES.get(key, FALLBACK_LINES["talk"])
	return String(pool[_rng.randi_range(0, pool.size() - 1)])


func _finish_ready(show: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_pending_request_id = ""
	show_ready.emit(show)
