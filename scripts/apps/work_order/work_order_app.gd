class_name WorkOrderApp extends Control
## 任务列表App — 简化版（无 AP 消耗）
## 玩家创建工单 → 直接派发给 LLM Controller → 等待完成

@warning_ignore("unused_signal")
signal close_requested()

enum FilterOption { ALL, IN_PROGRESS, PENDING, COMPLETED }

var _current_filter: FilterOption = FilterOption.ALL
var _selected_order_id: String = ""
var _is_creating: bool = false

var _work_order_manager: Node = null

@onready var new_button: Button = %NewButton
@onready var filter_dropdown: OptionButton = %FilterDropdown
@onready var order_list: ItemList = %OrderList
@onready var detail_panel: Control = %DetailPanel
@onready var title_edit: LineEdit = %TitleEdit
@onready var status_label: Label = %StatusLabel
@onready var description_edit: TextEdit = %DescriptionEdit
@onready var dispatch_button: Button = %ConsumeAPButton
@onready var delete_button: Button = %DeleteButton
@onready var empty_hint: Label = %EmptyHint


func _ready() -> void:
	_work_order_manager = get_node_or_null("/root/WorkOrderManager")
	if _work_order_manager == null:
		push_error("[WorkOrderApp] WorkOrderManager autoload not found!")
		return

	title_edit.editable = false
	description_edit.editable = false
	dispatch_button.hide()

	_setup_filter_dropdown()
	_setup_connections()
	_refresh_order_list()
	_update_detail_panel()


func _setup_filter_dropdown() -> void:
	if not filter_dropdown: return
	filter_dropdown.clear()
	filter_dropdown.add_item("全部", FilterOption.ALL)
	filter_dropdown.add_item("进行中", FilterOption.IN_PROGRESS)
	filter_dropdown.add_item("待推进", FilterOption.PENDING)
	filter_dropdown.add_item("已完成", FilterOption.COMPLETED)


func _setup_connections() -> void:
	new_button.pressed.connect(_on_new_pressed)
	if filter_dropdown: filter_dropdown.item_selected.connect(_on_filter_changed)
	order_list.item_selected.connect(_on_order_selected)
	dispatch_button.pressed.connect(_on_dispatch_pressed)
	if delete_button: delete_button.pressed.connect(_on_delete_pressed)

	_work_order_manager.order_created.connect(func(_id: String) -> void: _refresh_order_list())
	_work_order_manager.order_updated.connect(func(_id: String) -> void:
		_refresh_order_list(); _update_detail_panel())
	_work_order_manager.order_deleted.connect(func(_id: String) -> void:
		if _selected_order_id == _id:
			_selected_order_id = ""
			_update_detail_panel()
		_refresh_order_list())
	_work_order_manager.order_status_changed.connect(func(_id: String, _o: String, _n: String) -> void:
		_refresh_order_list(); _update_detail_panel())


func refresh_ui() -> void:
	_refresh_order_list()
	_update_detail_panel()


# =============================================================================
# 新建 & 派发
# =============================================================================

func _on_new_pressed() -> void:
	if _is_creating:
		return # 已经在创建模式，忽略
	_is_creating = true
	_selected_order_id = ""
	empty_hint.hide()
	detail_panel.show()
	title_edit.editable = true
	title_edit.text = ""
	title_edit.placeholder_text = "输入工单标题..."
	description_edit.editable = true
	description_edit.text = ""
	description_edit.placeholder_text = "描述你想让 AI 完成的任务..."
	status_label.text = "新建"
	status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	dispatch_button.show()
	dispatch_button.text = "派发工单"
	dispatch_button.disabled = false
	if delete_button:
		delete_button.text = "取消"


func _on_dispatch_pressed() -> void:
	if not _is_creating:
		return
	var title: String = title_edit.text.strip_edges()
	var desc: String = description_edit.text.strip_edges()
	if title.is_empty():
		status_label.text = "请输入标题"
		return
	if desc.is_empty():
		status_label.text = "请输入需求描述"
		return

	var order: Resource = _work_order_manager.create_order(title, desc, {
		"source_type": "manual",
		"source_id": "",
	})
	order.assignee_npc_id = "npc_lin_xia"
	_work_order_manager.dispatch_order(order.id)

	_exit_create_mode()
	_selected_order_id = order.id
	_refresh_order_list()
	_update_detail_panel()
	print("[WorkOrderApp] 工单已派发: %s" % order.id)


func _exit_create_mode() -> void:
	_is_creating = false
	title_edit.editable = false
	description_edit.editable = false
	dispatch_button.hide()
	new_button.text = "新建工单"
	if delete_button: delete_button.text = "放弃"


# =============================================================================
# 事件处理
# =============================================================================

func _on_filter_changed(index: int) -> void:
	_current_filter = filter_dropdown.get_item_id(index) as FilterOption
	_refresh_order_list()


func _on_order_selected(index: int) -> void:
	if _is_creating:
		_exit_create_mode()
	_selected_order_id = order_list.get_item_metadata(index)
	_update_detail_panel()


func _on_delete_pressed() -> void:
	if _is_creating:
		_exit_create_mode()
		_update_detail_panel()
		return
	if _selected_order_id.is_empty(): return
	_work_order_manager.delete_order(_selected_order_id)
	_selected_order_id = ""
	_update_detail_panel()


# =============================================================================
# UI 刷新
# =============================================================================

func _refresh_order_list() -> void:
	order_list.clear()
	var orders: Array = _work_order_manager.get_all_orders()
	orders.sort_custom(func(a, b): return a.created_at > b.created_at)

	for order in orders:
		var surf: String = order.surface_status
		if surf.is_empty():
			surf = order.status
		if _current_filter == FilterOption.IN_PROGRESS and surf not in ["in_progress", "milestone_ready"]:
			continue
		if _current_filter == FilterOption.PENDING and surf not in ["pending", "needs_input", "awaiting_player"]:
			continue
		if _current_filter == FilterOption.COMPLETED and surf not in ["completed", "delivered"]:
			continue

		var item_text: String = "[待办] " + order.title
		match surf:
			"completed", "delivered":
				item_text = "[完成] " + order.title
			"in_progress":
				item_text = "[制作中] " + order.title
			"needs_input":
				item_text = "[待确认] " + order.title
			"awaiting_player":
				item_text = "[待讨论] " + order.title
			"milestone_ready":
				item_text = "[可预览] " + order.title

		order_list.add_item(item_text)
		var idx: int = order_list.item_count - 1
		order_list.set_item_metadata(idx, order.id)
		if order.id == _selected_order_id:
			order_list.select(idx)


func _update_detail_panel() -> void:
	if _is_creating: return
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
	dispatch_button.hide()
	title_edit.text = order.title
	description_edit.text = order.description
	status_label.text = order.get_status_display_name()
	status_label.add_theme_color_override("font_color", order.get_status_color())
	if delete_button: delete_button.disabled = (order.surface_status == "completed")
