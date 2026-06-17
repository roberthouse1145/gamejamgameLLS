extends Node
## DevCycleManager Autoload
## 管理开发循环：任务池 → 玩家交互 → 触发后台工单 → 解锁新任务
##
## 核心设计:
##   表层(DevWork任务) 和 底层(WorkOrder工单) 完全解耦。
##   - DevWork 任务在玩家完成交互后立即标记为 completed（项目对玩家是黑箱）
##   - WorkOrder 工单在后台静默执行（1~10分钟），完成时不通知玩家
##   - 玩家通过里程碑 Demo/Preview 才能看到实际成果
##
## 任务进化:
##   玩家先通过 creative brief 建立创作基点，并将原始基点直接写入 KB，
##   再由系统根据当前 KB 内容生成第一批 dev work 与后续开发计划。
##
## 任务类型:
##   - chat_topic: 有 topic_config → 委托 MinigameManager 处理讨论，完成后可触发工单
##   - minigame: 有 minigame_type → 委托 MinigameManager 处理小游戏，完成后可触发工单
##   - work_order / simple: 仅保留给调试或内部兼容，不属于正式玩家任务类型

const DesktopNotificationUtilsClass = preload("res://scripts/pseudo_os/desktop_notification_utils.gd")
const DEVELOPMENT_BATCH_MIN_COUNT: int = 2
const DEVELOPMENT_BATCH_MAX_COUNT: int = 3
const DEVELOPMENT_BATCH_TRIGGER_PENDING_COUNT: int = 0
const DEFAULT_PRODUCTION_MINIGAME_TYPE: String = "typing_code"
const ALLOW_DIRECT_COMPLETE_DEV_TASKS: bool = false
## 项目立项讨论结果落地后写入 KB 的稳定 doc_id；用作"是否已立项"的探测依据
const CREATIVE_BRIEF_DOC_ID: String = "creative_brief"
const DEFAULT_CHAT_STRESS_LOAD: int = 10
const DEFAULT_CHAT_PASSION_COST: int = 6
const DEFAULT_DEV_STRESS_LOAD: int = 20
const DEFAULT_DEV_PASSION_COST: int = 18
const DEV_WORK_PASSION_REFUSE_THRESHOLD: int = 20
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
## 是否已生成开发计划（防止重复生成）
var _plan_generated: bool = false
## 计划生成中
var _plan_generating: bool = false
## 计划生成请求 ID
var _plan_gen_request_id: String = ""
## lab 测试捷径：跳过讨论/小游戏，直接完成任务并触发工单
var _debug_direct_execute_interactive_tasks: bool = false
## 表层任务顺序号，保证 DevWork 按 planner 顺位逐个放出
var _task_surface_sequence_counter: int = 0
## 当前时段已经被林夏拒绝过 dev_work（按时段重置）。空字符串表示未被拒绝。
var _dev_work_refused_this_phase: String = ""
#endregion


func _ready() -> void:
	_connect_signals()
	print("[DevCycleManager] Initialized. %d tasks in pool." % _task_pool.size())


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
		if planning.has_signal("development_plan_completed"):
			planning.development_plan_completed.connect(_on_development_plan_completed)


func reset_runtime_state() -> void:
	_cleanup_plan_gen_ai()
	_task_pool.clear()
	_order_queue.clear()
	_active_task_id = ""
	_active_order_id = ""
	_completed_task_ids.clear()
	_plan_generated = false
	_plan_generating = false
	_task_surface_sequence_counter = 0
	_dev_work_refused_this_phase = ""
	var planning: Node = get_node_or_null("/root/PlanningManager")
	if planning != null and planning.has_method("reset_runtime_state"):
		planning.reset_runtime_state()
	tasks_updated.emit()


#region ──── Public API ────

## 获取当前对玩家可见的任务列表（供 DevWorkApp 与上下文摘要使用）
## 现在只暴露一个当前任务；其余任务保留为内部顺序队列或只读后续预告
func get_visible_tasks() -> Array[Dictionary]:
	var current_task: Dictionary = get_current_surface_task()
	if current_task.is_empty():
		return []
	return [current_task]


func get_current_surface_task() -> Dictionary:
	var active_or_queued := _get_surface_candidates(["active", "queued"])
	if not active_or_queued.is_empty():
		return active_or_queued[0]

	var available := _get_surface_candidates(["available"])
	if available.is_empty():
		return {}
	return available[0]


func get_upcoming_surface_tasks(limit: int = 2) -> Array[Dictionary]:
	if limit <= 0:
		return []
	var available := _get_surface_candidates(["available"])
	if available.is_empty():
		return []

	var current_task: Dictionary = get_current_surface_task()
	var current_id: String = str(current_task.get("task_id", "")).strip_edges()
	var previews: Array[Dictionary] = []
	for task in available:
		var task_id: String = str(task.get("task_id", "")).strip_edges()
		if not current_id.is_empty() and task_id == current_id:
			continue
		previews.append(task)
		if previews.size() >= limit:
			break
	return previews


func _get_surface_candidates(allowed_statuses: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task_id in _task_pool:
		var task: Dictionary = _task_pool[task_id]
		var status: String = str(task.get("status", "")).strip_edges()
		if status not in allowed_statuses:
			continue
		if status == "available" and not _are_task_prerequisites_met(task):
			continue
		result.append(task)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("_surface_priority", 0))
		var pb: int = int(b.get("_surface_priority", 0))
		if pa != pb:
			return pa > pb
		var sa: int = int(a.get("_surface_sequence", 2147483647))
		var sb: int = int(b.get("_surface_sequence", 2147483647))
		if sa != sb:
			return sa < sb
		return int(a.get("weight", 5)) > int(b.get("weight", 5))
	)
	return result


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

	# 已经被林夏拒绝过 → 静默拒绝，不再触发新的对话，UI 应已 disable
	if not _dev_work_refused_this_phase.is_empty():
		push_warning("[DevCycleManager] dev_work refused this phase: %s" % _dev_work_refused_this_phase)
		return false

	# 当前数值不适合开发 → 触发林夏拒绝消息，并在当前时段禁用
	var refusal := _check_dev_work_refusal()
	if not refusal.is_empty():
		_dev_work_refused_this_phase = str(refusal.get("short", "林夏拒绝了这个时段的开发"))
		var refusal_center: Node = get_node_or_null("/root/NpcRefusalCenter")
		if refusal_center != null and refusal_center.has_method("trigger_refusal"):
			refusal_center.trigger_refusal(
				str(refusal.get("refusal_id", "dev_work")),
				str(refusal.get("warning_desc", "")),
				str(refusal.get("fallback", ""))
			)
		tasks_updated.emit()
		print("[DevCycleManager] dev_work refused: %s" % str(refusal.get("refusal_id", "")))
		return false

	var task_type: String = str(task.get("task_type", "")).strip_edges()

	if _debug_direct_execute_interactive_tasks:
		if task_type == "chat_topic" or (task_type == "minigame" and str(task.get("minigame_type", "")).strip_edges() == "creative_decision"):
			return _activate_debug_chat_topic_task(task)
		if not _get_post_task_work_order(task).is_empty():
			return _activate_work_order_task(task)
		return _activate_simple_task(task)

	# 根据任务类型路由

	# 向后兼容：旧的 chat_topic 统一走 creative_decision 小游戏路径
	if task_type == "chat_topic":
		task["task_type"] = "minigame"
		task["minigame_type"] = "creative_decision"
		return _activate_minigame_task(task)

	var minigame_type: String = _resolve_task_minigame_type(task)
	if not minigame_type.is_empty():
		task["task_type"] = "minigame"
		task["minigame_type"] = minigame_type
		return _activate_minigame_task(task)

	if ALLOW_DIRECT_COMPLETE_DEV_TASKS:
		if not _get_post_task_work_order(task).is_empty():
			return _activate_work_order_task(task)
		return _activate_simple_task(task)

	push_warning("[DevCycleManager] Non-interactive dev task blocked in runtime: %s" % task_id)
	return false


## 是否有工单正在执行
func is_order_active() -> bool:
	return not _active_task_id.is_empty()


## 获取队列长度
func get_queue_size() -> int:
	return _order_queue.size()


## 获取已完成任务数
func get_completed_count() -> int:
	return _completed_task_ids.size()


func set_debug_direct_execute_interactive_tasks(enabled: bool) -> void:
	_debug_direct_execute_interactive_tasks = enabled
	print("[DevCycleManager] Debug direct execute interactive tasks: %s" % ("enabled" if enabled else "disabled"))


func is_debug_direct_execute_interactive_tasks_enabled() -> bool:
	return _debug_direct_execute_interactive_tasks


## 当前时段是否已被林夏拒绝过 dev_work（用于 UI disable 与 tooltip）。
## 拒绝理由会持续到下一时段；下一时段重新允许玩家点击触发检测。
func get_dev_work_disabled_reason() -> String:
	return _dev_work_refused_this_phase


## 兼容旧调用：返回是否已被拒绝（不再做"提前禁用"，仅返回已拒绝状态）。
func get_dev_work_blocking_reason() -> String:
	return _dev_work_refused_this_phase


## 当玩家点击 dev_work 时，根据当前数值判定是否需要被林夏拒绝。
## 返回结构化拒绝信息：
##   refusal_id: 给 NpcRefusalCenter 用的标识
##   warning_desc: 给 LLM 的拒绝起因语义描述（第三人称视角，数值归属必须明确）
##   short: UI tooltip / 当前时段禁用原因（短文案）
##   fallback: LLM 不可用时的本地兜底句（这条是林夏直接说出口的话，所以用第一人称）
## 不需要拒绝时返回空字典。
func _check_dev_work_refusal() -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return {}
	var passion_value := int(gm.get("passion"))
	if passion_value <= DEV_WORK_PASSION_REFUSE_THRESHOLD:
		return {
			"refusal_id": "dev_work_passion_low",
			"warning_desc": (
				"搭档（玩家）想给林夏派一个新的开发任务，让她在这个时段动手干活。"
				+ "但林夏自己当前的创作热情已经掉到 %d（阈值≤%d，已是危险值）。"
				+ "林夏不想接这个工单，她希望搭档先放过她，让她去做点能找回灵感的事，或者干脆让她歇会儿。"
			) % [passion_value, DEV_WORK_PASSION_REFUSE_THRESHOLD],
			"short": "林夏现在没心情开发，先换换脑子",
			"fallback": "我现在真的写不动……先去找点能让我提起劲的事吧。",
		}
	return {}


## 探测当前 KB 是否已经写入立项 brief（worker 工单整理后会写一篇 doc_id=creative_brief 的文档）
func _has_creative_brief_in_kb() -> bool:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_document"):
		return false
	var doc: Dictionary = kb.get_document(CREATIVE_BRIEF_DOC_ID)
	return not doc.is_empty()

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

	var minigame_type: String = _resolve_task_minigame_type(task)
	if not mgr.has_minigame(minigame_type):
		push_warning("[DevCycleManager] No registered minigame for task: %s (%s)" % [
			str(task.get("task_id", "")),
			minigame_type,
		])
		return false

	task["task_type"] = "minigame"
	task["minigame_type"] = minigame_type
	if mgr.start_minigame(task):
		var task_id: String = str(task.get("task_id", ""))
		task["status"] = "active"
		task_status_changed.emit(task_id, "active")
		tasks_updated.emit()
		return true
	return false


## 调试兼容：work_order 类型直接结算，不用于正式玩家任务
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
	_ensure_development_task_supply()
	return true


## lab/test 快速模式：跳过 chat_topic 实际讨论，但仍直接触发后台工单
func _activate_debug_chat_topic_task(task: Dictionary) -> bool:
	var task_id: String = str(task.get("task_id", ""))

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.consume_ap(1, "dev_cycle", task_id):
		return false

	_settle_task_stats(task)

	task["status"] = "completed"
	if task_id not in _completed_task_ids:
		_completed_task_ids.append(task_id)
	task_status_changed.emit(task_id, "completed")

	if _active_task_id.is_empty():
		_dispatch_order_silently(task_id)
	else:
		_order_queue.append(task_id)
		print("[DevCycleManager] Debug chat-topic order queued: %s (queue size: %d)" % [task_id, _order_queue.size()])

	tasks_updated.emit()
	_ensure_development_task_supply()
	return true


## 调试兼容：simple 类型直接结算，不用于正式玩家任务
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
	_ensure_development_task_supply()
	print("[DevCycleManager] Simple task completed: %s" % task_id)
	return true

#endregion


#region ──── 工单桥接（底层，玩家不可见）────

## 静默派发隐藏工单（不影响任务状态，不通知玩家）
func _dispatch_order_silently(task_id: String) -> void:
	var task: Dictionary = _task_pool.get(task_id, {})
	if task.is_empty():
		return

	var wo_template: Dictionary = _get_post_task_work_order(task)
	if wo_template.is_empty():
		print("[DevCycleManager] No post_task_work_order for task: %s, skipping order" % task_id)
		_active_task_id = ""
		_process_queue()
		return

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[DevCycleManager] WorkOrderManager unavailable, skipping order for: %s" % task_id)
		_active_task_id = ""
		_process_queue()
		return

	var completion_result: Dictionary = task.get("_last_completion_result", {})
	var order_title: String = str(wo_template.get("title", task.get("title", "")))
	var order_desc: String = _build_order_description(task, wo_template, completion_result)

	var order: Resource = wom.create_order(order_title, order_desc, {
		"source_type": "dev_task",
		"source_id": task_id,
	})
	order.priority = int(wo_template.get("priority", 3))
	task.erase("_last_completion_result")

	if wom.dispatch_order(order.id):
		_active_task_id = task_id
		_active_order_id = order.id
		print("[DevCycleManager] Silently dispatched order %s for task %s" % [order.id, task_id])
	else:
		push_warning("[DevCycleManager] Failed to dispatch order for task: %s" % task_id)
		_active_task_id = ""
		_process_queue()


func _dispatch_debug_chat_topic_order_silently(task_id: String, task: Dictionary) -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[DevCycleManager] WorkOrderManager unavailable, skipping debug chat-topic order for: %s" % task_id)
		_active_task_id = ""
		_process_queue()
		return

	var topic_config: Dictionary = task.get("topic_config", {})
	var task_title: String = str(task.get("title", ""))
	var task_desc: String = str(task.get("description", ""))
	var kb_category: String = str(topic_config.get("kb_category", "notes")).strip_edges()
	var kb_entry_id: String = str(topic_config.get("kb_entry_id", "")).strip_edges()
	var goal_description: String = str(topic_config.get("goal_description", "")).strip_edges()
	var system_prompt: String = str(topic_config.get("system_prompt", "")).strip_edges()

	var desc_parts: PackedStringArray = []
	desc_parts.append("## 任务背景")
	desc_parts.append("这是测试 / lab 快速模式下直接跳过讨论的创意任务「%s」。" % task_title)
	if not task_desc.is_empty():
		desc_parts.append("任务描述：%s" % task_desc)
	if not goal_description.is_empty():
		desc_parts.append("讨论目标：%s" % goal_description)
	desc_parts.append("")
	desc_parts.append("## KB 目标")
	desc_parts.append("- 分类：%s" % kb_category)
	if not kb_entry_id.is_empty():
		desc_parts.append("- 条目 ID：%s" % kb_entry_id)
	desc_parts.append("")
	desc_parts.append("## Fast Mode 说明")
	desc_parts.append("本次没有真实对话记录，因为测试场景已跳过讨论流程。")
	desc_parts.append("请根据当前项目企划书、已有 KnowledgeBase、任务标题/描述与下方讨论指令，整理出这一轮最合理的讨论结论。")
	desc_parts.append("不要脑补未被当前上下文支持的内容；无法确认的部分明确标注为待定。")
	if not system_prompt.is_empty():
		desc_parts.append("")
		desc_parts.append("## 原讨论指令")
		desc_parts.append(system_prompt)

	var order: Resource = wom.create_order("整理讨论结果：%s" % task_title, "\n".join(desc_parts), {
		"source_type": "dev_task",
		"source_id": task_id,
	})
	order.priority = 3

	if wom.dispatch_order(order.id):
		if wom.has_method("is_order_running") and wom.is_order_running(order.id):
			_active_task_id = task_id
			_active_order_id = order.id
			print("[DevCycleManager] Silently dispatched debug chat-topic order %s for task %s" % [order.id, task_id])
		else:
			print("[DevCycleManager] Debug chat-topic order queued in WorkOrderManager: %s (task: %s)" % [order.id, task_id])
	else:
		push_warning("[DevCycleManager] Failed to dispatch debug chat-topic order for task: %s" % task_id)
		_active_task_id = ""
		_process_queue()


## 构建工单 description
func _build_order_description(task: Dictionary, wo_template: Dictionary, completion_result: Dictionary = {}) -> String:
	var parts: PackedStringArray = []

	# 任务背景
	var task_title: String = str(task.get("title", ""))
	var task_desc: String = str(task.get("description", ""))
	parts.append("## 任务背景")
	parts.append("搭档安排了开发任务「%s」。" % task_title)
	if not task_desc.is_empty():
		parts.append(task_desc)
	parts.append("")

	var performance_block := _build_post_task_performance_block(wo_template, completion_result)
	if not performance_block.is_empty():
		parts.append("## 本次执行结果")
		parts.append(performance_block)
		parts.append("")

	var creative_block := _build_creative_prompt_block(completion_result)
	if not creative_block.is_empty():
		parts.append("## 玩家输入锚点")
		parts.append(creative_block)
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


func _build_post_task_performance_block(wo_template: Dictionary, completion_result: Dictionary) -> String:
	if completion_result.is_empty():
		return ""
	if bool(completion_result.get("chat_task", false)):
		return ""

	var performance_context: String = str(wo_template.get("performance_context", "none")).strip_edges().to_lower()
	if performance_context.is_empty() or performance_context == "none":
		return ""

	var lines: PackedStringArray = []
	var score: float = float(completion_result.get("score", -1.0))
	if score >= 0.0:
		lines.append("- 本次小游戏综合表现：%.0f%%" % (score * 100.0))

	var snippet_title: String = str(completion_result.get("snippet_title", "")).strip_edges()
	if performance_context in ["summary", "full_context"] and not snippet_title.is_empty():
		lines.append("- 本次处理片段：%s" % snippet_title)

	var accuracy: float = float(completion_result.get("accuracy", -1.0))
	if performance_context in ["summary", "full_context"] and accuracy >= 0.0:
		lines.append("- 准确率：%.0f%%" % (accuracy * 100.0))

	var code_completion: float = float(completion_result.get("code_completion", -1.0))
	if performance_context == "full_context" and code_completion >= 0.0:
		lines.append("- 代码片段完成度：%.0f%%" % (code_completion * 100.0))

	var max_combo: int = int(completion_result.get("max_combo", 0))
	if performance_context == "full_context" and max_combo > 0:
		lines.append("- 最大连击：%d" % max_combo)

	var elapsed: float = float(completion_result.get("elapsed", -1.0))
	if performance_context == "full_context" and elapsed >= 0.0:
		lines.append("- 本次耗时：%.1f 秒" % elapsed)

	if lines.is_empty():
		return ""
	return "\n".join(lines)


func _build_creative_prompt_block(completion_result: Dictionary) -> String:
	if completion_result.is_empty():
		return ""
	var work_order_brief: String = str(completion_result.get("work_order_brief", "")).strip_edges()
	if not work_order_brief.is_empty():
		return work_order_brief
	var creative_prompt: String = str(completion_result.get("creative_prompt", "")).strip_edges()
	if not creative_prompt.is_empty():
		return creative_prompt
	return ""


## 工单状态变化回调（底层静默处理，不通知玩家）
## 任何工单 completed 都会触发一次 _ensure_development_task_supply 续杯尝试，
## 第一个 worker 完成（即立项讨论的整理工单）就由这条路径触发首次 plan_generation。
func _on_order_status_changed(order_id: String, _old_status: String, new_status: String) -> void:
	if new_status == "completed":
		# 任意 worker 完成都给一次续杯机会（含非 active_order 的子工单 / 异步派发完成）
		_ensure_development_task_supply()

	if order_id != _active_order_id:
		return
	if new_status not in ["completed", "needs_input", "failed"]:
		return

	if new_status == "completed":
		print("[DevCycleManager] Order completed silently: %s (task: %s)" % [order_id, _active_task_id])
	else:
		print("[DevCycleManager] Order left execution slot: %s -> %s (task: %s)" % [order_id, new_status, _active_task_id])

	# 仅清理内部状态，不通知玩家（项目对玩家是黑箱）
	_active_task_id = ""
	_active_order_id = ""

	# 处理排队中的下一个工单
	_process_queue()
	_ensure_development_task_supply()


## 处理工单队列（内部，静默）
func _process_queue() -> void:
	while not _order_queue.is_empty():
		var next_id: String = _order_queue.pop_front()
		var task: Dictionary = _task_pool.get(next_id, {})
		if task.is_empty():
			continue
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

	var cancelled: bool = bool(_result.get("cancelled", false))
	if cancelled:
		task["status"] = "available"
		task_status_changed.emit(task_id, "available")
		tasks_updated.emit()
		print("[DevCycleManager] Task cancelled, reset to available: %s" % task_id)
		return

	# 交互成功结束 → 消耗 AP
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

	var post_task_work_order := _get_post_task_work_order(task)
	_handle_post_task_handler(task, _result)
	if not post_task_work_order.is_empty():
		task["_last_completion_result"] = _result.duplicate(true)
		_enqueue_silent_order(task_id)

	tasks_updated.emit()

	_ensure_development_task_supply()

#endregion


## post_task_handler 是任务模板里 result 完成时由 DevCycleManager 同步执行的钩子。
## 当前没有任何 handler 类型在使用；保留分发入口以便未来扩展。
func _handle_post_task_handler(task: Dictionary, result: Dictionary) -> void:
	var raw_handler: Variant = task.get("post_task_handler", {})
	if not raw_handler is Dictionary:
		return
	var handler: Dictionary = raw_handler
	var handler_type := str(handler.get("type", "")).strip_edges()
	if handler_type.is_empty():
		return
	push_warning("[DevCycleManager] Unknown post_task_handler type: %s (task=%s, result_kind=%s)" % [
		handler_type,
		str(task.get("task_id", "")),
		str(result.get("result_kind", "")),
	])


#region ──── 时间事件 ────

## 时段变化 → 解锁新任务，并清除上一时段的 dev_work 拒绝状态
func _on_phase_changed(_new_phase: int) -> void:
	_dev_work_refused_this_phase = ""
	tasks_updated.emit()


## 日变化 → 解锁新任务，并清除上一时段的 dev_work 拒绝状态
func _on_day_changed(_new_day: int) -> void:
	_dev_work_refused_this_phase = ""
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
	if str(task.get("task_type", "")) == "chat_topic" or str(task.get("minigame_type", "")) == "creative_decision":
		return DEFAULT_CHAT_STRESS_LOAD
	return DEFAULT_DEV_STRESS_LOAD


func _get_default_passion_cost(task: Dictionary) -> int:
	if str(task.get("task_type", "")) == "chat_topic" or str(task.get("minigame_type", "")) == "creative_decision":
		return DEFAULT_CHAT_PASSION_COST
	return DEFAULT_DEV_PASSION_COST

#endregion


#region ──── 动态计划生成 ────

## 读取 KB 概念文档 → 构建 prompt → 调用 LLM
func _generate_development_plan() -> void:
	_plan_generating = true

	# KB 索引摘要：只给 doc_id / 标题 / 分类 / state / 首行，不给全文。
	# 这样模型必须调 kb_read 或 kb_summarize_state 才能引用具体内容，
	# 强制激活工具循环；同时保住 prompt cache 命中（索引比全文稳定）。
	var kb_content: String = _build_kb_index_text()
	if kb_content.is_empty():
		push_warning("[DevCycleManager] KB is empty, using minimal context for plan generation")
		kb_content = "（暂无概念设计文档，请生成一份通用的日式异世界 AVG 开发计划）"
	kb_content += "\n\n上面只是索引。编写任何 `post_task_work_order.description` 之前，至少 `kb_read` 一次你打算引用的具体 doc，或 `kb_summarize_state` 再看一遍最新状态。"

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


## PlanningManager 返回扁平开发任务列表
func _on_development_plan_completed(request_id: String, success: bool, tasks: Array, raw_output: String) -> void:
	if request_id != _plan_gen_request_id:
		return

	_cleanup_plan_gen_ai()

	if success:
		_print_generated_tasks("[DevCycle][development_plan]", tasks)
		var injected: int = inject_planned_tasks(tasks)
		_plan_generated = true
		_plan_generating = false
		print("[DevCycleManager] Development batch generated via PlanningManager: %d planned tasks registered" % injected)
		_notify_dev_work_plan_ready(injected)
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


#region ──── 计划批次工具 ────

func _print_generated_tasks(prefix: String, tasks: Array) -> void:
	print("%s total=%d" % [prefix, tasks.size()])
	for i in tasks.size():
		var t: Dictionary = tasks[i] if tasks[i] is Dictionary else {}
		var title: String = str(t.get("title", "")).strip_edges()
		var task_type: String = str(t.get("task_type", "")).strip_edges()
		var wo: Dictionary = t.get("post_task_work_order", {}) if t.get("post_task_work_order") is Dictionary else {}
		var wo_title: String = str(wo.get("title", "")).strip_edges()
		var wo_desc: String = str(wo.get("description", "")).strip_edges()
		print("%s [%d] %s (type=%s) → wo=%s" % [prefix, i, title, task_type, wo_title])
		if not wo_desc.is_empty():
			for line in wo_desc.split("\n"):
				print("%s     %s" % [prefix, line])


func _are_task_prerequisites_met(task: Dictionary) -> bool:
	var prereqs: Variant = task.get("prerequisites", [])
	if not prereqs is Array:
		return true
	for raw_prereq in prereqs:
		var prereq_id: String = str(raw_prereq).strip_edges()
		if prereq_id.is_empty():
			continue
		if prereq_id not in _completed_task_ids:
			return false
	return true


## 构建 KB 索引摘要：每个文档一行 `[category] doc_id — title (state=..., updated=...)`，
## 再附首行 ~120 字摘要。不含正文。让 Planner 必须用工具拉全文才能引用具体内容。
func _build_kb_index_text() -> String:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_documents"):
		return ""

	var docs: Array = kb.get_documents()
	if docs.is_empty():
		return ""

	var lines: PackedStringArray = ["## KB 索引（只列条目，不含正文）"]
	for doc in docs:
		if not doc is Dictionary:
			continue
		var doc_id: String = str(doc.get("doc_id", ""))
		var title: String = str(doc.get("title", ""))
		var category: String = str(doc.get("category", ""))
		var state: String = str(doc.get("state", ""))
		var updated_at: String = str(doc.get("updated_at", ""))
		var meta_parts: PackedStringArray = []
		if not state.is_empty():
			meta_parts.append("state=%s" % state)
		if not updated_at.is_empty():
			meta_parts.append("updated=%s" % updated_at)
		var meta_text: String = ""
		if meta_parts.size() > 0:
			meta_text = "（%s）" % ", ".join(meta_parts)

		lines.append("- [%s] %s — %s%s" % [category, doc_id, title, meta_text])

		var content: String = str(doc.get("content", ""))
		if content.is_empty():
			continue
		var newline_idx: int = content.find("\n")
		var first_line: String = content if newline_idx < 0 else content.substr(0, newline_idx)
		first_line = first_line.strip_edges()
		if first_line.length() > 120:
			first_line = first_line.substr(0, 120) + "…"
		if not first_line.is_empty():
			lines.append("    > %s" % first_line)

	return "\n".join(lines)


#endregion


func _notify_dev_work_plan_ready(added_task_count: int) -> void:
	if added_task_count <= 0:
		return
	var visible_count := get_visible_tasks().size()
	var body := "新一轮开发任务已经整理好，本轮注册了 %d 个任务。" % added_task_count
	if visible_count > 0:
		body += " 当前可执行 %d 个。" % visible_count
	DesktopNotificationUtilsClass.show_hint("开发计划已更新", body, "book", 4.8)


#region ──── 动态任务注入 API ────

## 注入正式开发计划里的扁平任务列表
## 返回成功注册的任务数量
func inject_planned_tasks(tasks: Array) -> int:
	var count: int = 0
	for task_def in tasks:
		if count >= DEVELOPMENT_BATCH_MAX_COUNT:
			break
		if not task_def is Dictionary:
			continue
		var title: String = str(task_def.get("title", "")).strip_edges()
		if not title.is_empty() and _task_title_exists_in_runtime(title):
			continue
		var added_id := add_dynamic_task(task_def)
		if added_id.is_empty():
			continue
		count += 1
	if count > 0:
		tasks_updated.emit()
	return count


func _count_pending_runtime_tasks() -> int:
	var count: int = 0
	for task_id in _task_pool:
		var task: Dictionary = _task_pool[task_id]
		var status: String = str(task.get("status", "")).strip_edges()
		if status in ["completed", "failed"]:
			continue
		count += 1
	return count


## 任务池快空就续杯一批 dev work：
## 也是首次 plan_generation 的触发点——开场立项讨论的 worker 工单完成后触发。
func _ensure_development_task_supply() -> void:
	if _plan_generating:
		return
	if not _active_task_id.is_empty() or not _order_queue.is_empty():
		return
	var pending_count := _count_pending_runtime_tasks()
	if pending_count > DEVELOPMENT_BATCH_TRIGGER_PENDING_COUNT:
		return
	print("[DevCycleManager] Pending dev tasks low (%d), generating next development batch..." % pending_count)
	_generate_development_plan()


func _task_title_exists_in_runtime(title: String) -> bool:
	for task_id in _task_pool:
		var task: Dictionary = _task_pool[task_id]
		if str(task.get("title", "")).strip_edges() == title:
			return true
	return false


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

	var task: Dictionary = _normalize_runtime_task_shape(task_def)
	if not task.has("_surface_sequence"):
		task["_surface_sequence"] = _task_surface_sequence_counter
		_task_surface_sequence_counter += 1
	if not task.has("_surface_priority"):
		task["_surface_priority"] = 0
	task["status"] = "available"
	_task_pool[task_id] = task

	# 不加入 _chapter_plans（动态任务独立于章节体系）
	tasks_updated.emit()
	print("[DevCycleManager] Dynamic task added: %s (%s) type=%s" % [
		task_id,
		str(task.get("title", "")),
		_describe_task_runtime_type(task),
	])
	return task_id


func _normalize_runtime_task_shape(task_def: Dictionary) -> Dictionary:
	var task: Dictionary = task_def.duplicate(true)
	var post_task_work_order := _extract_post_task_work_order(task)
	if not post_task_work_order.is_empty():
		if not post_task_work_order.has("performance_context") and str(task.get("minigame_type", "")).strip_edges() == DEFAULT_PRODUCTION_MINIGAME_TYPE:
			post_task_work_order["performance_context"] = "summary"
		task["post_task_work_order"] = post_task_work_order

	var task_type: String = str(task.get("task_type", "")).strip_edges()
	# 向后兼容：旧的 chat_topic 转换为 creative_decision 小游戏
	if task_type == "chat_topic":
		task["task_type"] = "minigame"
		task["minigame_type"] = "creative_decision"
		if post_task_work_order.is_empty():
			var tc: Dictionary = task.get("topic_config", {})
			var kb_cat: String = str(tc.get("kb_category", "notes"))
			post_task_work_order = {
				"title": "整理讨论结果：%s" % str(task.get("title", "")),
				"description": "将讨论中确认的内容整理到知识库。只处理 %s 维度，越界内容一律保留待定。" % kb_cat,
				"kb_sources": [kb_cat],
				"performance_context": "summary",
			}
			task["post_task_work_order"] = post_task_work_order
		return task

	var minigame_type: String = str(task.get("minigame_type", "")).strip_edges()
	if task_type == "minigame" or not minigame_type.is_empty() or not post_task_work_order.is_empty():
		task["task_type"] = "minigame"
		if minigame_type.is_empty():
			task["minigame_type"] = DEFAULT_PRODUCTION_MINIGAME_TYPE
		if not post_task_work_order.is_empty() and not post_task_work_order.has("performance_context") and str(task.get("minigame_type", "")).strip_edges() == DEFAULT_PRODUCTION_MINIGAME_TYPE:
			post_task_work_order["performance_context"] = "summary"
			task["post_task_work_order"] = post_task_work_order
	return task


func _extract_post_task_work_order(task: Dictionary) -> Dictionary:
	var direct_template: Variant = task.get("post_task_work_order", {})
	if direct_template is Dictionary and not (direct_template as Dictionary).is_empty():
		return (direct_template as Dictionary).duplicate(true)

	var legacy_template: Variant = task.get("work_order_template", {})
	if legacy_template is Dictionary and not (legacy_template as Dictionary).is_empty():
		return (legacy_template as Dictionary).duplicate(true)

	return {}


func _get_post_task_work_order(task: Dictionary) -> Dictionary:
	var direct_template: Variant = task.get("post_task_work_order", {})
	if direct_template is Dictionary and not (direct_template as Dictionary).is_empty():
		return direct_template as Dictionary

	var legacy_template: Variant = task.get("work_order_template", {})
	if legacy_template is Dictionary and not (legacy_template as Dictionary).is_empty():
		return legacy_template as Dictionary

	return {}


func _resolve_task_minigame_type(task: Dictionary) -> String:
	var explicit_type: String = str(task.get("minigame_type", "")).strip_edges()
	if not explicit_type.is_empty():
		return explicit_type
	if task.has("_auto_order_resource"):
		return ""
	if not _get_post_task_work_order(task).is_empty():
		return DEFAULT_PRODUCTION_MINIGAME_TYPE
	return ""


func _describe_task_runtime_type(task: Dictionary) -> String:
	var task_type: String = str(task.get("task_type", "")).strip_edges()
	if task_type == "chat_topic":
		return "minigame:creative_decision"
	var minigame_type: String = _resolve_task_minigame_type(task)
	if not minigame_type.is_empty():
		return "minigame:%s" % minigame_type
	if not _get_post_task_work_order(task).is_empty():
		return "work_order"
	return "simple"


## 查询计划是否已生成
func is_plan_generated() -> bool:
	return _plan_generated


## 查询计划是否正在生成中
func is_plan_generating() -> bool:
	return _plan_generating


func get_recent_completed_tasks(limit: int = 6) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(_completed_task_ids.size() - 1, -1, -1):
		var task_id: String = _completed_task_ids[i]
		var task: Dictionary = _task_pool.get(task_id, {})
		if task.is_empty():
			continue
		result.append({
			"task_id": task_id,
			"title": str(task.get("title", "")),
			"runtime_type": _describe_task_runtime_type(task),
			"source": str(task.get("_source", "")),
		})
		if result.size() >= limit:
			break
	return result


func get_next_planning_rhythm_hint() -> String:
	var recent_tasks := get_recent_completed_tasks(4)
	for item in recent_tasks:
		var runtime_type: String = str(item.get("runtime_type", "")).strip_edges()
		if runtime_type == "minigame:creative_decision":
			return "最近刚完成的是 KB/讨论任务。下一批默认应以执行/产出任务为主，只在知识库明确暴露真实阻塞缺口时夹带 1 个 creative_decision。"
		if runtime_type.begins_with("minigame"):
			return "最近刚完成的是执行/产出任务。下一批只有在知识库明确暴露真实阻塞缺口时才补 1 个 creative_decision，否则继续给可落地执行任务。"
	return "保持小步快跑：每次只给 2 到 3 个任务，不要连续堆叠多个同类型任务。"

#endregion


#region ──── 底层上浮回调 ────

## 底层 agent 请求创意讨论 → 创建动态 creative_decision 任务
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
			"你是林夏，{player_name}的叙事大赛搭档。\n"
			+ "你在开发过程中发现需要和搭档讨论一下：%s\n\n" % topic
			+ "背景：%s\n\n" % description
			+ "用1-2条简短消息回应，觉得讨论已经收束时在最后加 [TOPIC_COMPLETE]\n\n"
			+ "重要：如果搭档持续说与游戏设计完全无关的内容，先委婉提醒一次'咱们还是聊正事吧'。"
			+ "如果对方继续跑题，表达不满并在末尾加 [TOPIC_FAILED]"
		)

	# 默认 stat_changes
	var stat_changes: Dictionary = context.get("stat_changes", {"quality": 3, "completion": 1})

	var task_def: Dictionary = {
		"task_id": task_id,
		"title": topic,
		"description": description,
		"task_type": "minigame",
		"minigame_type": "creative_decision",
		"stat_changes": stat_changes,
		"stress_cost": 1,
		"weight": 9,  # 高优先级显示
		"one_time": true,
		"_source": "agent_request",
		"_surface_priority": 100,
		"_requester_order_id": requester,
		"topic_config": {
			"system_prompt": sys_prompt,
			"goal_description": "与搭档讨论：%s" % topic,
			"kb_category": kb_category,
			"kb_entry_id": kb_entry_id if not kb_entry_id.is_empty() else task_id,
		},
		"post_task_work_order": {
			"title": "整理讨论结果：%s" % topic,
			"description": "将讨论中确认的内容整理到知识库。只处理 %s 维度，越界内容一律保留待定。" % kb_category,
			"kb_sources": [kb_category],
			"performance_context": "summary",
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
