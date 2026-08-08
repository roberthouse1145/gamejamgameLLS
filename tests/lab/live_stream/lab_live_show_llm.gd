extends Node
## 真实 LLM 一次性生成整场直播 DSL，打印全文与校验结果。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const LIVE_SHOW_GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")

var _generator: Node = null
var _done: bool = false


func _ready() -> void:
	var opening: BehaviorCardResource = _find_card(true)
	var middle: BehaviorCardResource = _find_card(false)
	if opening == null or middle == null:
		print("LAB_LIVE_SHOW_DONE error=missing_cards")
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"lab_live_show"
	plan.title = "【联调】一次性直播 DSL"
	plan.persona_id = CATALOG.personas[0].content_id if not CATALOG.personas.is_empty() else &""
	plan.behavior_card_ids = [opening.content_id, middle.content_id]
	plan.rng_seed = 20260807
	plan.state_snapshot = {
		"skill_levels": {"game": 1, "talk": 2, "song": 1, "act": 1, "tech": 1},
		"stress": 45,
		"otaku_desire": 60,
		"loneliness": 30,
		"fans": 1200,
		"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
		"material_instance": {
			"definition_id": String(CATALOG.materials[0].content_id) if not CATALOG.materials.is_empty() else "",
			"depth": 4.0,
			"freshness": 1.0,
		},
	}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, CATALOG, BALANCE)
	_generator = LIVE_SHOW_GENERATOR_SCRIPT.new()
	_generator.llm_enabled = true
	add_child(_generator)
	_generator.setup(plan, result, CATALOG, CATALOG.personas[0].model)
	_generator.show_ready.connect(_on_ready)
	_generator.generation_failed.connect(_on_failed)
	print("LAB_LIVE_SHOW_START")
	_generator.generate()


func _on_ready(show: Dictionary) -> void:
	if _done:
		return
	_done = true
	var dsl_text: String = str(show.get("dsl_text", ""))
	var ops: Array = show.get("ops", [])
	print("LAB_LIVE_SHOW_RESULT title=%s ops=%d dsl_len=%d" % [
		str(show.get("title", "")),
		ops.size(),
		dsl_text.length(),
	])
	print("LAB_LIVE_SHOW_DSL\n%s" % dsl_text)
	print("LAB_LIVE_SHOW_DONE ok=1")


func _on_failed(reason: String) -> void:
	if _done:
		return
	_done = true
	print("LAB_LIVE_SHOW_DONE ok=0 reason=%s" % reason)


func _find_card(want_opening: bool) -> BehaviorCardResource:
	for card: BehaviorCardResource in CATALOG.behavior_cards:
		if card == null:
			continue
		if want_opening and card.is_opening_card():
			return card
		if not want_opening and not card.is_opening_card() and not card.is_closing_card():
			return card
	return null
