extends Node
## 开播向导草稿、纯预结算与幂等提交的业务入口。

signal draft_changed(draft: Dictionary)
signal step_changed(step: int)
signal catalogs_changed()
signal broadcast_requested(plan: StreamPlanSnapshot, result: StreamSettlementResult)
signal broadcast_committed(plan: StreamPlanSnapshot, result: StreamSettlementResult)
signal broadcast_failed(reason: String)
signal history_changed()
signal history_record_added(record: StreamSessionRecord)
signal stream_post_prefetched(session_id: StringName, post: Dictionary)
signal stream_post_prefetch_failed(session_id: StringName, error: String)
signal stream_post_published(session_id: StringName, post: SocialPostRecord)
signal approaches_changed(approaches: Array[Dictionary])
signal approaches_generation_completed(approaches: Array[Dictionary])
signal approaches_generation_failed(error: String)

enum WizardStep {
	SETUP,
	SCRIPT,
	CONFIRM,
}

const STEP_COUNT: int = 3
const SAVED_STATE_PATH: String = "user://obs_live_wizard.cfg"
const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const ROOM_THEME: StreamRoomThemeResource = preload("res://resources/live_stream/rooms/stream_room.tres")
const StreamHistoryStoreClass = preload("res://scripts/game/live_stream/stream_history_store.gd")
const SKILL_DOMAIN_CATALOG: StreamerSkillDomainCatalog = preload(
	"res://resources/live_stream/skills/streamer_skill_domains.tres"
)
const ACTION_OWNER: String = "live_stream"
const BROADCAST_TIME_SLOTS: int = 1
const LINKPOSTA_APP_ID: String = "linkposta"
const BROWSER_APP_ID: String = "browser"
const OBS_APP_ID: String = "obs_live"
const APPROACH_SOURCE_BUILTIN: String = "builtin"
const APPROACH_SOURCE_LLM: String = "llm"

var _current_step: int = WizardStep.SETUP
var _draft: Dictionary = {}
var _broadcast_pending: bool = false
var _pending_plan: StreamPlanSnapshot = null
var _pending_result: StreamSettlementResult = null
var _pending_summary: String = ""
var _pending_transaction_id: String = ""
var _awaiting_post_session_id: StringName = &""
var _session_serial: int = 0
var _calculator := LiveStreamCalculator.new()
var _history_store = null
var _post_generator: LiveStreamPostGenerator = null
var _approach_generator: LiveStreamApproachGenerator = null


func _ready() -> void:
	_history_store = StreamHistoryStoreClass.new(get_node_or_null("/root/GameState"))
	_post_generator = get_node_or_null("LiveStreamPostGenerator") as LiveStreamPostGenerator
	if _post_generator != null:
		_post_generator.post_prefetched.connect(_on_stream_post_prefetched)
		_post_generator.post_prefetch_failed.connect(_on_stream_post_prefetch_failed)
		_post_generator.post_published.connect(_on_stream_post_published)
	_approach_generator = LiveStreamApproachGenerator.new()
	_approach_generator.name = "LiveStreamApproachGenerator"
	add_child(_approach_generator)
	_approach_generator.approaches_generated.connect(_on_llm_approaches_generated)
	_approach_generator.approaches_failed.connect(_on_llm_approaches_failed)
	if not SocialMediaManager.post_presentation_completed.is_connected(_on_post_presentation_completed):
		SocialMediaManager.post_presentation_completed.connect(_on_post_presentation_completed)
	GameState.streamer_progress_changed.connect(_on_streamer_progress_changed)
	GameState.persona_changed.connect(_on_persona_changed)
	call_deferred("_connect_material_inventory")
	_ensure_persona_state()
	reset_draft()


func reset_draft() -> void:
	_cancel_pending_transaction()
	if _approach_generator != null:
		_approach_generator.cancel_all()
	_release_post_settlement_lock()
	_awaiting_post_session_id = &""
	_current_step = WizardStep.SETUP
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	_pending_summary = ""
	_draft = {
		"title": "",
		"persona_id": GameState.active_persona_id,
		"material_instance_id": "",
		"approach_state": "idle",
		"approach_cache_key": "",
		"approaches": [],
		"selected_approach_id": "",
	}
	clear_saved_run_state()
	_emit_step_changed()
	_emit_draft_changed()


## 上次配置落盘（策划 §10.1.4 老玩家快捷：默认沿用上次配置）。
func save_run_state() -> void:
	var config := ConfigFile.new()
	config.set_value("wizard", "current_step", _current_step)
	config.set_value("wizard", "draft", get_draft())
	config.save(SAVED_STATE_PATH)


func has_saved_run_state() -> bool:
	var config := ConfigFile.new()
	return config.load(SAVED_STATE_PATH) == OK and config.has_section("wizard")


## 恢复开播准备；素材或生成上下文失效时回到素材选择。
func load_saved_run_state() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVED_STATE_PATH) != OK:
		return false
	var data := {
		"current_step": int(config.get_value("wizard", "current_step", WizardStep.SETUP)),
		"draft": config.get_value("wizard", "draft", {}),
	}
	if not load_run_state(data):
		return false
	if not can_advance(_current_step):
		_current_step = WizardStep.SETUP
		_emit_step_changed()
	return true


func clear_saved_run_state() -> void:
	if FileAccess.file_exists(SAVED_STATE_PATH):
		DirAccess.remove_absolute(SAVED_STATE_PATH)


func _emit_step_changed() -> void:
	step_changed.emit(_current_step)
	save_run_state()


func _emit_draft_changed() -> void:
	draft_changed.emit(get_draft())
	save_run_state()


func get_current_step() -> int:
	return _current_step


func get_draft() -> Dictionary:
	return _draft.duplicate(true)


func get_personas() -> Array[StreamPersonaResource]:
	var result: Array[StreamPersonaResource] = []
	result.assign(CATALOG.personas)
	return result


## 当前扮演中的人设（开播前不可切换；切换走毕业转生，见策划案 §4.10）。
func get_active_persona() -> StreamPersonaResource:
	return CATALOG.get_persona(StringName(GameState.active_persona_id))


func get_graduated_personas() -> Array[String]:
	return GameState.graduated_personas.duplicate()


## 毕业转生（策划案 §4.10）：切换当前人设的唯一途径。
## 门控：目标人设必须存在、不是当前人设、未毕业。粉丝/熟练度/固化度由 GameState 重建。
func perform_graduation(new_persona_id: StringName) -> bool:
	var persona: StreamPersonaResource = CATALOG.get_persona(new_persona_id)
	if persona == null or String(new_persona_id) == GameState.active_persona_id:
		return false
	if String(new_persona_id) in GameState.graduated_personas:
		return false
	if not GameState.graduation_transform(
		String(new_persona_id),
		persona.initial_proficiency,
		persona.initial_fixation
	):
		return false
	_draft["persona_id"] = GameState.active_persona_id
	_emit_draft_changed()
	return true


func get_material_instances() -> Array[Dictionary]:
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	return material_manager.get_instances() if material_manager != null else []


func get_persona(persona_id: StringName = &"") -> StreamPersonaResource:
	var resolved_id: StringName = persona_id if persona_id != &"" else StringName(str(_draft.get("persona_id", "")))
	return CATALOG.get_persona(resolved_id)


func get_room_theme() -> StreamRoomThemeResource:
	return ROOM_THEME


func get_catalog() -> LiveStreamCatalog:
	return CATALOG


func get_balance() -> LiveStreamBalance:
	return BALANCE


func get_material_instance(instance_id: StringName = &"") -> Dictionary:
	var resolved_id: StringName = instance_id if instance_id != &"" else StringName(str(_draft.get("material_instance_id", "")))
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	return material_manager.get_instance(resolved_id) if material_manager != null else {}


func get_material_definition(instance_id: StringName = &"") -> LiveStreamMaterialResource:
	var resolved_id: StringName = instance_id if instance_id != &"" else StringName(str(_draft.get("material_instance_id", "")))
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	return material_manager.get_definition_for_instance(resolved_id) if material_manager != null else null


func select_material(material_instance_id: StringName) -> bool:
	if get_material_instance(material_instance_id).is_empty():
		return false
	_draft["material_instance_id"] = String(material_instance_id)
	# 标题占位 = 素材名；正式标题由演出生成器按人设/构思中途生成。
	var definition: LiveStreamMaterialResource = get_material_definition(material_instance_id)
	_draft["title"] = definition.display_name if definition != null else ""
	_emit_draft_changed()
	_prepare_builtin_approaches()
	return true


func get_approaches() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_draft.get("approaches", []))
	return result.duplicate(true)


func get_selected_approach() -> Dictionary:
	var selected_id: String = str(_draft.get("selected_approach_id", ""))
	for approach: Dictionary in get_approaches():
		if str(approach.get("approach_id", "")) == selected_id:
			return approach.duplicate(true)
	return {}


func select_approach(approach_id: StringName) -> bool:
	for approach: Dictionary in get_approaches():
		if StringName(str(approach.get("approach_id", ""))) != approach_id:
			continue
		_draft["selected_approach_id"] = String(approach_id)
		_emit_draft_changed()
		return true
	return false


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
		if get_material_instance().is_empty():
			return "选择本场素材"
	elif resolved_step == WizardStep.SCRIPT:
		if get_selected_approach().is_empty():
			return "选择一个直播构思"
	elif resolved_step == WizardStep.CONFIRM and _broadcast_pending:
		return "直播已提交"
	return "本步已完成"


func advance_step() -> bool:
	if _current_step >= WizardStep.CONFIRM or not can_advance(_current_step):
		return false
	if _current_step == WizardStep.SETUP:
		_ensure_approaches_current()
	_current_step += 1
	_emit_step_changed()
	return true


func previous_step() -> bool:
	if _current_step <= WizardStep.SETUP or _broadcast_pending:
		return false
	_current_step -= 1
	_emit_step_changed()
	return true


## 顶部 tab 跳转：回退任意步；前进要求途中每一步都已达完成条件。
func goto_step(step: int) -> bool:
	if _broadcast_pending or step < 0 or step >= STEP_COUNT or step == _current_step:
		return false
	if step > _current_step:
		for probe: int in range(_current_step, step):
			if not can_advance(probe):
				return false
	_current_step = step
	_emit_step_changed()
	return true


func build_stream_plan(rng_seed: int = 1, session_id: StringName = &"preview") -> StreamPlanSnapshot:
	if not _is_setup_valid() or not _is_script_valid():
		return null
	var plan := StreamPlanSnapshot.new()
	plan.session_id = session_id
	plan.title = str(_draft.get("title", ""))
	plan.persona_id = StringName(str(_draft.get("persona_id", "")))
	plan.material_instance_id = StringName(str(_draft.get("material_instance_id", "")))
	plan.approach = get_selected_approach()
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
	var transaction_id: String = "action_live_stream_%s" % String(session_id)
	if not ActionTransactionManager.reserve(
		transaction_id,
		ACTION_OWNER,
		0,
		BROADCAST_TIME_SLOTS
	):
		return null
	_pending_plan = plan
	_pending_result = result
	_pending_summary = ""
	_pending_transaction_id = transaction_id
	_broadcast_pending = true
	_emit_draft_changed()
	broadcast_requested.emit(plan, result)
	return plan


func commit_broadcast(session_id: StringName) -> bool:
	if _pending_plan == null or _pending_result == null or _pending_plan.session_id != session_id:
		return false
	if String(session_id) in GameState.completed_stream_sessions:
		return false
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	var material_instance_id: StringName = StringName(str(_pending_result.material_use.get("instance_id", "")))
	if material_manager == null or material_instance_id == &"" \
		or material_manager.get_instance(material_instance_id).is_empty():
		return false
	if _pending_transaction_id.is_empty() \
		or not ActionTransactionManager.commit(_pending_transaction_id):
		return false
	# 素材已在上方验证；同一主线程中不会在时段提交与实际消耗之间被其它动作抢占。
	if not material_manager.commit_use(_pending_result.material_use):
		return false
	GameState.adjust_attribute(GameState.ATTR_STRESS, _pending_result.stress_delta)
	GameState.add_money(_pending_result.revenue)
	GameState.set_fans(GameState.fans + _pending_result.fan_delta)
	GameState.set_fan_vector(_pending_result.resulting_fan_vector)
	GameState.apply_skill_experience(_pending_result.skill_exp_gains, BALANCE)
	GameState.completed_stream_sessions.append(String(session_id))
	_record_history(_pending_plan, _pending_result)
	var committed_plan: StreamPlanSnapshot = _pending_plan
	var committed_result: StreamSettlementResult = _pending_result
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	_pending_summary = ""
	_pending_transaction_id = ""
	_awaiting_post_session_id = &""
	_release_post_settlement_lock()
	broadcast_committed.emit(committed_plan, committed_result)
	_emit_draft_changed()
	return true


func mark_broadcast_failed(reason: String) -> void:
	if _post_generator != null and _pending_plan != null:
		_post_generator.cancel_session(_pending_plan.session_id)
	_cancel_pending_transaction()
	_release_post_settlement_lock()
	_awaiting_post_session_id = &""
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	_pending_summary = ""
	broadcast_failed.emit(reason)
	_emit_draft_changed()


func is_broadcast_pending() -> bool:
	return _broadcast_pending


func get_pending_result() -> StreamSettlementResult:
	return _pending_result


## 直播画面结束后的自动收尾：打开 LinkPosta 并等待预生成的新帖完成展示。
## 自动测试可关闭页面打开，只验证发布与展示完成信号的事务顺序。
func begin_post_settlement(session_id: StringName, open_linkposta: bool = true) -> bool:
	if not _broadcast_pending or _pending_plan == null or _pending_plan.session_id != session_id:
		return false
	if _post_generator == null:
		_complete_broadcast_without_post(session_id, "直播动态生成器不可用")
		return false
	var job: Dictionary = _post_generator.get_job_snapshot(session_id)
	if job.is_empty() or str(job.get("state", "")) == "failed":
		_complete_broadcast_without_post(session_id, str(job.get("error", "直播动态未能生成")))
		return false
	_acquire_post_settlement_lock()
	if open_linkposta and AppManager.focus_app(LINKPOSTA_APP_ID, true) == null:
		_complete_broadcast_without_post(session_id, "无法打开 LinkPosta")
		return false
	_awaiting_post_session_id = session_id
	if not _post_generator.authorize_publication(session_id):
		_complete_broadcast_without_post(session_id, "直播动态未能进入发布阶段")
		return false
	return true


func prefetch_stream_post(plan: StreamPlanSnapshot, show: Dictionary) -> bool:
	if _post_generator == null or not _broadcast_pending or _pending_plan == null or plan == null:
		return false
	if plan.session_id != _pending_plan.session_id:
		return false
	return _post_generator.prefetch(plan, show)


func get_stream_post_job(session_id: StringName) -> Dictionary:
	return _post_generator.get_job_snapshot(session_id) if _post_generator != null else {}


func _on_stream_post_prefetched(session_id: StringName, post: Dictionary) -> void:
	stream_post_prefetched.emit(session_id, post)


func _on_stream_post_prefetch_failed(session_id: StringName, error: String) -> void:
	stream_post_prefetch_failed.emit(session_id, error)
	if session_id == _awaiting_post_session_id:
		_complete_broadcast_without_post(session_id, error)


func _on_stream_post_published(session_id: StringName, post: SocialPostRecord) -> void:
	stream_post_published.emit(session_id, post)


func _on_post_presentation_completed(post: SocialPostRecord) -> void:
	if post == null or _awaiting_post_session_id == &"" \
		or post.source_session_id != String(_awaiting_post_session_id):
		return
	var job: Dictionary = _post_generator.get_job_snapshot(_awaiting_post_session_id)
	if str(job.get("state", "")) != "published" \
		or str(job.get("post_id", "")) != post.post_id:
		return
	_complete_pending_broadcast(_awaiting_post_session_id)


func _complete_pending_broadcast(session_id: StringName) -> bool:
	_awaiting_post_session_id = &""
	if not commit_broadcast(session_id):
		mark_broadcast_failed("直播结算提交失败")
		return false
	if _post_generator != null:
		_post_generator.cancel_session(session_id)
	reset_draft()
	return true


func _complete_broadcast_without_post(session_id: StringName, reason: String) -> void:
	push_warning("LiveStreamManager: %s；跳过动态展示并完成直播结算" % reason)
	_complete_pending_broadcast(session_id)


func _acquire_post_settlement_lock() -> void:
	StoryLockManager.acquire_lock(ACTION_OWNER, {
		"block_time_actions": true,
		"restrict_apps": true,
		"allowed_apps": [OBS_APP_ID, LINKPOSTA_APP_ID, BROWSER_APP_ID],
		"protected_apps": [BROWSER_APP_ID],
		"reason": "直播动态正在更新",
	})


func _release_post_settlement_lock() -> void:
	StoryLockManager.release_lock(ACTION_OWNER)


func set_pending_stream_summary(session_id: StringName, summary: String) -> bool:
	if _pending_plan == null or _pending_plan.session_id != session_id:
		return false
	var normalized_summary: String = summary.strip_edges()
	if normalized_summary.is_empty():
		return false
	_pending_summary = normalized_summary
	return true


func get_run_state() -> Dictionary:
	return {"current_step": _current_step, "draft": get_draft()}


func load_run_state(data: Dictionary) -> bool:
	var loaded_draft: Variant = data.get("draft", {})
	if not loaded_draft is Dictionary:
		return false
	_cancel_pending_transaction()
	_draft = (loaded_draft as Dictionary).duplicate(true)
	# 当前人设固定为扮演中档位；旧档残留的过期 persona_id 一律回退。
	_draft["persona_id"] = GameState.active_persona_id
	# 标题占位跟随素材名；正式标题由生成器中途生成。
	var material_instance_id := StringName(str(_draft.get("material_instance_id", "")))
	var material: LiveStreamMaterialResource = get_material_definition(material_instance_id)
	if material != null:
		_draft["title"] = material.display_name
	else:
		_draft["material_instance_id"] = ""
		_clear_approaches()
	if material != null:
		var current_key: String = _build_approach_cache_key()
		var loaded_key: String = str(_draft.get("approach_cache_key", ""))
		var loaded_approaches: Array[Dictionary] = []
		loaded_approaches.assign(_draft.get("approaches", []))
		if loaded_key != current_key or not _validate_approaches(loaded_approaches):
			_clear_approaches()
	_current_step = clampi(int(data.get("current_step", WizardStep.SETUP)), WizardStep.SETUP, WizardStep.CONFIRM)
	_broadcast_pending = false
	_pending_plan = null
	_pending_result = null
	_emit_step_changed()
	_emit_draft_changed()
	if material != null and get_approaches().is_empty():
		_prepare_builtin_approaches()
	return true


func _is_setup_valid() -> bool:
	return not get_material_instance().is_empty()


func _is_script_valid() -> bool:
	return (
		str(_draft.get("approach_state", "")) == "ready"
		and not get_selected_approach().is_empty()
		and str(_draft.get("approach_cache_key", "")) == _build_approach_cache_key()
	)


## 真实 LLM 构思生成（策划案 §6.4 过渡接口）：对当前草稿素材异步生成 2～3 个临时构思。
## 生成期间草稿进入 requesting 等待态；成功写回候选并发出 approaches_generation_completed，
## 失败回退内置构思并发出 approaches_generation_failed。当前默认开播流程仍使用内置构思。
func request_llm_approaches() -> bool:
	if _broadcast_pending or _approach_generator == null or not _approach_generator.is_ready():
		return false
	if get_material_instance().is_empty() or get_material_definition() == null:
		return false
	if str(_draft.get("approach_state", "")) == "requesting":
		return false
	var request_id: String = _approach_generator.request_approaches(
		get_material_definition(),
		_build_llm_approach_context()
	)
	if request_id.is_empty():
		return false
	_draft["approach_state"] = "requesting"
	_draft["approaches"] = []
	_draft["selected_approach_id"] = ""
	_emit_draft_changed()
	return true


func get_llm_approach_generator() -> LiveStreamApproachGenerator:
	return _approach_generator


## lab 与调试用：渲染当前草稿素材的 LLM 构思 prompt，不发起请求。
func build_llm_approach_prompt(material: LiveStreamMaterialResource = null) -> String:
	var resolved: LiveStreamMaterialResource = material if material != null else get_material_definition()
	if resolved == null or _approach_generator == null:
		return ""
	return _approach_generator.build_prompt(resolved, _build_llm_approach_context())


func _build_llm_approach_context() -> Dictionary:
	return {
		"persona_block": _format_persona_prompt(get_active_persona()),
		"skill_block": _format_skill_levels(),
		"state_block": "压力 %d / 宅欲 %d / 孤独 %d / 粉丝 %d" % [
			GameState.stress,
			GameState.otaku_desire,
			GameState.loneliness,
			GameState.fans,
		],
		"history_block": _format_recent_history(),
	}


func _format_persona_prompt(persona: StreamPersonaResource) -> String:
	if persona == null:
		return "默认直播人设"
	var fragment: String = persona.prompt_fragment.strip_edges()
	if not fragment.is_empty():
		fragment = str(PromptManager.resolve_template(fragment)).strip_edges()
	if fragment.is_empty():
		return persona.display_name
	return fragment


func _format_skill_levels() -> String:
	var lines: Array[String] = []
	for family: StringName in GameState.SKILL_FAMILIES:
		var domain: StreamerSkillDomainResource = SKILL_DOMAIN_CATALOG.get_domain(family)
		var domain_name: String = domain.display_name if domain != null else String(family)
		var level: int = clampi(int(GameState.skill_levels.get(String(family), 1)), 1, 5)
		lines.append("%s Lv.%d" % [domain_name, level])
	return "、".join(lines)


func _format_recent_history() -> String:
	if _history_store == null or GameState.active_persona_id.is_empty():
		return "暂无已完成的直播记录。"
	var records: Array[StreamSessionRecord] = _history_store.get_recent_records_for_persona(
		StringName(GameState.active_persona_id),
		3
	)
	if records.is_empty():
		return "暂无已完成的直播记录。"
	var lines: Array[String] = []
	for record: StreamSessionRecord in records:
		var summary: String = record.summary.strip_edges().replace("\n", "\n  ")
		lines.append("- 第 %d 天《%s》\n  %s" % [record.day, record.title, summary])
	return "\n".join(lines)


func _on_llm_approaches_generated(_request_id: String, approaches: Array[Dictionary]) -> void:
	if str(_draft.get("approach_state", "")) != "requesting":
		return
	var cache_key: String = _build_approach_cache_key()
	if cache_key.is_empty() or not _apply_approaches(cache_key, approaches):
		_on_llm_approaches_failed("", "生成的构思未能写入草稿")
		return
	approaches_generation_completed.emit(get_approaches())


func _on_llm_approaches_failed(_request_id: String, error: String) -> void:
	if str(_draft.get("approach_state", "")) != "requesting":
		return
	push_warning("LiveStreamManager: %s；回退内置构思" % error)
	_prepare_builtin_approaches()
	approaches_generation_failed.emit(error)


func _ensure_approaches_current() -> void:
	if get_material_instance().is_empty():
		return
	if str(_draft.get("approach_cache_key", "")) != _build_approach_cache_key():
		_prepare_builtin_approaches()


func _prepare_builtin_approaches() -> void:
	var material: LiveStreamMaterialResource = get_material_definition()
	if material == null or get_material_instance().is_empty():
		_clear_approaches()
		return
	var cache_key: String = _build_approach_cache_key()
	if cache_key.is_empty():
		_clear_approaches()
		return
	var approaches: Array[Dictionary] = []
	for approach_type: StringName in _builtin_types_for_material(material):
		approaches.append(_make_builtin_approach(material, approach_type))
	_apply_approaches(cache_key, approaches)


func _build_approach_cache_key() -> String:
	var material_instance: Dictionary = get_material_instance()
	if material_instance.is_empty():
		return ""
	return str(_draft.get("material_instance_id", ""))


func _validate_approaches(approaches: Array[Dictionary]) -> bool:
	if approaches.size() < 2 or approaches.size() > 3:
		return false
	var ids: Dictionary = {}
	var types: Dictionary = {}
	for data: Dictionary in approaches:
		var approach := StreamApproach.from_dict(data)
		if not approach.is_valid(LiveStreamBalance.APPROACH_TYPES):
			return false
		if ids.has(approach.approach_id) or types.has(approach.approach_type):
			return false
		ids[approach.approach_id] = true
		types[approach.approach_type] = true
	return true


func _apply_approaches(cache_key: String, approaches: Array[Dictionary]) -> void:
	if cache_key != _build_approach_cache_key() or not _validate_approaches(approaches):
		return
	_draft["approach_state"] = "ready"
	_draft["approach_cache_key"] = cache_key
	_draft["approaches"] = approaches.duplicate(true)
	_draft["selected_approach_id"] = ""
	_emit_draft_changed()
	approaches_changed.emit(get_approaches())


func _builtin_types_for_material(material: LiveStreamMaterialResource) -> Array[StringName]:
	var result: Array[StringName] = []
	var activities: Array[StringName] = material.activities if material != null else []
	if &"sing" in activities or &"voice_performance" in activities or &"imitate_voice" in activities:
		result.append(&"performance")
	if &"challenge" in activities or &"play" in activities:
		result.append(&"challenge")
	if &"inspect_visual" in activities or &"debate" in activities or &"discuss" in activities:
		result.append(&"analysis")
	if &"react" in activities or &"discuss" in activities:
		result.append(&"audience_interaction")
	for builtin_type: StringName in [&"personal_story", &"production"]:
		if result.size() >= 3:
			break
		if builtin_type not in result:
			result.append(builtin_type)
	if result.size() > 3:
		result.resize(3)
	return result


func _make_builtin_approach(
	material: LiveStreamMaterialResource,
	approach_type: StringName
) -> Dictionary:
	var templates: Dictionary = {
		"analysis": ["顺着细节聊透", "抓住素材里的几个关键细节，一边验证一边把自己的判断讲清楚。", "围绕素材中可验证的具体细节推进。先提出一个判断，再通过当场观察、比较或尝试得到结果；用结果修正判断并完成收束。"],
		"challenge": ["今晚定个目标", "给这份素材立一个能在直播里见分晓的目标，过程和结果都交给现场。", "开场明确一个本场可兑现的目标。用连续行动推进，失败或偏差必须改变下一步策略；达到或放弃目标后立即接住结果收尾。"],
		"audience_interaction": ["让弹幕来决定", "把几个关键选择交给弹幕，让观众的意见真正改变今晚的走向。", "尽早建立一种清楚的观众参与方式，并至少让一次投票、建议或起哄改变主播接下来的行动；最后回收这个共同选择造成的结果。"],
		"performance": ["把它演出来", "把重点放在歌声、声线和人物表现上，让素材成为一段完整演出。", "以可听见、可看见的表演变化推进本场。围绕一个明确的情绪或角色目标逐步打开，最终用一段完成度最高的表现收束。"],
		"personal_story": ["从自己的感受聊起", "不急着讲全貌，从她真正有感觉的一点切入，慢慢聊出个人味道。", "从主播对素材最具体的一种个人感受切入。让当场内容触发更深入的表达，但只使用已提供的真实关系与历史；在情绪落点出现后自然结束。"],
		"production": ["做成一场小企划", "给素材套上一个简单清楚的节目形式，让整场直播更有结构。", "为素材建立一个容易理解的节目规则或验证流程。所有段落都服务同一形式，逐步产出可比较的结果，最后给出本场结论。"],
	}
	var values: Array = templates[String(approach_type)]
	return {
		"approach_id": "builtin_%s" % String(approach_type),
		"approach_type": String(approach_type),
		"display_name": str(values[0]),
		"display_description": str(values[1]),
		"director_prompt": "%s\n本场素材为《%s》。" % [str(values[2]), material.display_name],
	}


func _clear_approaches() -> void:
	_draft["approach_state"] = "idle"
	_draft["approach_cache_key"] = ""
	_draft["approaches"] = []
	_draft["selected_approach_id"] = ""


func _build_state_snapshot(material_instance_id: StringName) -> Dictionary:
	return {
		"day": GameState.day,
		"time_slot": GameState.time_slot,
		"streamer_level": GameState.streamer_level,
		"skill_levels": GameState.skill_levels.duplicate(true),
		"skill_experience": GameState.skill_experience.duplicate(true),
		"stress": GameState.stress,
		"otaku_desire": GameState.otaku_desire,
		"loneliness": GameState.loneliness,
		"fans": GameState.fans,
		"fan_vector": GameState.fan_vector.duplicate(true),
		"relationships": GameState.relationships.duplicate(true),
		"material_instance": get_material_instance(material_instance_id),
	}


func _record_history(plan: StreamPlanSnapshot, result: StreamSettlementResult) -> void:
	if _history_store == null:
		return
	var persona: StreamPersonaResource = CATALOG.get_persona(plan.persona_id)
	var material: LiveStreamMaterialResource = get_material_definition(plan.material_instance_id)
	var record: StreamSessionRecord = _history_store.create_completed_record({
		"title": plan.title,
		"persona_id": String(plan.persona_id),
		"persona_name": persona.display_name if persona != null else "",
		"material_name": material.display_name if material != null else "",
		"approach_name": str(plan.approach.get("display_name", "")),
		"approach_type": str(plan.approach.get("approach_type", "")),
	}, {
		"session_id": String(result.session_id),
		"day": int(plan.state_snapshot.get("day", GameState.day)),
		"time_slot": int(plan.state_snapshot.get("time_slot", GameState.time_slot)),
		"heat": result.peak_viewers,
		"revenue": result.revenue,
		"fan_delta": result.fan_delta,
		"stress_delta": result.stress_delta,
		"summary": _pending_summary,
	})
	if record != null:
		history_record_added.emit(record)
		history_changed.emit()


func _cancel_pending_transaction() -> void:
	if _pending_transaction_id.is_empty():
		return
	ActionTransactionManager.cancel(_pending_transaction_id)
	_pending_transaction_id = ""


func get_history_records() -> Array[StreamSessionRecord]:
	return _history_store.get_records() if _history_store != null else []


func get_latest_history_record() -> StreamSessionRecord:
	return _history_store.get_latest_record() if _history_store != null else null


func reset_history() -> void:
	if _history_store == null:
		return
	_history_store.reset_history()
	history_changed.emit()


func _ensure_persona_state() -> void:
	for persona: StreamPersonaResource in CATALOG.personas:
		if persona != null and not GameState.persona_progress.has(String(persona.content_id)):
			GameState.persona_progress[String(persona.content_id)] = {
				"proficiency": persona.initial_proficiency,
				"fixation": persona.initial_fixation,
			}
	if GameState.active_persona_id.is_empty() or get_active_persona() == null:
		GameState.active_persona_id = "persona_default"
		if get_active_persona() == null and not CATALOG.personas.is_empty():
			GameState.active_persona_id = String(CATALOG.personas[0].content_id)


func _connect_material_inventory() -> void:
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	if material_manager != null and not material_manager.inventory_changed.is_connected(_on_inventory_changed):
		material_manager.inventory_changed.connect(_on_inventory_changed)


func _on_streamer_progress_changed(_level: int, _exp: int, _points: int) -> void:
	if not str(_draft.get("material_instance_id", "")).is_empty():
		_prepare_builtin_approaches()


func _on_persona_changed(_old_persona_id: String, _new_persona_id: String) -> void:
	_draft["persona_id"] = GameState.active_persona_id
	if not str(_draft.get("material_instance_id", "")).is_empty():
		_prepare_builtin_approaches()
	else:
		_emit_draft_changed()


func _on_inventory_changed() -> void:
	if not str(_draft.get("material_instance_id", "")).is_empty() and get_material_instance().is_empty():
		_draft["material_instance_id"] = ""
		_clear_approaches()
	catalogs_changed.emit()
	_emit_draft_changed()
