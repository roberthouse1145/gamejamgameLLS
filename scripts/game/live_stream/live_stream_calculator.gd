class_name LiveStreamCalculator extends RefCounted
## 直播纯预结算器。相同快照与 seed 必须得到相同结果。


func calculate(plan: StreamPlanSnapshot, catalog: LiveStreamCatalog, balance: LiveStreamBalance) -> StreamSettlementResult:
	var result := StreamSettlementResult.new()
	if plan == null or catalog == null or balance == null:
		return result
	result.session_id = plan.session_id

	var material_state: Dictionary = plan.state_snapshot.get("material_instance", {})
	var material_id := StringName(str(material_state.get("definition_id", "")))
	var material: LiveStreamMaterialResource = catalog.get_material(material_id)
	var persona: StreamPersonaResource = catalog.get_persona(plan.persona_id)
	if material == null or persona == null:
		return result

	var axes: Dictionary = {"hook": 0.0, "quality": 0.0, "impact": 0.0, "risk": 0.0}
	var fan_bias: Dictionary = {"r": 0.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0}
	var stress_delta: float = 0.0
	var behavior_cards: Array[BehaviorCardResource] = []
	var behavior_slot_indices: Array[int] = []
	for slot_index: int in range(plan.behavior_card_ids.size()):
		var card_id: StringName = plan.behavior_card_ids[slot_index]
		var behavior_card: BehaviorCardResource = catalog.get_card(card_id) as BehaviorCardResource
		if behavior_card != null:
			behavior_cards.append(behavior_card)
			behavior_slot_indices.append(slot_index)
	var empty_program_slot_count: int = plan.behavior_card_ids.size() - behavior_cards.size()
	var empty_fill_rescue_available: bool = _get_skill_level(plan, &"talk") >= 3
	var seamless_transition: bool = _has_effect(plan.modifier_card_ids, catalog, &"seam_penalty_half")
	var full_chain_active: bool = behavior_cards.size() > 1 and _are_all_seams_full(behavior_cards)
	var global_modifiers: Array[ModifierCardResource] = []
	for modifier_id: StringName in plan.modifier_card_ids:
		var modifier: ModifierCardResource = catalog.get_card(modifier_id) as ModifierCardResource
		if modifier != null:
			global_modifiers.append(modifier)
			stress_delta += modifier.stress_cost
			_accumulate_fan_bias(fan_bias, modifier.fan_bias)

	for card_index: int in range(behavior_cards.size()):
		var card: BehaviorCardResource = behavior_cards[card_index]
		var connected_slots: Array[int] = []
		var fill_ratio: float = 1.0
		var fill_multiplier: float = 1.0
		var seam_risk_bonus: float = 0.0
		if card_index > 0 and not card.left_slots.is_empty():
			var previous_card: BehaviorCardResource = behavior_cards[card_index - 1]
			connected_slots = BehaviorCardResource.intersect_slots(previous_card.right_slots, card.left_slots)
			fill_ratio = float(connected_slots.size()) / float(card.left_slots.size())
			fill_multiplier = balance.get_fill_multiplier(fill_ratio)
			if is_zero_approx(fill_ratio):
				if empty_fill_rescue_available:
					empty_fill_rescue_available = false
					fill_multiplier = balance.half_fill_multiplier
				elif seamless_transition:
					fill_multiplier = balance.partial_fill_multiplier
					seam_risk_bonus = balance.empty_fill_risk_bonus * 0.5
				else:
					seam_risk_bonus = balance.empty_fill_risk_bonus
		var skill_level: int = _get_skill_level(plan, card.family)
		var skill_multiplier: float = 1.0 + balance.skill_bonus_per_level * float(maxi(skill_level - 1, 0))
		var width_multiplier: float = balance.get_left_width_multiplier(card.get_left_width())
		var chain_multiplier: float = balance.full_chain_multiplier if full_chain_active else 1.0
		var base_multiplier: float = skill_multiplier * material.affinity.get_value(card.family)
		base_multiplier *= width_multiplier * fill_multiplier * chain_multiplier
		base_multiplier *= persona.base_performance_multiplier
		for axis_key: StringName in StreamAxisValues.KEYS:
			var value: float = card.axes.get_value(axis_key) * base_multiplier
			value *= _get_material_axis_multiplier(card, material, axis_key)
			value *= _get_card_modifier_multiplier(card, global_modifiers, axis_key)
			axes[String(axis_key)] = float(axes[String(axis_key)]) + value
		axes["risk"] = float(axes["risk"]) + seam_risk_bonus * 10.0
		stress_delta += card.stress_cost
		_accumulate_fan_bias(fan_bias, card.fan_bias)
		result.interface_trace.append({
			"card_id": String(card.content_id),
			"slot_index": behavior_slot_indices[card_index],
			"left_slots": card.left_slots.duplicate(),
			"right_slots": card.right_slots.duplicate(),
			"connected_slots": connected_slots.duplicate(),
			"fill_ratio": fill_ratio,
			"fill_multiplier": fill_multiplier,
			"width_multiplier": width_multiplier,
		})

	for axis_key: StringName in StreamAxisValues.KEYS:
		axes[String(axis_key)] = float(axes[String(axis_key)]) + material.axes.get_value(axis_key)
		axes[String(axis_key)] *= _get_global_modifier_multiplier(global_modifiers, axis_key)

	if float(material_state.get("depth", material.initial_depth)) <= 0.0:
		axes["quality"] = float(axes["quality"]) - 1.0
	_apply_private_state_penalties(axes, plan.state_snapshot)

	var freshness: float = clampf(float(material_state.get("freshness", 1.0)), 0.4, 1.0)
	var fans: int = maxi(int(plan.state_snapshot.get("fans", 0)), 0)
	var base_audience: float = (material.base_popularity + float(fans) * 0.08) * freshness
	base_audience *= pow(balance.empty_program_slot_multiplier, empty_program_slot_count)
	result.peak_viewers = maxi(int(round(base_audience * maxf(0.2, 1.0 + float(axes["hook"]) * 0.12))), 1)
	var passerby_ratio: float = clampf(float((plan.state_snapshot.get("fan_vector", {}) as Dictionary).get("r", 100.0)) / 100.0, 0.05, 1.0)
	result.fan_delta = maxi(int(round(float(result.peak_viewers) * maxf(0.0, 0.03 + float(axes["quality"]) * 0.01) * passerby_ratio)), 0)
	var fan_vector: Dictionary = plan.state_snapshot.get("fan_vector", {}).duplicate(true)
	var monetization_weight: float = (
		0.3 * float(fan_vector.get("r", 100.0))
		+ 0.6 * (float(fan_vector.get("m", 0.0)) + float(fan_vector.get("w", 0.0)))
		+ 1.6 * float(fan_vector.get("c", 0.0))
		- 0.5 * float(fan_vector.get("b", 0.0))
	) / 100.0
	result.revenue = maxi(int(round(float(result.peak_viewers) * maxf(float(axes["impact"]), 0.0) * 0.08 * maxf(monetization_weight, 0.1))), 0)
	var stress: int = clampi(int(plan.state_snapshot.get("stress", 0)), 0, 100)
	result.accident_probability = clampf(0.01 + maxf(float(axes["risk"]), 0.0) * 0.03 + float(stress) * 0.001, 0.0, 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = plan.rng_seed
	result.accident_occurred = rng.randf() < result.accident_probability
	if result.accident_occurred:
		fan_bias["b"] = float(fan_bias["b"]) + 5.0
		fan_bias["r"] = float(fan_bias["r"]) - 5.0
	if material.material_type == LiveStreamMaterialResource.TYPE_SPONSOR and material.sponsor_terms != null:
		result.sponsor_satisfied = float(axes["quality"]) >= material.sponsor_terms.quality_floor and not result.accident_occurred
		var sponsor_multiplier: float = 1.0 if result.sponsor_satisfied else material.sponsor_terms.failure_payout_multiplier
		result.sponsor_payout = int(round(float(material.sponsor_terms.guaranteed_money) * sponsor_multiplier))
		result.revenue += result.sponsor_payout
	result.resulting_fan_vector = _resolve_fan_vector(fan_vector, fan_bias)
	result.axes = axes
	result.stress_delta = int(round(stress_delta))
	result.streamer_exp_gain = balance.stream_exp_reward
	result.material_use = {
		"instance_id": String(plan.material_instance_id),
		"material_type": String(material.material_type),
		"depth_delta": -1.0,
		"progress_delta": 1,
		"freshness_delta": -material.freshness_decay,
	}
	return result


func _get_skill_level(plan: StreamPlanSnapshot, family: StringName) -> int:
	var levels: Dictionary = plan.state_snapshot.get("skill_levels", {})
	return clampi(int(levels.get(String(family), 1)), 1, 5)


func _are_all_seams_full(cards: Array[BehaviorCardResource]) -> bool:
	for index: int in range(1, cards.size()):
		var card: BehaviorCardResource = cards[index]
		if card.left_slots.is_empty() or card.get_fill_ratio(cards[index - 1].right_slots) < 1.0:
			return false
	return true


func _get_material_axis_multiplier(card: BehaviorCardResource, material: LiveStreamMaterialResource, axis_key: StringName) -> float:
	var result: float = 1.0
	for boost: StreamTagEffect in card.material_boosts:
		if boost != null and boost.axis_key == axis_key and boost.with_tag in material.tags:
			result *= boost.multiplier
	for combo: StreamTagEffect in material.combo_effects:
		if combo != null and combo.axis_key == axis_key and combo.with_tag in card.tags:
			result *= combo.multiplier
	return result


func _get_card_modifier_multiplier(card: BehaviorCardResource, modifiers: Array[ModifierCardResource], axis_key: StringName) -> float:
	var result: float = 1.0
	for modifier: ModifierCardResource in modifiers:
		if modifier.target_family != &"" and modifier.target_family != card.family:
			continue
		if modifier.target_family == &"":
			continue
		result *= 1.0 + modifier.axis_multiplier_bonus.get_value(axis_key)
	return maxf(result, 0.0)


func _get_global_modifier_multiplier(modifiers: Array[ModifierCardResource], axis_key: StringName) -> float:
	var result: float = 1.0
	for modifier: ModifierCardResource in modifiers:
		if modifier.target_family == &"":
			result *= 1.0 + modifier.axis_multiplier_bonus.get_value(axis_key)
	return maxf(result, 0.0)


func _has_effect(card_ids: Array[StringName], catalog: LiveStreamCatalog, effect_id: StringName) -> bool:
	for card_id: StringName in card_ids:
		var card: LiveStreamCardResource = catalog.get_card(card_id)
		if card == null:
			continue
		for effect: StreamSpecialEffect in card.special_effects:
			if effect != null and effect.effect_id == effect_id:
				return true
	return false


func _accumulate_fan_bias(target: Dictionary, bias: StreamFanBias) -> void:
	if bias == null:
		return
	var values: Dictionary = bias.to_dict()
	for key: String in values:
		target[key] = float(target.get(key, 0.0)) + float(values[key])


func _apply_private_state_penalties(axes: Dictionary, state: Dictionary) -> void:
	var multiplier: float = 1.0
	if int(state.get("stress", 0)) > 60:
		multiplier *= 0.9
	if int(state.get("otaku_desire", 0)) > 70:
		multiplier *= 0.9
	for key: String in ["hook", "quality", "impact"]:
		if float(axes[key]) > 0.0:
			axes[key] = float(axes[key]) * multiplier


func _resolve_fan_vector(current: Dictionary, delta: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var total: float = 0.0
	for key: String in ["r", "m", "w", "c", "b"]:
		var value: float = maxf(float(current.get(key, 0.0)) + float(delta.get(key, 0.0)), 0.0)
		result[key] = value
		total += value
	if total <= 0.0:
		return {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0}
	for key: String in result:
		result[key] = float(result[key]) / total * 100.0
	return result
