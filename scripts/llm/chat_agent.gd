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
## sub-agent 注册表: tool_name -> {agent: ChatAgent, description: String}
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
#endregion


#region 生命周期
func _ready() -> void:
	_ai_service.request_completed.connect(_on_request_completed)
	_ai_service.request_failed.connect(_on_request_failed)
	_ai_service.tool_executed.connect(_on_tool_executed)

	# 用 AIConfigManager 配置 AIService
	var config_mgr: AIConfigManager = AIConfigManager.new()
	if config_mgr.load_config() and not role.is_empty():
		config_mgr.apply_to_service(_ai_service, role)
#endregion


#region 公共 API

## 发送消息。自动管理对话历史和 system prompt。
func send_message(text: String) -> String:
	if _is_busy:
		_emit_log("error", "Agent 正忙，无法处理新消息")
		return ""

	_is_busy = true

	# 首次对话时设置 system prompt
	if _messages.is_empty() and _system_prompt.is_empty():
		_system_prompt = _resolve_prompt()

	# 添加用户消息到历史
	_messages.append({"role": "user", "content": text})
	_trim_history()

	# 构建完整 messages 数组发给 AIService
	var full_messages: Array = _build_messages_for_api()

	# 带上已注册的 tools（如果有的话）
	var options: Dictionary = {"auto_execute": true}
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


## 注册普通工具。
func register_tool(tool_name: String, description: String, schema: Dictionary, callback: Callable) -> void:
	_ai_service.register_tool(tool_name, description, schema, callback)


## 注册 sub-agent 工具。
func register_sub_agent_tool(tool_name: String, description: String, agent: Node) -> void:
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
	}

	_ai_service.register_tool(
		tool_name,
		description,
		schema,
		func(args: Dictionary) -> Dictionary: return await _execute_sub_agent(tool_name, args)
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
		_ai_service.register_tool(tname, t.get("description", ""), t.get("schema", {}), t.get("callback", Callable()))
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

func _execute_sub_agent(tool_name: String, args: Dictionary) -> Dictionary:
	var sub_info: Dictionary = _sub_agents.get(tool_name, {})
	var agent: Node = sub_info.get("agent", null)
	if agent == null:
		return {"success": false, "error": "Sub-agent not found for tool: " + tool_name}

	var task: String = args.get("task", "")
	if task.is_empty():
		return {"success": false, "error": "task is required"}

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

	agent.send_message(task)

	while not state["completed"]:
		await get_tree().process_frame

	if state["has_error"]:
		_emit_log("error", "子代理 [%s] 失败: %s" % [tool_name, state["error"]])
		return {"success": false, "error": state["error"]}

	var extracted: String = _extract_result_tag(state["content"])
	_emit_log("progress", "子代理 [%s] 完成" % tool_name)

	agent.reset()

	return {"success": true, "data": extracted}


func _extract_result_tag(text: String) -> String:
	var start_tag: String = "<result>"
	var end_tag: String = "</result>"
	var start_idx: int = text.find(start_tag)
	var end_idx: int = text.find(end_tag)

	if start_idx == -1 or end_idx == -1 or end_idx <= start_idx:
		return text.strip_edges()

	return text.substr(start_idx + start_tag.length(), end_idx - start_idx - start_tag.length()).strip_edges()
#endregion


#region AIService 信号处理

func _on_request_completed(_request_id: String, response: Dictionary) -> void:
	print("[ChatAgent] _on_request_completed: req=%s _is_busy=%s" % [_request_id, str(_is_busy)])
	if not _is_busy:
		print("[ChatAgent] SKIPPED: not busy")
		return

	var content: String = ""
	var has_tool_calls: bool = false
	if response.has("choices") and response.choices.size() > 0:
		var message: Dictionary = response.choices[0].get("message", {})
		var msg_content: Variant = message.get("content", null)
		has_tool_calls = message.has("tool_calls") and message.tool_calls.size() > 0
		print("[ChatAgent] msg_content type=%s is_null=%s" % [type_string(typeof(msg_content)), str(msg_content == null)])
		if msg_content != null and msg_content is String:
			content = msg_content
	else:
		print("[ChatAgent] no choices in response, keys=%s" % str(response.keys()))

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
			var message_node: Dictionary = response.choices[0].get("message", {})
			assistant_msg["tool_calls"] = message_node.get("tool_calls", [])
			
		_messages.append(assistant_msg)
		_trim_history()
		_emit_log("ai_response", content)

	# 如果存在 tool_calls，这只是一个中间返回（AIService 还在忙着自动执行跑工具）
	# 此时我们可以把阶段性文本展示给前端，但不要结束 agent 的 busyness
	if not has_tool_calls:
		_is_busy = false
		
	if not content.is_empty() or not has_tool_calls:
		message_completed.emit(_request_id, content)


func _on_request_failed(_request_id: String, error: String, _error_code: int) -> void:
	if not _is_busy:
		return

	_emit_log("error", "请求失败: " + error)
	_is_busy = false
	message_failed.emit(_request_id, error)


func _on_tool_executed(_request_id: String, tool_name: String, arguments: Dictionary, result: Variant, tool_call_id: String) -> void:
	_emit_log("tool_call", "调用工具: %s(%s)" % [tool_name, str(arguments).left(150)])
	if result != null:
		_emit_log("tool_result", "结果: %s" % str(result).left(200))
	
	# 将工具执行结果存入 history，否则下一轮对话模型将无法感知工具产出
	_messages.append({
		"role": "tool",
		"tool_call_id": tool_call_id,
		"content": JSON.stringify(result) if result != null else "null"
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
##   - 可用 skill 元数据列表：始终动态追加到末尾（不污染 base prompt）
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

	# 2) 可用 skill 元数据（名称+描述+工具数），让 AI 知道能激活什么
	if not _available_skills.is_empty():
		var meta_section: String = "\n\n# 可用 Skills（使用 activate_skill 工具激活）\n"
		for sname in _available_skills:
			var s: Dictionary = _available_skills[sname]
			var skill_tools: Array = s.get("tools", [])
			if skill_tools.is_empty():
				meta_section += "- **%s**: %s\n" % [sname, s.description]
			else:
				var tnames: Array[String] = []
				for t in skill_tools:
					tnames.append(t.get("name", "?"))
				meta_section += "- **%s**: %s (附带工具: %s)\n" % [sname, s.description, ", ".join(tnames)]
		combined_prompt += meta_section

	if not combined_prompt.is_empty():
		result.append({"role": "system", "content": combined_prompt})
	result.append_array(_messages)
	return result


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
	var regex: RegEx = RegEx.new()
	regex.compile("<thinking>[\\s\\S]*?</thinking>")
	return regex.sub(text, "", true).strip_edges()


## 裁剪历史消息数量
func _trim_history() -> void:
	if max_history_messages <= 0:
		return
	while _messages.size() > max_history_messages:
		_messages.remove_at(0)


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
