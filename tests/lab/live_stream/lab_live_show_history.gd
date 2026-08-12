extends Node
## 真实 LLM 连续性实验：先生成一场直播及其摘要，再验证同一人设的下一场只接收真实摘要历史。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")
const HISTORY_STORE_SCRIPT = preload("res://scripts/game/live_stream/stream_history_store.gd")

const PERSONA_ID: StringName = &"persona_default"
const MATERIAL_ID: StringName = &"material_cozy_game"

var _case_index: int = 0
var _generator: LiveShowGenerator = null
var _active_plan: StreamPlanSnapshot = null
var _active_show: Dictionary = {}
var _history_store: StreamHistoryStore = null


func _ready() -> void:
	GameState.stream_history.clear()
	_history_store = HISTORY_STORE_SCRIPT.new(GameState)
	print("LAB_LIVE_HISTORY_START")
	call_deferred("_start_case")


func _start_case() -> void:
	if _case_index >= 2:
		var records: Array[StreamSessionRecord] = _history_store.get_recent_records_for_persona(PERSONA_ID, 3)
		print("LAB_LIVE_HISTORY_ALL_DONE ok=1 records=%d" % records.size())
		return
	var material: LiveStreamMaterialResource = CATALOG.get_material(MATERIAL_ID)
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	if material == null or persona == null:
		print("LAB_LIVE_HISTORY_ALL_DONE ok=0 error=missing_content")
		return
	_active_plan = StreamPlanSnapshot.new()
	_active_plan.session_id = StringName("lab_history_%d" % (_case_index + 1))
	_active_plan.title = material.display_name
	_active_plan.persona_id = PERSONA_ID
	_active_plan.approach = {"approach_id": "cozy_audience", "approach_type": "audience_interaction", "display_name": "和弹幕一起决定岛上行程", "display_description": "把关键去向交给观众选择。", "director_prompt": "让弹幕至少一次真正改变岛上的下一段行动，并回收这个共同选择造成的结果。"}
	_active_plan.rng_seed = 20260812 + _case_index
	_active_plan.state_snapshot = {
		"skill_levels": {"game": 3, "talk": 3, "song": 1, "act": 1, "tech": 1},
		"stress": 18,
		"otaku_desire": 35,
		"loneliness": 24,
		"fans": 1200,
		"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
		"material_instance": {"definition_id": String(MATERIAL_ID)},
	}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(_active_plan, CATALOG, BALANCE)
	_active_show.clear()
	_generator = GENERATOR_SCRIPT.new()
	_generator.llm_enabled = true
	_generator.summary_enabled = true
	add_child(_generator)
	_generator.setup(_active_plan, result, CATALOG, persona.model)
	_generator.show_ready.connect(_on_show_ready)
	_generator.summary_ready.connect(_on_summary_ready)
	_generator.generation_failed.connect(_on_generation_failed)
	print("LAB_LIVE_HISTORY_CASE_START index=%d existing_records=%d" % [
		_case_index + 1,
		_history_store.get_recent_records_for_persona(PERSONA_ID, 3).size(),
	])
	_generator.generate()


func _on_show_ready(show: Dictionary) -> void:
	_active_show = show
	print("LAB_LIVE_HISTORY_SHOW index=%d title=%s dsl=%s" % [
		_case_index + 1,
		str(show.get("title", "")),
		JSON.stringify(str(show.get("dsl_text", ""))),
	])


func _on_summary_ready(_session_id: StringName, summary: String) -> void:
	if summary.strip_edges().is_empty() or _active_show.is_empty():
		print("LAB_LIVE_HISTORY_ALL_DONE ok=0 error=empty_summary index=%d" % (_case_index + 1))
		return
	var record := StreamSessionRecord.new()
	record.session_id = String(_active_plan.session_id)
	record.day = _case_index + 1
	record.title = str(_active_show.get("title", ""))
	record.persona_id = PERSONA_ID
	record.persona_name = CATALOG.get_persona(PERSONA_ID).display_name
	record.material_name = CATALOG.get_material(MATERIAL_ID).display_name
	record.summary = summary
	if not _history_store.add_record(record):
		print("LAB_LIVE_HISTORY_ALL_DONE ok=0 error=history_store_failed index=%d" % (_case_index + 1))
		return
	print("LAB_LIVE_HISTORY_SUMMARY index=%d text=%s" % [
		_case_index + 1,
		JSON.stringify(summary),
	])
	_finish_case()


func _on_generation_failed(reason: String) -> void:
	print("LAB_LIVE_HISTORY_ALL_DONE ok=0 error=generation_failed index=%d reason=%s" % [
		_case_index + 1,
		reason,
	])


func _finish_case() -> void:
	if _generator != null:
		_generator.queue_free()
		_generator = null
	_active_plan = null
	_active_show.clear()
	_case_index += 1
	call_deferred("_start_case")
