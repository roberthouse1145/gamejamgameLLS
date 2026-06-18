extends Node
## WorkOrderManager Autoload
## 管理工单的CRUD操作、状态管理、AI Spec生成、与ChatManager联动

# Preload classes
const WorkOrderDataClass = preload("res://scripts/apps/work_order/work_order_data.gd")
const WorkOrderAgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")
const AVGDevContextToolsClass = preload("res://scripts/avg/dev_tools/context_tools.gd")

#region 信号
## 工单创建
signal order_created(order_id: String)
## 工单更新
signal order_updated(order_id: String)
## 工单状态变化
signal order_status_changed(order_id: String, old_status: String, new_status: String)
## Spec生成开始
signal spec_generation_started(order_id: String)
## Spec生成完成
signal spec_generation_completed(order_id: String, success: bool)
## 工单删除
signal order_deleted(order_id: String)
## 工单列表加载完成
signal orders_loaded()
## 工单发送执行
signal order_dispatched(order_id: String, assignee_npc_id: String)
# Removed unused daily_progress_settled signal
#endregion

#region 数据
## 工单字典: order_id -> WorkOrderData
var _orders: Dictionary = {}
## 下一个工单ID序号
var _next_id_num: int = 1
## AI服务引用
var _ai_service: AIService = null
## 当前正在生成Spec的工单ID
var _pending_spec_order_id: String = ""
## 当前AI请求ID
var _pending_request_id: String = ""
## 后台工单执行代理实例 (order_id -> ChatAgent)
var _worker_agents: Dictionary = {}
## 是否自动发送 worker LLM 请求；测试可关闭，仍保留 worker 实例化路径
var _worker_auto_run: bool = true
## Worker 活动时间，仅用于诊断/测试；当前不做静默重试
var _worker_last_activity_msec: Dictionary = {}
var _worker_retry_counts: Dictionary = {}
## 测试/运行态重置后保持内存模式，避免把临时工单写回模板工程
var _runtime_reset_mode: bool = false
#endregion


func _ready() -> void:
	_setup_ai_service()
	# 等待 StorageManager 加载项目后再加载工单
	StorageManager.current_project_changed.connect(_on_project_changed)
	if StorageManager.current_project != null:
		_load_orders_from_project()


func _setup_ai_service() -> void:
	_ai_service = AIService.new()
	_ai_service.name = "WorkOrderAIService"
	add_child(_ai_service)
	
	# 加载AI配置
	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		config_mgr.apply_to_service(_ai_service, "work_order")
	
	# 连接信号
	_ai_service.request_completed.connect(_on_ai_request_completed)
	_ai_service.request_failed.connect(_on_ai_request_failed)


func _on_project_changed(_project: Resource) -> void:
	_runtime_reset_mode = false
	_load_orders_from_project()
	# 存档恢复：检查并重启被中断的 LLM 生成
	if _worker_auto_run:
		call_deferred("resume_pending_generations")


func reset_runtime_state() -> void:
	for order_id in _worker_agents.keys():
		_cleanup_worker(str(order_id))
	_orders.clear()
	_next_id_num = 1
	_pending_spec_order_id = ""
	_pending_request_id = ""
	_worker_last_activity_msec.clear()
	_worker_retry_counts.clear()
	_runtime_reset_mode = true
	orders_loaded.emit()


#region 工单CRUD

## 创建新工单
func create_order(title: String, description: String = "", metadata: Dictionary = {}) -> Resource:
	var order := WorkOrderDataClass.new()
	order.id = "wo_%d" % _next_id_num
	_next_id_num += 1
	order.title = title
	order.description = description
	order.assignee_npc_id = str(metadata.get("assignee_npc_id", metadata.get("assignee", "")))
	order.source_type = str(metadata.get("source_type", ""))
	order.source_id = str(metadata.get("source_id", ""))
	order.metadata = metadata.duplicate(true)
	order.status = "draft"
	order.created_at = int(Time.get_unix_time_from_system())
	order.updated_at = order.created_at
	
	_orders[order.id] = order
	_save_orders_to_project()
	order_created.emit(order.id)
	return order


## 获取工单
func get_order(order_id: String) -> Resource:
	return _orders.get(order_id)


## 获取所有工单
func get_all_orders() -> Array:
	var result: Array = []
	for order in _orders.values():
		result.append(order)
	# 按更新时间倒序排列
	result.sort_custom(func(a: Resource, b: Resource) -> bool:
		return a.updated_at > b.updated_at
	)
	return result


## 获取指定状态的工单
func get_orders_by_status(status: String) -> Array:
	var result: Array = []
	for order in _orders.values():
		if order.status == status:
			result.append(order)
	return result


## 更新工单
func update_order(order_id: String, data: Dictionary) -> bool:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return false
	
	if data.has("title"):
		order.title = data.title
	if data.has("description"):
		order.description = data.description
	if data.has("assignee_npc_id"):
		order.assignee_npc_id = data.assignee_npc_id
	if data.has("priority"):
		order.priority = data.priority
	if data.has("spec"):
		order.spec = data.spec
	
	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()
	order_updated.emit(order_id)
	return true


## 设置工单状态
func set_order_status(order_id: String, new_status: String) -> bool:
	var order = _orders.get(order_id)
	if order == null:
		return false
	
	var old_status: String = order.status
	if old_status == new_status:
		return true
	
	order.status = new_status
	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()
	order_status_changed.emit(order_id, old_status, new_status)
	return true


## 删除工单
func delete_order(order_id: String) -> bool:
	if not _orders.has(order_id):
		return false
	
	_orders.erase(order_id)
	_save_orders_to_project()
	order_deleted.emit(order_id)
	return true


## 设置任务完成状态
func set_task_done(order_id: String, task_index: int, done: bool) -> bool:
	var order = _orders.get(order_id)
	if order == null:
		return false
	
	var tasks: Array = order.spec.get("tasks", [])
	if task_index < 0 or task_index >= tasks.size():
		return false
	
	tasks[task_index]["done"] = done
	order.spec["tasks"] = tasks
	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()
	order_updated.emit(order_id)
	return true

#endregion


#region AI Spec生成

## 请求AI生成Spec
func request_spec_generation(order_id: String) -> bool:
	var order = _orders.get(order_id)
	if order == null:
		push_warning("[WorkOrderManager] Order not found: %s" % order_id)
		return false
	
	if order.description.strip_edges().is_empty():
		push_warning("[WorkOrderManager] Order description is empty")
		return false
	
	# 设置状态
	set_order_status(order_id, "pending_spec")
	_pending_spec_order_id = order_id
	spec_generation_started.emit(order_id)
	
	# 构建prompt
	var prompt := _build_spec_prompt(order)
	var system_prompt := _get_spec_system_prompt()
	
	# 调用AI（不使用 response_format，模型会自行输出JSON）
	_pending_request_id = _ai_service.chat_simple(prompt, system_prompt)
	print("[WorkOrderManager] Spec generation requested for %s, request_id=%s" % [order_id, _pending_request_id])
	return true


func _get_spec_system_prompt() -> String:
	# 尝试从PromptManager加载
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm and pm.has_method("resolve"):
		var prompt: String = pm.resolve("work_order_spec")
		if not prompt.is_empty():
			return prompt
	
	# 默认系统prompt
	return """你是一个AVG游戏开发助手，负责将玩家的需求转化为清晰的工单规格说明。

## 输出格式
请以JSON格式输出，包含以下字段：
{
  "requirements_text": "需求整理文档（Markdown格式，包含目标、涉及内容、预期效果）",
  "tasks": [
	{"description": "任务1描述", "done": false},
	{"description": "任务2描述", "done": false}
  ]
}

## 任务拆解原则
1. 每个任务应该是一个具体的、可执行的操作
2. 任务顺序应该符合执行逻辑
3. 通常最后一个任务是"保存项目"
4. 任务数量控制在3-6个为宜

## 注意事项
- 不要添加玩家没有提到的功能
- 使用简洁清晰的语言
- 任务描述应该让AI Agent能够理解并执行"""


func _build_spec_prompt(order: Resource) -> String:
	var parts: PackedStringArray = []
	
	# 工单基本信息
	parts.append("## 工单信息")
	parts.append("标题：%s" % order.title)
	parts.append("描述：%s" % order.description)
	
	# 项目上下文
	var project: Resource = StorageManager.current_project
	if project != null:
		parts.append("\n## 项目上下文")
		parts.append("项目名称：%s" % project.project_name)
		parts.append("分辨率：%dx%d" % [project.resolution.x, project.resolution.y])
		
		# 场景列表
		if project.scenes.size() > 0:
			parts.append("\n### 现有场景")
			for i in range(min(project.scenes.size(), 10)):
				var scene: Resource = project.scenes[i]
				if scene:
					var scene_name: String = scene.scene_name if "scene_name" in scene else "未命名"
					var scene_id: String = scene.scene_id if "scene_id" in scene else ""
					parts.append("- %s (%s)" % [scene_name, scene_id])
		
		# 角色列表 (characters 是 Array，不是 Dictionary)
		if project.characters.size() > 0:
			parts.append("\n### 现有角色")
			for char_data in project.characters:
				if char_data:
					var char_name: String = char_data.display_name if "display_name" in char_data else "未命名"
					var char_id: String = char_data.character_id if "character_id" in char_data else ""
					parts.append("- %s (%s)" % [char_name, char_id])
	
	parts.append("\n请根据以上信息，生成工单的Spec。")
	return "\n".join(parts)


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_request_id:
		return
	
	_pending_request_id = ""
	var order_id := _pending_spec_order_id
	_pending_spec_order_id = ""
	
	if order_id.is_empty():
		return
	
	# 解析响应
	var content: String = AIService.extract_content(response)
	if content.is_empty():
		push_warning("[WorkOrderManager] Empty AI response")
		set_order_status(order_id, "draft")
		spec_generation_completed.emit(order_id, false)
		return
	
	# 智能提取并解析JSON
	var json_result: Variant = _extract_json_from_response(content)
	if json_result == null or not json_result is Dictionary:
		push_warning("[WorkOrderManager] Failed to parse JSON from response: %s" % content.left(300))
		set_order_status(order_id, "draft")
		spec_generation_completed.emit(order_id, false)
		return
	
	# 更新工单Spec
	var order = _orders.get(order_id)
	if order == null:
		return
	
	order.spec["requirements_text"] = json_result.get("requirements_text", "")
	order.spec["tasks"] = json_result.get("tasks", [])
	order.updated_at = int(Time.get_unix_time_from_system())
	
	set_order_status(order_id, "ready")
	_save_orders_to_project()
	order_updated.emit(order_id)
	spec_generation_completed.emit(order_id, true)
	print("[WorkOrderManager] Spec generated for %s" % order_id)


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _pending_request_id:
		return
	
	_pending_request_id = ""
	var order_id := _pending_spec_order_id
	_pending_spec_order_id = ""
	
	push_warning("[WorkOrderManager] AI request failed: %s" % error)
	if not order_id.is_empty():
		set_order_status(order_id, "draft")
		spec_generation_completed.emit(order_id, false)

#endregion


#region 发送执行 & 双层状态管理

## 派发工单 (由知识库或自动流程触发)
## 设置双层状态并启动后台 LLM
## required_ap: 表层需要玩家投入的总 AP
## dispatch_day: 当前游戏天数
func dispatch_order(order_id: String, required_ap: int = 3, dispatch_day: int = 1) -> bool:
	var order = _orders.get(order_id)
	if order == null:
		push_warning("[WorkOrderManager] Order not found: %s" % order_id)
		return false

	if order.assignee_npc_id.is_empty():
		order.assignee_npc_id = "npc_lin_xia"

	# --- 设置双层状态 ---
	order.surface_status = "pending" # 表层在任务列表里等待玩家投入 AP
	order.current_progress_ap = 0
	order.required_ap = required_ap
	order.inner_status = "generating" if _worker_agents.is_empty() else "idle"
	order.dispatch_day = dispatch_day

	# 同步旧 status 字段
	set_order_status(order_id, "pending")

	print("[WorkOrderManager] 工单派发: %s -> %s  (需投入: %d AP)" % [order_id, order.assignee_npc_id, required_ap])
	order_dispatched.emit(order_id, order.assignee_npc_id)

	if _worker_agents.is_empty():
		_spawn_worker_agent_for_order(order_id, order.assignee_npc_id, order.title)
	else:
		print("[WorkOrderManager] 已有工单 Worker 运行，排队等待: %s" % order_id)
	_save_orders_to_project()
	return true


## 原有发送接口 (向后兼容，内部转发到 dispatch_order)
func send_order(order_id: String) -> bool:
	var game_loop: Node = get_node_or_null("/root/GameLoopManager")
	var day: int = game_loop.current_day if game_loop else 1
	return dispatch_order(order_id, 2, day)


func finish_order(order_id: String) -> bool:
	return _mark_order_completed(order_id)


## 每日进度推进 (保留接口以配合未来扩展)
## (在新逻辑下，不再每天自动减天数，而是由玩家主动消耗 AP 推进 progress_ap。这里保留接口以配合未来扩展)
func advance_daily_progress() -> Array:
	return []

## 玩家主动花费 AP 推进某个工单的进度
func progress_order(order_id: String, ap_spent: int = 1) -> bool:
	var order = _orders.get(order_id)
	if order == null:
		return false
	
	if order.surface_status != "pending" and order.surface_status != "in_progress":
		return false
		
	order.surface_status = "in_progress"
	order.current_progress_ap += ap_spent
	print("[WorkOrderManager] 工单 %s 进度提升: %d/%d" % [order_id, order.current_progress_ap, order.required_ap])
	
	# 如果 AP 投入已满
	if order.current_progress_ap >= order.required_ap:
		if order.inner_status == "ready":
			# Worker 已直接写入引擎，标记完成
			_mark_order_completed(order_id)
			return true
		else:
			# Worker 还在生成中（罕见情况: 玩家扣 AP 太快）
			print("[WorkOrderManager] 工单 %s AP已满，但Worker尚未完成，等待" % order_id)
			return true
			
	_save_orders_to_project()
	order_updated.emit(order_id)
	return true
	
## 标记工单为完成状态（Worker 已直接写入引擎，无需额外操作）
func _mark_order_completed(order_id: String) -> bool:
	var order = _orders.get(order_id)
	if not order:
		return false
	
	var old_status: String = str(order.status)
	order.surface_status = "completed"
	order.status = "completed"
	order.inner_status = "ready"
	order.updated_at = int(Time.get_unix_time_from_system())
	print("[WorkOrderManager] 工单完成交付: %s" % order_id)
	order_status_changed.emit(order_id, old_status, "completed")
	_cleanup_worker(order_id)
	_save_orders_to_project()
	if _worker_auto_run:
		call_deferred("resume_pending_generations")
	return true


func _mark_order_failed(order_id: String, error: String) -> bool:
	var order = _orders.get(order_id)
	if not order:
		return false

	var old_status: String = str(order.status)
	order.surface_status = "failed"
	order.status = "failed"
	order.inner_status = "failed"
	order.updated_at = int(Time.get_unix_time_from_system())
	if "metadata" in order:
		order.metadata["last_error"] = error
	print("[WorkOrderManager] 工单执行失败: %s  %s" % [order_id, error])
	order_status_changed.emit(order_id, old_status, "failed")
	order_updated.emit(order_id)
	_save_orders_to_project()
	return true


## 存档恢复：重启被中断的后台 LLM 生成
func resume_pending_generations() -> void:
	if not _worker_agents.is_empty():
		return

	var resumed_count: int = 0
	var order_ids: Array = _get_generation_candidate_order_ids()
	for order_id in order_ids:
		var order = _orders[order_id]
		print("[WorkOrderManager] 恢复中断的工单: %s (inner=%s)" % [order_id, order.inner_status])
		order.inner_status = "generating"
		_spawn_worker_agent_for_order(order_id, order.assignee_npc_id, order.title)
		resumed_count += 1
		break

	if resumed_count > 0:
		print("[WorkOrderManager] 恢复了 %d 个中断的工单" % resumed_count)
		_save_orders_to_project()


func resume_order_generation(order_id: String) -> bool:
	if not _worker_agents.is_empty():
		return false
	var order: Resource = _orders.get(order_id)
	if order == null:
		return false
	if str(order.surface_status) == "completed" or str(order.inner_status) == "ready":
		return false
	order.inner_status = "generating"
	_spawn_worker_agent_for_order(order_id, order.assignee_npc_id, order.title)
	_save_orders_to_project()
	return true


func is_order_running(order_id: String) -> bool:
	return _worker_agents.has(order_id)


func get_order_queue_position(order_id: String) -> int:
	var candidate_ids: Array = _get_generation_candidate_order_ids()
	for i in range(candidate_ids.size()):
		if str(candidate_ids[i]) == order_id:
			return i + 1
	return 0


func _get_generating_order_ids(except_order_id: String = "") -> Array[String]:
	var result: Array[String] = []
	for order_id in _worker_agents.keys():
		var id: String = str(order_id)
		if not except_order_id.is_empty() and id == except_order_id:
			continue
		result.append(id)
	return result


func run_worker_watchdog_once() -> void:
	# 静默 worker 不再由 watchdog 自动重试，避免重复写入同一批项目资源。
	pass


func get_worker_retry_count(order_id: String) -> int:
	return int(_worker_retry_counts.get(order_id, 0))


func _get_generation_candidate_order_ids() -> Array:
	var order_ids: Array = []
	for order_id in _orders:
		var order: Resource = _orders[order_id]
		if order == null:
			continue
		var surface_status: String = str(order.surface_status)
		if surface_status == "completed":
			continue
		if surface_status != "pending" and surface_status != "in_progress":
			continue
		if str(order.inner_status) == "ready":
			continue
		if _worker_agents.has(order_id):
			continue
		order_ids.append(str(order_id))

	order_ids.sort_custom(func(a: String, b: String) -> bool:
		var order_a: Resource = _orders.get(a)
		var order_b: Resource = _orders.get(b)
		var created_a: int = int(order_a.created_at if order_a != null and "created_at" in order_a else 0)
		var created_b: int = int(order_b.created_at if order_b != null and "created_at" in order_b else 0)
		if created_a == created_b:
			return a < b
		return created_a < created_b
	)
	return order_ids


func _build_worker_agent_for_order(order_id: String) -> ChatAgent:
	var worker: ChatAgent = WorkOrderAgentScene.instantiate()
	worker.name = "Worker_%s" % order_id
	_worker_agents[order_id] = worker
	_worker_last_activity_msec[order_id] = Time.get_ticks_msec()

	# 日志转发
	worker.log_entry.connect(func(entry: Dictionary):
		_worker_last_activity_msec[order_id] = Time.get_ticks_msec()
		var log_type: String = entry.get("type", "info")
		var log_content: String = entry.get("content", "")
		if log_type == "error":
			push_warning("[Worker-%s] %s" % [order_id, log_content])
		else:
			print("[Worker-%s] %s" % [order_id, log_content])
	)

	# 监听完成信号 — Worker 已直接写入引擎，这里只标记 inner_status
	worker.message_completed.connect(func(_req_id: String, _content: String):
		var order = _orders.get(order_id)
		if order != null:
			order.inner_status = "ready"
			order.updated_at = int(Time.get_unix_time_from_system())
			print("[WorkOrderManager] Worker %s 完成，inner_status -> ready" % order_id)
			_save_orders_to_project()
			order_updated.emit(order_id)

			# 如果表层 AP 已经扣满，直接标记完成
			if order.current_progress_ap >= order.required_ap:
				_mark_order_completed(order_id)
			else:
				_cleanup_worker(order_id)
				if _worker_auto_run:
					call_deferred("resume_pending_generations")
	)

	worker.message_failed.connect(func(_req_id: String, error: String):
		push_warning("[WorkOrderManager] Worker %s failed: %s" % [order_id, error])
		_mark_order_failed(order_id, error)
		_cleanup_worker(order_id)
	)

	return worker


func _spawn_worker_agent_for_order(order_id: String, _npc_id: String, _title: String) -> void:
	var worker: ChatAgent = _build_worker_agent_for_order(order_id)
	add_child(worker)
	if not _worker_auto_run:
		print("[WorkOrderManager] Worker auto run disabled: %s" % order_id)
		return

	# 下发初始任务
	var prompt := _build_worker_initial_prompt(order_id)
	worker.send_message_with_options(prompt, {
		"prompt_key": "work_order_agent",
		"source": "WorkOrderManager",
		"tool_execution_policy": "read_parallel_write_serial",
	})


func _build_worker_initial_prompt(order_id: String) -> String:
	var vars: Dictionary = AVGDevContextToolsClass.build_work_order_project_index_vars()
	vars.merge(_build_worker_order_vars(order_id), true)
	var prompt_manager: Node = _get_prompt_manager()
	if prompt_manager != null and prompt_manager.has_method("resolve_with_vars"):
		if not prompt_manager.has_method("has_prompt") or prompt_manager.has_prompt("work_order_initial_task"):
			var resolved: String = str(prompt_manager.resolve_with_vars("work_order_initial_task", vars)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return _build_worker_initial_prompt_fallback(vars)


func _build_worker_initial_prompt_fallback(vars: Dictionary) -> String:
	var index_block: String = AVGDevContextToolsClass.build_work_order_project_index()
	var order_block: String = str(vars.get("work_order_order_block", "")).strip_edges()
	return "\n\n".join([
		index_block,
		"---",
		"# 当前工单（动态尾部）",
		order_block,
		"",
		"请执行上述工单。优先利用项目索引定位相关 KB、场景、变量、角色和资源；索引不是全文，缺少正文或完整 DSL 时再调用工具读取。",
	]).strip_edges()


func _build_worker_order_vars(order_id: String) -> Dictionary:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return {
			"work_order_order_id": order_id,
			"work_order_title": "",
			"work_order_description": "",
			"work_order_order_block": "- order_id: %s\n- error: 工单不存在，请调用 wo_get_order_details 再确认。" % order_id,
		}
	return {
		"work_order_order_id": str(order.id),
		"work_order_title": str(order.title),
		"work_order_description": str(order.description).strip_edges(),
		"work_order_status": str(order.status),
		"work_order_surface_status": str(order.surface_status),
		"work_order_inner_status": str(order.inner_status),
		"work_order_priority": str(int(order.priority)),
		"work_order_assignee_npc_id": str(order.assignee_npc_id),
		"work_order_source_type": str(order.source_type),
		"work_order_source_id": str(order.source_id),
		"work_order_progress_ap": "%d/%d" % [int(order.current_progress_ap), int(order.required_ap)],
		"work_order_order_block": _build_worker_order_block(order_id),
	}


func _build_worker_order_block(order_id: String) -> String:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return "- order_id: %s\n- error: 工单不存在，请调用 wo_get_order_details 再确认。" % order_id

	var lines: Array[String] = [
		"- order_id: %s" % str(order.id),
		"- title: %s" % str(order.title),
		"- status: %s / surface=%s / inner=%s" % [
			str(order.status),
			str(order.surface_status),
			str(order.inner_status),
		],
		"- priority: %d" % int(order.priority),
		"- assignee_npc_id: %s" % str(order.assignee_npc_id),
		"- source: %s:%s" % [str(order.source_type), str(order.source_id)],
		"- progress_ap: %d/%d" % [int(order.current_progress_ap), int(order.required_ap)],
	]
	var linked_ids: Array = order.linked_llm_kb_ids if "linked_llm_kb_ids" in order else []
	if not linked_ids.is_empty():
		lines.append("- linked_llm_kb_ids: %s" % ", ".join(PackedStringArray(linked_ids)))
	var parent_id: String = str(order.parent_order_id if "parent_order_id" in order else "").strip_edges()
	if not parent_id.is_empty():
		lines.append("- parent_order_id: %s" % parent_id)
	var children: Array = order.children_order_ids if "children_order_ids" in order else []
	if not children.is_empty():
		lines.append("- children_order_ids: %s" % ", ".join(PackedStringArray(children)))

	var description: String = str(order.description).strip_edges()
	if not description.is_empty():
		lines.append("")
		lines.append("## 需求描述")
		lines.append(description)

	var spec_block: String = _build_worker_spec_block(order.spec if "spec" in order else {})
	if not spec_block.is_empty():
		lines.append("")
		lines.append("## Spec")
		lines.append(spec_block)

	return "\n".join(lines).strip_edges()


func _build_worker_spec_block(spec: Dictionary) -> String:
	if spec.is_empty():
		return ""
	var lines: Array[String] = []
	var requirements: String = str(spec.get("requirements_text", "")).strip_edges()
	if not requirements.is_empty():
		lines.append("requirements_text: %s" % requirements)
	var design: String = str(spec.get("design_text", "")).strip_edges()
	if not design.is_empty():
		lines.append("design_text: %s" % design)
	var tasks: Array = spec.get("tasks", [])
	if not tasks.is_empty():
		lines.append("tasks:")
		for i in range(tasks.size()):
			var task: Variant = tasks[i]
			if task is Dictionary:
				var task_dict: Dictionary = task
				lines.append("- [%s] %s" % [
					"x" if bool(task_dict.get("done", false)) else " ",
					str(task_dict.get("description", "")).strip_edges(),
				])
			else:
				lines.append("- [ ] %s" % str(task).strip_edges())
	return "\n".join(lines).strip_edges()


func _get_prompt_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PromptManager")


## 清理已完成的 Worker Agent
func _cleanup_worker(order_id: String) -> void:
	var worker: Node = _worker_agents.get(order_id)
	if worker != null:
		worker.queue_free()
		_worker_agents.erase(order_id)
	_worker_last_activity_msec.erase(order_id)

#endregion


#region 数据持久化

## 从项目目录加载工单
func _load_orders_from_project() -> void:
	_orders.clear()
	_next_id_num = 1

	if _runtime_reset_mode:
		orders_loaded.emit()
		return
	
	var project_path := StorageManager.current_project_path
	if project_path.is_empty():
		orders_loaded.emit()
		return
	
	var json_path := project_path + "work_orders/data.json"
	
	if not FileAccess.file_exists(json_path):
		print("[WorkOrderManager] No work orders file found at: %s" % json_path)
		orders_loaded.emit()
		return
	
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_warning("[WorkOrderManager] Failed to open: %s" % json_path)
		orders_loaded.emit()
		return
	
	var content := file.get_as_text()
	file.close()
	
	var data: Variant = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_warning("[WorkOrderManager] Invalid JSON in: %s" % json_path)
		orders_loaded.emit()
		return
	
	_next_id_num = data.get("next_id_num", 1)
	var orders_dict: Dictionary = data.get("orders", {})
	
	for order_id in orders_dict:
		var order_data: Dictionary = orders_dict[order_id]
		var order = WorkOrderDataClass.from_dict(order_data)
		_orders[order_id] = order
	
	print("[WorkOrderManager] Loaded %d orders from %s" % [_orders.size(), json_path])
	orders_loaded.emit()


## 保存工单到项目目录
func _save_orders_to_project() -> void:
	if _runtime_reset_mode:
		return

	var project_path := StorageManager.current_project_path
	if project_path.is_empty():
		push_warning("[WorkOrderManager] No project path set")
		return
	
	var dir_path := project_path + "work_orders/"
	var json_path := dir_path + "data.json"
	
	# 确保目录存在
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_warning("[WorkOrderManager] Failed to create directory: %s" % dir_path)
			return
	
	# 构建数据
	var orders_dict: Dictionary = {}
	for order_id in _orders:
		var order = _orders[order_id]
		orders_dict[order_id] = order.to_dict()
	
	var data: Dictionary = {
		"next_id_num": _next_id_num,
		"orders": orders_dict
	}
	
	# 写入文件
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		push_warning("[WorkOrderManager] Failed to write: %s" % json_path)
		return
	
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[WorkOrderManager] Saved %d orders to %s" % [_orders.size(), json_path])

#endregion


#region 辅助函数

## 从AI响应中智能提取JSON
## 处理: ```json ... ``` 代码块、不完整JSON等情况
func _extract_json_from_response(content: String) -> Variant:
	var json_str := content.strip_edges()
	
	# 1. 尝试提取 ```json ... ``` 代码块
	var json_block_regex := RegEx.new()
	json_block_regex.compile("```(?:json)?\\s*([\\s\\S]*?)```")
	var match_result := json_block_regex.search(json_str)
	if match_result:
		json_str = match_result.get_string(1).strip_edges()
	
	# 2. 尝试找到JSON对象的起始位置
	var start_idx := json_str.find("{")
	if start_idx == -1:
		return null
	json_str = json_str.substr(start_idx)
	
	# 3. 直接尝试解析
	var result: Variant = JSON.parse_string(json_str)
	if result != null:
		return result
	
	# 4. 尝试修复不完整的JSON（补全括号）
	result = _try_fix_incomplete_json(json_str)
	return result


## 尝试修复不完整的JSON
func _try_fix_incomplete_json(json_str: String) -> Variant:
	# 统计未闭合的括号
	var open_braces := 0
	var open_brackets := 0
	var in_string := false
	var escape_next := false
	
	for i in range(json_str.length()):
		var c := json_str[i]
		if escape_next:
			escape_next = false
			continue
		if c == "\\":
			escape_next = true
			continue
		if c == "\"":
			in_string = not in_string
			continue
		if in_string:
			continue
		match c:
			"{": open_braces += 1
			"}": open_braces -= 1
			"[": open_brackets += 1
			"]": open_brackets -= 1
	
	# 如果在字符串中未闭合，先尝试闭合字符串
	if in_string:
		json_str += "\""
	
	# 补全括号
	for i in range(open_brackets):
		json_str += "]"
	for i in range(open_braces):
		json_str += "}"
	
	# 再次尝试解析
	return JSON.parse_string(json_str)

#endregion
