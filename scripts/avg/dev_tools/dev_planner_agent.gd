extends ChatAgent
## DevPlannerAgent
## 项目级规划代理：
## - 负责生成玩家可见的 dev work
## - 负责生成正式开发计划
## - 不直接写 KB，不直接执行工单


func _ready() -> void:
	super._ready()
	AVGDevKBTools.register_read_only(_ai_service)
	AVGDevWorkOrderTools.register_summary_read_only(_ai_service)
	_register_project_read_only_tools()
	_register_dev_cycle_snapshot_tool()
	_register_kb_summarize_state_tool()
	print("[DevPlannerAgent] Ready - tools: %d" % _ai_service.get_tools_definition().size())


func _register_project_read_only_tools() -> void:
	_ai_service.register_tool("project_info", "获取当前项目基础信息（名称、分辨率、场景数、角色数、变量数等）。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._project_info(args), {
		"fields": ["success", "data.project_name", "data.resolution", "data.scene_count", "data.character_count", "data.variable_count", "data.event_count", "data.initial_scene_id", "data.initial_scene_name", "error"]
	})

	_ai_service.register_tool("list_scene_catalog", "获取场景目录摘要，返回场景 ID、名称、备注，以及初始场景/孤立场景提示。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._list_scene_catalog(args), {
		"fields": ["success", "data", "entry_scene_id", "error"]
	})

	_ai_service.register_tool("analyze_story_reachability", "分析当前项目的剧情可达性，检查孤立场景、不可达分支和 unknown 路径。", {
		"type": "object",
		"properties": {
			"max_total_states": {"type": "integer"},
			"max_command_steps": {"type": "integer"},
		},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._analyze_story_reachability(args), {
		"fields": ["success", "data.entry_scene_id", "data.scene_catalog", "data.unreachable_scenes", "data.warnings", "error"]
	})

	_ai_service.register_tool("list_assets", "列出当前项目可用资源及 alias。只有在你需要确认真实资源范围时才调用。", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["all", "backgrounds", "images", "cg", "bgm", "sfx", "characters"], "description": "要查询的资源类别，默认 all"}
		},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._list_assets(args), {
		"fields": ["success", "data", "error"]
	})


func _register_dev_cycle_snapshot_tool() -> void:
	_ai_service.register_tool("get_dev_cycle_snapshot", "获取当前开发循环的简要状态，包括当前天数、可见任务、已完成任务数量、工单队列情况、计划是否已生成。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _get_dev_cycle_snapshot(args), {
		"fields": ["success", "data.current_day", "data.visible_tasks", "data.completed_task_count", "data.queue_size", "data.order_active", "data.plan_generated", "data.plan_generating", "error"]
	})


func _register_kb_summarize_state_tool() -> void:
	_ai_service.register_tool("kb_summarize_state", "快速查看当前 KB 所有文档的索引（doc_id / 标题 / 分类 / 标签 / state / 更新时间 / 首行摘要）；不返回正文。用于产出工单前的 KB 实地核对，决定哪些任务有素材落地、哪些必须降级为 creative_decision。", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "可选：仅列出某一分类的文档"}
		},
	}, func(args: Dictionary) -> Variant: return _kb_summarize_state(args), {
		"fields": ["success", "data", "error"]
	})


func _kb_summarize_state(args: Dictionary) -> Dictionary:
	var kbm: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kbm == null or not kbm.has_method("get_documents"):
		return {"success": false, "error": "KnowledgeBaseManager not available."}

	var category: String = str(args.get("category", "")).strip_edges()
	var docs: Array = kbm.get_documents(category)

	var rows: Array = []
	for doc in docs:
		if not doc is Dictionary:
			continue
		var content: String = str(doc.get("content", ""))
		var first_line: String = ""
		if not content.is_empty():
			var newline_idx: int = content.find("\n")
			first_line = content if newline_idx < 0 else content.substr(0, newline_idx)
			first_line = first_line.strip_edges()
			if first_line.length() > 120:
				first_line = first_line.substr(0, 120) + "…"
		rows.append({
			"doc_id": str(doc.get("doc_id", "")),
			"title": str(doc.get("title", "")),
			"category": str(doc.get("category", "")),
			"tags": doc.get("tags", []),
			"state": str(doc.get("state", "")),
			"doc_kind": str(doc.get("doc_kind", "")),
			"updated_at": str(doc.get("updated_at", "")),
			"first_line": first_line,
		})

	return {"success": true, "data": rows}


func _get_dev_cycle_snapshot(_args: Dictionary) -> Dictionary:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		return {"success": false, "error": "DevCycleManager not available."}

	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	var task_summaries: Array[Dictionary] = []
	for task in visible_tasks:
		task_summaries.append({
			"task_id": str(task.get("task_id", "")),
			"title": str(task.get("title", "")),
			"status": str(task.get("status", "")),
			"task_type": str(task.get("task_type", "")),
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
