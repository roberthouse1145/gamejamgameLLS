extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		print("[FAIL] WorkOrder runtime reset test missing WorkOrderManager")
		return

	wom.reset_runtime_state()
	await get_tree().process_frame

	if wom.get_all_orders().size() != 0:
		print("[FAIL] Work orders should start empty after runtime reset")
		return

	wom.create_order("运行期清空测试", "这条工单只用于验证不会写回模板")
	if wom.get_all_orders().size() != 1:
		print("[FAIL] Failed to create in-memory work order during runtime reset test")
		wom.reset_runtime_state()
		return

	wom._load_orders_from_project()
	await get_tree().process_frame

	if wom.get_all_orders().size() != 0:
		print("[FAIL] Work orders were restored from project data, expected empty runtime state")
		wom.reset_runtime_state()
		return

	var order: Resource = wom.create_order("第二次创建测试", "验证编号会重新从空状态开始")
	if order == null or str(order.id) != "wo_1":
		print("[FAIL] Work order id did not restart from wo_1 after runtime reset")
		wom.reset_runtime_state()
		return

	print("[OK] WorkOrder runtime reset test passed")
	wom.reset_runtime_state()
