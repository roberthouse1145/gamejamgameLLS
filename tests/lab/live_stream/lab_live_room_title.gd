extends Node
## 真实 LLM 直播间标题实验：只调用标题阶段，对比不同素材是否生成持续成立的房间名。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")
const PERSONA_ID: StringName = &"persona_default"

var _cases: Array[Dictionary] = [
	{
		"id": "cozy_game",
		"material_id": &"material_cozy_game",
		"approach": {"approach_id": "cozy_analysis", "approach_type": "analysis", "display_name": "沿着岛上的细节慢慢逛", "display_description": "边逛边聊清楚岛上的生活细节。", "director_prompt": "沿着岛上几个具体细节推进探索和讨论。"},
		"history_title": "第一次登上悠闲岛",
		"history_summary": "上次在悠闲岛河边钓到蓝鳟鱼，并把它放进了仓库。",
	},
	{
		"id": "midnight_song",
		"material_id": &"material_midnight_setlist",
		"approach": {"approach_id": "song_performance", "approach_type": "performance", "display_name": "唱一场慢慢打开的深夜歌回", "display_description": "让歌声从克制逐渐走向温暖。", "director_prompt": "用演唱完成一条从克制到释放的情绪弧线。"},
	},
	{
		"id": "forum_talk",
		"material_id": &"material_forum_hot_meme",
		"approach": {"approach_id": "forum_analysis", "approach_type": "analysis", "display_name": "现场把热梗上下文扒清楚", "display_description": "看图、比对回复并验证说法。", "director_prompt": "围绕截屏中的矛盾细节逐步验证说法。"},
	},
]
var _case_index: int = 0
var _service: AIService = null
var _generator: LiveShowGenerator = null
var _pending_request_id: String = ""


func _ready() -> void:
	_service = AIService.new()
	_service.name = "LabLiveRoomTitleService"
	add_child(_service)
	_service.request_completed.connect(_on_request_completed)
	_service.request_failed.connect(_on_request_failed)
	if not AIConfigManager.get_instance().apply_to_service(_service, "chat_default"):
		print("LAB_LIVE_ROOM_TITLE_ALL_DONE ok=0 reason=llm_unavailable")
		return
	call_deferred("_run_next_case")


func _run_next_case() -> void:
	if _case_index >= _cases.size():
		print("LAB_LIVE_ROOM_TITLE_ALL_DONE ok=1 cases=%d" % _cases.size())
		return
	var case_data: Dictionary = _cases[_case_index]
	GameState.stream_history.clear()
	var history_summary: String = str(case_data.get("history_summary", "")).strip_edges()
	if not history_summary.is_empty():
		GameState.stream_history.append({
			"session_id": "lab_room_title_history",
			"day": 1,
			"title": str(case_data.get("history_title", "")),
			"persona_id": String(PERSONA_ID),
			"summary": history_summary,
		})
	var material_id: StringName = StringName(str(case_data.get("material_id", "")))
	var material: LiveStreamMaterialResource = CATALOG.get_material(material_id)
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	if material == null or persona == null:
		print("LAB_LIVE_ROOM_TITLE_ALL_DONE ok=0 reason=missing_content case=%s" % case_data.get("id", ""))
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = StringName("lab_room_title_%s" % case_data.get("id", ""))
	plan.title = material.display_name
	plan.persona_id = PERSONA_ID
	plan.approach = (case_data.get("approach", {}) as Dictionary).duplicate(true)
	plan.state_snapshot = {
		"material_instance": {"definition_id": String(material_id)},
	}
	_generator = GENERATOR_SCRIPT.new()
	add_child(_generator)
	_generator.setup(plan, null, CATALOG, persona.model)
	var prompt: String = _generator._build_title_prompt()
	print("LAB_LIVE_ROOM_TITLE_PROMPT case=%s\n%s" % [case_data.get("id", ""), prompt])
	_pending_request_id = _service.chat_simple(prompt, GENERATOR_SCRIPT.TITLE_SYSTEM_PROMPT, {
		"temperature": 0.85,
		"max_tokens": 128,
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
	})


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_request_id or _generator == null:
		return
	_pending_request_id = ""
	var raw_title: String = AIService.extract_content(response)
	var validation: Dictionary = _generator._validate_title(raw_title)
	print("LAB_LIVE_ROOM_TITLE_RESULT case=%s valid=%s title=%s" % [
		_cases[_case_index].get("id", ""),
		str(validation.get("success", false)),
		JSON.stringify(str(validation.get("title", raw_title))),
	])
	_finish_case()


func _on_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _pending_request_id:
		return
	print("LAB_LIVE_ROOM_TITLE_ALL_DONE ok=0 reason=request_failed case=%s error=%s" % [
		_cases[_case_index].get("id", ""),
		error,
	])


func _finish_case() -> void:
	if _generator != null:
		_generator.queue_free()
		_generator = null
	_case_index += 1
	call_deferred("_run_next_case")
