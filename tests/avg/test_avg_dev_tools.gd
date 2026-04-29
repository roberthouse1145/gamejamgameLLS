extends Node
## End-to-end test: Main agent delegates to writer sub-agent
## to create a new scene. Verifies the full chain.

var _agent: Node


func _ready() -> void:
	var agent_scene: PackedScene = load("res://scenes/avg/dev_tools/avg_dev_agent.tscn")
	_agent = agent_scene.instantiate()
	add_child(_agent)

	await get_tree().process_frame
	await get_tree().process_frame

	print("=== E2E Sub-Agent Test ===")
	print("Main: %d tools, Writer: %d, Executor: %d" % [
		_agent.get_node("AIService").get_tools_definition().size(),
		_agent.get_node("WriterAgent/AIService").get_tools_definition().size(),
		_agent.get_node("ExecutorAgent/AIService").get_tools_definition().size(),
	])

	# Connect signals
	_agent.log_entry.connect(_on_log)
	_agent.message_completed.connect(_on_completed)
	_agent.message_failed.connect(_on_failed)
	_agent.tool_executed.connect(_on_tool)

	# Also connect writer sub-agent signals for visibility
	var writer: Node = _agent.get_node("WriterAgent")
	writer.log_entry.connect(func(e: Dictionary) -> void:
		print("[WRITER-LOG] %s: %s" % [e.get("type", ""), str(e.get("message", "")).left(200)])
	)
	writer.tool_executed.connect(func(_rid: String, tn: String, a: Dictionary, r: Variant, _tool_call_id: String) -> void:
		print("[WRITER-TOOL] %s(%s) -> %s" % [tn, str(a).left(80), str(r).left(150)])
	)

	# Send a message that should trigger writer delegation
	var msg: String = "Please create a short test scene called 'Ghost Encounter'. It should have a narrator line saying 'A shadow appears in the darkness' and a choice between 'Run away' and 'Stay'. Just create a minimal scene to test the pipeline. Do it now, no need to ask for confirmation."
	print("\n--- Sending: %s ---" % msg.left(100))
	_agent.send_message(msg)


func _on_log(entry: Dictionary) -> void:
	print("[MAIN-LOG] %s: %s" % [entry.get("type", ""), str(entry.get("message", "")).left(200)])


func _on_tool(_rid: String, tn: String, args: Dictionary, result: Variant, _tool_call_id: String) -> void:
	print("[MAIN-TOOL] %s(%s) -> %s" % [tn, str(args).left(80), str(result).left(200)])


func _on_completed(_rid: String, content: String) -> void:
	print("\n[MAIN-COMPLETED]\n%s" % content.left(600))
	print("\n=== E2E test done ===")


func _on_failed(_rid: String, error: String) -> void:
	print("\n[MAIN-FAILED] %s" % error)
	print("\n=== E2E test failed ===")
