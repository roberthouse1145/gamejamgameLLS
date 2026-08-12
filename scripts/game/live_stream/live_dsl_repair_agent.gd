class_name LiveDSLRepairAgent
extends Node
## 直播 DSL 的最小工具修复代理。只接收候选 DSL、实际校验错误和必要取值提示。

signal repair_completed(session_id: StringName, dsl_text: String)
signal repair_failed(session_id: StringName, error: String)

const REPAIR_ROLE: String = "dsl_repair"
const FALLBACK_ROLES: PackedStringArray = ["chat_default"]
const MAX_TOOL_ITERATIONS: int = 4
const SYSTEM_PROMPT: String = "你只负责修复直播 DSL 中已列出的校验错误。必须调用 repair_live_dsl 工具提交最小范围的精确文本替换；不要重写整场内容，不要在普通回复中输出 DSL。工具会在每次修改后重新校验；若仍有错误，根据工具返回继续修复。"

var _repair_service: AIService = null
var _repair_ready: bool = false
var _active_repair: Dictionary = {}
var _pending_request_id: String = ""
var _last_prompt_metrics: Dictionary = {}


func _ready() -> void:
	_setup_repair_service()


func is_available() -> bool:
	return _repair_ready and _repair_service != null


func is_busy() -> bool:
	return not _active_repair.is_empty()


func get_last_prompt_metrics() -> Dictionary:
	return _last_prompt_metrics.duplicate(true)


func attempt_repair(
	session_id: StringName,
	dsl_text: String,
	validation_errors: Array,
	validator: Callable,
	repair_hints: Dictionary = {},
) -> void:
	if not is_available():
		repair_failed.emit(session_id, "repair_service_unavailable")
		return
	if is_busy():
		repair_failed.emit(session_id, "repair_agent_busy")
		return
	if dsl_text.strip_edges().is_empty():
		repair_failed.emit(session_id, "empty_dsl_cannot_be_patched")
		return
	if validation_errors.is_empty():
		repair_failed.emit(session_id, "no_errors_to_repair")
		return
	if not validator.is_valid():
		repair_failed.emit(session_id, "invalid_repair_validator")
		return

	var errors: Array[String] = []
	errors.assign(validation_errors)
	_active_repair = {
		"session_id": session_id,
		"current_dsl": dsl_text,
		"validator": validator,
		"patch_count": 0,
	}
	var user_message: String = _build_user_message(dsl_text, errors, repair_hints)
	_last_prompt_metrics = {
		"system_chars": SYSTEM_PROMPT.length(),
		"user_chars": user_message.length(),
		"total_chars": SYSTEM_PROMPT.length() + user_message.length(),
		"dsl_chars": dsl_text.length(),
		"error_count": errors.size(),
	}
	print("[LiveDSLRepairAgent] start session=%s prompt_chars=%d dsl_chars=%d errors=%d" % [
		session_id,
		int(_last_prompt_metrics.get("total_chars", 0)),
		dsl_text.length(),
		errors.size(),
	])
	_pending_request_id = _repair_service.chat_with_tools([
		{"role": "system", "content": SYSTEM_PROMPT},
		{"role": "user", "content": user_message},
	], [], "required", {
		"temperature": 0.1,
		"max_tokens": 768,
		"auto_execute": true,
		"tool_execution_policy": "read_parallel_write_serial",
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
	})
	if _pending_request_id.is_empty():
		_finish_repair(false, "repair_request_send_failed")


func cancel_repair() -> void:
	if _repair_service != null:
		_repair_service.cancel_all()
	_pending_request_id = ""
	_active_repair.clear()


func _setup_repair_service() -> void:
	_repair_service = AIService.new()
	_repair_service.name = "LiveDSLRepairService"
	_repair_service.auto_execute_tools = true
	_repair_service.max_tool_iterations = MAX_TOOL_ITERATIONS
	add_child(_repair_service)
	_repair_service.register_tool(
		"repair_live_dsl",
		"Apply exact text replacements to the current live DSL. Fix only the reported validation errors. Empty new_text deletes the matched fragment. The tool validates the patched DSL and returns remaining errors.",
		{
			"type": "object",
			"properties": {
				"operations": {
					"type": "array",
					"description": "Exact replacements applied in order.",
					"items": {
						"type": "object",
						"properties": {
							"old_text": {"type": "string", "description": "Exact unique text in the current DSL."},
							"new_text": {"type": "string", "description": "Replacement text; empty string deletes it."},
						},
						"required": ["old_text", "new_text"],
					},
				},
			},
			"required": ["operations"],
		},
		_on_repair_tool_called,
		null,
		{"effect": "terminal"},
	)
	_repair_service.request_completed.connect(_on_request_completed)
	_repair_service.request_failed.connect(_on_request_failed)

	var config_manager := AIConfigManager.get_instance()
	_repair_ready = config_manager.apply_to_service(_repair_service, REPAIR_ROLE)
	if not _repair_ready:
		for fallback_role: String in FALLBACK_ROLES:
			_repair_ready = config_manager.apply_to_service(_repair_service, fallback_role)
			if _repair_ready:
				break


func _on_repair_tool_called(args: Dictionary) -> Dictionary:
	if _active_repair.is_empty():
		return {"success": false, "error": "no active repair context"}
	var raw_operations: Variant = args.get("operations", null)
	if not (raw_operations is Array) or raw_operations.is_empty():
		return {"success": false, "error": "operations must be a non-empty array"}

	var current_dsl: String = str(_active_repair.get("current_dsl", ""))
	var applied: int = 0
	var skipped: Array[String] = []
	for raw_operation: Variant in raw_operations:
		if not (raw_operation is Dictionary):
			skipped.append("operation is not an object")
			continue
		var operation: Dictionary = raw_operation
		var old_text: String = str(operation.get("old_text", ""))
		var new_text: String = str(operation.get("new_text", ""))
		if old_text.is_empty():
			skipped.append("old_text is empty")
			continue
		var match_count: int = current_dsl.count(old_text)
		if match_count != 1:
			skipped.append("old_text matched %d times: %s" % [match_count, old_text.left(60)])
			continue
		current_dsl = current_dsl.replace(old_text, new_text)
		applied += 1

	_active_repair["current_dsl"] = current_dsl
	_active_repair["patch_count"] = int(_active_repair.get("patch_count", 0)) + applied
	var validation: Dictionary = _validate_current_dsl()
	var passed: bool = bool(validation.get("success", validation.get("ok", false)))
	var response: Dictionary = {
		"success": passed,
		"applied": applied,
		"remaining_errors": validation.get("errors", []),
		"summary": "直播 DSL 已通过校验。" if passed else "修改已应用，但仍需继续修复返回的校验错误。",
	}
	if not skipped.is_empty():
		response["skipped"] = skipped
	return response


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_request_id or _active_repair.is_empty():
		return
	if _response_has_tool_calls(response):
		return
	var validation: Dictionary = _validate_current_dsl()
	if bool(validation.get("success", validation.get("ok", false))):
		_finish_repair(true, str(_active_repair.get("current_dsl", "")))
		return
	var errors: Array = validation.get("errors", [])
	_finish_repair(false, str(errors[0]) if not errors.is_empty() else "repair_validation_failed")


func _on_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _pending_request_id or _active_repair.is_empty():
		return
	_finish_repair(false, "repair_request_failed: " + error)


func _validate_current_dsl() -> Dictionary:
	var validator: Callable = _active_repair.get("validator", Callable())
	if not validator.is_valid():
		return {"success": false, "errors": ["invalid_repair_validator"]}
	var result: Variant = validator.call(str(_active_repair.get("current_dsl", "")))
	if not (result is Dictionary):
		return {"success": false, "errors": ["invalid_validator_result"]}
	return result


func _finish_repair(success: bool, result: String) -> void:
	var session_id := StringName(str(_active_repair.get("session_id", "")))
	var patch_count: int = int(_active_repair.get("patch_count", 0))
	_pending_request_id = ""
	_active_repair.clear()
	if success:
		print("[LiveDSLRepairAgent] success session=%s patches=%d" % [session_id, patch_count])
		repair_completed.emit(session_id, result)
	else:
		print("[LiveDSLRepairAgent] failed session=%s reason=%s" % [session_id, result])
		repair_failed.emit(session_id, result)


func _response_has_tool_calls(response: Dictionary) -> bool:
	var choices: Variant = response.get("choices", [])
	if not (choices is Array) or choices.is_empty():
		return false
	var first_choice: Variant = choices[0]
	if not (first_choice is Dictionary):
		return false
	var message: Variant = first_choice.get("message", {})
	if not (message is Dictionary):
		return false
	var tool_calls: Variant = message.get("tool_calls", [])
	return tool_calls is Array and not tool_calls.is_empty()


func _build_user_message(dsl_text: String, errors: Array[String], repair_hints: Dictionary) -> String:
	var lines: Array[String] = [
		"当前直播 DSL：",
		dsl_text,
		"",
		"校验错误：",
	]
	for error: String in errors:
		lines.append("- " + error)
	if not repair_hints.is_empty():
		lines.append("")
		lines.append("这些错误需要的合法取值：")
		for key: Variant in repair_hints.keys():
			lines.append("%s: %s" % [str(key), str(repair_hints.get(key, ""))])
	return "\n".join(lines)
