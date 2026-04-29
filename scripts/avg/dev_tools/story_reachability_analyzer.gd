class_name AVGStoryReachabilityAnalyzer extends RefCounted

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

const REACHABLE := "reachable"
const UNREACHABLE := "unreachable"
const UNKNOWN := "unknown"

var _project: Resource
var _scene_by_id: Dictionary = {}
var _event_by_id: Dictionary = {}
var _default_domains: Dictionary = {}
var _var_keys_by_ref: Dictionary = {}
var _reachable: Dictionary = {}
var _definite: Dictionary = {}
var _incoming: Dictionary = {}
var _branches: Array[Dictionary] = []
var _warnings: Array[String] = []
var _max_states: int = 256
var _max_steps: int = 512
var _max_event_depth: int = 8
var _state_limit_hit: bool = false
var _path_limit_hit: bool = false


func analyze(project: Resource, options: Dictionary = {}) -> Dictionary:
	_reset()
	_project = project
	if _project == null:
		return {"success": false, "error": "未打开项目"}
	_max_states = max(16, int(options.get("max_total_states", 256)))
	_max_steps = max(64, int(options.get("max_command_steps", 512)))
	_max_event_depth = max(1, int(options.get("max_event_depth", 8)))
	_index_project()
	var entry_scene_id: String = _resolve_entry_scene_id()
	if entry_scene_id.is_empty():
		_warnings.append("未配置有效的初始场景，无法建立主流程入口。")
	else:
		_explore(entry_scene_id)
	var scene_catalog: Array[Dictionary] = _build_scene_catalog(entry_scene_id)
	var unreachable_scenes: Array[Dictionary] = []
	for row in scene_catalog:
		if row.get("reachability_status", "") == UNREACHABLE:
			unreachable_scenes.append(row)
	return {
		"success": true,
		"data": {
			"entry_scene_id": entry_scene_id,
			"scene_catalog": scene_catalog,
			"unreachable_scenes": unreachable_scenes,
			"unreachable_branches": _branches,
			"warnings": _warnings,
			"limits": {
				"max_total_states": _max_states,
				"max_command_steps": _max_steps,
				"max_event_depth": _max_event_depth,
				"state_limit_hit": _state_limit_hit,
				"path_limit_hit": _path_limit_hit,
			},
		},
	}


func build_scene_catalog(project: Resource, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = analyze(project, options)
	if not bool(result.get("success", false)):
		return result
	var data: Dictionary = result.get("data", {})
	return {"success": true, "data": data.get("scene_catalog", []), "entry_scene_id": data.get("entry_scene_id", "")}


func _reset() -> void:
	_project = null
	_scene_by_id.clear()
	_event_by_id.clear()
	_default_domains.clear()
	_var_keys_by_ref.clear()
	_reachable.clear()
	_definite.clear()
	_incoming.clear()
	_branches.clear()
	_warnings.clear()
	_state_limit_hit = false
	_path_limit_hit = false


func _index_project() -> void:
	for scene in _project.scenes:
		if scene == null:
			continue
		var sid := str(scene.scene_id if "scene_id" in scene else "").strip_edges()
		if not sid.is_empty():
			_scene_by_id[sid] = scene
	for event in _project.events:
		if event == null:
			continue
		var eid := str(event.event_id if "event_id" in event else "").strip_edges()
		if not eid.is_empty():
			_event_by_id[eid] = event
	for variable in _project.variables:
		if variable == null:
			continue
		var vid := str(variable.variable_id if "variable_id" in variable else "").strip_edges()
		var vkey := AVGVariableClass.get_key(variable)
		if vkey.is_empty():
			continue
		_default_domains[vkey] = _exact(variable.default_value if "default_value" in variable else 0)
		_var_keys_by_ref[vkey] = vkey
		if not vid.is_empty():
			_var_keys_by_ref[vid] = vkey


func _resolve_entry_scene_id() -> String:
	if _project.title_config != null:
		var entry := str(_project.title_config.first_scene_id if "first_scene_id" in _project.title_config else "").strip_edges()
		if not entry.is_empty() and _scene_by_id.has(entry):
			return entry
	if not _project.scenes.is_empty():
		var scene: Resource = _project.scenes[0]
		if scene != null and "scene_id" in scene:
			return str(scene.scene_id).strip_edges()
	return ""


func _explore(entry_scene_id: String) -> void:
	var queue: Array[Dictionary] = [{"scene_id": entry_scene_id, "state": _initial_state(), "confidence": "definite"}]
	var visited: Dictionary = {}
	var processed: int = 0
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var scene_id := str(item.get("scene_id", "")).strip_edges()
		if scene_id.is_empty() or not _scene_by_id.has(scene_id):
			continue
		var state: Dictionary = item.get("state", {})
		var confidence := str(item.get("confidence", "definite"))
		var signature := "%s|%s|%s" % [scene_id, confidence, _state_signature(state)]
		if visited.has(signature):
			continue
		visited[signature] = true
		processed += 1
		if processed > _max_states:
			_state_limit_hit = true
			_warnings.append("可达性分析达到状态上限，部分路径被保守截断。")
			break
		_reachable[scene_id] = true
		if confidence == "definite":
			_definite[scene_id] = true
		var commands: Array = _scene_root_commands(_scene_by_id[scene_id])
		var flows: Array = _walk(commands, 0, state, {"scope_id": scene_id, "label_index": _build_label_index(commands), "confidence": confidence, "event_depth": 0, "steps": 0}, {})
		for flow in flows:
			if str(flow.get("kind", "")) != "jump_scene":
				continue
			var target := str(flow.get("target_scene_id", "")).strip_edges()
			if target.is_empty():
				continue
			if not _incoming.has(target):
				_incoming[target] = []
			_incoming[target].append({"from_scene_id": scene_id, "location": flow.get("location", ""), "reason": flow.get("reason", ""), "confidence": flow.get("confidence", confidence)})
			queue.append({"scene_id": target, "state": flow.get("state", state), "confidence": flow.get("confidence", confidence)})


func _initial_state() -> Dictionary:
	var vars: Dictionary = {}
	for key in _default_domains.keys():
		vars[key] = _default_domains[key].duplicate(true)
	return {"vars": vars}


func _scene_root_commands(scene: Resource) -> Array:
	var root: Resource = AVGDevDBTools.find_root_node(scene)
	if root == null or not ("command_tabs" in root) or root.command_tabs == null or root.command_tabs.is_empty():
		return []
	return (root.command_tabs[0] as Dictionary).get("commands", [])


func _build_label_index(commands: Array) -> Dictionary:
	var labels: Dictionary = {}
	for i in range(commands.size()):
		if _cmd_type(commands[i]) != "LABEL":
			continue
		var name := str(_cmd_params(commands[i]).get("name", "")).strip_edges()
		if not name.is_empty():
			labels[name] = i
	return labels


func _walk(commands: Array, index: int, state: Dictionary, ctx: Dictionary, local_seen: Dictionary) -> Array:
	if index >= commands.size():
		return [{"kind": "end", "state": state, "confidence": ctx.get("confidence", "definite")}]
	if int(ctx.get("steps", 0)) >= _max_steps:
		_path_limit_hit = true
		return [{"kind": "unknown_halt", "state": state, "confidence": "conditional", "location": _loc(ctx, index), "reason": "命令步数超过分析上限"}]
	var step_key := "%s|%d|%s" % [str(ctx.get("scope_id", "")), index, _state_signature(state)]
	if local_seen.has(step_key):
		_path_limit_hit = true
		return [{"kind": "unknown_halt", "state": state, "confidence": "conditional", "location": _loc(ctx, index), "reason": "检测到局部循环，提前截断"}]
	var seen_next := local_seen.duplicate(true)
	seen_next[step_key] = true
	var next_ctx := ctx.duplicate(true)
	next_ctx["steps"] = int(ctx.get("steps", 0)) + 1
	var ctype := _cmd_type(commands[index])
	var params := _cmd_params(commands[index])
	match ctype:
		"", "LABEL":
			return _walk(commands, index + 1, state, next_ctx, seen_next)
		"SET_VARIABLE":
			return _walk(commands, index + 1, _apply_set_variable(state, params), next_ctx, seen_next)
		"JUMP_SCENE":
			return [{"kind": "jump_scene", "target_scene_id": str(params.get("scene_id", "")).strip_edges(), "state": state, "confidence": ctx.get("confidence", "definite"), "location": _loc(ctx, index), "reason": "场景跳转"}]
		"JUMP_LABEL":
			var target := str(params.get("target", "")).strip_edges()
			if target.is_empty() or not (ctx.get("label_index", {}) as Dictionary).has(target):
				return [{"kind": "unknown_halt", "state": state, "confidence": "conditional", "location": _loc(ctx, index), "reason": "JUMP_LABEL 目标不存在"}]
			return _walk(commands, int((ctx.get("label_index", {}) as Dictionary)[target]), state, next_ctx, seen_next)
		"CALL_EVENT":
			return _walk_call_event(commands, index, state, params, next_ctx, seen_next)
		"IF":
			return _walk_if(commands, index, state, params, next_ctx, seen_next)
		"CHOICE":
			return _walk_choice(commands, index, state, params, next_ctx, seen_next)
		_:
			return _walk(commands, index + 1, state, next_ctx, seen_next)


func _walk_call_event(commands: Array, index: int, state: Dictionary, params: Dictionary, ctx: Dictionary, seen: Dictionary) -> Array:
	var event_id := str(params.get("event_id", "")).strip_edges()
	if event_id.is_empty():
		return _walk(commands, index + 1, state, ctx, seen)
	if int(ctx.get("event_depth", 0)) >= _max_event_depth or not _event_by_id.has(event_id):
		return [{"kind": "unknown_halt", "state": state, "confidence": "conditional", "location": _loc(ctx, index), "reason": "CALL_EVENT 无法继续展开: %s" % event_id}]
	var event_cmds: Array = _event_by_id[event_id].commands if "commands" in _event_by_id[event_id] else []
	var event_ctx := ctx.duplicate(true)
	event_ctx["scope_id"] = event_id
	event_ctx["label_index"] = _build_label_index(event_cmds)
	event_ctx["event_depth"] = int(ctx.get("event_depth", 0)) + 1
	var flows: Array = []
	for flow in _walk(event_cmds, 0, state, event_ctx, {}):
		if str(flow.get("kind", "")) == "end":
			flows.append_array(_walk(commands, index + 1, flow.get("state", state), ctx, seen))
		else:
			flows.append(flow)
	return flows


func _walk_if(commands: Array, index: int, state: Dictionary, params: Dictionary, ctx: Dictionary, seen: Dictionary) -> Array:
	var cond: Dictionary = _eval_conditions(params.get("condition_commands", []), state)
	var flows: Array = []
	var base := _loc(ctx, index)
	if cond.status == UNREACHABLE:
		_record_branch(base, "if_true", UNREACHABLE, "true 分支不可达：%s" % str(cond.reason), "IF")
	elif cond.status == UNKNOWN:
		_record_branch(base, "if_true", UNKNOWN, "true 分支依赖未知条件：%s" % str(cond.reason), "IF")
	if cond.status != UNREACHABLE:
		var true_conf := "conditional" if cond.status == UNKNOWN else str(ctx.get("confidence", "definite"))
		for flow in _walk_block(params.get("if_commands", []), state, ctx, seen, base + ".if", true_conf):
			if str(flow.get("kind", "")) == "end":
				flows.append_array(_walk(commands, index + 1, flow.get("state", state), _with_conf(ctx, str(flow.get("confidence", true_conf))), seen))
			else:
				flows.append(flow)
	elif not bool(params.get("has_else", false)):
		return _walk(commands, index + 1, state, ctx, seen)
	var else_status := REACHABLE
	var else_reason := "条件为 false"
	if cond.status == REACHABLE:
		else_status = UNREACHABLE
		else_reason = "else 分支不可达：条件恒为 true"
	elif cond.status == UNKNOWN:
		else_status = UNKNOWN
		else_reason = "else 分支依赖未知条件：%s" % str(cond.reason)
	if bool(params.get("has_else", false)):
		if else_status != REACHABLE:
			_record_branch(base, "if_false", else_status, else_reason, "IF")
		if else_status != UNREACHABLE:
			var else_conf := "conditional" if else_status == UNKNOWN else str(ctx.get("confidence", "definite"))
			for flow in _walk_block(params.get("else_commands", []), state, ctx, seen, base + ".else", else_conf):
				if str(flow.get("kind", "")) == "end":
					flows.append_array(_walk(commands, index + 1, flow.get("state", state), _with_conf(ctx, str(flow.get("confidence", else_conf))), seen))
				else:
					flows.append(flow)
	else:
		flows.append_array(_walk(commands, index + 1, state, ctx, seen))
	return flows


func _walk_choice(commands: Array, index: int, state: Dictionary, params: Dictionary, ctx: Dictionary, seen: Dictionary) -> Array:
	var flows: Array = []
	var base := _loc(ctx, index)
	var had_option: bool = false
	var choices: Array = params.get("choices", [])
	for i in range(choices.size()):
		var choice: Dictionary = choices[i] if choices[i] is Dictionary else {}
		var cond: Dictionary = _eval_conditions(choice.get("condition_commands", []), state)
		var branch_type := "choice_%d" % i
		var preview := "选项[%d] %s" % [i, str(choice.get("text", ""))]
		if cond.status == UNREACHABLE:
			_record_branch(base, branch_type, UNREACHABLE, "选项不可达：%s" % str(cond.reason), preview)
			continue
		if cond.status == UNKNOWN:
			_record_branch(base, branch_type, UNKNOWN, "选项依赖未知条件：%s" % str(cond.reason), preview)
		had_option = true
		var option_conf := "conditional" if cond.status == UNKNOWN else str(ctx.get("confidence", "definite"))
		for flow in _walk_block(choice.get("commands", []), state, ctx, seen, "%s.choice_%d" % [base, i], option_conf):
			if str(flow.get("kind", "")) == "end":
				flows.append_array(_walk(commands, index + 1, flow.get("state", state), _with_conf(ctx, str(flow.get("confidence", option_conf))), seen))
			else:
				flows.append(flow)
	if not had_option:
		return [{"kind": "unknown_halt", "state": state, "confidence": "conditional", "location": base, "reason": "CHOICE 没有任何可达选项"}]
	return flows


func _walk_block(block_cmds: Array, state: Dictionary, ctx: Dictionary, seen: Dictionary, scope_id: String, confidence: String) -> Array:
	if block_cmds.is_empty():
		return [{"kind": "end", "state": state, "confidence": confidence}]
	var nested_ctx := ctx.duplicate(true)
	nested_ctx["scope_id"] = scope_id
	nested_ctx["label_index"] = _build_label_index(block_cmds)
	nested_ctx["confidence"] = confidence
	return _walk(block_cmds, 0, state, nested_ctx, seen)


func _eval_conditions(commands: Array, state: Dictionary) -> Dictionary:
	if commands.is_empty():
		return {"status": REACHABLE, "reason": "无条件"}
	for cmd in commands:
		var ctype := _cmd_type(cmd)
		var params := _cmd_params(cmd)
		match ctype:
			"CHECK_VAR":
				var result: Dictionary = _eval_check_var(params, state)
				if result.status != REACHABLE:
					return result
			"CHECK_HOVER", "CHECK_CLICK":
				continue
			"IF":
				return {"status": UNKNOWN, "reason": "嵌套 IF 条件暂按 unknown 处理"}
			_:
				return {"status": UNKNOWN, "reason": "条件命令 %s 暂不支持静态证明" % ctype}
	return {"status": REACHABLE, "reason": "条件满足"}


func _eval_check_var(params: Dictionary, state: Dictionary) -> Dictionary:
	var vkey := _resolve_var_key(params, "variable_id", "variable_key", "variable_name")
	if vkey.is_empty():
		return {"status": UNKNOWN, "reason": "CHECK_VAR 缺少变量引用"}
	if str(params.get("value_source", "constant")).strip_edges() == "game_data":
		return {"status": REACHABLE, "reason": "game_data 条件按可推进路径处理"}
	var lhs: Dictionary = _get_domain(state, vkey)
	var rhs: Dictionary = _resolve_compare_domain(params, state)
	var op := str(params.get("operator", "==")).strip_edges()
	var result: Dictionary = _compare(lhs, op, rhs)
	if result.status == REACHABLE:
		return {"status": REACHABLE, "reason": "%s 满足 %s %s" % [vkey, op, _domain_text(rhs)]}
	if result.status == UNREACHABLE:
		return {"status": UNREACHABLE, "reason": "%s 当前为 %s，无法满足 %s %s" % [vkey, _domain_text(lhs), op, _domain_text(rhs)]}
	_report_unknown_check_var(vkey, op, lhs, rhs, result)
	return {"status": UNKNOWN, "reason": "%s 当前为 %s，无法静态证明是否满足 %s %s" % [vkey, _domain_text(lhs), op, _domain_text(rhs)]}


func _resolve_compare_domain(params: Dictionary, state: Dictionary) -> Dictionary:
	match str(params.get("value_source", "constant")).strip_edges():
		"variable":
			var source_key := _resolve_var_key(params, "source_variable_id", "source_variable_key", "source_variable_name")
			return _get_domain(state, source_key) if not source_key.is_empty() else _unknown("源变量引用缺失")
		"game_data":
			return _unknown("依赖 game_data:%s" % str(params.get("game_data_key", "")))
		_:
			return _exact(_parse_value(params.get("value", 0)))


func _apply_set_variable(state: Dictionary, params: Dictionary) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	var vars: Dictionary = next_state.get("vars", {})
	var target_key := _resolve_var_key(params, "variable_id", "variable_key", "variable_name")
	if target_key.is_empty():
		return next_state
	var current: Dictionary = _get_domain(next_state, target_key)
	var operand: Dictionary = _resolve_set_value_domain(params, next_state)
	var op := str(params.get("operation", "set")).strip_edges()
	vars[target_key] = _apply_op(current, op, operand)
	next_state["vars"] = vars
	return next_state


func _resolve_set_value_domain(params: Dictionary, state: Dictionary) -> Dictionary:
	match str(params.get("value_source", "constant")).strip_edges():
		"constant":
			return _exact(_parse_value(params.get("value", 0)))
		"variable":
			var source_key := _resolve_var_key(params, "source_variable_id", "source_variable_key", "source_variable_name")
			return _get_domain(state, source_key) if not source_key.is_empty() else _unknown("SET_VARIABLE 缺少源变量")
		"random":
			var rmin := int(params.get("random_min", 0))
			var rmax := int(params.get("random_max", 100))
			if rmin > rmax:
				var tmp := rmin
				rmin = rmax
				rmax = tmp
			return {"kind": "range", "min": rmin, "max": rmax}
		"game_data":
			return _unknown("SET_VARIABLE 依赖 game_data:%s" % str(params.get("game_data_key", "")))
		_:
			return _unknown("未知 value_source")


func _apply_op(current: Dictionary, op: String, operand: Dictionary) -> Dictionary:
	if op == "set":
		return operand.duplicate(true)
	if current.kind == "exact" and operand.kind == "exact" and (current.value is int or current.value is float) and (operand.value is int or operand.value is float):
		var lhs := float(current.value)
		var rhs := float(operand.value)
		match op:
			"add": return _exact(lhs + rhs)
			"subtract": return _exact(lhs - rhs)
			"multiply": return _exact(lhs * rhs)
			"divide": return _unknown("除以 0") if is_zero_approx(rhs) else _exact(lhs / rhs)
			"modulo": return _unknown("模 0") if is_zero_approx(rhs) else _exact(int(lhs) % int(rhs))
	if op in ["add", "subtract"] and current.kind == "range" and operand.kind == "exact" and (operand.value is int or operand.value is float):
		var delta := float(operand.value) * (1.0 if op == "add" else -1.0)
		return {"kind": "range", "min": float(current.min) + delta, "max": float(current.max) + delta}
	return _unknown("无法静态推导 %s 结果" % op)


func _compare(lhs: Dictionary, op: String, rhs: Dictionary) -> Dictionary:
	if lhs.kind == "exact" and rhs.kind == "exact":
		if not _can_compare_exact_values(lhs.value, op, rhs.value):
			return {
				"status": UNKNOWN,
				"reason": "无法比较 %s %s %s" % [
					_type_label(lhs.value),
					op,
					_type_label(rhs.value),
				],
			}
		return {"status": REACHABLE if _compare_values(lhs.value, op, rhs.value) else UNREACHABLE}
	if lhs.kind == "range" and rhs.kind == "exact" and (rhs.value is int or rhs.value is float):
		var target := float(rhs.value)
		var lo := float(lhs.min)
		var hi := float(lhs.max)
		match op:
			"==": return {"status": UNREACHABLE if target < lo or target > hi else UNKNOWN}
			"!=": return {"status": UNREACHABLE if lo == hi and lo == target else UNKNOWN}
			">": return {"status": REACHABLE if lo > target else (UNREACHABLE if hi <= target else UNKNOWN)}
			">=": return {"status": REACHABLE if lo >= target else (UNREACHABLE if hi < target else UNKNOWN)}
			"<": return {"status": REACHABLE if hi < target else (UNREACHABLE if lo >= target else UNKNOWN)}
			"<=": return {"status": REACHABLE if hi <= target else (UNREACHABLE if lo > target else UNKNOWN)}
	if lhs.kind == "exact" and rhs.kind == "range" and (lhs.value is int or lhs.value is float):
		return _compare(rhs, _swap_op(op), lhs)
	return {"status": UNKNOWN}


func _swap_op(op: String) -> String:
	match op:
		">": return "<"
		">=": return "<="
		"<": return ">"
		"<=": return ">="
		_: return op


func _compare_values(actual: Variant, op: String, expected: Variant) -> bool:
	if op in [">", ">=", "<", "<="]:
		if actual is int or actual is float or expected is int or expected is float:
			var lhs_num := float(actual)
			var rhs_num := float(expected)
			match op:
				">": return lhs_num > rhs_num
				">=": return lhs_num >= rhs_num
				"<": return lhs_num < rhs_num
				"<=": return lhs_num <= rhs_num
		if actual is String and expected is String:
			match op:
				">": return String(actual) > String(expected)
				">=": return String(actual) >= String(expected)
				"<": return String(actual) < String(expected)
				"<=": return String(actual) <= String(expected)
	match op:
		"==": return actual == expected
		"!=": return actual != expected
		">": return actual > expected
		">=": return actual >= expected
		"<": return actual < expected
		"<=": return actual <= expected
		_: return false


func _can_compare_exact_values(actual: Variant, op: String, expected: Variant) -> bool:
	if op in ["==", "!="]:
		return true
	if op in [">", ">=", "<", "<="]:
		var actual_numeric: bool = actual is int or actual is float
		var expected_numeric: bool = expected is int or expected is float
		if actual_numeric and expected_numeric:
			return true
		if actual is String and expected is String:
			return true
		return false
	return false


func _type_label(value: Variant) -> String:
	if value is int:
		return "int"
	if value is float:
		return "float"
	if value is String:
		return "String"
	if value is bool:
		return "bool"
	if value == null:
		return "null"
	return type_string(typeof(value))


func _resolve_var_key(params: Dictionary, id_field: String, key_field: String, legacy_field: String) -> String:
	var raw_id := str(params.get(id_field, "")).strip_edges()
	if not raw_id.is_empty() and _var_keys_by_ref.has(raw_id):
		return str(_var_keys_by_ref[raw_id])
	var raw_key := str(params.get(key_field, params.get(legacy_field, ""))).strip_edges()
	return "" if raw_key.is_empty() else AVGVariableClass.normalize_key(raw_key)


func _get_domain(state: Dictionary, variable_key: String) -> Dictionary:
	if variable_key.is_empty():
		return _unknown("变量引用为空")
	var normalized := AVGVariableClass.normalize_key(variable_key)
	var vars: Dictionary = state.get("vars", {})
	if vars.has(normalized):
		return vars[normalized].duplicate(true)
	if _default_domains.has(normalized):
		return _default_domains[normalized].duplicate(true)
	return _unknown("变量 %s 没有默认值" % normalized)


func _exact(value: Variant) -> Dictionary:
	return {"kind": "exact", "value": value}


func _unknown(why: String) -> Dictionary:
	return {"kind": "unknown", "why": why}


func _report_unknown_check_var(vkey: String, op: String, lhs: Dictionary, rhs: Dictionary, result: Dictionary) -> void:
	var detail := str(result.get("reason", "")).strip_edges()
	if detail.is_empty():
		return
	var message := "[StoryReachability] CHECK_VAR 无法静态证明: %s (%s) %s %s (%s) | %s" % [
		vkey,
		_domain_text(lhs),
		op,
		_domain_text(rhs),
		str(rhs.get("kind", "unknown")),
		detail,
	]
	print(message)
	push_warning(message)


func _parse_value(value: Variant) -> Variant:
	return AVGVariableClass.normalize_script_literal(value)


func _state_signature(state: Dictionary) -> String:
	var vars: Dictionary = state.get("vars", {})
	var keys: Array = vars.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		var domain: Dictionary = vars[key]
		match str(domain.get("kind", "unknown")):
			"exact": parts.append("%s=%s" % [key, JSON.stringify(domain.get("value", null))])
			"range": parts.append("%s=[%s,%s]" % [key, str(domain.get("min", "")), str(domain.get("max", ""))])
			_: parts.append("%s=?" % key)
	return "|".join(parts)


func _domain_text(domain: Dictionary) -> String:
	match str(domain.get("kind", "unknown")):
		"exact": return str(domain.get("value", null))
		"range": return "[%s,%s]" % [str(domain.get("min", "")), str(domain.get("max", ""))]
		_: return "unknown(%s)" % str(domain.get("why", ""))


func _loc(ctx: Dictionary, index: int) -> String:
	return "%s:%d" % [str(ctx.get("scope_id", "")), index + 1]


func _with_conf(ctx: Dictionary, confidence: String) -> Dictionary:
	var next_ctx := ctx.duplicate(true)
	next_ctx["confidence"] = confidence
	return next_ctx


func _record_branch(location: String, branch_type: String, status: String, reason: String, preview: String) -> void:
	_branches.append({"location": location, "branch_type": branch_type, "status": status, "reason": reason, "preview": preview})


func _build_scene_catalog(entry_scene_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for scene in _project.scenes:
		if scene == null:
			continue
		var sid := str(scene.scene_id if "scene_id" in scene else "").strip_edges()
		if sid.is_empty():
			continue
		var reachable := _reachable.has(sid)
		var definite := _definite.has(sid)
		var branch_warning_count: int = 0
		for branch in _branches:
			if str(branch.get("location", "")).begins_with(sid + ":"):
				branch_warning_count += 1
		var display_name := "%s (%s)" % [str(scene.scene_name if "scene_name" in scene else ""), sid]
		if sid == entry_scene_id:
			display_name = "(初始场景) " + display_name
		var is_placeholder: bool = AVGDevDBTools.is_placeholder_scene(scene)
		if is_placeholder:
			display_name += "（占位待实现）"
		if not reachable and sid != entry_scene_id:
			display_name += "（该场景为孤立场景）"
		rows.append({
			"scene_id": sid,
			"scene_name": str(scene.scene_name if "scene_name" in scene else ""),
			"scene_note": str(scene.scene_note if "scene_note" in scene else ""),
			"folder": str(scene.folder if "folder" in scene else ""),
			"is_placeholder": is_placeholder,
			"is_initial": sid == entry_scene_id,
			"reachability_status": REACHABLE if reachable else UNREACHABLE,
			"reachability_confidence": "definite" if definite else ("conditional" if reachable else "none"),
			"is_isolated": not reachable and sid != entry_scene_id,
			"is_definitely_reachable": definite,
			"is_conditionally_reachable": reachable and not definite,
			"isolation_reason": "" if reachable or sid == entry_scene_id else _isolation_reason(sid),
			"incoming_edges": _incoming.get(sid, []),
			"branch_warning_count": branch_warning_count,
			"display_name": display_name,
		})
	return rows


func _isolation_reason(scene_id: String) -> String:
	var edges: Array = _incoming.get(scene_id, [])
	if edges.is_empty():
		return "没有任何 JUMP_SCENE 或可展开事件链路指向该场景"
	var conditional_only: bool = true
	for edge in edges:
		if str(edge.get("confidence", "")) == "definite":
			conditional_only = false
			break
	if conditional_only:
		return "仅存在依赖未知运行时条件的入口，当前分析无法证明其一定可达"
	return "所有指向它的入口都来自不可达链路，或入口条件在静态分析下无法满足"


func _cmd_type(cmd: Variant) -> String:
	if cmd is Resource and "command_type" in cmd:
		return str(cmd.command_type)
	if cmd is Dictionary:
		return str(cmd.get("command_type", ""))
	return ""


func _cmd_params(cmd: Variant) -> Dictionary:
	if cmd is Resource and "params" in cmd:
		return cmd.params if cmd.params is Dictionary else {}
	if cmd is Dictionary:
		return cmd.get("params", {})
	return {}
