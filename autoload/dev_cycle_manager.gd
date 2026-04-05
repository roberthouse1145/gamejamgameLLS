extends Node
## DevCycleManager Autoload
## 管理开发循环：任务池 → 玩家激活 → 立即完成 → 静默派发工单 → 解锁新任务
##
## 核心设计:
##   表层(DevWork任务) 和 底层(WorkOrder工单) 完全解耦。
##   - DevWork 任务在玩家完成交互后立即标记为 completed（项目对玩家是黑箱）
##   - WorkOrder 工单在后台静默执行（1~10分钟），完成时不通知玩家
##   - 玩家通过里程碑 Demo/Preview 才能看到实际成果
##
## 任务进化:
##   概念期使用固定任务（角色设计、故事大纲），
##   概念期完成后由 LLM 根据 KB 中的讨论成果动态生成开发计划。
##
## 任务类型:
##   - work_order: 有 work_order_template → 立即完成 + 静默派发隐藏工单
##   - chat_topic: 有 topic_config → 委托 MinigameManager 处理讨论
##   - minigame: 有 minigame_type → 委托 MinigameManager 处理小游戏
##   - simple: 无上述字段 → 仅结算数值，直接完成

const CHAPTER_PLANS_PATH: String = "res://resources/data/chapter_plans.json"
const MAX_VISIBLE_TASKS: int = 4
## 概念期的固定任务 ID
const CONCEPT_TASK_IDS: Array[String] = ["design_protagonist", "design_heroine", "plan_story_outline"]
const CREATIVE_SEED_ORDER_TITLE: String = "整理创作基点"
const CREATIVE_SEED_SOURCE_TYPE: String = "creative_seed_setup"
const CREATIVE_SEED_SOURCE_ID: String = "creative_brief"
const CREATIVE_CORE_DOC_ID: String = "creative_core"
const OPEN_DESIGN_QUESTIONS_DOC_ID: String = "open_design_questions"
const DEFAULT_CHAT_STRESS_LOAD: int = 4
const DEFAULT_CHAT_PASSION_COST: int = 4
const DEFAULT_DEV_STRESS_LOAD: int = 6
const DEFAULT_DEV_PASSION_COST: int = 6
#endregion

#region 信号
## 任务池更新，DevWorkApp 应刷新 UI
signal tasks_updated()
## 任务状态变化
signal task_status_changed(task_id: String, new_status: String)
## 开发计划生成完成
signal plan_generated(success: bool)
#endregion

#region 状态
## task_id → task Dictionary (包含 status 字段)
var _task_pool: Dictionary = {}
## 工单排队 (task_id FIFO)
var _order_queue: Array[String] = []
## 当前正在执行工单的任务 ID
var _active_task_id: String = ""
## 当前工单的 WorkOrderManager order ID
var _active_order_id: String = ""
## 历史已完成任务 ID
var _completed_task_ids: Array[String] = []
## 章节计划原始数据
var _chapter_plans: Array = []
## 是否已生成开发计划（防止重复生成）
var _plan_generated: bool = false
## 计划生成中
var _plan_generating: bool = false
## 计划生成请求 ID
var _plan_gen_request_id: String = ""
## 当前概念期的闸门任务（完成后才进入完整开发计划）
var _concept_gate_task_ids: Array[String] = CONCEPT_TASK_IDS.duplicate()
## 被创作基点流程替换掉的默认任务 ID
var _suppressed_task_ids: Array[String] = []
## 最近一次提交的创作基点原始数据
var _latest_creative_brief: Dictionary = {}
## 创作基点整理工单 ID（等待后台整理完成）
var _creative_seed_setup_order_id: String = ""
## 第一批 dev work 生成中
var _seed_task_generating: bool = false
## 第一批 dev work 请求 ID
var _seed_task_gen_request_id: String = ""
#endregion


func _ready() -> void:
	_load_chapter_plans()
	_seed_initial_tasks()
	_connect_signals()
	_connect_auto_order_signals()
	print("[DevCycleManager] Initialized. %d tasks in pool, %d chapters loaded." % [_task_pool.size(), _chapter_plans.size()])


func _connect_signals() -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom != null:
		if wom.has_signal("order_status_changed"):
			wom.order_status_changed.connect(_on_order_status_changed)
		if wom.has_signal("creative_task_requested"):
			wom.creative_task_requested.connect(_on_creative_task_requested)

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		if glm.has_signal("phase_changed"):
			glm.phase_changed.connect(_on_phase_changed)
		if glm.has_signal("day_changed"):
			glm.day_changed.connect(_on_day_changed)

	var mgr: Node = get_node_or_null("/root/MinigameManager")
	if mgr != null and mgr.has_signal("review_completed"):
		mgr.review_completed.connect(_on_minigame_review_completed)

	var planning: Node = get_node_or_null("/root/PlanningManager")
	if planning != null:
		if planning.has_signal("seed_task_plan_completed"):
			planning.seed_task_plan_completed.connect(_on_seed_task_plan_completed)
		if planning.has_signal("development_plan_completed"):
			planning.development_plan_completed.connect(_on_development_plan_completed)


func reset_runtime_state() -> void:
	_cleanup_plan_gen_ai()
	_cleanup_seed_task_gen_ai()
	_task_pool.clear()
	_order_queue.clear()
	_active_task_id = ""
	_active_order_id = ""
	_completed_task_ids.clear()
	_chapter_plans.clear()
	_plan_generated = false
	_plan_generating = false
	_concept_gate_task_ids = CONCEPT_TASK_IDS.duplicate()
	_suppressed_task_ids.clear()
	_latest_creative_brief.clear()
	_creative_seed_setup_order_id = ""
	_triggered_auto_orders.clear()
	var planning: Node = get_node_or_null("/root/PlanningManager")
	if planning != null and planning.has_method("reset_runtime_state"):
		planning.reset_runtime_state()
	_load_chapter_plans()
	_seed_initial_tasks()
	tasks_updated.emit()


#region ──── Public API ────

## 获取当前可见的任务列表（供 DevWorkApp 渲染）
## 返回最多 MAX_VISIBLE_TASKS 个任务，按优先级排序
## 包含状态: available / queued / active
func get_visible_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task_id in _task_pool:
		var task: Dictionary = _task_pool[task_id]
		var status: String = str(task.get("status", ""))
		if status in ["available", "queued", "active"]:
			result.append(task)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# active > queued > available; 同级按 weight 降序
		var rank_map: Dictionary = {"active": 2, "queued": 1, "available": 0}
		var ra: int = rank_map.get(str(a.get("status", "")), 0)
		var rb: int = rank_map.get(str(b.get("status", "")), 0)
		if ra != rb:
			return ra > rb
		return int(a.get("weight", 5)) > int(b.get("weight", 5))
	)
	return result.slice(0, MAX_VISIBLE_TASKS)


## 获取指定任务
func get_task(task_id: String) -> Dictionary:
	return _task_pool.get(task_id, {})


## 激活任务。根据任务类型自动路由到不同处理器。
## 返回是否成功启动。
func activate_task(task_id: String) -> bool:
	var task: Dictionary = _task_pool.get(task_id, {})
	if task.is_empty():
		push_warning("[DevCycleManager] Task not found: %s" % task_id)
		return false

	if str(task.get("status", "")) != "available":
		push_warning("[DevCycleManager] Task not available: %s (status: %s)" % [task_id, str(task.get("status", ""))])
		return false

	# 检查前置条件
	var prereqs: Array = task.get("prerequisites", [])
	for prereq_id in prereqs:
		if str(prereq_id) not in _completed_task_ids:
			push_warning("[DevCycleManager] Prerequisite not met: %s requires %s" % [task_id, str(prereq_id)])
			return false

	# 根据任务类型路由
	var task_type: String = str(task.get("task_type", ""))

	if task_type == "chat_topic":
		return _activate_chat_topic_task(task)

	var minigame_type: String = str(task.get("minigame_type", ""))
	if not minigame_type.is_empty():
		return _activate_minigame_task(task)

	if task.has("work_order_template"):
		return _activate_work_order_task(task)

	return _activate_simple_task(task)


## 是否有工单正在执行
func is_order_active() -> bool:
	return not _active_task_id.is_empty()


## 获取队列长度
func get_queue_size() -> int:
	return _order_queue.size()


## 获取已完成任务数
func get_completed_count() -> int:
	return _completed_task_ids.size()


## 企划书提交后的桥接入口：
## 保存原始创作基点 → 派发隐藏工单整理成 KB → 再生成第一批 dev work
## [param brief_data] 企划书数据字典，包含 game_title / game_genre / game_tags / game_outline
func on_creative_brief_completed(brief_data: Dictionary) -> void:
	_latest_creative_brief = brief_data.duplicate(true)

	if _creative_seed_setup_order_id != "" or _seed_task_generating:
		print("[DevCycleManager] Creative seed pipeline already running, skipping duplicate brief bridge")
		return

	if _plan_generated or _plan_generating:
		print("[DevCycleManager] Plan already generated/generating, skipping brief bridge")
		return

	_replace_default_concept_tasks_with_seed_flow()
	_concept_gate_task_ids.clear()

	var order_id := _dispatch_creative_seed_setup_order(brief_data)
	if order_id.is_empty():
		push_warning("[DevCycleManager] Failed to dispatch creative seed setup order, falling back to direct seed task generation")
		_generate_seed_tasks_from_context()
		return

	_creative_seed_setup_order_id = order_id
	print("[DevCycleManager] Creative brief completed, dispatched seed setup order: %s" % order_id)
	tasks_updated.emit()


func _replace_default_concept_tasks_with_seed_flow() -> void:
	for task_id in CONCEPT_TASK_IDS:
		if task_id not in _suppressed_task_ids:
			_suppressed_task_ids.append(task_id)
		if _task_pool.has(task_id):
			var status: String = str(_task_pool[task_id].get("status", ""))
			if status in ["active", "queued"]:
				push_warning("[DevCycleManager] Default concept task is already busy, cannot remove cleanly: %s" % task_id)
				continue
			_task_pool.erase(task_id)


func _dispatch_creative_seed_setup_order(brief_data: Dictionary) -> String:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[DevCycleManager] WorkOrderManager unavailable for creative seed setup")
		return ""

	var order_desc := _build_creative_seed_order_description(brief_data)
	var order: Resource = wom.create_order(CREATIVE_SEED_ORDER_TITLE, order_desc, {
		"source_type": CREATIVE_SEED_SOURCE_TYPE,
		"source_id": CREATIVE_SEED_SOURCE_ID,
	})
	if order == null:
		return ""

	order.assignee_npc_id = "npc_lin_xia"
	order.priority = 3

	if not wom.dispatch_order(order.id):
		return ""
	return order.id


func _build_creative_seed_order_description(brief_data: Dictionary) -> String:
	var title: String = str(brief_data.get("game_title", "")).strip_edges()
	var genre: String = str(brief_data.get("game_genre", "")).strip_edges()
	var tags: String = str(brief_data.get("game_tags", "")).strip_edges()
	var outline: String = str(brief_data.get("game_outline", "")).strip_edges()
	var lines: PackedStringArray = []
	lines.append("## 背景")
	lines.append("玩家刚刚提交了一份作品基点卡。这份内容只是创作起点，不是完整企划书。")
	lines.append("你需要先把它整理成系统可读的知识库文档，再交给后续的开发循环使用。")
	lines.append("")
	lines.append("## 玩家原始基点")
	lines.append("- 固定背景：日式魔法异世界学院")
	lines.append("- 作品名称：%s" % title)
	lines.append("- 作品类型：%s" % genre)
	lines.append("- 基调标签：%s" % tags)
	if not outline.is_empty():
		lines.append("- 页面大纲：%s" % outline)
	lines.append("")
	lines.append("## 你的交付物")
	lines.append("1. 在 KnowledgeBase 中创建或更新 doc_id=`%s` 的世界观文档，标题使用“创作基点”。" % CREATIVE_CORE_DOC_ID)
	lines.append("   只整理已经明确的方向：固定背景、作品倾向、基调、故事钩子、规模约束、页面里已经写出的剧情雏形。")
	lines.append("2. 在 KnowledgeBase 中创建或更新 doc_id=`%s` 的 notes 文档，标题使用“待讨论设计问题”。" % OPEN_DESIGN_QUESTIONS_DOC_ID)
	lines.append("   列出 3-5 个最适合玩家继续参与讨论的关键问题。")
	lines.append("3. 这份“待讨论设计问题”里必须包含以下三个方向：")
	lines.append("   - 女主角给人的第一印象与关系张力")
	lines.append("   - 主角在学院里的位置、立场或处境")
	lines.append("   - 第一章开场事件应该怎样切入")
	lines.append("")
	lines.append("## 约束")
	lines.append("- 不要直接生成完整开发计划。")
	lines.append("- 不要创建 AVG 场景脚本，不要动 Writer。")
	lines.append("- 不要把尚未讨论的角色设定、剧情走向写成既定事实。")
	lines.append("- 如果页面大纲很模糊，可以整理成“暂定方向”，但不要补成完整企划。")
	lines.append("- 这是一张“基点整理工单”，目标是让系统后续能继续长出 dev work。")
	return "\n".join(lines)

#endregion


#region ──── 任务激活路由 ────

## chat_topic 类型：委托 MinigameManager 处理讨论
func _activate_chat_topic_task(task: Dictionary) -> bool:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.can_consume_ap(1):
		return false

	var mgr: Node = get_node_or_null("/root/MinigameManager")
	if mgr == null or not mgr.has_method("start_chat_task"):
		push_warning("[DevCycleManager] MinigameManager not available for chat task")
		return false

	# MinigameManager 会处理讨论 + 自动派发 KB 工单
	if mgr.start_chat_task(task):
		var task_id: String = str(task.get("task_id", ""))
		task["status"] = "active"
		task_status_changed.emit(task_id, "active")
		tasks_updated.emit()
		return true
	return false


## minigame 类型：委托 MinigameManager 启动小游戏
func _activate_minigame_task(task: Dictionary) -> bool:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.can_consume_ap(1):
		return false

	var mgr: Node = get_node_or_null("/root/MinigameManager")
	if mgr == null:
		push_warning("[DevCycleManager] MinigameManager not available")
		return false

	var minigame_type: String = str(task.get("minigame_type", ""))
	if not mgr.has_minigame(minigame_type):
		# 无对应小游戏 → 降级为 work_order 或 simple
		if task.has("work_order_template"):
			return _activate_work_order_task(task)
		return _activate_simple_task(task)

	if mgr.start_minigame(task):
		var task_id: String = str(task.get("task_id", ""))
		task["status"] = "active"
		task_status_changed.emit(task_id, "active")
		tasks_updated.emit()
		return true
	return false


## work_order 类型：消耗 AP + 数值结算 → 立即完成 + 静默派发/排队隐藏工单
func _activate_work_order_task(task: Dictionary) -> bool:
	var task_id: String = str(task.get("task_id", ""))

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.consume_ap(1, "dev_cycle", task_id):
		return false

	# 立即结算数值
	_settle_task_stats(task)

	# 任务从玩家视角立即 completed（项目是黑箱，玩家无法验证）
	task["status"] = "completed"
	if task_id not in _completed_task_ids:
		_completed_task_ids.append(task_id)
	task_status_changed.emit(task_id, "completed")

	# 静默派发/排队隐藏工单（底层，玩家不可见）
	if _active_task_id.is_empty():
		_dispatch_order_silently(task_id)
	else:
		_order_queue.append(task_id)
		print("[DevCycleManager] Order queued: %s (queue size: %d)" % [task_id, _order_queue.size()])

	tasks_updated.emit()
	return true


## simple 类型：消耗 AP + 数值结算 → 直接完成
func _activate_simple_task(task: Dictionary) -> bool:
	var task_id: String = str(task.get("task_id", ""))

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.consume_ap(1, "dev_cycle", task_id):
		return false

	_settle_task_stats(task)

	task["status"] = "completed"
	_completed_task_ids.append(task_id)
	task_status_changed.emit(task_id, "completed")
	tasks_updated.emit()
	print("[DevCycleManager] Simple task completed: %s" % task_id)
	return true

#endregion


#region ──── 工单桥接（底层，玩家不可见）────

## 静默派发隐藏工单（不影响任务状态，不通知玩家）
func _dispatch_order_silently(task_id: String) -> void:
	var task: Dictionary = _task_pool.get(task_id, {})
	if task.is_empty():
		return

	var wo_template: Dictionary = task.get("work_order_template", {})
	if wo_template.is_empty():
		print("[DevCycleManager] No work_order_template for task: %s, skipping order" % task_id)
		_active_task_id = ""
		_process_queue()
		return

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[DevCycleManager] WorkOrderManager unavailable, skipping order for: %s" % task_id)
		_active_task_id = ""
		_process_queue()
		return

	var order_title: String = str(wo_template.get("title", task.get("title", "")))
	var order_desc: String = _build_order_description(task, wo_template)

	var order: Resource = wom.create_order(order_title, order_desc, {
		"source_type": "dev_task",
		"source_id": task_id,
	})
	order.assignee_npc_id = "npc_lin_xia"
	order.priority = int(wo_template.get("priority", 3))

	if wom.dispatch_order(order.id):
		_active_task_id = task_id
		_active_order_id = order.id
		print("[DevCycleManager] Silently dispatched order %s for task %s" % [order.id, task_id])
	else:
		push_warning("[DevCycleManager] Failed to dispatch order for task: %s" % task_id)
		_active_task_id = ""
		_process_queue()


## 构建工单 description
func _build_order_description(task: Dictionary, wo_template: Dictionary) -> String:
	var parts: PackedStringArray = []

	# 任务背景
	var task_title: String = str(task.get("title", ""))
	var task_desc: String = str(task.get("description", ""))
	parts.append("## 任务背景")
	parts.append("搭档安排了开发任务「%s」。" % task_title)
	if not task_desc.is_empty():
		parts.append(task_desc)
	parts.append("")

	# KB 源提示
	var kb_sources: Array = wo_template.get("kb_sources", [])
	if not kb_sources.is_empty():
		parts.append("## 参考资料")
		parts.append("请从 KnowledgeBase 中读取以下分类作为创作参考：")
		for src in kb_sources:
			parts.append("- %s" % str(src))
		parts.append("")

	# 具体要求
	var desc: String = str(wo_template.get("description", ""))
	if not desc.is_empty():
		parts.append("## 具体要求")
		parts.append(desc)
		parts.append("")

	# 输出目标
	var scene_target: String = str(wo_template.get("scene_target", ""))
	if not scene_target.is_empty():
		parts.append("## 输出目标")
		parts.append("- 场景 ID: %s" % scene_target)
		parts.append("")

	return "\n".join(parts)


## 工单状态变化回调（底层静默处理，不通知玩家）
func _on_order_status_changed(order_id: String, _old_status: String, new_status: String) -> void:
	if order_id == _creative_seed_setup_order_id:
		_handle_creative_seed_order_status_changed(order_id, new_status)

	if order_id != _active_order_id:
		return
	if new_status != "completed":
		return

	print("[DevCycleManager] Order completed silently: %s (task: %s)" % [order_id, _active_task_id])

	# 仅清理内部状态，不通知玩家（项目对玩家是黑箱）
	_active_task_id = ""
	_active_order_id = ""

	# 处理排队中的下一个工单
	_process_queue()


## 处理工单队列（内部，静默）
func _process_queue() -> void:
	while not _order_queue.is_empty():
		var next_id: String = _order_queue.pop_front()
		var task: Dictionary = _task_pool.get(next_id, {})
		if task.is_empty():
			continue
		# 自动工单有预创建的 order 对象
		if task.has("_auto_order_resource"):
			_dispatch_auto_order_from_queue(next_id, task)
		else:
			_dispatch_order_silently(next_id)
		return


## 将任务的工单加入静默派发队列
func _enqueue_silent_order(task_id: String) -> void:
	if _active_task_id.is_empty():
		_dispatch_order_silently(task_id)
	else:
		_order_queue.append(task_id)
		print("[DevCycleManager] Order queued (from callback): %s (queue size: %d)" % [task_id, _order_queue.size()])

#endregion


#region ──── MinigameManager 回调 ────

## MinigameManager 的小游戏/聊天任务完成回调
func _on_minigame_review_completed(task_id: String, _result: Dictionary) -> void:
	var task: Dictionary = _task_pool.get(task_id, {})
	if task.is_empty():
		return  # 不是 DevCycleManager 管理的任务

	# Topic 结束 → 消耗 AP（无论成败，经历讨论就消耗时间）
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("consume_ap"):
		glm.consume_ap(1, "dev_cycle", task_id)

	# 讨论失败 → 任务不算完成，恢复为可用，不派发工单，不结算数值
	var topic_failed: bool = bool(_result.get("topic_failed", false))
	if topic_failed:
		task["status"] = "available"
		task_status_changed.emit(task_id, "available")
		tasks_updated.emit()
		print("[DevCycleManager] Task failed (topic_failed), reset to available: %s" % task_id)
		return

	# 成功完成 → 标记任务状态
	if task.get("one_time", false):
		task["status"] = "completed"
		if task_id not in _completed_task_ids:
			_completed_task_ids.append(task_id)
		task_status_changed.emit(task_id, "completed")
	else:
		task["status"] = "available"  # 可重复任务恢复可用
		task_status_changed.emit(task_id, "available")

	# 如果任务带有 work_order_template，静默派发工单（底层）
	if task.has("work_order_template"):
		var task_type: String = str(task.get("task_type", ""))
		if task_type == "chat_topic":
			# chat_topic 的 KB 整理工单由 MinigameManager 处理
			# 这里只在模板额外指定了场景生成目标时才追加工单
			var wo_template: Dictionary = task.get("work_order_template", {})
			if not str(wo_template.get("scene_target", "")).is_empty():
				_enqueue_silent_order(task_id)
		else:
			# minigame 等类型：直接派发
			_enqueue_silent_order(task_id)

	tasks_updated.emit()

	# 检查概念期是否全部完成 → 触发计划生成
	_check_concept_completion()

#endregion


#region ──── 时间事件 ────

## 时段变化 → 解锁新任务
func _on_phase_changed(_new_phase: int) -> void:
	_unlock_new_tasks()
	tasks_updated.emit()


## 日变化 → 解锁新任务
func _on_day_changed(_new_day: int) -> void:
	_unlock_new_tasks()
	tasks_updated.emit()

#endregion


#region ──── 任务解锁 ────

## 检查章节计划中是否有新任务可以解锁
func _unlock_new_tasks() -> void:
	var day: int = _get_current_day()
	var unlocked_count: int = 0

	for plan in _chapter_plans:
		var unlock_day: int = int(plan.get("unlock_day", 1))
		if day < unlock_day:
			continue

		var tasks: Array = plan.get("tasks", [])
		for task_def in tasks:
			var task_id: String = str(task_def.get("task_id", ""))
			if task_id.is_empty():
				continue
			if task_id in _suppressed_task_ids:
				continue
			if _task_pool.has(task_id):
				continue  # 已在池中

			# 检查前置条件
			var prereqs: Array = task_def.get("prerequisites", [])
			var all_met: bool = true
			for prereq_id in prereqs:
				if str(prereq_id) not in _completed_task_ids:
					all_met = false
					break

			if all_met:
				var task: Dictionary = task_def.duplicate(true)
				task["status"] = "available"
				_task_pool[task_id] = task
				unlocked_count += 1
				print("[DevCycleManager] Unlocked task: %s (%s)" % [task_id, str(task.get("title", ""))])

	if unlocked_count > 0:
		tasks_updated.emit()

#endregion


#region ──── 数值结算 ────

func _settle_task_stats(task: Dictionary) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	var rewards: Dictionary = build_task_reward_preview(task)
	if not rewards.is_empty():
		gm.modify_stats(rewards)


func build_task_reward_preview(task: Dictionary, positive_scale: float = 1.0) -> Dictionary:
	var rewards: Dictionary = {}
	var stat_changes: Dictionary = task.get("stat_changes", {})
	for key in stat_changes:
		var scaled_value: int = roundi(float(int(stat_changes[key])) * positive_scale)
		if scaled_value != 0:
			rewards[str(key)] = scaled_value

	var stress_delta: int = get_effective_stress_cost(task)
	if stress_delta > 0:
		rewards["stress"] = stress_delta

	var passion_delta: int = -get_effective_passion_cost(task)
	if passion_delta != 0:
		rewards["passion"] = passion_delta

	return rewards


func get_effective_stress_cost(task: Dictionary) -> int:
	var base_load: int = _get_default_stress_load(task)
	return base_load + max(0, int(task.get("stress_cost", 0)))


func get_effective_passion_cost(task: Dictionary) -> int:
	if task.has("passion_cost"):
		return max(0, int(task.get("passion_cost", 0)))
	return _get_default_passion_cost(task)


func _get_default_stress_load(task: Dictionary) -> int:
	return DEFAULT_CHAT_STRESS_LOAD if str(task.get("task_type", "")) == "chat_topic" else DEFAULT_DEV_STRESS_LOAD


func _get_default_passion_cost(task: Dictionary) -> int:
	return DEFAULT_CHAT_PASSION_COST if str(task.get("task_type", "")) == "chat_topic" else DEFAULT_DEV_PASSION_COST

#endregion


#region ──── 数据加载 ────

func _load_chapter_plans() -> void:
	_chapter_plans.clear()
	if not FileAccess.file_exists(CHAPTER_PLANS_PATH):
		push_warning("[DevCycleManager] Chapter plans not found: %s" % CHAPTER_PLANS_PATH)
		return
	var file := FileAccess.open(CHAPTER_PLANS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[DevCycleManager] Failed to open chapter plans")
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("chapters"):
		_chapter_plans = parsed.get("chapters", [])
	elif parsed is Array:
		_chapter_plans = parsed
	print("[DevCycleManager] Loaded %d chapter plans" % _chapter_plans.size())


func _seed_initial_tasks() -> void:
	_unlock_new_tasks()

#endregion


#region ──── 动态计划生成 ────

## 概念期任务全部完成 → 读取 KB → 调用 LLM 生成开发计划
func _check_concept_completion() -> void:
	if _plan_generated or _plan_generating:
		return
	if _creative_seed_setup_order_id != "" or _seed_task_generating:
		return
	if _concept_gate_task_ids.is_empty():
		return

	for cid in _concept_gate_task_ids:
		if cid not in _completed_task_ids:
			return  # 还有概念任务未完成

	print("[DevCycleManager] All concept tasks completed, generating development plan...")
	_generate_development_plan()


## 读取 KB 概念文档 → 构建 prompt → 调用 LLM
func _generate_development_plan() -> void:
	_plan_generating = true

	# 收集 KB 中的概念设计文档
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	var kb_content: String = ""
	if kb != null and kb.has_method("get_documents"):
		var docs: Array = kb.get_documents()
		for doc in docs:
			var cat: String = str(doc.get("category", ""))
			var title: String = str(doc.get("title", ""))
			var content: String = str(doc.get("content", ""))
			if content.is_empty():
				continue
			kb_content += "### [%s] %s\n%s\n\n" % [cat, title, content]

	if kb_content.is_empty():
		push_warning("[DevCycleManager] KB is empty, using minimal context for plan generation")
		kb_content = "（暂无概念设计文档，请生成一份通用的日式异世界 AVG 开发计划）"

	var planning: Node = get_node_or_null("/root/PlanningManager")
	if planning == null or not planning.has_method("request_development_plan"):
		push_warning("[DevCycleManager] PlanningManager unavailable, skipping plan generation")
		_plan_generating = false
		plan_generated.emit(false)
		return

	_plan_gen_request_id = str(planning.request_development_plan(kb_content))
	if _plan_gen_request_id.is_empty():
		push_warning("[DevCycleManager] Failed to start development plan generation request")
		_plan_generating = false
		plan_generated.emit(false)
		return
	print("[DevCycleManager] Plan generation delegated to PlanningManager: %s" % _plan_gen_request_id)


## PlanningManager 返回开发计划
func _on_development_plan_completed(request_id: String, success: bool, chapters: Array, raw_output: String) -> void:
	if request_id != _plan_gen_request_id:
		return

	_cleanup_plan_gen_ai()

	if success:
		var injected: int = inject_chapters(chapters)
		_plan_generated = true
		_plan_generating = false
		print("[DevCycleManager] Development plan generated via PlanningManager: %d chapters stored, %d tasks immediately available" % [chapters.size(), injected])
		plan_generated.emit(true)
		return

	push_warning("[DevCycleManager] Failed to parse development plan output: %s" % raw_output.left(200))
	_plan_generating = false
	plan_generated.emit(false)


## 清理 AI 服务节点
func _cleanup_plan_gen_ai() -> void:
	_plan_gen_request_id = ""


## 从 LLM 响应中提取 JSON（处理 ```json ... ``` 包裹）
func _extract_json_from_response(text: String) -> String:
	# 尝试提取代码块中的 JSON
	var regex := RegEx.new()
	regex.compile("```(?:json)?\\s*\\n([\\s\\S]*?)\\n```")
	var match_result := regex.search(text)
	if match_result != null:
		return match_result.get_string(1).strip_edges()
	# 没有代码块，尝试直接找 [ ... ]
	var start: int = text.find("[")
	var end: int = text.rfind("]")
	if start >= 0 and end > start:
		return text.substr(start, end - start + 1)
	return text.strip_edges()

#endregion


#region ──── 创作基点 → 第一批 Dev Work ────

func _handle_creative_seed_order_status_changed(order_id: String, new_status: String) -> void:
	if new_status == "completed":
		print("[DevCycleManager] Creative seed setup order completed: %s" % order_id)
		_creative_seed_setup_order_id = ""
		_generate_seed_tasks_from_context()
		return

	if new_status == "failed":
		push_warning("[DevCycleManager] Creative seed setup order failed: %s" % order_id)
		_creative_seed_setup_order_id = ""
		_apply_seed_task_generation_result([])


func _generate_seed_tasks_from_context() -> void:
	if _seed_task_generating:
		return
	if _plan_generated or _plan_generating:
		return

	var planning: Node = get_node_or_null("/root/PlanningManager")
	if planning == null or not planning.has_method("request_seed_task_plan"):
		push_warning("[DevCycleManager] PlanningManager unavailable, using fallback seed tasks")
		_apply_seed_task_generation_result([])
		return

	_seed_task_generating = true
	_seed_task_gen_request_id = str(planning.request_seed_task_plan(_build_creative_seed_context()))
	if _seed_task_gen_request_id.is_empty():
		push_warning("[DevCycleManager] Failed to start seed task planning request, using fallback seed tasks")
		_cleanup_seed_task_gen_ai()
		_apply_seed_task_generation_result([])
		return
	print("[DevCycleManager] Seed dev work generation delegated to PlanningManager: %s" % _seed_task_gen_request_id)


func _on_seed_task_plan_completed(request_id: String, success: bool, tasks: Array, raw_output: String) -> void:
	if request_id != _seed_task_gen_request_id:
		return

	_cleanup_seed_task_gen_ai()

	if success:
		var added_count := _apply_seed_task_generation_result(tasks)
		if added_count > 0:
			print("[DevCycleManager] Seed dev work generated via PlanningManager: %d tasks" % added_count)
			return

	push_warning("[DevCycleManager] Failed to parse seed dev work output, using fallback tasks: %s" % raw_output.left(200))
	_apply_seed_task_generation_result([])


func _cleanup_seed_task_gen_ai() -> void:
	_seed_task_gen_request_id = ""
	_seed_task_generating = false


func _apply_seed_task_generation_result(raw_tasks: Array) -> int:
	if not _concept_gate_task_ids.is_empty():
		var existing_count := 0
		for task_id in _concept_gate_task_ids:
			if _task_pool.has(task_id) or task_id in _completed_task_ids:
				existing_count += 1
		if existing_count == _concept_gate_task_ids.size():
			return existing_count

	var fallback_tasks := _build_seed_task_fallbacks()
	var normalized_tasks: Array[Dictionary] = []
	for i in range(fallback_tasks.size()):
		var base_task: Dictionary = fallback_tasks[i].duplicate(true)
		if i < raw_tasks.size() and raw_tasks[i] is Dictionary:
			_merge_seed_task_override(base_task, raw_tasks[i])
		normalized_tasks.append(base_task)

	var added_ids: Array[String] = []
	for task in normalized_tasks:
		var added_id := add_dynamic_task(task)
		if not added_id.is_empty():
			added_ids.append(added_id)

	_concept_gate_task_ids.assign(added_ids)
	if added_ids.is_empty():
		push_warning("[DevCycleManager] Seed dev work registration failed; no tasks were added")
		return 0

	tasks_updated.emit()
	return added_ids.size()


func _merge_seed_task_override(base_task: Dictionary, override_task: Dictionary) -> void:
	var simple_keys: Array[String] = [
		"title", "description", "stress_cost", "passion_cost", "weight", "one_time",
	]
	for key in simple_keys:
		if override_task.has(key):
			base_task[key] = override_task[key]

	if override_task.has("stat_changes") and override_task["stat_changes"] is Dictionary:
		base_task["stat_changes"] = (override_task["stat_changes"] as Dictionary).duplicate(true)

	if override_task.has("topic_config") and override_task["topic_config"] is Dictionary:
		var base_topic: Dictionary = base_task.get("topic_config", {}).duplicate(true)
		var incoming_topic: Dictionary = override_task["topic_config"]
		for key in ["system_prompt", "goal_description", "kb_category", "kb_entry_id", "max_turns"]:
			if incoming_topic.has(key):
				base_topic[key] = incoming_topic[key]
		base_task["topic_config"] = base_topic


func _build_seed_task_fallbacks() -> Array[Dictionary]:
	var summary := _build_brief_summary_text()
	return [
		{
			"task_id": "seed_discuss_heroine_hook",
			"title": "讨论女主角的第一印象",
			"description": "和林夏一起确定女主角给人的第一感觉，以及她和主角之间最抓人的关系张力。",
			"task_type": "chat_topic",
			"stat_changes": {"quality": 5, "completion": 2},
			"stress_cost": 1,
			"weight": 10,
			"one_time": true,
			"topic_config": {
				"system_prompt": (
					"你是林夏，{player_name}的 GameJam 搭档。你们已经定下了作品基点：\n%s\n\n"
					+ "这次只讨论女主角给人的第一印象，以及她和主角之间最关键的关系张力。"
					+ "请主动给出 2-3 个有明显差异的方向，让搭档做取舍。"
					+ "用 1-2 条简短消息回应，讨论几轮后在最后加 [TOPIC_COMPLETE]。\n\n"
					+ "重要：如果搭档持续说与游戏设计完全无关的内容，先委婉提醒一次“咱们还是聊正事吧”。"
					+ "如果对方继续跑题，表达不满并在末尾加 [TOPIC_FAILED]"
				) % summary,
				"goal_description": "与搭档讨论女主角的第一印象与关系张力",
				"kb_category": "characters",
				"kb_entry_id": "heroine_seed",
				"max_turns": 8,
			},
		},
		{
			"task_id": "seed_discuss_protagonist_role",
			"title": "讨论主角在学院里的处境",
			"description": "和林夏一起确定主角在学院里的位置、处境和他看待这座学院的角度。",
			"task_type": "chat_topic",
			"stat_changes": {"quality": 5, "completion": 2},
			"stress_cost": 1,
			"weight": 10,
			"one_time": true,
			"topic_config": {
				"system_prompt": (
					"你是林夏，{player_name}的 GameJam 搭档。你们已经定下了作品基点：\n%s\n\n"
					+ "这次只讨论主角在学院里的位置和处境，比如他是边缘人、优等生、问题学生、旁听生还是别的身份。"
					+ "请多讨论这种处境会怎样影响故事气质和玩家代入感。"
					+ "用 1-2 条简短消息回应，讨论几轮后在最后加 [TOPIC_COMPLETE]。\n\n"
					+ "重要：如果搭档持续说与游戏设计完全无关的内容，先委婉提醒一次“咱们还是聊正事吧”。"
					+ "如果对方继续跑题，表达不满并在末尾加 [TOPIC_FAILED]"
				) % summary,
				"goal_description": "与搭档讨论主角在学院里的位置和处境",
				"kb_category": "characters",
				"kb_entry_id": "protagonist_seed",
				"max_turns": 8,
			},
		},
		{
			"task_id": "seed_discuss_opening_scene",
			"title": "讨论第一章开场事件",
			"description": "和林夏一起确定故事开场要先从什么事件切入，让玩家一进来就知道这部作品的味道。",
			"task_type": "chat_topic",
			"stat_changes": {"quality": 4, "completion": 3},
			"stress_cost": 2,
			"weight": 10,
			"one_time": true,
			"prerequisites": ["seed_discuss_heroine_hook", "seed_discuss_protagonist_role"],
			"topic_config": {
				"system_prompt": (
					"你是林夏，{player_name}的 GameJam 搭档。你们已经定下了作品基点：\n%s\n\n"
					+ "这次只讨论第一章该怎样开场。"
					+ "请围绕“第一幕先让玩家看到什么、感到什么、好奇什么”来推进讨论。"
					+ "可以提出几种切入方案，比如日常开场、事件开场、冲突开场、秘密开场。"
					+ "用 1-2 条简短消息回应，讨论几轮后在最后加 [TOPIC_COMPLETE]。\n\n"
					+ "重要：如果搭档持续说与游戏设计完全无关的内容，先委婉提醒一次“咱们还是聊正事吧”。"
					+ "如果对方继续跑题，表达不满并在末尾加 [TOPIC_FAILED]"
				) % summary,
				"goal_description": "与搭档讨论第一章开场事件",
				"kb_category": "story",
				"kb_entry_id": "opening_seed",
				"max_turns": 10,
			},
		},
	]


func _build_creative_seed_context() -> String:
	var sections: PackedStringArray = []
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb != null and kb.has_method("get_document"):
		for doc_id in [CREATIVE_CORE_DOC_ID, OPEN_DESIGN_QUESTIONS_DOC_ID, CREATIVE_SEED_SOURCE_ID]:
			var doc: Dictionary = kb.get_document(doc_id)
			if doc.is_empty():
				continue
			sections.append("### [%s] %s\n%s" % [
				str(doc.get("category", "")),
				str(doc.get("title", "")),
				str(doc.get("content", "")),
			])

	if sections.is_empty():
		sections.append(_format_brief_data_as_markdown(_latest_creative_brief))
	return "\n\n".join(sections)


func _build_brief_summary_text() -> String:
	var title := str(_latest_creative_brief.get("game_title", "")).strip_edges()
	var genre := str(_latest_creative_brief.get("game_genre", "")).strip_edges()
	var tags := str(_latest_creative_brief.get("game_tags", "")).strip_edges()
	var outline := str(_latest_creative_brief.get("game_outline", "")).strip_edges()
	var parts: PackedStringArray = [
		"固定背景：日式魔法异世界学院",
		"作品名称：%s" % title,
		"作品类型：%s" % genre,
		"基调标签：%s" % tags,
	]
	if not outline.is_empty():
		parts.append("页面大纲：%s" % outline)
	return "\n".join(parts)


func _format_brief_data_as_markdown(brief_data: Dictionary) -> String:
	var title := str(brief_data.get("game_title", "")).strip_edges()
	var genre := str(brief_data.get("game_genre", "")).strip_edges()
	var tags := str(brief_data.get("game_tags", "")).strip_edges()
	var outline := str(brief_data.get("game_outline", "")).strip_edges()
	var lines: PackedStringArray = [
		"### [creative_brief] 玩家原始创作基点",
		"- 固定背景：日式魔法异世界学院",
		"- 作品名称：%s" % title,
		"- 作品类型：%s" % genre,
		"- 基调标签：%s" % tags,
		"- 页面大纲：%s" % outline,
	]
	return "\n".join(lines)


#endregion


#region ──── 动态任务注入 API ────

## 注入多个章节到计划中（由 LLM 生成或底层 agent 请求）
## 返回注入的任务数量
func inject_chapters(chapters: Array) -> int:
	var count: int = 0
	for ch in chapters:
		if not ch is Dictionary:
			continue
		_chapter_plans.append(ch)
		count += _inject_chapter_tasks(ch)
	if count > 0:
		tasks_updated.emit()
	return count


## 注入单个章节的任务到池中（检查 unlock_day 和 prerequisites）
func _inject_chapter_tasks(chapter: Dictionary) -> int:
	var unlock_day: int = int(chapter.get("unlock_day", 1))
	var day: int = _get_current_day()
	var count: int = 0

	var tasks: Array = chapter.get("tasks", [])
	for task_def in tasks:
		var task_id: String = str(task_def.get("task_id", ""))
		if task_id.is_empty() or _task_pool.has(task_id):
			continue
		if task_id in _suppressed_task_ids:
			continue

		# 检查解锁日和前置条件
		if day < unlock_day:
			continue
		var prereqs: Array = task_def.get("prerequisites", [])
		var all_met: bool = true
		for prereq_id in prereqs:
			if str(prereq_id) not in _completed_task_ids:
				all_met = false
				break
		if not all_met:
			continue

		var task: Dictionary = task_def.duplicate(true)
		task["status"] = "available"
		_task_pool[task_id] = task
		count += 1
		print("[DevCycleManager] Injected task: %s (%s)" % [task_id, str(task.get("title", ""))])

	return count


## 动态添加单个任务（可由底层 agent 或其他系统调用）
## 返回任务 ID（如果添加成功）
func add_dynamic_task(task_def: Dictionary) -> String:
	var task_id: String = str(task_def.get("task_id", ""))
	if task_id.is_empty():
		task_id = "dynamic_%d" % int(Time.get_unix_time_from_system())
		task_def["task_id"] = task_id

	if _task_pool.has(task_id):
		push_warning("[DevCycleManager] Task already exists: %s" % task_id)
		return ""

	var task: Dictionary = task_def.duplicate(true)
	task["status"] = "available"
	_task_pool[task_id] = task

	# 不加入 _chapter_plans（动态任务独立于章节体系）
	tasks_updated.emit()
	print("[DevCycleManager] Dynamic task added: %s (%s)" % [task_id, str(task.get("title", ""))])
	return task_id


## 查询计划是否已生成
func is_plan_generated() -> bool:
	return _plan_generated


## 查询计划是否正在生成中
func is_plan_generating() -> bool:
	return _plan_generating

#endregion


#region ──── 底层上浮回调 ────

## 底层 agent 请求创意讨论 → 创建动态 chat_topic 任务
func _on_creative_task_requested(context: Dictionary) -> void:
	var topic: String = str(context.get("topic", ""))
	var description: String = str(context.get("description", "搭档建议讨论：%s" % topic))
	var kb_category: String = str(context.get("kb_category", "story"))
	var kb_entry_id: String = str(context.get("kb_entry_id", ""))
	var requester: String = str(context.get("requester_order_id", ""))

	# 生成唯一的 task_id
	var task_id: String = "agent_req_%d" % int(Time.get_unix_time_from_system())

	# 构建 system_prompt
	var sys_prompt: String = str(context.get("system_prompt", ""))
	if sys_prompt.is_empty():
		sys_prompt = (
			"你是林夏，{player_name}的 GameJam 搭档。\n"
			+ "你在开发过程中发现需要和搭档讨论一下：%s\n\n" % topic
			+ "背景：%s\n\n" % description
			+ "用1-2条简短消息回应，讨论几轮后觉得差不多了在最后加 [TOPIC_COMPLETE]\n\n"
			+ "重要：如果搭档持续说与游戏设计完全无关的内容，先委婉提醒一次'咱们还是聊正事吧'。"
			+ "如果对方继续跑题，表达不满并在末尾加 [TOPIC_FAILED]"
		)

	# 默认 stat_changes
	var stat_changes: Dictionary = context.get("stat_changes", {"quality": 3, "completion": 1})

	var task_def: Dictionary = {
		"task_id": task_id,
		"title": topic,
		"description": description,
		"task_type": "chat_topic",
		"stat_changes": stat_changes,
		"stress_cost": 1,
		"weight": 9,  # 高优先级显示
		"one_time": true,
		"_source": "agent_request",
		"_requester_order_id": requester,
		"topic_config": {
			"system_prompt": sys_prompt,
			"goal_description": "与搭档讨论：%s" % topic,
			"kb_category": kb_category,
			"kb_entry_id": kb_entry_id if not kb_entry_id.is_empty() else task_id,
			"max_turns": 8,
		},
	}

	var added_id: String = add_dynamic_task(task_def)
	if not added_id.is_empty():
		print("[DevCycleManager] Agent-requested creative task created: %s (from: %s)" % [added_id, requester])

#endregion


#region ──── 辅助方法 ────

func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return 1
	return int(glm.get("current_day"))

#endregion


#region ──── 条件自动工单（方案 3）────

## 已触发过的自动工单条件 ID，防止重复触发
var _triggered_auto_orders: Array[String] = []

## 自动工单条件定义
## 格式: { "id": "unique_id", "stat": "completion", "threshold": 25,
##          "operator": ">=", "title": "...", "description": "...",
##          "kb_sources": [...], "scene_target": "..." }
const AUTO_ORDER_CONDITIONS: Array[Dictionary] = [
	{
		"id": "auto_midpoint_review",
		"stat": "completion",
		"threshold": 40,
		"operator": ">=",
		"title": "中期内容整合审查",
		"description": "项目已完成约40%%。请对已有的全部场景进行整合审查。\n\n要求：\n- 检查各章节之间的衔接和连贯性\n- 验证角色性格和语气的一致性\n- 标注需要修改的问题\n- 生成一份简短的审查报告",
		"kb_sources": ["characters", "story", "world"],
	},
	{
		"id": "auto_quality_polish",
		"stat": "quality",
		"threshold": 60,
		"operator": "<",
		"requires_completion": 50,
		"title": "全局质量润色",
		"description": "完成度已过半但质量偏低。请对已有场景进行质量润色。\n\n要求：\n- 优化对话的自然度和表现力\n- 改善场景描写的细腻程度\n- 统一文风和语气\n- 不改变剧情走向，只提升文字质量",
		"kb_sources": ["characters", "story"],
	},
]


func _connect_auto_order_signals() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	if gm.has_signal("stats_changed"):
		gm.stats_changed.connect(_check_auto_order_conditions)


## 检查所有自动工单条件
func _check_auto_order_conditions() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	for condition in AUTO_ORDER_CONDITIONS:
		var cond_id: String = str(condition.get("id", ""))
		if cond_id in _triggered_auto_orders:
			continue

		var stat_name: String = str(condition.get("stat", ""))
		var threshold: int = int(condition.get("threshold", 0))
		var op: String = str(condition.get("operator", ">="))
		var current_val: int = int(gm.get(stat_name)) if stat_name in gm else 0

		# 额外条件检查
		var requires_completion: int = int(condition.get("requires_completion", 0))
		if requires_completion > 0:
			var current_completion: int = int(gm.get("completion")) if "completion" in gm else 0
			if current_completion < requires_completion:
				continue

		var met: bool = false
		match op:
			">=":
				met = current_val >= threshold
			"<=":
				met = current_val <= threshold
			"<":
				met = current_val < threshold
			">":
				met = current_val > threshold
			"==":
				met = current_val == threshold

		if met:
			_triggered_auto_orders.append(cond_id)
			_dispatch_auto_order(condition)


## 派发条件触发的自动工单（从队列恢复时）
func _dispatch_auto_order_from_queue(dummy_id: String, task: Dictionary) -> void:
	var order: Resource = task.get("_auto_order_resource")
	if order == null:
		push_warning("[DevCycleManager] Auto order resource missing for: %s" % dummy_id)
		_process_queue()
		return

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[DevCycleManager] WorkOrderManager unavailable for auto order: %s" % dummy_id)
		_process_queue()
		return

	if wom.dispatch_order(order.id):
		_active_task_id = dummy_id
		_active_order_id = order.id
		print("[DevCycleManager] Auto order dispatched from queue: %s (%s)" % [dummy_id, order.id])
	else:
		push_warning("[DevCycleManager] Failed to dispatch queued auto order: %s" % dummy_id)
		_process_queue()


## 派发条件触发的自动工单
func _dispatch_auto_order(condition: Dictionary) -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		return

	var title: String = str(condition.get("title", "自动任务"))
	var desc_parts: PackedStringArray = []
	desc_parts.append("## 自动触发")
	desc_parts.append("此工单由系统根据项目数值条件自动触发。")
	desc_parts.append("")

	var kb_sources: Array = condition.get("kb_sources", [])
	if not kb_sources.is_empty():
		desc_parts.append("## 参考资料")
		desc_parts.append("请从 KnowledgeBase 中读取以下分类作为参考：")
		for src in kb_sources:
			desc_parts.append("- %s" % str(src))
		desc_parts.append("")

	var desc_text: String = str(condition.get("description", ""))
	if not desc_text.is_empty():
		desc_parts.append("## 具体要求")
		desc_parts.append(desc_text)

	var scene_target: String = str(condition.get("scene_target", ""))
	if not scene_target.is_empty():
		desc_parts.append("")
		desc_parts.append("## 输出目标")
		desc_parts.append("- 场景 ID: %s" % scene_target)

	var order: Resource = wom.create_order(title, "\n".join(desc_parts), {
		"source_type": "dev_task",
		"source_id": "auto_%s" % str(condition.get("id", "")),
	})
	order.assignee_npc_id = "npc_lin_xia"
	order.priority = int(condition.get("priority", 2))

	# 使用内部队列确保不与其他工单冲突
	var dummy_id: String = "auto_%s" % str(condition.get("id", ""))
	# 直接存入 task_pool 以便队列管理
	_task_pool[dummy_id] = {
		"task_id": dummy_id,
		"status": "completed",
		"work_order_template": condition,
		"_auto_order_resource": order,
	}

	if _active_task_id.is_empty():
		if wom.dispatch_order(order.id):
			_active_task_id = dummy_id
			_active_order_id = order.id
			print("[DevCycleManager] Auto order dispatched: %s (%s)" % [str(condition.get("id", "")), order.id])
		else:
			push_warning("[DevCycleManager] Failed to dispatch auto order: %s" % dummy_id)
	else:
		_order_queue.append(dummy_id)
		print("[DevCycleManager] Auto order queued: %s (queue size: %d)" % [dummy_id, _order_queue.size()])

#endregion
