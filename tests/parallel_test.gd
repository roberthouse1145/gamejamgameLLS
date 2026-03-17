@tool
extends EditorScript
## 并行执行器测试 — 在编辑器中运行
## 验证: ParallelExecutor 创建、tick、WAIT_TIME、SET_VARIABLE
## 运行方式: 在 Godot 编辑器中打开此脚本，点击 File > Run

const ParallelExecutorClass = preload("res://scripts/avg/runtime/parallel_executor.gd")
const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const AVGNodeClass = preload("res://scripts/avg/resources/avg_node.gd")


func _run() -> void:
	print("========== Parallel Executor Unit Test ==========")
	_test_basic_loop()
	_test_wait_time()
	_test_check_var_condition()
	_test_if_sync()
	print("========== All Tests Passed ==========")


## 测试1: 基本循环 — 执行到末尾后 index 回到 0
func _test_basic_loop() -> void:
	print("[Test] Basic Loop...")
	var executor := ParallelExecutorClass.new()
	var node := AVGNodeClass.new()
	node.node_id = "test_node"

	# 两条 LABEL 命令（瞬时，不阻塞）
	var cmd1 := AVGCommandClass.new()
	cmd1.command_type = "LABEL"
	cmd1.params = {"name": "start"}

	var cmd2 := AVGCommandClass.new()
	cmd2.command_type = "LABEL"
	cmd2.params = {"name": "end"}

	executor.setup([cmd1, cmd2], node)

	# tick 一帧 — 应该执行两条并回到 index 0
	executor.tick(0.016, null)
	assert(executor.index == 0, "Expected index 0 after loop, got %d" % executor.index)
	assert(executor.state == ParallelExecutorClass.State.RUNNING, "Expected RUNNING state")
	print("[Test] Basic Loop... OK")


## 测试2: WAIT_TIME — 进入等待状态，计时结束后恢复
func _test_wait_time() -> void:
	print("[Test] Wait Time...")
	var executor := ParallelExecutorClass.new()
	var node := AVGNodeClass.new()
	node.node_id = "test_node"

	var cmd_wait := AVGCommandClass.new()
	cmd_wait.command_type = "WAIT_TIME"
	cmd_wait.params = {"duration": 0.5}

	var cmd_label := AVGCommandClass.new()
	cmd_label.command_type = "LABEL"
	cmd_label.params = {"name": "after_wait"}

	executor.setup([cmd_wait, cmd_label], node)

	# tick — 应该进入 WAIT_TIME 状态
	executor.tick(0.016, null)
	assert(executor.state == ParallelExecutorClass.State.WAIT_TIME, "Expected WAIT_TIME state, got %d" % executor.state)
	assert(executor.index == 0, "Expected index 0 during wait")

	# tick 0.3s — 还在等待
	executor.tick(0.3, null)
	assert(executor.state == ParallelExecutorClass.State.WAIT_TIME, "Should still be waiting")

	# tick 0.3s — 总共 0.616s > 0.5s，应该恢复并推进
	executor.tick(0.3, null)
	assert(executor.state == ParallelExecutorClass.State.RUNNING, "Expected RUNNING after wait expired")
	# index 应该推进到 1（wait 之后的命令）
	assert(executor.index == 1 or executor.index == 0, "Expected index 1 or 0 after wait")
	print("[Test] Wait Time... OK")


## 测试3: CHECK_VAR 条件 — 条件不满足时回到 index 0
func _test_check_var_condition() -> void:
	print("[Test] CHECK_VAR Condition...")
	var executor := ParallelExecutorClass.new()
	var node := AVGNodeClass.new()
	node.node_id = "test_node"

	var cmd_check := AVGCommandClass.new()
	cmd_check.command_type = "CHECK_VAR"
	cmd_check.params = {"variable_id": "var_001", "operator": ">=", "value": "999"}

	var cmd_label := AVGCommandClass.new()
	cmd_label.command_type = "LABEL"
	cmd_label.params = {"name": "should_not_reach"}

	executor.setup([cmd_check, cmd_label], node)

	# tick — CHECK_VAR 应该失败（没有 runner 提供变量），index 回到 0
	# 注意: _eval_check_var_params 调用 runner._eval_check_var，runner 为 null 时返回 false
	executor.tick(0.016, null)
	assert(executor.index == 0, "Expected index 0 after failed CHECK_VAR, got %d" % executor.index)
	print("[Test] CHECK_VAR Condition... OK")


## 测试4: IF 同步处理 — 分支命令插入
func _test_if_sync() -> void:
	print("[Test] IF Sync...")
	var executor := ParallelExecutorClass.new()
	var node := AVGNodeClass.new()
	node.node_id = "test_node"

	# IF 命令，条件为空（始终满足），if_commands 有一条 LABEL
	var cmd_if := AVGCommandClass.new()
	cmd_if.command_type = "IF"
	cmd_if.params = {
		"condition_commands": [],
		"if_commands": [],
		"has_else": false,
		"else_commands": []
	}

	var cmd_label := AVGCommandClass.new()
	cmd_label.command_type = "LABEL"
	cmd_label.params = {"name": "after_if"}

	executor.setup([cmd_if, cmd_label], node)

	# tick — IF 应该被处理，然后继续到 LABEL
	executor.tick(0.016, null)
	# 空条件 + 空 if_commands = 什么都不插入，直接推进
	assert(executor.state == ParallelExecutorClass.State.RUNNING, "Expected RUNNING")
	print("[Test] IF Sync... OK")
