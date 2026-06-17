extends Node
## 调试测试：检查 WorkOrderAgent 的 API 配置

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("\n=== 调试：工单代理 API 配置检查 ===\n")

	# 检查 AIConfigManager 是否正确加载了角色映射
	var acm = AIConfigManager.get_instance()
	var roles_to_check: Array = ["work_order_agent", "work_order"]
	for r in roles_to_check:
		var config: Dictionary = acm.get_config_for_role(r)
		if config.is_empty():
			print("ROLE [%s]: ❌ 未找到配置" % r)
		else:
			print("ROLE [%s]: ✅ base_url=%s model=%s" % [r, config.get("base_url", ""), config.get("model", "")])

	print("\n--- 实例化 WorkOrderAgent ---")
	var AgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")
	var agent: ChatAgent = AgentScene.instantiate()
	agent.name = "DebugWorkOrderAgent"
	add_child(agent)

	# 等待一帧确保 _ready 已执行
	await get_tree().process_frame

	# 检查 controller 自身
	var agent_ai: AIService = agent.get_node_or_null("AIService")
	if agent_ai:
		print("WorkOrderAgent AIService: url=%s model=%s tools=%d" % [agent_ai.api_base_url, agent_ai.model, agent_ai.get_tools_definition().size()])
	else:
		print("WorkOrderAgent AIService: ❌ 未找到")

	print("\n=== 调试完成 ===")
	agent.queue_free()
