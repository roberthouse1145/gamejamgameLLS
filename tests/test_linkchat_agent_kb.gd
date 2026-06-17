extends Node
## 端到端测试：LinkChat 协作者 Agent + 伪造 KB
##
## 目的（不做断言通过/失败，重点是 print 出来给人工 review）：
##   1. 伪造一个项目 KB（5 篇文档），观察 system prompt 中 KB 段实际形态
##   2. 验证「被动注入」：玩家消息含命中关键词时，命中段直接给完整 content
##   3. 验证「主动调用」：玩家消息只命中索引但没命中关键词时，LLM 是否会
##      自主调用 kb_read(doc_id=...) 取全文
##
## 注意：
##   - 此测试会真实调用 LLM API，需要 ai_config.cfg 已配置好
##   - 测试结束后会还原 KB（通过 ChatManager 走 collaborator_agent 路径，
##     不污染主项目 KB 文件，只改运行时 documents 数组）
##   - 测试不会自动退出，请人工 review 输出后通过 stop_project 停止

const ChatProjectContextBuilderClass = preload("res://scripts/chat/chat_project_context_builder.gd")
const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")

const CASE_TIMEOUT_SECONDS: float = 60.0
const INTER_CASE_DELAY: float = 1.5

var _agent: Node = null
var _original_docs: Array = []


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	var lin: NPCCharacter = ChatManager.get_npc("npc_lin_xia") if Engine.has_singleton("ChatManager") or get_node_or_null("/root/ChatManager") else null
	if lin == null:
		lin = ChatManager.get_npc("npc_lin_xia")
	if kb == null or lin == null:
		print("[FAIL] missing KnowledgeBaseManager or npc_lin_xia")
		return

	_agent = ChatManager.collaborator_agent
	if _agent == null or not is_instance_valid(_agent):
		print("[FAIL] CollaboratorChatAgent not initialized")
		return

	# 备份运行时 KB（不动磁盘文件）
	_original_docs = kb.documents.duplicate(true)
	kb.documents.clear()
	await get_tree().process_frame
	_seed_fake_kb(kb)

	var lin_channel := ChatChannelClass.new()
	lin_channel.channel_id = "dm_lin_xia"
	lin_channel.display_name = "林夏"
	lin_channel.members = ["player", "npc_lin_xia"]

	# Case A：玩家消息直接命中 char_yulian 的 title「尤里安」
	# 期望：命中段含 char_yulian 完整 content，LLM 不需要调 kb_read
	await _run_case(
		"A",
		"命中 title『尤里安』→ 应只走被动注入，无需 kb_read",
		lin_channel,
		lin,
		"尤里安这个角色我感觉还需要再打磨一下，你怎么看？"
	)

	await get_tree().create_timer(INTER_CASE_DELAY).timeout

	# Case B：玩家消息不命中任何 title/tag，但答案在 hidden_secret 里
	# 期望：命中段空，LLM 应根据索引主动 kb_read(doc_id="hidden_secret")
	await _run_case(
		"B",
		"命中段空 + 索引可见 hidden_secret → 期望 LLM 主动 kb_read",
		lin_channel,
		lin,
		"我有点想不起来主角的生母到底是什么背景了，你能帮我捋一下吗？"
	)

	# 还原运行时 KB
	kb.documents = _original_docs.duplicate(true)
	print("\n[RESTORE] KB documents 已还原（共 %d 篇）" % kb.documents.size())
	print("[DONE] 测试完毕。请通过 mcp_godot_mcp_stop_project 手动停止。")


func _seed_fake_kb(kb: Node) -> void:
	kb.upsert_document(
		"char_yulian",
		"尤里安",
		"尤里安是塞拉菲娜学院的王子学员，外表高傲，对平民学生态度冷淡。但内心其实是一个被王室期望压垮的少年——他真正想成为的是一个独立的炼金术研究者，而不是继承王位。",
		"characters",
		["主角", "王室"]
	)
	kb.upsert_document(
		"char_melu",
		"梅露",
		"梅露是平民出身的学院特招生，努力但常常自我怀疑。她的特殊体质让她能感知禁书库的封印波动，这是她被招收的真正原因。",
		"characters",
		["主角", "平民"]
	)
	kb.upsert_document(
		"world_academy",
		"塞拉菲娜王立魔法学院",
		"六大魔法属性体系（火/水/风/土/光/暗）。禁书库位于学院地下三层，只有院长持有钥匙。",
		"world",
		["世界观", "学院"]
	)
	kb.upsert_document(
		"story_main",
		"主线剧情大纲",
		"第一幕：入学与试炼 → 第二幕：揭秘禁书库 → 第三幕：阶级冲突爆发 → 双结局分支。",
		"story",
		["主线"]
	)
	# 关键测试文档：title/tag 都不会被「母亲/生母/背景」这类词命中，
	# 但 LLM 在索引里能看到 [story] [doc_id=hidden_secret] 深层秘密 (tags: 机密/二幕)
	kb.upsert_document(
		"hidden_secret",
		"深层秘密",
		"主角的生母实际上是禁书库的最后一位守护者。她当年为保护尚在襁褓中的主角隐姓埋名、流落民间。这是第二幕中段的核心反转——主角入学时偶然触发的封印共鸣，正是她血脉中残存的守护契约在召唤。",
		"story",
		["机密", "二幕"]
	)
	print("[SEED] fake KB documents loaded: %d" % kb.documents.size())


func _run_case(case_id: String, description: String, channel, lin, player_message: String) -> void:
	print("\n========================== Case %s ==========================" % case_id)
	print("说明：%s" % description)
	print("玩家消息：%s" % player_message)
	print("------------------------------------------------------------")

	# ---- 构建 prompt ----
	var scan_text: String = ChatProjectContextBuilderClass.build_chat_scan_text(
		[] as Array[Dictionary],
		[player_message] as Array[String],
		null
	)
	var project_shared_context: String = ChatManager._build_project_context_for_chat(lin, scan_text)

	var prompt_data: Dictionary = ChatPromptBuilder.build(
		channel,
		[lin],
		[] as Array[Dictionary],
		[player_message] as Array[String],
		[],
		null,
		project_shared_context,
	)
	var messages: Array = prompt_data.get("messages", [])
	if messages.size() < 2:
		print("[FAIL] prompt build failed")
		return

	var system_prompt: String = str((messages[0] as Dictionary).get("content", ""))
	var user_prompt: String = str((messages[1] as Dictionary).get("content", ""))

	# ---- 打印 KB 相关段落 ----
	_print_kb_section(system_prompt)

	# ---- 监听工具调用 ----
	var tool_calls: Array = []
	var tool_callback := func(_req_id: String, tool_name: String, args: Dictionary, result: Variant, _tcid: String) -> void:
		tool_calls.append({"name": tool_name, "args": args})
		print("\n[TOOL CALL] %s(%s)" % [tool_name, JSON.stringify(args)])
		print("[TOOL RESULT] %s" % str(result).substr(0, 600))
	_agent.tool_executed.connect(tool_callback)

	# ---- 发送 ----
	_agent.reset()
	_agent.set_system_prompt_override(system_prompt)
	var request_id: String = _agent.send_message(user_prompt)
	print("\n[REQUEST_ID] %s" % request_id)
	if request_id.is_empty():
		print("[FAIL] send_message returned empty")
		_agent.tool_executed.disconnect(tool_callback)
		return

	# ---- 等待完成 ----
	var outcome: Dictionary = await _wait_for_agent_completion()
	if _agent.tool_executed.is_connected(tool_callback):
		_agent.tool_executed.disconnect(tool_callback)

	print("\n[RESULT] tool_calls=%d, status=%s" % [tool_calls.size(), outcome.get("status", "?")])
	if outcome.get("status", "") == "ok":
		print("[FINAL REPLY]\n%s" % str(outcome.get("content", "")))
	else:
		print("[ERROR] %s" % str(outcome.get("error", outcome.get("content", ""))))


func _print_kb_section(system_prompt: String) -> void:
	var kb_idx_start: int = system_prompt.find("### 项目设定索引")
	if kb_idx_start < 0:
		print("[SYSTEM PROMPT — KB 部分] (未找到「### 项目设定索引」段)")
		return
	# 截到下一个一级或二级标题
	var search_from: int = kb_idx_start + 5
	var next_h2: int = system_prompt.find("\n## ", search_from)
	if next_h2 < 0:
		next_h2 = system_prompt.length()
	var snippet: String = system_prompt.substr(kb_idx_start, next_h2 - kb_idx_start).strip_edges()
	print("[SYSTEM PROMPT — KB 部分]")
	print(snippet)


func _wait_for_agent_completion() -> Dictionary:
	var outcome: Dictionary = {"done": false, "status": "", "content": "", "error": ""}

	var on_completed := func(_request_id: String, content: String) -> void:
		if outcome["done"]:
			return
		outcome["done"] = true
		outcome["status"] = "ok"
		outcome["content"] = content

	var on_failed := func(_request_id: String, error: String) -> void:
		if outcome["done"]:
			return
		outcome["done"] = true
		outcome["status"] = "fail"
		outcome["error"] = error

	_agent.message_completed.connect(on_completed)
	_agent.message_failed.connect(on_failed)

	var timer: SceneTreeTimer = get_tree().create_timer(CASE_TIMEOUT_SECONDS)
	while not outcome["done"]:
		if timer.time_left <= 0.0:
			outcome["done"] = true
			outcome["status"] = "timeout"
			outcome["error"] = "等待 agent 完成超时（%.0f 秒）" % CASE_TIMEOUT_SECONDS
			break
		await get_tree().process_frame

	if _agent.message_completed.is_connected(on_completed):
		_agent.message_completed.disconnect(on_completed)
	if _agent.message_failed.is_connected(on_failed):
		_agent.message_failed.disconnect(on_failed)
	return outcome
