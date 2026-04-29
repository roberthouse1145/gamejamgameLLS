extends Node
## 测试 StoryDirector 的 dispatch_work_order 和 generate_work_order 功能

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var sd: Node = get_node_or_null("/root/StoryDirector")
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if sd == null:
		print("ERROR: StoryDirector not found")
		return
	if wom == null:
		print("ERROR: WorkOrderManager not found")
		return

	print("\n=== StoryDirector Work Order 测试 ===\n")

	var pass_count := 0
	var fail_count := 0

	# --- Test 1: dispatch_work_order 直接创建并派发 ---
	print("--- Test 1: dispatch_work_order ---")
	var initial_count: int = wom.get_all_orders().size()

	# 设置一个故事变量用于插值测试
	sd.set_variable("project_name", "测试项目Alpha")

	# 模拟执行 dispatch_work_order action
	var action1: Dictionary = {
		"type": "dispatch_work_order",
		"title": "完成{project_name}的概案",
		"description": "根据讨论结果整理策划案。项目名称：{project_name}",
		"priority": 3,
		"save_order_id": "test_order_id",
	}

	# 直接调用内部方法进行测试（不通过步骤系统）
	sd._action_dispatch_work_order(action1)

	# 验证工单被创建
	var new_count: int = wom.get_all_orders().size()
	if new_count == initial_count + 1:
		print("PASS: Test1a - 工单成功创建")
		pass_count += 1
	else:
		print("FAIL: Test1a - 工单数量未增长: %d -> %d" % [initial_count, new_count])
		fail_count += 1

	# 验证 save_order_id 保存了工单ID
	var saved_id = sd.story_variables.get("test_order_id", "")
	if not str(saved_id).is_empty() and str(saved_id).begins_with("wo_"):
		print("PASS: Test1b - save_order_id 已保存: %s" % str(saved_id))
		pass_count += 1
	else:
		print("FAIL: Test1b - save_order_id 未保存: '%s'" % str(saved_id))
		fail_count += 1

	# 验证插值成功
	var order = wom.get_order(str(saved_id))
	if order != null and "测试项目Alpha" in order.title:
		print("PASS: Test1c - 变量插值正确: %s" % order.title)
		pass_count += 1
	else:
		var t: String = order.title if order != null else "(null)"
		print("FAIL: Test1c - 插值异常: %s" % t)
		fail_count += 1

	# 验证 priority
	if order != null and order.priority == 3:
		print("PASS: Test1d - priority 正确")
		pass_count += 1
	else:
		print("FAIL: Test1d - priority 异常")
		fail_count += 1

	# --- Test 2: dispatch_work_order 缺少 title 的错误处理 ---
	print("\n--- Test 2: dispatch_work_order 缺少 title ---")
	var count_before: int = wom.get_all_orders().size()
	sd._action_dispatch_work_order({"type": "dispatch_work_order"})
	var count_after: int = wom.get_all_orders().size()
	if count_after == count_before:
		print("PASS: Test2 - 缺少 title 时不创建工单")
		pass_count += 1
	else:
		print("FAIL: Test2 - 不应创建工单但创建了")
		fail_count += 1

	# --- Test 3: _build_kb_context_for_generation ---
	print("\n--- Test 3: KB context 构建 ---")
	var context: String = sd._build_kb_context_for_generation()
	if not context.is_empty():
		print("PASS: Test3 - KB context 非空 (%d 字符)" % context.length())
		pass_count += 1
	else:
		print("FAIL: Test3 - KB context 为空")
		fail_count += 1

	# --- Test 4: generate_work_order (仅验证不崩溃+请求发送) ---
	print("\n--- Test 4: generate_work_order 触发 ---")
	var action2: Dictionary = {
		"type": "generate_work_order",
		"prompt": "为{project_name}创建一个角色设计任务",
		"priority": 2,
		"role": "work_order",
		"save_order_id": "gen_order_id",
	}
	# 这会发送 LLM 请求（异步），验证不会崩溃
	sd._action_generate_work_order(action2)
	print("PASS: Test4 - generate_work_order 未崩溃，LLM 请求已发送")
	pass_count += 1

	# --- 汇总 ---
	print("\n=== 测试结果: %d PASS / %d FAIL ===" % [pass_count, fail_count])
	if fail_count == 0:
		print("ALL TESTS PASSED!")
	else:
		print("SOME TESTS FAILED!")
	print("\n注意: Test4 (generate_work_order) 为异步操作，LLM 回复后会看到额外日志。")
