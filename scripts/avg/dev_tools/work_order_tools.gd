class_name AVGDevWorkOrderTools extends RefCounted
## AVG Dev AI — 工单执行工具集
## 提供 wo_get_order_details / wo_complete_task / wo_finish_order
## 让 AI 代理能够自主获取、执行并完成派发给它的工单任务。


# =============================================================================
# 工具注册
# =============================================================================

## 只读摘要工具：查看项目内全部工单的简要状态，不返回详情正文。
static func register_summary_read_only(ai_service: Node) -> void:
	ai_service.register_tool("wo_list_order_summaries", "获取当前项目所有工单的摘要列表。只返回标题、状态、优先级、来源、父子关系等简要信息，不返回 description 正文。适合全局规划时查看当前工单负载。", {
		"type": "object",
		"properties": {
			"status": {
				"type": "string",
				"description": "可选。只看某一种状态的工单，例如 in_progress / completed / needs_input"
			},
			"limit": {
				"type": "integer",
				"description": "可选。最多返回多少条，默认 20，最大 50"
			}
		}
	}, func(args: Dictionary) -> Variant: return _wo_list_order_summaries(args))

## Controller 专用：只需要读取工单详情 + 完成工单 + 上行回传（不需要逐 task 打勾）
static func register_controller_tools(ai_service: Node) -> void:
	ai_service.register_tool("wo_get_order_details", "获取工单的详细信息（标题、需求描述等）", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID（如 wo_1）"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_get_order_details(args))

	ai_service.register_tool("wo_finish_order", "将整个工单标记为完成。所有工作执行完毕后调用。", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_finish_order(args))

	# ── 上行回传工具 ──

	ai_service.register_tool("wo_request_clarification",
		"向玩家请求需求澄清。当工单需求模糊、缺少关键信息时调用。会在 LinkChat 中创建一个澄清话题，让 NPC 自然地向玩家追问。调用后当前工单会暂停，等玩家回答后自动恢复。",
		{
			"type": "object",
			"properties": {
				"order_id": {"type": "string", "description": "当前工单 ID"},
				"questions": {
					"type": "array",
					"items": {"type": "string"},
					"description": "需要向玩家澄清的问题列表（1-3 个最关键的问题）"
				}
			},
			"required": ["order_id", "questions"]
		},
		func(args: Dictionary) -> Variant: return _wo_request_clarification(args)
	)

	ai_service.register_tool("wo_request_creative_discussion",
		"请求玩家参与创意讨论。当遇到需要玩家拍板的创意分叉（如角色性格方向、剧情走向选择）时调用。会在 DevWork 中创建一个高优先级讨论任务，不阻塞当前工单。",
		{
			"type": "object",
			"properties": {
				"order_id": {"type": "string", "description": "当前工单 ID（用于关联追踪）"},
				"topic": {"type": "string", "description": "讨论主题（如「第二章分支走向」）"},
				"description": {"type": "string", "description": "为什么需要讨论、当前面临什么抉择"},
				"kb_category": {
					"type": "string",
					"description": "讨论结果存入哪个 KB 分类",
					"enum": ["world", "characters", "story", "notes"],
					"default": "story"
				}
			},
			"required": ["order_id", "topic", "description"]
		},
		func(args: Dictionary) -> Variant: return _wo_request_creative_discussion(args)
	)


## 全量注册（向后兼容，保留 wo_complete_task）
static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("wo_get_order_details", "获取一个工单的详细信息和当前所有任务的完成状态", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID（如 wo_1）"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_get_order_details(args))

	ai_service.register_tool("wo_complete_task", "将工单内的某个子任务标记为已完成", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID"},
			"task_index": {"type": "integer", "description": "任务的序号（从 0 开始）"}
		},
		"required": ["order_id", "task_index"]
	}, func(args: Dictionary) -> Variant: return _wo_complete_task(args))

	ai_service.register_tool("wo_finish_order", "将整个工单标记为彻底完成。请在执行完所有 task 后再调用此工具。", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_finish_order(args))


# =============================================================================
# 实现
# =============================================================================

static func _get_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/WorkOrderManager")


static func _wo_get_order_details(args: Dictionary) -> Dictionary:
	var mgr: Node = _get_manager()
	if mgr == null:
		return {"success": false, "error": "WorkOrderManager 未就绪"}
		
	var order_id: String = args.get("order_id", "")
	var order: Resource = mgr.get_order(order_id)
	if order == null:
		return {"success": false, "error": "工单不存在: %s" % order_id}
		
	return {
		"success": true,
		"data": order.to_dict()
	}


static func _wo_list_order_summaries(args: Dictionary) -> Dictionary:
	var mgr: Node = _get_manager()
	if mgr == null:
		return {"success": false, "error": "WorkOrderManager 未就绪"}

	var status_filter: String = str(args.get("status", "")).strip_edges()
	var limit: int = clampi(int(args.get("limit", 20)), 1, 50)

	var orders: Array = []
	if status_filter.is_empty():
		orders = mgr.get_all_orders()
	else:
		orders = mgr.get_orders_by_status(status_filter)

	var summaries: Array[Dictionary] = []
	for i in range(mini(limit, orders.size())):
		var order: Resource = orders[i]
		if order == null:
			continue
		var parent_id: String = str(order.parent_order_id)
		var children: Array = order.children_order_ids if "children_order_ids" in order else []
		summaries.append({
			"order_id": str(order.id),
			"title": str(order.title),
			"status": str(order.status),
			"surface_status": str(order.surface_status),
			"inner_status": str(order.inner_status),
			"priority": int(order.priority),
			"assignee_npc_id": str(order.assignee_npc_id),
			"source_type": str(order.source_type),
			"source_id": str(order.source_id),
			"parent_order_id": parent_id,
			"has_parent": not parent_id.is_empty(),
			"children_count": children.size(),
			"updated_at": int(order.updated_at),
		})

	return {
		"success": true,
		"data": summaries,
		"count": summaries.size(),
		"total_orders": orders.size(),
		"note": "This summary omits description/spec details to reduce token usage."
	}


static func _wo_complete_task(args: Dictionary) -> Dictionary:
	var mgr: Node = _get_manager()
	if mgr == null:
		return {"success": false, "error": "WorkOrderManager 未就绪"}
		
	var order_id: String = args.get("order_id", "")
	var task_index: int = args.get("task_index", -1)
	
	if mgr.set_task_done(order_id, task_index, true):
		return {"success": true, "message": "任务 %d 标记为完成" % task_index}
	else:
		return {"success": false, "error": "标记失败，请检查工单ID或Task序号是否正确"}


static func _wo_finish_order(args: Dictionary) -> Dictionary:
	var mgr: Node = _get_manager()
	if mgr == null:
		return {"success": false, "error": "WorkOrderManager 未就绪"}
		
	var order_id: String = args.get("order_id", "")
	
	if mgr.set_order_status(order_id, "completed"):
		return {"success": true, "message": "工单 %s 设置为完成" % order_id}
	else:
		return {"success": false, "error": "完成工单失败，工单不存在: %s" % order_id}


static func _wo_request_clarification(args: Dictionary) -> Dictionary:
	var mgr: Node = _get_manager()
	if mgr == null:
		return {"success": false, "error": "WorkOrderManager 未就绪"}

	var order_id: String = args.get("order_id", "")
	var questions: Array = args.get("questions", [])

	if order_id.is_empty():
		return {"success": false, "error": "缺少 order_id"}
	if questions.is_empty():
		return {"success": false, "error": "缺少 questions"}

	var order: Resource = mgr.get_order(order_id)
	if order == null:
		return {"success": false, "error": "工单不存在: %s" % order_id}

	mgr.request_clarification(order_id, questions)
	return {
		"success": true,
		"message": "已发起需求澄清，工单暂停等待玩家回答。问题: %s" % str(questions)
	}


static func _wo_request_creative_discussion(args: Dictionary) -> Dictionary:
	var mgr: Node = _get_manager()
	if mgr == null:
		return {"success": false, "error": "WorkOrderManager 未就绪"}

	var order_id: String = args.get("order_id", "")
	var topic: String = args.get("topic", "")
	var description: String = args.get("description", "")
	var kb_category: String = args.get("kb_category", "story")

	if topic.is_empty():
		return {"success": false, "error": "缺少 topic"}
	if description.is_empty():
		return {"success": false, "error": "缺少 description"}

	mgr.request_creative_task({
		"topic": topic,
		"description": description,
		"kb_category": kb_category,
		"requester_order_id": order_id,
	})
	return {
		"success": true,
		"message": "已请求创意讨论任务: '%s'。该任务会出现在 DevWork 中，不阻塞当前工单。" % topic
	}
