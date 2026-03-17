extends ChatAgent
## AVG Dev Main Agent
## The player-facing conversational agent that coordinates AVG development.
## Has two sub-agents: writer (creative) and executor (mechanical).

var _writer_agent: ChatAgent
var _executor_agent: ChatAgent


func _ready() -> void:
	super._ready()
	_setup_writer_agent()
	_setup_executor_agent()
	# Main agent also gets preview_scene (it controls the preview flow)
	AVGDevProjectTools.register_preview_and_finish(_ai_service)
	# 主 Agent 还需要只读的诊断能力，用来满足用户直接的信息查阅请求
	AVGDevDBTools.register_read_only(_ai_service)
	AVGDevScriptTools.register_read_only(_ai_service)
	print("[AVGDevAgent] Ready - main tools: %d" % _ai_service.get_tools_definition().size())


func _setup_writer_agent() -> void:
	_writer_agent = ChatAgent.new()
	_writer_agent.name = "WriterAgent"
	_writer_agent.role = "avg_dev_writer"
	_writer_agent.prompt_key = "avg_dev_writer"
	_writer_agent.strip_thinking_from_history = true

	var ai_svc: AIService = AIService.new()
	ai_svc.name = "AIService"
	ai_svc.auto_execute_tools = true
	ai_svc.max_tool_iterations = 20
	ai_svc.default_max_tokens = 16384
	_writer_agent.add_child(ai_svc)
	add_child(_writer_agent)

	# Writer gets all read + write tools
	AVGDevDBTools.register_all(ai_svc)
	AVGDevScriptTools.register_all(ai_svc)
	AVGDevProjectTools.register_save_only(ai_svc)

	# Register writer as sub-agent tool on main agent
	register_sub_agent_tool(
		"writer",
		"Delegate a creative writing task to the writer sub-agent. Use for creating new scenes, writing dialogue, designing story branches. The writer will autonomously explore existing content, create resources, and write DSL scripts.",
		_writer_agent
	)

	# 转发子代理的日志和工具调用给主 Agent，方便 UI 展示
	_writer_agent.log_entry.connect(func(entry: Dictionary): log_entry.emit(entry))
	_writer_agent.tool_executed.connect(func(req: String, tool: String, args: Dictionary, res: Variant): tool_executed.emit(req, tool , args, res))


func _setup_executor_agent() -> void:
	_executor_agent = ChatAgent.new()
	_executor_agent.name = "ExecutorAgent"
	_executor_agent.role = "avg_dev_executor"
	_executor_agent.prompt_key = "avg_dev_executor"
	_executor_agent.strip_thinking_from_history = true

	var ai_svc: AIService = AIService.new()
	ai_svc.name = "AIService"
	ai_svc.auto_execute_tools = true
	ai_svc.max_tool_iterations = 10
	_executor_agent.add_child(ai_svc)
	add_child(_executor_agent)

	# Executor gets db tools + project_save
	AVGDevDBTools.register_all(ai_svc)
	AVGDevProjectTools.register_save_only(ai_svc)

	# Register executor as sub-agent tool on main agent
	register_sub_agent_tool(
		"executor",
		"Delegate a mechanical data operation to the executor sub-agent. Use for renaming, deleting, updating fields, bulk modifications. NOT for creative writing.",
		_executor_agent
	)

	# 转发子代理的日志和工具调用给主 Agent，方便 UI 展示
	_executor_agent.log_entry.connect(func(entry: Dictionary): log_entry.emit(entry))
	_executor_agent.tool_executed.connect(func(req: String, tool: String, args: Dictionary, res: Variant): tool_executed.emit(req, tool , args, res))
