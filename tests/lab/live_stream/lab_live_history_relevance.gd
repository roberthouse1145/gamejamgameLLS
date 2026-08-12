extends Node
## 真实 LLM 历史相关性实验：无关历史不得污染新直播；summary 不把一次性物件误记为梗。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")
const HISTORY_STORE_SCRIPT = preload("res://scripts/game/live_stream/stream_history_store.gd")
const PERSONA_ID: StringName = &"persona_default"
const MATERIAL_ID: StringName = &"material_masterpiece_boss"
const SUMMARY_FIXTURE: String = """say: 刚才下雨，伞放门口了，先不管它，今天继续打最终 BOSS。
chat: 水杯又空了 | 水杯警报
say: 什么水杯警报，我只是忘记倒水。
chat: 水杯警报解除了吗 | 先喝水再开怪
say: 好好好，水杯警报解除。以后你们提醒我喝水就叫这个。
say: 最后一阶段看地面光圈，躲完再输出。
chat: 过了！ | 水杯警报立功 | 终于通关
say: 通关了，今晚这趟旅程算是好好收尾了。"""

var _original_history: Array[Dictionary] = []
var _show_generator: LiveShowGenerator = null
var _summary_generator: LiveShowGenerator = null
var _history_clean: bool = false


func _ready() -> void:
	_original_history.assign(GameState.stream_history.duplicate(true))
	GameState.stream_history.clear()
	var record := StreamSessionRecord.new()
	record.session_id = "history_relevance_fixture"
	record.day = 1
	record.title = "今晚弹幕不许假装听不懂开场白"
	record.persona_id = PERSONA_ID
	record.persona_name = "白星眠"
	record.summary = "白星眠聊新番片头曲和名场面，因弹幕起哄示范搭腰和气声时设备出现电流声翻车，承诺下次专门讲伞下亲亲名场面并展示气声学习成果，结尾以带伞作为告别梗。"
	var history_store: StreamHistoryStore = HISTORY_STORE_SCRIPT.new(GameState)
	if not history_store.add_record(record):
		_finish_lab(false, "history_setup_failed")
		return
	call_deferred("_start_unrelated_show")


func _start_unrelated_show() -> void:
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	var material: LiveStreamMaterialResource = CATALOG.get_material(MATERIAL_ID)
	if persona == null or persona.model == null or material == null:
		_finish_lab(false, "missing_content")
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"lab_history_relevance_show"
	plan.title = "最终 BOSS 今晚必须过"
	plan.persona_id = PERSONA_ID
	plan.approach = {"approach_id": "boss_challenge", "approach_type": "challenge", "display_name": "今晚必须打完最终战", "display_description": "让每次尝试都推进最终通关目标。", "director_prompt": "围绕击败最终首领推进，每次失败都带来具体策略变化，胜负出现后立即收束。"}
	plan.rng_seed = 20260812
	plan.state_snapshot = {
		"skill_levels": {"game": 3, "talk": 2, "song": 1, "act": 1, "tech": 2},
		"stress": 20,
		"otaku_desire": 35,
		"loneliness": 20,
		"fans": 1200,
		"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
		"material_instance": {"definition_id": String(MATERIAL_ID)},
	}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, CATALOG, BALANCE)
	_show_generator = GENERATOR_SCRIPT.new()
	_show_generator.summary_enabled = false
	add_child(_show_generator)
	_show_generator.setup(plan, result, CATALOG, persona.model)
	_show_generator.show_ready.connect(_on_unrelated_show_ready)
	_show_generator.generation_failed.connect(_on_generation_failed.bind("show"))
	if not _show_generator._ensure_llm():
		_finish_lab(false, "show_llm_unavailable")
		return
	print("LAB_LIVE_HISTORY_RELEVANCE_SHOW_START")
	_show_generator._request_generation()


func _on_unrelated_show_ready(show: Dictionary) -> void:
	var dsl_text: String = str(show.get("dsl_text", ""))
	var leaked_terms: Array[String] = []
	for term: String in ["伞", "气声", "亲亲", "搭腰", "听不懂开场白"]:
		if term in dsl_text:
			leaked_terms.append(term)
	_history_clean = leaked_terms.is_empty()
	print("LAB_LIVE_HISTORY_RELEVANCE_SHOW_RESULT clean=%d leaked=%s dsl=%s" % [
		int(_history_clean),
		JSON.stringify(leaked_terms),
		JSON.stringify(dsl_text),
	])
	if _show_generator != null:
		_show_generator.queue_free()
		_show_generator = null
	call_deferred("_start_summary_case")


func _start_summary_case() -> void:
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	if persona == null or persona.model == null:
		_finish_lab(false, "missing_summary_persona")
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"lab_history_relevance_summary"
	plan.title = "最终 BOSS 收尾"
	plan.persona_id = PERSONA_ID
	_summary_generator = GENERATOR_SCRIPT.new()
	add_child(_summary_generator)
	_summary_generator.setup(plan, null, CATALOG, persona.model)
	_summary_generator.summary_ready.connect(_on_summary_ready)
	_summary_generator.generation_failed.connect(_on_generation_failed.bind("summary"))
	if not _summary_generator._ensure_llm():
		_finish_lab(false, "summary_llm_unavailable")
		return
	_summary_generator.set("_summary_source_dsl", SUMMARY_FIXTURE)
	print("LAB_LIVE_HISTORY_RELEVANCE_SUMMARY_START")
	_summary_generator._request_summary()


func _on_summary_ready(_session_id: StringName, summary: String) -> void:
	var incidental_omitted: bool = "伞" not in summary
	var established_kept: bool = "水杯警报" in summary
	print("LAB_LIVE_HISTORY_RELEVANCE_SUMMARY_RESULT incidental_omitted=%d established_kept=%d text=%s" % [
		int(incidental_omitted),
		int(established_kept),
		JSON.stringify(summary),
	])
	_finish_lab(_history_clean and incidental_omitted and established_kept, "completed")


func _on_generation_failed(reason: String, phase: String) -> void:
	_finish_lab(false, "%s_generation_failed:%s" % [phase, reason])


func _finish_lab(ok: bool, reason: String) -> void:
	GameState.stream_history.assign(_original_history)
	print("LAB_LIVE_HISTORY_RELEVANCE_DONE ok=%d reason=%s" % [int(ok), reason])
