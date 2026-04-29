class_name VariablePickerController extends RefCounted
## 变量选择器控制器 — 管理变量选择对话框的逻辑
## 新变量系统仅支持项目级变量
## 不是场景节点，由 scene_editor 传入 UI 引用

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

## 选择完成信号 (variable_id, variable_key)
signal variable_selected(var_id: String, var_key: String)

## UI 引用（由外部传入）
var dialog: Window = null
var picker_list: ItemList = null
var select_button: Button = null
var cancel_button: Button = null
var add_button: Button = null
var delete_button: Button = null
var editor: Control = null

## 状态
var _selected_index: int = -1
## 当前编辑的条件命令（用于自动选中已有变量）
var _current_cmd: Resource = null
## 当前场景（兼容旧调用，已不再使用）
var _current_scene: Resource = null
## 当前选中的 tab: 仅保留 0=项目变量
var _current_tab: int = 0
## Tab 按钮引用
var _tab_global_btn: Button = null
var _tab_local_btn: Button = null
## Tab 容器
var _tab_bar: HBoxContainer = null
## 预选变量 ID（从外部传入，用于自动选中）
var _preselect_var_id: String = ""


## 初始化 — 传入 UI 节点引用并连接信号
func initialize(refs: Dictionary) -> void:
	dialog = refs.get("dialog")
	picker_list = refs.get("list")
	select_button = refs.get("select_btn")
	cancel_button = refs.get("cancel_btn")
	add_button = refs.get("add_btn")
	delete_button = refs.get("delete_btn")
	editor = refs.get("editor")

	if dialog:
		dialog.close_requested.connect(_on_cancel)
	if picker_list:
		picker_list.item_selected.connect(_on_item_selected)
	if select_button:
		select_button.pressed.connect(_on_select)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel)
	if add_button:
		add_button.pressed.connect(_on_add)
	if delete_button:
		delete_button.pressed.connect(_on_delete)

	# 在 picker_list 上方插入 tab 栏
	_create_tab_bar()


## 创建 tab 栏（兼容旧 UI，默认隐藏）
func _create_tab_bar() -> void:
	if picker_list == null:
		return
	var parent: Control = picker_list.get_parent()
	if parent == null:
		return
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "VarTabBar"
	# 插入到 picker_list 之前（ListLabel 之后）
	var list_idx: int = picker_list.get_index()
	parent.add_child(_tab_bar)
	parent.move_child(_tab_bar, list_idx)

	_tab_global_btn = Button.new()
	_tab_global_btn.text = "项目变量"
	_tab_global_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_global_btn.pressed.connect(_on_tab_switch.bind(0))
	_tab_bar.add_child(_tab_global_btn)

	_tab_local_btn = Button.new()
	_tab_local_btn.text = "场景变量"
	_tab_local_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_local_btn.pressed.connect(_on_tab_switch.bind(1))
	_tab_bar.add_child(_tab_local_btn)

	_tab_bar.visible = false


## 切换 tab
func _on_tab_switch(tab: int) -> void:
	_current_tab = 0 if tab != 0 else tab
	_selected_index = -1
	if editor and editor.has_method("set_target"):
		editor.set_target(null)
	_refresh_list()
	_update_tab_style()
	_update_list_label()


## 更新 tab 按钮样式（当前 tab 禁用）
func _update_tab_style() -> void:
	if _tab_global_btn:
		_tab_global_btn.disabled = (_current_tab == 0)
	if _tab_local_btn:
		_tab_local_btn.disabled = true


## 更新列表标题
func _update_list_label() -> void:
	if picker_list == null:
		return
	var parent: Control = picker_list.get_parent()
	if parent == null:
		return
	# 查找 ListLabel（第一个 Label 子节点）
	for child in parent.get_children():
		if child is Label and child.name == "ListLabel":
			child.text = "项目变量"
			break


## 设置当前场景（兼容旧调用，已不再使用）
func set_current_scene(scene: Resource) -> void:
	_current_scene = scene


## 打开变量选择器
func open(current_cmd: Resource = null) -> void:
	_current_cmd = current_cmd
	_preselect_var_id = ""
	_selected_index = -1
	_current_tab = 0
	_refresh_list()
	_update_tab_visibility()
	_update_tab_style()
	_update_list_label()
	if editor and editor.has_method("set_target"):
		editor.set_target(null)
	if dialog:
		dialog.popup_centered()


## 打开变量选择器（带预选 ID，由 variable_ref 按钮调用）
func open_with_preselect(var_id: String, scene: Resource = null) -> void:
	_current_cmd = null
	_preselect_var_id = var_id
	_current_scene = scene
	_selected_index = -1
	_current_tab = 0
	_refresh_list()
	_update_tab_visibility()
	_update_tab_style()
	_update_list_label()
	if editor and editor.has_method("set_target"):
		editor.set_target(null)
	if dialog:
		dialog.popup_centered()


## 更新 tab 栏可见性（场景变量已废弃，始终隐藏）
func _update_tab_visibility() -> void:
	if _tab_bar:
		_tab_bar.visible = false
	_current_tab = 0
	_update_list_label()


## 获取当前 tab 的变量列表
func _get_current_variables() -> Array:
	var project: Resource = StorageManager.current_project
	if project != null and "variables" in project and project.variables != null:
		return project.variables
	return []


## 刷新变量列表
func _refresh_list() -> void:
	if picker_list == null:
		return
	picker_list.clear()

	var variables: Array = _get_current_variables()
	for v in variables:
		var var_id: String = v.variable_id if "variable_id" in v else ""
		var var_key: String = AVGVariableClass.get_key(v)
		var display: String
		if not var_key.is_empty() and not var_id.is_empty():
			display = "%s (%s)" % [var_key, var_id]
		elif not var_key.is_empty():
			display = var_key
		elif not var_id.is_empty():
			display = var_id
		else:
			display = "(未命名变量)"
		picker_list.add_item(display)

	# 自动选中：优先用 _preselect_var_id，其次用 _current_cmd
	var target_id: String = _preselect_var_id
	var target_key: String = ""
	if target_id.is_empty() and _current_cmd != null and _current_cmd.params:
		target_id = _current_cmd.params.get("variable_id", "")
		target_key = _current_cmd.params.get("variable_key", _current_cmd.params.get("variable_name", ""))

	if not target_id.is_empty():
		for i in range(variables.size()):
			var v = variables[i]
			var vid: String = v.variable_id if "variable_id" in v else ""
			if vid == target_id:
				picker_list.select(i)
				_selected_index = i
				_on_item_selected(i)
				return
	if not target_key.is_empty():
		for i in range(variables.size()):
			if AVGVariableClass.get_key(variables[i]) == AVGVariableClass.normalize_key(target_key):
				picker_list.select(i)
				_selected_index = i
				_on_item_selected(i)
				return


## 列表项选中
func _on_item_selected(index: int) -> void:
	_selected_index = index
	var variables: Array = _get_current_variables()
	if index < 0 or index >= variables.size():
		return
	var v: Resource = variables[index]
	if editor and editor.has_method("set_target"):
		editor.set_target(v)
		if editor.has_signal("property_changed"):
			if not editor.is_connected("property_changed", _on_property_changed):
				editor.property_changed.connect(_on_property_changed)


## 变量属性被修改
func _on_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	var variables: Array = _get_current_variables()
	if _selected_index >= 0 and _selected_index < variables.size():
		AVGVariableClass.apply_key(variables[_selected_index], AVGVariableClass.get_key(variables[_selected_index]))
	var saved_index: int = _selected_index
	_refresh_list()
	if saved_index >= 0 and picker_list:
		var refreshed_variables: Array = _get_current_variables()
		if saved_index < refreshed_variables.size():
			picker_list.select(saved_index)
			_selected_index = saved_index
	StorageManager.notify_content_changed()


## 添加新变量
func _on_add() -> void:
	_add_global_variable()


## 添加全局变量（使用槽位制 ID，与 variable_list_panel 一致）
func _add_global_variable() -> void:
	var project: Resource = StorageManager.current_project
	if project == null or not "variables" in project:
		return
	# 找到下一个可用槽位号
	var used_slots: Dictionary = {}
	for v in project.variables:
		var vid: String = v.variable_id if "variable_id" in v else ""
		if vid.begins_with("var_") and vid.substr(4).is_valid_int():
			used_slots[int(vid.substr(4))] = true
	var next_slot: int = 1
	while used_slots.has(next_slot):
		next_slot += 1
	var new_var: Resource = AVGVariableClass.new()
	new_var.variable_id = AVGVariableClass.make_id(next_slot)
	AVGVariableClass.apply_key(new_var, AVGVariableClass.make_default_key(next_slot))
	new_var.value_type = AVGVariableClass.VALUE_TYPE_INT
	new_var.default_value = 0
	project.variables.append(new_var)
	_refresh_list()
	var new_idx: int = project.variables.size() - 1
	if picker_list:
		picker_list.select(new_idx)
	_on_item_selected(new_idx)
	StorageManager.notify_content_changed()


## 删除选中变量
func _on_delete() -> void:
	var variables: Array = _get_current_variables()
	if _selected_index < 0 or _selected_index >= variables.size():
		return
	variables.remove_at(_selected_index)
	if _selected_index >= variables.size():
		_selected_index = variables.size() - 1
	_refresh_list()
	if _selected_index >= 0:
		if picker_list:
			picker_list.select(_selected_index)
		_on_item_selected(_selected_index)
	else:
		if editor and editor.has_method("set_target"):
			editor.set_target(null)
	StorageManager.notify_content_changed()


## 确认选择
func _on_select() -> void:
	var variables: Array = _get_current_variables()
	if _selected_index < 0 or _selected_index >= variables.size():
		_on_cancel()
		return
	var v: Resource = variables[_selected_index]
	var var_id: String = v.variable_id if "variable_id" in v else ""
	var var_key: String = AVGVariableClass.get_key(v)
	variable_selected.emit(var_id, var_key)
	if dialog:
		dialog.hide()


## 取消
func _on_cancel() -> void:
	if dialog:
		dialog.hide()
