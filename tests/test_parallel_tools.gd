extends Control
## 并行工具调用测试
## 测试 ai_config.cfg 中所有 chat 类型 AI 是否支持并行调用多个 tool
## 直接使用 AIService（不经过 ChatAgent），避免信号冲突

## 要测试的 profile 列表
var _test_queue: Array[Dictionary] = []
var _current_index: int = -1
var _results: Array[Dictionary] = []
var _current_ai: AIService = null
var _current_profile: Dictionary = {}
var _timeout_timer: float = 0.0
var _waiting: bool = false

const TEST_TIMEOUT: float = 120.0

const SYSTEM_PROMPT: String = "You are a helpful assistant. When the user asks for information, use the available tools to gather data. IMPORTANT: You MUST call ALL relevant tools at once in a single response using parallel tool calls. Do NOT call them one by one."

const USER_PROMPT: String = "I need three pieces of information right now. Please call all three tools simultaneously in one response:\n1. What time is it? (use get_current_time)\n2. What's the weather in Beijing? (use get_weather)\n3. What's today's news? (use get_news)\n\nCall all 3 tools in parallel in a single response."


func _ready() -> void:
	print("=" .repeat(60))
	print("[ParallelToolTest] 并行工具调用能力测试")
	print("=" .repeat(60))

	# 直接从 ConfigFile 读取所有 chat profile
	var cf := ConfigFile.new()
	if cf.load("res://ai_config.cfg") != OK:
		push_error("[ParallelToolTest] 无法加载 ai_config.cfg")
		return

	for section in cf.get_sections():
		if not section.begins_with("profiles/"):
			continue
		var profile_type: String = cf.get_value(section, "type", "chat")
		if profile_type != "chat":
			continue
		var profile_name: String = section.substr("profiles/".length())
		_test_queue.append({
			"profile_name": profile_name,
			"base_url": cf.get_value(section, "base_url", ""),
			"api_key": cf.get_value(section, "api_key", ""),
			"model": cf.get_value(section, "model", ""),
		})

	print("[ParallelToolTest] 找到 %d 个 chat profile 待测试" % _test_queue.size())
	for item in _test_queue:
		print("  - %s (%s)" % [item.profile_name, item.model])
	print("-" .repeat(60))

	_test_next()


func _process(delta: float) -> void:
	if not _waiting:
		return
	_timeout_timer += delta
	if _timeout_timer >= TEST_TIMEOUT:
		print("[ParallelToolTest] ⏰ %s 超时 (%.0fs)" % [_current_profile.profile_name, TEST_TIMEOUT])
		_record_result("TIMEOUT", 0, "请求超时")
		_cleanup_current()
		_test_next()


func _test_next() -> void:
	_current_index += 1
	if _current_index >= _test_queue.size():
		_print_summary()
		return

	_current_profile = _test_queue[_current_index]
	print("\n[ParallelToolTest] (%d/%d) 测试: %s [%s]" % [
		_current_index + 1, _test_queue.size(),
		_current_profile.profile_name, _current_profile.model
	])

	# 创建 AIService 节点
	_current_ai = AIService.new()
	_current_ai.api_base_url = _current_profile.base_url
	_current_ai.api_key = _current_profile.api_key
	_current_ai.model = _current_profile.model
	_current_ai.auto_execute_tools = false
	_current_ai.timeout = TEST_TIMEOUT
	add_child(_current_ai)

	# 注册 3 个工具
	_current_ai.register_tool("get_current_time", "Get the current date and time.", {
		"type": "object", "properties": {}, "required": []
	}, Callable(self, "_tool_get_time"))

	_current_ai.register_tool("get_weather", "Get weather information for a city.", {
		"type": "object",
		"properties": {"city": {"type": "string", "description": "City name"}},
		"required": ["city"]
	}, Callable(self, "_tool_get_weather"))

	_current_ai.register_tool("get_news", "Get today's news headlines.", {
		"type": "object", "properties": {}, "required": []
	}, Callable(self, "_tool_get_news"))

	# 连接信号
	_current_ai.tool_calls_requested.connect(_on_tool_calls_requested)
	_current_ai.request_completed.connect(_on_request_completed)
	_current_ai.request_failed.connect(_on_request_failed)

	# 构建消息并发送
	var messages: Array = [
		{"role": "system", "content": SYSTEM_PROMPT},
		{"role": "user", "content": USER_PROMPT},
	]

	_waiting = true
	_timeout_timer = 0.0
	_current_ai.chat_with_tools(messages, [], "auto", {"auto_execute": false})


## 工具回调（模拟数据）
func _tool_get_time(_args: Dictionary) -> Dictionary:
	return {"time": "2025-01-15 14:30:00", "timezone": "Asia/Shanghai"}

func _tool_get_weather(args: Dictionary) -> Dictionary:
	return {"city": args.get("city", "unknown"), "weather": "sunny", "temp": "5°C"}

func _tool_get_news(_args: Dictionary) -> Dictionary:
	return {"headlines": ["AI breakthrough", "Economy update", "Sports results"]}


## 信号回调
func _on_tool_calls_requested(_request_id: String, tool_calls: Array, _content: String) -> void:
	if not _waiting:
		return
	var count: int = tool_calls.size()
	var tool_names: Array[String] = []
	for tc in tool_calls:
		tool_names.append(tc.function.name)

	print("[ParallelToolTest] ✅ %s 返回 %d 个 tool_calls: %s" % [
		_current_profile.profile_name, count, str(tool_names)
	])

	if count >= 3:
		_record_result("PARALLEL_ALL", count, "并行调用全部 %d 个工具: %s" % [count, ", ".join(tool_names)])
	elif count >= 2:
		_record_result("PARALLEL_PARTIAL", count, "并行调用 %d 个工具: %s" % [count, ", ".join(tool_names)])
	else:
		_record_result("SEQUENTIAL", count, "仅调用 %d 个工具: %s" % [count, ", ".join(tool_names)])

	_cleanup_current()
	_test_next()


func _on_request_completed(_request_id: String, response: Dictionary) -> void:
	if not _waiting:
		return
	var content: String = ""
	if response.has("choices") and response["choices"].size() > 0:
		content = str(response["choices"][0].get("message", {}).get("content", ""))
	print("[ParallelToolTest] ⚠️ %s 未调用工具，直接返回文本" % _current_profile.profile_name)
	print("  回复前200字: %s" % content.left(200))
	_record_result("NO_TOOLS", 0, "未调用工具")
	_cleanup_current()
	_test_next()


func _on_request_failed(_request_id: String, error: String, _error_code: int) -> void:
	if not _waiting:
		return
	print("[ParallelToolTest] ❌ %s 请求失败: %s" % [_current_profile.profile_name, error])
	_record_result("ERROR", 0, error)
	_cleanup_current()
	_test_next()


func _record_result(status: String, tool_count: int, detail: String) -> void:
	_results.append({
		"profile": _current_profile.profile_name,
		"model": _current_profile.model,
		"status": status,
		"tool_count": tool_count,
		"detail": detail,
	})


func _cleanup_current() -> void:
	_waiting = false
	if _current_ai != null:
		_current_ai.queue_free()
		_current_ai = null


func _print_summary() -> void:
	print("\n" + "=" .repeat(60))
	print("[ParallelToolTest] 测试结果汇总")
	print("=" .repeat(60))
	for r in _results:
		var icon: String
		match r.status:
			"PARALLEL_ALL": icon = "✅"
			"PARALLEL_PARTIAL": icon = "🟡"
			"SEQUENTIAL": icon = "⚠️"
			"NO_TOOLS": icon = "🔵"
			"ERROR": icon = "❌"
			"TIMEOUT": icon = "⏰"
			_: icon = "❓"
		print("%s [%s] %s (model: %s)" % [icon, r.status, r.profile, r.model])
		print("   %s" % r.detail)

	print("-" .repeat(60))
	var parallel_count: int = 0
	for r in _results:
		if r.status.begins_with("PARALLEL"):
			parallel_count += 1
	print("支持并行调用: %d / %d" % [parallel_count, _results.size()])
	print("=" .repeat(60))
