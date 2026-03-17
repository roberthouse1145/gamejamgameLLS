class_name WorkOrderApp extends Control
## 任务列表App主界面 (Task App)
## 面向玩家的经过包装的"待办清单"。玩家在此消耗 AP 推进工作。

# 信号
signal close_requested()

# 过滤选项
enum FilterOption {
	ALL, ## 全部
	IN_PROGRESS, ## 进行中
	PENDING, ## 待处理
	COMPLETED ## 已完成
}

# 当前过滤选项
var _current_filter: FilterOption = FilterOption.ALL

# 当前选中的工单ID
var _selected_order_id: String = ""

# Autoload引用
var _work_order_manager: Node = null
var _game_loop_manager: Node = null

# UI节点引用
@onready var filter_dropdown: OptionButton = %FilterDropdown
@onready var order_list: ItemList = %OrderList

@onready var detail_panel: Control = %DetailPanel
@onready var title_edit: LineEdit = %TitleEdit
@onready var status_label: Label = %StatusLabel
@onready var description_edit: TextEdit = %DescriptionEdit

@onready var spec_container: VBoxContainer = %SpecContainer
@onready var requirements_label: RichTextLabel = %RequirementsLabel
@onready var tasks_container: VBoxContainer = %TasksContainer

@onready var consume_ap_button: Button = %ConsumeAPButton
@onready var delete_button: Button = %DeleteButton
@onready var empty_hint: Label = %EmptyHint


func _ready() -> void:
	_work_order_manager = get_node_or_null("/root/WorkOrderManager")
	_game_loop_manager = get_node_or_null("/root/GameLoopManager")
	
	if _work_order_manager == null:
		push_error("[WorkOrderApp] WorkOrderManager autoload not found!")
		return
		
	# 强行隐藏只读组件
	title_edit.editable = false
	description_edit.editable = false
	
	_setup_filter_dropdown()
	_setup_connections()
	_refresh_order_list()
	_update_detail_panel()


func _setup_filter_dropdown() -> void:
	if filter_dropdown == null: return
	filter_dropdown.clear()
	filter_dropdown.add_item("全部", FilterOption.ALL)
	filter_dropdown.add_item("进行中", FilterOption.IN_PROGRESS)
	filter_dropdown.add_item("待推进", FilterOption.PENDING)
	filter_dropdown.add_item("已完成", FilterOption.COMPLETED)


func _setup_connections() -> void:
	# UI信号
	if filter_dropdown: filter_dropdown.item_selected.connect(_on_filter_changed)
	order_list.item_selected.connect(_on_order_selected)
	
	if consume_ap_button: consume_ap_button.pressed.connect(_on_consume_ap_pressed)
	if delete_button: delete_button.pressed.connect(_on_delete_pressed)
	
	# WorkOrderManager信号
	_work_order_manager.order_created.connect(_on_order_created)
	_work_order_manager.order_updated.connect(_on_order_updated)
	_work_order_manager.order_deleted.connect(_on_order_deleted)
	_work_order_manager.order_status_changed.connect(_on_order_status_changed)
	
	# GameLoopManager 信号 (用于刷新 AP 按钮状态)
	if _game_loop_manager:
		if _game_loop_manager.has_signal("ap_changed"):
			_game_loop_manager.ap_changed.connect(_on_ap_changed)
		if _game_loop_manager.has_signal("phase_changed"):
			_game_loop_manager.phase_changed.connect(_on_phase_changed)


# =============================================================================
# API Updates
# =============================================================================

func refresh_ui() -> void:
	_refresh_order_list()
	_update_detail_panel()


# =============================================================================
# Event Handlers: UI
# =============================================================================

func _on_filter_changed(index: int) -> void:
	_current_filter = filter_dropdown.get_item_id(index) as FilterOption
	_refresh_order_list()


func _on_order_selected(index: int) -> void:
	_selected_order_id = order_list.get_item_metadata(index)
	_update_detail_panel()


func _on_consume_ap_pressed() -> void:
	if _selected_order_id.is_empty(): return
	
	if _game_loop_manager == null or not _game_loop_manager.has_method("consume_ap"):
		push_error("[WorkOrderApp] GameLoopManager.consume_ap missing!")
		return
		
	# 检查玩家是否有能力花这个 AP
	if not _game_loop_manager.can_consume_ap(1):
		# TODO: 显示一个漂浮提示"本时段已行动", 或者是系统提示声
		return
		
	# 尝试扣属性
	var success = _game_loop_manager.consume_ap(1, "work_order")
	if success:
		# 推进进度
		_work_order_manager.progress_order(_selected_order_id, 1)
		_update_detail_panel()


func _on_delete_pressed() -> void:
	if _selected_order_id.is_empty(): return
	# 玩家手动放弃任务
	_work_order_manager.delete_order(_selected_order_id)
	_selected_order_id = ""
	_update_detail_panel()


# =============================================================================
# Event Handlers: WorkOrderManager & GameLoopManager
# =============================================================================

func _on_order_created(_order_id: String) -> void: _refresh_order_list()
func _on_order_updated(_order_id: String) -> void:
	_refresh_order_list()
	_update_detail_panel()
	
func _on_order_deleted(_order_id: String) -> void:
	if _selected_order_id == _order_id:
		_selected_order_id = ""
		_update_detail_panel()
	_refresh_order_list()
	
func _on_order_status_changed(_order_id: String, _old_status: String, _new_status: String) -> void:
	_refresh_order_list()
	_update_detail_panel()

func _on_ap_changed(_current_ap: int, _max_ap: int) -> void:
	_update_consume_button_state()
	
func _on_phase_changed(_new_phase: int) -> void:
	_update_consume_button_state()

# =============================================================================
# UI Updaters
# =============================================================================

func _refresh_order_list() -> void:
	order_list.clear()
	var orders: Array = _work_order_manager.get_all_orders()
	
	# 按创建时间降序排序
	orders.sort_custom(func(a, b): return a.created_at > b.created_at)
	
	for order in orders:
		# 过滤隐藏系统私有或后台生成的
		var surf_status = order.has_method("get") and order.get("surface_status")
		if not surf_status: surf_status = order.surface_status
			
		# 根据过滤选项筛选
		if surf_status != "pending" and surf_status != "in_progress" and surf_status != "completed":
			continue # 忽略未处理状态
			
		if _current_filter == FilterOption.IN_PROGRESS and surf_status != "in_progress": continue
		if _current_filter == FilterOption.PENDING and surf_status != "pending": continue
		if _current_filter == FilterOption.COMPLETED and surf_status != "completed": continue
		
		# 添加列表项
		var item_text: String = "[待办] " + order.title
		if surf_status == "completed": item_text = "[完成] " + order.title
		elif surf_status == "in_progress": item_text = "[进行中] " + order.title
		
		order_list.add_item(item_text)
		var item_idx: int = order_list.item_count - 1
		order_list.set_item_metadata(item_idx, order.id)
		
		# 恢复选中状态
		if order.id == _selected_order_id:
			order_list.select(item_idx)


func _update_detail_panel() -> void:
	if _selected_order_id.is_empty():
		detail_panel.hide()
		empty_hint.show()
		return
		
	var order: Resource = _work_order_manager.get_order(_selected_order_id)
	if order == null:
		_selected_order_id = ""
		detail_panel.hide()
		empty_hint.show()
		return
		
	empty_hint.hide()
	detail_panel.show()
	
	# 基本信息显示（只读）
	title_edit.text = order.title
	description_edit.text = order.description
	status_label.text = order.get_status_display_name()
	status_label.add_theme_color_override("font_color", order.get_status_color())
	
	# 从知识库自动拉取的Spec需求部分（如果不空）
	if order.spec and not order.spec.get("tasks", []).is_empty():
		spec_container.show()
		requirements_label.text = order.spec.get("requirements_text", "")
		_refresh_tasks_ui(order)
	else:
		spec_container.hide()
		
	_update_consume_button_state()
	
	# 允许玩家主动放弃处于早期阶段的任务
	delete_button.disabled = false


func _refresh_tasks_ui(order: Resource) -> void:
	# 清空现有任务条目
	for child in tasks_container.get_children():
		child.queue_free()
		
	# 任务列表显示（只读）
	var tasks: Array = order.spec.get("tasks", [])
	if tasks.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "暂无具体任务列表"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		tasks_container.add_child(empty_lbl)
		return
		
	for task in tasks:
		var cb: CheckBox = CheckBox.new()
		cb.text = task.get("description", "Unknown Task")
		cb.button_pressed = task.get("done", false)
		cb.disabled = true # 玩家不能手动点，由Worker或全局进度推送
		tasks_container.add_child(cb)


func _update_consume_button_state() -> void:
	if _selected_order_id.is_empty() or not consume_ap_button: return
	var order: Resource = _work_order_manager.get_order(_selected_order_id)
	if not order: return
	
	# 判断是否能投入 AP
	var can_consume: bool = true
	var current = order.current_progress_ap
	var req = order.required_ap
	
	consume_ap_button.text = "投入当前时段行动 - 进度: %d/%d" % [current, req]

	if order.surface_status == "completed":
		can_consume = false
		consume_ap_button.text = "任务已完成"
		
	elif current >= req:
		can_consume = false
		consume_ap_button.text = "时间投入已满，等待完工"
		
	elif _game_loop_manager != null and not _game_loop_manager.can_consume_ap(1):
		can_consume = false
		consume_ap_button.text = "本时段已行动，稍后再来"
		
	consume_ap_button.disabled = not can_consume
