extends Node
## 真实 LLM 人设对照 lab：相同素材与构思分别使用两种主播人设，比较表达与弹幕表现。

const CATALOG_SOURCE: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const LIVE_SHOW_GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")

const MATERIAL_ID: StringName = &"material_forum_hot_meme"
const PERSONA_IDS: Array[StringName] = [&"persona_default", &"persona_lab_little_devil"]
const SNAPSHOT: Dictionary = {
	"skill_levels": {"game": 2, "talk": 2, "song": 1, "act": 1, "tech": 1},
	"stress": 30,
	"otaku_desire": 50,
	"loneliness": 40,
	"fans": 1200,
	"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
}

var _catalog: LiveStreamCatalog = null
var _case_index: int = 0
var _active_generator: Node = null
var _case_started_msec: int = 0
var _lab_started_msec: int = 0
var _result_by_persona: Dictionary = {}
var _failed_case_count: int = 0


func _ready() -> void:
	_catalog = _build_lab_catalog()
	if _catalog == null or _catalog.get_material(MATERIAL_ID) == null:
		print("LAB_LIVE_SHOW_DONE ok=0 error=invalid_catalog")
		return
	_lab_started_msec = Time.get_ticks_msec()
	call_deferred("_start_next_case")


func _build_lab_catalog() -> LiveStreamCatalog:
	var catalog: LiveStreamCatalog = CATALOG_SOURCE.duplicate(true) as LiveStreamCatalog
	if catalog == null:
		return null
	var base_persona: StreamPersonaResource = catalog.get_persona(&"persona_default")
	if base_persona == null:
		return null
	var little_devil: StreamPersonaResource = base_persona.duplicate(true) as StreamPersonaResource
	little_devil.content_id = &"persona_lab_little_devil"
	little_devil.display_name = "莓菲"
	little_devil.channel_name = "莓菲的杂鱼观察室"
	little_devil.description = "把挑衅、赌局和观众反杀做成互动节奏的小恶魔系主播。"
	little_devil.prompt_fragment = "{{live_stream/personas/little_devil}}"
	var personas: Array[StreamPersonaResource] = []
	personas.append(base_persona)
	personas.append(little_devil)
	catalog.personas = personas
	return catalog


func _start_next_case() -> void:
	if _case_index >= PERSONA_IDS.size():
		var total_seconds: float = float(Time.get_ticks_msec() - _lab_started_msec) / 1000.0
		for persona_id: StringName in PERSONA_IDS:
			if not _result_by_persona.has(String(persona_id)):
				continue
			var case_result: Dictionary = _result_by_persona.get(String(persona_id), {})
			print("LAB_LIVE_SHOW_FINAL persona=%s title=%s elapsed=%.2fs dsl=%s" % [
				persona_id,
				str(case_result.get("title", "")),
				float(case_result.get("elapsed", 0.0)),
				JSON.stringify(str(case_result.get("dsl", ""))),
			])
		print("LAB_LIVE_SHOW_ALL_DONE ok=%d failed=%d elapsed=%.2fs" % [
			int(_failed_case_count == 0),
			_failed_case_count,
			total_seconds,
		])
		return
	var persona_id: StringName = PERSONA_IDS[_case_index]
	var persona: StreamPersonaResource = _catalog.get_persona(persona_id)
	var material: LiveStreamMaterialResource = _catalog.get_material(MATERIAL_ID)
	if persona == null or material == null:
		print("LAB_LIVE_SHOW_DONE ok=0 persona=%s error=missing_content" % persona_id)
		return

	var plan := StreamPlanSnapshot.new()
	plan.session_id = StringName("lab_live_show_%s" % persona_id)
	plan.title = material.display_name
	plan.persona_id = persona_id
	plan.approach = {"approach_id": "forum_audience", "approach_type": "audience_interaction", "display_name": "让弹幕站队审案", "display_description": "一边翻上下文，一边让观众站队。", "director_prompt": "尽早让弹幕围绕截屏中的矛盾说法站队，并让多数意见改变主播接下来验证哪条线索。"}
	plan.rng_seed = 20260811
	plan.state_snapshot = SNAPSHOT.duplicate(true)
	plan.state_snapshot["material_instance"] = {"definition_id": String(MATERIAL_ID)}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, _catalog, BALANCE)

	_active_generator = LIVE_SHOW_GENERATOR_SCRIPT.new()
	_active_generator.llm_enabled = true
	_active_generator.summary_enabled = false
	add_child(_active_generator)
	_active_generator.setup(plan, result, _catalog, persona.model)
	_active_generator.show_ready.connect(_on_case_ready.bind(String(persona_id)))
	_active_generator.generation_failed.connect(_on_case_failed.bind(String(persona_id)))
	_case_started_msec = Time.get_ticks_msec()
	print("LAB_LIVE_SHOW_START persona=%s material=%s approach=audience_interaction" % [persona_id, MATERIAL_ID])
	_active_generator.generate()


func _on_case_ready(show: Dictionary, persona_id: String) -> void:
	var dsl_text: String = str(show.get("dsl_text", ""))
	var ops: Array = show.get("ops", [])
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _case_started_msec) / 1000.0
	_result_by_persona[persona_id] = {
		"title": str(show.get("title", "")),
		"dsl": dsl_text,
		"elapsed": elapsed_seconds,
	}
	print("LAB_LIVE_SHOW_RESULT persona=%s title=%s ops=%d dsl_len=%d elapsed=%.2fs" % [
		persona_id,
		str(show.get("title", "")),
		ops.size(),
		dsl_text.length(),
		elapsed_seconds,
	])
	print("LAB_LIVE_SHOW_DSL_JSON persona=%s dsl=%s" % [persona_id, JSON.stringify(dsl_text)])
	_finish_case()


func _on_case_failed(reason: String, persona_id: String) -> void:
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _case_started_msec) / 1000.0
	_failed_case_count += 1
	print("LAB_LIVE_SHOW_DONE ok=0 persona=%s reason=%s elapsed=%.2fs" % [persona_id, reason, elapsed_seconds])
	_finish_case()


func _finish_case() -> void:
	if _active_generator != null:
		_active_generator.queue_free()
		_active_generator = null
	_case_index += 1
	call_deferred("_start_next_case")
