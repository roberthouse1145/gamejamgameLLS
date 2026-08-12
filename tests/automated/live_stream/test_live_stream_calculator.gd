extends Node
## 固定直播构思类型、能力倍率、素材熟练度奖励与赞助结算契约。


func _ready() -> void:
	var catalog := LiveStreamCatalog.new()
	var balance := LiveStreamBalance.new()
	var material := _make_material()
	var persona := StreamPersonaResource.new()
	persona.content_id = &"persona_test"
	persona.display_name = "测试人设"
	catalog.materials = [material]
	catalog.personas = [persona]

	var calculator := LiveStreamCalculator.new()
	var analysis_plan: StreamPlanSnapshot = _make_plan(&"analysis", 1)
	var analysis_result: StreamSettlementResult = calculator.calculate(analysis_plan, catalog, balance)
	var repeat_result: StreamSettlementResult = calculator.calculate(analysis_plan, catalog, balance)
	assert(analysis_result.to_dict() == repeat_result.to_dict(), "fixed snapshot must be deterministic")
	assert(not analysis_result.axes.has("risk"), "settlement axes must not expose a removed risk axis")
	assert(analysis_result.skill_exp_gains == material.skill_exp_rewards.to_dict())
	assert(analysis_result.streamer_exp_gain == material.skill_exp_rewards.get_total())

	var skilled_result: StreamSettlementResult = calculator.calculate(
		_make_plan(&"analysis", 4), catalog, balance
	)
	assert(float(skilled_result.axes.get("quality")) > float(analysis_result.axes.get("quality")))

	var challenge_result: StreamSettlementResult = calculator.calculate(
		_make_plan(&"challenge", 1), catalog, balance
	)
	assert(float(challenge_result.axes.get("hook")) > float(analysis_result.axes.get("hook")))
	assert(challenge_result.stress_delta > analysis_result.stress_delta)

	var interaction_result: StreamSettlementResult = calculator.calculate(
		_make_plan(&"audience_interaction", 1), catalog, balance
	)
	assert(float(interaction_result.axes.get("impact")) > float(analysis_result.axes.get("impact")))

	var invalid_result: StreamSettlementResult = calculator.calculate(
		_make_plan(&"unknown", 1), catalog, balance
	)
	assert(invalid_result.peak_viewers == 0, "unknown approach types must not silently gain a default profile")

	var sponsor: LiveStreamMaterialResource = _make_material()
	sponsor.content_id = &"material_sponsor"
	sponsor.material_type = LiveStreamMaterialResource.TYPE_SPONSOR
	sponsor.sponsor_terms = MaterialSponsorTerms.new()
	sponsor.sponsor_terms.guaranteed_money = 3000
	sponsor.sponsor_terms.quality_floor = 100.0
	sponsor.sponsor_terms.failure_payout_multiplier = 0.5
	catalog.materials.append(sponsor)
	var sponsor_plan: StreamPlanSnapshot = _make_plan(&"analysis", 1)
	(sponsor_plan.state_snapshot["material_instance"] as Dictionary)["definition_id"] = "material_sponsor"
	var sponsor_result: StreamSettlementResult = calculator.calculate(sponsor_plan, catalog, balance)
	assert(not sponsor_result.sponsor_satisfied)
	assert(sponsor_result.sponsor_payout == 1500)
	print("LIVE_STREAM_CALCULATOR_TEST_PASS")


func _make_material() -> LiveStreamMaterialResource:
	var material := LiveStreamMaterialResource.new()
	material.content_id = &"material_test"
	material.display_name = "测试素材"
	material.material_type = LiveStreamMaterialResource.TYPE_CONSUMABLE
	material.activities = [&"discuss"]
	material.skill_exp_rewards = StreamSkillExperience.new()
	material.skill_exp_rewards.talk = 60
	material.affinity = StreamFamilyValues.new()
	material.axes = StreamAxisValues.new()
	material.base_popularity = 100.0
	return material


func _make_plan(approach_type: StringName, talk_level: int) -> StreamPlanSnapshot:
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"calculator_test"
	plan.persona_id = &"persona_test"
	plan.material_instance_id = &"material_instance_test"
	plan.approach = {
		"approach_id": "test_%s" % String(approach_type),
		"approach_type": String(approach_type),
		"display_name": "测试构思",
		"display_description": "测试说明",
		"director_prompt": "围绕测试素材完成一场直播。",
	}
	plan.rng_seed = 314159
	plan.state_snapshot = {
		"skill_levels": {"game": 1, "talk": talk_level, "song": 1, "act": 1, "tech": 1},
		"stress": 0,
		"otaku_desire": 0,
		"loneliness": 0,
		"fans": 0,
		"fan_vector": {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0},
		"material_instance": {"definition_id": "material_test"},
	}
	return plan
