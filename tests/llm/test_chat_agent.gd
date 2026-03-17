extends Node
## ChatAgent 集成测试
## 测试 PromptManager 模板替换 + ChatAgent 工具调用 + Sub-Agent 委托

@onready var main_agent: Node = $MainAgent
@onready var file_agent: Node = $FileAgent


func _ready() -> void:
	# === 测试 PromptManager ===
	_test_prompt_manager()
	
	# === 设置 Main Agent ===
	_setup_main_agent()
	
	# === 设置 File Agent (sub-agent) ===
	_setup_file_agent()
	
	# 连接日志信号
	main_agent.log_entry.connect(_on_main_log)
	file_agent.log_entry.connect(_on_file_log)
	main_agent.message_completed.connect(_on_main_completed)
	main_agent.message_failed.connect(_on_main_failed)
	
	print("[TEST] === ChatAgent 测试就绪 ===")
	print("[TEST] 发送测试消息...")
	
	# 发送测试消息
	main_agent.send_message("帮我查一下北京的天气，然后看看 res://prompts/ 目录下有哪些文件")


func _test_prompt_manager() -> void:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		print("[TEST] ERROR: PromptManager not found!")
		return
	
	# 测试基本解析
	var keys: Array[String] = pm.get_all_keys()
	print("[TEST] PromptManager loaded keys: %s" % str(keys))
	
	# 测试模板替换
	var resolved: String = pm.resolve("chat_demo")
	var has_common_rules: bool = resolved.find("通用规则") != -1
	var has_no_template: bool = resolved.find("{{") == -1
	print("[TEST] PromptManager resolve 'chat_demo': common_rules_injected=%s, no_unresolved_templates=%s" % [has_common_rules, has_no_template])
	
	# 测试环形引用检测
	pm.register_prompt("loop_a", "A references {{loop_b}}")
	pm.register_prompt("loop_b", "B references {{loop_a}}")
	var loop_result: String = pm.resolve("loop_a")
	print("[TEST] PromptManager circular reference test: result_length=%d (should contain unresolved ref)" % loop_result.length())


func _setup_main_agent() -> void:
	# 注册虚拟天气工具
	main_agent.register_tool(
		"get_weather",
		"查询指定城市的天气信息",
		{
			"type": "object",
			"properties": {
				"city": {
					"type": "string",
					"description": "城市名称"
				}
			},
			"required": ["city"]
		},
		Callable(self, "_tool_get_weather")
	)
	
	# 注册 file_agent 作为 sub-agent 工具
	main_agent.register_sub_agent_tool(
		"check_files",
		"委托文件查看助手查看指定目录的文件结构",
		file_agent
	)


func _setup_file_agent() -> void:
	# 注册真实的目录查看工具
	file_agent.register_tool(
		"list_directory",
		"列出指定目录下的文件和子目录",
		{
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "要查看的目录路径，如 res://prompts/"
				}
			},
			"required": ["path"]
		},
		Callable(self, "_tool_list_directory")
	)


## 虚拟天气工具
func _tool_get_weather(args: Dictionary) -> Dictionary:
	var city: String = args.get("city", "未知")
	print("[TEST] get_weather called: city=%s" % city)
	# 返回虚拟数据
	return {
		"success": true,
		"data": {
			"city": city,
			"temperature": "22°C",
			"weather": "晴",
			"humidity": "45%",
			"wind": "东北风 3级"
		}
	}


## 真实目录查看工具
func _tool_list_directory(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "res://")
	print("[TEST] list_directory called: path=%s" % path)
	
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return {"success": false, "error": "无法打开目录: " + path}
	
	var files: Array[String] = []
	var dirs: Array[String] = []
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			dirs.append(file_name + "/")
		else:
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	return {
		"success": true,
		"data": {
			"path": path,
			"directories": dirs,
			"files": files
		}
	}


func _on_main_log(entry: Dictionary) -> void:
	print("[MAIN] [%s] %s" % [entry.get("type", ""), entry.get("content", "").left(200)])


func _on_file_log(entry: Dictionary) -> void:
	print("[FILE] [%s] %s" % [entry.get("type", ""), entry.get("content", "").left(200)])


func _on_main_completed(_request_id: String, content: String) -> void:
	print("[TEST] === Main Agent 完成 ===")
	print("[TEST] 最终回复: %s" % content.left(500))
	print("[TEST] === 测试结束 ===")


func _on_main_failed(_request_id: String, error: String) -> void:
	print("[TEST] === Main Agent 失败 ===")
	print("[TEST] 错误: %s" % error)
