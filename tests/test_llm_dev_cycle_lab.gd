extends Control

const BrowserAppScene = preload("res://scenes/apps/browser/browser_app.tscn")
const DevWorkAppScene = preload("res://scenes/apps/dev_work/dev_work_app.tscn")
const GamePreviewerScene = preload("res://scenes/apps/game_previewer/game_previewer.tscn")
const KnowledgeBaseAppScene = preload("res://scenes/apps/knowledge_base/knowledge_base_app.tscn")
const LinkChatAppScene = preload("res://scenes/apps/linkchat/linkchat_app.tscn")
const ProjectManagerScene = preload("res://scenes/apps/project_manager/project_manager.tscn")
const SceneEditorScene = preload("res://scenes/apps/scene_editor/scene_editor.tscn")

const TEMPLATE_NAME: String = "tutorial_project"
const BRIEF_URL: String = "gamejam://brief"
const RUNTIME_PLAYER_PROJECT_PATH: String = "user://run/player_project/"
const RUNTIME_TRUNK_PATH: String = "user://run/trunk/"

var _reset_button: Button
var _open_brief_button: Button
var _open_dev_work_button: Button
var _refill_ap_button: Button
var _next_day_button: Button
var _resume_order_button: Button
var _preview_button: Button
var _project_label: Label
var _time_label: Label
var _loop_label: Label
var _summary_view: RichTextLabel
var _orders_view: RichTextLabel
var _log_view: RichTextLabel
var _workspace_tabs: TabContainer

var _browser_app: Control
var _dev_work_app: Control
var _previewer: Control
var _linkchat_app: Control
var _knowledge_base_app: Control
var _project_editor: Control
var _scene_editor: Control

var _connected_worker_ids: Dictionary = {}
var _last_visible_task_ids: Array[String] = []


func _ready() -> void:
	_configure_lab_debug_mode(true)
	_build_ui()
	_connect_signals()
	call_deferred("_bootstrap_scene_state")


func _exit_tree() -> void:
	_configure_lab_debug_mode(false)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	var title := Label.new()
	title.text = "LLM Dev Cycle Lab"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = false
	hint.fit_content = true
	hint.scroll_active = false
	hint.custom_minimum_size.y = 94
	hint.text = "用途：人工验证 LLM 是否能从 brief 开始生成第一批 dev work，执行后触发真实后台工单，并在工单完成后继续长出新任务，最终把 tutorial project 循环成一个可试玩 AVG。\n建议流程：1. 点击“重置工程”  2. 在 Browser 填写并提交 brief  3. 去 DevWork 直接点击任务  4. lab 模式会跳过讨论/小游戏，直接触发工单  5. 在 KnowledgeBase / Project Editor / Scene Editor 检查产物  6. 用 Game Preview 测试当前项目。\n说明：本场景不再手工写死业务工单，重点是观测真实开发循环。左侧会持续显示 brief、dev work、工单和项目产物的变化。"
	root.add_child(hint)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	root.add_child(button_row)

	_reset_button = Button.new()
	_reset_button.text = "重置工程"
	button_row.add_child(_reset_button)

	_open_brief_button = Button.new()
	_open_brief_button.text = "打开 Brief"
	button_row.add_child(_open_brief_button)

	_open_dev_work_button = Button.new()
	_open_dev_work_button.text = "打开 DevWork"
	button_row.add_child(_open_dev_work_button)

	_refill_ap_button = Button.new()
	_refill_ap_button.text = "补满 AP"
	button_row.add_child(_refill_ap_button)

	_next_day_button = Button.new()
	_next_day_button.text = "下一天"
	button_row.add_child(_next_day_button)

	_resume_order_button = Button.new()
	_resume_order_button.text = "继续当前工单"
	button_row.add_child(_resume_order_button)

	_preview_button = Button.new()
	_preview_button.text = "测试当前游戏"
	button_row.add_child(_preview_button)

	_project_label = Label.new()
	_project_label.text = "项目：准备中"
	root.add_child(_project_label)

	_time_label = Label.new()
	_time_label.text = "时间：准备中"
	root.add_child(_time_label)

	_loop_label = Label.new()
	_loop_label.text = "循环：准备中"
	root.add_child(_loop_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size.x = 470
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	var summary_title := Label.new()
	summary_title.text = "循环摘要"
	summary_title.add_theme_font_size_override("font_size", 18)
	left_panel.add_child(summary_title)

	_summary_view = RichTextLabel.new()
	_summary_view.bbcode_enabled = false
	_summary_view.scroll_following = false
	_summary_view.custom_minimum_size.y = 220
	left_panel.add_child(_summary_view)

	var order_title := Label.new()
	order_title.text = "工单状态"
	order_title.add_theme_font_size_override("font_size", 18)
	left_panel.add_child(order_title)

	_orders_view = RichTextLabel.new()
	_orders_view.bbcode_enabled = false
	_orders_view.scroll_following = true
	_orders_view.custom_minimum_size.y = 250
	_orders_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(_orders_view)

	var log_title := Label.new()
	log_title.text = "运行日志"
	log_title.add_theme_font_size_override("font_size", 18)
	left_panel.add_child(log_title)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = false
	_log_view.scroll_following = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(_log_view)

	_workspace_tabs = TabContainer.new()
	_workspace_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.custom_minimum_size = Vector2(980, 560)
	split.add_child(_workspace_tabs)

	_rebuild_workspace_tabs()
	_render_cycle_summary()
	_render_order_state()


func _rebuild_workspace_tabs() -> void:
	if _workspace_tabs == null:
		return

	for child in _workspace_tabs.get_children():
		_workspace_tabs.remove_child(child)
		child.queue_free()

	_browser_app = BrowserAppScene.instantiate()
	_browser_app.name = "Browser"
	_browser_app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser_app.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_browser_app)

	_dev_work_app = DevWorkAppScene.instantiate()
	_dev_work_app.name = "DevWork"
	_dev_work_app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_work_app.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_dev_work_app)

	_linkchat_app = LinkChatAppScene.instantiate()
	_linkchat_app.name = "LinkChat"
	_linkchat_app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_linkchat_app.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_linkchat_app)

	_knowledge_base_app = KnowledgeBaseAppScene.instantiate()
	_knowledge_base_app.name = "KnowledgeBase"
	_knowledge_base_app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_knowledge_base_app.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_knowledge_base_app)

	_project_editor = ProjectManagerScene.instantiate()
	_project_editor.name = "Project Editor"
	_project_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_project_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_project_editor)

	_scene_editor = SceneEditorScene.instantiate()
	_scene_editor.name = "Scene Editor"
	_scene_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_scene_editor)

	_previewer = GamePreviewerScene.instantiate()
	_previewer.name = "Game Preview"
	_previewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_previewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_previewer)

	if _previewer != null and _previewer.has_signal("error_occurred") and not _previewer.error_occurred.is_connected(_on_previewer_error):
		_previewer.error_occurred.connect(_on_previewer_error)

	_workspace_tabs.current_tab = 0


func _connect_signals() -> void:
	_reset_button.pressed.connect(_on_reset_pressed)
	_open_brief_button.pressed.connect(_on_open_brief_pressed)
	_open_dev_work_button.pressed.connect(_on_open_dev_work_pressed)
	_refill_ap_button.pressed.connect(_on_refill_ap_pressed)
	_next_day_button.pressed.connect(_on_next_day_pressed)
	_resume_order_button.pressed.connect(_on_resume_order_pressed)
	_preview_button.pressed.connect(_on_preview_pressed)

	if StorageManager.has_signal("current_project_changed") and not StorageManager.current_project_changed.is_connected(_on_project_changed):
		StorageManager.current_project_changed.connect(_on_project_changed)

	if WorkOrderManager.has_signal("order_created") and not WorkOrderManager.order_created.is_connected(_on_order_created):
		WorkOrderManager.order_created.connect(_on_order_created)
	if WorkOrderManager.has_signal("order_updated") and not WorkOrderManager.order_updated.is_connected(_on_order_updated):
		WorkOrderManager.order_updated.connect(_on_order_updated)
	if WorkOrderManager.has_signal("order_status_changed") and not WorkOrderManager.order_status_changed.is_connected(_on_order_status_changed):
		WorkOrderManager.order_status_changed.connect(_on_order_status_changed)
	if WorkOrderManager.has_signal("order_dispatched") and not WorkOrderManager.order_dispatched.is_connected(_on_order_dispatched):
		WorkOrderManager.order_dispatched.connect(_on_order_dispatched)
	if WorkOrderManager.has_signal("orders_loaded") and not WorkOrderManager.orders_loaded.is_connected(_on_orders_loaded):
		WorkOrderManager.orders_loaded.connect(_on_orders_loaded)

	if DevCycleManager.has_signal("tasks_updated") and not DevCycleManager.tasks_updated.is_connected(_on_tasks_updated):
		DevCycleManager.tasks_updated.connect(_on_tasks_updated)
	if DevCycleManager.has_signal("task_status_changed") and not DevCycleManager.task_status_changed.is_connected(_on_task_status_changed):
		DevCycleManager.task_status_changed.connect(_on_task_status_changed)
	if DevCycleManager.has_signal("plan_generated") and not DevCycleManager.plan_generated.is_connected(_on_plan_generated):
		DevCycleManager.plan_generated.connect(_on_plan_generated)

	if PlanningManager.has_signal("seed_task_plan_completed") and not PlanningManager.seed_task_plan_completed.is_connected(_on_seed_task_plan_completed):
		PlanningManager.seed_task_plan_completed.connect(_on_seed_task_plan_completed)
	if PlanningManager.has_signal("development_plan_completed") and not PlanningManager.development_plan_completed.is_connected(_on_development_plan_completed):
		PlanningManager.development_plan_completed.connect(_on_development_plan_completed)

	if KnowledgeBaseManager.has_signal("document_changed") and not KnowledgeBaseManager.document_changed.is_connected(_on_document_changed):
		KnowledgeBaseManager.document_changed.connect(_on_document_changed)

	if GameLoopManager.has_signal("day_changed") and not GameLoopManager.day_changed.is_connected(_on_day_changed):
		GameLoopManager.day_changed.connect(_on_day_changed)
	if GameLoopManager.has_signal("ap_changed") and not GameLoopManager.ap_changed.is_connected(_on_ap_changed):
		GameLoopManager.ap_changed.connect(_on_ap_changed)
	if GameLoopManager.has_signal("phase_changed") and not GameLoopManager.phase_changed.is_connected(_on_phase_changed):
		GameLoopManager.phase_changed.connect(_on_phase_changed)


func _bootstrap_scene_state() -> void:
	_configure_lab_debug_mode(true)
	if _is_runtime_project_bound():
		_append_log("检测到已有 runtime project，保留当前工程。")
		_refresh_workspace_binding()
		_refresh_all_views()
		if not _has_brief_doc():
			call_deferred("_open_brief_page", true)
		return

	if StorageManager != null and StorageManager.has_method("should_use_runtime_project_in_editor") and StorageManager.should_use_runtime_project_in_editor():
		_append_log("editor runtime 复用开关已开启，尝试恢复 runtime project。")
		if StorageManager.has_method("_auto_load_default_project"):
			StorageManager._auto_load_default_project()
		if _is_runtime_project_bound():
			_refresh_workspace_binding()
			_refresh_all_views()
			if not _has_brief_doc():
				call_deferred("_open_brief_page", true)
			return

	_append_log("当前未绑定 runtime 工程，请点击“重置工程”开始实验。")
	_refresh_workspace_binding()
	_refresh_all_views()
func _is_runtime_project_bound() -> bool:
	var current_path: String = str(StorageManager.current_project_path).strip_edges()
	return StorageManager.current_project != null and current_path.begins_with(RUNTIME_PLAYER_PROJECT_PATH)


func _require_runtime_project_binding() -> bool:
	if _is_runtime_project_bound():
		return true
	_append_log("当前未绑定 runtime project，先重置工程。")
	_reset_runtime_project()
	return _is_runtime_project_bound()


func _reset_runtime_project() -> void:
	if _previewer != null and _previewer.has_method("get_is_playing") and _previewer.get_is_playing():
		_previewer.stop_preview()

	_connected_worker_ids.clear()
	_last_visible_task_ids.clear()
	_clear_views()
	_reset_runtime_managers()

	if StorageManager != null and StorageManager.has_method("discard_trunk"):
		StorageManager.discard_trunk()
	if StorageManager != null and StorageManager.has_method("_remove_directory_recursive"):
		if DirAccess.dir_exists_absolute(RUNTIME_TRUNK_PATH):
			StorageManager._remove_directory_recursive(RUNTIME_TRUNK_PATH)
		if DirAccess.dir_exists_absolute(RUNTIME_PLAYER_PROJECT_PATH):
			StorageManager._remove_directory_recursive(RUNTIME_PLAYER_PROJECT_PATH)
	if StorageManager != null and StorageManager.has_method("reset_runtime_state"):
		StorageManager.reset_runtime_state()

	var mount_err: Error = StorageManager.mount_runtime_project(TEMPLATE_NAME)
	if mount_err != OK:
		_append_log("重置失败：mount_runtime_project error=%s" % mount_err)
	else:
		_append_log("已重置并挂载 tutorial project runtime copy。")

	_refresh_workspace_binding()
	_refresh_all_views()
	call_deferred("_open_brief_page", true)


func _reset_runtime_managers() -> void:
	var manager_specs: Array[Dictionary] = [
		{"path": "/root/WorkOrderManager"},
		{"path": "/root/ChatManager", "args": [false]},
		{"path": "/root/BrowserManager", "args": [false]},
		{"path": "/root/PlanningManager"},
		{"path": "/root/DevCycleManager"},
		{"path": "/root/GameLoopManager"},
		{"path": "/root/GameManager"},
		{"path": "/root/StoryDirector"},
		{"path": "/root/ActivitySessionManager"},
		{"path": "/root/CommunityActionManager"},
		{"path": "/root/TransitManager"},
		{"path": "/root/NPCInitiativeManager"},
	]

	for spec in manager_specs:
		var node: Node = get_node_or_null(str(spec.get("path", "")))
		if node == null or not node.has_method("reset_runtime_state"):
			continue
		var args: Array = spec.get("args", [])
		if args.is_empty():
			node.reset_runtime_state()
		else:
			node.callv("reset_runtime_state", args)


func _refresh_workspace_binding() -> void:
	var project: Resource = StorageManager.current_project
	if _previewer != null and _previewer.has_method("set_project"):
		_previewer.set_project(project)
	if _knowledge_base_app != null and _knowledge_base_app.has_method("_refresh_all"):
		_knowledge_base_app._refresh_all()
	if _project_editor != null and _project_editor.has_method("set_project"):
		_project_editor.set_project(project)
	if _scene_editor != null:
		var scene_file_panel: Node = _scene_editor.get_node_or_null("%SceneFilePanel")
		if scene_file_panel != null and scene_file_panel.has_method("set_project"):
			scene_file_panel.set_project(project)
		var first_scene: Resource = _get_first_scene(project)
		if first_scene != null and _scene_editor.has_method("set_scene"):
			_scene_editor.set_scene(first_scene)

	var project_name: String = "未加载"
	if project != null and "project_name" in project:
		project_name = str(project.project_name)
	var project_path: String = str(StorageManager.current_project_path).strip_edges()
	if project_path.is_empty():
		project_path = "(空)"
	_project_label.text = "项目：%s  |  路径：%s" % [project_name, project_path]
	_update_ui_state()


func _refresh_all_views() -> void:
	_update_time_label()
	_update_loop_label()
	_render_cycle_summary()
	_render_order_state()
	_update_ui_state()


func _configure_lab_debug_mode(enabled: bool) -> void:
	if DevCycleManager != null and DevCycleManager.has_method("set_debug_direct_execute_interactive_tasks"):
		DevCycleManager.set_debug_direct_execute_interactive_tasks(enabled)


func _update_time_label() -> void:
	if _time_label == null:
		return
	if GameLoopManager == null:
		_time_label.text = "时间：不可用"
		return
	_time_label.text = "时间：第 %d 天  |  %s  |  AP %d/%d" % [
		int(GameLoopManager.current_day),
		str(GameLoopManager.get_phase_display_name(GameLoopManager.time_phase)),
		int(GameLoopManager.current_ap),
		int(GameLoopManager.max_ap_per_day),
	]


func _update_loop_label() -> void:
	if _loop_label == null:
		return
	if not _is_runtime_project_bound():
		_loop_label.text = "循环：未绑定 runtime 工程"
		return

	var visible_tasks: Array[Dictionary] = _get_visible_tasks()
	var order_counts: Dictionary = _build_order_counts()
	var scene_count: int = _get_project_scene_count(StorageManager.current_project)

	if not _has_brief_doc():
		_loop_label.text = "循环：等待提交 brief"
	elif bool(DevCycleManager.get("_seed_task_generating")):
		_loop_label.text = "循环：正在生成第一批 dev work"
	elif _is_waiting_for_clarification():
		_loop_label.text = "循环：后台工单等待玩家澄清"
	elif bool(DevCycleManager.get("_plan_generating")):
		_loop_label.text = "循环：正在生成正式开发计划"
	elif not visible_tasks.is_empty():
		_loop_label.text = "循环：当前可执行 dev work %d 项" % visible_tasks.size()
	elif int(order_counts.get("in_progress", 0)) > 0 or int(order_counts.get("pending", 0)) > 0:
		_loop_label.text = "循环：后台工单执行中"
	elif scene_count > 0 and int(order_counts.get("completed", 0)) > 0:
		_loop_label.text = "循环：已有产物，可检查当前项目"
	else:
		_loop_label.text = "循环：等待下一步状态变化"


func _render_cycle_summary() -> void:
	if _summary_view == null:
		return

	var lines: PackedStringArray = []
	var project: Resource = StorageManager.current_project
	var brief_doc: Dictionary = KnowledgeBaseManager.get_document("creative_brief") if KnowledgeBaseManager != null else {}
	var visible_tasks: Array[Dictionary] = _get_visible_tasks()
	var order_counts: Dictionary = _build_order_counts()
	var total_tasks: int = 0
	var task_pool: Variant = DevCycleManager.get("_task_pool") if DevCycleManager != null else {}
	if task_pool is Dictionary:
		total_tasks = (task_pool as Dictionary).size()

	lines.append("实验目标")
	lines.append("- brief 是否能自动长出第一批 dev work")
	lines.append("- 执行 dev work 后是否会自动创建并推进后台工单")
	lines.append("- 工单完成后是否会继续长出新任务 / 新章节")
	lines.append("- 当前项目是否真的在往可试玩 AVG 收敛")
	lines.append("")
	lines.append("当前状态")
	lines.append("- Brief：%s" % ("已提交" if not brief_doc.is_empty() else "未提交"))
	lines.append("- Lab 快速模式：%s" % ("开启（跳过讨论/小游戏）" if _is_lab_fast_mode_enabled() else "关闭"))
	lines.append("- Seed 任务生成：%s" % ("进行中" if bool(DevCycleManager.get("_seed_task_generating")) else "空闲"))
	lines.append("- 正式计划：%s" % _get_plan_state_text())
	lines.append("- DevWork：可见 %d / 总量 %d / 已完成 %d" % [
		visible_tasks.size(),
		total_tasks,
		int(DevCycleManager.get_completed_count()) if DevCycleManager != null else 0,
	])
	lines.append("- 后台队列：%d" % (int(DevCycleManager.get_queue_size()) if DevCycleManager != null else 0))
	lines.append("- 当前活跃工单：%s" % _get_active_order_label())
	lines.append("- 工单统计：总数 %d / 完成 %d / 进行中 %d / 待澄清 %d / 失败 %d" % [
		int(order_counts.get("total", 0)),
		int(order_counts.get("completed", 0)),
		int(order_counts.get("in_progress", 0)) + int(order_counts.get("pending", 0)),
		int(order_counts.get("needs_input", 0)),
		int(order_counts.get("failed", 0)),
	])
	lines.append("- 知识库文档：%d" % (KnowledgeBaseManager.get_documents().size() if KnowledgeBaseManager != null else 0))
	lines.append("- 项目产物：场景 %d / 角色 %d" % [
		_get_project_scene_count(project),
		_get_project_character_count(project),
	])

	if not visible_tasks.is_empty():
		lines.append("")
		lines.append("当前可见 DevWork")
		for task in visible_tasks:
			lines.append("- %s [%s]" % [
				str(task.get("title", "未命名任务")),
				str(task.get("task_type", "minigame")),
			])

	_summary_view.text = "\n".join(lines)


func _render_order_state() -> void:
	if _orders_view == null:
		return

	var orders: Array = _get_orders_sorted(false)
	if orders.is_empty():
		_orders_view.text = "尚无后台工单。\n提交 brief 并推进 DevWork 后，这里会显示真实工单状态。"
		return

	var lines: PackedStringArray = []
	for i in range(orders.size()):
		var order: Resource = orders[i]
		if order == null:
			continue
		lines.append("%d. %s" % [i + 1, str(order.title)])
		lines.append("   工单：%s" % str(order.id))
		lines.append("   来源：%s / %s" % [str(order.source_type), str(order.source_id)])
		lines.append("   状态：legacy=%s  surface=%s  inner=%s" % [
			str(order.status),
			str(order.surface_status),
			str(order.inner_status),
		])
	_orders_view.text = "\n\n".join(lines)


func _clear_views() -> void:
	if _summary_view != null:
		_summary_view.text = ""
	if _orders_view != null:
		_orders_view.text = ""
	if _log_view != null:
		_log_view.text = ""


func _on_reset_pressed() -> void:
	_append_log("开始重置 runtime tutorial project。")
	_reset_runtime_project()


func _on_open_brief_pressed() -> void:
	if not _require_runtime_project_binding():
		return
	_open_brief_page(true)


func _on_open_dev_work_pressed() -> void:
	if _workspace_tabs != null and _dev_work_app != null:
		_workspace_tabs.current_tab = _dev_work_app.get_index()
		_append_log("已切到 DevWork。")


func _on_refill_ap_pressed() -> void:
	if not _require_runtime_project_binding():
		return
	var state: Dictionary = GameLoopManager.get_run_state()
	state["current_ap"] = state.get("max_ap_per_day", 1)
	GameLoopManager.load_run_state(state)
	_append_log("已补满本时段 AP。")


func _on_next_day_pressed() -> void:
	if not _require_runtime_project_binding():
		return
	GameLoopManager.advance_to_next_day()
	_append_log("已推进到下一天。")


func _on_resume_order_pressed() -> void:
	if not _require_runtime_project_binding():
		return
	_resume_current_order()


func _on_preview_pressed() -> void:
	if StorageManager.current_project == null:
		_append_log("当前没有可预览的项目。")
		return
	_refresh_workspace_binding()
	if _workspace_tabs != null and _previewer != null:
		_workspace_tabs.current_tab = _previewer.get_index()
	_append_log("正在打开 Game Preview 并运行当前项目。")
	if _previewer != null and _previewer.has_method("start_preview"):
		_previewer.start_preview()


func _open_brief_page(switch_tab: bool = true) -> void:
	if _browser_app == null or not is_instance_valid(_browser_app):
		return
	if switch_tab and _workspace_tabs != null:
		_workspace_tabs.current_tab = _browser_app.get_index()
	if _browser_app.has_method("_on_page_action"):
		_browser_app.call("_on_page_action", {"action": "open_url", "url": BRIEF_URL})
	_append_log("已打开 Project Brief 页面。")


func _focus_linkchat() -> void:
	if _workspace_tabs != null and _linkchat_app != null:
		_workspace_tabs.current_tab = _linkchat_app.get_index()
	if _linkchat_app != null and _linkchat_app.has_method("open_topic_channel"):
		_linkchat_app.open_topic_channel("dm_lin_xia")


func _on_project_changed(_project: Resource) -> void:
	_refresh_workspace_binding()
	_refresh_all_views()


func _on_orders_loaded() -> void:
	_refresh_all_views()


func _on_order_created(order_id: String) -> void:
	_append_log("工单已创建：%s" % order_id)
	_connect_worker_log(order_id)
	_refresh_all_views()


func _on_order_updated(order_id: String) -> void:
	_connect_worker_log(order_id)
	_refresh_all_views()


func _on_order_dispatched(order_id: String) -> void:
	_append_log("工单进入后台执行：%s" % order_id)
	_connect_worker_log(order_id)
	_refresh_all_views()


func _on_order_status_changed(order_id: String, old_status: String, new_status: String) -> void:
	_connect_worker_log(order_id)
	_append_log("工单状态变化：%s  %s -> %s" % [order_id, old_status, new_status])
	if new_status == "needs_input":
		_append_log("当前工单需要玩家补充说明，请去 LinkChat 回复。")
		_focus_linkchat()
	if new_status == "completed":
		_refresh_workspace_binding()
	_refresh_all_views()


func _on_tasks_updated() -> void:
	_log_visible_task_changes()
	_refresh_all_views()


func _on_task_status_changed(task_id: String, new_status: String) -> void:
	var task: Dictionary = DevCycleManager.get_task(task_id) if DevCycleManager != null else {}
	var title: String = str(task.get("title", task_id))
	_append_log("DevWork 状态变化：%s -> %s" % [title, new_status])
	_log_visible_task_changes()
	_refresh_all_views()


func _on_plan_generated(success: bool) -> void:
	_append_log("正式开发计划生成%s。" % ("成功" if success else "失败"))
	_refresh_all_views()


func _on_seed_task_plan_completed(_request_id: String, success: bool, tasks: Array, _raw_output: String) -> void:
	if success:
		_append_log("Seed DevWork 规划完成：返回 %d 项任务。" % tasks.size())
	else:
		_append_log("Seed DevWork 规划失败，系统可能会回退到兜底任务。")
	_refresh_all_views()


func _on_development_plan_completed(_request_id: String, success: bool, tasks: Array, _raw_output: String) -> void:
	if success:
		_append_log("正式开发计划完成：返回 %d 个任务。" % tasks.size())
	else:
		_append_log("正式开发计划生成失败。")
	_refresh_all_views()


func _on_document_changed(doc_id: String) -> void:
	if doc_id == "creative_brief":
		_append_log("KnowledgeBase 已写入项目企划书。")
	_refresh_all_views()


func _on_day_changed(_new_day: int) -> void:
	_refresh_all_views()


func _on_ap_changed(_current: int, _max_ap: int) -> void:
	_refresh_all_views()


func _on_phase_changed(_new_phase: int) -> void:
	_refresh_all_views()


func _on_previewer_error(message: String) -> void:
	_append_log("GamePreview 报错：%s" % message)


func _connect_worker_log(order_id: String) -> void:
	if _connected_worker_ids.has(order_id):
		return
	if WorkOrderManager == null:
		return

	var agents: Dictionary = WorkOrderManager.get("_worker_agents")
	if not agents.has(order_id):
		return

	var worker: ChatAgent = agents.get(order_id)
	if worker == null or not is_instance_valid(worker):
		return
	if not worker.has_signal("log_entry"):
		return

	worker.log_entry.connect(func(entry: Dictionary) -> void:
		var content: String = str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			return
		_append_log("[%s] %s" % [order_id, content])
	)
	_connected_worker_ids[order_id] = true


func _resume_current_order() -> void:
	var order: Resource = _find_resume_target_order()
	if order == null:
		_append_log("当前没有需要继续处理的工单。")
		return

	var order_id: String = str(order.id)
	var status: String = str(order.status)
	if status == "needs_input":
		_append_log("当前工单仍在等待澄清，请先去 LinkChat 回复。")
		_focus_linkchat()
		_update_ui_state()
		return

	if WorkOrderManager.has_method("resume_order_generation"):
		var resumed: bool = WorkOrderManager.resume_order_generation(order_id)
		if resumed:
			_append_log("已定向恢复工单：%s" % str(order.title))
			_connect_worker_log(order_id)
			_update_ui_state()
			return

	if WorkOrderManager.has_method("is_order_running") and WorkOrderManager.is_order_running(order_id):
		_append_log("当前工单已有后台 worker，继续等待即可。")
		_update_ui_state()
		return

	if _has_pending_generation(order_id):
		_append_log("检测到其他工单仍在执行，暂不重复派发。")
		_update_ui_state()
		return

	var redispatch_ok: bool = WorkOrderManager.dispatch_order(order_id)
	if redispatch_ok:
		_append_log("已重新派发工单：%s" % str(order.title))
		_connect_worker_log(order_id)
	else:
		_append_log("继续工单失败：%s" % str(order.title))
	_update_ui_state()


func _has_pending_generation(except_order_id: String = "") -> bool:
	if WorkOrderManager == null or not WorkOrderManager.has_method("_get_generating_order_ids"):
		return false
	return not WorkOrderManager._get_generating_order_ids(except_order_id).is_empty()


func _find_resume_target_order() -> Resource:
	if WorkOrderManager == null:
		return null

	if WorkOrderManager.has_method("_get_generating_order_ids"):
		var generating_ids: Array[String] = WorkOrderManager._get_generating_order_ids()
		if not generating_ids.is_empty():
			return WorkOrderManager.get_order(str(generating_ids[0]))

	var orders: Array = _get_orders_sorted(true)
	var priority_statuses: PackedStringArray = [
		"needs_input",
		"failed",
		"pending",
		"in_progress",
		"created",
		"idle",
		"queued",
	]
	for desired_status in priority_statuses:
		for order in orders:
			if order != null and str(order.status) == desired_status:
				return order
	return null


func _get_orders_sorted(descending: bool) -> Array:
	var orders: Array = []
	if WorkOrderManager == null or not WorkOrderManager.has_method("get_all_orders"):
		return orders
	for order in WorkOrderManager.get_all_orders():
		if order != null:
			orders.append(order)
	orders.sort_custom(func(a: Resource, b: Resource) -> bool:
		if descending:
			return int(a.updated_at) > int(b.updated_at)
		return int(a.updated_at) < int(b.updated_at)
	)
	return orders


func _build_order_counts() -> Dictionary:
	var counts: Dictionary = {
		"total": 0,
		"completed": 0,
		"needs_input": 0,
		"failed": 0,
		"in_progress": 0,
		"pending": 0,
	}
	for order in _get_orders_sorted(false):
		counts["total"] = int(counts.get("total", 0)) + 1
		var status: String = str(order.status)
		if counts.has(status):
			counts[status] = int(counts.get(status, 0)) + 1
	return counts


func _get_visible_tasks() -> Array[Dictionary]:
	if DevCycleManager == null or not DevCycleManager.has_method("get_visible_tasks"):
		return []
	return DevCycleManager.get_visible_tasks()


func _log_visible_task_changes() -> void:
	var visible_tasks: Array[Dictionary] = _get_visible_tasks()
	var current_ids: Array[String] = []
	var newly_visible_titles: PackedStringArray = []
	for task in visible_tasks:
		var task_id: String = str(task.get("task_id", "")).strip_edges()
		if task_id.is_empty():
			continue
		current_ids.append(task_id)
		if task_id not in _last_visible_task_ids:
			newly_visible_titles.append(str(task.get("title", task_id)))

	if not newly_visible_titles.is_empty():
		_append_log("出现新的 DevWork：%s" % " / ".join(newly_visible_titles))

	_last_visible_task_ids = current_ids


func _has_brief_doc() -> bool:
	if KnowledgeBaseManager == null or not KnowledgeBaseManager.has_method("get_document"):
		return false
	return not KnowledgeBaseManager.get_document("creative_brief").is_empty()


func _get_plan_state_text() -> String:
	if DevCycleManager == null:
		return "不可用"
	if bool(DevCycleManager.get("_plan_generating")):
		return "生成中"
	if bool(DevCycleManager.get("_plan_generated")):
		return "已生成"
	return "未生成"


func _is_lab_fast_mode_enabled() -> bool:
	if DevCycleManager == null or not DevCycleManager.has_method("is_debug_direct_execute_interactive_tasks_enabled"):
		return false
	return bool(DevCycleManager.is_debug_direct_execute_interactive_tasks_enabled())


func _get_active_order_label() -> String:
	if DevCycleManager == null:
		return "不可用"
	var raw_active_order_id: Variant = DevCycleManager.get("_active_order_id")
	var active_order_id: String = str(raw_active_order_id if raw_active_order_id != null else "")
	if active_order_id.is_empty():
		var target_order: Resource = _find_resume_target_order()
		if target_order != null:
			return "%s (%s)" % [str(target_order.title), str(target_order.status)]
		return "无"
	var order: Resource = WorkOrderManager.get_order(active_order_id) if WorkOrderManager != null else null
	if order == null:
		return active_order_id
	return "%s (%s)" % [str(order.title), str(order.status)]


func _get_project_scene_count(project: Resource) -> int:
	if project == null or not ("scenes" in project) or project.scenes == null:
		return 0
	return project.scenes.size()


func _get_project_character_count(project: Resource) -> int:
	if project == null or not ("characters" in project) or project.characters == null:
		return 0
	return project.characters.size()


func _get_first_scene(project: Resource) -> Resource:
	if project == null or not ("scenes" in project):
		return null
	if project.scenes == null or project.scenes.is_empty():
		return null
	return project.scenes[0]


func _is_waiting_for_clarification() -> bool:
	var target_order: Resource = _find_resume_target_order()
	return target_order != null and str(target_order.status) == "needs_input"


func _update_ui_state() -> void:
	var runtime_ready: bool = _is_runtime_project_bound()
	var resume_target: Resource = _find_resume_target_order()

	if _open_brief_button != null:
		_open_brief_button.disabled = not runtime_ready
	if _open_dev_work_button != null:
		_open_dev_work_button.disabled = not runtime_ready
	if _refill_ap_button != null:
		_refill_ap_button.disabled = not runtime_ready
	if _next_day_button != null:
		_next_day_button.disabled = not runtime_ready
	if _resume_order_button != null:
		_resume_order_button.disabled = resume_target == null
		if resume_target == null:
			_resume_order_button.text = "继续当前工单"
		else:
			match str(resume_target.status):
				"needs_input":
					_resume_order_button.text = "前往澄清"
				"failed":
					_resume_order_button.text = "重试工单"
				_:
					_resume_order_button.text = "继续当前工单"
	if _preview_button != null:
		_preview_button.disabled = StorageManager.current_project == null
	if _reset_button != null:
		_reset_button.disabled = false


func _append_log(message: String) -> void:
	if _log_view == null:
		return
	var timestamp := Time.get_datetime_dict_from_system()
	var prefix := "[%02d:%02d:%02d] " % [int(timestamp.get("hour", 0)), int(timestamp.get("minute", 0)), int(timestamp.get("second", 0))]
	_log_view.append_text(prefix + message + "\n")
	_log_view.scroll_to_line(_log_view.get_line_count())
