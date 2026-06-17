class_name AVGDevWorkOrderTools extends RefCounted
## AVG Dev AI — 工单执行工具集
## 提供 wo_get_order_details / wo_complete_task / wo_finish_order
## 让 AI 代理能够自主获取、执行并完成当前项目中的工单任务。


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
	}, func(args: Dictionary) -> Variant: return _wo_list_order_summaries(args), {
		"fields": ["success", "data", "count", "total_orders", "note", "error"]
	})

## Controller 专用：只需要读取工单详情 + 完成工单 + 上行回传（不需要逐 task 打勾）
static func register_controller_tools(ai_service: Node) -> void:
	ai_service.register_tool("wo_get_order_details", "获取工单的详细信息（标题、需求描述等）", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID（如 wo_1）"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_get_order_details(args), {
		"fields": ["success", "data.id", "data.title", "data.description", "data.status", "data.surface_status", "data.inner_status", "error"]
	})

	ai_service.register_tool("wo_finish_order", "将整个工单标记为完成。所有工作执行完毕后调用；若本次工单改动了场景链路、开场或跳转关系，应先完成一次伪运行/可达性检查并优先修复明显断链问题。", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_finish_order(args), {
		"fields": ["success", "message", "error"]
	})


## 全量注册（向后兼容，保留 wo_complete_task）
static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("wo_get_order_details", "获取一个工单的详细信息和当前所有任务的完成状态", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID（如 wo_1）"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_get_order_details(args), {
		"fields": ["success", "data.id", "data.title", "data.description", "data.status", "data.surface_status", "data.inner_status", "error"]
	})

	ai_service.register_tool("wo_complete_task", "将工单内的某个子任务标记为已完成", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID"},
			"task_index": {"type": "integer", "description": "任务的序号（从 0 开始）"}
		},
		"required": ["order_id", "task_index"]
	}, func(args: Dictionary) -> Variant: return _wo_complete_task(args), {
		"fields": ["success", "message", "error"]
	})

	ai_service.register_tool("wo_finish_order", "将整个工单标记为彻底完成。请在执行完所有 task 后再调用此工具。", {
		"type": "object",
		"properties": {
			"order_id": {"type": "string", "description": "工单 ID"}
		},
		"required": ["order_id"]
	}, func(args: Dictionary) -> Variant: return _wo_finish_order(args), {
		"fields": ["success", "message", "error"]
	})


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
		var queue_position: int = mgr.get_order_queue_position(str(order.id)) if mgr.has_method("get_order_queue_position") else 0
		summaries.append({
			"order_id": str(order.id),
			"title": str(order.title),
			"status": str(order.status),
			"surface_status": str(order.surface_status),
			"inner_status": str(order.inner_status),
			"queue_position": queue_position,
			"priority": int(order.priority),
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
	
	if mgr.has_method("finish_order") and mgr.finish_order(order_id):
		return {"success": true, "message": "工单 %s 设置为完成" % order_id}
	else:
		return {"success": false, "error": "完成工单失败，工单不存在: %s" % order_id}
