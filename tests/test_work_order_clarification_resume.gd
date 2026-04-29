extends Node

const WorkOrderManagerScript = preload("res://autoload/work_order_manager.gd")
const WorkOrderDataClass = preload("res://scripts/apps/work_order/work_order_data.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _saved_project_path: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== WorkOrder Clarification Resume Test ===")
	_saved_project_path = StorageManager.current_project_path
	StorageManager.current_project_path = ""
	ChatManager.reset_runtime_state(false)
	await get_tree().process_frame

	var manager: Node = WorkOrderManagerScript.new()
	manager.set("_worker_auto_run", false)
	add_child(manager)
	await get_tree().process_frame
	await get_tree().process_frame

	await _test_clarification_resume(manager)
	manager.queue_free()

	StorageManager.current_project_path = _saved_project_path
	_print_summary()


func _test_clarification_resume(manager: Node) -> void:
	var order := WorkOrderDataClass.new()
	order.id = "wo_clarify"
	order.title = "补一段角色说明"
	order.description = "角色感觉不够明确，需要先和玩家确认方向。"
	order.status = "in_progress"
	order.surface_status = "in_progress"
	order.inner_status = "generating"
	manager.set("_orders", {order.id: order})

	manager.request_clarification(order.id, ["这个角色更偏温柔还是更偏强势？"])
	await get_tree().process_frame

	_assert("clarification switches legacy status", order.status == "needs_input", str(order.status))
	_assert("clarification switches surface status", order.surface_status == "needs_input", str(order.surface_status))
	_assert("clarification pauses inner status", order.inner_status == "waiting_input", str(order.inner_status))

	var topic: ChatTopic = ChatManager.get_active_topic("dm_lin_xia")
	_assert("clarification topic created", topic != null, "")
	if topic == null:
		return

	ChatManager.store_player_message_data("dm_lin_xia", {"content": "偏温柔一点，但不要太软弱。"})
	ChatManager.topic_manager.complete_topic(topic, {
		"messages": [
			{"speaker": "npc_lin_xia", "content": "明白了，我会按这个方向继续。"}
		],
		"summary": "玩家希望角色偏温柔，但仍有自己的主见。"
	})
	await get_tree().process_frame
	await get_tree().process_frame

	_assert("order resumes legacy status", order.status == "in_progress", str(order.status))
	_assert("order restores surface status", order.surface_status == "in_progress", str(order.surface_status))
	_assert("order resumes generating", order.inner_status == "generating", str(order.inner_status))
	_assert("clarification history recorded", order.clarification_history.size() == 1, str(order.clarification_history.size()))

	var clarification: Dictionary = order.clarification_history[0]
	var player_messages: Array = clarification.get("player_messages", [])
	_assert("player clarification captured", player_messages.size() == 1, str(player_messages))
	if player_messages.size() > 0:
		_assert("player clarification content kept", str(player_messages[0]).find("偏温柔一点") >= 0, str(player_messages[0]))

	_assert("worker respawned after clarification", bool(manager.call("is_order_running", order.id)), "")


func _assert(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
