extends Node
## 真实 LLM 对照实验：固定素材与人设，比较技能等级和直播构思是否产生可接受的剧情差异。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const LIVE_SHOW_GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")

const MATERIAL_ID: StringName = &"material_trash_hunter"
const PERSONA_ID: StringName = &"persona_default"
const APPROACHES: Dictionary = {
	"analysis": {
		"approach_id": "lab_analysis",
		"approach_type": "analysis",
		"display_name": "把离谱判定拆明白",
		"display_description": "边玩边验证传闻，把最离谱的判定和机制讲清楚。",
		"director_prompt": "围绕一个具体的离谱判定展开验证。主播先提出判断，通过多次有差异的尝试缩小规则范围，最终得到足够明确的结论并用游戏内结果收束。",
	},
	"challenge": {
		"approach_id": "lab_challenge",
		"approach_type": "challenge",
		"display_name": "今晚必须过瞬移老板",
		"display_description": "立下通关目标，让每次失败都变成下一次尝试的依据。",
		"director_prompt": "开场明确要击败会瞬移的首领。每次受挫都必须促成具体策略变化，不绕去做教程或长篇设定讨论；成功或主动放弃时立刻接住结果收尾。",
	},
}
const CASES: Array[Dictionary] = [
	{"case_id": "analysis_lv1", "game_level": 1, "approach": "analysis"},
	{"case_id": "analysis_lv5", "game_level": 5, "approach": "analysis"},
	{"case_id": "challenge_lv5", "game_level": 5, "approach": "challenge"},
]

var _case_index: int = 0
var _active_generator: Node = null
var _success_count: int = 0
var _failure_count: int = 0


func _ready() -> void:
	call_deferred("_start_next_case")


func _start_next_case() -> void:
	if _case_index >= CASES.size():
		print("LAB_APPROACH_SKILL_ALL_DONE ok=%d success=%d failed=%d" % [
			int(_failure_count == 0), _success_count, _failure_count,
		])
		return
	var case_data: Dictionary = CASES[_case_index]
	var material: LiveStreamMaterialResource = CATALOG.get_material(MATERIAL_ID)
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	var plan := StreamPlanSnapshot.new()
	plan.session_id = StringName("lab_approach_skill_%s" % str(case_data.get("case_id", "")))
	plan.title = material.display_name
	plan.persona_id = PERSONA_ID
	plan.material_instance_id = &"lab_material_instance"
	plan.approach = (APPROACHES[str(case_data.get("approach", ""))] as Dictionary).duplicate(true)
	plan.rng_seed = 20260812
	plan.state_snapshot = _make_snapshot(int(case_data.get("game_level", 1)))
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, CATALOG, BALANCE)
	_active_generator = LIVE_SHOW_GENERATOR_SCRIPT.new()
	_active_generator.summary_enabled = false
	add_child(_active_generator)
	_active_generator.setup(plan, result, CATALOG, persona.model)
	_active_generator.show_ready.connect(_on_case_ready.bind(case_data))
	_active_generator.generation_failed.connect(_on_case_failed.bind(case_data))
	print("LAB_APPROACH_SKILL_START case=%s approach=%s game_lv=%d" % [
		str(case_data.get("case_id", "")), str(case_data.get("approach", "")), int(case_data.get("game_level", 1)),
	])
	_active_generator.generate()


func _make_snapshot(game_level: int) -> Dictionary:
	return {
		"skill_levels": {"game": game_level, "talk": 2, "song": 1, "act": 1, "tech": 1},
		"stress": 20,
		"otaku_desire": 40,
		"loneliness": 30,
		"fans": 1200,
		"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
		"material_instance": {"definition_id": String(MATERIAL_ID)},
	}


func _on_case_ready(show: Dictionary, case_data: Dictionary) -> void:
	_success_count += 1
	print("LAB_APPROACH_SKILL_RESULT case=%s title=%s dsl=%s" % [
		str(case_data.get("case_id", "")), str(show.get("title", "")), JSON.stringify(str(show.get("dsl_text", ""))),
	])
	_finish_case()


func _on_case_failed(reason: String, case_data: Dictionary) -> void:
	_failure_count += 1
	print("LAB_APPROACH_SKILL_FAILED case=%s reason=%s" % [str(case_data.get("case_id", "")), reason])
	_finish_case()


func _finish_case() -> void:
	if _active_generator != null:
		_active_generator.queue_free()
		_active_generator = null
	_case_index += 1
	call_deferred("_start_next_case")
