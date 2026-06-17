extends Node
## 端到端测试：决赛答辩剧情场景 + 伪造 KB
##
## 设计意图：
##   - 强制场景必须依赖 KB 才能写得出来：林夏要在台上介绍「我们做的这个游戏」，
##     不查 KB 就不知道项目名/主角名/玩法核心。
##   - 期望 LLM 在生成 DSL 前主动调 kb_read 取多篇文档全文。
##   - 验证最终 DSL 是否包含 KB 内容（项目名、主角名、玩法描述等）且能解析通过。
##
## 注意：
##   - 真实调用 LLM API（DeepSeek），需要 ai_config.cfg 配置好
##   - 测试结束不自动退出，请人工 review 输出后通过 stop_project 停止

const AVGSceneGeneratorClass = preload("res://scripts/activity/avg_scene_generator.gd")
const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")

const TEST_SESSION_ID: String = "test_finals_pitch_001"
const RESULT_TIMEOUT_MS: int = 180000  # 3 分钟，给工具循环留余量

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

	# 备份运行时 KB 并用伪造数据替换
	_original_docs = kb.documents.duplicate(true)
	kb.documents.clear()
	await get_tree().process_frame
	_seed_finals_kb(kb)

	# 模拟项目已经临近交付：DevCycleManager 状态可以保持默认（无法直接 mock，
	# 但 system prompt 里 dev_cycle 会自然显示「Day 1 / 已完成 0」——
	# 这反而能凸显 LLM 是否会主动通过 kb_read 而非 dev_cycle 来理解项目）

	_generator = AVGSceneGeneratorClass.new()
	_generator.name = "TestAVGGeneratorFinals"
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

	print("\n========== Injected {{project_shared_context}} ==========")
	print(AVGScenePromptBuilderClass.build_avg_project_shared_context())
	print("=========================================================\n")

	var session := _build_finals_session()
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
	print("kb_read 工具调用次数: %d" % _tool_calls.size())
	for i in _tool_calls.size():
		var tc: Dictionary = _tool_calls[i]
		print("  [%d] %s(%s)" % [i, tc.get("name", ""), JSON.stringify(tc.get("args", {}))])

	# KB 内容检查：DSL outline 是否引用了 KB 里的关键词
	if not _scene_outline.is_empty():
		print("\n========== KB 引用检查 ==========")
		var checks: Array = [
			["项目名 EchoForge", _scene_outline.contains("EchoForge") or _scene_outline.contains("回响铸造") or _scene_outline.contains("回声铸造")],
			["主角 尤里安", _scene_outline.contains("尤里安")],
			["主角 梅露", _scene_outline.contains("梅露")],
			["世界观关键词 塞拉菲娜/魔法学院/禁书库", \
				_scene_outline.contains("塞拉菲娜") or _scene_outline.contains("魔法学院") or _scene_outline.contains("禁书库")],
			["玩法核心 节奏战斗/节拍/共鸣", \
				_scene_outline.contains("节奏") or _scene_outline.contains("节拍") or _scene_outline.contains("共鸣")],
		]
		for c in checks:
			print("  [%s] %s" % ["✓" if c[1] else "✗", c[0]])

	_restore_kb(kb)
	print("\n[DONE] 测试完成（KB 已还原）。请通过 mcp_godot_mcp_stop_project 手动停止。")


func _seed_finals_kb(kb: Node) -> void:
	# 项目元信息——LLM 没读这篇就不知道项目叫啥名
	kb.upsert_document(
		"project_meta",
		"项目元信息：EchoForge",
		"项目代号「EchoForge」（中文暂定「回响铸造」）。这是一款融合节奏与角色养成的视觉小说+音游。AGJ 2027 新星赛道参赛作品。Demo 版本预计 30-45 分钟流程。核心卖点：用音乐节拍演绎魔法咏唱，画风方向是手绘水彩混合赛博霓虹。",
		"world",
		["项目元信息", "Demo"]
	)
	# 世界观——LLM 没读这篇就不知道魔法学院、禁书库这些核心场景
	kb.upsert_document(
		"world_academy",
		"塞拉菲娜王立魔法学院",
		"项目主舞台。学院位于北方雪山脚下，存在六大魔法学派（火/水/风/土/光/暗）。学院地下三层是禁书库，是 Demo 后半段的核心场景——封印着「回响之书」，里面记载了远古魔法咏唱的失传节拍。",
		"world",
		["世界观", "学院"]
	)
	# 主角设定 1——男主
	kb.upsert_document(
		"char_yulian",
		"尤里安（男主）",
		"塞拉菲娜学院王子学员。表面高傲冷漠，对平民有偏见。真实人格是被王室期望压垮的少年——他真正想当独立的炼金术研究者。Demo 中是玩家可操控的初始角色，魔法属性「光」。",
		"characters",
		["主角", "王室", "可操控"]
	)
	# 主角设定 2——女主
	kb.upsert_document(
		"char_melu",
		"梅露（女主）",
		"项目女主角。平民出身的特招生，努力但常自我怀疑。她的特殊体质让她能感知禁书库封印波动——这是被招收的真正原因。Demo 第二幕解锁，魔法属性「暗」。",
		"characters",
		["主角", "平民", "可操控"]
	)
	# 核心玩法——LLM 没读这篇答辩时讲不出"游戏怎么玩"
	kb.upsert_document(
		"gameplay_core",
		"核心玩法：节拍咏唱",
		"战斗系统：玩家通过点击/长按节奏轨道触发法术。每个角色对应不同节拍模式（尤里安偏稳定 4/4 拍，梅露偏切分音）。Demo 中包含 3 首演示曲目，分别对应教学战、Boss 战、合作战（双角色同屏）。技术实现使用 Bass.gd 处理音轨同步。",
		"story",
		["玩法", "战斗系统"]
	)
	# 主线大纲
	kb.upsert_document(
		"story_main",
		"主线剧情大纲",
		"第一幕：尤里安入学被分到禁书库整理任务，意外触发封印共鸣。第二幕：梅露作为新生介入，两人发现各自体质都与「回响之书」有关。第三幕（Demo 结尾）：双人合作首次完整咏唱失传节拍。完整版规划三周目分支结局。",
		"story",
		["主线", "Demo 结构"]
	)
	# 提交状态——含若干已确认决策
	kb.upsert_document(
		"build_status",
		"Demo 提交状态备忘",
		"已完成：6 张主角立绘、3 首 BGM、第一幕完整剧本、3 张背景。进行中：节奏轨道 UI、Boss 战谱面。未开工：第三幕双角色同屏战斗、片尾 CG。预计提交日为比赛 Day 8 晚 23:59。",
		"notes",
		["进度", "Demo 提交"]
	)
	print("[SEED] finals KB documents loaded: %d" % kb.documents.size())


func _build_finals_session() -> Dictionary:
	# 关键设计：story_scene_prompt 描述答辩现场
	# story_guidance_prompt 强制要求引用项目设定 → 不查 KB 就写不出
	return {
		"activity_type": "story",
		"story_scene_title": "AGJ 2027 决赛答辩——上台介绍我们的游戏",
		"story_scene_prompt": "AGJ 2027 决赛现场。林夏作为团队代表上台答辩，向评委介绍我们做的这款 Demo。\n\n舞台环境：礼堂式答辩厅，台下坐着评委席（4-5 位评委）和其他参赛队伍。投影幕布上播放着我们做的游戏画面。林夏紧张但兴奋，玩家在台下席位看着她。\n\n叙事重点：林夏需要在 5 分钟答辩里讲清楚——\n1. 项目名称\n2. 玩法核心（这个 Demo 玩起来是什么样）\n3. 世界观与主要角色\n4. 项目的最大亮点\n\n林夏的语气：高能量但偶尔卡壳（这是她第一次站在这种舞台上）。她讲到自己设计的角色和玩法时会突然非常 sparkle、滔滔不绝；遇到必须用专业术语的地方（比如技术实现）会下意识看向台下的玩家求助。\n\n答辩中段必须包含至少一次：评委问问题（用 NPC TextBlock 表现）、林夏当场答上来或临时让玩家补充。\n\n场景以答辩结束、林夏走下台为收束。不要写颁奖、不要写后续 LinkChat。",
		"story_guidance_prompt": "硬性要求：林夏的发言必须**具体引用项目实际设定**——项目名、核心玩法机制、主角名字与设定、世界观。这些信息存在于知识库中，请通过 kb_read 工具按 doc_id 查阅项目设定文档后再写台词。\n\n禁止：林夏使用 \"我们的游戏\"、\"主角\"、\"这个角色\" 这种泛化指代——必须说出具体名字（项目代号 / 主角名 / 玩法术语）。\n\n评委提问的内容应当能问到 KB 里实际有的信息（比如\"为什么选择节奏机制\"、\"主角魔法属性怎么平衡\"等）。林夏的回答必须忠实于 KB。",
		"start_day": 8,
		"phase_after_action": "AFTERNOON",
		"scene_window_title": "决赛答辩：上台",
		"scene_project_prefix": "story_finals",
		"allow_branching": false,
		"include_chat_history": false,
	}


func _on_writer_tool_executed(_request_id: String, tool_name: String, args: Dictionary, result: Variant, _tool_call_id: String) -> void:
	_tool_calls.append({"name": tool_name, "args": args})
	print("\n[TOOL CALL #%d] %s(%s)" % [_tool_calls.size(), tool_name, JSON.stringify(args)])
	# 打印 result 前 400 字看 LLM 拿到了什么
	var result_preview: String = str(result).substr(0, 400)
	print("[TOOL RESULT] %s" % result_preview)


func _on_scene_generated(_session_id: String, package: Dictionary) -> void:
	_scene_outcome = "ok"
	var outline: String = str(package.get("scene_outline", "")).strip_edges()
	_scene_outline = outline
	print("\n[SCENE GENERATED] outline length=%d" % outline.length())
	if not outline.is_empty():
		print("[OUTLINE FULL]")
		print(outline)


func _on_scene_failed(_session_id: String, error: String) -> void:
	_scene_outcome = "fail"
	_scene_error = error
	print("\n[SCENE FAILED] %s" % error)


func _restore_kb(kb: Node) -> void:
	if kb != null:
		kb.documents = _original_docs.duplicate(true)
		print("[RESTORE] KB documents 已还原（共 %d 篇）" % kb.documents.size())
