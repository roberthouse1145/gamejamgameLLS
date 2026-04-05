extends Node

const WorkOrderControllerScene = preload("res://scenes/avg/dev_tools/work_order_controller_agent.tscn")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	var chat: Node = get_node_or_null("/root/ChatManager")
	if wom == null or chat == null:
		print("[FAIL] WorkOrder clarification test missing autoloads")
		return

	_cleanup_existing_test_orders(wom)

	var order: Resource = wom.create_order("澄清回归测试", "先创建一个测试工单")
	order.assignee_npc_id = "npc_lin_xia"
	order.surface_status = "in_progress"
	order.status = "in_progress"
	order.inner_status = "generating"

	var worker: ChatAgent = WorkOrderControllerScene.instantiate()
	worker.name = "TestWorkerClarification"
	wom.add_child(worker)
	wom._worker_agents[order.id] = worker
	wom.request_clarification(order.id, ["主角更偏冷静还是活泼？"])
	await get_tree().process_frame

	var paused_ok: bool = order.surface_status == "needs_input" \
		and order.inner_status == "awaiting_clarification" \
		and not order.pending_questions.is_empty()
	if not paused_ok:
		print("[FAIL] Clarification request did not move order into waiting state")
		print("  surface_status: %s" % order.surface_status)
		print("  inner_status: %s" % order.inner_status)
		_cleanup_existing_test_orders(wom)
		return

	wom._on_worker_message_completed(order.id)
	await get_tree().process_frame
	if order.surface_status == "completed":
		print("[FAIL] Waiting clarification order was incorrectly marked completed")
		_cleanup_existing_test_orders(wom)
		return

	var channel: Resource = chat.get_channel("dm_lin_xia")
	if channel == null:
		print("[FAIL] Clarification test could not access dm channel")
		_cleanup_existing_test_orders(wom)
		return

	channel.messages.append({
		"sender_id": "player",
		"sender_name": "玩家",
		"content": "我想要更活泼一点的感觉。",
	})

	var topic := ChatTopicClass.new()
	topic.topic_id = "clarify_test_topic"
	topic.topic_type = "work_clarification"
	topic.channel_id = "dm_lin_xia"
	topic.context_data = {
		"order_id": order.id,
		"start_message_count": max(0, channel.messages.size() - 1),
	}

	wom._handle_completed_clarification_topic(topic, {"messages": []})
	await get_tree().process_frame

	var resumed_ok: bool = order.surface_status == "in_progress" \
		and order.inner_status == "generating" \
		and order.pending_questions.is_empty() \
		and order.description.contains("更活泼一点")
	if not resumed_ok:
		print("[FAIL] Clarification completion did not resume order correctly")
		print("  surface_status: %s" % order.surface_status)
		print("  inner_status: %s" % order.inner_status)
		print("  description: %s" % order.description)
		_cleanup_existing_test_orders(wom)
		return

	print("[OK] WorkOrder clarification pause/resume regression test passed")

	_cleanup_existing_test_orders(wom)
	if is_instance_valid(worker):
		worker.queue_free()


func _cleanup_existing_test_orders(wom: Node) -> void:
	var orders: Array = wom.get_all_orders()
	for order in orders:
		if order != null and str(order.title) == "澄清回归测试":
			wom.delete_order(order.id)
