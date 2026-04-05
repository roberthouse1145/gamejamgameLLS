extends ChatAgent
## WorkOrder Controller Agent
## 后台工单执行的控制器。自身为高端模型，负责规划和分派。
## 持有三个 sub-agent: planner（策划文案）、writer（场景脚本）、executor（操作），使用低端高速模型。

var _planner_agent: ChatAgent
var _writer_agent: ChatAgent
var _executor_agent: ChatAgent


func _ready() -> void:
	super._ready()
	_setup_planner_agent()
	_setup_writer_agent()
	_setup_executor_agent()
	# Controller 自身只需要只读工具 + 工单管理工具 + 资产查询
	AVGDevDBTools.register_read_only(_ai_service)
	AVGDevProjectTools.register_preview_and_finish(_ai_service)
	AVGDevWorkOrderTools.register_controller_tools(_ai_service)
	AVGDevKBTools.register_read_only(_ai_service)
	_register_list_assets(_ai_service)
	print("[WorkOrderController] Ready - tools: %d" % _ai_service.get_tools_definition().size())


func _setup_planner_agent() -> void:
	_planner_agent = ChatAgent.new()
	_planner_agent.name = "PlannerAgent"
	_planner_agent.role = "work_order_planner"
	_planner_agent.prompt_key = "work_order_planner"
	_planner_agent.strip_thinking_from_history = true

	var ai_svc: AIService = AIService.new()
	ai_svc.name = "AIService"
	ai_svc.auto_execute_tools = true
	ai_svc.max_tool_iterations = 15
	ai_svc.default_max_tokens = 8192
	_planner_agent.add_child(ai_svc)
	add_child(_planner_agent)

	# Planner 持有 KB 全部工具 + 资产查询
	AVGDevKBTools.register_all(ai_svc)
	_register_list_assets(ai_svc)

	# 注册写作 Skills（Planner 可自选或由 Controller 预激活）
	_register_planner_skills()

	# 注册 planner 子代理工具（带 skill 预激活支持）
	_register_planner_tool()

	_planner_agent.log_entry.connect(func(entry: Dictionary):
		var prefixed: Dictionary = entry.duplicate()
		prefixed["content"] = "[Planner] " + entry.get("content", "")
		log_entry.emit(prefixed))
	_planner_agent.tool_executed.connect(func(req: String, tool_name: String, args: Dictionary, res: Variant, _tcid: String):
		tool_executed.emit(req, tool_name, args, res, _tcid))


func _setup_writer_agent() -> void:
	_writer_agent = ChatAgent.new()
	_writer_agent.name = "WriterAgent"
	_writer_agent.role = "work_order_writer"
	_writer_agent.prompt_key = "work_order_writer"
	_writer_agent.strip_thinking_from_history = true

	var ai_svc: AIService = AIService.new()
	ai_svc.name = "AIService"
	ai_svc.auto_execute_tools = true
	ai_svc.max_tool_iterations = 20
	ai_svc.default_max_tokens = 8192
	_writer_agent.add_child(ai_svc)
	add_child(_writer_agent)

	# Writer 持有 DB + 脚本 + 保存 + KB只读
	AVGDevDBTools.register_all(ai_svc)
	AVGDevScriptTools.register_all(ai_svc)
	AVGDevProjectTools.register_save_only(ai_svc)
	AVGDevKBTools.register_read_only(ai_svc)

	register_sub_agent_tool(
		"writer",
		"委托场景脚本任务给 Writer 子代理。用于创建 AVG 场景、编写 DSL 脚本、创建角色/变量数据。Writer 可读取 KB 获取剧情上下文，但不修改 KB。",
		_writer_agent
	)

	_writer_agent.log_entry.connect(func(entry: Dictionary):
		# 给 Writer 日志加前缀后转发
		var prefixed: Dictionary = entry.duplicate()
		prefixed["content"] = "[Writer] " + entry.get("content", "")
		log_entry.emit(prefixed))
	_writer_agent.tool_executed.connect(func(req: String, tool_name: String, args: Dictionary, res: Variant, _tcid: String):
		tool_executed.emit(req, tool_name, args, res, _tcid))


func _setup_executor_agent() -> void:
	_executor_agent = ChatAgent.new()
	_executor_agent.name = "ExecutorAgent"
	_executor_agent.role = "work_order_executor"
	_executor_agent.prompt_key = "work_order_executor"
	_executor_agent.strip_thinking_from_history = true

	var ai_svc: AIService = AIService.new()
	ai_svc.name = "AIService"
	ai_svc.auto_execute_tools = true
	ai_svc.max_tool_iterations = 10
	_executor_agent.add_child(ai_svc)
	add_child(_executor_agent)

	# Executor 持有 DB 工具 + 保存
	AVGDevDBTools.register_all(ai_svc)
	AVGDevProjectTools.register_save_only(ai_svc)

	register_sub_agent_tool(
		"executor",
		"委托数据操作任务给 Executor 子代理。用于重命名、删除、修改字段值、批量操作等机械性工作。不用于创意写作。",
		_executor_agent
	)

	_executor_agent.log_entry.connect(func(entry: Dictionary):
		var prefixed: Dictionary = entry.duplicate()
		prefixed["content"] = "[Executor] " + entry.get("content", "")
		log_entry.emit(prefixed))
	_executor_agent.tool_executed.connect(func(req: String, tool_name: String, args: Dictionary, res: Variant, _tcid: String):
		tool_executed.emit(req, tool_name, args, res, _tcid))


## 为 Controller 注册 list_assets 工具（从 ProjectTools 借用实现）
func _register_list_assets(ai_service: AIService) -> void:
	# list_assets 在 register_save_only 中定义，但 Controller 不需要 save 权限
	# 这里单独注册 list_assets
	ai_service.register_tool("list_assets", "列出当前项目的可用资源文件与 alias（背景图、图片、CG、BGM、SFX、角色表情/服装）。委托 Writer 前应先调用此工具获取资源清单。", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["all", "backgrounds", "images", "cg", "bgm", "sfx", "characters"], "description": "要查询的资源类别，默认 all"}
		},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._list_assets(args))


## 注册 Planner 的写作 Skills（从 prompt 文件加载指令）
func _register_planner_skills() -> void:
	var skill_defs: Array[Dictionary] = [
		{
			"name": "character_writing",
			"description": "角色设定写作规范 — 产出对话生成参考卡式的角色设定",
			"prompt_key": "skill_character_writing",
			"keywords": ["角色", "人设", "character"],
		},
		{
			"name": "story_writing",
			"description": "故事剧本写作规范 — 产出内联舞台指示格式的场景节拍",
			"prompt_key": "skill_story_writing",
			"keywords": ["剧本", "故事", "节拍", "story", "scene"],
		},
		{
			"name": "world_building",
			"description": "世界观设定写作规范 — 产出创作约束清单式的世界观文档",
			"prompt_key": "skill_world_building",
			"keywords": ["世界观", "设定", "world"],
		},
	]
	for def in skill_defs:
		var instructions: String = PromptManager.resolve(def["prompt_key"])
		if instructions.is_empty():
			push_warning("[WorkOrderController] Skill prompt not found: %s" % def["prompt_key"])
			continue
		_planner_agent.register_skill(def["name"], def["description"], instructions, def["keywords"])

	# 同时给 Planner 注册 activate/deactivate 工具，保留自主选择能力
	var planner_svc: AIService = _planner_agent.get_node("AIService")
	planner_svc.register_tool("activate_skill", "激活一个写作 skill，注入对应的写作规范到上下文中", {
		"type": "object",
		"properties": {"skill_name": {"type": "string", "description": "要激活的 skill 名称"}},
		"required": ["skill_name"],
	}, func(args: Dictionary) -> Variant: return _planner_agent.activate_skill(args.get("skill_name", "")))

	planner_svc.register_tool("deactivate_skill", "停用当前激活的写作 skill", {
		"type": "object",
		"properties": {"skill_name": {"type": "string", "description": "要停用的 skill 名称"}},
		"required": ["skill_name"],
	}, func(args: Dictionary) -> Variant: return _planner_agent.deactivate_skill(args.get("skill_name", "")))


## 注册 planner 子代理工具（带 skill 预激活支持）
func _register_planner_tool() -> void:
	var planner_desc: String = "委托策划文案任务给 Planner 子代理。用于创建/修改角色设定、世界观、剧情大纲、故事节拍等知识库内容。不用于编写 DSL 脚本。可通过 skill 参数预激活写作规范：character_writing / story_writing / world_building。"
	var schema: Dictionary = {
		"type": "object",
		"properties": {
			"task": {
				"type": "string",
				"description": "要委托给子代理执行的任务描述",
			},
			"skill": {
				"type": "string",
				"description": "预激活的写作 skill 名称（可选）。character_writing=角色设定, story_writing=故事剧本, world_building=世界观设定",
				"enum": ["character_writing", "story_writing", "world_building"],
			},
		},
		"required": ["task"],
	}

	# 手动注册 sub-agent 映射（与 register_sub_agent_tool 等效）
	_sub_agents["planner"] = {
		"agent": _planner_agent,
		"description": planner_desc,
	}

	_ai_service.register_tool("planner", planner_desc, schema,
		func(args: Dictionary) -> Dictionary:
			# 预激活 skill（如果指定了）
			var skill_name: String = args.get("skill", "")
			if not skill_name.is_empty():
				_planner_agent.activate_skill(skill_name)
			return await _execute_sub_agent("planner", args)
	)
