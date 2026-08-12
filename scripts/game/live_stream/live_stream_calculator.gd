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

	var axes: Dictionary = {"hook": 0.0, "quality": 0.0, "impact": 0.0}
	var fan_bias: Dictionary = {"r": 0.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0}
	var stress_delta: float = 0.0
	var approach_type := StringName(str(plan.approach.get("approach_type", "")))
	var approach_profile: Dictionary = balance.get_approach_profile(approach_type)
	if approach_profile.is_empty():
		return result
	var approach_multiplier: float = _get_approach_skill_multiplier(
		plan, material, approach_profile, balance
	)
	_accumulate_axes(axes, approach_profile.get("axes", {}), approach_multiplier)
	stress_delta += float(approach_profile.get("stress", 0.0))
	_accumulate_fan_bias(fan_bias, approach_profile.get("fan_bias", {}))

	for axis_key: StringName in StreamAxisValues.KEYS:
		axes[String(axis_key)] = float(axes[String(axis_key)]) + material.axes.get_value(axis_key)

	_apply_private_state_penalties(axes, plan.state_snapshot)

	var fans: int = maxi(int(plan.state_snapshot.get("fans", 0)), 0)
	var base_audience: float = material.base_popularity + float(fans) * 0.08
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
	if material.material_type == LiveStreamMaterialResource.TYPE_SPONSOR and material.sponsor_terms != null:
		result.sponsor_satisfied = float(axes["quality"]) >= material.sponsor_terms.quality_floor
		var sponsor_multiplier: float = 1.0 if result.sponsor_satisfied else material.sponsor_terms.failure_payout_multiplier
		result.sponsor_payout = int(round(float(material.sponsor_terms.guaranteed_money) * sponsor_multiplier))
		result.revenue += result.sponsor_payout
	result.resulting_fan_vector = _resolve_fan_vector(fan_vector, fan_bias)
	result.axes = axes
	result.stress_delta = int(round(stress_delta))
	result.skill_exp_gains = material.skill_exp_rewards.to_dict()
	result.streamer_exp_gain = material.skill_exp_rewards.get_total()
	result.material_use = {
		"instance_id": String(plan.material_instance_id),
		"material_type": String(material.material_type),
	}
	return result


func _get_skill_level(plan: StreamPlanSnapshot, family: StringName) -> int:
	var levels: Dictionary = plan.state_snapshot.get("skill_levels", {})
	return clampi(int(levels.get(String(family), 1)), 1, 5)


func _get_approach_skill_multiplier(
	plan: StreamPlanSnapshot,
	material: LiveStreamMaterialResource,
	profile: Dictionary,
	balance: LiveStreamBalance
) -> float:
	var families: Array[StringName] = []
	if material.skill_exp_rewards != null:
		for family: StringName in GameState.SKILL_FAMILIES:
			if material.skill_exp_rewards.get_value(family) > 0:
				families.append(family)
	for family_value: Variant in profile.get("support_families", []):
		var family := StringName(str(family_value))
		if family not in families:
			families.append(family)
	if families.is_empty():
		return 1.0
	var total: float = 0.0
	for family: StringName in families:
		var skill_level: int = _get_skill_level(plan, family)
		var skill_multiplier: float = 1.0 + balance.skill_bonus_per_level * float(maxi(skill_level - 1, 0))
		total += skill_multiplier * material.affinity.get_value(family)
	return total / float(families.size())


func _accumulate_axes(target: Dictionary, additions: Dictionary, multiplier: float) -> void:
	for axis_key: StringName in StreamAxisValues.KEYS:
		var key := String(axis_key)
		target[key] = float(target.get(key, 0.0)) + float(additions.get(key, 0.0)) * multiplier


func _accumulate_fan_bias(target: Dictionary, additions: Dictionary) -> void:
	for key: String in additions:
		target[key] = float(target.get(key, 0.0)) + float(additions[key])


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
