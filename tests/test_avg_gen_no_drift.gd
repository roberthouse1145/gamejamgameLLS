extends Node
## 端到端测试：日常约会场景 + 满 KB → 验证 LLM 不漂移到项目话题
##
## 设计意图：
##   - KB 中塞入完整项目设定（EchoForge / 尤里安 / 梅露 / 塞拉菲娜学院等）
##   - Session 是纯日常约会（学校南门小广场散步），activity_hint 不暗示项目
##   - 期望 LLM 判定为「日常场景」→ 不调 kb_read / 不让台词触及项目内容
##   - 通过关键词扫描 outline，确认 KB 关键词全部缺席

const AVGSceneGeneratorClass = preload("res://scripts/activity/avg_scene_generator.gd")
const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")

const TEST_SESSION_ID: String = "test_no_drift_001"
const RESULT_TIMEOUT_MS: int = 180000

## 这些词在日常约会的 outline 里出现 = 项目漂移 = 测试失败
const PROJECT_DRIFT_KEYWORDS: Array[String] = [
	"EchoForge",
	"回响铸造",
	"尤里安",
	"梅露",
	"塞拉菲娜",
	"魔法学院",
	"禁书库",
	"回响之书",
	"节拍咏唱",
	"4/4 拍",
	"切分音",
	"光属性",
	"暗属性",
	"Demo",
]

var _generator: Node = null
var _writer_service: Node = null
var _original_docs: Array = []
var _tool_calls: Array = []
var _scene_outcome: String = ""
var _scene_error: String = ""
var _scene_outline: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		print("[FAIL] KnowledgeBaseManager autoload not found")
		return

	_original_docs = kb.documents.duplicate(true)
	kb.documents.clear()
	await get_tree().process_frame
	_seed_full_project_kb(kb)

	_generator = AVGSceneGeneratorClass.new()
	_generator.name = "TestAVGGeneratorNoDrift"
	add_child(_generator)
	await get_tree().process_frame
	await get_tree().process_frame

	if not _generator.is_available():
		print("[FAIL] AVGSceneGenerator not available")
		_restore_kb(kb)
		return

	_writer_service = _generator._writer_service
	_writer_service.tool_executed.connect(_on_writer_tool_executed)
	_generator.scene_generated.connect(_on_scene_generated)
	_generator.scene_failed.connect(_on_scene_failed)

	var session: Dictionary = _build_daily_date_session()
	var ok: bool = bool(_generator.generate_for_session(TEST_SESSION_ID, session))
	print("[Test] generate_for_session returned: %s" % str(ok))
	if not ok:
		_restore_kb(kb)
		return

	var deadline: int = Time.get_ticks_msec() + RESULT_TIMEOUT_MS
	while _scene_outcome.is_empty():
		if Time.get_ticks_msec() > deadline:
			print("[TIMEOUT] 等待超时")
			_scene_outcome = "timeout"
			break
		await get_tree().process_frame

	# ===== 漂移检测 =====
	print("\n========== 漂移关键词扫描 ==========")
	var drift_hits: Array[String] = []
	if not _scene_outline.is_empty():
		for keyword in PROJECT_DRIFT_KEYWORDS:
			if _scene_outline.contains(keyword):
				drift_hits.append(keyword)

	if drift_hits.is_empty():
		print("[OK] 日常约会场景中未出现任何项目相关关键词 — 抗漂移成功 ✓")
	else:
		print("[FAIL] 检测到项目漂移！LLM 在日常约会里编造/引用了项目内容：")
		for k in drift_hits:
			print("  - %s" % k)

	print("\n========== 工具调用记录 ==========")
	if _tool_calls.is_empty():
		print("[OK] 0 次 kb_read 调用 — LLM 正确识别日常场景不需要查 KB ✓")
	else:
		print("[INFO] LLM 调用了 %d 次 kb_read（日常场景理想为 0 次，但允许少量探索）" % _tool_calls.size())
		for i in _tool_calls.size():
			var tc: Dictionary = _tool_calls[i]
			print("  [%d] %s(%s)" % [i, tc.get("name", ""), JSON.stringify(tc.get("args", {}))])

	print("\n========== DSL 状态 ==========")
	print("scene_outcome: %s" % _scene_outcome)
	if not _scene_error.is_empty():
		print("scene_error: %s" % _scene_error)

	_restore_kb(kb)
	print("\n[DONE] 请通过 mcp_godot_mcp_stop_project 手动停止。")


func _seed_full_project_kb(kb: Node) -> void:
	# 故意塞满项目设定——验证 LLM 不会被诱惑写进日常对话
	kb.upsert_document("project_meta", "项目元信息：EchoForge",
		"项目代号「EchoForge」（中文暂定「回响铸造」）。融合节奏与角色养成的视觉小说+音游。",
		"world", ["项目元信息"])
	kb.upsert_document("char_yulian", "尤里安（男主）",
		"塞拉菲娜学院王子学员。高傲冷漠，魔法属性「光」，节拍模式偏 4/4 拍。",
		"characters", ["主角"])
	kb.upsert_document("char_melu", "梅露（女主）",
		"平民出身特招生，能感知禁书库封印波动。魔法属性「暗」，节拍偏切分音。",
		"characters", ["主角"])
	kb.upsert_document("world_academy", "塞拉菲娜王立魔法学院",
		"项目主舞台。北方雪山脚下，地下三层禁书库藏着「回响之书」。",
		"world", ["世界观"])
	kb.upsert_document("gameplay_core", "核心玩法：节拍咏唱",
		"玩家通过点击/长按节奏轨道触发法术。Demo 中包含 3 首演示曲目。",
		"story", ["玩法"])
	print("[SEED] full project KB loaded: %d docs" % kb.documents.size())


func _build_daily_date_session() -> Dictionary:
	# 故意写纯日常的 hint，不留任何项目暗示
	return {
		"event_id": "lab_park_walk",
		"entry_id": "lab_park_walk",
		"location_id": "lab_park",
		"location": {
			"location_id": "lab_park",
			"title": "学校南门小广场",
			"location_title": "学校南门小广场",
			"subtitle": "傍晚的银杏树下",
			"description": "校园南侧的开放小广场，晚饭前的悠闲时光。",
			"detail_prompt": "傍晚 5 点左右，金色光线斜照在地砖上。",
			# 关键：activity_hint 不提任何项目相关，只是日常
			"activity_hint": "随意散步聊天，看路过的猫，吐槽食堂的菜，享受这种没事干的下午。",
			"base_activity": "在小广场上找张长椅坐着，慢慢消磨晚饭前的时间。",
		},
		"rewards": {},
		"start_day": 4,
		"phase_after_action": "AFTERNOON",
		"scene_window_title": "约会中：学校南门",
		"activity_type": "date",
		"important_event_available": false,
		"important_event_active": false,
	}


func _on_writer_tool_executed(_request_id: String, tool_name: String, args: Dictionary, _result: Variant, _tool_call_id: String) -> void:
	_tool_calls.append({"name": tool_name, "args": args})
	print("\n[TOOL CALL #%d] %s(%s)" % [_tool_calls.size(), tool_name, JSON.stringify(args)])


func _on_scene_generated(_session_id: String, package: Dictionary) -> void:
	_scene_outcome = "ok"
	_scene_outline = str(package.get("scene_outline", "")).strip_edges()
	print("\n[SCENE GENERATED] outline length=%d" % _scene_outline.length())
	if not _scene_outline.is_empty():
		print("[OUTLINE FULL]")
		print(_scene_outline)


func _on_scene_failed(_session_id: String, error: String) -> void:
	_scene_outcome = "fail"
	_scene_error = error
	print("\n[SCENE FAILED] %s" % error)


func _restore_kb(kb: Node) -> void:
	if kb != null:
		kb.documents = _original_docs.duplicate(true)
		print("[RESTORE] KB restored")
