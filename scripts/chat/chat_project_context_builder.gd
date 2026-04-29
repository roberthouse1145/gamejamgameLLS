class_name ChatProjectContextBuilder extends RefCounted
## LinkChat 协作者项目上下文构建器

const AVGDevWorkOrderToolsClass = preload("res://scripts/avg/dev_tools/work_order_tools.gd")
const NPCCharacterClass = preload("res://scripts/chat/resources/npc_character.gd")


func build_for_channel(_channel: Resource, npcs: Array) -> String:
	if npcs.size() != 1:
		return ""
	return build_for_chat(npcs[0])


func build_for_chat(raw_npc: Variant) -> String:
	var npc = _resolve_npc(raw_npc)
	if npc == null or not npc.can_access_project_context():
		return ""

	var sections: PackedStringArray = [
		"## 项目共享上下文",
		"你是这个项目的协作搭档，可以参考以下只读摘要来回答玩家关于当前开发进度、已有设定和后台工单的问题。",
		"如果摘要不够用，可以调用只读工具进一步确认；不要把这里没有的信息说成既定事实。",
	]

	var dev_cycle_summary := build_dev_cycle_context()
	if not dev_cycle_summary.is_empty():
		sections.append("### 开发循环\n%s" % dev_cycle_summary)

	var work_order_summary := build_work_order_context()
	if not work_order_summary.is_empty():
		sections.append("### 工单状态\n%s" % work_order_summary)

	var kb_summary := build_kb_context()
	if not kb_summary.is_empty():
		sections.append("### 知识库摘要\n%s" % kb_summary)

	return "\n\n".join(sections).strip_edges()


func build_dev_cycle_context() -> String:
	var dcm: Node = _get_autoload("DevCycleManager")
	if dcm == null:
		return "- 开发循环信息当前不可用"

	var lines: PackedStringArray = []
	var current_day: int = int(dcm.call("_get_current_day")) if dcm.has_method("_get_current_day") else 1
	var order_active: bool = dcm.is_order_active() if dcm.has_method("is_order_active") else false
	lines.append("- 当前天数：Day %d" % current_day)
	lines.append("- 已完成任务数：%d" % (dcm.get_completed_count() if dcm.has_method("get_completed_count") else 0))
	lines.append("- 当前是否有后台工单在执行：%s" % ("是" if order_active else "否"))

	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	if visible_tasks.is_empty():
		lines.append("- 当前没有可见 dev work")
	else:
		lines.append("- 当前可见 dev work：")
		for task in visible_tasks:
			lines.append("  - [%s] %s" % [
				str(task.get("status", "")),
				str(task.get("title", "")),
			])

	return "\n".join(lines)


func build_work_order_context() -> String:
	var summary_result: Dictionary = AVGDevWorkOrderToolsClass._wo_list_order_summaries({"limit": 8})
	if not bool(summary_result.get("success", false)):
		return "- 当前无法读取工单摘要"

	var lines: PackedStringArray = []
	var rows: Array = summary_result.get("data", [])
	if rows.is_empty():
		lines.append("- 当前没有工单")
		return "\n".join(lines)

	lines.append("- 当前工单总数：%d" % int(summary_result.get("total_orders", rows.size())))
	for row in rows:
		if not row is Dictionary:
			continue
		lines.append("  - [%s/%s] %s" % [
			str(row.get("surface_status", row.get("status", ""))),
			str(row.get("inner_status", "")),
			str(row.get("title", "")),
		])
	return "\n".join(lines)


func build_kb_context() -> String:
	var kb: Node = _get_autoload("KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_documents"):
		return "- 当前知识库不可用"

	var docs: Array = kb.get_documents()
	if docs.is_empty():
		return "- 当前知识库为空"

	docs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("updated_at", "")) > str(b.get("updated_at", ""))
	)

	var lines: PackedStringArray = []
	for doc in docs.slice(0, 8):
		var content := str(doc.get("content", "")).strip_edges().replace("\n", " ")
		lines.append("- [%s] %s: %s" % [
			str(doc.get("category", "")),
			str(doc.get("title", "")),
			content.left(90),
		])
	return "\n".join(lines)


func build_dev_cycle_snapshot() -> Dictionary:
	var dcm: Node = _get_autoload("DevCycleManager")
	if dcm == null:
		return {"success": false, "error": "DevCycleManager not available."}

	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	var task_summaries: Array[Dictionary] = []
	for task in visible_tasks:
		var runtime_type: String = str(task.get("task_type", "")).strip_edges()
		if dcm.has_method("_describe_task_runtime_type"):
			runtime_type = str(dcm.call("_describe_task_runtime_type", task))
		task_summaries.append({
			"task_id": str(task.get("task_id", "")),
			"title": str(task.get("title", "")),
			"status": str(task.get("status", "")),
			"task_type": runtime_type,
		})

	return {
		"success": true,
		"data": {
			"current_day": int(dcm.call("_get_current_day")) if dcm.has_method("_get_current_day") else 1,
			"visible_tasks": task_summaries,
			"completed_task_count": dcm.get_completed_count() if dcm.has_method("get_completed_count") else 0,
			"queue_size": dcm.get_queue_size() if dcm.has_method("get_queue_size") else 0,
			"order_active": dcm.is_order_active() if dcm.has_method("is_order_active") else false,
			"plan_generated": dcm.is_plan_generated() if dcm.has_method("is_plan_generated") else false,
			"plan_generating": dcm.is_plan_generating() if dcm.has_method("is_plan_generating") else false,
		}
	}


func _resolve_npc(raw_npc: Variant) -> Variant:
	var npc := raw_npc as NPCCharacter
	if npc != null:
		return npc
	if raw_npc is Array and not (raw_npc as Array).is_empty():
		npc = (raw_npc as Array)[0] as NPCCharacter
		if npc != null:
			return npc
	return null


func _get_autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)
