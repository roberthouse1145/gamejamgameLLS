class_name AVGDevWorkOrderTools extends RefCounted
## AVG Dev AI — 工单执行工具集
## 提供 wo_get_order_details / wo_complete_task / wo_finish_order
## 让 AI 代理能够自主获取、执行并完成派发给它的工单任务。


# =============================================================================
# 工具注册
# =============================================================================

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
