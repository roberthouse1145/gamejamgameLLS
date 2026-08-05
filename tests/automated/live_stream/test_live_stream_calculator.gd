extends Node
## 纯结算器的接缝、技能钩子、修饰卡与固定 seed 契约。


func _ready() -> void:
	var catalog := LiveStreamCatalog.new()
	var balance := LiveStreamBalance.new()
	var material := _make_material()
	var persona := StreamPersonaResource.new()
	persona.content_id = &"persona_test"
	persona.display_name = "测试人设"
	persona.base_performance_multiplier = 1.0
	var multi_opening: BehaviorCardResource = _make_card(&"multi_opening", [], [&"hot", &"warm"], 0.0)
	var hot_opening: BehaviorCardResource = _make_card(&"hot_opening", [], [&"hot"], 0.0)
	var same_seam: BehaviorCardResource = _make_card(&"same", [&"calm", &"warm"], [&"gloom"], 10.0)
	var conflict_seam: BehaviorCardResource = _make_card(&"conflict", [&"gloom"], [&"warm"], 10.0)
	var mixed_seam: BehaviorCardResource = _make_card(&"mixed", [&"gloom", &"calm"], [&"warm"], 10.0)
	catalog.behavior_cards = [multi_opening, hot_opening, same_seam, conflict_seam, mixed_seam]
	catalog.materials = [material]
	catalog.personas = [persona]

	var calculator := LiveStreamCalculator.new()
	var perfect_plan: StreamPlanSnapshot = _make_plan(&"multi_opening", &"same", 1)
	var perfect_result: StreamSettlementResult = calculator.calculate(perfect_plan, catalog, balance)
	var perfect_repeat: StreamSettlementResult = calculator.calculate(perfect_plan, catalog, balance)
	assert(perfect_result.to_dict() == perfect_repeat.to_dict(), "fixed seed must be deterministic")
	assert(is_equal_approx(float(perfect_result.axes.get("quality")), 12.0), "same-color seam should multiply the following card by 1.2")
	assert((perfect_result.mood_flow[0] as Dictionary).get("outputs") == ["hot", "warm"])
	assert((perfect_result.mood_flow[1] as Dictionary).get("inputs") == ["calm", "warm"], "settlement must preserve every authored connector")

	var conflict_plan: StreamPlanSnapshot = _make_plan(&"hot_opening", &"conflict", 1)
	var conflict_result: StreamSettlementResult = calculator.calculate(conflict_plan, catalog, balance)
	assert(is_equal_approx(float(conflict_result.axes.get("quality")), 8.0), "hot-to-gloom conflict should multiply the following card by 0.8")
	assert(is_equal_approx(float(conflict_result.axes.get("risk")), 1.5), "conflict risk bonus should be applied once")
	var mixed_plan: StreamPlanSnapshot = _make_plan(&"hot_opening", &"mixed", 1)
	var mixed_result: StreamSettlementResult = calculator.calculate(mixed_plan, catalog, balance)
	assert(is_equal_approx(float(mixed_result.axes.get("quality")), 10.0), "one compatible option must prevent a multi-slot seam from being treated as an unavoidable conflict")
	assert(is_zero_approx(float(mixed_result.axes.get("risk"))))

	var rescued_plan: StreamPlanSnapshot = _make_plan(&"hot_opening", &"conflict", 3)
	var rescued_result: StreamSettlementResult = calculator.calculate(rescued_plan, catalog, balance)
	assert(is_zero_approx(float(rescued_result.axes.get("risk"))), "talk Lv3 should rescue the first conflict seam")
	assert(float(rescued_result.axes.get("quality")) > float(conflict_result.axes.get("quality")))
	print("LIVE_STREAM_CALCULATOR_TEST_PASS")


func _make_card(card_id: StringName, mood_inputs: Array, mood_outputs: Array, quality: float) -> BehaviorCardResource:
	var card := BehaviorCardResource.new()
	card.content_id = card_id
	card.display_name = String(card_id)
	card.family = &"talk"
	card.mood_inputs.assign(mood_inputs)
	card.mood_outputs.assign(mood_outputs)
	card.axes = StreamAxisValues.new()
	card.axes.quality = quality
	return card


func _make_material() -> LiveStreamMaterialResource:
	var material := LiveStreamMaterialResource.new()
	material.content_id = &"material_test"
	material.display_name = "测试素材"
	material.material_type = LiveStreamMaterialResource.TYPE_CONTINUOUS
	material.initial_depth = 4.0
	material.affinity = StreamFamilyValues.new()
	material.axes = StreamAxisValues.new()
	material.base_popularity = 100.0
	return material


func _make_plan(opening_card_id: StringName, second_card_id: StringName, talk_level: int) -> StreamPlanSnapshot:
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"calculator_test"
	plan.persona_id = &"persona_test"
	plan.material_instance_id = &"material_instance_test"
	plan.behavior_card_ids = [opening_card_id, second_card_id]
	plan.rng_seed = 314159
	plan.state_snapshot = {
		"skill_levels": {"game": 1, "talk": talk_level, "song": 1, "act": 1, "tech": 1},
		"stress": 0,
		"otaku_desire": 0,
		"loneliness": 0,
		"fans": 0,
		"fan_vector": {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0},
		"material_instance": {
			"definition_id": "material_test",
			"depth": 4.0,
			"freshness": 1.0,
		},
	}
	return plan
