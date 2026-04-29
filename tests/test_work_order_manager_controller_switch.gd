extends Node

const WorkOrderManagerScript = preload("res://autoload/work_order_manager.gd")
const WorkOrderDataClass = preload("res://scripts/apps/work_order/work_order_data.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== WorkOrderManager Controller Switch Test ===")
	await _test_builds_controller_worker()
	_test_finish_order_flow()
	_print_summary()


func _test_builds_controller_worker() -> void:
	var manager: Node = WorkOrderManagerScript.new()
	var worker: ChatAgent = manager.call("_build_worker_agent_for_order", "wo_test")
	_assert("controller worker instantiated", worker != null, "")
	if worker == null:
		return

	add_child(worker)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert("worker prompt key is controller", str(worker.prompt_key) == "work_order_controller", str(worker.prompt_key))
	_assert("worker has AIService", worker.get_node_or_null("AIService") != null, "")
	_assert("worker has PlannerAgent", worker.get_node_or_null("PlannerAgent") != null, "")
	_assert("worker has WriterAgent", worker.get_node_or_null("WriterAgent") != null, "")
	_assert("worker has ExecutorAgent", worker.get_node_or_null("ExecutorAgent") != null, "")

	worker.queue_free()


func _test_finish_order_flow() -> void:
	var manager: Node = WorkOrderManagerScript.new()

	var pending_order := WorkOrderDataClass.new()
	pending_order.id = "wo_pending"
	pending_order.title = "直接完成的工单"
	pending_order.status = "in_progress"
	pending_order.surface_status = "in_progress"
	pending_order.inner_status = "generating"
	manager.set("_orders", {"wo_pending": pending_order})

	var pending_ok: bool = bool(manager.finish_order("wo_pending"))
	_assert("finish_order returns true", pending_ok, "")
	_assert("finish_order sets inner ready", pending_order.inner_status == "ready", str(pending_order.inner_status))
	_assert("finish_order marks legacy status completed", pending_order.status == "completed", str(pending_order.status))
	_assert("finish_order marks surface completed", pending_order.surface_status == "completed", str(pending_order.surface_status))

	var complete_order := WorkOrderDataClass.new()
	complete_order.id = "wo_complete"
	complete_order.title = "可立即交付的工单"
	complete_order.status = "in_progress"
	complete_order.surface_status = "in_progress"
	complete_order.inner_status = "generating"
	manager.set("_orders", {"wo_complete": complete_order})

	var complete_ok: bool = bool(manager.finish_order("wo_complete"))
	_assert("finish_order completes second order", complete_ok, "")
	_assert("completed order status", complete_order.status == "completed", str(complete_order.status))
	_assert("completed order surface status", complete_order.surface_status == "completed", str(complete_order.surface_status))
	_assert("completed order inner status", complete_order.inner_status == "ready", str(complete_order.inner_status))


func _assert(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
