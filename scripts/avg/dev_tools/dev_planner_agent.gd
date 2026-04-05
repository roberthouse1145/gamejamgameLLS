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
	print("[DevPlannerAgent] Ready - tools: %d" % _ai_service.get_tools_definition().size())


func _register_project_read_only_tools() -> void:
	_ai_service.register_tool("project_info", "获取当前项目基础信息（名称、分辨率、场景数、角色数、变量数等）。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._project_info(args))

	_ai_service.register_tool("list_assets", "列出当前项目可用资源及 alias。只有在你需要确认真实资源范围时才调用。", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["all", "backgrounds", "images", "cg", "bgm", "sfx", "characters"], "description": "要查询的资源类别，默认 all"}
		},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._list_assets(args))


func _register_dev_cycle_snapshot_tool() -> void:
	_ai_service.register_tool("get_dev_cycle_snapshot", "获取当前开发循环的简要状态，包括当前天数、可见任务、已完成任务数量、工单队列情况、计划是否已生成。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _get_dev_cycle_snapshot(args))


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
