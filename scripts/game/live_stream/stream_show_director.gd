class_name StreamShowDirector extends Node
## 直播演出逐拍导演：节拍序列、LLM 流水线、模板兜底与播放控制。
## 数值真相来自预结算结果，本类只生产演出装饰（台词/表情/弹幕）。
## 通过信号驱动 UI，本身不触碰任何控件。

signal beat_content_resolved(beat: Dictionary)
signal beat_started(beat: Dictionary)
signal first_beat_resolved()
signal show_finished()

const KIND_OPENING: StringName = &"opening"
const KIND_CARD: StringName = &"card"
const KIND_CLOSING: StringName = &"closing"

const PROMPT_KEY: String = "channel/live_beat"
const REQUEST_TIMEOUT_MSEC: int = 15000
const DANMAKU_PER_BEAT: int = 3

const EMOTION_KEYS: Array[String] = [
	"default", "embarrassed", "neutral", "panicked",
	"shocked", "smile", "strained", "worried",
]

## 按系别准备的兜底台词；LLM 失败/超时/解析失败时使用。
const FALLBACK_LINES: Dictionary = {
	"opening": ["大家晚上好，今天也准时开播了。", "来了来了，今天播这个。"],
	"closing": ["今天就到这里，谢谢大家陪我。", "下播啦，下次见。"],
	"game": ["这里先这样操作……好，过了。", "等一下，这个我来过一次的。"],
	"talk": ["说起来，最近遇到一件事——", "你们有没有那种感觉，就是……"],
	"song": ["那，接下来这首，轻轻唱。", "（清了清嗓子）嗯，开始。"],
	"act": ["咳咳，今天的人家，可、可是很努力的呢。", "哼哼，看好了，这才是人家的实力。"],
	"tech": ["稍等，我调一下这边……好了。", "这个参数之前研究过，应该没问题。"],
}

## 拍间隔（秒）；测试可调小。快进时使用 fast_interval。
@export var beat_interval: float = 6.0
@export var fast_interval: float = 2.0
## 关闭后全部走模板兜底（测试与纯离线环境用）。
@export var llm_enabled: bool = true

var _plan: StreamPlanSnapshot = null
var _result: StreamSettlementResult = null
var _catalog: LiveStreamCatalog = null
var _beats: Array[Dictionary] = []
var _current_beat: int = -1
var _awaiting_beat: int = -1
var _finished: bool = false
var _first_resolved_emitted: bool = false
var _fast_forward: bool = false
var _llm: AIService = null
var _pending_requests: Dictionary = {}
var _beat_timer: Timer = null
var _rng := RandomNumberGenerator.new()


func setup(plan: StreamPlanSnapshot, result: StreamSettlementResult, catalog: LiveStreamCatalog) -> void:
	_plan = plan
	_result = result
	_catalog = catalog
	_rng.seed = plan.rng_seed if plan != null else 1
	_build_beats()


func get_beats() -> Array[Dictionary]:
	return _beats


## 本场弹幕倾向（chat 区环境弹幕用）。
func get_axis_hint() -> String:
	return _axis_hint()


func get_beat_count() -> int:
	return _beats.size()


func start() -> void:
	if _beats.is_empty() or _finished:
		return
	if llm_enabled and _llm == null:
		_llm = AIService.new()
		_llm.request_completed.connect(_on_request_completed)
		_llm.request_failed.connect(_on_request_failed)
		add_child(_llm)
	_resolve_beat(0)


func set_fast_forward(enabled: bool) -> void:
	_fast_forward = enabled


## 立即结束演出；数值早已预结算，跳过只丢装饰。
func skip() -> void:
	_finish()


func _process(_delta: float) -> void:
	if _pending_requests.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var timed_out: Array = []
	for request_id: String in _pending_requests:
		var entry: Dictionary = _pending_requests[request_id]
		if now - int(entry.get("time", now)) > REQUEST_TIMEOUT_MSEC:
			timed_out.append(request_id)
	for request_id: String in timed_out:
		var entry: Dictionary = _pending_requests[request_id]
		_pending_requests.erase(request_id)
		_apply_fallback(int(entry.get("beat", -1)))


func _build_beats() -> void:
	_beats.clear()
	_beats.append(_make_beat(KIND_OPENING, -1, &"", "开场"))
	var trace_by_slot: Dictionary = {}
	if _result != null:
		for trace: Dictionary in _result.interface_trace:
			trace_by_slot[int(trace.get("slot_index", -1))] = trace
	for slot_index: int in range(_plan.behavior_card_ids.size()):
		var card_id: StringName = _plan.behavior_card_ids[slot_index]
		if card_id == &"":
			continue
		var card: LiveStreamCardResource = _catalog.get_card(card_id) if _catalog != null else null
		if card == null:
			continue
		var beat: Dictionary = _make_beat(KIND_CARD, slot_index, card_id, card.display_name)
		beat["family"] = String(card.family)
		beat["card_prompt"] = card.prompt_fragment
		var trace: Dictionary = trace_by_slot.get(slot_index, {})
		beat["fill_ratio"] = float(trace.get("fill_ratio", 1.0))
		beat["fill_multiplier"] = float(trace.get("fill_multiplier", 1.0))
		_beats.append(beat)
	_beats.append(_make_beat(KIND_CLOSING, -1, &"", "收尾"))


func _make_beat(kind: StringName, slot_index: int, card_id: StringName, card_name: String) -> Dictionary:
	return {
		"kind": kind,
		"index": _beats.size(),
		"slot_index": slot_index,
		"card_id": String(card_id),
		"card_name": card_name,
		"family": "",
		"card_prompt": "",
		"fill_ratio": 1.0,
		"fill_multiplier": 1.0,
		"line": "",
		"emotion": "default",
		"danmaku": [],
		"resolved": false,
	}


func _resolve_beat(index: int) -> void:
	if index < 0 or index >= _beats.size() or _finished:
		return
	var beat: Dictionary = _beats[index]
	if bool(beat.get("resolved", false)):
		return
	if not llm_enabled or _llm == null:
		_apply_fallback(index)
		return
	var request_id: String = _llm.chat_simple(_build_beat_user_prompt(beat), _build_system_prompt())
	_pending_requests[request_id] = {"beat": index, "time": Time.get_ticks_msec()}


func _build_system_prompt() -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager != null and prompt_manager.has_prompt(PROMPT_KEY):
		return prompt_manager.resolve_with_vars(PROMPT_KEY, {"emotion_keys": ", ".join(EMOTION_KEYS)})
	return "你是直播台本写手。只输出一个 JSON 对象：{\"line\": 台词, \"emotion\": 表情, \"danmaku\": [弹幕]}。emotion 取值：%s。" % ", ".join(EMOTION_KEYS)


func _build_beat_user_prompt(beat: Dictionary) -> String:
	var snapshot: Dictionary = _plan.state_snapshot if _plan != null else {}
	var lines: Array[String] = []
	lines.append("直播标题：%s" % (_plan.title if _plan != null else ""))
	var persona: StreamPersonaResource = _catalog.get_persona(_plan.persona_id) if _catalog != null else null
	if persona != null:
		lines.append("人设：%s（%s）" % [persona.display_name, persona.description])
	var material_state: Dictionary = snapshot.get("material_instance", {})
	var material: LiveStreamMaterialResource = _catalog.get_material(StringName(str(material_state.get("definition_id", "")))) if _catalog != null else null
	if material != null:
		lines.append("本场素材：%s（%s）" % [material.display_name, material.description])
	lines.append("节目单：%s" % _describe_program())
	lines.append("当前拍：%s（%s）" % [String(beat.get("card_name", "")), _beat_role_text(beat)])
	var card_prompt: String = String(beat.get("card_prompt", ""))
	if not card_prompt.is_empty():
		lines.append("本拍演出指示：%s" % card_prompt)
	lines.append("主播状态：压力 %d / 宅欲 %d / 孤独 %d" % [
		int(snapshot.get("stress", 0)),
		int(snapshot.get("otaku_desire", 0)),
		int(snapshot.get("loneliness", 0)),
	])
	lines.append("本场走向：%s" % _describe_outcome())
	return "\n".join(lines)


func _describe_program() -> String:
	var parts: Array[String] = []
	for beat: Dictionary in _beats:
		if beat.get("kind") == KIND_CARD:
			var fill_ratio: float = float(beat.get("fill_ratio", 1.0))
			var fill_text: String = "，接缝 %.0f%%" % (fill_ratio * 100.0) if fill_ratio < 1.0 else ""
			parts.append("%s%s" % [String(beat.get("card_name", "")), fill_text])
	return " ▸ ".join(parts)


func _beat_role_text(beat: Dictionary) -> String:
	match beat.get("kind"):
		KIND_OPENING:
			return "开场白，向观众打招呼并点出今天的节目"
		KIND_CLOSING:
			return "收尾告别，回应本场结果后下播"
	return "节目进行中的一拍"


func _describe_outcome() -> String:
	if _result == null:
		return "平稳进行"
	var hints: Array[String] = []
	if _result.accident_occurred:
		hints.append("中途出了一次直播事故")
	if _result.peak_viewers >= 2000:
		hints.append("人气明显上涨")
	if _result.revenue >= 1000:
		hints.append("打赏不少")
	return "；".join(hints) if not hints.is_empty() else "平稳进行"


func _axis_hint() -> String:
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


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	var entry: Variant = _pending_requests.get(request_id, null)
	if entry == null:
		return
	_pending_requests.erase(request_id)
	var beat_index: int = int((entry as Dictionary).get("beat", -1))
	var parsed: Dictionary = _parse_beat_json(AIService.extract_content(response))
	if parsed.is_empty():
		_apply_fallback(beat_index)
		return
	var beat: Dictionary = _beats[beat_index]
	beat["line"] = String(parsed.get("line", ""))
	beat["emotion"] = String(parsed.get("emotion", "default"))
	var danmaku: Array = []
	for item: Variant in parsed.get("danmaku", []):
		var text: String = str(item).strip_edges()
		if not text.is_empty():
			danmaku.append({"nickname": DanmakuPool.roll_nickname(_rng), "text": text})
		if danmaku.size() >= DANMAKU_PER_BEAT + 1:
			break
	beat["danmaku"] = danmaku
	_mark_resolved(beat_index)


func _on_request_failed(request_id: String, _error: String, _error_code: int) -> void:
	var entry: Variant = _pending_requests.get(request_id, null)
	if entry == null:
		return
	_pending_requests.erase(request_id)
	_apply_fallback(int((entry as Dictionary).get("beat", -1)))


func _parse_beat_json(text: String) -> Dictionary:
	var cleaned: String = text.strip_edges()
	if cleaned.begins_with("```"):
		var first_newline: int = cleaned.find("\n")
		if first_newline >= 0:
			cleaned = cleaned.substr(first_newline + 1)
		cleaned = cleaned.trim_suffix("```").strip_edges()
	var data: Variant = JSON.parse_string(cleaned)
	if not data is Dictionary:
		return {}
	var parsed: Dictionary = data
	var line: String = str(parsed.get("line", "")).strip_edges()
	if line.is_empty():
		return {}
	var emotion: String = str(parsed.get("emotion", "default"))
	if emotion not in EMOTION_KEYS:
		emotion = "default"
	var danmaku: Array = parsed.get("danmaku", [])
	if not danmaku is Array:
		danmaku = []
	return {"line": line, "emotion": emotion, "danmaku": danmaku}


func _apply_fallback(beat_index: int) -> void:
	if beat_index < 0 or beat_index >= _beats.size():
		return
	var beat: Dictionary = _beats[beat_index]
	if bool(beat.get("resolved", false)):
		return
	var pool_key: String = String(beat.get("kind", ""))
	if beat.get("kind") == KIND_CARD:
		pool_key = String(beat.get("family", "talk"))
	var pool: Array = FALLBACK_LINES.get(pool_key, FALLBACK_LINES["talk"])
	beat["line"] = String(pool[_rng.randi_range(0, pool.size() - 1)])
	beat["emotion"] = "default"
	beat["danmaku"] = DanmakuPool.roll(_rng, _axis_hint(), DANMAKU_PER_BEAT)
	_mark_resolved(beat_index)


func _mark_resolved(beat_index: int) -> void:
	if beat_index < 0 or beat_index >= _beats.size() or _finished:
		return
	var beat: Dictionary = _beats[beat_index]
	if bool(beat.get("resolved", false)):
		return
	beat["resolved"] = true
	beat_content_resolved.emit(beat)
	if beat_index == 0 and not _first_resolved_emitted:
		_first_resolved_emitted = true
		first_beat_resolved.emit()
	# 只有首播（尚未开播）或播放计时器正在等待这一拍时才立即推进；
	# 预取的下一拍提前返回时不动播放节奏。
	if beat_index == _awaiting_beat or (beat_index == 0 and _current_beat == -1):
		_play_beat(beat_index)


func _play_beat(index: int) -> void:
	if _finished or index >= _beats.size():
		return
	_current_beat = index
	_awaiting_beat = -1
	var beat: Dictionary = _beats[index]
	beat_started.emit(beat)
	_resolve_beat(index + 1)
	_start_beat_timer()


func _start_beat_timer() -> void:
	if _beat_timer == null:
		_beat_timer = Timer.new()
		_beat_timer.one_shot = true
		_beat_timer.timeout.connect(_on_beat_timer_timeout)
		add_child(_beat_timer)
	_beat_timer.start(fast_interval if _fast_forward else beat_interval)


func _on_beat_timer_timeout() -> void:
	if _finished:
		return
	var next_index: int = _current_beat + 1
	if next_index >= _beats.size():
		_finish()
		return
	var next_beat: Dictionary = _beats[next_index]
	if bool(next_beat.get("resolved", false)):
		_play_beat(next_index)
	else:
		_awaiting_beat = next_index


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_pending_requests.clear()
	if _beat_timer != null:
		_beat_timer.stop()
	show_finished.emit()
