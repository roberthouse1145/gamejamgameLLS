class_name ChatAgent extends Node
## 通用 Chat Agent
## 管理对话历史、system prompt、工具注册。
## AIService 只负责发送请求，对话历史由 ChatAgent 管理。

#region 信号
signal message_completed(request_id: String, content: String)
signal message_failed(request_id: String, error: String)
signal tool_executed(request_id: String, tool_name: String, args: Dictionary, result: Variant, tool_call_id: String)
signal log_entry(entry: Dictionary)
#endregion

#region 导出属性
@export var role: String = ""
@export var prompt_key: String = ""
#endregion

#region 节点引用
@onready var _ai_service: AIService = $AIService
#endregion

#region 内部状态
## 对话历史 — 由 ChatAgent 管理，不再依赖 AIService
var _messages: Array = []
var _system_prompt: String = ""
var _is_busy: bool = false
var _pending_tool_call_content: String = ""
## sub-agent 注册表: tool_name -> {agent: ChatAgent, description: String, queued: bool}
var _sub_agents: Dictionary = {}
## 已激活的 skills: [{name: String, instructions: String}]
var _active_skills: Array[Dictionary] = []
## 可用 skills 注册表: skill_name -> {description: String, instructions: String, keywords: Array}
var _available_skills: Dictionary = {}
#endregion

#region 配置
## 是否在存入历史前剥离 <thinking> 标签内容（节省 token）
var strip_thinking_from_history: bool = true
## 最大历史消息数（0 = 不限制）
var max_history_messages: int = 50
## 最大历史字符预算（0 = 不限制，按近似字符数裁剪）
var max_history_chars: int = 12000
## 尽量保留最近多少条消息不被优先裁剪
var history_preserve_recent_messages: int = 6
## 是否在 system prompt 中附带所有可用 skills 元数据。
## 默认开启，确保模型知道可激活的 skills 及其使用场景。
var include_available_skills_metadata_in_prompt: bool = true
const TOOL_HISTORY_PREVIEW_CHARS: int = 220
const TOOL_HISTORY_MAX_ITEMS: int = 6
#endregion


#region 生命周期
func _ready() -> void:
	_ai_service.request_completed.connect(_on_request_completed)
	_ai_service.request_failed.connect(_on_request_failed)
	_ai_service.tool_executed.connect(_on_tool_executed)

	# 用 AIConfigManager 配置 AIService
	if not role.is_empty():
		AIConfigManager.get_instance().apply_to_service(_ai_service, role)
#endregion


#region 公共 API

## 发送消息。自动管理对话历史和 system prompt。
func send_message(text: String) -> String:
	return send_message_with_options(text, {})


## 发送消息，并给底层 AIService 传入本轮请求选项。
func send_message_with_options(text: String, request_options: Dictionary = {}) -> String:
	if _is_busy:
		_emit_log("error", "Agent 正忙，无法处理新消息")
		return ""

	_is_busy = true
	_pending_tool_call_content = ""

	# 首次对话时设置 system prompt
	if _messages.is_empty() and _system_prompt.is_empty():
		_system_prompt = _resolve_prompt()

	# 添加用户消息到历史
	_messages.append({"role": "user", "content": text})
	_trim_history()

	# 构建完整 messages 数组发给 AIService
	var full_messages: Array = _build_messages_for_api()

	# 带上已注册的 tools（如果有的话）
	var options: Dictionary = {
		"auto_execute": true,
		"tool_result_summarizer": Callable(self, "_summarize_tool_result_for_history"),
	}
	options.merge(request_options, true)
	var tools: Array = _ai_service.get_tools_definition()
	if tools.size() > 0:
		options["tools"] = tools
		options["tool_choice"] = "auto"
		options["auto_tools"] = true

	var request_id: String = _ai_service.chat(full_messages, options)
	return request_id


## 重置对话历史。
func reset() -> void:
	# 先停用所有 skill（移除专属工具）
	for s in _active_skills:
		var tool_names: Array = s.get("tool_names", [])
		for tname in tool_names:
			_ai_service.unregister_tool(tname)
	_active_skills.clear()
	_messages.clear()
	_system_prompt = ""
	_is_busy = false
	_pending_tool_call_content = ""


## 显式设置当前回合使用的 system prompt。
## 适合外部已经构建好完整 prompt、只需要借助 ChatAgent 做工具调用编排的场景。
func set_system_prompt_override(system_prompt: String) -> void:
	_system_prompt = system_prompt.strip_edges()


## 注册普通工具。
func register_tool(tool_name: String, description: String, schema: Dictionary, callback: Callable, llm_view: Variant = null, metadata: Dictionary = {}) -> void:
	_ai_service.register_tool(tool_name, description, schema, callback, llm_view, metadata)


## 注册 sub-agent 工具。
func register_sub_agent_tool(tool_name: String, description: String, agent: Node, queued: bool = false) -> void:
	var schema: Dictionary = {
		"type": "object",
		"properties": {
			"task": {
				"type": "string",
				"description": "要委托给子代理执行的任务描述"
			}
		},
		"required": ["task"]
	}

	_sub_agents[tool_name] = {
		"agent": agent,
		"description": description,
		"queued": queued,
		"queue": [],
		"queue_active": false,
	}

	_ai_service.register_tool(
		tool_name,
		description,
		schema,
		func(args: Dictionary) -> Dictionary: return await _execute_sub_agent(tool_name, args),
		["success", "data", "error"],
		{"effect": "write"}
	)


## 向历史中手动添加消息（不发送请求）。
func add_message(msg_role: String, content: String) -> void:
	_messages.append({"role": msg_role, "content": content})
	_trim_history()


## 获取对话历史副本。
func get_messages() -> Array:
	return _messages.duplicate(true)


## 是否正忙。
func is_busy() -> bool:
	return _is_busy


## 注册一个可用 skill（元数据 + 完整指令 + 可选专属工具）。
## 注册后 AI 可通过 activate_skill tool 激活它。
## [param tools] 可选的专属工具数组，每个元素: {name, description, schema, callback}
##   激活 skill 时自动注册这些工具，停用时自动移除。
func register_skill(skill_name: String, description: String, instructions: String, keywords: Array = [], tools: Array = []) -> void:
	_available_skills[skill_name] = {
		"description": description,
		"instructions": instructions,
		"keywords": keywords,
		"tools": tools,
	}


## 激活一个 skill — 注入指令到 system prompt，并注册专属工具。
func activate_skill(skill_name: String) -> Dictionary:
	if not _available_skills.has(skill_name):
		return {"success": false, "error": "未知的 skill: " + skill_name}
	# 检查是否已激活
	for s in _active_skills:
		if s.name == skill_name:
			return {"success": true, "message": "skill '%s' 已经处于激活状态" % skill_name}
	var skill: Dictionary = _available_skills[skill_name]
	var skill_tools: Array = skill.get("tools", [])
	var tool_names: Array[String] = []

	# 注册 skill 专属工具
	for t in skill_tools:
		var tname: String = t.get("name", "")
		if tname.is_empty():
			continue
		_ai_service.register_tool(tname, t.get("description", ""), t.get("schema", {}), t.get("callback", Callable()), t.get("llm_view", null), t.get("metadata", {}))
		tool_names.append(tname)

	_active_skills.append({"name": skill_name, "instructions": skill.instructions, "tool_names": tool_names})
	_rebuild_system_prompt()
	_emit_log("progress", "skill '%s' 已激活 (tools: %s)" % [skill_name, str(tool_names)])
	return {"success": true, "message": "skill '%s' 已激活" % skill_name}


## 停用一个 skill — 移除指令和专属工具。
func deactivate_skill(skill_name: String) -> Dictionary:
	for i in range(_active_skills.size()):
		if _active_skills[i].name == skill_name:
			# 移除 skill 专属工具
			var tool_names: Array = _active_skills[i].get("tool_names", [])
			for tname in tool_names:
				_ai_service.unregister_tool(tname)
			_active_skills.remove_at(i)
			_rebuild_system_prompt()
			_emit_log("progress", "skill '%s' 已停用 (removed tools: %s)" % [skill_name, str(tool_names)])
			return {"success": true, "message": "skill '%s' 已停用" % skill_name}
	return {"success": false, "error": "skill '%s' 未激活" % skill_name}


## 获取当前激活的 skill 列表。
func get_active_skills() -> Array[String]:
	var result: Array[String] = []
	for s in _active_skills:
		result.append(s.name)
	return result


## 获取所有可用 skill 的元数据（名称+描述，不含完整指令）。
func get_available_skills_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill_name in _available_skills:
		var skill: Dictionary = _available_skills[skill_name]
		var skill_tools: Array = skill.get("tools", [])
		result.append({
			"name": skill_name,
			"description": skill.description,
			"keywords": skill.keywords,
			"tool_count": skill_tools.size(),
			"active": skill_name in get_active_skills(),
		})
	return result


## 获取当前生效的完整 system prompt（含 skill 注入后的结果，用于 debug）。
func get_effective_system_prompt() -> String:
	var msgs: Array = _build_messages_for_api()
	if msgs.size() > 0 and msgs[0].get("role", "") == "system":
		return msgs[0].get("content", "")
	return ""
#endregion


#region Sub-Agent 执行

## Hook: 子类可重写以包装 sub-agent 的 task。
## 默认返回原 task；子类可在前面注入稳定前缀（如项目索引），
## 让 sub-agent 不必自己重复探索资源/索引。
func _prepare_sub_agent_task(_tool_name: String, task: String) -> String:
	return task


func _execute_sub_agent(tool_name: String, args: Dictionary) -> Dictionary:
	var sub_info: Dictionary = _sub_agents.get(tool_name, {})
	var agent: Node = sub_info.get("agent", null)
	if agent == null:
		return {"success": false, "error": "Sub-agent not found for tool: " + tool_name}

	var task: String = args.get("task", "")
	if task.is_empty():
		return {"success": false, "error": "task is required"}

	var prepared_task: String = _prepare_sub_agent_task(tool_name, task)
	var use_queue: bool = bool(sub_info.get("queued", false))
	if use_queue:
		await _acquire_sub_agent_queue_turn(tool_name, task)

	var result: Dictionary = await _run_sub_agent_task(tool_name, agent, task, prepared_task)

	if use_queue:
		_release_sub_agent_queue_turn(tool_name)

	return result


func _run_sub_agent_task(tool_name: String, agent: Node, task: String, prepared_task: String) -> Dictionary:

	_emit_log("progress", "委托子代理 [%s]: %s" % [tool_name, task.left(100)])

	var state: Dictionary = {"completed": false, "content": "", "has_error": false, "error": ""}

	var on_completed: Callable = func(_req_id: String, content: String) -> void:
		state["content"] = content
		state["completed"] = true

	var on_failed: Callable = func(_req_id: String, error: String) -> void:
		state["has_error"] = true
		state["error"] = error
		state["completed"] = true

	agent.message_completed.connect(on_completed, CONNECT_ONE_SHOT)
	agent.message_failed.connect(on_failed, CONNECT_ONE_SHOT)

	var request_id: String = str(agent.send_message(prepared_task))
	if request_id.is_empty():
		if agent.message_completed.is_connected(on_completed):
			agent.message_completed.disconnect(on_completed)
		if agent.message_failed.is_connected(on_failed):
			agent.message_failed.disconnect(on_failed)
		return {"success": false, "error": "Sub-agent is busy and did not accept task: " + tool_name}

	while not state["completed"]:
		await get_tree().process_frame

	if state["has_error"]:
		_emit_log("error", "子代理 [%s] 失败: %s" % [tool_name, state["error"]])
		agent.reset()
		return {"success": false, "error": state["error"]}

	var extracted: String = _extract_result_tag(state["content"])
	_emit_log("progress", "子代理 [%s] 完成" % tool_name)

	agent.reset()

	return {"success": true, "data": extracted}


func _acquire_sub_agent_queue_turn(tool_name: String, task: String) -> void:
	var sub_info: Dictionary = _sub_agents.get(tool_name, {})
	if not bool(sub_info.get("queue_active", false)):
		sub_info["queue_active"] = true
		_sub_agents[tool_name] = sub_info
		return

	var queue: Array = sub_info.get("queue", [])
	var turn: Dictionary = {"active": false}
	queue.append(turn)
	sub_info["queue"] = queue
	_sub_agents[tool_name] = sub_info
	_emit_log("progress", "子代理 [%s] 排队中（前方 %d 个）: %s" % [tool_name, queue.size(), task.left(80)])

	while not bool(turn.get("active", false)):
		await get_tree().process_frame


func _release_sub_agent_queue_turn(tool_name: String) -> void:
	var sub_info: Dictionary = _sub_agents.get(tool_name, {})
	var queue: Array = sub_info.get("queue", [])
	if queue.is_empty():
		sub_info["queue_active"] = false
		_sub_agents[tool_name] = sub_info
		return

	var next_turn: Dictionary = queue.pop_front()
	next_turn["active"] = true
	sub_info["queue"] = queue
	sub_info["queue_active"] = true
	_sub_agents[tool_name] = sub_info


func _extract_result_tag(text: String) -> String:
	var start_tag: String = "<result>"
	var end_tag: String = "</result>"
	var start_idx: int = text.find(start_tag)
	var end_idx: int = text.find(end_tag)

	if start_idx == -1 or end_idx == -1 or end_idx <= start_idx:
		return text.strip_edges()

	return text.substr(start_idx + start_tag.length(), end_idx - start_idx - start_tag.length()).strip_edges()


func _append_pending_tool_call_content(existing: String, next_content: String) -> String:
	var normalized_next := next_content.strip_edges()
	if normalized_next.is_empty():
		return existing
	var normalized_existing := existing.strip_edges()
	if normalized_existing.is_empty():
		return normalized_next
	return "%s\n%s" % [normalized_existing, normalized_next]


func _build_completed_content(content: String) -> String:
	var normalized_content := content.strip_edges()
	if role != "linkchat":
		return normalized_content
	var pending_content := _pending_tool_call_content.strip_edges()
	if pending_content.is_empty():
		return normalized_content
	if normalized_content.is_empty():
		return pending_content
	return "%s\n%s" % [pending_content, normalized_content]
#endregion


#region AIService 信号处理

func _on_request_completed(_request_id: String, response: Dictionary) -> void:
	if not _is_busy:
		return

	if role == "linkchat":
		print("[ChatAgent] AI full response BEGIN (%s)" % role)
		print(JSON.stringify(response, "  "))
		print("[ChatAgent] AI full response END (%s)" % role)

	var content: String = ""
	var has_tool_calls: bool = false
	if response.has("choices") and response.choices.size() > 0:
		var message: Dictionary = response.choices[0].get("message", {})
		var tool_calls_value: Variant = message.get("tool_calls", null)
		var tool_calls: Array = tool_calls_value if tool_calls_value is Array else []
		has_tool_calls = tool_calls.size() > 0
		var msg_content: String = AIService.extract_content(response)
		if not msg_content.is_empty():
			content = msg_content

	# 将 assistant 回复存入历史（可选剥离 thinking）
	if not content.is_empty() or has_tool_calls:
		var history_content: String = _strip_thinking(content) if strip_thinking_from_history else content
		var assistant_msg: Dictionary = {"role": "assistant"}
		if not history_content.is_empty():
			assistant_msg["content"] = history_content
		else:
			assistant_msg["content"] = null
		
		# 如果是工具调用响应，必须存入 tool_calls 才能保证下一轮对话不中断
		if has_tool_calls:
			if role == "linkchat" and not history_content.is_empty():
				_pending_tool_call_content = _append_pending_tool_call_content(_pending_tool_call_content, history_content)
			var message_node: Dictionary = response.choices[0].get("message", {})
			var message_tool_calls_value: Variant = message_node.get("tool_calls", null)
			var message_tool_calls: Array = message_tool_calls_value if message_tool_calls_value is Array else []
			assistant_msg["tool_calls"] = message_tool_calls
			
		_messages.append(assistant_msg)
		_trim_history()
		_emit_log("ai_response", content)

	# 如果存在 tool_calls，这只是一个中间返回（AIService 还在忙着自动执行跑工具）
	# 此时我们可以把阶段性文本展示给前端，但不要结束 agent 的 busyness
	if not has_tool_calls:
		_is_busy = false
		# 最终完成：没有 tool_calls，发出 message_completed
		var completed_content: String = _build_completed_content(content)
		if not completed_content.is_empty():
			message_completed.emit(_request_id, completed_content)
		else:
			message_completed.emit(_request_id, "")
		_pending_tool_call_content = ""
	# 有 tool_calls 时不发 message_completed，等工具执行完后 AIService 会再次回调


func _on_request_failed(_request_id: String, error: String, _error_code: int) -> void:
	if not _is_busy:
		return

	_emit_log("error", "请求失败: " + error)
	_is_busy = false
	_pending_tool_call_content = ""
	message_failed.emit(_request_id, error)


func _on_tool_executed(_request_id: String, tool_name: String, arguments: Dictionary, result: Variant, tool_call_id: String) -> void:
	_emit_log("tool_call", "调用工具: %s(%s)" % [tool_name, str(arguments).left(150)])
	if result != null:
		_emit_log("tool_result", "结果: %s" % str(result).left(200))

	# 将工具执行结果存入 history，否则下一轮对话模型将无法感知工具产出
	_messages.append({
		"role": "tool",
		"tool_call_id": tool_call_id,
		"content": _summarize_tool_result_for_history(tool_name, result)
	})
	_trim_history()
	
	tool_executed.emit(_request_id, tool_name, arguments, result, tool_call_id)
#endregion


#region 辅助方法

## 生成对话 ID。子类可覆盖以自定义前缀。
func _generate_conversation_id() -> String:
	return "agent_" + str(Time.get_ticks_msec()) + "_" + str(randi())


## 构建发给 API 的完整 messages 数组（system prompt + skill 注入 + 历史）
## skill 注入策略：
##   - 已激活 skill 的完整指令：有 {%skill_prompt%} 标记则替换，否则追加
##   - 可用 skill 元数据列表：默认动态追加到末尾；如显式关闭则不注入
## 注意：使用 {%...%} 而非 {{...}} 避免与 PromptManager 的 {{key}} 模板冲突
func _build_messages_for_api() -> Array:
	var result: Array = []
	var combined_prompt: String = _system_prompt

	# 1) 已激活 skill 的完整指令注入
	if not _active_skills.is_empty():
		var skill_block: String = ""
		for s in _active_skills:
			skill_block += "\n## [Skill: %s]\n%s\n" % [s.name, s.instructions]

		if combined_prompt.find("{%skill_prompt%}") != -1:
			combined_prompt = combined_prompt.replace("{%skill_prompt%}", skill_block)
		else:
			combined_prompt += "\n\n# 已激活的 Skills\n" + skill_block
	else:
		combined_prompt = combined_prompt.replace("{%skill_prompt%}", "")

	# 2) 可用 skill 元数据默认注入，确保模型知道有哪些 skill 可激活
	if include_available_skills_metadata_in_prompt and not _available_skills.is_empty():
		var meta_section: String = "\n\n# 可用 Skills\n"
		for sname in _available_skills:
			var s: Dictionary = _available_skills[sname]
			var parts: Array[String] = ["- %s: %s" % [sname, s.description]]
			var keywords: Array = s.get("keywords", [])
			if not keywords.is_empty():
				parts.append("关键词=%s" % "/".join(PackedStringArray(keywords)))
			var skill_tools: Array = s.get("tools", [])
			if not skill_tools.is_empty():
				parts.append("激活后附带 %d 个工具" % skill_tools.size())
			meta_section += " | ".join(parts) + "\n"
		combined_prompt += meta_section

	if not combined_prompt.is_empty():
		result.append({"role": "system", "content": combined_prompt})
	result.append_array(_strip_orphaned_tool_messages(_messages))
	return result


func _strip_orphaned_tool_messages(messages: Array) -> Array:
	var out: Array = []
	for msg in messages:
		if str(msg.get("role", "")) == "tool":
			var last_assistant_has_calls: bool = false
			for i in range(out.size() - 1, -1, -1):
				var prev: Dictionary = out[i]
				if str(prev.get("role", "")) == "assistant":
					last_assistant_has_calls = prev.has("tool_calls")
					break
				if str(prev.get("role", "")) in ["user", "system"]:
					break
			if not last_assistant_has_calls:
				continue
		out.append(msg)
	return out


## 解析 prompt：从 PromptManager 获取并替换模板变量。
func _resolve_prompt() -> String:
	if prompt_key.is_empty():
		return ""
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		push_warning("ChatAgent: PromptManager autoload not found")
		return ""
	return pm.resolve(prompt_key)


## 重建 system prompt（skill 激活/停用时调用）。
## 基础 prompt 不变，skill 注入在 _build_messages_for_api 中动态拼接。
func _rebuild_system_prompt() -> void:
	# 如果 base prompt 还没初始化，先初始化
	if _system_prompt.is_empty():
		_system_prompt = _resolve_prompt()


## 剥离 <thinking>...</thinking> 标签及其内容
func _strip_thinking(text: String) -> String:
	var paired_regex: RegEx = RegEx.new()
	paired_regex.compile("^\\s*<(thinking|think)>([\\s\\S]*?)</(thinking|think)>\\s*")
	var paired_match := paired_regex.search(text)
	if paired_match:
		return text.substr(paired_match.get_end()).strip_edges()

	var truncated_regex: RegEx = RegEx.new()
	truncated_regex.compile("^\\s*<(thinking|think)>([\\s\\S]*)$")
	var truncated_match := truncated_regex.search(text)
	if truncated_match:
		var content_after_tag := truncated_match.get_string(2)
		var body_start := content_after_tag.find("\n@")
		if body_start == -1:
			body_start = content_after_tag.find("\n{")
		if body_start == -1:
			body_start = content_after_tag.find("\n#")
		if body_start == -1:
			body_start = content_after_tag.find("\n[")
		if body_start == -1:
			body_start = content_after_tag.find("\n>")
		if body_start >= 0:
			return content_after_tag.substr(body_start).strip_edges()

	return text.strip_edges()


## 裁剪历史消息数量
func _trim_history() -> void:
	while _is_history_over_budget():
		var remove_idx: int = _find_history_trim_candidate_index()
		if remove_idx < 0:
			break
		_messages.remove_at(remove_idx)


func _is_history_over_budget() -> bool:
	var over_message_limit: bool = max_history_messages > 0 and _messages.size() > max_history_messages
	var over_char_budget: bool = max_history_chars > 0 and _estimate_history_chars() > max_history_chars
	return over_message_limit or over_char_budget


func _estimate_history_chars() -> int:
	var total: int = 0
	for msg in _messages:
		total += _estimate_message_chars(msg)
	return total


func _estimate_message_chars(msg: Dictionary) -> int:
	var total: int = 24
	var content: Variant = msg.get("content", null)
	if content != null:
		total += str(content).length()
	if msg.has("tool_calls"):
		total += JSON.stringify(msg.get("tool_calls", [])).length()
	if msg.has("tool_call_id"):
		total += str(msg.get("tool_call_id", "")).length()
	return total


func _find_history_trim_candidate_index() -> int:
	if _messages.is_empty():
		return -1

	var protected_cutoff: int = maxi(_messages.size() - history_preserve_recent_messages, 0)
	var preferred_roles: Array[String] = ["tool", "assistant", "user"]

	for role_name in preferred_roles:
		for i in range(protected_cutoff):
			if _is_trim_candidate(_messages[i], role_name):
				return i

	# 如果预算仍然爆了，再放宽到更近的消息，但尽量保住最后一条
	for role_name in preferred_roles:
		for i in range(maxi(_messages.size() - 1, 0)):
			if _is_trim_candidate(_messages[i], role_name):
				return i

	return -1


func _is_trim_candidate(msg: Dictionary, expected_role: String) -> bool:
	var role_name: String = str(msg.get("role", "")).strip_edges()
	if role_name != expected_role:
		return false
	# 保住承载 tool_calls 的 assistant 消息，避免打断 API 继续链路所需的语义配对
	if role_name == "assistant" and msg.has("tool_calls"):
		return false
	return true


func _summarize_tool_result_for_history(tool_name: String, result: Variant) -> String:
	if result == null:
		return "null"

	match tool_name:
		"gather_scene_context":
			return _summarize_gather_scene_context_result(result)
		"batch_patch_scene_scripts":
			return _summarize_batch_patch_scene_scripts_result(result)
		"kb_read":
			return _summarize_kb_read_result(result)
		"db_list":
			return _summarize_db_list_result(result)
		"db_get":
			return _summarize_db_get_result(result)
		"get_scene_script":
			return _summarize_get_scene_script_result(result)
		"list_assets":
			return _summarize_list_assets_result(result)
		"analyze_story_reachability":
			return _summarize_reachability_result(result)
		_:
			return _summarize_generic_result(result)


func _summarize_kb_read_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "kb_read failed: %s" % str(dict_result.get("error", "unknown error"))
	var data: Variant = dict_result.get("data", [])
	if data is Array:
		var docs: Array = data
		var labels: Array[String] = []
		for doc in docs.slice(0, TOOL_HISTORY_MAX_ITEMS):
			if doc is Dictionary:
				var doc_dict: Dictionary = doc
				var doc_id: String = str(doc_dict.get("doc_id", "")).strip_edges()
				var title: String = str(doc_dict.get("title", "")).strip_edges()
				if not doc_id.is_empty() and not title.is_empty():
					labels.append("%s:%s" % [doc_id, title])
				elif not title.is_empty():
					labels.append(title)
		var suffix: String = " ..." if docs.size() > labels.size() else ""
		return "kb_read success: %d docs [%s]%s" % [docs.size(), ", ".join(labels), suffix]
	if data is Dictionary:
		var doc_data: Dictionary = data
		var content_chars: int = str(doc_data.get("content", "")).length()
		return "kb_read success: %s (%s, content_chars=%d)" % [
			str(doc_data.get("title", "")),
			str(doc_data.get("doc_id", "")),
			content_chars,
		]
	return _summarize_generic_result(result)


func _summarize_db_list_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "db_list failed: %s" % str(dict_result.get("error", "unknown error"))
	var items: Array = dict_result.get("data", [])
	var labels: Array[String] = []
	for item in items.slice(0, TOOL_HISTORY_MAX_ITEMS):
		if item is Dictionary:
			var item_dict: Dictionary = item
			var entry_id: String = str(item_dict.get("id", "")).strip_edges()
			if not entry_id.is_empty():
				labels.append(entry_id)
	return "db_list success: count=%d [%s]%s" % [
		int(dict_result.get("count", items.size())),
		", ".join(labels),
		" ..." if items.size() > labels.size() else "",
	]


func _summarize_db_get_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "db_get failed: %s" % str(dict_result.get("error", "unknown error"))
	var data: Dictionary = dict_result.get("data", {})
	var base: String = "db_get success: %s (%s)" % [
		str(data.get("name", data.get("scene_name", ""))),
		str(data.get("id", data.get("scene_id", ""))),
	]
	if data.has("root_dsl"):
		base += " dsl_chars=%d" % str(data.get("root_dsl", "")).length()
	return base


func _summarize_get_scene_script_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "get_scene_script failed: %s" % str(dict_result.get("error", "unknown error"))
	var data: Dictionary = dict_result.get("data", {})
	var dsl: String = str(data.get("dsl", ""))
	var preview: String = dsl.replace("\n", "\\n").left(TOOL_HISTORY_PREVIEW_CHARS)
	return "get_scene_script success: %s dsl_chars=%d preview=%s" % [
		str(data.get("scene_id", "")),
		dsl.length(),
		preview,
	]


func _summarize_list_assets_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "list_assets failed: %s" % str(dict_result.get("error", "unknown error"))
	var data: Dictionary = dict_result.get("data", {})
	var chunks: Array[String] = []
	for key in ["background_aliases", "image_aliases", "cg_aliases", "bgm_aliases", "sfx_aliases"]:
		var value: Variant = data.get(key, null)
		if value is Array:
			chunks.append("%s=%d" % [key, (value as Array).size()])
	for key in ["backgrounds", "images", "cg", "bgm", "sfx"]:
		var value: Variant = data.get(key, null)
		if value is Array:
			chunks.append("%s=%d" % [key, (value as Array).size()])
	if data.get("characters", null) is Dictionary:
		chunks.append("characters=%d" % (data.get("characters", {}) as Dictionary).size())
	return "list_assets success: %s" % ", ".join(chunks)


func _summarize_reachability_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "analyze_story_reachability failed: %s" % str(dict_result.get("error", "unknown error"))
	var data: Dictionary = dict_result.get("data", {})
	var unreachable: Array = data.get("unreachable_scenes", [])
	var warnings: Array = data.get("warnings", [])
	return "analyze_story_reachability success: entry=%s scene_catalog=%d unreachable=%d warnings=%d" % [
		str(data.get("entry_scene_id", "")),
		(data.get("scene_catalog", []) as Array).size(),
		unreachable.size(),
		warnings.size(),
	]


func _summarize_gather_scene_context_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	if not bool(dict_result.get("success", false)):
		return "gather_scene_context failed: %s" % str(dict_result.get("error", "unknown error"))
	var data: Dictionary = dict_result.get("data", {})
	var scene_count: int = (data.get("scenes", []) as Array).size()
	var kb_count: int = 0
	var kb_value: Variant = data.get("kb", null)
	if kb_value is Dictionary:
		kb_count = (kb_value as Dictionary).get("docs", []).size()
	var asset_sections: Array[String] = []
	var assets_value: Variant = data.get("assets", null)
	if assets_value is Dictionary:
		for key in (assets_value as Dictionary).keys():
			asset_sections.append(str(key))
	asset_sections.sort()
	return "gather_scene_context success: scenes=%d kb_docs=%d characters=%d variables=%d scene_catalog=%d reachability=%s assets=[%s]" % [
		scene_count,
		kb_count,
		(data.get("characters", []) as Array).size(),
		(data.get("variables", []) as Array).size(),
		(data.get("scene_catalog", []) as Array).size(),
		"yes" if data.has("reachability") else "no",
		", ".join(asset_sections),
	]


func _summarize_batch_patch_scene_scripts_result(result: Variant) -> String:
	if not (result is Dictionary):
		return _summarize_generic_result(result)
	var dict_result: Dictionary = result
	return "batch_patch_scene_scripts %s: patched=%d failed=%d" % [
		"success" if bool(dict_result.get("success", false)) else "partial",
		int(dict_result.get("patched_count", 0)),
		int(dict_result.get("failed_count", 0)),
	]


func _summarize_generic_result(result: Variant) -> String:
	var raw: String = JSON.stringify(result) if result != null else "null"
	raw = raw.replace("\n", "\\n")
	if raw.length() > TOOL_HISTORY_PREVIEW_CHARS:
		return raw.left(TOOL_HISTORY_PREVIEW_CHARS) + "..."
	return raw


## 发出日志信号。
func _emit_log(type: String, content: String, metadata: Dictionary = {}) -> void:
	var entry: Dictionary = {
		"type": type,
		"timestamp": Time.get_unix_time_from_system(),
		"content": content,
		"metadata": metadata,
	}
	log_entry.emit(entry)
#endregion
