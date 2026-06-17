extends Node

const ChatProjectContextBuilderClass = preload("res://scripts/chat/chat_project_context_builder.gd")
const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if kb == null or wom == null or dcm == null:
		print("[FAIL] LinkChat project context test missing required autoloads")
		return

	var lin: NPCCharacter = ChatManager.get_npc("npc_lin_xia")
	var mom: NPCCharacter = ChatManager.get_npc("npc_mom")
	if lin == null or mom == null:
		print("[FAIL] LinkChat project context test missing NPC resources")
		return

	var original_docs: Array = kb.documents.duplicate(true)
	var original_task_pool: Dictionary = dcm.get("_task_pool").duplicate(true)
	var original_completed_ids: Array = dcm.get("_completed_task_ids").duplicate(true)

	if wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()
	if dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	kb.documents.clear()
	await get_tree().process_frame

	kb.upsert_document(
		"world_magic_rules",
		"学院魔法规则底稿",
		"魔法使用需要通过学院徽章登记，禁书库相关魔法只能在导师许可下调阅。",
		"world"
	)
	kb.upsert_document(
		"char_protagonist",
		"主角角色设定",
		"主角是魔法学院优等生，同时经营虚拟主播身份，对外冷静，对内有强迫式自我要求。",
		"characters"
	)
	kb.upsert_document(
		"story_opening",
		"第一章开场节拍",
		"开场先让主角在直播事故后收到禁书库邀请，再把林夏的正式出场压在第一幕尾声。",
		"story"
	)
	kb.upsert_document(
		"notes_open_questions",
		"待确认问题",
		"还没决定女主第一次暴露真实能力时应该更危险还是更暧昧。",
		"notes"
	)

	var order: Resource = wom.create_order("整理主角角色设定文档", "根据现有共识补完主角角色设定。")
	order.priority = 3
	order.status = "in_progress"
	order.surface_status = "in_progress"
	order.inner_status = "generating"
	order.updated_at = int(Time.get_unix_time_from_system())

	dcm.set("_task_pool", {
		"seed_discuss_hook": {
			"task_id": "seed_discuss_hook",
			"title": "讨论第一幕最先抓人的情绪钩子",
			"status": "available",
			"task_type": "chat_topic",
			"weight": 10,
		},
		"seed_write_profile": {
			"task_id": "seed_write_profile",
			"title": "撰写主角角色设定文档",
			"status": "available",
			"task_type": "minigame",
			"minigame_type": "typing_code",
			"weight": 8,
			"post_task_work_order": {
				"title": "撰写主角角色设定文档",
				"description": "根据现有讨论补完主角角色设定。",
				"performance_context": "summary"
			},
		},
	})
	dcm.set("_completed_task_ids", [])

	var access_ok: bool = bool(lin.can_access_project_context()) and not bool(mom.can_access_project_context())
	if not access_ok:
		print("[FAIL] NPC project context permission flags are wrong")
		_cleanup_test_state(kb, wom, dcm, original_docs, original_task_pool, original_completed_ids)
		return
	print("[OK] NPC project context permission flags distinguish collaborator and normal chat target")

	# 不传 scan_text → 命中段为空，索引段必出
	var lin_context: String = str(ChatManager._build_project_context_for_chat(lin)).strip_edges()
	var mom_context: String = str(ChatManager._build_project_context_for_chat(mom)).strip_edges()
	var context_ok: bool = lin_context.contains("开发循环") \
		and lin_context.contains("工单状态") \
		and lin_context.contains("项目设定索引") \
		and lin_context.contains("整理主角角色设定文档") \
		and lin_context.contains("world_magic_rules") \
		and lin_context.contains("学院魔法规则底稿") \
		and not lin_context.contains("当前对话相关条目") \
		and mom_context.is_empty()
	if not context_ok:
		print("[FAIL] ChatManager should only build project context for collaborator NPCs")
		print("  lin_context: %s" % lin_context)
		print("  mom_context: %s" % mom_context)
		_cleanup_test_state(kb, wom, dcm, original_docs, original_task_pool, original_completed_ids)
		return
	print("[OK] ChatManager only exposes project context to collaborator NPCs (index-only when scan_text empty)")

	var builder := ChatProjectContextBuilderClass.new()
	var builder_context: String = str(builder.build_for_chat(lin)).strip_edges()
	var builder_ok: bool = builder_context.contains("开发循环") \
		and builder_context.contains("工单状态") \
		and builder_context.contains("项目设定索引") \
		and builder_context.contains("world_magic_rules")
	if not builder_ok:
		print("[FAIL] ChatProjectContextBuilder direct usage regression")
		print("  builder_context: %s" % builder_context)
		_cleanup_test_state(kb, wom, dcm, original_docs, original_task_pool, original_completed_ids)
		return
	print("[OK] ChatProjectContextBuilder direct usage keeps collaborator context independent")

	var lin_channel := ChatChannelClass.new()
	lin_channel.channel_id = "dm_lin_xia"
	lin_channel.display_name = "林夏"
	lin_channel.members = ["player", "npc_lin_xia"]

	var lin_prompt_data := ChatPromptBuilder.build(
		lin_channel,
		[lin],
		[],
		["最近项目进度怎么样"],
		[],
		null,
		lin_context
	)
	var lin_messages: Array = lin_prompt_data.get("messages", [])
	var lin_system_prompt: String = ""
	if not lin_messages.is_empty() and lin_messages[0] is Dictionary:
		lin_system_prompt = str((lin_messages[0] as Dictionary).get("content", ""))

	var prompt_ok: bool = lin_system_prompt.contains("项目共享上下文") \
		and lin_system_prompt.contains("整理主角角色设定文档") \
		and lin_system_prompt.contains("主角角色设定")
	if not prompt_ok:
		print("[FAIL] Collaborator prompt should include injected project context")
		print("  lin_system_prompt: %s" % lin_system_prompt)
		_cleanup_test_state(kb, wom, dcm, original_docs, original_task_pool, original_completed_ids)
		return
	print("[OK] Collaborator LinkChat prompt includes project context")

	var mom_channel := ChatChannelClass.new()
	mom_channel.channel_id = "dm_mom"
	mom_channel.display_name = "妈妈"
	mom_channel.members = ["player", "npc_mom"]

	var mom_prompt_data := ChatPromptBuilder.build(
		mom_channel,
		[mom],
		[],
		["我最近在忙比赛"],
		[],
		null,
		mom_context
	)
	var mom_messages: Array = mom_prompt_data.get("messages", [])
	var mom_system_prompt: String = ""
	if not mom_messages.is_empty() and mom_messages[0] is Dictionary:
		mom_system_prompt = str((mom_messages[0] as Dictionary).get("content", ""))

	var mom_prompt_ok: bool = mom_system_prompt.contains("当前角色没有额外的项目共享上下文") \
		and not mom_system_prompt.contains("整理主角角色设定文档")
	if not mom_prompt_ok:
		print("[FAIL] Normal NPC prompt should not receive project context")
		print("  mom_system_prompt: %s" % mom_system_prompt)
		_cleanup_test_state(kb, wom, dcm, original_docs, original_task_pool, original_completed_ids)
		return
	print("[OK] Normal NPC LinkChat prompt keeps project context sealed off")

	_cleanup_test_state(kb, wom, dcm, original_docs, original_task_pool, original_completed_ids)
	print("[Test] LinkChat project context tests ready")


func _cleanup_test_state(
	kb: Node,
	wom: Node,
	dcm: Node,
	original_docs: Array,
	original_task_pool: Dictionary,
	original_completed_ids: Array
) -> void:
	if kb != null:
		kb.documents = original_docs.duplicate(true)
	if wom != null and wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()
	if dcm != null:
		dcm.set("_task_pool", original_task_pool.duplicate(true))
		dcm.set("_completed_task_ids", original_completed_ids.duplicate(true))
