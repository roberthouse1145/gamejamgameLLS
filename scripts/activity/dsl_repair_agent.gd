class_name DSLRepairAgent
extends Node
## DSL 修复代理
## 当 AVG DSL 验证失败时，使用工具调用模式修复 DSL 中的错误，
## 而不是让 LLM 全量重写。
##
## 设计要点：
## - 使用 _active_repair 单一状态来共享上下文给工具回调
## - 在发送请求前就设置好上下文，避免时序问题
## - 使用 tool_calls_completed 信号检测工具循环结束，而非 request_completed

signal repair_completed(session_id: String, dsl_text: String)
signal repair_failed(session_id: String, error: String)

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")

const REPAIR_ROLE: String = "dsl_repair"
const FALLBACK_ROLES: PackedStringArray = ["date_scene_writer", "avg_dev_writer", "chat_default"]
const MAX_TOOL_ITERATIONS: int = 10

var _repair_service: AIService = null
var _repair_ready: bool = false
var _parser: RefCounted = ParserClass.new()
var _validator: RefCounted = ValidatorClass.new()

## 当前活跃的修复上下文（同一时刻只允许一个修复任务）
var _active_repair: Dictionary = {}
## 标记当前是否有修复任务正在进行
var _is_busy: bool = false


func _ready() -> void:
	_setup_repair_service()


func is_available() -> bool:
	return _repair_ready and _repair_service != null


func _setup_repair_service() -> void:
	_repair_service = AIService.new()
	_repair_service.name = "DSLRepairService"
	_repair_service.auto_execute_tools = true
	_repair_service.max_tool_iterations = MAX_TOOL_ITERATIONS
	add_child(_repair_service)

	# 注册工具（常驻，回调通过 _active_repair 访问上下文）
	_repair_service.register_tool(
		"patch_dsl",
		"Replace a specific text fragment in the DSL with a corrected version. After each call, the DSL is automatically re-validated and the result is returned.",
		{
			"type": "object",
			"properties": {
				"old_text": {
					"type": "string",
					"description": "The exact text fragment in the current DSL to replace. Must match exactly (including whitespace and newlines).",
				},
				"new_text": {
					"type": "string",
					"description": "The corrected text to replace old_text with. Use empty string to delete the fragment.",
				},
			},
			"required": ["old_text", "new_text"],
		},
		_on_patch_tool_called,
	)

	_repair_service.register_tool(
		"delete_lines",
		"Delete one or more complete lines from the DSL by their exact text content. Useful for removing invalid commands entirely.",
		{
			"type": "object",
			"properties": {
				"line_text": {
					"type": "string",
					"description": "The exact text of the line(s) to delete (including leading whitespace). The entire matching line will be removed.",
				},
			},
			"required": ["line_text"],
		},
		_on_delete_lines_called,
	)

	_repair_service.register_tool(
		"batch_patch_dsl",
		"Apply multiple text replacements to the DSL in one call. Use this to fix all errors at once. Each operation replaces old_text with new_text. The DSL is re-validated after ALL patches are applied.",
		{
			"type": "object",
			"properties": {
				"operations": {
					"type": "array",
					"description": "Array of patch operations to apply sequentially.",
					"items": {
						"type": "object",
						"properties": {
							"old_text": {
								"type": "string",
								"description": "Exact text to find and replace.",
							},
							"new_text": {
								"type": "string",
								"description": "Replacement text. Empty string to delete.",
							},
						},
						"required": ["old_text", "new_text"],
					},
				},
			},
			"required": ["operations"],
		},
		_on_batch_patch_called,
	)

	# 连接信号（常驻连接，内部通过 _is_busy 过滤）
	_repair_service.request_completed.connect(_on_request_completed)
	_repair_service.request_failed.connect(_on_request_failed)

	var config_mgr := AIConfigManager.get_instance()
	_repair_ready = config_mgr.apply_to_service(_repair_service, REPAIR_ROLE)
	if not _repair_ready:
		for fallback_role in FALLBACK_ROLES:
			_repair_ready = config_mgr.apply_to_service(_repair_service, fallback_role)
			if _repair_ready:
				break


## 尝试修复验证失败的 DSL。
func attempt_repair(
	session_id: String,
	dsl_text: String,
	validation_result: Dictionary,
	project: Resource,
	project_root_path: String,
	asset_manifest: String,
) -> void:
	if not is_available():
		repair_failed.emit(session_id, "repair_service_unavailable")
		return
	if _is_busy:
		repair_failed.emit(session_id, "repair_agent_busy")
		return

	var errors: Array = validation_result.get("errors", [])
	if errors.is_empty():
		repair_failed.emit(session_id, "no_errors_to_repair")
		return

	# 设定活跃修复上下文（必须在发请求前设好，工具回调才能访问）
	_active_repair = {
		"session_id": session_id,
		"current_dsl": dsl_text,
		"project": project,
		"project_root_path": project_root_path,
		"patch_count": 0,
	}
	_is_busy = true

	# 构建消息并发送（不使用 conversation API，直接 chat_with_tools）
	var system_prompt: String = _build_system_prompt(asset_manifest)
	var user_message: String = _build_user_message(dsl_text, errors)
	var messages: Array = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_message},
	]

	var request_id: String = _repair_service.chat_with_tools(messages, [], "auto", {
		"temperature": 0.2,
		"max_tokens": 1200,
		"auto_execute": true,
	})

	if request_id.is_empty():
		_finish_repair(false, "repair_request_send_failed")
		return

	print("[DSLRepairAgent] Repair started for %s | errors=%d" % [session_id, errors.size()])


#region 信号处理

func _on_request_completed(_request_id: String, response: Dictionary) -> void:
	if not _is_busy:
		return

	# 检查响应是否包含 tool_calls —— 如果是，说明这是中间结果，AIService 的
	# auto_execute_tools 循环还在继续，此时不要处理最终结果
	var has_tool_calls: bool = false
	if response.has("choices") and response.choices.size() > 0:
		var message: Dictionary = response.choices[0].get("message", {})
		var tool_calls_value: Variant = message.get("tool_calls", null)
		if tool_calls_value is Array and tool_calls_value.size() > 0:
			has_tool_calls = true

	if has_tool_calls:
		# 中间结果，忽略（工具循环还在进行）
		return

	# 最终结果（无 tool_calls），检查修复状态
	var session_id: String = str(_active_repair.get("session_id", ""))
	var current_dsl: String = str(_active_repair.get("current_dsl", ""))
	var patch_count: int = int(_active_repair.get("patch_count", 0))

	var final_result: Dictionary = _validate_dsl_full(current_dsl)
	if bool(final_result.get("ok", false)):
		print("[DSLRepairAgent] Repair succeeded for %s | patches=%d" % [session_id, patch_count])
		_finish_repair(true, current_dsl)
	else:
		var summary: String = str(final_result.get("summary", "validation_still_failing"))
		print("[DSLRepairAgent] Repair exhausted for %s | patches=%d | %s" % [session_id, patch_count, summary])
		_finish_repair(false, summary)


func _on_request_failed(_request_id: String, error: String, _error_code: int) -> void:
	if not _is_busy:
		return
	print("[DSLRepairAgent] Request failed: %s" % error)
	_finish_repair(false, "repair_request_failed: " + error)

#endregion


#region 工具回调

func _on_patch_tool_called(args: Dictionary) -> Dictionary:
	var old_text: String = str(args.get("old_text", ""))
	var new_text: String = str(args.get("new_text", ""))

	if old_text.is_empty():
		return {"success": false, "error": "old_text is empty"}
	if not _is_busy or _active_repair.is_empty():
		return {"success": false, "error": "no active repair context"}

	var current_dsl: String = str(_active_repair.get("current_dsl", ""))
	if current_dsl.find(old_text) == -1:
		return {
			"success": false,
			"error": "old_text not found in current DSL. Make sure it matches exactly including whitespace.",
			"hint": "Try a shorter, more unique fragment.",
		}

	# 检查多次匹配
	var count: int = current_dsl.count(old_text)
	if count > 1:
		return {
			"success": false,
			"error": "old_text matches %d locations. Use a longer, more unique fragment." % count,
		}

	# 应用 patch
	var patched_dsl: String = current_dsl.replace(old_text, new_text)
	_active_repair["current_dsl"] = patched_dsl
	_active_repair["patch_count"] = int(_active_repair.get("patch_count", 0)) + 1

	# 重新验证
	var result: Dictionary = _validate_dsl_full(patched_dsl)
	if bool(result.get("ok", false)):
		return {
			"success": true,
			"message": "Patch applied. DSL now passes validation. You can stop.",
			"remaining_errors": [],
		}

	return {
		"success": true,
		"message": "Patch applied but DSL still has errors.",
		"remaining_errors": result.get("errors", []),
	}


func _on_delete_lines_called(args: Dictionary) -> Dictionary:
	var line_text: String = str(args.get("line_text", ""))
	if line_text.is_empty():
		return {"success": false, "error": "line_text is empty"}
	if not _is_busy or _active_repair.is_empty():
		return {"success": false, "error": "no active repair context"}

	var current_dsl: String = str(_active_repair.get("current_dsl", ""))
	var lines: PackedStringArray = current_dsl.split("\n")
	var new_lines: PackedStringArray = []
	var removed_count: int = 0

	for line in lines:
		if line.strip_edges() == line_text.strip_edges():
			removed_count += 1
		else:
			new_lines.append(line)

	if removed_count == 0:
		return {
			"success": false,
			"error": "No matching line found. Make sure line_text matches exactly.",
		}

	var patched_dsl: String = "\n".join(new_lines)
	_active_repair["current_dsl"] = patched_dsl
	_active_repair["patch_count"] = int(_active_repair.get("patch_count", 0)) + 1

	var result: Dictionary = _validate_dsl_full(patched_dsl)
	if bool(result.get("ok", false)):
		return {
			"success": true,
			"message": "Lines removed (%d). DSL now passes validation. You can stop." % removed_count,
			"remaining_errors": [],
		}

	return {
		"success": true,
		"message": "Lines removed (%d) but DSL still has errors." % removed_count,
		"remaining_errors": result.get("errors", []),
	}


func _on_batch_patch_called(args: Dictionary) -> Dictionary:
	if not _is_busy or _active_repair.is_empty():
		return {"success": false, "error": "no active repair context"}

	var operations: Variant = args.get("operations", null)
	if operations == null or not (operations is Array) or operations.is_empty():
		return {"success": false, "error": "operations must be a non-empty array"}

	var current_dsl: String = str(_active_repair.get("current_dsl", ""))
	var applied: int = 0
	var skipped: Array[String] = []

	for op in operations:
		if not (op is Dictionary):
			continue
		var old_text: String = str(op.get("old_text", ""))
		var new_text: String = str(op.get("new_text", ""))
		if old_text.is_empty():
			skipped.append("empty old_text")
			continue
		if current_dsl.find(old_text) == -1:
			skipped.append("not found: %s" % old_text.left(40))
			continue
		if current_dsl.count(old_text) > 1:
			skipped.append("ambiguous (%d matches): %s" % [current_dsl.count(old_text), old_text.left(40)])
			continue
		current_dsl = current_dsl.replace(old_text, new_text)
		applied += 1

	_active_repair["current_dsl"] = current_dsl
	_active_repair["patch_count"] = int(_active_repair.get("patch_count", 0)) + applied

	var result: Dictionary = _validate_dsl_full(current_dsl)
	var response: Dictionary = {
		"success": true,
		"applied": applied,
		"remaining_errors": result.get("errors", []),
	}
	if not skipped.is_empty():
		response["skipped"] = skipped
	if bool(result.get("ok", false)):
		response["message"] = "All patches applied. DSL now passes validation. You can stop."
	else:
		response["message"] = "%d patches applied but DSL still has errors." % applied
	return response

#endregion


#region 内部方法

func _finish_repair(success: bool, result: String) -> void:
	var session_id: String = str(_active_repair.get("session_id", ""))
	_active_repair.clear()
	_is_busy = false
	if success:
		repair_completed.emit(session_id, result)
	else:
		repair_failed.emit(session_id, result)


func _validate_dsl_full(dsl_text: String) -> Dictionary:
	if dsl_text.strip_edges().is_empty():
		return {"ok": false, "summary": "empty_dsl", "errors": ["DSL is empty"]}

	var parse_result: Dictionary = _parser.parse(dsl_text)
	if not bool(parse_result.get("success", false)):
		var parse_errors: Array = parse_result.get("errors", [])
		var first_error: String = "dsl_parse_failed"
		if not parse_errors.is_empty() and parse_errors[0] is Dictionary:
			var error_entry: Dictionary = parse_errors[0]
			first_error = "line %d: %s" % [int(error_entry.get("line", 0)), str(error_entry.get("message", ""))]
		return {"ok": false, "summary": first_error, "errors": [first_error]}

	var commands: Array = parse_result.get("commands", [])
	var project: Resource = _active_repair.get("project", null)
	var project_root_path: String = str(_active_repair.get("project_root_path", ""))

	if project == null:
		return {"ok": true, "summary": "ok (no project for semantic check)", "commands": commands, "errors": []}

	var semantic_result: Dictionary = _validator.validate_commands(
		commands,
		project,
		project_root_path,
		{"min_choice_count": 0, "max_choice_count": 0},
	)

	if not bool(semantic_result.get("ok", false)):
		return {
			"ok": false,
			"summary": str(semantic_result.get("summary", "dsl_semantic_failed")),
			"errors": semantic_result.get("errors", []),
		}

	return {
		"ok": true,
		"summary": str(semantic_result.get("summary", "ok")),
		"commands": commands,
		"errors": [],
	}


func _build_system_prompt(asset_manifest: String) -> String:
	var lines: Array[String] = []
	lines.append("You are a DSL repair assistant. Your job is to fix validation errors in AVG DSL V2 code.")
	lines.append("You have access to tools to patch the DSL text. Each patch triggers automatic re-validation.")
	lines.append("")
	lines.append("RULES:")
	lines.append("- Only fix the errors listed. Do NOT rewrite creative content (dialogue, narration).")
	lines.append("- Prefer batch_patch_dsl to fix ALL errors in one call when possible.")
	lines.append("- Use patch_dsl for a single replacement, or delete_lines to remove a command.")
	lines.append("- old_text must match the DSL exactly (whitespace matters).")
	lines.append("- If an emotion/outfit/background/bgm/sfx name is invalid, replace it with a valid one from the asset manifest below.")
	lines.append("- If a resource has no valid replacement, replace the entire line with empty string to delete it.")
	lines.append("- Stop calling tools once validation passes (remaining_errors is empty).")
	lines.append("")
	lines.append("AVAILABLE ASSETS:")
	lines.append(asset_manifest)
	return "\n".join(lines)


func _build_user_message(dsl_text: String, errors: Array) -> String:
	var lines: Array[String] = []
	lines.append("The following DSL has validation errors. Fix them using the patch_dsl tool.")
	lines.append("")
	lines.append("=== CURRENT DSL ===")
	lines.append(dsl_text)
	lines.append("=== END DSL ===")
	lines.append("")
	lines.append("=== VALIDATION ERRORS ===")
	for error in errors:
		lines.append("- %s" % str(error))
	lines.append("=== END ERRORS ===")
	return "\n".join(lines)

#endregion
