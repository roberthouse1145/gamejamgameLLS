extends Node
## 调试测试：检查 WorkOrderController 子代理的 API 配置

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("\n=== 调试：工单代理 API 配置检查 ===\n")

	# 检查 AIConfigManager 是否正确加载了角色映射
	var acm = AIConfigManager.get_instance()
	var roles_to_check: Array = ["work_order_controller", "work_order_planner", "work_order_writer", "work_order_executor", "work_order"]
	for r in roles_to_check:
		var config: Dictionary = acm.get_config_for_role(r)
		if config.is_empty():
			print("ROLE [%s]: ❌ 未找到配置" % r)
		else:
			print("ROLE [%s]: ✅ base_url=%s model=%s" % [r, config.get("base_url", ""), config.get("model", "")])

	# 实例化 WorkOrderController 检查子代理的实际 AIService 配置
	print("\n--- 实例化 WorkOrderController ---")
	var ControllerScene = preload("res://scenes/avg/dev_tools/work_order_controller_agent.tscn")
	var controller: ChatAgent = ControllerScene.instantiate()
	controller.name = "DebugController"
	add_child(controller)

	# 等待一帧确保 _ready 已执行
	await get_tree().process_frame

	# 检查 controller 自身
	var ctrl_ai: AIService = controller.get_node_or_null("AIService")
	if ctrl_ai:
		print("Controller AIService: url=%s model=%s" % [ctrl_ai.api_base_url, ctrl_ai.model])
	else:
		print("Controller AIService: ❌ 未找到")

	# 检查 planner sub-agent
	var planner: Node = controller.get_node_or_null("PlannerAgent")
	if planner:
		var planner_ai: AIService = planner.get_node_or_null("AIService")
		if planner_ai:
			print("Planner AIService:    url=%s model=%s" % [planner_ai.api_base_url, planner_ai.model])
		else:
			print("Planner AIService: ❌ 未找到")
	else:
		print("PlannerAgent: ❌ 未找到")

	# 检查 writer sub-agent
	var writer: Node = controller.get_node_or_null("WriterAgent")
	if writer:
		var writer_ai: AIService = writer.get_node_or_null("AIService")
		if writer_ai:
			print("Writer AIService:     url=%s model=%s" % [writer_ai.api_base_url, writer_ai.model])
		else:
			print("Writer AIService: ❌ 未找到")
	else:
		print("WriterAgent: ❌ 未找到")

	# 检查 executor sub-agent
	var executor: Node = controller.get_node_or_null("ExecutorAgent")
	if executor:
		var exec_ai: AIService = executor.get_node_or_null("AIService")
		if exec_ai:
			print("Executor AIService:   url=%s model=%s" % [exec_ai.api_base_url, exec_ai.model])
		else:
			print("Executor AIService: ❌ 未找到")
	else:
		print("ExecutorAgent: ❌ 未找到")

	print("\n=== 调试完成 ===")
	controller.queue_free()
