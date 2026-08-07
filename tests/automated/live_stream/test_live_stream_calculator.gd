extends Node
## 纯结算器的位置接口、空槽透传、商单收益与固定 seed 契约。


func _ready() -> void:
	var catalog := LiveStreamCatalog.new()
	var balance := LiveStreamBalance.new()
	var material := _make_material()
	var persona := StreamPersonaResource.new()
	persona.content_id = &"persona_test"
	persona.display_name = "测试人设"
	persona.base_performance_multiplier = 1.0
	var opening_a: BehaviorCardResource = _make_card(&"opening_a", [], [1, 3], 0.0)
	var opening_one: BehaviorCardResource = _make_card(&"opening_one", [], [1], 0.0)
	var full_fill: BehaviorCardResource = _make_card(&"full", [1, 3], [], 10.0)
	var half_fill: BehaviorCardResource = _make_card(&"half", [1, 2], [], 10.0)
	var partial_fill: BehaviorCardResource = _make_card(&"partial", [1, 2, 3], [], 10.0)
	var empty_fill: BehaviorCardResource = _make_card(&"empty", [2, 4], [], 10.0)
	catalog.behavior_cards = [opening_a, opening_one, full_fill, half_fill, partial_fill, empty_fill]
	catalog.modifier_cards = [_make_seamless_modifier()]
	catalog.materials = [material]
	catalog.personas = [persona]

	var calculator := LiveStreamCalculator.new()
	var full_result: StreamSettlementResult = calculator.calculate(_make_plan(&"opening_a", &"full", 1), catalog, balance)
	var full_repeat: StreamSettlementResult = calculator.calculate(_make_plan(&"opening_a", &"full", 1), catalog, balance)
	assert(full_result.to_dict() == full_repeat.to_dict(), "fixed seed must be deterministic")
	assert(is_equal_approx(float(full_result.axes.get("quality")), 13.2), "full fill and full-chain reward must both apply")
	assert(is_equal_approx(float((full_result.interface_trace[1] as Dictionary).get("fill_ratio")), 1.0))
	assert((full_result.interface_trace[1] as Dictionary).get("connected_slots") == [1, 3])

	var half_result: StreamSettlementResult = calculator.calculate(_make_plan(&"opening_one", &"half", 1), catalog, balance)
	assert(is_equal_approx(float(half_result.axes.get("quality")), 10.0), "half-filled two-slot cards keep normal power")

	var partial_result: StreamSettlementResult = calculator.calculate(_make_plan(&"opening_one", &"partial", 1), catalog, balance)
	assert(is_equal_approx(float(partial_result.axes.get("quality")), 10.8), "three-slot width bonus and partial-fill penalty must stack")

	var empty_result: StreamSettlementResult = calculator.calculate(_make_plan(&"opening_one", &"empty", 1), catalog, balance)
	assert(is_equal_approx(float(empty_result.axes.get("quality")), 8.0), "empty fill must reduce the following card to 0.8 power")
	assert(is_equal_approx(float(empty_result.axes.get("risk")), 1.0), "empty fill must add ten percent risk in axis units")
	var seamless_result: StreamSettlementResult = calculator.calculate(
		_make_plan(&"opening_one", &"empty", 1, [&"seamless"]),
		catalog,
		balance
	)
	assert(is_equal_approx(float(seamless_result.axes.get("quality")), 9.0), "seamless transition must raise empty fill to partial power")
	assert(is_equal_approx(float(seamless_result.axes.get("risk")), 0.5), "seamless transition must halve empty-fill risk")

	var rescued_result: StreamSettlementResult = calculator.calculate(_make_plan(&"opening_one", &"empty", 3), catalog, balance)
	assert(is_equal_approx(float(rescued_result.axes.get("quality")), 13.0), "talk Lv3 should rescue the first empty fill before applying its skill bonus")
	assert(is_zero_approx(float(rescued_result.axes.get("risk"))))

	var sparse_plan: StreamPlanSnapshot = _make_plan(&"opening_a", &"full", 1)
	sparse_plan.behavior_card_ids = [&"opening_a", &"", &"full"]
	var sparse_result: StreamSettlementResult = calculator.calculate(sparse_plan, catalog, balance)
	assert(is_equal_approx(float(sparse_result.axes.get("quality")), float(full_result.axes.get("quality"))), "empty slots must be transparent to seam calculation")
	assert(sparse_result.peak_viewers < full_result.peak_viewers, "each empty program slot must reduce the base audience")
	assert((sparse_result.interface_trace[1] as Dictionary).get("slot_index") == 2)

	var sponsor: LiveStreamMaterialResource = _make_material()
	sponsor.content_id = &"material_sponsor"
	sponsor.material_type = LiveStreamMaterialResource.TYPE_SPONSOR
	sponsor.sponsor_terms = MaterialSponsorTerms.new()
	sponsor.sponsor_terms.guaranteed_money = 3000
	sponsor.sponsor_terms.quality_floor = 100.0
	sponsor.sponsor_terms.failure_payout_multiplier = 0.5
	catalog.materials.append(sponsor)
	var sponsor_plan: StreamPlanSnapshot = _make_plan(&"opening_a", &"full", 1)
	(sponsor_plan.state_snapshot["material_instance"] as Dictionary)["definition_id"] = "material_sponsor"
	var sponsor_result: StreamSettlementResult = calculator.calculate(sponsor_plan, catalog, balance)
	assert(not sponsor_result.sponsor_satisfied)
	assert(sponsor_result.sponsor_payout == 1500, "failed sponsor satisfaction must discount only its guaranteed payout")
	print("LIVE_STREAM_CALCULATOR_TEST_PASS")


func _make_card(card_id: StringName, left_slots: Array, right_slots: Array, quality: float) -> BehaviorCardResource:
	var card := BehaviorCardResource.new()
	card.content_id = card_id
	card.display_name = String(card_id)
	card.family = &"talk"
	card.left_slots.assign(left_slots)
	card.right_slots.assign(right_slots)
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


func _make_seamless_modifier() -> ModifierCardResource:
	var modifier := ModifierCardResource.new()
	modifier.content_id = &"seamless"
	modifier.display_name = "无缝转场"
	modifier.family = &"tech"
	modifier.axis_multiplier_bonus = StreamAxisValues.new()
	var effect := StreamSpecialEffect.new()
	effect.effect_id = &"seam_penalty_half"
	modifier.special_effects.append(effect)
	return modifier


func _make_plan(
	opening_card_id: StringName,
	second_card_id: StringName,
	talk_level: int,
	modifier_ids: Array[StringName] = []
) -> StreamPlanSnapshot:
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"calculator_test"
	plan.persona_id = &"persona_test"
	plan.material_instance_id = &"material_instance_test"
	plan.behavior_card_ids = [opening_card_id, second_card_id]
	plan.modifier_card_ids.assign(modifier_ids)
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
