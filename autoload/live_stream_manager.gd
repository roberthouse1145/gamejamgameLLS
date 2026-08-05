extends Node
## 开播向导草稿、纯预结算与幂等提交的业务入口。

signal draft_changed(draft: Dictionary)
signal step_changed(step: int)
signal catalogs_changed()
signal broadcast_requested(plan: StreamPlanSnapshot, result: StreamSettlementResult)
signal broadcast_committed(plan: StreamPlanSnapshot, result: StreamSettlementResult)
signal broadcast_failed(reason: String)

enum WizardStep {
	SETUP,
	SCRIPT,
	CONFIRM,
}

const STEP_COUNT: int = 3
const MAX_TITLE_LENGTH: int = 48
const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")

var _current_step: int = WizardStep.SETUP
var _draft: Dictionary = {}
var _broadcast_pending: bool = false
var _pending_plan: StreamPlanSnapshot = null
var _pending_result: StreamSettlementResult = null
var _session_serial: int = 0
var _calculator := LiveStreamCalculator.new()


func _ready() -> void:
	GameState.streamer_progress_changed.connect(_on_streamer_progress_changed)
	call_deferred("_connect_material_inventory")
	_ensure_persona_state()
	reset_draft()


func reset_draft() -> void:
	_current_step = WizardStep.SETUP
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	var default_persona_id: String = String(CATALOG.personas[0].content_id) if not CATALOG.personas.is_empty() else ""
	_draft = {
		"title": "",
		"persona_id": default_persona_id,
		"material_instance_id": "",
		"behavior_slots": [],
		"modifier_slots": [],
	}
	_resize_slots()
	step_changed.emit(_current_step)
	draft_changed.emit(get_draft())


func get_current_step() -> int:
	return _current_step


func get_draft() -> Dictionary:
	return _draft.duplicate(true)


func get_personas() -> Array[StreamPersonaResource]:
	var result: Array[StreamPersonaResource] = []
	result.assign(CATALOG.personas)
	return result


func get_material_instances() -> Array[Dictionary]:
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	return material_manager.get_instances() if material_manager != null else []


func get_persona(persona_id: StringName = &"") -> StreamPersonaResource:
	var resolved_id: StringName = persona_id if persona_id != &"" else StringName(str(_draft.get("persona_id", "")))
	return CATALOG.get_persona(resolved_id)


func get_material_instance(instance_id: StringName = &"") -> Dictionary:
	var resolved_id: StringName = instance_id if instance_id != &"" else StringName(str(_draft.get("material_instance_id", "")))
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	return material_manager.get_instance(resolved_id) if material_manager != null else {}


func get_material_definition(instance_id: StringName = &"") -> LiveStreamMaterialResource:
	var resolved_id: StringName = instance_id if instance_id != &"" else StringName(str(_draft.get("material_instance_id", "")))
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	return material_manager.get_definition_for_instance(resolved_id) if material_manager != null else null


func set_title(value: String) -> void:
	var normalized: String = value.replace("\n", " ").replace("\r", " ").strip_edges()
	if normalized.length() > MAX_TITLE_LENGTH:
		normalized = normalized.substr(0, MAX_TITLE_LENGTH)
	if str(_draft.get("title", "")) == normalized:
		return
	_draft["title"] = normalized
	draft_changed.emit(get_draft())


func select_persona(persona_id: StringName) -> bool:
	if CATALOG.get_persona(persona_id) == null:
		return false
	_draft["persona_id"] = String(persona_id)
	draft_changed.emit(get_draft())
	return true


func select_material(material_instance_id: StringName) -> bool:
	if get_material_instance(material_instance_id).is_empty():
		return false
	_draft["material_instance_id"] = String(material_instance_id)
	_clear_incompatible_behavior_cards()
	draft_changed.emit(get_draft())
	return true


func select_behavior_card(card_id: StringName) -> bool:
	var card: BehaviorCardResource = CATALOG.get_card(card_id) as BehaviorCardResource
	var material_instance_id := StringName(str(_draft.get("material_instance_id", "")))
	var card_manager: Node = get_node_or_null("/root/CardLibraryManager")
	if card == null or card_manager == null or not card_manager.is_card_unlocked(card_id):
		return false
	if material_instance_id == &"" or not card_manager.is_compatible(card_id, material_instance_id):
		return false
	var slots: Array = (_draft.get("behavior_slots", []) as Array).duplicate()
	var existing_index: int = slots.find(String(card_id))
	if existing_index >= 0:
		slots[existing_index] = ""
	else:
		var empty_index: int = slots.find("")
		if empty_index < 0:
			return false
		slots[empty_index] = String(card_id)
	_draft["behavior_slots"] = slots
	draft_changed.emit(get_draft())
	return true


func clear_behavior_slot(slot_index: int) -> bool:
	var slots: Array = (_draft.get("behavior_slots", []) as Array).duplicate()
	if slot_index < 0 or slot_index >= slots.size() or str(slots[slot_index]).is_empty():
		return false
	slots[slot_index] = ""
	_draft["behavior_slots"] = slots
	draft_changed.emit(get_draft())
	return true


func select_modifier_card(card_id: StringName) -> bool:
	var card: ModifierCardResource = CATALOG.get_card(card_id) as ModifierCardResource
	var card_manager: Node = get_node_or_null("/root/CardLibraryManager")
	if card == null or card_manager == null or not card_manager.is_card_unlocked(card_id):
		return false
	var slots: Array = (_draft.get("modifier_slots", []) as Array).duplicate()
	var existing_index: int = slots.find(String(card_id))
	if existing_index >= 0:
		slots[existing_index] = ""
	else:
		var empty_index: int = slots.find("")
		if empty_index < 0:
			return false
		slots[empty_index] = String(card_id)
	_draft["modifier_slots"] = slots
	draft_changed.emit(get_draft())
	return true


func clear_modifier_slot(slot_index: int) -> bool:
	var slots: Array = (_draft.get("modifier_slots", []) as Array).duplicate()
	if slot_index < 0 or slot_index >= slots.size() or str(slots[slot_index]).is_empty():
		return false
	slots[slot_index] = ""
	_draft["modifier_slots"] = slots
	draft_changed.emit(get_draft())
	return true


func get_budget_used() -> int:
	var result: int = 0
	for card_id: Variant in (_draft.get("behavior_slots", []) as Array) + (_draft.get("modifier_slots", []) as Array):
		var card: LiveStreamCardResource = CATALOG.get_card(StringName(str(card_id)))
		if card != null:
			result += card.budget_cost
	return result


func get_budget_limit() -> int:
	return BALANCE.get_budget(GameState.streamer_level, GameState.stress)


func can_advance(step: int = -1) -> bool:
	var resolved_step: int = _current_step if step < 0 else step
	match resolved_step:
		WizardStep.SETUP:
			return _is_setup_valid()
		WizardStep.SCRIPT:
			return _is_script_valid()
		WizardStep.CONFIRM:
			return _is_setup_valid() and _is_script_valid() and not _broadcast_pending
	return false


func get_validation_message(step: int = -1) -> String:
	var resolved_step: int = _current_step if step < 0 else step
	if resolved_step == WizardStep.SETUP:
		if str(_draft.get("title", "")).is_empty():
			return "填写直播标题"
		if get_persona() == null:
			return "选择本场人设"
		if get_material_instance().is_empty():
			return "选择本场素材"
	elif resolved_step == WizardStep.SCRIPT:
		for card_id: Variant in _draft.get("behavior_slots", []):
			if str(card_id).is_empty():
				return "节目槽尚未排满"
		var structure_error: String = _get_structure_error()
		if not structure_error.is_empty():
			return structure_error
		if get_budget_used() > get_budget_limit():
			return "演出预算 %d / %d" % [get_budget_used(), get_budget_limit()]
	elif resolved_step == WizardStep.CONFIRM and _broadcast_pending:
		return "节目单已提交"
	return "本步已完成"


func advance_step() -> bool:
	if _current_step >= WizardStep.CONFIRM or not can_advance(_current_step):
		return false
	_current_step += 1
	step_changed.emit(_current_step)
	return true


func previous_step() -> bool:
	if _current_step <= WizardStep.SETUP or _broadcast_pending:
		return false
	_current_step -= 1
	step_changed.emit(_current_step)
	return true


func build_stream_plan(rng_seed: int = 1, session_id: StringName = &"preview") -> StreamPlanSnapshot:
	if not _is_setup_valid() or not _is_script_valid():
		return null
	var plan := StreamPlanSnapshot.new()
	plan.session_id = session_id
	plan.title = str(_draft.get("title", ""))
	plan.persona_id = StringName(str(_draft.get("persona_id", "")))
	plan.material_instance_id = StringName(str(_draft.get("material_instance_id", "")))
	for card_id: Variant in _draft.get("behavior_slots", []):
		plan.behavior_card_ids.append(StringName(str(card_id)))
	for card_id: Variant in _draft.get("modifier_slots", []):
		if not str(card_id).is_empty():
			plan.modifier_card_ids.append(StringName(str(card_id)))
	plan.rng_seed = rng_seed
	plan.state_snapshot = _build_state_snapshot(plan.material_instance_id)
	return plan


func get_preview_result() -> StreamSettlementResult:
	var plan: StreamPlanSnapshot = build_stream_plan(1, &"preview")
	return _calculator.calculate(plan, CATALOG, BALANCE) if plan != null else null


func request_broadcast(rng_seed: int = 0) -> StreamPlanSnapshot:
	if not can_advance(WizardStep.CONFIRM):
		return null
	_session_serial += 1
	var session_id := StringName("day_%d_slot_%d_%03d" % [GameState.day, GameState.time_slot, _session_serial])
	var resolved_seed: int = rng_seed if rng_seed != 0 else hash(String(session_id))
	var plan: StreamPlanSnapshot = build_stream_plan(resolved_seed, session_id)
	if plan == null:
		return null
	var result: StreamSettlementResult = _calculator.calculate(plan, CATALOG, BALANCE)
	_pending_plan = plan
	_pending_result = result
	_broadcast_pending = true
	draft_changed.emit(get_draft())
	broadcast_requested.emit(plan, result)
	return plan


func commit_broadcast(session_id: StringName) -> bool:
	if _pending_plan == null or _pending_result == null or _pending_plan.session_id != session_id:
		return false
	if String(session_id) in GameState.completed_stream_sessions:
		return false
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	if material_manager == null or not material_manager.commit_use(_pending_result.material_use):
		return false
	GameState.adjust_attribute(GameState.ATTR_STRESS, _pending_result.stress_delta)
	GameState.add_money(_pending_result.revenue)
	GameState.set_fans(GameState.fans + _pending_result.fan_delta)
	GameState.set_fan_vector(_pending_result.resulting_fan_vector)
	if _pending_result.accident_occurred:
		GameState.flame_value += 1.0
	GameState.add_streamer_exp(_pending_result.streamer_exp_gain, BALANCE)
	GameState.completed_stream_sessions.append(String(session_id))
	_record_history(_pending_plan, _pending_result)
	var committed_plan: StreamPlanSnapshot = _pending_plan
	var committed_result: StreamSettlementResult = _pending_result
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	broadcast_committed.emit(committed_plan, committed_result)
	draft_changed.emit(get_draft())
	return true


func mark_broadcast_failed(reason: String) -> void:
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	broadcast_failed.emit(reason)
	draft_changed.emit(get_draft())


func is_broadcast_pending() -> bool:
	return _broadcast_pending


func get_pending_result() -> StreamSettlementResult:
	return _pending_result


func get_run_state() -> Dictionary:
	return {"current_step": _current_step, "draft": get_draft()}


func load_run_state(data: Dictionary) -> bool:
	var loaded_draft: Variant = data.get("draft", {})
	if not loaded_draft is Dictionary:
		return false
	_draft = (loaded_draft as Dictionary).duplicate(true)
	_resize_slots()
	_current_step = clampi(int(data.get("current_step", WizardStep.SETUP)), WizardStep.SETUP, WizardStep.CONFIRM)
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	step_changed.emit(_current_step)
	draft_changed.emit(get_draft())
	return true


func _is_setup_valid() -> bool:
	return (
		not str(_draft.get("title", "")).is_empty()
		and get_persona() != null
		and not get_material_instance().is_empty()
	)


func _is_script_valid() -> bool:
	var card_manager: Node = get_node_or_null("/root/CardLibraryManager")
	if card_manager == null or get_budget_used() > get_budget_limit():
		return false
	var material_instance_id := StringName(str(_draft.get("material_instance_id", "")))
	var slots: Array = _draft.get("behavior_slots", [])
	if slots.size() != BALANCE.get_behavior_slot_count(GameState.streamer_level):
		return false
	for card_id: Variant in slots:
		var normalized_id := StringName(str(card_id))
		if normalized_id == &"" or not card_manager.is_card_unlocked(normalized_id) or not card_manager.is_compatible(normalized_id, material_instance_id):
			return false
	if not _get_structure_error().is_empty():
		return false
	for card_id: Variant in _draft.get("modifier_slots", []):
		if not str(card_id).is_empty() and not card_manager.is_card_unlocked(StringName(str(card_id))):
			return false
	return true


func _get_structure_error() -> String:
	var slots: Array = _draft.get("behavior_slots", [])
	if slots.is_empty():
		return "节目单需要一张开场卡"
	for index: int in range(slots.size()):
		var card: BehaviorCardResource = CATALOG.get_card(StringName(str(slots[index]))) as BehaviorCardResource
		if card == null:
			continue
		if index == 0 and card.mood_in != BehaviorCardResource.MOOD_OPEN:
			return "第一张必须是左端平齐的开场卡"
		if index > 0 and card.mood_in == BehaviorCardResource.MOOD_OPEN:
			return "开场卡只能放在第一格"
		if index < slots.size() - 1 and card.mood_out == BehaviorCardResource.MOOD_OPEN:
			return "右端平齐的收尾卡只能放在最后一格"
	return ""


func _resize_slots() -> void:
	var behavior_slots: Array = (_draft.get("behavior_slots", []) as Array).duplicate()
	behavior_slots.resize(BALANCE.get_behavior_slot_count(GameState.streamer_level))
	for index: int in range(behavior_slots.size()):
		if behavior_slots[index] == null:
			behavior_slots[index] = ""
	_draft["behavior_slots"] = behavior_slots
	var modifier_slots: Array = (_draft.get("modifier_slots", []) as Array).duplicate()
	modifier_slots.resize(BALANCE.get_modifier_slot_count(GameState.streamer_level))
	for index: int in range(modifier_slots.size()):
		if modifier_slots[index] == null:
			modifier_slots[index] = ""
	_draft["modifier_slots"] = modifier_slots


func _clear_incompatible_behavior_cards() -> void:
	var card_manager: Node = get_node_or_null("/root/CardLibraryManager")
	if card_manager == null:
		return
	var material_instance_id := StringName(str(_draft.get("material_instance_id", "")))
	var slots: Array = (_draft.get("behavior_slots", []) as Array).duplicate()
	for index: int in range(slots.size()):
		if not str(slots[index]).is_empty() and not card_manager.is_compatible(StringName(str(slots[index])), material_instance_id):
			slots[index] = ""
	_draft["behavior_slots"] = slots


func _build_state_snapshot(material_instance_id: StringName) -> Dictionary:
	return {
		"streamer_name": GameState.streamer_name,
		"streamer_level": GameState.streamer_level,
		"skill_levels": GameState.skill_levels.duplicate(true),
		"stress": GameState.stress,
		"otaku_desire": GameState.otaku_desire,
		"loneliness": GameState.loneliness,
		"fans": GameState.fans,
		"fan_vector": GameState.fan_vector.duplicate(true),
		"material_instance": get_material_instance(material_instance_id),
	}


func _record_history(plan: StreamPlanSnapshot, result: StreamSettlementResult) -> void:
	var history_manager: Node = get_node_or_null("/root/StreamHistoryManager")
	if history_manager == null:
		return
	var persona: StreamPersonaResource = CATALOG.get_persona(plan.persona_id)
	var material: LiveStreamMaterialResource = get_material_definition(plan.material_instance_id)
	history_manager.record_completed_stream({
		"title": plan.title,
		"persona_name": persona.display_name if persona != null else "",
		"material_name": material.display_name if material != null else "",
		"card_ids": plan.behavior_card_ids + plan.modifier_card_ids,
	}, {
		"session_id": String(result.session_id),
		"heat": result.peak_viewers,
		"revenue": result.revenue,
		"fan_delta": result.fan_delta,
		"stress_delta": result.stress_delta,
		"flame_delta": 1.0 if result.accident_occurred else 0.0,
		"summary": "直播已按节目单完成预结算。",
	})


func _ensure_persona_state() -> void:
	for persona: StreamPersonaResource in CATALOG.personas:
		if persona != null and not GameState.persona_progress.has(String(persona.content_id)):
			GameState.persona_progress[String(persona.content_id)] = {
				"proficiency": persona.initial_proficiency,
				"fixation": persona.initial_fixation,
			}


func _connect_material_inventory() -> void:
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	if material_manager != null and not material_manager.inventory_changed.is_connected(_on_inventory_changed):
		material_manager.inventory_changed.connect(_on_inventory_changed)


func _on_streamer_progress_changed(_level: int, _exp: int, _points: int) -> void:
	_resize_slots()
	draft_changed.emit(get_draft())


func _on_inventory_changed() -> void:
	if not str(_draft.get("material_instance_id", "")).is_empty() and get_material_instance().is_empty():
		_draft["material_instance_id"] = ""
	catalogs_changed.emit()
	draft_changed.emit(get_draft())
