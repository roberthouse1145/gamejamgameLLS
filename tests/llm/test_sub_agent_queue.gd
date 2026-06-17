extends Node

const ChatAgentScene = preload("res://scenes/llm/chat_agent.tscn")

class FakeSubAgent:
	extends Node

	signal message_completed(request_id: String, content: String)
	signal message_failed(request_id: String, error: String)

	var sent_tasks: Array[String] = []
	var pending: Array[Dictionary] = []
	var reset_count: int = 0

	func send_message(text: String) -> String:
		var request_id: String = "fake_%d" % (sent_tasks.size() + 1)
		sent_tasks.append(text)
		pending.append({"request_id": request_id, "text": text})
		return request_id

	func complete_next(content: String) -> void:
		if pending.is_empty():
			return
		var item: Dictionary = pending.pop_front()
		message_completed.emit(str(item.get("request_id", "")), "<result>%s</result>" % content)

	func fail_next(error: String) -> void:
		if pending.is_empty():
			return
		var item: Dictionary = pending.pop_front()
		message_failed.emit(str(item.get("request_id", "")), error)

	func reset() -> void:
		reset_count += 1


var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	var host: ChatAgent = ChatAgentScene.instantiate() as ChatAgent
	add_child(host)
	await get_tree().process_frame

	var fake_agent := FakeSubAgent.new()
	add_child(fake_agent)
	host.register_sub_agent_tool("writer", "queued writer test", fake_agent, true)

	var first: Dictionary = {"done": false}
	var second: Dictionary = {"done": false}
	_start_sub_agent_call(host, "first task", first)
	_start_sub_agent_call(host, "second task", second)

	await get_tree().process_frame
	_assert_eq(fake_agent.sent_tasks.size(), 1, "queued writer starts only first task")
	_assert_eq(fake_agent.sent_tasks[0], "first task", "queued writer first task text")
	_assert_true(not bool(second.get("done", false)), "queued writer keeps second call waiting")

	fake_agent.complete_next("first result")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(bool(first.get("done", false)), "queued writer first call completes")
	_assert_eq(str(first.get("data", "")), "first result", "queued writer first result")
	_assert_eq(fake_agent.sent_tasks.size(), 2, "queued writer starts second after first completes")
	_assert_eq(fake_agent.sent_tasks[1], "second task", "queued writer second task text")

	fake_agent.complete_next("second result")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(bool(second.get("done", false)), "queued writer second call completes")
	_assert_eq(str(second.get("data", "")), "second result", "queued writer second result")
	_assert_eq(fake_agent.reset_count, 2, "queued writer resets after each task")

	var third: Dictionary = {"done": false}
	var fourth: Dictionary = {"done": false}
	_start_sub_agent_call(host, "third task", third)
	_start_sub_agent_call(host, "fourth task", fourth)

	await get_tree().process_frame
	_assert_eq(fake_agent.sent_tasks.size(), 3, "queued writer starts third task")
	_assert_true(not bool(fourth.get("done", false)), "queued writer keeps fourth call waiting")

	fake_agent.fail_next("third failed")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(bool(third.get("done", false)), "queued writer failed call completes")
	_assert_true(not bool(third.get("success", true)), "queued writer reports failed call")
	_assert_eq(fake_agent.reset_count, 3, "queued writer resets after failed task")
	_assert_eq(fake_agent.sent_tasks.size(), 4, "queued writer starts fourth after third fails")
	_assert_eq(fake_agent.sent_tasks[3], "fourth task", "queued writer fourth task text")

	fake_agent.complete_next("fourth result")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(bool(fourth.get("done", false)), "queued writer fourth call completes")
	_assert_eq(str(fourth.get("data", "")), "fourth result", "queued writer fourth result")
	_assert_eq(fake_agent.reset_count, 4, "queued writer resets after fourth task")

	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])


func _start_sub_agent_call(host: ChatAgent, task: String, state: Dictionary) -> void:
	var result: Dictionary = await host._execute_sub_agent("writer", {"task": task})
	state["result"] = result
	state["done"] = true
	state["success"] = bool(result.get("success", false))
	state["data"] = str(result.get("data", ""))


func _assert_true(value: bool, label: String) -> void:
	if value:
		_pass_count += 1
		print("PASS  %s" % label)
		return
	_fail_count += 1
	push_error("FAIL  %s" % label)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("PASS  %s" % label)
		return
	_fail_count += 1
	push_error("FAIL  %s actual=%s expected=%s" % [label, str(actual), str(expected)])
