extends Control

const GamePreviewerScene = preload("res://scenes/apps/game_previewer/game_previewer.tscn")
const KnowledgeBaseAppScene = preload("res://scenes/apps/knowledge_base/knowledge_base_app.tscn")
const LinkChatAppScene = preload("res://scenes/apps/linkchat/linkchat_app.tscn")
const ProjectManagerScene = preload("res://scenes/apps/project_manager/project_manager.tscn")
const SceneEditorScene = preload("res://scenes/apps/scene_editor/scene_editor.tscn")

const TEMPLATE_NAME: String = "tutorial_project"
const RUNTIME_PLAYER_PROJECT_PATH: String = "user://run/player_project/"
const RUNTIME_TRUNK_PATH: String = "user://run/trunk/"
const ORDER_DEFINITIONS: Array[Dictionary] = [
	{
		"key": "world",
		"title": "测试流水线：补完世界观",
		"description": "基于 tutorial project 现有素材与知识库，补完一个可用于校园奇幻恋爱 AVG 的世界观基础文档。需要明确舞台规则、主线冲突，以及为什么主角会在短时间内与两位不同性格的女主角产生关系推进。故事规模控制在一个很短的可玩样片：有开头、中间、结局，并能自然承接三个不同 ENDING。若已有相关文档，请在原有内容上整理和补强，不要另外再造一套平行设定。只处理知识库内容，不要编写场景 DSL。",
	},
	{
		"key": "protagonist",
		"title": "测试流水线：设计主角",
		"description": "为 tutorial project 整理并落实 1 名主角。请产出稳定可用的人设文档，并把该角色绑定到未占用的预置 AVGCharacter 壳子。主角需要适合承接一个很短的校园奇幻恋爱 AVG：既能在开头推动事件，又能在中段面对两位不同女主角带来的不同关系张力，并自然导向单身 / 角色2 / 角色3 三种结局。只聚焦主角，不要顺带扩写其他角色。",
	},
	{
		"key": "heroine_2",
		"title": "测试流水线：设计角色2女主角",
		"description": "为 tutorial project 整理并落实角色2女主角。请产出稳定可用的人设文档，并把该角色绑定到未占用的预置 AVGCharacter 壳子。她必须有清晰的性格、口吻、价值取向和与主角的关系推进方式，并且和角色3女主角形成明显差异，不要只是轻微变体。只聚焦这名女主角本身，不要把三条路线结构也塞进这一单。",
	},
	{
		"key": "heroine_3",
		"title": "测试流水线：设计角色3女主角",
		"description": "为 tutorial project 整理并落实角色3女主角。请产出稳定可用的人设文档，并把该角色绑定到未占用的预置 AVGCharacter 壳子。她必须与角色2在性格、说话方式、吸引主角的点、关系推进节奏上明显不同，确保两个女主角真的构成两条不同路线，而不是换皮。只处理角色3，不要扩写无关配角。",
	},
	{
		"key": "route_blueprint",
		"title": "测试流水线：编写短篇结构约束稿",
		"description": "基于前面已经整理好的世界观、主角、角色2女主角、角色3女主角，为一个极简可玩短篇写一份给 Writer 用的结构约束稿。严格控制规模：全篇总量最多 6 到 8 个场景，不要写 10+ 场景，不要写 30 天流程，不要写阶段总表。只需要明确：开头大概做几场、中段大概做几场、结局段如何收束；三条 ENDING 分别是单身、角色2结局、角色3结局；哪些少量变量负责路线推进；中段在哪一个或两个节点发生分歧；三条结局各自的触发条件；以及全篇必须使用的真实背景/BGM 约束。不要写空泛分析，不要写大表格，不要直接写 DSL。",
	},
	{
		"key": "opening_story_draft",
		"title": "测试流水线：编写开头实现稿",
		"description": "基于短篇结构约束稿，为短篇的开头部分写一份给 Writer 使用的自然语言实现稿。开头必须完成：建立世界与舞台、介绍主角、让角色2与角色3都实际登场、埋下两条关系路线的不同吸引力，并为中段分歧提供明确前置。规模控制在 2 到 3 个场景内，不要扩写成连续很多天。请直接写可实现内容：场景顺序、对白推进、变量初始变化、必须出现的资源约束。不要写氛围要点，不要写无效分点。",
	},
	{
		"key": "middle_story_draft",
		"title": "测试流水线：编写中段实现稿",
		"description": "基于短篇结构约束稿，为短篇的中段部分写一份自然语言实现稿。中段必须真正承担分歧功能：主角分别与角色2、角色3发生不同互动，玩家或状态推进需要能把路线推向单身 / 角色2 / 角色3 三个方向。规模控制在 2 到 3 个场景内。请明确中段有哪些场景、哪些选择或条件变化在这里发生、变量如何累计、如何自然过渡到结局段。不要发明额外的大量日程或训练周目。",
	},
	{
		"key": "ending_story_draft",
		"title": "测试流水线：编写结局实现稿",
		"description": "基于短篇结构约束稿，为短篇的结局部分写一份自然语言实现稿。必须明确写出 3 个 ENDING：单身结局、角色2结局、角色3结局。结局段总量控制在 2 到 3 个很短场景或共享前置 + 3 个短结局内，不要扩成庞大的终章结构。请直接决定每条结局的触发条件、各自最后一段场景如何收束、变量阈值如何判断、是否需要共享前置场景，以及每条结局使用的真实资源约束。不要写泛泛总结，要让 Writer 能按此直接落地。",
	},
	{
		"key": "implement_opening_and_middle",
		"title": "测试流水线：制作开头与中段",
		"description": "基于已经完成的世界观、角色设定、短篇结构约束稿、开头实现稿和中段实现稿，创建一个可以直接在 GamePreview 中运行的前半段样片。要求至少实现：开头和中段的完整可玩结构、角色2与角色3都实际登场并发生不同互动、路线变量真实落地、进入结局前的分歧条件已经建立。前半段总体也必须保持短篇体量，不要偷偷膨胀成十几个场景。允许使用多个场景，但不要提前把三条结局全部做完。Controller 在执行这一单时，不要让一个 Writer 一次写完整个前半段；更推荐按场景或按小批次逐个委托，先做开头，再做中段的不同场景。",
	},
	{
		"key": "implement_endings_and_integration",
		"title": "测试流水线：制作三条结局并完成整合",
		"description": "基于已经完成的全部设定和实现稿，在现有开头与中段基础上，补完整个可玩短篇的结尾部分。必须落地 3 个实际可达 ENDING：单身结局、角色2结局、角色3结局；并确保从入口到三条结局都能走通，没有假分支、孤立结局或断链。Controller 在执行这一单时，不要把三个结局一次性交给一个 Writer；应优先拆成多个小批次，例如公共前置场景一批、角色2结局一批、角色3结局一批、单身结局一批。结束前要修正初始场景、通过 reachability 检查，并让整个作品保持为一个能在较短时间内完整试玩的短篇。",
	},
]

var _dispatch_button: Button
var _preview_button: Button
var _reset_button: Button
var _project_label: Label
var _pipeline_label: Label
var _orders_view: RichTextLabel
var _log_view: RichTextLabel
var _previewer: Control
var _linkchat_app: Control
var _knowledge_base_app: Control
var _project_editor: Control
var _scene_editor: Control
var _workspace_tabs: TabContainer

var _pipeline_running: bool = false
var _pipeline_finished: bool = false
var _active_order_id: String = ""
var _next_order_index: int = 0
var _order_records: Array[Dictionary] = []
var _connected_worker_ids: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_connect_signals()
	call_deferred("_bootstrap_scene_state")


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
	title.text = "LLM Build Pipeline Lab"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = false
	hint.fit_content = true
	hint.scroll_active = false
	hint.custom_minimum_size.y = 72
	hint.text = "用途：在 tutorial project 的 runtime copy 上，串行派发 %d 张真实工单，验证 Controller 是否能把项目从 0 做成一个可运行的多结局短篇 AVG。\\n目标规格：1 名主角 + 2 名不同性格女主角；包含简单开头、中间、结局；最终有 3 个实际可达 ENDING（单身、角色2、角色3）。\\n步骤：1. 点击“重置工程”恢复干净副本  2. 点击“派发工单”开始流水线  3. 在右侧切到 LinkChat / KnowledgeBase / Project Editor / Scene Editor 检查产物  4. 全部完成后点击“测试游戏”。\\n说明：这次流程已拆成更细的多工单链，不再假设 4 单就能完成。工单派发后会直接进入后台执行，完成后自动闭环。若工单进入“待确认”，请切到 LinkChat 回答后再回来等待。" % ORDER_DEFINITIONS.size()
	root.add_child(hint)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	root.add_child(button_row)

	_dispatch_button = Button.new()
	_dispatch_button.text = "派发工单"
	button_row.add_child(_dispatch_button)

	_preview_button = Button.new()
	_preview_button.text = "测试游戏"
	_preview_button.disabled = true
	button_row.add_child(_preview_button)

	_reset_button = Button.new()
	_reset_button.text = "重置工程"
	button_row.add_child(_reset_button)

	_project_label = Label.new()
	_project_label.text = "项目：准备中"
	root.add_child(_project_label)

	_pipeline_label = Label.new()
	_pipeline_label.text = "流水线：未开始"
	root.add_child(_pipeline_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size.x = 460
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	var order_title := Label.new()
	order_title.text = "工单状态"
	order_title.add_theme_font_size_override("font_size", 18)
	left_panel.add_child(order_title)

	_orders_view = RichTextLabel.new()
	_orders_view.bbcode_enabled = false
	_orders_view.scroll_following = true
	_orders_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_orders_view.custom_minimum_size.y = 260
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
	_workspace_tabs.custom_minimum_size = Vector2(960, 540)
	split.add_child(_workspace_tabs)

	_previewer = GamePreviewerScene.instantiate()
	_previewer.name = "Game Preview"
	_previewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_previewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_tabs.add_child(_previewer)

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

	_render_order_state()
	_append_log("测试场景已加载。")


func _connect_signals() -> void:
	_dispatch_button.pressed.connect(_on_dispatch_pressed)
	_preview_button.pressed.connect(_on_preview_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)

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

	if _previewer.has_signal("error_occurred") and not _previewer.error_occurred.is_connected(_on_previewer_error):
		_previewer.error_occurred.connect(_on_previewer_error)


func _bootstrap_scene_state() -> void:
	if _is_runtime_project_bound():
		_append_log("检测到已有 runtime project，保留当前工程与工单进度。")
		_refresh_project_binding()
		_sync_pipeline_from_existing_orders()
		_update_ui_state()
		return

	if StorageManager != null and StorageManager.has_method("should_use_runtime_project_in_editor") and StorageManager.should_use_runtime_project_in_editor():
		_append_log("editor runtime 复用开关已开启，按全局规则恢复 runtime project。")
		if StorageManager.has_method("_auto_load_default_project"):
			StorageManager._auto_load_default_project()
		if _is_runtime_project_bound():
			_refresh_project_binding()
			_sync_pipeline_from_existing_orders()
			_update_ui_state()
			return
		_append_log("按全局规则恢复 runtime project 失败，请点击“重置工程”。")
	else:
		_append_log("当前保持默认模板工程。若要继续 runtime 测试，请开启 editor runtime 开关，或直接点击“重置工程”。")

	_refresh_project_binding()
	_clear_pipeline_snapshot()
	_update_ui_state()


func _is_runtime_project_bound() -> bool:
	var current_path: String = str(StorageManager.current_project_path).strip_edges()
	return StorageManager.current_project != null and current_path.begins_with(RUNTIME_PLAYER_PROJECT_PATH)


func _clear_pipeline_snapshot() -> void:
	_pipeline_running = false
	_pipeline_finished = false
	_active_order_id = ""
	_next_order_index = 0
	_order_records.clear()
	_connected_worker_ids.clear()
	_pipeline_label.text = "流水线：未绑定 runtime 工程"
	_render_order_state()


func _require_runtime_project_binding() -> bool:
	if _is_runtime_project_bound():
		return true
	_append_log("当前未绑定 runtime project，先创建并切换到 runtime copy。")
	_reset_runtime_project()
	return _is_runtime_project_bound()


func _reset_runtime_project() -> void:
	if _previewer != null and _previewer.has_method("get_is_playing") and _previewer.get_is_playing():
		_previewer.stop_preview()

	_pipeline_running = false
	_pipeline_finished = false
	_active_order_id = ""
	_next_order_index = 0
	_order_records.clear()
	_connected_worker_ids.clear()
	_pipeline_label.text = "流水线：未开始"

	if WorkOrderManager != null and WorkOrderManager.has_method("reset_runtime_state"):
		WorkOrderManager.reset_runtime_state()
	if ChatManager != null and ChatManager.has_method("reset_runtime_state"):
		ChatManager.reset_runtime_state(false)
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

	_refresh_project_binding()
	_sync_pipeline_from_existing_orders()
	_render_order_state()
	_update_ui_state()


func _refresh_project_binding() -> void:
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


func _on_dispatch_pressed() -> void:
	if not _require_runtime_project_binding():
		_append_log("无法启动流水线：runtime project 仍未就绪。")
		return
	if _pipeline_running:
		_append_log("流水线正在执行中，请先等待当前工单。")
		return
	if _pipeline_finished:
		_append_log("当前流水线已经全部完成，若要重跑请先重置工程。")
		return
	if StorageManager.current_project == null:
		_append_log("当前项目未就绪，正在重新挂载 tutorial project。")
		_reset_runtime_project()
	if StorageManager.current_project == null:
		_append_log("无法启动流水线：项目仍未就绪。")
		return

	if not _active_order_id.is_empty():
		_resume_active_order()
		return

	_pipeline_running = true
	_pipeline_finished = false
	_pipeline_label.text = "流水线：执行中（%d/%d）" % [_next_order_index, ORDER_DEFINITIONS.size()]
	if _next_order_index <= 0:
		_append_log("开始连续派发 %d 张工单。" % ORDER_DEFINITIONS.size())
	else:
		_append_log("继续从第 %d 张工单开始执行。" % [_next_order_index + 1])
	_update_ui_state()
	call_deferred("_dispatch_next_order")


func _dispatch_next_order() -> void:
	if not _pipeline_running or not _active_order_id.is_empty():
		return
	if _has_pending_generation():
		_pipeline_label.text = "流水线：等待当前工单结束"
		_update_ui_state()
		return

	if _next_order_index >= ORDER_DEFINITIONS.size():
		_pipeline_running = false
		_pipeline_finished = true
		_pipeline_label.text = "流水线：全部完成（%d/%d）" % [ORDER_DEFINITIONS.size(), ORDER_DEFINITIONS.size()]
		_append_log("%d 张工单已全部完成，可以点击“测试游戏”。" % ORDER_DEFINITIONS.size())
		_update_ui_state()
		return

	var spec: Dictionary = ORDER_DEFINITIONS[_next_order_index]
	var order: Resource = WorkOrderManager.create_order(
		str(spec.get("title", "")),
		str(spec.get("description", "")),
		{
			"source_type": "llm_build_pipeline_lab",
			"source_id": str(spec.get("key", "step_%d" % _next_order_index)),
		}
	)
	if order == null:
		_append_log("创建工单失败：%s" % str(spec.get("title", "")))
		_pipeline_running = false
		_update_ui_state()
		return

	WorkOrderManager.update_order(order.id, {
		"priority": 3,
	})
	order.priority = 3
	order.updated_at = int(Time.get_unix_time_from_system())

	_order_records.append({
		"order_id": str(order.id),
		"title": str(order.title),
		"step_key": str(spec.get("key", "")),
	})
	var order_id: String = str(order.id)
	_active_order_id = order_id
	_pipeline_label.text = "流水线：执行中（%d/%d）" % [_next_order_index + 1, ORDER_DEFINITIONS.size()]

	_append_log("派发工单 %d/%d：%s" % [_next_order_index + 1, ORDER_DEFINITIONS.size(), str(order.title)])
	var dispatch_ok: bool = WorkOrderManager.dispatch_order(order_id)
	if not dispatch_ok:
		_append_log("派发失败：%s" % str(order.title))
		_set_record_status(order_id, "dispatch_failed")
		_pipeline_running = false
		_active_order_id = ""
		_pipeline_label.text = "流水线：派发失败"
	else:
		_connect_worker_log(order_id)

	_render_order_state()
	_update_ui_state()


func _on_preview_pressed() -> void:
	if not _pipeline_finished:
		_append_log("所有工单完成后才能测试游戏。")
		return
	if StorageManager.current_project == null:
		_append_log("当前没有可预览的项目。")
		return

	_refresh_project_binding()
	_append_log("正在打开 GamePreview 并运行当前项目。")
	if _workspace_tabs != null:
		_workspace_tabs.current_tab = 0
	if _previewer != null and _previewer.has_method("start_preview"):
		_previewer.start_preview()


func _on_reset_pressed() -> void:
	_append_log("开始重置 runtime tutorial project。")
	_reset_runtime_project()


func _on_project_changed(_project: Resource) -> void:
	_refresh_project_binding()
	if _is_runtime_project_bound():
		_sync_pipeline_from_existing_orders()
	else:
		_clear_pipeline_snapshot()
	_update_ui_state()


func _on_orders_loaded() -> void:
	_sync_pipeline_from_existing_orders()
	_render_order_state()
	_update_ui_state()


func _on_order_created(order_id: String) -> void:
	_append_log("工单已创建：%s" % order_id)
	_render_order_state()


func _on_order_updated(order_id: String) -> void:
	_connect_worker_log(order_id)
	_render_order_state()


func _on_order_dispatched(order_id: String) -> void:
	_append_log("工单进入后台执行：%s" % order_id)
	_connect_worker_log(order_id)
	_render_order_state()


func _on_order_status_changed(order_id: String, old_status: String, new_status: String) -> void:
	_set_record_status(order_id, new_status)
	_connect_worker_log(order_id)
	_append_log("工单状态变化：%s  %s -> %s" % [order_id, old_status, new_status])
	_render_order_state()

	if order_id != _active_order_id:
		return

	match new_status:
		"completed":
			_next_order_index += 1
			_active_order_id = ""
			_pipeline_label.text = "流水线：执行中（%d/%d）" % [_next_order_index, ORDER_DEFINITIONS.size()]
			_refresh_project_binding()
			call_deferred("_dispatch_next_order")
		"failed":
			_active_order_id = ""
			_pipeline_running = false
			_pipeline_finished = false
			_pipeline_label.text = "流水线：执行失败"
			_append_log("流水线已暂停，请查看上面的日志。")
			_update_ui_state()
		"needs_input":
			_pipeline_label.text = "流水线：等待玩家澄清"
			_append_log("当前工单需要玩家补充说明，请在 LinkChat 回答后继续等待。")
			if _workspace_tabs != null and _linkchat_app != null:
				_workspace_tabs.current_tab = _linkchat_app.get_index()
			if _linkchat_app != null and _linkchat_app.has_method("open_topic_channel"):
				_linkchat_app.open_topic_channel("dm_lin_xia")
			_update_ui_state()
		"in_progress":
			_pipeline_label.text = "流水线：执行中（%d/%d）" % [_next_order_index, ORDER_DEFINITIONS.size()]


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


func _set_record_status(order_id: String, status: String) -> void:
	for i in range(_order_records.size()):
		var record: Dictionary = _order_records[i]
		if str(record.get("order_id", "")) == order_id:
			record["status"] = status
			_order_records[i] = record
			return


func _render_order_state() -> void:
	if _orders_view == null:
		return

	var lines: PackedStringArray = []
	for i in range(ORDER_DEFINITIONS.size()):
		var spec: Dictionary = ORDER_DEFINITIONS[i]
		var title: String = str(spec.get("title", "步骤 %d" % [i + 1]))
		var line := "%d. %s" % [i + 1, title]

		if i >= _order_records.size():
			lines.append("%s\n   状态：未派发" % line)
			continue

		var record: Dictionary = _order_records[i]
		var order_id: String = str(record.get("order_id", ""))
		var order: Resource = WorkOrderManager.get_order(order_id)
		if order == null:
			lines.append("%s\n   状态：已创建，但当前内存中不存在" % line)
			continue

		var legacy_status: String = str(order.status)
		var surface_status: String = str(order.surface_status)
		var inner_status: String = str(order.inner_status)
		lines.append("%s\n   工单：%s\n   状态：legacy=%s  surface=%s  inner=%s" % [
			line,
			order_id,
			legacy_status,
			surface_status,
			inner_status,
		])

	_orders_view.text = "\n\n".join(lines)


func _append_log(message: String) -> void:
	if _log_view == null:
		return
	var timestamp := Time.get_datetime_dict_from_system()
	var prefix := "[%02d:%02d:%02d] " % [int(timestamp.get("hour", 0)), int(timestamp.get("minute", 0)), int(timestamp.get("second", 0))]
	_log_view.append_text(prefix + message + "\n")
	_log_view.scroll_to_line(_log_view.get_line_count())


func _update_ui_state() -> void:
	if _dispatch_button != null:
		_dispatch_button.disabled = false
		if not _is_runtime_project_bound():
			_dispatch_button.text = "切到 Runtime 后派发"
		elif _pipeline_finished:
			_dispatch_button.disabled = true
			_dispatch_button.text = "已全部完成"
		elif _is_waiting_for_clarification():
			_dispatch_button.disabled = true
			_dispatch_button.text = "等待澄清"
		elif not _active_order_id.is_empty():
			var active_order: Resource = WorkOrderManager.get_order(_active_order_id)
			if active_order != null and str(active_order.status) == "failed":
				_dispatch_button.text = "重试当前工单"
			else:
				_dispatch_button.disabled = _pipeline_running
				_dispatch_button.text = "继续当前工单"
		elif _next_order_index > 0:
			_dispatch_button.disabled = _pipeline_running
			_dispatch_button.text = "继续派发工单"
		else:
			_dispatch_button.disabled = _pipeline_running
			_dispatch_button.text = "派发工单"
	if _preview_button != null:
		_preview_button.disabled = not _pipeline_finished
	if _reset_button != null:
		_reset_button.disabled = false


func _get_first_scene(project: Resource) -> Resource:
	if project == null or not ("scenes" in project):
		return null
	if project.scenes == null or project.scenes.is_empty():
		return null
	return project.scenes[0]


func _sync_pipeline_from_existing_orders() -> void:
	_order_records.clear()
	_active_order_id = ""
	_pipeline_running = false
	_pipeline_finished = false
	_next_order_index = 0

	var all_orders: Array = WorkOrderManager.get_all_orders()
	var lab_orders_by_key: Dictionary = {}
	for order in all_orders:
		if order == null:
			continue
		if str(order.source_type) != "llm_build_pipeline_lab":
			continue
		lab_orders_by_key[str(order.source_id)] = order

	var found_blocker: bool = false
	for i in range(ORDER_DEFINITIONS.size()):
		var spec: Dictionary = ORDER_DEFINITIONS[i]
		var step_key: String = str(spec.get("key", ""))
		var order: Resource = lab_orders_by_key.get(step_key)
		if order != null:
			_order_records.append({
				"order_id": str(order.id),
				"title": str(order.title),
				"step_key": step_key,
				"status": str(order.status),
			})
		if found_blocker:
			continue
		if order == null:
			_next_order_index = i
			found_blocker = true
			continue
		if str(order.status) == "completed":
			_next_order_index = i + 1
			continue
		_active_order_id = str(order.id)
		_next_order_index = i
		found_blocker = true

	if not found_blocker and _next_order_index >= ORDER_DEFINITIONS.size():
		_pipeline_finished = true

	if _pipeline_finished:
		_pipeline_label.text = "流水线：全部完成（%d/%d）" % [ORDER_DEFINITIONS.size(), ORDER_DEFINITIONS.size()]
	elif not _active_order_id.is_empty():
		var active_order: Resource = WorkOrderManager.get_order(_active_order_id)
		if active_order != null and str(active_order.status) == "needs_input":
			_pipeline_label.text = "流水线：等待玩家澄清"
		elif active_order != null and str(active_order.status) == "failed":
			_pipeline_label.text = "流水线：当前工单失败，可重试"
		else:
			_pipeline_label.text = "流水线：已恢复到第 %d/%d 张工单" % [_next_order_index + 1, ORDER_DEFINITIONS.size()]
	elif _next_order_index > 0:
		_pipeline_label.text = "流水线：已完成 %d/%d，可继续派发" % [_next_order_index, ORDER_DEFINITIONS.size()]
	else:
		_pipeline_label.text = "流水线：未开始"

	_render_order_state()


func _resume_active_order() -> void:
	var order: Resource = WorkOrderManager.get_order(_active_order_id)
	if order == null:
		_active_order_id = ""
		_pipeline_running = true
		call_deferred("_dispatch_next_order")
		return
	if str(order.status) == "needs_input":
		_append_log("当前工单仍在等待玩家澄清，请先去 LinkChat 回复。")
		_update_ui_state()
		return

	_pipeline_running = true
	_pipeline_finished = false
	_pipeline_label.text = "流水线：执行中（%d/%d）" % [_next_order_index + 1, ORDER_DEFINITIONS.size()]
	_append_log("继续当前工单：%s" % order.title)
	_connect_worker_log(_active_order_id)

	if WorkOrderManager.has_method("resume_order_generation"):
		var resumed: bool = WorkOrderManager.resume_order_generation(_active_order_id)
		if resumed:
			_append_log("已定向恢复当前工单。")
	elif WorkOrderManager.has_method("resume_pending_generations"):
		WorkOrderManager.resume_pending_generations()

	if WorkOrderManager.has_method("is_order_running") and WorkOrderManager.is_order_running(_active_order_id):
		_append_log("当前工单已有后台 worker，继续等待执行结果。")
		_update_ui_state()
		return
	if _has_pending_generation(_active_order_id):
		_pipeline_label.text = "流水线：等待其他工单结束"
		_append_log("检测到仍有其他后台工单在执行，暂不重复派发当前工单。")
		_update_ui_state()
		return

	var redispatch_ok: bool = WorkOrderManager.dispatch_order(_active_order_id)
	if not redispatch_ok:
		_pipeline_running = false
		_pipeline_label.text = "流水线：恢复失败"
		_append_log("恢复当前工单失败，请查看 WorkOrder 日志。")
	else:
		_connect_worker_log(_active_order_id)
	_update_ui_state()


func _is_waiting_for_clarification() -> bool:
	if _active_order_id.is_empty():
		return false
	var order: Resource = WorkOrderManager.get_order(_active_order_id)
	return order != null and str(order.status) == "needs_input"


func _has_pending_generation(except_order_id: String = "") -> bool:
	if WorkOrderManager == null or not WorkOrderManager.has_method("_get_generating_order_ids"):
		return false
	return not WorkOrderManager._get_generating_order_ids(except_order_id).is_empty()


func get_pipeline_snapshot() -> Dictionary:
	return {
		"active_order_id": _active_order_id,
		"next_order_index": _next_order_index,
		"pipeline_running": _pipeline_running,
		"pipeline_finished": _pipeline_finished,
		"record_count": _order_records.size(),
	}
