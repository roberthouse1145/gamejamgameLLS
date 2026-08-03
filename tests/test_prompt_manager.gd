extends Node


func _ready() -> void:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	_assert(prompt_manager != null, "PromptManager is available")
	if prompt_manager == null:
		return
	prompt_manager.register_prompt("test_variable_resolution", "Scene: {{scene_name}}")
	var resolved := str(prompt_manager.resolve_with_vars("test_variable_resolution", {"scene_name": "Opening"}))
	_assert(resolved == "Scene: Opening", "caller variables are resolved")
	_assert(prompt_manager.has_prompt("avg_scene_dsl_preview"), "generic AVG prompt is loaded")


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		push_error("[FAIL] %s" % message)
