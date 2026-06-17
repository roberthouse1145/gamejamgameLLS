extends Node

const WorkOrderManagerScript = preload("res://autoload/work_order_manager.gd")
const WorkOrderDataClass = preload("res://scripts/apps/work_order/work_order_data.gd")
const WorkOrderAgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== WorkOrder Agent Cache Index Test ===")
	_test_initial_prompt_shape()
	await _test_agent_history_budget_and_shape()
	_print_summary()


func _test_initial_prompt_shape() -> void:
	var manager: Node = WorkOrderManagerScript.new()
	var order := WorkOrderDataClass.new()
	order.id = "wo_cache_index"
	order.title = "缓存索引测试"
	order.description = "验证工单动态内容位于项目索引之后"
	order.status = "in_progress"
	order.surface_status = "in_progress"
	order.inner_status = "generating"
	manager.set("_orders", {"wo_cache_index": order})

	var prompt: String = str(manager.call("_build_worker_initial_prompt", "wo_cache_index"))
	var index_pos: int = prompt.find("# 项目索引（稳定前缀）")
	var order_pos: int = prompt.find("# 当前工单（动态尾部）")
	_assert("initial prompt contains project index", index_pos >= 0, prompt.left(120))
	_assert("initial prompt contains order tail", order_pos >= 0, prompt.left(120))
	_assert("project index precedes order tail", index_pos >= 0 and order_pos > index_pos, "index=%d order=%d" % [index_pos, order_pos])
	_assert("order id included in tail", prompt.find("order_id: wo_cache_index") >= 0, "")
	_assert("index usage instruction included", prompt.find("索引不是全文") >= 0, "")
	_assert("initial task template resolved", prompt.find("请执行上述工单") >= 0, "")
	_assert("project index template resolved", prompt.find("## KB 文档索引") >= 0, "")


func _test_agent_history_budget_and_shape() -> void:
	var agent: ChatAgent = WorkOrderAgentScene.instantiate()
	add_child(agent)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert("agent history chars raised", agent.max_history_chars >= 180000, str(agent.max_history_chars))
	_assert("agent history messages raised", agent.max_history_messages >= 180, str(agent.max_history_messages))
	_assert("agent prompt key is work_order_agent", str(agent.prompt_key) == "work_order_agent", str(agent.prompt_key))

	_assert("no PlannerAgent child", agent.get_node_or_null("PlannerAgent") == null, "")
	_assert("no WriterAgent child", agent.get_node_or_null("WriterAgent") == null, "")
	_assert("no ExecutorAgent child", agent.get_node_or_null("ExecutorAgent") == null, "")

	agent.queue_free()


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
