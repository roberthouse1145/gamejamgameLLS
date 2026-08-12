extends Node
## 真实 LLM repair 实验：注入一个非法表情，验证工具 patch 后能直接抵达 show_ready。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")
const PERSONA_ID: StringName = &"persona_default"
const MATERIAL_ID: StringName = &"material_forum_hot_meme"
const INVALID_DSL: String = """expression: euphoric
say: 晚上好，今天测试一下修复链路。
chat: 修好了吗 | 主播收到啦"""

var _generator: LiveShowGenerator = null
var _started_msec: int = 0


func _ready() -> void:
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	if persona == null or persona.model == null:
		print("LAB_LIVE_DSL_REPAIR_DONE ok=0 error=missing_persona_model")
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"lab_live_dsl_repair"
	plan.title = "直播 repair 实验"
	plan.persona_id = PERSONA_ID
	plan.state_snapshot = {
		"fans": 1200,
		"stress": 20,
		"otaku_desire": 40,
		"loneliness": 30,
		"skill_levels": {"game": 1, "talk": 2, "song": 1, "act": 1, "tech": 1},
		"material_instance": {"definition_id": String(MATERIAL_ID)},
	}

	_generator = GENERATOR_SCRIPT.new()
	_generator.summary_enabled = false
	add_child(_generator)
	_generator.setup(plan, null, CATALOG, persona.model)
	_generator.show_ready.connect(_on_show_ready)
	_generator.generation_failed.connect(_on_generation_failed)
	if not _generator._ensure_llm():
		print("LAB_LIVE_DSL_REPAIR_DONE ok=0 error=llm_unavailable")
		return

	var validation: Dictionary = _generator.compile_dsl(INVALID_DSL)
	if bool(validation.get("success", false)):
		print("LAB_LIVE_DSL_REPAIR_DONE ok=0 error=fixture_should_be_invalid")
		return
	_generator.set("_attempt", 2)
	var full_prompt_chars: int = _generator._build_prompt().length()
	_started_msec = Time.get_ticks_msec()
	if not _generator._start_repair(INVALID_DSL, validation.get("errors", [])):
		print("LAB_LIVE_DSL_REPAIR_DONE ok=0 error=repair_unavailable")
		return
	var repair_agent: LiveDSLRepairAgent = _generator.get("_repair_agent") as LiveDSLRepairAgent
	var metrics: Dictionary = repair_agent.get_last_prompt_metrics() if repair_agent != null else {}
	print("LAB_LIVE_DSL_REPAIR_START full_prompt_chars=%d repair_prompt_chars=%d dsl_chars=%d errors=%s" % [
		full_prompt_chars,
		int(metrics.get("total_chars", 0)),
		INVALID_DSL.length(),
		JSON.stringify(validation.get("errors", [])),
	])


func _on_show_ready(show: Dictionary) -> void:
	var repaired_dsl: String = str(show.get("dsl_text", ""))
	var elapsed: float = float(Time.get_ticks_msec() - _started_msec) / 1000.0
	var body_preserved: bool = "say: 晚上好，今天测试一下修复链路。" in repaired_dsl \
		and "chat: 修好了吗 | 主播收到啦" in repaired_dsl
	print("LAB_LIVE_DSL_REPAIR_RESULT ok=1 delivered=1 body_preserved=%d ops=%d elapsed=%.2fs dsl=%s" % [
		int(body_preserved),
		(show.get("ops", []) as Array).size(),
		elapsed,
		JSON.stringify(repaired_dsl),
	])


func _on_generation_failed(reason: String) -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _started_msec) / 1000.0
	print("LAB_LIVE_DSL_REPAIR_RESULT ok=0 delivered=0 reason=%s elapsed=%.2fs" % [reason, elapsed])
