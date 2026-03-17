## AIService - 通用LLM API调用服务节点
## 
## 一个类似Godot内置节点的通用AI服务，可在任何需要LLM的项目中使用。
## 支持OpenAI兼容API（DeepSeek、OpenAI、Ollama等）
##
## 功能特性:
## - Function Calling (工具调用)
## - 对话历史管理
## - 流式响应
## - 请求队列和并发控制
## - MCP协议支持
## - 多种补全模式
##
## 使用示例:
## [codeblock]
## var ai = AIService.new()
## ai.api_base_url = "https://api.deepseek.com"
## ai.api_key = "your-api-key"
## ai.model = "deepseek-chat"
## ai.request_completed.connect(_on_response)
## add_child(ai)
## ai.chat([{"role": "user", "content": "Hello!"}])
## [/codeblock]

class_name AIService
extends Node

#region 信号定义
## 请求完成时发出，返回完整响应
signal request_completed(request_id: String, response: Dictionary)
## 请求失败时发出
signal request_failed(request_id: String, error: String, error_code: int)
## 流式响应：收到数据块时发出
signal stream_chunk_received(request_id: String, chunk: String, delta: Dictionary)
## 流式响应完成时发出
signal stream_completed(request_id: String, full_content: String, response: Dictionary)
## Function Call被触发时发出（仅在auto_execute_tools=false时，或用于监听）
signal function_call_requested(request_id: String, function_name: String, arguments: Dictionary)
## 多个Tool Calls被触发时发出（仅在auto_execute_tools=false时，或用于监听）
signal tool_calls_requested(request_id: String, tool_calls: Array, content: String)
## 工具执行完成时发出（用于监听自动执行过程）
signal tool_executed(request_id: String, tool_name: String, arguments: Dictionary, result: Variant, tool_call_id: String)
## 工具调用循环完成，返回所有工具调用记录
signal tool_calls_completed(request_id: String, tool_history: Array)
## 请求队列变空时发出
signal queue_empty()
## 请求开始处理时发出
signal request_started(request_id: String)
## 对话历史更新时发出
signal conversation_updated(conversation_id: String, messages: Array)
#endregion

#region 导出配置
@export_group("API Configuration")
## API基础URL（不含端点路径）
@export var api_base_url: String = "https://api.deepseek.com"
## API密钥
@export var api_key: String = ""
## 使用的模型名称
@export var model: String = "deepseek-chat"

@export_group("Request Settings")
## 请求超时时间（秒）
@export var timeout: float = 240.0
## 最大并发请求数
@export var max_concurrent_requests: int = 3
## 失败后重试次数
@export var max_retries: int = 2
## 重试间隔（秒）
@export var retry_delay: float = 1.0
## 是否启用流式响应
@export var stream_enabled: bool = false

@export_group("Default Parameters")
## 默认温度参数
@export_range(0.0, 2.0) var default_temperature: float = 1.0
## 默认最大token数
@export var default_max_tokens: int = 8192
## 默认top_p参数
@export_range(0.0, 1.0) var default_top_p: float = 1.0

@export_group("Conversation Settings")
## 是否自动管理对话历史
@export var auto_manage_history: bool = true
## 最大历史消息数（0表示不限制）
@export var max_history_messages: int = 50
## 是否在历史中包含function call结果
@export var include_function_results: bool = true

@export_group("Tool Call Settings")
## 是否自动处理工具调用（循环直到获得最终回复）
@export var auto_execute_tools: bool = true
## 最大工具调用循环次数（防止无限循环）
@export var max_tool_iterations: int = 10
#endregion

#region 内部变量
# 请求队列
var _request_queue: Array[Dictionary] = []
# 当前活跃的请求 {request_id: HTTPRequest}
var _active_requests: Dictionary = {}
# 流式响应缓冲 {request_id: {buffer, content, tool_calls}}
var _stream_buffers: Dictionary = {}
# 请求计数器
var _request_counter: int = 0
# 重试计数 {request_id: int}
var _retry_counts: Dictionary = {}
# 对话历史 {conversation_id: Array[messages]}
var _conversations: Dictionary = {}
# 已注册的工具/函数 {name: {description, parameters, callback}}
var _registered_tools: Dictionary = {}
# MCP服务器连接 {server_id: MCPConnection}
var _mcp_servers: Dictionary = {}
# 请求对应的conversation_id {request_id: conversation_id}
var _request_conversations: Dictionary = {}
# 工具调用迭代计数 {request_id: int}
var _tool_iteration_counts: Dictionary = {}
# 原始请求ID映射（用于工具调用循环时保持同一request_id）{internal_id: original_id}
var _original_request_ids: Dictionary = {}
# 请求的工具调用累积记录 {request_id: Array[{name, args, result}]}
var _tool_call_history: Dictionary = {}
#endregion

#region 生命周期
func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	_process_queue()
#endregion

#region 公共API - 基础聊天

## 发送聊天请求
## [param messages] 消息数组，格式: [{"role": "user/assistant/system", "content": "..."}]
## [param options] 可选参数覆盖
## [return] 请求ID
func chat(messages: Array, options: Dictionary = {}) -> String:
	var request_id = _generate_request_id()
	var request_data = _build_chat_request(messages, options)
	_enqueue_request(request_id, request_data, options)
	return request_id

## 发送单条消息的便捷方法
func chat_simple(content: String, system_prompt: String = "", options: Dictionary = {}) -> String:
	var messages: Array = []
	if system_prompt != "":
		messages.append({"role": "system", "content": system_prompt})
	messages.append({"role": "user", "content": content})
	return chat(messages, options)

## 文本补全（非聊天模式）
## [param prompt] 要补全的文本
## [param options] 可选参数
## [return] 请求ID
func complete(prompt: String, options: Dictionary = {}) -> String:
	var request_id = _generate_request_id()
	var body: Dictionary = {
		"model": options.get("model", model),
		"prompt": prompt,
		"max_tokens": options.get("max_tokens", default_max_tokens),
		"temperature": options.get("temperature", default_temperature),
		"stream": options.get("stream", stream_enabled)
	}
	
	if options.has("stop"):
		body["stop"] = options["stop"]
	if options.has("suffix"):
		body["suffix"] = options["suffix"]
	
	var url = options.get("api_url", api_base_url) + "/v1/completions"
	_request_queue.append({
		"id": request_id,
		"body": body,
		"options": options,
		"url": url,
		"type": "completion"
	})
	_retry_counts[request_id] = 0
	return request_id
#endregion

#region 公共API - 对话管理

## 创建新对话
## [param conversation_id] 对话ID，为空则自动生成
## [param system_prompt] 可选的系统提示
## [return] 对话ID
func create_conversation(conversation_id: String = "", system_prompt: String = "") -> String:
	if conversation_id == "":
		conversation_id = "conv_%d_%d" % [Time.get_ticks_msec(), randi()]
	
	var messages: Array = []
	if system_prompt != "":
		messages.append({"role": "system", "content": system_prompt})
	
	_conversations[conversation_id] = messages
	return conversation_id

## 向对话发送消息并获取回复
## [param conversation_id] 对话ID
## [param content] 用户消息内容
## [param options] 可选参数
## [return] 请求ID
func send_message(conversation_id: String, content: String, options: Dictionary = {}) -> String:
	if not _conversations.has(conversation_id):
		create_conversation(conversation_id)
	
	# 添加用户消息到历史
	var user_message = {"role": "user", "content": content}
	_conversations[conversation_id].append(user_message)
	_trim_history(conversation_id)
	
	# 发送请求
	var request_id = chat(_conversations[conversation_id].duplicate(true), options)
	_request_conversations[request_id] = conversation_id
	
	conversation_updated.emit(conversation_id, _conversations[conversation_id])
	return request_id

## 获取对话历史
func get_conversation(conversation_id: String) -> Array:
	return _conversations.get(conversation_id, []).duplicate(true)

## 获取所有对话ID
func get_conversation_ids() -> Array:
	return _conversations.keys()

## 清除对话历史
func clear_conversation(conversation_id: String, keep_system: bool = true) -> void:
	if not _conversations.has(conversation_id):
		return
	
	if keep_system:
		var messages = _conversations[conversation_id]
		var system_messages: Array = []
		for msg in messages:
			if msg.get("role") == "system":
				system_messages.append(msg)
		_conversations[conversation_id] = system_messages
	else:
		_conversations[conversation_id] = []
	
	conversation_updated.emit(conversation_id, _conversations[conversation_id])

## 删除对话
func delete_conversation(conversation_id: String) -> void:
	_conversations.erase(conversation_id)

## 向对话添加消息（不发送请求）
func add_message_to_conversation(conversation_id: String, role: String, content: String) -> void:
	if not _conversations.has(conversation_id):
		create_conversation(conversation_id)
	_conversations[conversation_id].append({"role": role, "content": content})
	_trim_history(conversation_id)
	conversation_updated.emit(conversation_id, _conversations[conversation_id])

## 设置对话的系统提示
func set_system_prompt(conversation_id: String, system_prompt: String) -> void:
	if not _conversations.has(conversation_id):
		create_conversation(conversation_id, system_prompt)
		return
	
	var messages = _conversations[conversation_id]
	# 移除旧的system消息
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].get("role") == "system":
			messages.remove_at(i)
	# 添加新的system消息到开头
	if system_prompt != "":
		messages.insert(0, {"role": "system", "content": system_prompt})
	
	conversation_updated.emit(conversation_id, messages)

func _trim_history(conversation_id: String) -> void:
	if max_history_messages <= 0:
		return
	var messages = _conversations[conversation_id]
	while messages.size() > max_history_messages:
		# 保留system消息
		if messages[0].get("role") == "system":
			if messages.size() > 1:
				messages.remove_at(1)
			else:
				break
		else:
			messages.remove_at(0)
#endregion

#region 公共API - Function Calling / Tools

## 注册一个工具/函数供AI调用
## [param tool_name] 函数名称
## [param description] 函数描述
## [param parameters] JSON Schema格式的参数定义
## [param callback] 可选的回调函数，签名: func(args: Dictionary) -> Variant
func register_tool(tool_name: String, description: String, parameters: Dictionary, callback: Callable = Callable()) -> void:
	_registered_tools[tool_name] = {
		"type": "function",
		"function": {
			"name": tool_name,
			"description": description,
			"parameters": parameters
		},
		"callback": callback
	}

## 注册多个工具
func register_tools(tools: Array[Dictionary]) -> void:
	for tool in tools:
		var cb = tool.get("callback", Callable())
		register_tool(tool.name, tool.description, tool.parameters, cb)

## 取消注册工具
func unregister_tool(tool_name: String) -> void:
	_registered_tools.erase(tool_name)

## 获取所有已注册的工具定义（用于发送给API）
func get_tools_definition() -> Array:
	var tools: Array = []
	for tool_data in _registered_tools.values():
		tools.append({
			"type": tool_data.type,
			"function": tool_data.function
		})
	return tools

## 带工具调用的聊天请求（默认自动执行工具直到获得最终回复）
## [param messages] 消息数组
## [param tools] 工具定义数组，为空则使用已注册的工具
## [param tool_choice] 工具选择策略: "auto", "none", "required", 或指定工具名
## [param options] 其他选项，可设置 "auto_execute": false 禁用自动执行
func chat_with_tools(messages: Array, tools: Array = [], tool_choice: Variant = "auto", options: Dictionary = {}) -> String:
	if tools.is_empty():
		tools = get_tools_definition()
	
	options["tools"] = tools
	options["tool_choice"] = tool_choice
	
	# 默认启用自动工具执行
	var auto_tools = options.get("auto_execute", true) and auto_execute_tools
	options["auto_tools"] = auto_tools
	
	return chat(messages, options)

## 提交工具调用结果并继续对话
## [param conversation_id] 对话ID
## [param tool_call_id] 工具调用ID
## [param result] 工具执行结果
## [param options] 其他选项
func submit_tool_result(conversation_id: String, tool_call_id: String, result: String, options: Dictionary = {}) -> String:
	if not _conversations.has(conversation_id):
		push_error("Conversation not found: " + conversation_id)
		return ""
	
	var tool_message = {
		"role": "tool",
		"tool_call_id": tool_call_id,
		"content": result
	}
	_conversations[conversation_id].append(tool_message)
	
	# 继续对话
	var request_id = chat(_conversations[conversation_id].duplicate(true), options)
	_request_conversations[request_id] = conversation_id
	return request_id

## 执行已注册的工具回调
## [param function_name] 函数名
## [param arguments] 参数字典
## [return] 执行结果，如果没有回调则返回null（支持异步回调）
func execute_tool_callback(function_name: String, arguments: Dictionary) -> Variant:
	if not _registered_tools.has(function_name):
		return null
	
	var callback: Callable = _registered_tools[function_name].callback
	if callback.is_valid():
		return await callback.call(arguments)
	return null

## 自动处理工具调用（执行回调并提交结果）
## [param conversation_id] 对话ID
## [param tool_calls] 工具调用数组
## [param options] 其他选项
## [return] 新的请求ID，如果没有工具调用则返回空
func auto_handle_tool_calls(conversation_id: String, tool_calls: Array, options: Dictionary = {}) -> String:
	if tool_calls.is_empty():
		return ""
	
	# 先添加assistant的tool_calls消息
	var assistant_msg = {
		"role": "assistant",
		"content": null,
		"tool_calls": tool_calls
	}
	if _conversations.has(conversation_id):
		_conversations[conversation_id].append(assistant_msg)
	
	# 执行每个工具调用并添加结果（支持异步）
	for tool_call in tool_calls:
		var func_name = tool_call.function.name
		var args_str = tool_call.function.arguments
		var args = {}
		
		var json = JSON.new()
		if json.parse(args_str) == OK:
			args = json.data
		
		var result = await execute_tool_callback(func_name, args)
		var result_str = JSON.stringify(result) if result != null else '{"error": "No callback registered"}'
		
		if _conversations.has(conversation_id):
			_conversations[conversation_id].append({
				"role": "tool",
				"tool_call_id": tool_call.id,
				"content": result_str
			})
	
	# 继续对话
	return chat(_conversations[conversation_id].duplicate(true), options)
#endregion

#region 公共API - MCP协议支持

## MCP服务器配置
class MCPServerConfig:
	var server_id: String
	var command: String
	var args: Array
	var env: Dictionary
	var tools: Array = []
	var connected: bool = false

## 注册MCP服务器（配置信息，实际连接需要外部实现）
## [param server_id] 服务器标识
## [param command] 启动命令
## [param args] 命令参数
## [param env] 环境变量
func register_mcp_server(server_id: String, command: String, args: Array = [], env: Dictionary = {}) -> void:
	var config = MCPServerConfig.new()
	config.server_id = server_id
	config.command = command
	config.args = args
	config.env = env
	_mcp_servers[server_id] = config
	print("[AIService] MCP server registered: ", server_id)

## 从MCP服务器导入工具定义
## [param server_id] 服务器ID
## [param tools] 工具定义数组（从MCP服务器获取）
func import_mcp_tools(server_id: String, tools: Array) -> void:
	if not _mcp_servers.has(server_id):
		push_error("MCP server not registered: " + server_id)
		return
	
	_mcp_servers[server_id].tools = tools
	
	# 将MCP工具注册为本地工具
	for tool in tools:
		var tool_name = "%s/%s" % [server_id, tool.name]
		register_tool(
			tool_name,
			tool.get("description", ""),
			tool.get("inputSchema", {}),
			Callable() # MCP工具的回调需要通过MCP协议调用
		)
	
	print("[AIService] Imported %d tools from MCP server: %s" % [tools.size(), server_id])

## 获取MCP服务器列表
func get_mcp_servers() -> Array:
	return _mcp_servers.keys()

## 获取MCP服务器配置
func get_mcp_server_config(server_id: String) -> MCPServerConfig:
	return _mcp_servers.get(server_id)

## 移除MCP服务器
func remove_mcp_server(server_id: String) -> void:
	if _mcp_servers.has(server_id):
		# 移除该服务器的工具
		var prefix = server_id + "/"
		var tools_to_remove: Array = []
		for tool_name in _registered_tools.keys():
			if tool_name.begins_with(prefix):
				tools_to_remove.append(tool_name)
		for tool_name in tools_to_remove:
			_registered_tools.erase(tool_name)
		
		_mcp_servers.erase(server_id)
#endregion

#region 公共API - 请求控制

## 取消指定请求
func cancel_request(request_id: String) -> bool:
	for i in range(_request_queue.size() - 1, -1, -1):
		if _request_queue[i].id == request_id:
			_request_queue.remove_at(i)
			return true
	
	if _active_requests.has(request_id):
		var http: HTTPRequest = _active_requests[request_id]
		http.cancel_request()
		_cleanup_request(request_id)
		return true
	
	return false

## 取消所有请求
func cancel_all() -> void:
	_request_queue.clear()
	for request_id in _active_requests.keys():
		var http: HTTPRequest = _active_requests[request_id]
		http.cancel_request()
	_cleanup_all_requests()

## 清空请求队列
func clear_queue() -> void:
	_request_queue.clear()

## 获取队列长度
func get_queue_size() -> int:
	return _request_queue.size()

## 获取活跃请求数
func get_active_request_count() -> int:
	return _active_requests.size()

## 检查是否忙碌
func is_busy() -> bool:
	return _request_queue.size() > 0 or _active_requests.size() > 0
#endregion

#region 内部方法 - 请求构建

func _generate_request_id() -> String:
	_request_counter += 1
	return "req_%d_%d" % [Time.get_ticks_msec(), _request_counter]

func _build_chat_request(messages: Array, options: Dictionary) -> Dictionary:
	var body: Dictionary = {
		"model": options.get("model", model),
		"messages": messages,
		"temperature": options.get("temperature", default_temperature),
		"max_tokens": options.get("max_tokens", default_max_tokens),
		"top_p": options.get("top_p", default_top_p),
		"stream": options.get("stream", stream_enabled)
	}
	
	# 可选参数
	if options.has("frequency_penalty"):
		body["frequency_penalty"] = options["frequency_penalty"]
	if options.has("presence_penalty"):
		body["presence_penalty"] = options["presence_penalty"]
	if options.has("stop"):
		body["stop"] = options["stop"]
	
	# Function Calling / Tools
	if options.has("tools") and options["tools"].size() > 0:
		body["tools"] = options["tools"]
		if options.has("tool_choice"):
			var choice = options["tool_choice"]
			if choice is String:
				if choice in ["auto", "none", "required"]:
					body["tool_choice"] = choice
				else:
					# 指定特定工具
					body["tool_choice"] = {
						"type": "function",
						"function": {"name": choice}
					}
			else:
				body["tool_choice"] = choice
	
	# Response format (JSON mode)
	if options.has("response_format"):
		body["response_format"] = options["response_format"]
	
	# Thinking / Deep reasoning (火山引擎 doubao-seed 等模型)
	# 默认 disabled，避免浪费 token（项目已通过 <think> 标签自行管理思维链）
	var thinking_type: String = options.get("thinking", "disabled")
	body["thinking"] = {"type": thinking_type}
	
	# Seed for reproducibility
	if options.has("seed"):
		body["seed"] = options["seed"]
	
	return body

func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	])
#endregion

#region 内部方法 - 队列管理

func _enqueue_request(request_id: String, body: Dictionary, options: Dictionary) -> void:
	var auto_tools = options.get("auto_tools", false)
	_request_queue.append({
		"id": request_id,
		"body": body,
		"options": options,
		"url": options.get("api_url", api_base_url) + "/v1/chat/completions",
		"type": "chat",
		"auto_tools": auto_tools
	})
	_retry_counts[request_id] = 0

func _process_queue() -> void:
	while _active_requests.size() < max_concurrent_requests and _request_queue.size() > 0:
		var request = _request_queue.pop_front()
		_execute_request(request)

func _execute_request(request: Dictionary) -> void:
	var request_id: String = request.id
	var http = HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	
	_active_requests[request_id] = http
	
	var is_stream = request.body.get("stream", false)
	if is_stream:
		_stream_buffers[request_id] = {
			"buffer": "",
			"content": "",
			"tool_calls": [],
			"current_tool_call": null
		}
		http.request_completed.connect(_on_stream_completed.bind(request_id, request))
		http.download_chunk_size = 256
	else:
		http.request_completed.connect(_on_request_completed.bind(request_id, request))
	
	var body_json = JSON.stringify(request.body)
	var error = http.request(request.url, _build_headers(), HTTPClient.METHOD_POST, body_json)
	
	if error != OK:
		_handle_error(request_id, "Failed to create HTTP request: " + str(error), error, request)
		return
	
	request_started.emit(request_id)
#endregion

#region 内部方法 - 响应处理

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: String, original_request: Dictionary) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_http_error(result, request_id, original_request)
		return
	
	if response_code != 200:
		var error_body = body.get_string_from_utf8()
		_handle_api_error(response_code, error_body, request_id, original_request)
		return
	
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	var parse_result = json.parse(response_text)
	print(response_text)
	if parse_result != OK:
		_handle_error(request_id, "Failed to parse JSON response", parse_result, original_request)
		return
	
	var response = json.data
	
	# 获取原始请求ID（用于工具调用循环）
	var original_id = _original_request_ids.get(request_id, request_id)
	
	# 处理对话历史更新
	_update_conversation_from_response(request_id, response)
	
	# 检查是否有tool calls
	if _has_tool_calls(response):
		var tool_calls = _extract_tool_calls(response)
		
		# 提取 content（可能与 tool_calls 同时存在）
		var tc_content: String = ""
		if response.has("choices") and response["choices"].size() > 0:
			var msg = response["choices"][0].get("message", {})
			if msg.get("content") != null:
				tc_content = str(msg["content"])
				# 补救：如果有附带的解释内容，在此处向外层先报一次完成，让 UI 可以显示 AI 对调用工具前的陈述
				if not tc_content.is_empty():
					request_completed.emit(original_id, response)
		
		# 发出信号（用于监听）
		tool_calls_requested.emit(original_id, tool_calls, tc_content)
		if tool_calls.size() == 1:
			var tc = tool_calls[0]
			var args = _parse_tool_arguments(tc.function.arguments)
			function_call_requested.emit(original_id, tc.function.name, args)
		
		# 检查是否自动执行工具
		if auto_execute_tools and original_request.get("auto_tools", false):
			_auto_execute_tool_calls(request_id, original_id, tool_calls, original_request, tc_content)
		else:
			_cleanup_request(request_id)
	else:
		# 没有工具调用，返回最终结果
		var tool_history = _tool_call_history.get(original_id, [])
		if tool_history.size() > 0:
			tool_calls_completed.emit(original_id, tool_history)
		
		_cleanup_request(request_id)
		_cleanup_tool_tracking(original_id)
		request_completed.emit(original_id, response)
	
	_check_queue_empty()

func _on_stream_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: String, original_request: Dictionary) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_http_error(result, request_id, original_request)
		return
	
	if response_code != 200:
		var error_body = body.get_string_from_utf8()
		_handle_api_error(response_code, error_body, request_id, original_request)
		return
	
	var response_text = body.get_string_from_utf8()
	_process_stream_data(request_id, response_text)
	
	var buffer_data = _stream_buffers.get(request_id, {})
	var full_content = buffer_data.get("content", "")
	var tool_calls = buffer_data.get("tool_calls", [])
	
	# 获取原始请求ID
	var original_id = _original_request_ids.get(request_id, request_id)
	
	# 构建最终响应
	var final_response: Dictionary = {
		"model": original_request.body.get("model", model),
		"choices": [ {
			"message": {
				"role": "assistant",
				"content": full_content if full_content != "" else null
			}
		}]
	}
	
	if tool_calls.size() > 0:
		final_response.choices[0].message["tool_calls"] = tool_calls
	
	# 更新对话历史
	_update_conversation_from_response(request_id, final_response)
	
	if tool_calls.size() > 0:
		# 发出信号（用于监听）
		var stream_content: String = full_content if full_content != "" else ""
		tool_calls_requested.emit(original_id, tool_calls, stream_content)
		if tool_calls.size() == 1:
			var tc = tool_calls[0]
			var args = _parse_tool_arguments(tc.function.arguments)
			function_call_requested.emit(original_id, tc.function.name, args)
		
		# 检查是否自动执行工具
		if auto_execute_tools and original_request.get("auto_tools", false):
			_auto_execute_tool_calls(request_id, original_id, tool_calls, original_request, stream_content)
		else:
			_cleanup_request(request_id)
	else:
		# 没有工具调用，返回最终结果
		var tool_history = _tool_call_history.get(original_id, [])
		if tool_history.size() > 0:
			tool_calls_completed.emit(original_id, tool_history)
		
		_cleanup_request(request_id)
		_cleanup_tool_tracking(original_id)
		stream_completed.emit(original_id, full_content, final_response)
	
	_check_queue_empty()

func _process_stream_data(request_id: String, data: String) -> void:
	if not _stream_buffers.has(request_id):
		return
	
	var buffer_data = _stream_buffers[request_id]
	buffer_data.buffer += data
	
	var lines = buffer_data.buffer.split("\n")
	buffer_data.buffer = lines[-1]
	
	for i in range(lines.size() - 1):
		var line = lines[i].strip_edges()
		if line.begins_with("data: "):
			var json_str = line.substr(6)
			if json_str == "[DONE]":
				continue
			
			var json = JSON.new()
			if json.parse(json_str) == OK:
				var chunk_data = json.data
				if chunk_data.has("choices") and chunk_data.choices.size() > 0:
					var delta = chunk_data.choices[0].get("delta", {})
					
					# 处理文本内容
					var content = delta.get("content", "")
					if content != "":
						buffer_data.content += content
						stream_chunk_received.emit(request_id, content, delta)
					
					# 处理tool calls
					if delta.has("tool_calls"):
						_process_stream_tool_calls(buffer_data, delta.tool_calls)

func _process_stream_tool_calls(buffer_data: Dictionary, tool_calls_delta: Array) -> void:
	for tc_delta in tool_calls_delta:
		var index = tc_delta.get("index", 0)
		
		# 确保tool_calls数组足够大
		while buffer_data.tool_calls.size() <= index:
			buffer_data.tool_calls.append({
				"id": "",
				"type": "function",
				"function": {"name": "", "arguments": ""}
			})
		
		var tc = buffer_data.tool_calls[index]
		
		if tc_delta.has("id"):
			tc.id = tc_delta.id
		if tc_delta.has("type"):
			tc.type = tc_delta.type
		if tc_delta.has("function"):
			var func_delta = tc_delta.function
			if func_delta.has("name"):
				tc.function.name += func_delta.name
			if func_delta.has("arguments"):
				tc.function.arguments += func_delta.arguments

func _has_tool_calls(response: Dictionary) -> bool:
	if not response.has("choices") or response.choices.size() == 0:
		return false
	var message = response.choices[0].get("message", {})
	return message.has("tool_calls") and message.tool_calls.size() > 0

func _extract_tool_calls(response: Dictionary) -> Array:
	if not _has_tool_calls(response):
		return []
	return response.choices[0].message.tool_calls

func _parse_tool_arguments(args_str: String) -> Dictionary:
	var json = JSON.new()
	if json.parse(args_str) == OK:
		return json.data
	return {}

## 自动执行工具调用并继续对话
func _auto_execute_tool_calls(request_id: String, original_id: String, tool_calls: Array, original_request: Dictionary, assistant_content: String = "") -> void:
	# 检查迭代次数
	var iteration = _tool_iteration_counts.get(original_id, 0)
	if iteration >= max_tool_iterations:
		push_warning("[AIService] Max tool iterations reached for request: " + original_id)
		_cleanup_request(request_id)
		_cleanup_tool_tracking(original_id)
		request_failed.emit(original_id, "Max tool call iterations reached (%d)" % max_tool_iterations, -1)
		return
	
	_tool_iteration_counts[original_id] = iteration + 1
	
	# 初始化工具调用历史
	if not _tool_call_history.has(original_id):
		_tool_call_history[original_id] = []
	
	# 获取对话ID
	var conversation_id = _request_conversations.get(request_id, "")
	if conversation_id == "":
		# 如果没有对话ID，创建临时对话
		conversation_id = _create_temp_conversation_for_tools(original_request)
		_request_conversations[request_id] = conversation_id
	
	# 先添加assistant的tool_calls消息到对话历史
	var content_val: Variant = null
	if assistant_content != "":
		content_val = assistant_content
		
	var assistant_msg = {
		"role": "assistant",
		"content": content_val,
		"tool_calls": tool_calls
	}
	if _conversations.has(conversation_id):
		_conversations[conversation_id].append(assistant_msg)
	
	# 执行每个工具调用（支持异步）
	for tc in tool_calls:
		var func_name = tc.function.name
		var args = _parse_tool_arguments(tc.function.arguments)
		
		print("[AIService] Auto-executing tool: %s with args: %s" % [func_name, str(args)])
		
		# 使用await支持异步回调
		var result = await execute_tool_callback(func_name, args)
		var result_str = JSON.stringify(result) if result != null else '{"error": "No callback registered for tool: ' + func_name + '"}'
		
		# 记录工具调用历史
		_tool_call_history[original_id].append({
			"name": func_name,
			"arguments": args,
			"result": result
		})
		
		# 发出工具执行信号
		tool_executed.emit(original_id, func_name, args, result, tc.id)
		
		# 添加工具结果到对话历史
		if _conversations.has(conversation_id):
			_conversations[conversation_id].append({
				"role": "tool",
				"tool_call_id": tc.id,
				"content": result_str
			})
	
	# 清理当前请求
	_cleanup_request(request_id)
	
	# 继续对话 - 发送新请求
	var new_request_id = _generate_request_id()
	_original_request_ids[new_request_id] = original_id
	_request_conversations[new_request_id] = conversation_id
	
	# 构建新请求，保持原有选项，但刷新 tools 定义
	# （工具调用期间可能注册了新工具，如 skill 激活）
	var new_options = original_request.get("options", {}).duplicate()
	new_options["auto_tools"] = true
	var current_tools: Array = get_tools_definition()
	if current_tools.size() > 0:
		new_options["tools"] = current_tools
		new_options["tool_choice"] = "auto"
	
	var new_body = _build_chat_request(_conversations[conversation_id].duplicate(true), new_options)
	
	_request_queue.append({
		"id": new_request_id,
		"body": new_body,
		"options": new_options,
		"url": original_request.get("url", api_base_url + "/v1/chat/completions"),
		"type": "chat",
		"auto_tools": true
	})
	_retry_counts[new_request_id] = 0

func _create_temp_conversation_for_tools(original_request: Dictionary) -> String:
	var temp_id = "temp_tool_%d_%d" % [Time.get_ticks_msec(), randi()]
	var messages = original_request.body.get("messages", []).duplicate(true)
	_conversations[temp_id] = messages
	return temp_id

func _cleanup_tool_tracking(original_id: String) -> void:
	_tool_iteration_counts.erase(original_id)
	_tool_call_history.erase(original_id)
	# 清理所有指向此original_id的映射
	var keys_to_remove: Array = []
	for key in _original_request_ids.keys():
		if _original_request_ids[key] == original_id:
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_original_request_ids.erase(key)

func _update_conversation_from_response(request_id: String, response: Dictionary) -> void:
	if not auto_manage_history:
		return
	
	var conversation_id = _request_conversations.get(request_id, "")
	if conversation_id == "" or not _conversations.has(conversation_id):
		return
	
	if not response.has("choices") or response.choices.size() == 0:
		return
	
	var message = response.choices[0].get("message", {})
	if message.is_empty():
		return
	
	# 添加assistant消息到历史
	var assistant_msg: Dictionary = {"role": "assistant"}
	
	if message.has("content") and message.content != null:
		assistant_msg["content"] = message.content
	else:
		assistant_msg["content"] = null
	
	if message.has("tool_calls"):
		assistant_msg["tool_calls"] = message.tool_calls
	
	_conversations[conversation_id].append(assistant_msg)
	_trim_history(conversation_id)
	
	conversation_updated.emit(conversation_id, _conversations[conversation_id])
	_request_conversations.erase(request_id)
#endregion

#region 内部方法 - 错误处理

func _handle_http_error(result: int, request_id: String, original_request: Dictionary) -> void:
	var error_messages = {
		HTTPRequest.RESULT_CANT_CONNECT: "Cannot connect to server",
		HTTPRequest.RESULT_CANT_RESOLVE: "Cannot resolve hostname",
		HTTPRequest.RESULT_CONNECTION_ERROR: "Connection error",
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS handshake failed",
		HTTPRequest.RESULT_NO_RESPONSE: "No response from server",
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "Response body too large",
		HTTPRequest.RESULT_REQUEST_FAILED: "Request failed",
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "Cannot open download file",
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "Download file write error",
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "Redirect limit reached",
		HTTPRequest.RESULT_TIMEOUT: "Request timeout"
	}
	
	var error_msg = error_messages.get(result, "Unknown HTTP error: " + str(result))
	
	# 打印完整请求信息用于调试
	print("[AIService] === HTTP ERROR ===")
	print("[AIService] Request ID: ", request_id)
	print("[AIService] URL: ", original_request.get("url", "N/A"))
	print("[AIService] HTTP Result Code: ", result)
	print("[AIService] Error: ", error_msg)
	print("[AIService] Request Body: ", JSON.stringify(original_request.get("body", {}), "  "))
	print("[AIService] =================")
	
	_handle_error(request_id, error_msg, result, original_request)

func _handle_api_error(response_code: int, body: String, request_id: String, original_request: Dictionary) -> void:
	var error_msg = "API error (HTTP %d)" % response_code
	
	var json = JSON.new()
	if json.parse(body) == OK and json.data is Dictionary:
		var error_data = json.data.get("error", {})
		if error_data is Dictionary and error_data.has("message"):
			error_msg += ": " + error_data.message
	
	# 打印完整请求信息用于调试
	print("[AIService] === REQUEST FAILED ===")
	print("[AIService] Request ID: ", request_id)
	print("[AIService] URL: ", original_request.get("url", "N/A"))
	print("[AIService] HTTP Status: ", response_code)
	print("[AIService] Error: ", error_msg)
	print("[AIService] Response Body: ", body)
	print("[AIService] Request Body: ", JSON.stringify(original_request.get("body", {}), "  "))
	print("[AIService] ======================")
	
	_handle_error(request_id, error_msg, response_code, original_request)

func _handle_error(request_id: String, error: String, error_code: int, original_request: Dictionary) -> void:
	# 401/403等认证错误不应重试
	var no_retry_codes = [401, 403, 400, 404]
	if error_code in no_retry_codes:
		_cleanup_request(request_id)
		request_failed.emit(request_id, error, error_code)
		_check_queue_empty()
		return
	
	var retry_count = _retry_counts.get(request_id, 0)
	
	if retry_count < max_retries:
		_retry_counts[request_id] = retry_count + 1
		print("[AIService] Retrying request %s (attempt %d/%d): %s" % [request_id, retry_count + 1, max_retries, error])
		
		await get_tree().create_timer(retry_delay).timeout
		if is_instance_valid(self ):
			# 只清理HTTP请求，保留retry计数
			if _active_requests.has(request_id):
				var http: HTTPRequest = _active_requests[request_id]
				if is_instance_valid(http):
					http.queue_free()
				_active_requests.erase(request_id)
			_stream_buffers.erase(request_id)
			_request_queue.push_front(original_request)
	else:
		_cleanup_request(request_id)
		request_failed.emit(request_id, error, error_code)
		_check_queue_empty()

func _cleanup_request(request_id: String) -> void:
	if _active_requests.has(request_id):
		var http: HTTPRequest = _active_requests[request_id]
		if is_instance_valid(http):
			http.queue_free()
		_active_requests.erase(request_id)
	
	_stream_buffers.erase(request_id)
	_retry_counts.erase(request_id)

func _cleanup_all_requests() -> void:
	for request_id in _active_requests.keys():
		_cleanup_request(request_id)
	_stream_buffers.clear()
	_retry_counts.clear()

func _check_queue_empty() -> void:
	if _request_queue.size() == 0 and _active_requests.size() == 0:
		queue_empty.emit()
#endregion

#region 公共API - 实用工具

## 创建JSON模式请求选项
static func json_mode_options() -> Dictionary:
	return {"response_format": {"type": "json_object"}}

## 创建工具定义的辅助方法
static func create_tool(tool_name: String, description: String, properties: Dictionary, required: Array = []) -> Dictionary:
	return {
		"name": tool_name,
		"description": description,
		"parameters": {
			"type": "object",
			"properties": properties,
			"required": required
		}
	}

## 从响应中提取文本内容
static func extract_content(response: Dictionary) -> String:
	if not response.has("choices") or response.choices.size() == 0:
		return ""
	var message = response.choices[0].get("message", {})
	return message.get("content", "") if message.get("content") != null else ""

## 从响应中提取token使用信息
static func extract_usage(response: Dictionary) -> Dictionary:
	return response.get("usage", {})

## 检查响应是否因为工具调用而结束
static func is_tool_call_response(response: Dictionary) -> bool:
	if not response.has("choices") or response.choices.size() == 0:
		return false
	var finish_reason = response.choices[0].get("finish_reason", "")
	return finish_reason == "tool_calls"
#endregion
