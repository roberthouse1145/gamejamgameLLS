class_name ConditionEditorController extends RefCounted
## 条件编辑控制器 — 可复用的条件命令编辑逻辑
## 被 command_tab_panel（tab条件）和 choice_editor_dialog（选项条件）共用
## 不是场景节点，由外部传入 UI 引用

const CDU = preload("res://scripts/apps/scene_editor/command_display_utils.gd")

## 条件变化信号
signal condition_changed()

## UI 引用（由外部传入）
var condition_command_dialog: Window = null
var condition_param_dialog: Window = null
var cond_param_container: VBoxContainer = null

## 变量选择器控制器
var var_picker: RefCounted = null

## 当前场景（用于变量选择器显示本地变量）
var current_scene: Resource = null

## 当前编辑的条件命令
var _editing_cmd: Resource = null
var _editing_index: int = -1
## 条件参数编辑临时控件引用
var _cond_var_button: Button = null
var _cond_op_option: OptionButton = null
var _cond_value_input: LineEdit = null
var _cond_node_id_input: LineEdit = null


## 初始化 — 传入 UI 引用
func initialize(refs: Dictionary) -> void:
	condition_command_dialog = refs.get("cond_cmd_dialog")
	condition_param_dialog = refs.get("cond_param_dialog")
	cond_param_container = refs.get("cond_param_container")
	var_picker = refs.get("var_picker")

	# 连接条件参数对话框信号
	if condition_param_dialog:
		condition_param_dialog.close_requested.connect(_on_param_cancel)
	var ok_btn: Button = refs.get("cond_param_ok_btn")
	var cancel_btn: Button = refs.get("cond_param_cancel_btn")
	if ok_btn:
		ok_btn.pressed.connect(_on_param_ok)
	if cancel_btn:
		cancel_btn.pressed.connect(_on_param_cancel)

	# 连接条件命令类型选择对话框
	if condition_command_dialog:
		condition_command_dialog.close_requested.connect(_on_type_dialog_closed)
	var check_var_btn: Button = refs.get("check_var_btn")
	var cond_if_btn: Button = refs.get("cond_if_btn")
	var check_hover_btn: Button = refs.get("check_hover_btn")
	var check_click_btn: Button = refs.get("check_click_btn")
	var cond_cancel_btn: Button = refs.get("cond_cancel_btn")
	if check_var_btn:
		check_var_btn.pressed.connect(_on_type_selected.bind("CHECK_VAR"))
	if cond_if_btn:
		cond_if_btn.pressed.connect(_on_type_selected.bind("IF"))
	if check_hover_btn:
		check_hover_btn.pressed.connect(_on_type_selected.bind("CHECK_HOVER"))
	if check_click_btn:
		check_click_btn.pressed.connect(_on_type_selected.bind("CHECK_CLICK"))
	if cond_cancel_btn:
		cond_cancel_btn.pressed.connect(_on_type_dialog_closed)

	# 连接变量选择器
	if var_picker:
		var_picker.variable_selected.connect(_on_variable_selected)


## 当前正在编辑的条件命令数组（外部设置）
var _target_commands: Array = []
## 编辑完成后的回调（用于区分 tab 条件 vs 选项条件）
var _on_done_callback: Callable = Callable()
## 编辑取消后的回调
var _on_cancel_callback: Callable = Callable()


## 构建条件树到指定 Tree 控件
func build_condition_tree(tree: Tree, commands: Array) -> void:
	if tree == null:
		return
	tree.clear()
	var tree_root: TreeItem = tree.create_item()

	if commands.is_empty():
		var hint_item: TreeItem = tree.create_item(tree_root)
		hint_item.set_text(0, "(无条件)")
		hint_item.set_custom_color(0, Color(0.5, 0.5, 0.5))
		hint_item.set_selectable(0, false)
	else:
		for i in range(commands.size()):
			var cmd = commands[i]
			if cmd == null:
				continue
			var cmd_type: String = cmd.command_type if cmd is Resource and "command_type" in cmd else ""
			if cmd_type == "CHECK_VAR":
				var item: TreeItem = tree.create_item(tree_root)
				var var_id: String = cmd.params.get("variable_id", "") if cmd.params else ""
				var vn: String = cmd.params.get("variable_name", "?") if cmd.params else "?"
				var display_name: String = CDU.resolve_variable_display(var_id, vn)
				var op: String = cmd.params.get("operator", ">=") if cmd.params else ">="
				var val = cmd.params.get("value", "0") if cmd.params else "0"
				item.set_text(0, "%s %s %s" % [display_name, op, str(val)])
				item.set_metadata(0, {"type": "CHECK_VAR", "index": i})
			elif cmd_type == "CHECK_HOVER":
				var item: TreeItem = tree.create_item(tree_root)
				var nid: String = cmd.params.get("node_id", "") if cmd.params else ""
				var display: String = "悬停(%s)" % nid if not nid.is_empty() else "悬停(自身)"
				item.set_text(0, display)
				item.set_metadata(0, {"type": "CHECK_HOVER", "index": i})
			elif cmd_type == "CHECK_CLICK":
				var item: TreeItem = tree.create_item(tree_root)
				var nid2: String = cmd.params.get("node_id", "") if cmd.params else ""
				var display2: String = "点击(%s)" % nid2 if not nid2.is_empty() else "点击(自身)"
				item.set_text(0, display2)
				item.set_metadata(0, {"type": "CHECK_CLICK", "index": i})
			elif cmd_type == "IF":
				var item: TreeItem = tree.create_item(tree_root)
				var sub_conds: Array = cmd.params.get("condition_commands", []) if cmd.params else []
				item.set_text(0, "IF [%s]" % CDU.get_condition_summary(sub_conds))
				item.set_metadata(0, {"type": "IF", "index": i})


## 打开条件类型选择对话框，添加条件到指定数组
func add_condition_to(commands: Array, on_done: Callable = Callable(), on_cancel: Callable = Callable()) -> void:
	_target_commands = commands
	_on_done_callback = on_done
	_on_cancel_callback = on_cancel
	if condition_command_dialog:
		condition_command_dialog.popup_centered()


## 编辑已有条件（双击条件项）
func edit_condition(cmd: Resource, index: int, on_done: Callable = Callable(), on_cancel: Callable = Callable()) -> void:
	_editing_cmd = cmd
	_editing_index = index
	_on_done_callback = on_done
	_on_cancel_callback = on_cancel
	if cmd.command_type == "CHECK_VAR":
		_show_check_var_param_dialog(cmd)
	elif cmd.command_type == "CHECK_HOVER" or cmd.command_type == "CHECK_CLICK":
		_show_node_id_param_dialog(cmd)


## 删除条件（从指定数组中按索引删除）
func delete_condition_at(commands: Array, index: int) -> void:
	if index >= 0 and index < commands.size():
		commands.remove_at(index)
		condition_changed.emit()


## 获取当前编辑的条件命令
func get_editing_cmd() -> Resource:
	return _editing_cmd


# ============ 内部逻辑 ============

## 条件类型选择对话框关闭
func _on_type_dialog_closed() -> void:
	if condition_command_dialog:
		condition_command_dialog.hide()


## 选择条件命令类型
func _on_type_selected(cmd_type: String) -> void:
	if condition_command_dialog:
		condition_command_dialog.hide()

	var new_cmd: Resource = CDU.create_command(cmd_type)
	_target_commands.append(new_cmd)

	if cmd_type == "CHECK_VAR":
		_editing_cmd = new_cmd
		_editing_index = _target_commands.size() - 1
		_show_check_var_param_dialog(new_cmd)
	elif cmd_type == "CHECK_HOVER" or cmd_type == "CHECK_CLICK":
		_editing_cmd = new_cmd
		_editing_index = _target_commands.size() - 1
		_show_node_id_param_dialog(new_cmd)
	else:
		condition_changed.emit()
		if _on_done_callback.is_valid():
			_on_done_callback.call()


## 显示 CHECK_VAR 参数编辑对话框
func _show_check_var_param_dialog(cmd: Resource) -> void:
	if cond_param_container == null or condition_param_dialog == null:
		return

	for child in cond_param_container.get_children():
		child.queue_free()

	var params: Dictionary = cmd.params if cmd.params else {}

	# 变量名按钮
	var var_hbox := HBoxContainer.new()
	var var_label := Label.new()
	var_label.text = "变量:"
	var_label.custom_minimum_size.x = 60
	var_hbox.add_child(var_label)
	_cond_var_button = Button.new()
	var current_var_id: String = params.get("variable_id", "")
	var current_var_name: String = params.get("variable_name", "")
	var display_text: String = CDU.resolve_variable_display(current_var_id, current_var_name)
	_cond_var_button.text = display_text if display_text != "?" else "(点击选择)"
	_cond_var_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cond_var_button.pressed.connect(_on_open_var_picker)
	# 存储已有的 ID/名称
	if not current_var_id.is_empty():
		_cond_var_button.set_meta("variable_id", current_var_id)
	if not current_var_name.is_empty():
		_cond_var_button.set_meta("variable_name", current_var_name)
	var_hbox.add_child(_cond_var_button)
	cond_param_container.add_child(var_hbox)

	# 运算符
	var op_hbox := HBoxContainer.new()
	var op_label := Label.new()
	op_label.text = "运算符:"
	op_label.custom_minimum_size.x = 60
	op_hbox.add_child(op_label)
	_cond_op_option = OptionButton.new()
	_cond_op_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for op in CDU.CONDITION_OPERATORS:
		_cond_op_option.add_item(op)
	var current_op: String = params.get("operator", ">=")
	var op_idx: int = CDU.CONDITION_OPERATORS.find(current_op)
	if op_idx >= 0:
		_cond_op_option.select(op_idx)
	op_hbox.add_child(_cond_op_option)
	cond_param_container.add_child(op_hbox)

	# 比较值
	var val_hbox := HBoxContainer.new()
	var val_label := Label.new()
	val_label.text = "值:"
	val_label.custom_minimum_size.x = 60
	val_hbox.add_child(val_label)
	_cond_value_input = LineEdit.new()
	_cond_value_input.text = str(params.get("value", "0"))
	_cond_value_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cond_value_input.placeholder_text = "比较值"
	val_hbox.add_child(_cond_value_input)
	cond_param_container.add_child(val_hbox)

	condition_param_dialog.popup_centered()


## 显示 CHECK_HOVER / CHECK_CLICK 参数编辑对话框（只需 node_id）
func _show_node_id_param_dialog(cmd: Resource) -> void:
	if cond_param_container == null or condition_param_dialog == null:
		return

	for child in cond_param_container.get_children():
		child.queue_free()

	var params: Dictionary = cmd.params if cmd.params else {}

	# 节点 ID 输入
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "节点ID:"
	lbl.custom_minimum_size.x = 60
	hbox.add_child(lbl)
	_cond_node_id_input = LineEdit.new()
	_cond_node_id_input.text = params.get("node_id", "")
	_cond_node_id_input.placeholder_text = "留空=自身节点"
	_cond_node_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_cond_node_id_input)
	cond_param_container.add_child(hbox)

	condition_param_dialog.popup_centered()


## 打开变量选择器
func _on_open_var_picker() -> void:
	if var_picker:
		var_picker.set_current_scene(current_scene)
		var_picker.open(_editing_cmd)


## 变量选择完成回调
func _on_variable_selected(var_id: String, var_name: String) -> void:
	if _cond_var_button:
		if not var_id.is_empty():
			_cond_var_button.text = "%s(%s)" % [var_id, var_name]
		else:
			_cond_var_button.text = var_name
		_cond_var_button.set_meta("variable_id", var_id)
		_cond_var_button.set_meta("variable_name", var_name)


## 条件参数确定
func _on_param_ok() -> void:
	if _editing_cmd != null:
		var cmd_type: String = _editing_cmd.command_type if "command_type" in _editing_cmd else ""
		if cmd_type == "CHECK_VAR":
			if _cond_var_button and _cond_var_button.text != "(点击选择)":
				_editing_cmd.params["variable_id"] = _cond_var_button.get_meta("variable_id", "")
				_editing_cmd.params["variable_name"] = _cond_var_button.get_meta("variable_name", "")
			if _cond_op_option and _cond_op_option.selected >= 0:
				_editing_cmd.params["operator"] = CDU.CONDITION_OPERATORS[_cond_op_option.selected]
			if _cond_value_input:
				_editing_cmd.params["value"] = _cond_value_input.text.strip_edges()
		elif cmd_type == "CHECK_HOVER" or cmd_type == "CHECK_CLICK":
			if _cond_node_id_input:
				_editing_cmd.params["node_id"] = _cond_node_id_input.text.strip_edges()

	_editing_cmd = null
	_editing_index = -1
	_cond_var_button = null
	_cond_op_option = null
	_cond_value_input = null
	_cond_node_id_input = null
	if condition_param_dialog:
		condition_param_dialog.hide()

	condition_changed.emit()
	if _on_done_callback.is_valid():
		_on_done_callback.call()
	_on_done_callback = Callable()
	_on_cancel_callback = Callable()


## 条件参数取消
func _on_param_cancel() -> void:
	var cancel_cb: Callable = _on_cancel_callback
	_editing_cmd = null
	_editing_index = -1
	_cond_var_button = null
	_cond_op_option = null
	_cond_value_input = null
	_cond_node_id_input = null
	if condition_param_dialog:
		condition_param_dialog.hide()
	if cancel_cb.is_valid():
		cancel_cb.call()
	_on_done_callback = Callable()
	_on_cancel_callback = Callable()
