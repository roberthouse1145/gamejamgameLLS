extends Node
## 质量验收 lab：预置素材卡与事件卡，真实 LLM 生成整场直播 DSL，生成成功后自动打开直播姬播放，供人工检查效果。
## 修改配置只需改 MATERIAL_ID / CARD_IDS / SNAPSHOT 三处。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const LIVE_SHOW_GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")
const OBS_APP_PATH: String = "res://resources/apps/obs_live_app.tres"

## 预置素材卡（content_id）。
const MATERIAL_ID: StringName = &"material_cozy_game"
## 预置事件卡（行为卡）节目单，按演出顺序。
const CARD_IDS: Array[StringName] = [&"talk_daily_greeting", &"game_hardcore_guide", &"game_clear_reflection"]
## 预置主播状态快照。
const SNAPSHOT: Dictionary = {
	"skill_levels": {"game": 2, "talk": 2, "song": 1, "act": 1, "tech": 1},
	"stress": 30,
	"otaku_desire": 50,
	"loneliness": 40,
	"fans": 1200,
	"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
}

var _generator: Node = null
var _done: bool = false
var _plan: StreamPlanSnapshot = null
var _result: StreamSettlementResult = null
var _model: StreamerModelResource = null


func _ready() -> void:
	var material: LiveStreamMaterialResource = CATALOG.get_material(MATERIAL_ID)
	if material == null:
		print("LAB_SHOW_QUALITY_DONE ok=0 error=missing_material id=%s" % MATERIAL_ID)
		return
	var card_ids: Array[StringName] = []
	for card_id: StringName in CARD_IDS:
		if CATALOG.get_card(card_id) == null:
			print("LAB_SHOW_QUALITY_DONE ok=0 error=missing_card id=%s" % card_id)
			return
		card_ids.append(card_id)
	var persona: StreamPersonaResource = CATALOG.get_persona(&"persona_default")
	if persona == null:
		print("LAB_SHOW_QUALITY_DONE ok=0 error=missing_persona")
		return
	_plan = StreamPlanSnapshot.new()
	_plan.session_id = &"lab_show_quality"
	_plan.title = material.display_name
	_plan.persona_id = persona.content_id
	_plan.behavior_card_ids = card_ids
	_plan.rng_seed = 20260809
	_plan.state_snapshot = SNAPSHOT.duplicate(true)
	_plan.state_snapshot["material_instance"] = {"definition_id": String(MATERIAL_ID)}
	_result = LiveStreamCalculator.new().calculate(_plan, CATALOG, BALANCE)
	_model = persona.model
	_generator = LIVE_SHOW_GENERATOR_SCRIPT.new()
	_generator.llm_enabled = true
	add_child(_generator)
	_generator.setup(_plan, _result, CATALOG, _model)
	_generator.show_ready.connect(_on_ready)
	_generator.generation_failed.connect(_on_failed)
	print("LAB_SHOW_QUALITY_START material=%s cards=%s" % [MATERIAL_ID, CARD_IDS])
	_generator.generate()


func _on_ready(show: Dictionary) -> void:
	if _done:
		return
	_done = true
	var dsl_text: String = str(show.get("dsl_text", ""))
	var ops: Array = show.get("ops", [])
	print("LAB_SHOW_QUALITY_RESULT title=%s ops=%d dsl_len=%d" % [
		str(show.get("title", "")),
		ops.size(),
		dsl_text.length(),
	])
	print("LAB_SHOW_QUALITY_DSL\n%s" % dsl_text)
	_play_in_live_app(dsl_text)
	print("LAB_SHOW_QUALITY_DONE ok=1")


func _on_failed(reason: String) -> void:
	if _done:
		return
	_done = true
	print("LAB_SHOW_QUALITY_DONE ok=0 reason=%s" % reason)


## 打开直播姬并直接播放生成的 DSL，供人工检查演出效果。
func _play_in_live_app(dsl_text: String) -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		print("LAB_SHOW_QUALITY_PLAY skipped=no_app_manager")
		return
	if not bool(app_manager.is_app_registered("obs_live")):
		app_manager.install_app_from_path(OBS_APP_PATH)
	var window: Control = app_manager.launch_app("obs_live", true)
	if window == null:
		print("LAB_SHOW_QUALITY_PLAY skipped=launch_failed")
		return
	var app: Control = window.get("content") as Control
	if app == null or not app.has_method("play_test_show"):
		print("LAB_SHOW_QUALITY_PLAY skipped=bad_app")
		return
	var ok: bool = bool(app.play_test_show(dsl_text, _plan, _result))
	print("LAB_SHOW_QUALITY_PLAY ok=%s" % ok)
