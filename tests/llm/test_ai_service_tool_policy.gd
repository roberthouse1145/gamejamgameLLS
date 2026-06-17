extends Node

var _pass_count: int = 0
var _fail_count: int = 0
var _ai: AIService = null
var _events: Array[String] = []


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== AIService Tool Execution Policy Test ===")
	_ai = AIService.new()
	_ai.name = "PolicyAIService"
	add_child(_ai)
	await get_tree().process_frame

	_register_fake_tools()
	var tool_calls: Array = [
		_tool_call("tc_read_a", "read_a"),
		_tool_call("tc_read_b", "read_b"),
		_tool_call("tc_write_a", "write_a"),
		_tool_call("tc_read_c", "read_c"),
		_tool_call("tc_write_b", "write_b"),
		_tool_call("tc_finish", "wo_finish_order"),
		_tool_call("tc_after", "read_after_finish"),
	]
	_ai.set("_tool_call_history", {"orig_policy": []})
	_ai.set("_conversations", {"conv_policy": []})

	var terminal_response: Dictionary = await _ai.call("_execute_tool_calls_with_policy", tool_calls, {
		"options": {"tool_execution_policy": "read_parallel_write_serial"}
	}, "orig_policy", "conv_policy")

	_assert_true("terminal response emitted", not terminal_response.is_empty(), str(terminal_response))
	_assert_true("read A starts before write A", _index_of("start:read_a") < _index_of("start:write_a"), str(_events))
	_assert_true("read B starts before write A", _index_of("start:read_b") < _index_of("start:write_a"), str(_events))
	_assert_true("read A and B overlap before first read end",
		_index_of("start:read_a") >= 0
		and _index_of("start:read_b") >= 0
		and _index_of("start:read_b") < _first_index_of_any(["end:read_a", "end:read_b"]),
		str(_events))
	_assert_true("write A completes before read C starts", _index_of("end:write_a") < _index_of("start:read_c"), str(_events))
	_assert_true("read C completes before write B starts", _index_of("end:read_c") < _index_of("start:write_b"), str(_events))
	_assert_true("write B completes before finish starts", _index_of("end:write_b") < _index_of("start:finish"), str(_events))
	_assert_true("tool after terminal skipped", _index_of("start:read_after_finish") == -1, str(_events))

	var history_map: Dictionary = _ai.get("_tool_call_history")
	var history: Array = history_map.get("orig_policy", [])
	_assert_true("history records six executed tools", history.size() == 6, str(history))

	_print_summary()


func _register_fake_tools() -> void:
	_ai.register_tool("read_a", "read a", {"type": "object", "properties": {}}, Callable(self, "_read_a"), null, {"effect": "read"})
	_ai.register_tool("read_b", "read b", {"type": "object", "properties": {}}, Callable(self, "_read_b"), null, {"effect": "read"})
	_ai.register_tool("read_c", "read c", {"type": "object", "properties": {}}, Callable(self, "_read_c"), null, {"effect": "read"})
	_ai.register_tool("read_after_finish", "read after finish", {"type": "object", "properties": {}}, Callable(self, "_read_after_finish"), null, {"effect": "read"})
	_ai.register_tool("write_a", "write a", {"type": "object", "properties": {}}, Callable(self, "_write_a"), null, {"effect": "write"})
	_ai.register_tool("write_b", "write b", {"type": "object", "properties": {}}, Callable(self, "_write_b"), null, {"effect": "write"})
	_ai.register_tool("wo_finish_order", "finish", {"type": "object", "properties": {}}, Callable(self, "_finish_order"), null, {"effect": "terminal"})


func _tool_call(call_id: String, tool_name: String) -> Dictionary:
	return {
		"id": call_id,
		"function": {
			"name": tool_name,
			"arguments": "{}",
		},
	}


func _read_a(_args: Dictionary) -> Dictionary:
	return await _fake_async("read_a", 0.04)


func _read_b(_args: Dictionary) -> Dictionary:
	return await _fake_async("read_b", 0.04)


func _read_c(_args: Dictionary) -> Dictionary:
	return await _fake_async("read_c", 0.01)


func _read_after_finish(_args: Dictionary) -> Dictionary:
	return await _fake_async("read_after_finish", 0.01)


func _write_a(_args: Dictionary) -> Dictionary:
	return await _fake_async("write_a", 0.01)


func _write_b(_args: Dictionary) -> Dictionary:
	return await _fake_async("write_b", 0.01)


func _finish_order(_args: Dictionary) -> Dictionary:
	_events.append("start:finish")
	await get_tree().process_frame
	_events.append("end:finish")
	return {"success": true, "message": "finished"}


func _fake_async(label: String, delay: float) -> Dictionary:
	_events.append("start:%s" % label)
	await get_tree().create_timer(delay).timeout
	_events.append("end:%s" % label)
	return {"success": true, "label": label}


func _index_of(value: String) -> int:
	for i in range(_events.size()):
		if _events[i] == value:
			return i
	return -1


func _first_index_of_any(values: Array[String]) -> int:
	var best: int = 2147483647
	for value in values:
		var idx: int = _index_of(value)
		if idx >= 0 and idx < best:
			best = idx
	return best if best != 2147483647 else -1


func _assert_true(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	if is_instance_valid(_ai):
		_ai.queue_free()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
