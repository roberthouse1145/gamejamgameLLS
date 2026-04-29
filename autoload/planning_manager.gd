extends Node
## PlanningManager Autoload
## 管理项目级规划 Agent：
## - 第一批 dev work 规划
## - 正式开发计划规划

const DevPlannerScene = preload("res://scenes/avg/dev_tools/dev_planner_agent.tscn")

const SEED_TASK_PROMPT_KEY: String = "seed_dev_work_generation"
const DEVELOPMENT_PLAN_PROMPT_KEY: String = "plan_generation"

signal seed_task_plan_completed(request_id: String, success: bool, tasks: Array, raw_output: String)
signal development_plan_completed(request_id: String, success: bool, tasks: Array, raw_output: String)

var _planner_agent: ChatAgent = null
var _active_request_id: String = ""
var _active_request_kind: String = ""
var verbose_agent_logging: bool = false


func _ready() -> void:
	_ensure_planner_agent()


func reset_runtime_state() -> void:
	_active_request_id = ""
	_active_request_kind = ""
	if _planner_agent != null:
		_planner_agent.reset()


func request_seed_task_plan(creative_context: String) -> String:
	var request_prompt: String = _resolve_prompt_template(SEED_TASK_PROMPT_KEY, {
		"creative_context": creative_context,
	})
	if request_prompt.is_empty():
		push_warning("[PlanningManager] Seed task prompt unavailable")
		return ""
	request_prompt = _prepend_preflight_context(request_prompt)
	return _begin_request("seed", request_prompt)


func request_development_plan(kb_content: String) -> String:
	var request_prompt: String = _resolve_prompt_template(DEVELOPMENT_PLAN_PROMPT_KEY, {
		"kb_content": kb_content,
	})
	if request_prompt.is_empty():
		push_warning("[PlanningManager] Development plan prompt unavailable")
		return ""
	request_prompt = _prepend_preflight_context(request_prompt)
	return _begin_request("development_plan", request_prompt)


func _begin_request(kind: String, request_prompt: String) -> String:
	_ensure_planner_agent()
	if _planner_agent == null:
		return ""
	if _planner_agent.is_busy():
		push_warning("[PlanningManager] Planner agent is busy, cannot start request: %s" % kind)
		return ""

	_planner_agent.reset()
	var request_id: String = _planner_agent.send_message(request_prompt)
	if request_id.is_empty():
		return ""

	_active_request_id = request_id
	_active_request_kind = kind
	print("[PlanningManager] Planner request sent: %s (%s)" % [request_id, kind])
	return request_id


func _ensure_planner_agent() -> void:
	if _planner_agent != null and is_instance_valid(_planner_agent):
		return

	var planner: ChatAgent = DevPlannerScene.instantiate()
	planner.name = "DevPlannerAgent"
	add_child(planner)
	_planner_agent = planner

	_planner_agent.message_completed.connect(_on_planner_message_completed)
	_planner_agent.message_failed.connect(_on_planner_message_failed)
	_planner_agent.log_entry.connect(func(entry: Dictionary):
		var log_type: String = str(entry.get("type", "info"))
		var log_content: String = str(entry.get("content", "")).strip_edges()
		if log_type == "error":
			push_warning("[DevPlanner][error] %s" % log_content)
			return
		if not verbose_agent_logging:
			return
		match log_type:
			"ai_response":
				print("[DevPlanner][ai] %s" % log_content.left(200))
			"tool_call":
				print("[DevPlanner][tool] %s" % log_content.left(160))
			"tool_result":
				print("[DevPlanner][result] %s" % log_content.left(160))
			"progress":
				print("[DevPlanner][progress] %s" % log_content.left(160))
	)


func _on_planner_message_completed(request_id: String, content: String) -> void:
	if request_id != _active_request_id:
		return

	var request_kind: String = _active_request_kind
	var parsed: Variant = _parse_json_array_output(content)

	_active_request_id = ""
	_active_request_kind = ""

	if _planner_agent != null:
		_planner_agent.reset()

	if parsed is Array:
		match request_kind:
			"seed":
				seed_task_plan_completed.emit(request_id, true, parsed, content)
			"development_plan":
				development_plan_completed.emit(request_id, true, parsed, content)
		return

	match request_kind:
		"seed":
			seed_task_plan_completed.emit(request_id, false, [], content)
		"development_plan":
			development_plan_completed.emit(request_id, false, [], content)


func _on_planner_message_failed(request_id: String, error: String) -> void:
	if request_id != _active_request_id:
		return

	var request_kind: String = _active_request_kind
	_active_request_id = ""
	_active_request_kind = ""

	if _planner_agent != null:
		_planner_agent.reset()

	push_warning("[PlanningManager] Planner request failed (%s): %s" % [request_kind, error])
	match request_kind:
		"seed":
			seed_task_plan_completed.emit(request_id, false, [], error)
		"development_plan":
			development_plan_completed.emit(request_id, false, [], error)


func _resolve_prompt_template(prompt_key: String, vars: Dictionary = {}) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		push_warning("[PlanningManager] PromptManager unavailable for key: %s" % prompt_key)
		return ""
	if pm.has_method("has_prompt") and not pm.has_prompt(prompt_key):
		push_warning("[PlanningManager] Prompt key not found: %s" % prompt_key)
		return ""
	if pm.has_method("resolve_with_vars"):
		return str(pm.resolve_with_vars(prompt_key, vars)).strip_edges()
	return ""


func _prepend_preflight_context(request_prompt: String) -> String:
	var preflight_context: String = _build_preflight_context()
	if preflight_context.is_empty():
		return request_prompt
	return (
		"以下是系统已经为你预先整理好的项目现状摘要。\n"
		+ "这些信息来自当前开发循环和工单系统的只读摘要，不包含工单详情正文。\n"
		+ "请优先依据这份摘要规划，除非你明确发现信息不足，否则不要重复查询同样的信息。\n\n"
		+ preflight_context
		+ "\n\n"
		+ request_prompt
	).strip_edges()


func _build_preflight_context() -> String:
	var sections: PackedStringArray = []

	var dev_cycle_summary: String = _build_dev_cycle_summary_text()
	if not dev_cycle_summary.is_empty():
		sections.append("## 当前开发循环摘要\n%s" % dev_cycle_summary)

	var order_summary: String = _build_order_summary_text()
	if not order_summary.is_empty():
		sections.append("## 当前工单摘要\n%s" % order_summary)

	return "\n\n".join(sections).strip_edges()


func _build_dev_cycle_summary_text() -> String:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		return ""

	var lines: PackedStringArray = []
	var current_day: int = int(dcm.call("_get_current_day")) if dcm.has_method("_get_current_day") else 1
	var completed_task_count: int = dcm.get_completed_count() if dcm.has_method("get_completed_count") else 0
	var order_active: bool = dcm.is_order_active() if dcm.has_method("is_order_active") else false
	var plan_generated: bool = dcm.is_plan_generated() if dcm.has_method("is_plan_generated") else false
	lines.append("- 当前天数：Day %d" % current_day)
	lines.append("- 已完成任务数：%d" % completed_task_count)
	lines.append("- 当前是否有后台工单在执行：%s" % ("是" if order_active else "否"))
	lines.append("- 当前计划是否已生成：%s" % ("是" if plan_generated else "否"))
	if dcm.has_method("get_next_planning_rhythm_hint"):
		lines.append("- 下一批节奏提示：%s" % str(dcm.call("get_next_planning_rhythm_hint")))

	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	if visible_tasks.is_empty():
		lines.append("- 当前没有可见 dev work")
	else:
		lines.append("- 当前可见 dev work：")
		for task in visible_tasks:
			var runtime_type: String = str(task.get("task_type", "")).strip_edges()
			if dcm.has_method("_describe_task_runtime_type"):
				runtime_type = str(dcm.call("_describe_task_runtime_type", task))
			lines.append("  - [%s] %s（%s）" % [
				str(task.get("status", "")),
				str(task.get("title", "")),
				runtime_type,
			])

	var recent_completed: Array = dcm.get_recent_completed_tasks(6) if dcm.has_method("get_recent_completed_tasks") else []
	if recent_completed.is_empty():
		lines.append("- 最近还没有完成过 dev work")
	else:
		lines.append("- 最近完成的 dev work：")
		for item in recent_completed:
			if not item is Dictionary:
				continue
			lines.append("  - %s（%s）" % [
				str(item.get("title", "")),
				str(item.get("runtime_type", "")),
			])

	return "\n".join(lines)


func _build_order_summary_text() -> String:
	var summary_result: Dictionary = AVGDevWorkOrderTools._wo_list_order_summaries({"limit": 12})
	if not bool(summary_result.get("success", false)):
		return "- 当前无法读取工单摘要"

	var lines: PackedStringArray = []
	var total_orders: int = int(summary_result.get("total_orders", 0))
	lines.append("- 当前工单总数：%d" % total_orders)

	var rows: Array = summary_result.get("data", [])
	if rows.is_empty():
		lines.append("- 当前没有工单")
		return "\n".join(lines)

	lines.append("- 近期工单列表：")
	for row in rows:
		if not row is Dictionary:
			continue
		lines.append("  - [%s] %s（ID: %s，优先级: %d，子工单: %d）" % [
			str(row.get("status", "")),
			str(row.get("title", "")),
			str(row.get("order_id", "")),
			int(row.get("priority", 0)),
			int(row.get("children_count", 0)),
		])

	return "\n".join(lines)


func _parse_json_array_output(text: String) -> Variant:
	for candidate in _collect_json_parse_candidates(text):
		var parsed: Variant = JSON.parse_string(candidate)
		if parsed is Array:
			return parsed
	return null


func _collect_json_parse_candidates(text: String) -> Array[String]:
	var candidates: Array[String] = []
	var stripped: String = text.strip_edges()
	if stripped.is_empty():
		return candidates

	if stripped.begins_with("["):
		_append_unique_json_candidate(candidates, stripped)

	var fenced_content: String = _extract_fenced_content(stripped)
	if not fenced_content.is_empty() and fenced_content.begins_with("["):
		_append_unique_json_candidate(candidates, fenced_content)

	var text_array: String = _extract_balanced_json_array(stripped)
	if not text_array.is_empty():
		_append_unique_json_candidate(candidates, text_array)

	if not fenced_content.is_empty():
		var fenced_array: String = _extract_balanced_json_array(fenced_content)
		if not fenced_array.is_empty():
			_append_unique_json_candidate(candidates, fenced_array)

	return candidates


func _append_unique_json_candidate(candidates: Array[String], candidate: String) -> void:
	var normalized: String = candidate.strip_edges()
	if normalized.is_empty() or normalized in candidates:
		return
	candidates.append(normalized)


func _extract_json_from_response(text: String) -> String:
	var fenced_content: String = _extract_fenced_content(text)
	if not fenced_content.is_empty():
		return fenced_content

	var balanced_array: String = _extract_balanced_json_array(text)
	if not balanced_array.is_empty():
		return balanced_array
	return text.strip_edges()


func _extract_fenced_content(text: String) -> String:
	var stripped: String = text.strip_edges()
	var fence_start: int = stripped.find("```")
	if fence_start < 0:
		return ""

	var content_start: int = stripped.find("\n", fence_start)
	if content_start < 0:
		return ""

	var fence_end: int = stripped.find("\n```", content_start + 1)
	if fence_end >= 0:
		return stripped.substr(content_start + 1, fence_end - content_start - 1).strip_edges()
	return stripped.substr(content_start + 1).strip_edges()


func _extract_balanced_json_array(text: String) -> String:
	var stripped: String = text.strip_edges()
	if stripped.is_empty():
		return ""

	for start in range(stripped.length()):
		if stripped[start] != "[":
			continue
		var candidate: String = _slice_balanced_json_array(stripped, start)
		if candidate.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(candidate)
		if parsed is Array:
			return candidate
	return ""


func _slice_balanced_json_array(text: String, start_index: int) -> String:
	if start_index < 0 or start_index >= text.length() or text[start_index] != "[":
		return ""

	var depth: int = 0
	var in_string: bool = false
	var escaping: bool = false
	for i in range(start_index, text.length()):
		var ch: String = text[i]
		if in_string:
			if escaping:
				escaping = false
			elif ch == "\\":
				escaping = true
			elif ch == '"':
				in_string = false
			continue

		if ch == '"':
			in_string = true
			continue
		if ch == "[":
			depth += 1
			continue
		if ch == "]":
			depth -= 1
			if depth == 0:
				return text.substr(start_index, i - start_index + 1)

	return ""
