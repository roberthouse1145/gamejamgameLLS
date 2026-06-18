extends ChatAgent
## WorkOrder Agent
## 单体后台工单执行者：直接读上下文、写 KB/DSL/项目数据、验证并完成工单。

const MAIN_HISTORY_MESSAGES: int = 180
const MAIN_HISTORY_CHARS: int = 180000
const MAIN_HISTORY_PRESERVE: int = 32
const RESEARCH_HISTORY_MESSAGES: int = 60
const RESEARCH_HISTORY_CHARS: int = 60000
const RESEARCH_HISTORY_PRESERVE: int = 10
const GameEditorToolsClass = preload("res://scripts/avg/dev_tools/game_editor_tools.gd")


func _ready() -> void:
	_configure_history_budget(self, MAIN_HISTORY_MESSAGES, MAIN_HISTORY_CHARS, MAIN_HISTORY_PRESERVE)
	super._ready()
	_ai_service.max_tool_iterations = 80

	GameEditorToolsClass.register_work_order_tools(_ai_service)
	AVGDevWorkOrderTools.register_finish_tool(_ai_service)
	_register_research_tool()
	_mark_tool_effects(_ai_service)

	print("[WorkOrderAgent] Ready - tools: %d" % _ai_service.get_tools_definition().size())


func send_message_with_options(text: String, request_options: Dictionary = {}) -> String:
	var options: Dictionary = request_options.duplicate(true)
	options["tool_execution_policy"] = "read_parallel_write_serial"
	return super.send_message_with_options(text, options)


func _register_list_assets(ai_service: AIService) -> void:
	ai_service.register_tool("list_assets", "列出当前项目的可用资源文件与 alias（背景图、图片、CG、BGM、SFX、角色表情/服装）。写 DSL 前用于确认真实资源名，禁止编造。", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["all", "backgrounds", "images", "cg", "bgm", "sfx", "characters"], "description": "要查询的资源类别，默认 all"}
		},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._list_assets(args), {
		"fields": ["success", "data", "error"]
	}, {"effect": "read"})


func _register_research_tool() -> void:
	_ai_service.register_tool("research", "启动一个只读临时研究代理，处理复杂资料查询、上下文归纳和引用 ID 汇总。该代理不能写 KB、DSL 或项目数据。", {
		"type": "object",
		"properties": {
			"task": {"type": "string", "description": "需要归纳的只读查询任务；应说明要查哪些 doc_id、scene_id、资源或变量。"}
		},
		"required": ["task"]
	}, func(args: Dictionary) -> Dictionary: return await _run_research(args), {
		"fields": ["success", "data", "error"]
	}, {"effect": "read"})


func _run_research(args: Dictionary) -> Dictionary:
	var task: String = str(args.get("task", "")).strip_edges()
	if task.is_empty():
		return {"success": false, "error": "task is required"}

	var agent: ChatAgent = ChatAgent.new()
	agent.name = "ResearchAgent_%d_%d" % [Time.get_ticks_usec(), randi() % 10000]
	agent.role = "work_order_agent"
	agent.prompt_key = ""
	agent.strip_thinking_from_history = true
	agent.include_available_skills_metadata_in_prompt = false
	_configure_history_budget(agent, RESEARCH_HISTORY_MESSAGES, RESEARCH_HISTORY_CHARS, RESEARCH_HISTORY_PRESERVE)

	var ai_svc: AIService = AIService.new()
	ai_svc.name = "AIService"
	ai_svc.auto_execute_tools = true
	ai_svc.max_tool_iterations = 30
	agent.add_child(ai_svc)
	_register_research_tools(ai_svc)
	_mark_research_tool_effects(ai_svc)

	add_child(agent)
	await get_tree().process_frame
	agent.set_system_prompt_override(_build_research_system_prompt())

	var state: Dictionary = {"completed": false, "content": "", "failed": false, "error": ""}
	var on_completed: Callable = func(_req_id: String, content: String) -> void:
		state["content"] = content
		state["completed"] = true
	var on_failed: Callable = func(_req_id: String, error: String) -> void:
		state["failed"] = true
		state["error"] = error
		state["completed"] = true

	agent.message_completed.connect(on_completed, CONNECT_ONE_SHOT)
	agent.message_failed.connect(on_failed, CONNECT_ONE_SHOT)
	agent.log_entry.connect(func(entry: Dictionary) -> void:
		var prefixed: Dictionary = entry.duplicate()
		prefixed["content"] = "[Research] " + str(entry.get("content", ""))
		log_entry.emit(prefixed)
	)
	agent.tool_executed.connect(func(req: String, tool_name: String, tool_args: Dictionary, result: Variant, tool_call_id: String) -> void:
		tool_executed.emit(req, tool_name, tool_args, result, tool_call_id)
	)

	var index_block: String = AVGDevContextTools.build_work_order_project_index()
	var prompt: String = "%s\n\n---\n\n# 研究任务\n\n%s" % [index_block, task]
	var request_id: String = agent.send_message_with_options(prompt, {
		"tool_execution_policy": "read_parallel_write_serial",
		"prompt_key": "work_order_research",
		"source": "WorkOrderAgent",
	})
	if request_id.is_empty():
		agent.queue_free()
		return {"success": false, "error": "Research agent is busy"}

	while not bool(state.get("completed", false)):
		await get_tree().process_frame

	agent.queue_free()
	if bool(state.get("failed", false)):
		return {"success": false, "error": str(state.get("error", ""))}
	return {"success": true, "data": _extract_result_tag(str(state.get("content", "")))}


func _register_research_tools(ai_service: AIService) -> void:
	AVGDevKBTools.register_read_only(ai_service)
	AVGDevDBTools.register_read_only(ai_service)
	AVGDevScriptTools.register_read_only(ai_service)
	_register_list_assets(ai_service)
	_register_research_project_tools(ai_service)


func _register_research_project_tools(ai_service: AIService) -> void:
	ai_service.register_tool("project_info", "获取当前项目基础信息。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._project_info(args), {
		"fields": ["success", "data.project_name", "data.scene_count", "data.character_count", "data.variable_count", "data.event_count", "data.initial_scene_id", "error"]
	}, {"effect": "read"})

	ai_service.register_tool("list_scene_catalog", "列出场景目录摘要。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._list_scene_catalog(args), {
		"fields": ["success", "data", "entry_scene_id", "error"]
	}, {"effect": "read"})

	ai_service.register_tool("analyze_story_reachability", "分析当前 AVG 项目的伪运行可达性。", {
		"type": "object",
		"properties": {
			"max_total_states": {"type": "integer", "description": "可选。最多展开多少个场景状态，默认 256。"},
			"max_command_steps": {"type": "integer", "description": "可选。单路径最多遍历多少条命令，默认 512。"}
		},
	}, func(args: Dictionary) -> Variant: return AVGDevProjectTools._analyze_story_reachability(args), {
		"fields": ["success", "data.entry_scene_id", "data.scene_catalog", "data.unreachable_scenes", "data.warnings", "error"]
	}, {"effect": "read"})


func _build_research_system_prompt() -> String:
	return "\n".join([
		"你是 WorkOrderAgent 的只读研究助手。",
		"你只能查询和归纳事实，不能写 KB、DSL、项目数据，也不能完成工单。",
		"优先使用调用方给出的 doc_id、scene_id、变量 key、角色名和资源 alias 精确读取。",
		"输出必须简短，列出结论、引用到的 ID、仍缺失的信息。",
		"最终回答用 <result>...</result> 包裹。",
	])


func _mark_tool_effects(ai_service: AIService) -> void:
	var read_tools: Array[String] = [
		"kb_read", "get_project_context", "research",
	]
	var write_tools: Array[String] = [
		"kb_write", "upsert_scene", "edit_scenes", "upsert_character",
		"upsert_variable", "upsert_event", "import_project_asset",
	]
	for tool_name in read_tools:
		ai_service.set_tool_metadata(tool_name, {"effect": "read"})
	for tool_name in write_tools:
		ai_service.set_tool_metadata(tool_name, {"effect": "write"})
	ai_service.set_tool_metadata("wo_finish_order", {"effect": "terminal"})


func _mark_research_tool_effects(ai_service: AIService) -> void:
	for tool_name in [
		"kb_read", "db_list", "db_get", "get_story_outline", "get_scene_script",
		"project_info", "list_assets", "list_scene_catalog", "analyze_story_reachability",
	]:
		ai_service.set_tool_metadata(tool_name, {"effect": "read"})


func _configure_history_budget(agent: ChatAgent, max_messages: int, max_chars: int, preserve_recent: int) -> void:
	if agent == null:
		return
	agent.max_history_messages = max_messages
	agent.max_history_chars = max_chars
	agent.history_preserve_recent_messages = preserve_recent
