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
## ai.model = "deepseek-v4-flash"
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
## API基础URL。可传纯域名、带版本前缀的路径，或完整端点。
@export var api_base_url: String = "https://api.deepseek.com"
## API密钥
@export var api_key: String = ""
## 使用的模型名称
@export var model: String = "deepseek-v4-flash"

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
@export var default_max_tokens: int = 16384
## 默认top_p参数
@export_range(0.0, 1.0) var default_top_p: float = 1.0
## 默认思考模式: "disabled" 或 "enabled"
@export var default_thinking: String = "disabled"
## 兼容部分 OpenAI-compatible provider 的思考开关
@export var default_enable_thinking: bool = false
## 思考强度，留空则不发送。
## 接受 low / medium / high / xhigh / max；实际下发前会按 base_url 自动适配 provider：
##   - DeepSeek：low/medium/high → high；xhigh/max → max
##   - 其他 OpenAI 兼容（含 OpenAI o-series）：xhigh/max → high；其余原样下发
@export var default_reasoning_effort: String = ""

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
## 是否输出完整响应与逐步工具调用日志（默认关闭，避免刷屏）
@export var verbose_debug_logging: bool = false
const TERMINAL_TOOL_NAMES: PackedStringArray = ["finish", "wo_finish_order"]
const TOOL_EXECUTION_POLICY_PARALLEL: String = "parallel"
const TOOL_EXECUTION_POLICY_READ_PARALLEL_WRITE_SERIAL: String = "read_parallel_write_serial"
const TOOL_EFFECT_READ: String = "read"
const TOOL_EFFECT_WRITE: String = "write"
const TOOL_EFFECT_TERMINAL: String = "terminal"
const READ_TOOL_NAMES: PackedStringArray = [
	"kb_read", "db_list", "db_get", "get_story_outline", "get_scene_script",
	"gather_scene_context", "list_assets", "list_scene_catalog",
	"analyze_story_reachability", "project_info", "wo_get_order_details",
	"wo_list_order_summaries", "research",
]
const WRITE_TOOL_NAMES: PackedStringArray = [
	"kb_write", "kb_delete", "db_create", "db_update", "db_delete",
	"set_scene_script", "batch_patch_scene_scripts", "project_save",
	"import_project_asset", "preview_scene", "set_initial_scene",
	"wo_complete_task", "occupy_character_shell", "activate_skill",
	"deactivate_skill",
]

@export_group("Debug Metadata")
## 由 AIConfigManager 写入的业务 role，用于定位缓存命中日志来源。
@export var service_role: String = ""
## 可选的业务来源标签；为空时使用节点名。
@export var debug_source: String = ""
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
# 单次请求调试元数据 {request_id: {source, role, prompt_key}}
var _request_debug_meta: Dictionary = {}
# DeepSeek 上下文缓存命中统计（本进程累计），便于调优 prompt 前缀稳定性
var _cache_session_hit_tokens: int = 0
var _cache_session_miss_tokens: int = 0
var _cache_session_request_count: int = 0
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
	
	var url = _resolve_completion_api_url(options)
	_request_queue.append({
		"id": request_id,
		"body": body,
		"options": options,
		"url": url,
		"type": "completion"
	})
	_request_debug_meta[request_id] = _build_request_debug_meta(options)
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
## [param llm_view] 可选。定义该工具执行后喂回 LLM 的可见结果。
##   - Array[String]: 按 dotted path 选择返回字段，如 ["success", "data.scene_id", "data.dsl"]
##   - Dictionary: {"fields": [...]} 或 {"raw": true}
##   - Callable: func(result) -> Variant，自定义投影
## [param metadata] 可选。工具调度元数据，如 {"effect": "read"|"write"|"terminal"}。
func register_tool(tool_name: String, description: String, parameters: Dictionary, callback: Callable = Callable(), llm_view: Variant = null, metadata: Dictionary = {}) -> void:
	_registered_tools[tool_name] = {
		"type": "function",
		"function": {
			"name": tool_name,
			"description": description,
			"parameters": parameters
		},
		"callback": callback,
		"llm_view": llm_view,
		"metadata": metadata.duplicate(true),
	}

## 注册多个工具
func register_tools(tools: Array[Dictionary]) -> void:
	for tool in tools:
		var cb = tool.get("callback", Callable())
		var llm_view: Variant = tool.get("llm_view", null)
		var metadata: Dictionary = tool.get("metadata", {})
		register_tool(tool.name, tool.description, tool.parameters, cb, llm_view, metadata)

## 取消注册工具
func unregister_tool(tool_name: String) -> void:
	_registered_tools.erase(tool_name)


func set_tool_metadata(tool_name: String, metadata: Dictionary, merge: bool = true) -> void:
	if not _registered_tools.has(tool_name):
		return
	var tool_data: Dictionary = _registered_tools[tool_name]
	var current: Dictionary = tool_data.get("metadata", {})
	if merge:
		for key in metadata.keys():
			current[key] = metadata[key]
	else:
		current = metadata.duplicate(true)
	tool_data["metadata"] = current
	_registered_tools[tool_name] = tool_data


func get_tool_metadata(tool_name: String) -> Dictionary:
	if not _registered_tools.has(tool_name):
		return {}
	return (_registered_tools[tool_name] as Dictionary).get("metadata", {}).duplicate(true)

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


func _summarize_tool_result_for_conversation(function_name: String, result: Variant, options: Dictionary) -> String:
	var projected: Variant = _project_tool_result_for_llm(function_name, result)
	if projected != null:
		return _stringify_tool_result(projected, 0)

	var summarizer: Variant = options.get("tool_result_summarizer", Callable())
	if summarizer is Callable:
		var cb: Callable = summarizer
		if cb.is_valid():
			var summarized: Variant = cb.call(function_name, result)
			return str(summarized)

	return _stringify_tool_result(result)


func _project_tool_result_for_llm(function_name: String, result: Variant) -> Variant:
	if not _registered_tools.has(function_name):
		return null

	var llm_view: Variant = (_registered_tools[function_name] as Dictionary).get("llm_view", null)
	if llm_view == null:
		return null

	if llm_view is Callable:
		var cb: Callable = llm_view
		if cb.is_valid():
			return cb.call(result)
		return null

	if llm_view is Dictionary:
		var cfg: Dictionary = llm_view
		if bool(cfg.get("raw", false)):
			return result
		var cfg_fields: Variant = cfg.get("fields", [])
		if cfg_fields is Array:
			return _pick_result_fields(result, cfg_fields)
		return null

	if llm_view is Array:
		return _pick_result_fields(result, llm_view)

	return null


func _pick_result_fields(source: Variant, field_paths: Array) -> Variant:
	if not (source is Dictionary):
		return source
	var projected: Dictionary = {}
	for raw_path in field_paths:
		var path: String = str(raw_path).strip_edges()
		if path.is_empty():
			continue
		var value: Variant = _get_value_by_dotted_path(source, path)
		if value == null:
			continue
		_set_value_by_dotted_path(projected, path, value)
	return projected


func _get_value_by_dotted_path(source: Variant, dotted_path: String) -> Variant:
	var current: Variant = source
	for segment in dotted_path.split("."):
		var key: String = segment.strip_edges()
		if key.is_empty():
			return null
		if current is Dictionary:
			var current_dict: Dictionary = current
			if not current_dict.has(key):
				return null
			current = current_dict.get(key)
			continue
		if current is Array and key.is_valid_int():
			var current_array: Array = current
			var idx: int = int(key)
			if idx < 0 or idx >= current_array.size():
				return null
			current = current_array[idx]
			continue
		return null
	return current


func _set_value_by_dotted_path(target: Dictionary, dotted_path: String, value: Variant) -> void:
	var parts: PackedStringArray = dotted_path.split(".")
	if parts.is_empty():
		return
	var cursor: Dictionary = target
	for i in range(parts.size()):
		var key: String = parts[i].strip_edges()
		if key.is_empty():
			return
		if i == parts.size() - 1:
			cursor[key] = value
			return
		var next_value: Variant = cursor.get(key, null)
		if not (next_value is Dictionary):
			cursor[key] = {}
		var child_dict: Dictionary = cursor.get(key, {})
		cursor = child_dict


func _stringify_tool_result(result: Variant, max_chars: int = 400) -> String:
	var raw: String = JSON.stringify(result) if result != null else "null"
	raw = raw.replace("\n", "\\n")
	if max_chars > 0 and raw.length() > max_chars:
		return raw.left(max_chars) + "..."
	return raw

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
		var result_str = _summarize_tool_result_for_conversation(func_name, result, options)
		
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
	
	# Thinking / Deep reasoning (DeepSeek/OpenAI 兼容模型)
	# 默认 disabled，避免浪费 token（项目已通过 <think> 标签自行管理思维链）
	var thinking_type: String = str(options.get("thinking", default_thinking)).strip_edges()
	if thinking_type.is_empty():
		thinking_type = "disabled"
	body["thinking"] = {"type": thinking_type}
	body["enable_thinking"] = options.get("enable_thinking", default_enable_thinking)
	var reasoning_effort: String = str(options.get("reasoning_effort", default_reasoning_effort)).strip_edges()
	var normalized_effort: String = _normalize_reasoning_effort(reasoning_effort, str(options.get("api_url", api_base_url)))
	if not normalized_effort.is_empty():
		body["reasoning_effort"] = normalized_effort
	
	# Seed for reproducibility
	if options.has("seed"):
		body["seed"] = options["seed"]
	
	return body

func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	])


func _resolve_chat_api_url(options: Dictionary = {}) -> String:
	return _normalize_api_endpoint(str(options.get("api_url", api_base_url)), "/chat/completions")


func _resolve_completion_api_url(options: Dictionary = {}) -> String:
	return _normalize_api_endpoint(str(options.get("api_url", api_base_url)), "/completions")


func _normalize_api_endpoint(raw_url: String, required_suffix: String, default_version: String = "v1") -> String:
	var normalized_url: String = raw_url.strip_edges().trim_suffix("/")
	if normalized_url.is_empty():
		var fallback_suffix: String = required_suffix.trim_prefix("/")
		return "/%s/%s" % [default_version.trim_prefix("/"), fallback_suffix]

	if normalized_url.ends_with(required_suffix):
		return normalized_url

	var has_version_segment: bool = false
	var scheme_index: int = normalized_url.find("://")
	var path_start: int = normalized_url.find("/", scheme_index + 3) if scheme_index != -1 else normalized_url.find("/")
	if path_start != -1 and path_start + 1 < normalized_url.length():
		var path_segments: PackedStringArray = normalized_url.substr(path_start + 1).split("/", false)
		for segment in path_segments:
			var normalized_segment: String = segment.strip_edges().to_lower()
			if normalized_segment.length() > 1 \
					and normalized_segment.begins_with("v") \
					and _is_ascii_digit(normalized_segment.unicode_at(1)):
				has_version_segment = true
				break

	if not has_version_segment:
		normalized_url += "/%s" % default_version.trim_prefix("/")

	if not normalized_url.ends_with(required_suffix):
		normalized_url += required_suffix
	return normalized_url


func _is_ascii_digit(codepoint: int) -> bool:
	return codepoint >= 48 and codepoint <= 57
#endregion

#region 内部方法 - 队列管理

func _enqueue_request(request_id: String, body: Dictionary, options: Dictionary) -> void:
	var auto_tools = options.get("auto_tools", false)
	_request_queue.append({
		"id": request_id,
		"body": body,
		"options": options,
		"url": _resolve_chat_api_url(options),
		"type": "chat",
		"auto_tools": auto_tools
	})
	_request_debug_meta[request_id] = _build_request_debug_meta(options)
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
	if verbose_debug_logging:
		print(response_text)
	if parse_result != OK:
		_handle_error(request_id, "Failed to parse JSON response", parse_result, original_request)
		return
	
	var response = _normalize_response_reasoning(json.data)
	var original_id = _original_request_ids.get(request_id, request_id)

	_log_cache_stats(response, request_id, original_id)
	_update_conversation_from_response(request_id, response)
	
	if _has_tool_calls(response):
		var tool_calls = _extract_tool_calls(response)
		var tc_content: String = ""
		var tc_reasoning: String = AIService.extract_reasoning_content(response)
		if response.has("choices") and response["choices"].size() > 0:
			var msg = response["choices"][0].get("message", {})
			tc_content = _get_message_content_text(msg)
		# 工具轮必须始终通知监听方（如 ChatAgent）：即使 assistant 正文为空，也要先写入带 tool_calls 的 assistant，
		# 再追加 tool 消息；否则下一轮请求会出现「tool 前无 tool_calls」而被 API 拒绝。
		request_completed.emit(original_id, response)

		tool_calls_requested.emit(original_id, tool_calls, tc_content)
		if tool_calls.size() == 1:
			var tc = tool_calls[0]
			var args = _parse_tool_arguments(tc.function.arguments)
			function_call_requested.emit(original_id, tc.function.name, args)

		if auto_execute_tools and original_request.get("auto_tools", false):
			_auto_execute_tool_calls(request_id, original_id, tool_calls, original_request, tc_content, tc_reasoning)
		else:
			_cleanup_request(request_id)
	else:
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

	final_response = _normalize_response_reasoning(final_response)
	var final_message: Dictionary = final_response.choices[0].get("message", {})
	var normalized_content: Variant = final_message.get("content", "")
	full_content = str(normalized_content) if normalized_content != null else ""
	
	# 更新对话历史
	_update_conversation_from_response(request_id, final_response)
	
	if tool_calls.size() > 0:
		# 与非流式一致：工具轮必须触发 request_completed，供 ChatAgent 写入 tool_calls  assistant（正文可为空）。
		request_completed.emit(original_id, final_response)
		# 发出信号（用于监听）
		var stream_content: String = full_content if full_content != "" else ""
		tool_calls_requested.emit(original_id, tool_calls, stream_content)
		if tool_calls.size() == 1:
			var tc = tool_calls[0]
			var args = _parse_tool_arguments(tc.function.arguments)
			function_call_requested.emit(original_id, tc.function.name, args)
		
		# 检查是否自动执行工具
		if auto_execute_tools and original_request.get("auto_tools", false):
			var stream_reasoning: String = AIService.extract_reasoning_content(final_response)
			_auto_execute_tool_calls(request_id, original_id, tool_calls, original_request, stream_content, stream_reasoning)
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

func _get_message_tool_calls(message: Dictionary) -> Array:
	var tool_calls_value: Variant = message.get("tool_calls", null)
	if tool_calls_value is Array:
		return tool_calls_value
	return []

func _get_message_content_text(message: Dictionary) -> String:
	var content_text: String = _content_value_to_text(message.get("content", null))
	if message.has("reasoning_content"):
		return content_text.strip_edges()
	if not content_text.is_empty():
		return _split_reasoning_from_text(content_text).get("content", "")
	var refusal_value: Variant = message.get("refusal", null)
	if refusal_value is String:
		return refusal_value
	return ""


func _normalize_response_reasoning(response: Dictionary) -> Dictionary:
	var raw_choices: Variant = response.get("choices", [])
	if not response.has("choices") or not (raw_choices is Array) or raw_choices.is_empty():
		return response

	var normalized: Dictionary = response.duplicate(true)
	var first_choice: Variant = normalized.choices[0]
	if not (first_choice is Dictionary):
		return normalized

	var message: Dictionary = first_choice.get("message", {})
	if message.is_empty():
		return normalized

	var normalized_message: Dictionary = message.duplicate(true)
	var content_text: String = _content_value_to_text(normalized_message.get("content", null))
	if content_text.is_empty():
		return normalized

	var split := _split_reasoning_from_text(content_text)
	var reasoning_text: String = str(split.get("reasoning_content", "")).strip_edges()
	var body_text: String = str(split.get("content", "")).strip_edges()
	if reasoning_text.is_empty():
		return normalized

	normalized_message["reasoning_content"] = reasoning_text
	if body_text.is_empty():
		normalized_message["content"] = null
	else:
		normalized_message["content"] = body_text
	normalized.choices[0]["message"] = normalized_message
	return normalized


static func _content_value_to_text(content_value: Variant) -> String:
	if content_value is String:
		return content_value
	if content_value is Array:
		var parts: Array[String] = []
		for part in content_value:
			if part is String:
				parts.append(part)
			elif part is Dictionary:
				var part_type: String = str(part.get("type", ""))
				if part_type == "text":
					var text_value: Variant = part.get("text", "")
					if text_value is String and not text_value.is_empty():
						parts.append(text_value)
				elif part.has("content"):
					var nested_content: Variant = part.get("content", "")
					if nested_content is String and not nested_content.is_empty():
						parts.append(nested_content)
		return "".join(parts)
	return ""


static func _strip_leading_thinking_block_text(text: String) -> String:
	return str(_split_reasoning_from_text(text).get("content", ""))


static func _split_reasoning_from_text(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return {"reasoning_content": "", "content": cleaned}

	var regex := RegEx.new()
	regex.compile("^\\s*<(thinking|think)>([\\s\\S]*?)</(thinking|think)>\\s*([\\s\\S]*)$")
	var match := regex.search(cleaned)
	if match:
		var opening_tag := match.get_string(1).strip_edges().to_lower()
		var closing_tag := match.get_string(3).strip_edges().to_lower()
		if opening_tag == closing_tag or (opening_tag == "thinking" and closing_tag == "think"):
			return {
				"reasoning_content": match.get_string(2).strip_edges(),
				"content": match.get_string(4).strip_edges(),
			}

	var fallback_regex := RegEx.new()
	fallback_regex.compile("^\\s*<thinking>([\\s\\S]*?)</think>\\s*([\\s\\S]*)$")
	var fallback_match := fallback_regex.search(cleaned)
	if fallback_match:
		return {
			"reasoning_content": fallback_match.get_string(1).strip_edges(),
			"content": fallback_match.get_string(2).strip_edges(),
		}

	var unclosed_regex := RegEx.new()
	unclosed_regex.compile("^\\s*<(thinking|think)>([\\s\\S]*)$")
	var unclosed_match := unclosed_regex.search(cleaned)
	if unclosed_match:
		var trailing_text := unclosed_match.get_string(2).strip_edges()
		var separator_index := trailing_text.find("\n\n")
		if separator_index >= 0:
			return {
				"reasoning_content": trailing_text.substr(0, separator_index).strip_edges(),
				"content": trailing_text.substr(separator_index + 2).strip_edges(),
			}
		return {"reasoning_content": trailing_text, "content": ""}

	return {"reasoning_content": "", "content": cleaned}

func _has_tool_calls(response: Dictionary) -> bool:
	if not response.has("choices") or response.choices.size() == 0:
		return false
	var message = response.choices[0].get("message", {})
	var tool_calls: Array = _get_message_tool_calls(message)
	return tool_calls.size() > 0

func _extract_tool_calls(response: Dictionary) -> Array:
	if not _has_tool_calls(response):
		return []
	var message = response.choices[0].get("message", {})
	return _get_message_tool_calls(message)

func _parse_tool_arguments(args_str: String) -> Dictionary:
	var json = JSON.new()
	if json.parse(args_str) == OK:
		return json.data
	return {}

## 自动执行工具调用并继续对话
## assistant_reasoning_content：在 thinking 模式下必须把第一回合的 reasoning 回传，
## 否则 DeepSeek 等服务商会返回 400「reasoning_content must be passed back to the API」。
func _auto_execute_tool_calls(request_id: String, original_id: String, tool_calls: Array, original_request: Dictionary, assistant_content: String = "", assistant_reasoning_content: String = "") -> void:
	var debug_meta: Dictionary = _request_debug_meta.get(request_id, _request_debug_meta.get(original_id, {})).duplicate()
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
	# thinking 模式下必须保留 reasoning_content，否则下一轮调用会被服务商拒掉
	if not assistant_reasoning_content.is_empty():
		assistant_msg["reasoning_content"] = assistant_reasoning_content
	if _conversations.has(conversation_id):
		_conversations[conversation_id].append(assistant_msg)

	var terminal_tool_response: Dictionary = await _execute_tool_calls_with_policy(
		tool_calls,
		original_request,
		original_id,
		conversation_id
	)
	
	# 清理当前请求
	_cleanup_request(request_id)

	if not terminal_tool_response.is_empty():
		var tool_history = _tool_call_history.get(original_id, [])
		if tool_history.size() > 0:
			tool_calls_completed.emit(original_id, tool_history)
		_cleanup_tool_tracking(original_id)
		request_completed.emit(original_id, terminal_tool_response)
		_check_queue_empty()
		return
	
	# 继续对话 - 发送新请求
	var new_request_id = _generate_request_id()
	_original_request_ids[new_request_id] = original_id
	_request_conversations[new_request_id] = conversation_id
	_request_debug_meta[new_request_id] = debug_meta
	
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
		"url": original_request.get("url", _resolve_chat_api_url(new_options)),
		"type": "chat",
		"auto_tools": true
	})
	_retry_counts[new_request_id] = 0


func _execute_tool_calls_with_policy(tool_calls: Array, original_request: Dictionary, original_id: String, conversation_id: String) -> Dictionary:
	var options: Dictionary = original_request.get("options", {})
	var policy: String = str(options.get("tool_execution_policy", TOOL_EXECUTION_POLICY_PARALLEL)).strip_edges()
	if policy == TOOL_EXECUTION_POLICY_READ_PARALLEL_WRITE_SERIAL:
		return await _execute_tool_calls_read_parallel_write_serial(tool_calls, original_request, original_id, conversation_id)
	return await _execute_tool_calls_parallel(tool_calls, original_request, original_id, conversation_id)


func _execute_tool_calls_parallel(tool_calls: Array, original_request: Dictionary, original_id: String, conversation_id: String) -> Dictionary:
	var tool_states: Array = []
	for tc in tool_calls:
		var state: Dictionary = _build_tool_state(tc)
		tool_states.append(state)
		_run_one_tool_async(state)
	await _wait_for_parallel_tool_states(tool_states)
	return _record_tool_states(tool_states, original_request, original_id, conversation_id)


func _execute_tool_calls_read_parallel_write_serial(tool_calls: Array, original_request: Dictionary, original_id: String, conversation_id: String) -> Dictionary:
	var pending_read_states: Array = []
	for tc in tool_calls:
		var state: Dictionary = _build_tool_state(tc)
		var effect: String = _get_tool_effect(str(state.get("func_name", "")))
		if effect == TOOL_EFFECT_READ:
			pending_read_states.append(state)
			continue

		if not pending_read_states.is_empty():
			await _execute_read_tool_batch(pending_read_states)
			var read_terminal: Dictionary = _record_tool_states(pending_read_states, original_request, original_id, conversation_id)
			pending_read_states = []
			if not read_terminal.is_empty():
				return read_terminal

		await _execute_tool_state_serial(state)
		var terminal_response: Dictionary = _record_tool_states([state], original_request, original_id, conversation_id)
		if not terminal_response.is_empty():
			return terminal_response

	if not pending_read_states.is_empty():
		await _execute_read_tool_batch(pending_read_states)
		return _record_tool_states(pending_read_states, original_request, original_id, conversation_id)

	return {}


func _build_tool_state(tc: Dictionary) -> Dictionary:
	var func_name: String = tc.function.name
	var args: Dictionary = _parse_tool_arguments(tc.function.arguments)
	if verbose_debug_logging:
		print("[AIService] Auto-executing tool: %s with args: %s" % [func_name, str(args)])
	return {
		"tc": tc,
		"func_name": func_name,
		"args": args,
		"completed": false,
		"result": null,
	}


func _execute_read_tool_batch(states: Array) -> void:
	for state in states:
		_run_one_tool_async(state)
	await _wait_for_parallel_tool_states(states)


func _wait_for_parallel_tool_states(states: Array) -> void:
	for state in states:
		while not bool(state.get("completed", false)):
			await get_tree().process_frame


func _execute_tool_state_serial(state: Dictionary) -> void:
	state["result"] = await execute_tool_callback(state["func_name"], state["args"])
	state["completed"] = true


func _record_tool_states(states: Array, original_request: Dictionary, original_id: String, conversation_id: String) -> Dictionary:
	var terminal_tool_response: Dictionary = {}
	for state in states:
		var func_name: String = state["func_name"]
		var args: Dictionary = state["args"]
		var tc: Dictionary = state["tc"]
		var result: Variant = state["result"]
		var result_str = _summarize_tool_result_for_conversation(func_name, result, original_request.get("options", {}))

		_tool_call_history[original_id].append({
			"name": func_name,
			"arguments": args,
			"result": result,
		})

		tool_executed.emit(original_id, func_name, args, result, tc.id)

		if _conversations.has(conversation_id):
			_conversations[conversation_id].append({
				"role": "tool",
				"tool_call_id": tc.id,
				"content": result_str,
			})

		if _is_terminal_tool_name(func_name) and _is_terminal_tool_success(result):
			terminal_tool_response = _build_terminal_tool_response(result)
			break
	return terminal_tool_response


func _is_terminal_tool_name(function_name: String) -> bool:
	if TERMINAL_TOOL_NAMES.has(function_name):
		return true
	return _get_tool_effect(function_name) == TOOL_EFFECT_TERMINAL


func _get_tool_effect(function_name: String) -> String:
	var metadata: Dictionary = get_tool_metadata(function_name)
	var explicit_effect: String = str(metadata.get("effect", "")).strip_edges()
	if explicit_effect in [TOOL_EFFECT_READ, TOOL_EFFECT_WRITE, TOOL_EFFECT_TERMINAL]:
		return explicit_effect
	if TERMINAL_TOOL_NAMES.has(function_name):
		return TOOL_EFFECT_TERMINAL
	if READ_TOOL_NAMES.has(function_name):
		return TOOL_EFFECT_READ
	if WRITE_TOOL_NAMES.has(function_name):
		return TOOL_EFFECT_WRITE
	return TOOL_EFFECT_WRITE


## Fan-out 协程：执行单个 tool callback，结果写回 state 字典。
## 调用方不 await 此函数，多个调用便能并发推进各自的 await 点。
func _run_one_tool_async(state: Dictionary) -> void:
	state["result"] = await execute_tool_callback(state["func_name"], state["args"])
	state["completed"] = true


func _is_terminal_tool_success(result: Variant) -> bool:
	if not (result is Dictionary):
		return false
	return bool((result as Dictionary).get("success", false))


func _build_terminal_tool_response(result: Variant) -> Dictionary:
	var summary: String = ""
	if result is Dictionary:
		summary = str((result as Dictionary).get("summary", "")).strip_edges()
		if summary.is_empty():
			summary = str((result as Dictionary).get("message", "")).strip_edges()
	var content: String = "<result>%s</result>" % summary
	return {
		"choices": [{
			"message": {
				"role": "assistant",
				"content": content,
			}
		}]
	}

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
	
	var message_content: String = _get_message_content_text(message)
	if not message_content.is_empty():
		assistant_msg["content"] = message_content
	else:
		assistant_msg["content"] = null
	
	if message.has("tool_calls"):
		var tool_calls: Array = _get_message_tool_calls(message)
		if tool_calls.size() > 0:
			assistant_msg["tool_calls"] = tool_calls
	
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
	_request_debug_meta.erase(request_id)

func _cleanup_all_requests() -> void:
	for request_id in _active_requests.keys():
		_cleanup_request(request_id)
	_stream_buffers.clear()
	_retry_counts.clear()
	_request_debug_meta.clear()

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
	var content_value: Variant = message.get("content", null)
	var content_text: String = _content_value_to_text(content_value)
	if message.has("reasoning_content"):
		return content_text.strip_edges()
	if not content_text.is_empty():
		return str(_split_reasoning_from_text(content_text).get("content", ""))
	var refusal_value: Variant = message.get("refusal", null)
	return refusal_value if refusal_value is String else ""


## 把通用 reasoning_effort 标签映射为对应 provider 实际支持的合法值。
##
## 不同 provider 的 reasoning_effort 词表不一样：
##   - OpenAI o-series：low / medium / high
##   - DeepSeek 思考模型：仅 high / max（low、medium 会被 reject）
##
## 为了让上层配置（cfg / options）不必关心 provider 差异，在这里做一次兼容映射。
## 对未知 provider 默认按 OpenAI 兼容处理（直通），避免错误改写合法值。
static func _normalize_reasoning_effort(effort: String, base_url: String) -> String:
	var normalized: String = effort.strip_edges().to_lower()
	if normalized.is_empty():
		return ""

	var url_lower: String = base_url.to_lower()
	var is_deepseek: bool = url_lower.contains("deepseek")

	if is_deepseek:
		# DeepSeek 仅有 high / max 两档
		match normalized:
			"low", "medium", "high":
				return "high"
			"xhigh", "max":
				return "max"
			_:
				# 未知值：按 high 兜底（比 reject 更友好）
				return "high"

	# 其他 provider（OpenAI 兼容）
	match normalized:
		"xhigh":
			# OpenAI 不识别 xhigh，向下取 high
			return "high"
		"max":
			# 同上，OpenAI 不识别 max
			return "high"
		_:
			return normalized


static func extract_reasoning_content(response: Dictionary) -> String:
	if not response.has("choices") or response.choices.size() == 0:
		return ""
	var message = response.choices[0].get("message", {})
	if message.has("reasoning_content"):
		return str(message.get("reasoning_content", "")).strip_edges()
	var content_text: String = _content_value_to_text(message.get("content", null))
	if content_text.is_empty():
		return ""
	return str(_split_reasoning_from_text(content_text).get("reasoning_content", "")).strip_edges()

## 从响应中提取token使用信息
static func extract_usage(response: Dictionary) -> Dictionary:
	return response.get("usage", {})


func _build_request_debug_meta(options: Dictionary) -> Dictionary:
	var meta: Dictionary = {}
	var keys: Array[String] = ["source", "trace_label", "business", "prompt_key", "role"]
	for key in keys:
		if options.has(key):
			var value: String = str(options.get(key, "")).strip_edges()
			if not value.is_empty():
				meta[key] = value
	return meta


func _get_request_debug_meta(request_id: String, original_id: String) -> Dictionary:
	var meta: Dictionary = _request_debug_meta.get(request_id, {})
	if meta.is_empty() and original_id != request_id:
		meta = _request_debug_meta.get(original_id, {})
	return meta


func _get_cache_log_context(request_id: String, original_id: String) -> Dictionary:
	var meta: Dictionary = _get_request_debug_meta(request_id, original_id)
	var source: String = str(meta.get("source", meta.get("trace_label", meta.get("business", debug_source)))).strip_edges()
	if source.is_empty():
		source = str(name) if not str(name).is_empty() else "AIService"
	var role: String = str(meta.get("role", service_role)).strip_edges()
	if role.is_empty():
		role = "unassigned"
	var prompt_key: String = str(meta.get("prompt_key", "-")).strip_edges()
	if prompt_key.is_empty():
		prompt_key = "-"
	return {
		"source": source,
		"role": role,
		"prompt_key": prompt_key,
	}


## DeepSeek 缓存命中统计：把每次响应里的 prompt_cache_hit_tokens / prompt_cache_miss_tokens
## 累计到本进程会话计数器，并打一条单行日志，便于调优 prompt 前缀稳定性。
## 字段缺失（其它 provider 或老版本接口）时静默跳过。
func _log_cache_stats(response: Dictionary, request_id: String, original_id: String) -> void:
	var usage: Dictionary = response.get("usage", {})
	if usage.is_empty():
		return
	if not usage.has("prompt_cache_hit_tokens") and not usage.has("prompt_cache_miss_tokens"):
		return

	var hit: int = int(usage.get("prompt_cache_hit_tokens", 0))
	var miss: int = int(usage.get("prompt_cache_miss_tokens", 0))
	var prompt_tokens: int = int(usage.get("prompt_tokens", hit + miss))

	_cache_session_hit_tokens += hit
	_cache_session_miss_tokens += miss
	_cache_session_request_count += 1

	var ratio: float = 0.0
	if hit + miss > 0:
		ratio = 100.0 * float(hit) / float(hit + miss)
	var session_total: int = _cache_session_hit_tokens + _cache_session_miss_tokens
	var session_ratio: float = 0.0
	if session_total > 0:
		session_ratio = 100.0 * float(_cache_session_hit_tokens) / float(session_total)
	var context: Dictionary = _get_cache_log_context(request_id, original_id)

	print("[AIService.cache] source=%s role=%s model=%s prompt_key=%s req=%s prompt=%d hit=%d miss=%d ratio=%.1f%% | session reqs=%d hit_total=%d miss_total=%d ratio=%.1f%%" % [
		context.source, context.role, model, context.prompt_key,
		original_id, prompt_tokens, hit, miss, ratio,
		_cache_session_request_count, _cache_session_hit_tokens, _cache_session_miss_tokens, session_ratio,
	])


## 取本进程会话累计的 DeepSeek 缓存命中统计。
func get_cache_session_stats() -> Dictionary:
	return {
		"requests": _cache_session_request_count,
		"hit_tokens": _cache_session_hit_tokens,
		"miss_tokens": _cache_session_miss_tokens,
	}

## 检查响应是否因为工具调用而结束
static func is_tool_call_response(response: Dictionary) -> bool:
	if not response.has("choices") or response.choices.size() == 0:
		return false
	var finish_reason = response.choices[0].get("finish_reason", "")
	return finish_reason == "tool_calls"
#endregion
