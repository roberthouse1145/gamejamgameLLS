extends Node

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	var old_auto_run: bool = bool(WorkOrderManager.get("_worker_auto_run"))
	WorkOrderManager.set("_worker_auto_run", false)
	WorkOrderManager.reset_runtime_state()

	if StorageManager.current_project == null or str(StorageManager.current_project_path) != "user://run/player_project/":
		var mount_err: Error = StorageManager.mount_runtime_project("tutorial_project")
		_assert("mount runtime project", mount_err == OK, str(mount_err))
		await get_tree().process_frame

	var order: Resource = WorkOrderManager.create_order("Retry watchdog test", "验证静默不会触发自动重试", {
		"source_type": "llm_build_pipeline_lab",
		"source_id": "retry_watchdog_test",
	})

	var dispatch_ok: bool = WorkOrderManager.dispatch_order(order.id)
	_assert("dispatch order succeeds", dispatch_ok)
	await get_tree().process_frame

	var agents: Dictionary = WorkOrderManager.get("_worker_agents")
	_assert("worker spawned", agents.has(order.id))

	_force_worker_stall(order.id)
	WorkOrderManager.run_worker_watchdog_once()
	await get_tree().process_frame
	_assert("watchdog no longer retries stalled worker", WorkOrderManager.get_worker_retry_count(order.id) == 0, str(WorkOrderManager.get_worker_retry_count(order.id)))
	_assert("stalled worker remains in progress", str(WorkOrderManager.get_order(order.id).status) == "in_progress", str(WorkOrderManager.get_order(order.id).status))
	_assert("worker remains attached after silent stall", WorkOrderManager.get("_worker_agents").has(order.id))

	WorkOrderManager.call("_cleanup_worker", order.id)

	_test_resume_only_one_order_at_a_time()

	WorkOrderManager.reset_runtime_state()
	WorkOrderManager.set("_worker_auto_run", old_auto_run)
	_print_summary()


func _test_resume_only_one_order_at_a_time() -> void:
	WorkOrderManager.reset_runtime_state()

	var order_a: Resource = WorkOrderManager.create_order("Serial resume A", "验证恢复只会拉起一个工单", {
		"source_type": "llm_build_pipeline_lab",
		"source_id": "serial_resume_a",
	})
	order_a.status = "in_progress"
	order_a.surface_status = "in_progress"
	order_a.inner_status = "idle"

	var order_b: Resource = WorkOrderManager.create_order("Serial resume B", "验证恢复只会拉起一个工单", {
		"source_type": "llm_build_pipeline_lab",
		"source_id": "serial_resume_b",
	})
	order_b.status = "in_progress"
	order_b.surface_status = "in_progress"
	order_b.inner_status = "idle"

	WorkOrderManager.resume_pending_generations()
	await get_tree().process_frame

	var first_agents: Dictionary = WorkOrderManager.get("_worker_agents")
	_assert("resume_pending_generations only starts one worker", first_agents.size() == 1, str(first_agents.keys()))

	var first_order_id: String = ""
	for key in first_agents.keys():
		first_order_id = str(key)
		break
	_assert("first resumed order is oldest", first_order_id == order_a.id, first_order_id)
	_assert("second order still idle", str(WorkOrderManager.get_order(order_b.id).inner_status) != "generating" or not first_agents.has(order_b.id), str(WorkOrderManager.get_order(order_b.id).inner_status))

	WorkOrderManager.call("_cleanup_worker", first_order_id)
	var first_order: Resource = WorkOrderManager.get_order(first_order_id)
	if first_order != null:
		first_order.inner_status = "ready"

	var resumed_second: bool = false
	if WorkOrderManager.has_method("resume_order_generation"):
		resumed_second = bool(WorkOrderManager.resume_order_generation(order_b.id))
	else:
		WorkOrderManager.resume_pending_generations()
		resumed_second = true
	await get_tree().process_frame
	var second_agents: Dictionary = WorkOrderManager.get("_worker_agents")
	_assert("resume_order_generation starts second worker", resumed_second and second_agents.has(order_b.id), str(second_agents.keys()))
	WorkOrderManager.call("_cleanup_worker", order_b.id)


func _force_worker_stall(order_id: String) -> void:
	var last_activity: Dictionary = WorkOrderManager.get("_worker_last_activity_msec")
	last_activity[order_id] = Time.get_ticks_msec() - 120000
	WorkOrderManager.set("_worker_last_activity_msec", last_activity)


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		if detail.is_empty():
			print("FAIL  %s" % label)
		else:
			print("FAIL  %s -- %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
