extends Node
## 端到端测试：AVG 场景生成 + 伪造 KB
##
## 验证两件事：
##   1. 系统 prompt 中 {{project_shared_context}} 段被正确注入（开发循环 + 工单 + KB 索引）
##   2. AVG 生成 LLM 在生成 DSL 前能主动调 kb_read 取 KB 文档全文
##
## 注意：
##   - 真实调用 LLM API（DeepSeek），需要 ai_config.cfg 配置好
##   - 测试结束不自动退出，请人工 review 输出后通过 stop_project 停止

const AVGSceneGeneratorClass = preload("res://scripts/activity/avg_scene_generator.gd")
const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")

const TEST_SESSION_ID: String = "test_avg_gen_session_001"
const RESULT_TIMEOUT_MS: int = 120000

var _generator: Node = null
var _writer_service: Node = null
var _original_docs: Array = []
var _tool_calls: Array = []
var _scene_outcome: String = ""
var _scene_error: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		print("[FAIL] KnowledgeBaseManager autoload not found")
		return

	# 备份运行时 KB 并用伪造数据替换
	_original_docs = kb.documents.duplicate(true)
	kb.documents.clear()
	await get_tree().process_frame
	_seed_fake_kb(kb)

	# 实例化 generator
	_generator = AVGSceneGeneratorClass.new()
	_generator.name = "TestAVGSceneGenerator"
	add_child(_generator)
	await get_tree().process_frame
	await get_tree().process_frame

	if not _generator.is_available():
		print("[FAIL] AVGSceneGenerator not available (check ai_config.cfg)")
		_restore_kb(kb)
		return

	_writer_service = _generator._writer_service
	if _writer_service == null:
		print("[FAIL] _writer_service not initialized")
		_restore_kb(kb)
		return

	_writer_service.tool_executed.connect(_on_writer_tool_executed)
	_generator.scene_generated.connect(_on_scene_generated)
	_generator.scene_failed.connect(_on_scene_failed)

	# 打印一次 project_shared_context 让人能直观看到注入的内容
	print("\n========== Injected {{project_shared_context}} ==========")
	print(AVGScenePromptBuilderClass.build_avg_project_shared_context())
	print("=========================================================\n")

	var session: Dictionary = _build_test_session()
	var ok: bool = bool(_generator.generate_for_session(TEST_SESSION_ID, session))
	print("[Test] generate_for_session returned: %s" % str(ok))
	if not ok:
		_restore_kb(kb)
		return

	# 等结果
	var deadline: int = Time.get_ticks_msec() + RESULT_TIMEOUT_MS
	while _scene_outcome.is_empty():
		if Time.get_ticks_msec() > deadline:
			print("[TIMEOUT] 等待 scene_generated/scene_failed 超时（%d ms）" % RESULT_TIMEOUT_MS)
			_scene_outcome = "timeout"
			break
		await get_tree().process_frame

	# 总结
	print("\n========== 测试总结 ==========")
	print("scene_outcome: %s" % _scene_outcome)
	if not _scene_error.is_empty():
		print("scene_error: %s" % _scene_error)
	print("工具调用次数: %d" % _tool_calls.size())
	for i in _tool_calls.size():
		var tc: Dictionary = _tool_calls[i]
		print("  [%d] %s(%s)" % [i, tc.get("name", ""), JSON.stringify(tc.get("args", {}))])

	_restore_kb(kb)
	print("\n[DONE] 测试完成（KB 已还原）。请通过 mcp_godot_mcp_stop_project 手动停止。")


func _seed_fake_kb(kb: Node) -> void:
	# 5 篇假文档：覆盖 world / characters / story / notes 多类目
	kb.upsert_document(
		"world_academy",
		"塞拉菲娜王立魔法学院",
		"项目设定的核心舞台。学院位于北方雪山脚下，有六大魔法学派（火/水/风/土/光/暗）。禁书库位于学院地下三层，是第二幕的核心场景。",
		"world",
		["世界观", "学院"]
	)
	kb.upsert_document(
		"char_yulian",
		"尤里安（王子主角）",
		"项目的男主角。塞拉菲娜学院王子学员，外表高傲，对平民冷淡。内心其实是被王室期望压垮的少年——他真正想成为的是独立的炼金术研究者。",
		"characters",
		["主角", "王室"]
	)
	kb.upsert_document(
		"char_melu",
		"梅露（女主角）",
		"项目的女主角。平民出身的特招生，努力但常自我怀疑。她有感知禁书库封印波动的特殊体质——这是被招收的真正原因。",
		"characters",
		["主角", "平民"]
	)
	kb.upsert_document(
		"story_main",
		"主线剧情大纲",
		"第一幕：入学与试炼 → 第二幕：揭秘禁书库 → 第三幕：阶级冲突 → 双结局分支。当前重点放在第一幕的两位主角破冰部分。",
		"story",
		["主线"]
	)
	kb.upsert_document(
		"notes_open",
		"待确认问题",
		"梅露第一次施法的暴露程度还没定。是否要让尤里安在第一幕末尾就发现她的特殊体质，目前尚有争议。",
		"notes",
		["待确认"]
	)
	print("[SEED] fake KB documents loaded: %d" % kb.documents.size())


func _build_test_session() -> Dictionary:
	# 最小可用的 date session：date_prompt_builder 主要读 location / start_day / phase_after_action
	return {
		"event_id": "lab_park_walk",
		"entry_id": "lab_park_walk",
		"location_id": "lab_park",
		"location": {
			"location_id": "lab_park",
			"title": "学校南门小广场",
			"location_title": "学校南门小广场",
			"subtitle": "傍晚的银杏树下",
			"description": "校园南侧的开放小广场，紧邻教学楼，傍晚有不少学生坐在长椅上聊天。",
			"detail_prompt": "下午约 5 点，金色光线斜照在地砖上。",
			"activity_hint": "和女友随意散步聊天，可能会聊到最近的项目进度。",
			"base_activity": "在小广场上找个长椅坐着，聊聊最近的项目和学校的事。",
			"description_subtitle": "傍晚约会",
		},
		"rewards": {},
		"start_day": 5,
		"phase_after_action": "AFTERNOON",
		"scene_window_title": "约会中：学校南门",
		"activity_type": "date",
		"important_event_available": false,
		"important_event_active": false,
	}


func _on_writer_tool_executed(_request_id: String, tool_name: String, args: Dictionary, _result: Variant, _tool_call_id: String) -> void:
	_tool_calls.append({"name": tool_name, "args": args})
	print("\n[TOOL CALL] %s(%s)" % [tool_name, JSON.stringify(args)])


func _on_scene_generated(_session_id: String, package: Dictionary) -> void:
	_scene_outcome = "ok"
	var outline: String = str(package.get("scene_outline", "")).strip_edges()
	print("\n[SCENE GENERATED] outline length=%d" % outline.length())
	# 打印 outline 前 2000 字看 LLM 是否引用了 KB 内容
	if not outline.is_empty():
		print("[OUTLINE PREVIEW]")
		print(outline.substr(0, 2000))


func _on_scene_failed(_session_id: String, error: String) -> void:
	_scene_outcome = "fail"
	_scene_error = error
	print("\n[SCENE FAILED] %s" % error)


func _restore_kb(kb: Node) -> void:
	if kb != null:
		kb.documents = _original_docs.duplicate(true)
		print("[RESTORE] KB documents 已还原（共 %d 篇）" % kb.documents.size())
