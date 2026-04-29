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
const CREATIVE_SEED_SOURCE_ID: String = "creative_brief"
const CREATIVE_CORE_DOC_ID: String = "creative_core"
const OPEN_DESIGN_QUESTIONS_DOC_ID: String = "open_design_questions"
const SEED_DEVELOPMENT_BACKBONE_DOC_ID: String = "seed_development_backbone"
const DEFAULT_CHAT_STRESS_LOAD: int = 4
const DEFAULT_CHAT_PASSION_COST: int = 4
const DEFAULT_DEV_STRESS_LOAD: int = 6
const DEFAULT_DEV_PASSION_COST: int = 6
const SEED_TASK_MIN_COUNT: int = 2
const SEED_FALLBACK_KB_SOURCES := ["world", "characters", "story", "notes"]
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
## 当前 seed 阶段的闸门任务（完成后才进入完整开发计划）
var _concept_gate_task_ids: Array[String] = []
## 已完成 concept task 中，仍在等待隐藏工单真正完成的任务 ID
var _concept_gate_pending_order_task_ids: Array[String] = []
## 最近一次提交的创作基点原始数据
var _latest_creative_brief: Dictionary = {}
## 第一批 dev work 生成中
var _seed_task_generating: bool = false
## 第一批 dev work 请求 ID
var _seed_task_gen_request_id: String = ""
## lab 测试捷径：跳过讨论/小游戏，直接完成任务并触发工单
var _debug_direct_execute_interactive_tasks: bool = false
## 表层任务顺序号，保证 DevWork 按 planner 顺位逐个放出
var _task_surface_sequence_counter: int = 0
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
	_plan_generated = false
	_plan_generating = false
	_concept_gate_task_ids.clear()
	_concept_gate_pending_order_task_ids.clear()
	_latest_creative_brief.clear()
	_task_surface_sequence_counter = 0
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


## 企划书提交后的桥接入口：
## 直接把原始创作基点写入 KB → 再生成第一批 dev work
## [param brief_data] 企划书数据字典，包含 game_title / game_genre / game_tags / game_outline
func on_creative_brief_completed(brief_data: Dictionary) -> void:
	_latest_creative_brief = brief_data.duplicate(true)

	if _seed_task_generating:
		print("[DevCycleManager] Creative seed pipeline already running, skipping duplicate brief bridge")
		return

	if _plan_generated or _plan_generating:
		print("[DevCycleManager] Plan already generated/generating, skipping brief bridge")
		return

	_persist_creative_brief_to_kb(brief_data)
	print("[DevCycleManager] Creative brief completed, source doc updated in KnowledgeBase")
	_generate_seed_tasks_from_context()


func _persist_creative_brief_to_kb(brief_data: Dictionary) -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("upsert_document"):
		push_warning("[DevCycleManager] KnowledgeBaseManager unavailable for creative brief persistence")
		return

	var title: String = str(brief_data.get("game_title", "")).strip_edges()
	var genre: String = str(brief_data.get("game_genre", "")).strip_edges()
	var tags: String = str(brief_data.get("game_tags", "")).strip_edges()
	var outline: String = str(brief_data.get("game_outline", "")).strip_edges()
	var content_lines: PackedStringArray = [
		"## 基本信息",
		"- 固定背景：日式魔法异世界学院",
		"- 作品名称：%s" % title,
		"- 作品类型：%s" % genre,
		"- 基调标签：%s" % tags,
		"",
		"## 故事大纲",
		outline if not outline.is_empty() else "（待补充）",
	]

	var doc_tags: Array = ["brief", "direction"]
	if not genre.is_empty() and genre not in doc_tags:
		doc_tags.append(genre)

	kb.upsert_document(
		CREATIVE_SEED_SOURCE_ID,
		"项目企划书",
		"\n".join(content_lines),
		"notes",
		doc_tags,
		"player",
		{
			"doc_kind": "brief",
			"state": "confirmed",
		}
	)

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
	_track_concept_gate_follow_up(task)

	# 静默派发/排队隐藏工单（底层，玩家不可见）
	if _active_task_id.is_empty():
		_dispatch_order_silently(task_id)
	else:
		_order_queue.append(task_id)
		print("[DevCycleManager] Order queued: %s (queue size: %d)" % [task_id, _order_queue.size()])

	tasks_updated.emit()
	_check_concept_completion()
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
	_track_concept_gate_follow_up(task, {"chat_task": true, "work_order_created": true})

	if _active_task_id.is_empty():
		_dispatch_order_silently(task_id)
	else:
		_order_queue.append(task_id)
		print("[DevCycleManager] Debug chat-topic order queued: %s (queue size: %d)" % [task_id, _order_queue.size()])

	tasks_updated.emit()
	_check_concept_completion()
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
	_check_concept_completion()
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
		if wom.has_method("is_order_running") and wom.is_order_running(order.id):
			_active_task_id = task_id
			_active_order_id = order.id
			print("[DevCycleManager] Silently dispatched order %s for task %s" % [order.id, task_id])
		else:
			print("[DevCycleManager] Order queued in WorkOrderManager: %s (task: %s)" % [order.id, task_id])
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
	var creative_prompt: String = str(completion_result.get("creative_prompt", "")).strip_edges()
	if not creative_prompt.is_empty():
		return creative_prompt
	return ""


## 工单状态变化回调（底层静默处理，不通知玩家）
func _on_order_status_changed(order_id: String, _old_status: String, new_status: String) -> void:
	_sync_concept_gate_follow_up_state(order_id, new_status)

	if order_id != _active_order_id:
		return
	if new_status not in ["completed", "needs_input", "pending", "failed"]:
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
		_track_concept_gate_follow_up(task, _result)
		task["_last_completion_result"] = _result.duplicate(true)
		_enqueue_silent_order(task_id)
	elif bool(_result.get("chat_task", false)) and bool(_result.get("work_order_created", false)):
		_track_concept_gate_follow_up(task, _result)

	tasks_updated.emit()

	# 检查概念期是否全部完成 → 触发计划生成
	_check_concept_completion()
	_ensure_development_task_supply()

#endregion


func _handle_post_task_handler(task: Dictionary, result: Dictionary) -> void:
	var raw_handler: Variant = task.get("post_task_handler", {})
	if not raw_handler is Dictionary:
		return
	var handler: Dictionary = raw_handler
	var handler_type := str(handler.get("type", "")).strip_edges()
	match handler_type:
		"creative_brief_completed":
			_handle_creative_brief_form_result(result)


func _handle_creative_brief_form_result(result: Dictionary) -> void:
	if str(result.get("result_kind", "")) != "structured_form":
		return
	var values: Dictionary = result.get("form_values", {})
	if values.is_empty():
		push_warning("[DevCycleManager] Creative brief form result has no form_values")
		return

	var tags_value: Variant = values.get("game_tags", [])
	var tags_text := _format_form_value_for_brief(tags_value)
	var brief_data: Dictionary = {
		"game_title": str(values.get("game_title", "")).strip_edges(),
		"game_genre": str(values.get("game_genre", "")).strip_edges(),
		"game_tags": tags_text,
		"game_outline": str(values.get("game_outline", "")).strip_edges(),
	}

	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("set_variable"):
		story_director.set_variable("game_title", brief_data["game_title"])
		story_director.set_variable("game_genre", brief_data["game_genre"])
		story_director.set_variable("game_tags", brief_data["game_tags"])
		story_director.set_variable("creative_brief_submitted", true)

	on_creative_brief_completed(brief_data)


func _format_form_value_for_brief(value: Variant) -> String:
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				parts.append(text)
		return ", ".join(parts)
	return str(value).strip_edges()


#region ──── 时间事件 ────

## 时段变化 → 解锁新任务
func _on_phase_changed(_new_phase: int) -> void:
	tasks_updated.emit()


## 日变化 → 解锁新任务
func _on_day_changed(_new_day: int) -> void:
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

## 概念期任务全部完成 → 读取 KB → 调用 LLM 生成开发计划
func _check_concept_completion() -> void:
	if _plan_generated or _plan_generating:
		return
	if _seed_task_generating:
		return
	if _concept_gate_task_ids.is_empty():
		return

	for cid in _concept_gate_task_ids:
		if cid not in _completed_task_ids:
			return  # 还有概念任务未完成
		if cid in _concept_gate_pending_order_task_ids:
			return  # 对应隐藏工单仍未真正完成

	print("[DevCycleManager] All concept tasks and follow-up orders completed, generating development plan...")
	_generate_development_plan()


func _track_concept_gate_follow_up(task: Dictionary, completion_result: Dictionary = {}) -> void:
	var task_id: String = str(task.get("task_id", "")).strip_edges()
	if task_id.is_empty() or task_id not in _concept_gate_task_ids:
		return
	if not _concept_task_requires_follow_up_completion(task, completion_result):
		return
	if task_id not in _concept_gate_pending_order_task_ids:
		_concept_gate_pending_order_task_ids.append(task_id)


func _concept_task_requires_follow_up_completion(task: Dictionary, completion_result: Dictionary = {}) -> bool:
	if task.is_empty():
		return false
	if not _get_post_task_work_order(task).is_empty():
		return true
	if bool(completion_result.get("chat_task", false)):
		return bool(completion_result.get("work_order_created", false))
	return false


func _sync_concept_gate_follow_up_state(order_id: String, new_status: String) -> void:
	if new_status != "completed":
		return

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null or not wom.has_method("get_order"):
		return

	var order: Resource = wom.get_order(order_id)
	if order == null:
		return
	if str(order.source_type).strip_edges() != "dev_task":
		return

	var task_id: String = str(order.source_id).strip_edges()
	if task_id.is_empty() or task_id not in _concept_gate_task_ids:
		return

	if task_id in _concept_gate_pending_order_task_ids:
		_concept_gate_pending_order_task_ids.erase(task_id)
	_check_concept_completion()


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


## PlanningManager 返回扁平开发任务列表
func _on_development_plan_completed(request_id: String, success: bool, tasks: Array, raw_output: String) -> void:
	if request_id != _plan_gen_request_id:
		return

	_cleanup_plan_gen_ai()

	if success:
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


#region ──── 创作基点 → 第一批 Dev Work ────

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
			_notify_seed_tasks_ready(added_count)
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

	var normalized_tasks := _normalize_seed_task_batch(raw_tasks)
	if normalized_tasks.size() < SEED_TASK_MIN_COUNT:
		for fallback_task in _build_seed_task_fallbacks():
			var fallback_id := str(fallback_task.get("task_id", "")).strip_edges()
			var fallback_title := str(fallback_task.get("title", "")).strip_edges()
			if _seed_task_id_exists(normalized_tasks, fallback_id):
				continue
			if _seed_task_title_exists(normalized_tasks, fallback_title):
				continue
			normalized_tasks.append(fallback_task.duplicate(true))

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


func _normalize_seed_task_batch(raw_tasks: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var used_ids: Dictionary = {}
	for i in range(raw_tasks.size()):
		if not raw_tasks[i] is Dictionary:
			continue
		var task := _normalize_seed_task(raw_tasks[i], i, used_ids)
		if task.is_empty():
			continue
		normalized.append(task)
		used_ids[task["task_id"]] = true
	return normalized


func _normalize_seed_task(raw_task: Dictionary, index: int, used_ids: Dictionary) -> Dictionary:
	var title: String = str(raw_task.get("title", "")).strip_edges()
	var description: String = str(raw_task.get("description", "")).strip_edges()
	if title.is_empty() or description.is_empty():
		return {}

	var task_id: String = str(raw_task.get("task_id", "")).strip_edges()
	if task_id.is_empty():
		task_id = "seed_generated_%02d" % (index + 1)
	if used_ids.has(task_id):
		task_id = "%s_%02d" % [task_id, index + 1]

	var normalized: Dictionary = {
		"task_id": task_id,
		"title": title,
		"description": description,
		"weight": int(raw_task.get("weight", 9)),
		"stress_cost": int(raw_task.get("stress_cost", 1)),
		"one_time": bool(raw_task.get("one_time", true)),
		"stat_changes": _normalize_seed_stat_changes(raw_task.get("stat_changes", {}), raw_task),
	}

	if raw_task.has("passion_cost"):
		normalized["passion_cost"] = int(raw_task.get("passion_cost", 0))

	var prerequisites: Array = []
	if raw_task.get("prerequisites", []) is Array:
		for raw_prereq in raw_task.get("prerequisites", []):
			var prereq_id := str(raw_prereq).strip_edges()
			if prereq_id.is_empty():
				continue
			prerequisites.append(prereq_id)
	if not prerequisites.is_empty():
		normalized["prerequisites"] = prerequisites

	var task_type: String = str(raw_task.get("task_type", "")).strip_edges()
	var has_topic_config: bool = raw_task.get("topic_config", {}) is Dictionary and not (raw_task.get("topic_config", {}) as Dictionary).is_empty()
	var raw_post_task_work_order := _extract_post_task_work_order(raw_task)
	var has_post_task_work_order: bool = not raw_post_task_work_order.is_empty()
	var discussion_intent: bool = _looks_like_seed_discussion_intent(title, description)
	var production_intent: bool = _looks_like_seed_production_intent(title, description)

	if task_type == "chat_topic" or has_topic_config:
		if production_intent and not discussion_intent:
			push_warning("[DevCycleManager] Seed task looks production-oriented but was emitted as chat_topic: %s" % title)
		# 向后兼容：将旧的 chat_topic 转换为 creative_decision 小游戏
		normalized["task_type"] = "minigame"
		normalized["minigame_type"] = "creative_decision"
		normalized["topic_config"] = _normalize_seed_topic_config(task_id, title, description, raw_task.get("topic_config", {}))
		# 若无 post_task_work_order，基于 topic_config 自动生成
		if not has_post_task_work_order:
			var tc: Dictionary = normalized["topic_config"]
			var kb_cat: String = str(tc.get("kb_category", "notes"))
			normalized["post_task_work_order"] = {
				"title": "整理讨论结果：%s" % title,
				"description": "将讨论中确认的内容整理到知识库。只处理 %s 维度，越界内容一律保留待定。" % kb_cat,
				"kb_sources": [kb_cat],
				"performance_context": "summary",
			}
		else:
			normalized["post_task_work_order"] = _normalize_seed_work_order_template(title, description, raw_post_task_work_order)
		return normalized

	if task_type == "minigame" or not str(raw_task.get("minigame_type", "")).strip_edges().is_empty() or has_post_task_work_order:
		if discussion_intent and not production_intent:
			push_warning("[DevCycleManager] Seed task looks discussion-oriented but was emitted as minigame: %s" % title)
		var work_order_template := _normalize_seed_work_order_template(title, description, raw_post_task_work_order)
		if work_order_template.is_empty():
			return {}
		if not work_order_template.has("performance_context"):
			work_order_template["performance_context"] = "summary"
		normalized["task_type"] = "minigame"
		normalized["minigame_type"] = str(raw_task.get("minigame_type", DEFAULT_PRODUCTION_MINIGAME_TYPE)).strip_edges()
		if str(normalized.get("minigame_type", "")).is_empty():
			normalized["minigame_type"] = DEFAULT_PRODUCTION_MINIGAME_TYPE
		normalized["post_task_work_order"] = work_order_template
		return normalized

	return {}


func _normalize_seed_stat_changes(raw_changes: Variant, raw_task: Dictionary) -> Dictionary:
	if raw_changes is Dictionary and not (raw_changes as Dictionary).is_empty():
		return (raw_changes as Dictionary).duplicate(true)
	var task_type: String = str(raw_task.get("task_type", "")).strip_edges()
	var minigame_type: String = str(raw_task.get("minigame_type", "")).strip_edges()
	if task_type == "chat_topic" or raw_task.has("topic_config") or minigame_type == "creative_decision":
		return {"quality": 5, "completion": 2}
	return {"quality": 3, "completion": 6}


func _normalize_seed_topic_config(task_id: String, title: String, description: String, raw_topic: Variant) -> Dictionary:
	var topic: Dictionary = raw_topic.duplicate(true) if raw_topic is Dictionary else {}
	var goal_description: String = str(topic.get("goal_description", title)).strip_edges()
	if goal_description.is_empty():
		goal_description = title
	# 注意：旧版会在这里生成 chat_topic 风格的 system_prompt。
	# 新的 creative_decision 小游戏有自己的 DSL 规格 system prompt，
	# 这里不再注入 legacy system_prompt，交由小游戏本身决定格式。
	var system_prompt: String = str(topic.get("system_prompt", "")).strip_edges()

	var kb_category: String = str(topic.get("kb_category", "")).strip_edges().to_lower()
	if kb_category not in ["world", "characters", "story", "notes"]:
		kb_category = _infer_seed_kb_category("%s %s" % [title, description])

	var kb_entry_id: String = str(topic.get("kb_entry_id", task_id)).strip_edges()
	if kb_entry_id.is_empty():
		kb_entry_id = task_id

	return {
		"system_prompt": system_prompt,
		"goal_description": goal_description,
		"kb_category": kb_category,
		"kb_entry_id": kb_entry_id,
	}


func _normalize_seed_work_order_template(task_title: String, task_description: String, raw_template: Variant) -> Dictionary:
	if not raw_template is Dictionary:
		return {}
	var template: Dictionary = raw_template.duplicate(true)
	var title: String = str(template.get("title", task_title)).strip_edges()
	var description: String = str(template.get("description", task_description)).strip_edges()
	if title.is_empty() or description.is_empty():
		return {}

	var normalized: Dictionary = {
		"title": title,
		"description": description,
	}

	if template.get("kb_sources", []) is Array:
		var kb_sources: Array = []
		for raw_source in template.get("kb_sources", []):
			var source_name := str(raw_source).strip_edges().to_lower()
			if source_name in ["world", "characters", "story", "notes"] and source_name not in kb_sources:
				kb_sources.append(source_name)
		if not kb_sources.is_empty():
			normalized["kb_sources"] = kb_sources

	var scene_target: String = str(template.get("scene_target", "")).strip_edges()
	if not scene_target.is_empty():
		normalized["scene_target"] = scene_target

	if template.has("priority"):
		normalized["priority"] = int(template.get("priority", 3))

	if template.has("performance_context"):
		normalized["performance_context"] = str(template.get("performance_context", "none")).strip_edges().to_lower()

	return normalized


func _infer_seed_kb_category(text: String) -> String:
	var normalized := text.to_lower()
	for keyword in ["角色", "人物", "关系", "主角", "女主", "搭档"]:
		if keyword in normalized:
			return "characters"
	for keyword in ["世界", "设定", "规则", "学院", "社会", "背景"]:
		if keyword in normalized:
			return "world"
	for keyword in ["剧情", "章节", "场景", "开场", "第一幕", "第一章", "事件", "结局"]:
		if keyword in normalized:
			return "story"
	return "notes"


func _build_seed_task_fallbacks() -> Array[Dictionary]:
	var fallback_tasks: Array[Dictionary] = []

	for suggestion in _extract_seed_backbone_suggestions():
		var task := _build_seed_task_from_backbone_suggestion(suggestion, fallback_tasks.size())
		if task.is_empty():
			continue
		fallback_tasks.append(task)

	for question in _extract_seed_open_questions():
		var task := _build_seed_discussion_fallback_task(question, fallback_tasks.size())
		if task.is_empty() or _seed_task_title_exists(fallback_tasks, str(task.get("title", ""))):
			continue
		fallback_tasks.append(task)

	if fallback_tasks.size() >= SEED_TASK_MIN_COUNT:
		return fallback_tasks

	for suggestion in _build_generic_seed_fallback_suggestions():
		var task := _build_seed_task_from_backbone_suggestion(suggestion, fallback_tasks.size())
		if task.is_empty() or _seed_task_title_exists(fallback_tasks, str(task.get("title", ""))):
			continue
		fallback_tasks.append(task)

	return fallback_tasks


func _extract_seed_backbone_suggestions() -> Array[Dictionary]:
	var suggestions: Array[Dictionary] = []
	var content := _get_seed_doc_content(SEED_DEVELOPMENT_BACKBONE_DOC_ID)
	if content.is_empty():
		return suggestions

	for raw_line in content.split("\n"):
		var line := _normalize_seed_doc_line(str(raw_line))
		if line.begins_with("[discussion]"):
			var text := line.trim_prefix("[discussion]").strip_edges()
			if not text.is_empty():
				suggestions.append({"kind": "discussion", "text": text})
		elif line.begins_with("[production]"):
			var text := line.trim_prefix("[production]").strip_edges()
			if not text.is_empty():
				suggestions.append({"kind": "production", "text": text})

	return suggestions


func _extract_seed_open_questions() -> Array[String]:
	var questions: Array[String] = []
	var content := _get_seed_doc_content(OPEN_DESIGN_QUESTIONS_DOC_ID)
	if content.is_empty():
		return questions

	for raw_line in content.split("\n"):
		var line := _normalize_seed_doc_line(str(raw_line))
		if line.is_empty():
			continue
		if line.begins_with("#"):
			continue
		if line.length() < 6:
			continue
		if line in questions:
			continue
		questions.append(line)
	return questions


func _normalize_seed_doc_line(raw_line: String) -> String:
	var line := raw_line.strip_edges()
	if line.begins_with("-"):
		line = line.trim_prefix("-").strip_edges()
	if line.begins_with("*"):
		line = line.trim_prefix("*").strip_edges()
	if line.begins_with("•"):
		line = line.trim_prefix("•").strip_edges()
	var dot_index := line.find(".")
	if dot_index > 0:
		var prefix := line.substr(0, dot_index).strip_edges()
		if prefix.is_valid_int():
			line = line.substr(dot_index + 1).strip_edges()
	return line


func _get_seed_doc_content(doc_id: String) -> String:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_document"):
		return ""
	var doc: Dictionary = kb.get_document(doc_id)
	if doc.is_empty():
		return ""
	return str(doc.get("content", "")).strip_edges()


func _build_seed_task_from_backbone_suggestion(suggestion: Dictionary, index: int) -> Dictionary:
	var kind := str(suggestion.get("kind", "")).strip_edges()
	var text := str(suggestion.get("text", "")).strip_edges()
	if text.is_empty():
		return {}
	if kind == "production":
		return _build_seed_production_fallback_task(text, index)
	return _build_seed_discussion_fallback_task(text, index)


func _build_seed_discussion_fallback_task(text: String, index: int) -> Dictionary:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return {}
	var title := _format_seed_discussion_title(clean_text)
	return {
		"task_id": "seed_discuss_%02d" % (index + 1),
		"title": title,
		"description": "和林夏把这个关键问题聊清楚，再决定后面的开发怎么推进。",
		"task_type": "minigame",
		"minigame_type": "creative_decision",
		"stat_changes": {"quality": 5, "completion": 2},
		"stress_cost": 1,
		"weight": 10,
		"one_time": true,
		"topic_config": {
			"goal_description": clean_text,
			"kb_category": _infer_seed_kb_category(clean_text),
			"kb_entry_id": "seed_discussion_%02d" % (index + 1),
		},
		"post_task_work_order": {
			"title": "整理讨论结果：%s" % title,
			"description": "将讨论中确认的内容整理到知识库。只处理 %s 维度，越界内容一律保留待定。" % _infer_seed_kb_category(clean_text),
			"kb_sources": [_infer_seed_kb_category(clean_text)],
			"performance_context": "summary",
		},
	}


func _build_seed_production_fallback_task(text: String, index: int) -> Dictionary:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return {}
	var title := _format_seed_production_title(clean_text)
	return {
		"task_id": "seed_production_%02d" % (index + 1),
		"title": title,
		"description": "把当前已经够清楚的部分往前推进一步，先产出一份能继续接力的内容骨架。",
		"task_type": "minigame",
		"minigame_type": DEFAULT_PRODUCTION_MINIGAME_TYPE,
		"stat_changes": {"quality": 3, "completion": 6},
		"stress_cost": 2,
		"weight": 10,
		"one_time": true,
		"post_task_work_order": {
			"title": title,
			"description": "根据当前创作基点和已确认内容，推进这项前期制作：%s。\n\n只处理已经有信息支撑的部分；遇到真正缺口时请明确标注待定，不要擅自补完。" % clean_text,
			"kb_sources": _build_seed_work_order_sources(clean_text),
			"performance_context": "summary",
		},
	}


func _format_seed_discussion_title(text: String) -> String:
	var title := text.replace("？", "").replace("?", "").strip_edges()
	for prefix in ["讨论", "决定", "确定", "澄清", "补齐", "梳理"]:
		if title.begins_with(prefix):
			return title
	if title.length() <= 14:
		return "讨论" + title
	return title


func _format_seed_production_title(text: String) -> String:
	var title := text.replace("？", "").replace("?", "").strip_edges()
	for prefix in ["整理", "编写", "补齐", "拆出", "输出", "推进", "锁定", "收束", "搭出"]:
		if title.begins_with(prefix):
			return title
	if title.length() <= 14:
		return "推进" + title
	return title


func _build_seed_work_order_sources(text: String) -> Array:
	var category := _infer_seed_kb_category(text)
	match category:
		"characters":
			return ["characters", "notes"]
		"world":
			return ["world", "notes"]
		"story":
			return ["story", "characters", "world", "notes"]
		_:
			return SEED_FALLBACK_KB_SOURCES.duplicate()


func _seed_task_title_exists(tasks: Array[Dictionary], title: String) -> bool:
	for task in tasks:
		if str(task.get("title", "")) == title:
			return true
	return false


func _seed_task_id_exists(tasks: Array[Dictionary], task_id: String) -> bool:
	for task in tasks:
		if str(task.get("task_id", "")) == task_id:
			return true
	return false


func _looks_like_seed_discussion_intent(title: String, description: String) -> bool:
	var combined_text: String = ("%s\n%s" % [title, description]).to_lower()
	for keyword in [
		"讨论", "决定", "确定", "澄清", "拍板", "取舍", "聊清", "先定", "该选", "哪种", "哪一个", "到底是什么", "到底要不要", "先聊",
	]:
		if keyword in combined_text:
			return true
	return false


func _looks_like_seed_production_intent(title: String, description: String) -> bool:
	var combined_text: String = ("%s\n%s" % [title, description]).to_lower()
	for keyword in [
		"撰写", "编写", "整理", "收束", "输出", "补齐", "文档", "底稿", "草案", "节拍", "骨架", "设定文档", "可写", "场景",
	]:
		if keyword in combined_text:
			return true
	return false


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


func _build_generic_seed_fallback_suggestions() -> Array[Dictionary]:
	return [
		{"kind": "discussion", "text": "当前最影响开工的创作缺口到底是什么"},
		{"kind": "production", "text": "整理第一批能直接开工的内容骨架"},
		{"kind": "discussion", "text": "决定接下来一小段开发该先推进哪一步"},
	]


func _build_creative_seed_context() -> String:
	var sections: PackedStringArray = []
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb != null and kb.has_method("get_document"):
		for doc_id in [CREATIVE_SEED_SOURCE_ID, CREATIVE_CORE_DOC_ID, OPEN_DESIGN_QUESTIONS_DOC_ID, SEED_DEVELOPMENT_BACKBONE_DOC_ID]:
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


func _notify_seed_tasks_ready(added_count: int) -> void:
	if added_count <= 0:
		return
	var visible_count := get_visible_tasks().size()
	var body := "林夏整理出了 %d 个新的开发任务，先去 Dev Work 看看吧。" % added_count
	if visible_count > 0:
		body = "林夏整理出了 %d 个新的开发任务，当前先展示 %d 个可执行项。" % [added_count, visible_count]
	DesktopNotificationUtilsClass.show_hint("Dev Work 已更新", body, "document", 4.8)


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


func _ensure_development_task_supply() -> void:
	if not _plan_generated:
		return
	if _plan_generating or _seed_task_generating:
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
			"你是林夏，{player_name}的 GameJam 搭档。\n"
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
