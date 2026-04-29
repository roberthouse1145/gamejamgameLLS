extends Node

const WorkOrderManagerScript = preload("res://autoload/work_order_manager.gd")
const WorkOrderDataClass = preload("res://scripts/apps/work_order/work_order_data.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _saved_project_path: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_saved_project_path = StorageManager.current_project_path
	StorageManager.current_project_path = ""
	ChatManager.reset_runtime_state(false)
	await get_tree().process_frame

	var manager: Node = WorkOrderManagerScript.new()
	manager.set("_worker_auto_run", false)
	add_child(manager)
	await get_tree().process_frame
	await get_tree().process_frame

	var order := WorkOrderDataClass.new()
	order.id = "wo_prompt"
	order.title = "补一段角色说明"
	order.description = "角色感觉不够明确，需要先和玩家确认方向。"
	order.status = "in_progress"
	order.surface_status = "in_progress"
	order.inner_status = "generating"
	manager.set("_orders", {order.id: order})

	manager.request_clarification(order.id, ["这个角色更偏温柔还是更偏强势？"])
	await get_tree().process_frame

	var topic: ChatTopic = ChatManager.get_active_topic("dm_lin_xia")
	_assert("clarification topic created", topic != null, "")
	if topic != null:
		var prompt: String = str(topic.system_prompt)
		_assert("prompt forbids complete before player reply", prompt.find("绝对不要输出 [TOPIC_COMPLETE] 或 [TOPIC_FAILED]") >= 0, prompt)
		_assert("prompt requires waiting for player reply", prompt.find("只有在玩家已经明确回复") >= 0, prompt)
		_assert("prompt restricts topic failed semantics", prompt.find("只有在玩家明确拒绝回答、明确要求取消这张工单") >= 0, prompt)
		_assert("prompt asks to continue if unclear", prompt.find("如果玩家的回复仍然不够明确，就继续追问") >= 0, prompt)

	manager.queue_free()
	StorageManager.current_project_path = _saved_project_path
	_print_summary()


func _assert(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
