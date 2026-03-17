class_name ParallelExecutor extends RefCounted
## 并行执行器 — 每个并行模式节点拥有一个独立执行器
## 类似 RPG Maker 的并行处理：每帧 tick，顺序执行命令，
## 遇到等待则暂停该执行器（其他执行器继续），执行到末尾自动循环。
## IF 命令在执行器内同步处理（不走 async）。

## 执行器状态
enum State { RUNNING, WAIT_TIME, WAIT_CLICK, STOPPED }

## 命令列表
var commands: Array = []
## 当前指令指针
var index: int = 0
## 所属节点（AVGNode Resource）
var owner_node: Resource = null
## 当前状态
var state: State = State.RUNNING
## 等待计时器（WAIT_TIME 用）
var wait_timer: float = 0.0

## 阻塞命令 — 并行执行器中这些命令会暂停该执行器
const PARALLEL_BLOCKING: Array[String] = ["WAIT_TIME", "WAIT_CLICK"]

## 每帧最大执行命令数（防止死循环）
const MAX_COMMANDS_PER_TICK: int = 100


## 初始化
func setup(p_commands: Array, p_owner: Resource) -> void:
	commands = p_commands
	owner_node = p_owner
	index = 0
	state = State.RUNNING
	wait_timer = 0.0


## 每帧 tick — 由 SceneRunner._process() 调用
## 返回值: 本帧执行的命令数组（用于外部追踪，可忽略）
func tick(delta: float, runner: Node) -> void:
	if commands.is_empty() or state == State.STOPPED:
		return

	# 处理等待状态
	if state == State.WAIT_TIME:
		wait_timer -= delta
		if wait_timer <= 0.0:
			state = State.RUNNING
			index += 1
			if index >= commands.size():
				index = 0
		else:
			return

	if state == State.WAIT_CLICK:
		# WAIT_CLICK 在并行模式中跳过（没有意义），直接推进
		state = State.RUNNING
		index += 1
		if index >= commands.size():
			index = 0

	# 执行命令（一帧内可连续执行多条瞬时命令）
	var executed: int = 0
	while state == State.RUNNING and executed < MAX_COMMANDS_PER_TICK:
		if index >= commands.size():
			index = 0  # 循环回起点

		var cmd: Resource = commands[index]
		if cmd == null:
			index += 1
			executed += 1
			continue

		var cmd_type: String = cmd.command_type if "command_type" in cmd else ""

		# IF 命令 — 同步评估，插入分支命令
		if cmd_type == "IF":
			_handle_if_sync(cmd, runner)
			index += 1
			if index >= commands.size():
				index = 0
			executed += 1
			continue

		# LABEL — 跳过（标签只是标记）
		if cmd_type == "LABEL":
			index += 1
			executed += 1
			continue

		# JUMP_LABEL — 同步跳转
		if cmd_type == "JUMP_LABEL":
			var target: String = cmd.params.get("target", "") if cmd.params else ""
			if not target.is_empty():
				var label_idx: int = _find_label(target)
				if label_idx >= 0:
					index = label_idx + 1  # 跳到标签后一条
					executed += 1
					continue
			index += 1
			executed += 1
			continue

		# WAIT_TIME — 进入等待状态
		if cmd_type == "WAIT_TIME":
			var duration: float = cmd.params.get("duration", 1.0) if cmd.params else 1.0
			wait_timer = duration
			state = State.WAIT_TIME
			executed += 1
			break

		# WAIT_CLICK — 在并行模式中跳过
		if cmd_type == "WAIT_CLICK":
			state = State.WAIT_CLICK
			executed += 1
			break

		# DIALOGUE — 并行模式中不应该有对话，但如果有就跳过
		if cmd_type == "DIALOGUE" or cmd_type == "CHOICE":
			index += 1
			executed += 1
			continue

		# CHECK_HOVER / CHECK_CLICK — 条件命令，评估后决定是否跳过后续
		if cmd_type == "CHECK_HOVER" or cmd_type == "CHECK_CLICK":
			var result: bool = _eval_condition_cmd(cmd, runner)
			if not result:
				# 条件不满足 — 跳到本轮末尾，等下一帧重新从头开始
				index = 0
				break
			index += 1
			executed += 1
			continue

		# CHECK_VAR — 条件命令
		if cmd_type == "CHECK_VAR":
			var result: bool = _eval_check_var(cmd, runner)
			if not result:
				index = 0
				break
			index += 1
			executed += 1
			continue

		# 普通命令 — 通过 registry 执行（自动填充空 node_id 为自身）
		_resolve_self_node_id(cmd)
		_execute_via_runner(cmd, runner)
		index += 1
		executed += 1

		if index >= commands.size():
			index = 0
			break  # 一轮结束，等下一帧


## 停止执行器
func stop() -> void:
	state = State.STOPPED


## 重置执行器（重新开始）
func restart() -> void:
	index = 0
	state = State.RUNNING
	wait_timer = 0.0


# ============ 内部方法 ============

## 通过 SceneRunner 执行单条命令
func _execute_via_runner(cmd: Resource, runner: Node) -> void:
	if runner.has_method("_execute_single_command"):
		runner._execute_single_command(cmd)


## 同步处理 IF 命令（不 await，直接评估并插入分支命令）
func _handle_if_sync(cmd: Resource, runner: Node) -> void:
	if cmd == null or cmd.params == null:
		return

	var condition_commands: Array = cmd.params.get("condition_commands", [])
	var condition_met: bool = false

	if not condition_commands.is_empty():
		condition_met = _evaluate_condition_commands_sync(condition_commands, runner)
	else:
		var condition: String = cmd.params.get("condition", "")
		if not condition.is_empty() and runner.has_method("_evaluate_legacy_condition"):
			condition_met = runner._evaluate_legacy_condition(condition)

	var branch_commands: Array = []
	if condition_met:
		branch_commands = cmd.params.get("if_commands", [])
	else:
		var has_else: bool = cmd.params.get("has_else", false)
		if has_else:
			branch_commands = cmd.params.get("else_commands", [])

	if branch_commands.is_empty():
		return

	# 将分支命令插入到当前位置之后
	var insert_pos: int = index + 1
	for i in range(branch_commands.size()):
		commands.insert(insert_pos + i, branch_commands[i])


## 同步评估条件命令列表
func _evaluate_condition_commands_sync(cond_commands: Array, runner: Node) -> bool:
	for cmd in cond_commands:
		if cmd == null:
			continue
		var cmd_type: String = ""
		var params: Dictionary = {}
		if cmd is Resource and "command_type" in cmd:
			cmd_type = cmd.command_type
			params = cmd.params if cmd.params != null else {}
		elif cmd is Dictionary:
			cmd_type = cmd.get("command_type", "")
			params = cmd.get("params", {})
		else:
			continue

		match cmd_type:
			"CHECK_VAR":
				if not _eval_check_var_params(params, runner):
					return false
			"CHECK_HOVER":
				if not _eval_hover_params(params, runner):
					return false
			"CHECK_CLICK":
				if not _eval_click_params(params, runner):
					return false
			"IF":
				if not _eval_if_sync(params, runner):
					return false
			_:
				return false
	return true


## 评估 CHECK_VAR（使用 runner 的变量管理器）
func _eval_check_var(cmd: Resource, runner: Node) -> bool:
	var params: Dictionary = cmd.params if cmd.params != null else {}
	return _eval_check_var_params(params, runner)


func _eval_check_var_params(params: Dictionary, runner: Node) -> bool:
	if runner.has_method("_eval_check_var"):
		return runner._eval_check_var(params)
	return false


## 评估 CHECK_HOVER
func _eval_condition_cmd(cmd: Resource, runner: Node) -> bool:
	var params: Dictionary = cmd.params if cmd.params != null else {}
	var cmd_type: String = cmd.command_type if "command_type" in cmd else ""
	if cmd_type == "CHECK_HOVER":
		return _eval_hover_params(params, runner)
	elif cmd_type == "CHECK_CLICK":
		return _eval_click_params(params, runner)
	return false


func _eval_hover_params(params: Dictionary, runner: Node) -> bool:
	var node_id: String = params.get("node_id", "")
	if node_id.is_empty():
		# 默认检查自身节点
		if owner_node != null and "node_id" in owner_node:
			node_id = owner_node.node_id
	if node_id.is_empty():
		return false
	if runner.has_method("is_node_hovered"):
		return runner.is_node_hovered(node_id)
	return false


func _eval_click_params(params: Dictionary, runner: Node) -> bool:
	var node_id: String = params.get("node_id", "")
	if node_id.is_empty():
		if owner_node != null and "node_id" in owner_node:
			node_id = owner_node.node_id
	if node_id.is_empty():
		return false
	if runner.has_method("is_node_pressed"):
		return runner.is_node_pressed(node_id)
	return false


## 同步评估嵌套 IF
func _eval_if_sync(params: Dictionary, runner: Node) -> bool:
	var condition_commands: Array = params.get("condition_commands", [])
	if condition_commands.is_empty():
		return true
	var condition_met: bool = _evaluate_condition_commands_sync(condition_commands, runner)
	if condition_met:
		var if_cmds: Array = params.get("if_condition_commands", [])
		if if_cmds.is_empty():
			return true
		return _evaluate_condition_commands_sync(if_cmds, runner)
	else:
		var has_else: bool = params.get("has_else", false)
		if has_else:
			var else_cmds: Array = params.get("else_condition_commands", [])
			if else_cmds.is_empty():
				return true
			return _evaluate_condition_commands_sync(else_cmds, runner)
		return false


## 自动填充空 node_id 为自身节点 ID（并行/点击模式下 "自身" 语义）
## 只对含 node_id 参数的命令生效
func _resolve_self_node_id(cmd: Resource) -> void:
	if cmd == null or cmd.params == null:
		return
	if not cmd.params.has("node_id"):
		return
	if not cmd.params["node_id"].is_empty():
		return
	# 填充为 owner 的 node_id
	if owner_node != null and "node_id" in owner_node and not owner_node.node_id.is_empty():
		cmd.params["node_id"] = owner_node.node_id


## 查找标签在命令列表中的位置
func _find_label(label_name: String) -> int:
	for i in range(commands.size()):
		var cmd = commands[i]
		if cmd == null:
			continue
		if cmd.command_type == "LABEL":
			var name: String = cmd.params.get("name", "") if cmd.params else ""
			if name == label_name:
				return i
	return -1
