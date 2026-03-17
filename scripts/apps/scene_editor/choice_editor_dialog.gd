class_name ChoiceEditorDialog extends RefCounted
## 选项编辑对话框 — 管理 CHOICE 命令的选项列表和属性编辑
## 动态创建 Window，内含选项列表、属性编辑区、条件编辑

const CDU = preload("res://scripts/apps/scene_editor/command_display_utils.gd")

## 选项变化信号（关闭时刷新命令树）
signal choice_changed()

## 条件编辑控制器（复用）
var condition_editor: RefCounted = null

## 对话框和 UI 控件
var _dialog: Window = null
var _choice_list: ItemList = null
var _text_input: LineEdit = null
var _hidden_option: OptionButton = null
var _cond_tree: Tree = null

## 当前编辑的 CHOICE 命令
var _cmd: Resource = null
## 当前选中的选项索引
var _selected: int = -1
## 父节点（用于 add_child）
var _parent: Control = null


## 初始化
func initialize(parent: Control, cond_editor: RefCounted) -> void:
	_parent = parent
	condition_editor = cond_editor


## 打开选项编辑对话框
func open(cmd: Resource, focus_choice: int = -1) -> void:
	if cmd == null or cmd.command_type != "CHOICE":
		return
	_cmd = cmd
	_selected = -1
	_ensure_dialog()
	_refresh_list()

	if focus_choice >= 0 and _choice_list:
		var choices: Array = cmd.params.get("choices", [])
		if focus_choice < choices.size():
			_choice_list.select(focus_choice)
			_on_list_selected(focus_choice)

	_dialog.popup_centered()


## 确保对话框已创建
func _ensure_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		return

	_dialog = Window.new()
	_dialog.title = "编辑选项"
	_dialog.size = Vector2i(600, 500)
	_dialog.exclusive = true
	_dialog.close_requested.connect(_on_close)
	_parent.add_child(_dialog)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	_dialog.add_child(root_vbox)

	# 选项列表
	var list_label := Label.new()
	list_label.text = "选项列表:"
	root_vbox.add_child(list_label)

	_choice_list = ItemList.new()
	_choice_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_list.custom_minimum_size.y = 120
	_choice_list.item_selected.connect(_on_list_selected)
	root_vbox.add_child(_choice_list)

	var list_btn_hbox := HBoxContainer.new()
	var add_btn := Button.new()
	add_btn.text = "添加选项"
	add_btn.pressed.connect(_on_add)
	list_btn_hbox.add_child(add_btn)
	var del_btn := Button.new()
	del_btn.text = "删除选项"
	del_btn.pressed.connect(_on_delete)
	list_btn_hbox.add_child(del_btn)
	root_vbox.add_child(list_btn_hbox)

	root_vbox.add_child(HSeparator.new())

	# 属性编辑区
	var prop_label := Label.new()
	prop_label.text = "选中选项属性:"
	root_vbox.add_child(prop_label)

	var text_hbox := HBoxContainer.new()
	var text_lbl := Label.new()
	text_lbl.text = "文本:"
	text_lbl.custom_minimum_size.x = 100
	text_hbox.add_child(text_lbl)
	_text_input = LineEdit.new()
	_text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_input.placeholder_text = "输入选项文本"
	_text_input.text_changed.connect(_on_text_changed)
	text_hbox.add_child(_text_input)
	root_vbox.add_child(text_hbox)

	var hidden_hbox := HBoxContainer.new()
	var hidden_lbl := Label.new()
	hidden_lbl.text = "不满足时:"
	hidden_lbl.custom_minimum_size.x = 100
	hidden_hbox.add_child(hidden_lbl)
	_hidden_option = OptionButton.new()
	_hidden_option.add_item("灰暗(不可选)", 0)
	_hidden_option.add_item("隐藏", 1)
	_hidden_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hidden_option.item_selected.connect(_on_hidden_changed)
	hidden_hbox.add_child(_hidden_option)
	root_vbox.add_child(hidden_hbox)

	# 条件树
	var cond_label := Label.new()
	cond_label.text = "显示条件 (空=始终显示):"
	root_vbox.add_child(cond_label)

	_cond_tree = Tree.new()
	_cond_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cond_tree.custom_minimum_size.y = 80
	_cond_tree.hide_root = true
	_cond_tree.item_activated.connect(_on_cond_item_activated)
	root_vbox.add_child(_cond_tree)

	var cond_btn_hbox := HBoxContainer.new()
	var add_cond_btn := Button.new()
	add_cond_btn.text = "添加条件"
	add_cond_btn.pressed.connect(_on_cond_add)
	cond_btn_hbox.add_child(add_cond_btn)
	var del_cond_btn := Button.new()
	del_cond_btn.text = "删除条件"
	del_cond_btn.pressed.connect(_on_cond_delete)
	cond_btn_hbox.add_child(del_cond_btn)
	root_vbox.add_child(cond_btn_hbox)

	# 底部确定按钮
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_END
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size.x = 80
	ok_btn.pressed.connect(_on_close)
	bottom_hbox.add_child(ok_btn)
	root_vbox.add_child(bottom_hbox)


# ============ 列表操作 ============

func _refresh_list() -> void:
	if _choice_list == null or _cmd == null:
		return
	_choice_list.clear()
	var choices: Array = _cmd.params.get("choices", [])
	for i in range(choices.size()):
		var choice: Dictionary = choices[i] if choices[i] is Dictionary else {}
		var text: String = choice.get("text", "")
		var cond_cmds: Array = choice.get("condition_commands", [])
		var hide_unmet: bool = choice.get("hidden_when_unmet", false)
		var display: String = "%d. \"%s\"" % [i + 1, text]
		if not cond_cmds.is_empty():
			var mode_str: String = "隐藏" if hide_unmet else "灰暗"
			display += "  [%s, %s]" % [CDU.get_condition_summary(cond_cmds), mode_str]
		_choice_list.add_item(display)

	if _selected >= 0 and _selected < choices.size():
		_choice_list.select(_selected)
		_load_properties(_selected)
	else:
		_selected = -1
		_clear_properties()


func _load_properties(index: int) -> void:
	if _cmd == null:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if index < 0 or index >= choices.size():
		_clear_properties()
		return
	var choice: Dictionary = choices[index]
	if _text_input:
		_text_input.text = choice.get("text", "")
		_text_input.editable = true
	if _hidden_option:
		_hidden_option.select(1 if choice.get("hidden_when_unmet", false) else 0)
		_hidden_option.disabled = false
	_refresh_cond_tree(choice)


func _clear_properties() -> void:
	if _text_input:
		_text_input.text = ""
		_text_input.editable = false
	if _hidden_option:
		_hidden_option.select(0)
		_hidden_option.disabled = true
	if _cond_tree:
		_cond_tree.clear()


func _refresh_cond_tree(choice: Dictionary) -> void:
	if _cond_tree == null or condition_editor == null:
		return
	_cond_tree.hide_root = true
	condition_editor.build_condition_tree(_cond_tree, choice.get("condition_commands", []))


# ============ 事件处理 ============

func _on_list_selected(index: int) -> void:
	_selected = index
	_load_properties(index)


func _on_text_changed(new_text: String) -> void:
	if _cmd == null or _selected < 0:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if _selected >= choices.size():
		return
	choices[_selected]["text"] = new_text
	_refresh_list()


func _on_hidden_changed(index: int) -> void:
	if _cmd == null or _selected < 0:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if _selected >= choices.size():
		return
	choices[_selected]["hidden_when_unmet"] = (index == 1)
	_refresh_list()


func _on_add() -> void:
	if _cmd == null:
		return
	var choices: Array = _cmd.params.get("choices", [])
	choices.append({"text": "", "commands": [], "condition_commands": [], "hidden_when_unmet": false})
	_cmd.params["choices"] = choices
	_selected = choices.size() - 1
	_refresh_list()


func _on_delete() -> void:
	if _cmd == null or _selected < 0:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if _selected >= choices.size():
		return
	choices.remove_at(_selected)
	_cmd.params["choices"] = choices
	if _selected >= choices.size():
		_selected = choices.size() - 1
	_refresh_list()


func _on_cond_add() -> void:
	if _cmd == null or _selected < 0 or condition_editor == null:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if _selected >= choices.size():
		return
	var choice: Dictionary = choices[_selected]
	if not choice.has("condition_commands"):
		choice["condition_commands"] = []

	var cond_cmds: Array = choice["condition_commands"]
	var new_cmd: Resource = CDU.create_command("CHECK_VAR")
	cond_cmds.append(new_cmd)

	# 编辑新条件，完成后刷新
	var done_cb: Callable = func():
		_refresh_cond_tree(choice)
		_refresh_list()
	var cancel_cb: Callable = func():
		var idx: int = cond_cmds.find(new_cmd)
		if idx >= 0:
			cond_cmds.remove_at(idx)
		_refresh_cond_tree(choice)
		_refresh_list()
	condition_editor.edit_condition(new_cmd, cond_cmds.size() - 1, done_cb, cancel_cb)


func _on_cond_delete() -> void:
	if _cmd == null or _selected < 0 or _cond_tree == null:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if _selected >= choices.size():
		return
	var selected_item: TreeItem = _cond_tree.get_selected()
	if selected_item == null:
		return
	var meta_raw = selected_item.get_metadata(0)
	if meta_raw == null or not meta_raw is Dictionary:
		return
	var meta: Dictionary = meta_raw
	if not meta.has("index"):
		return
	var choice: Dictionary = choices[_selected]
	var cond_cmds: Array = choice.get("condition_commands", [])
	var idx: int = meta.get("index", -1)
	if idx >= 0 and idx < cond_cmds.size():
		cond_cmds.remove_at(idx)
		choice["condition_commands"] = cond_cmds
	_refresh_cond_tree(choice)
	_refresh_list()


func _on_cond_item_activated() -> void:
	if _cond_tree == null or condition_editor == null:
		return
	var selected_item: TreeItem = _cond_tree.get_selected()
	if selected_item == null:
		return
	var meta_raw = selected_item.get_metadata(0)
	if meta_raw == null or not meta_raw is Dictionary:
		return
	var meta: Dictionary = meta_raw
	if not meta.has("index"):
		return
	if _cmd == null or _selected < 0:
		return
	var choices: Array = _cmd.params.get("choices", [])
	if _selected >= choices.size():
		return
	var choice: Dictionary = choices[_selected]
	var cond_cmds: Array = choice.get("condition_commands", [])
	var idx: int = meta.get("index", -1)
	if idx < 0 or idx >= cond_cmds.size():
		return
	var cond_cmd: Resource = cond_cmds[idx]
	if cond_cmd.command_type == "CHECK_VAR":
		var done_cb: Callable = func():
			_refresh_cond_tree(choice)
			_refresh_list()
		condition_editor.edit_condition(cond_cmd, idx, done_cb)


func _on_close() -> void:
	if _dialog:
		_dialog.hide()
	_cmd = null
	_selected = -1
	choice_changed.emit()
