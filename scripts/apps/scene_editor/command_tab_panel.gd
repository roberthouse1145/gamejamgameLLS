class_name CommandTabController extends RefCounted
## 命令标签页控制器 — 管理命令标签页、命令树显示、命令增删
## 不是场景节点，由 scene_editor 传入 UI 引用

const CDU = preload("res://scripts/apps/scene_editor/command_display_utils.gd")
const CommandRegistryClass = preload("res://scripts/avg/commands/command_registry.gd")
const CommandInitializerClass = preload("res://scripts/avg/commands/command_initializer.gd")
const SceneSelectorDialogClass = preload("res://scripts/editor/scene_selector_dialog.gd")
const ResourceLibraryPanelScene = preload("res://scenes/apps/project_manager/resource_library_panel.tscn")

## 请求打开选项编辑器 (cmd, focus_choice)
signal choice_edit_requested(cmd: Resource, focus_choice: int)
## 请求刷新命令列表（外部数据变化后）
signal command_list_refreshed()

## UI 引用
var tab_container: HBoxContainer = null
var add_tab_button: Button = null
var delete_tab_button: Button = null
var add_condition_button: Button = null
var delete_condition_button: Button = null
var condition_tree: Tree = null
var mode_option: OptionButton = null
var command_tree: Tree = null
var delete_command_button: Button = null
var add_command_dialog: Window = null
var command_button_grid: Control = null
var add_command_cancel_button: Button = null
var command_param_dialog: Window = null
var param_container: VBoxContainer = null
var param_ok_button: Button = null
var param_cancel_button: Button = null

## 条件编辑控制器
var condition_editor: RefCounted = null
## 变量选择器控制器
var var_picker: RefCounted = null

## IF 命令编辑器临时状态
var _if_condition_tree: Tree = null
var _if_has_else_check: CheckBox = null

## 外部状态（由 scene_editor 设置）
var selected_node: Resource = null
var current_scene: Resource = null
var current_tab_index: int = 0
var current_command_index: int = -1

## 内部状态
var _pending_add_meta: Dictionary = {}
## 参数编辑器：当前编辑的命令和控件映射
var _editing_cmd: Resource = null
var _editing_schema: Resource = null
var _param_controls: Dictionary = {} # param_name -> Control
## CommandRegistry 实例（懒初始化）
var _registry: RefCounted = null
## 资源选择弹窗（懒初始化）
var _resource_picker_dialog: Window = null
var _resource_picker_panel: Control = null
## 资源选择回调
var _resource_picker_target_input: LineEdit = null
var _resource_picker_filter: String = ""


## 初始化
func initialize(refs: Dictionary) -> void:
	tab_container = refs.get("tab_container")
	add_tab_button = refs.get("add_tab_btn")
	delete_tab_button = refs.get("delete_tab_btn")
	add_condition_button = refs.get("add_condition_btn")
	delete_condition_button = refs.get("delete_condition_btn")
	condition_tree = refs.get("condition_tree")
	mode_option = refs.get("mode_option")
	command_tree = refs.get("command_tree")
	delete_command_button = refs.get("delete_command_btn")
	add_command_dialog = refs.get("add_command_dialog")
	command_button_grid = refs.get("command_button_grid")
	add_command_cancel_button = refs.get("add_command_cancel_btn")
	command_param_dialog = refs.get("command_param_dialog")
	param_container = refs.get("param_container")
	param_ok_button = refs.get("param_ok_btn")
	param_cancel_button = refs.get("param_cancel_btn")
	condition_editor = refs.get("condition_editor")
	var_picker = refs.get("var_picker")

	_connect_signals()
	_setup_options()
	_setup_command_buttons()


func _connect_signals() -> void:
	if add_tab_button:
		add_tab_button.pressed.connect(_on_add_tab_pressed)
	if delete_tab_button:
		delete_tab_button.pressed.connect(_on_delete_tab_pressed)
	if add_condition_button:
		add_condition_button.pressed.connect(_on_add_condition_pressed)
	if delete_condition_button:
		delete_condition_button.pressed.connect(_on_delete_condition_pressed)
	if condition_tree:
		condition_tree.item_activated.connect(_on_condition_item_activated)
	if mode_option:
		mode_option.item_selected.connect(_on_mode_changed)
	if command_tree:
		command_tree.item_selected.connect(_on_tree_item_selected)
		command_tree.item_activated.connect(_on_tree_item_activated)
	if delete_command_button:
		delete_command_button.pressed.connect(_on_delete_command_pressed)
	if add_command_dialog:
		add_command_dialog.close_requested.connect(_on_add_command_dialog_closed)
	if add_command_cancel_button:
		add_command_cancel_button.pressed.connect(_on_add_command_dialog_closed)
	if param_ok_button:
		param_ok_button.pressed.connect(_on_param_ok_pressed)
	if param_cancel_button:
		param_cancel_button.pressed.connect(_on_param_cancel_pressed)
	if command_param_dialog:
		command_param_dialog.close_requested.connect(_on_param_cancel_pressed)


func _setup_options() -> void:
	if mode_option:
		mode_option.clear()
		mode_option.add_item("自动", 0)
		mode_option.add_item("并行", 1)
		mode_option.add_item("点击", 2)


func _setup_command_buttons() -> void:
	if command_button_grid == null:
		return
	# command_button_grid 原本是 ScrollContainer 内的 GridContainer
	# 将 ScrollContainer 替换为 TabContainer 分类布局
	var scroll_parent: Node = command_button_grid.get_parent() # ScrollContainer
	if scroll_parent == null:
		return
	var vbox_parent: Node = scroll_parent.get_parent() # VBoxContainer
	if vbox_parent == null:
		return
	var scroll_index: int = scroll_parent.get_index()
	var old_size_flags_v: int = scroll_parent.size_flags_vertical if scroll_parent is Control else Control.SIZE_EXPAND_FILL
	scroll_parent.queue_free()

	var tab_cont := TabContainer.new()
	tab_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_cont.size_flags_vertical = old_size_flags_v
	vbox_parent.add_child(tab_cont)
	vbox_parent.move_child(tab_cont, scroll_index)
	command_button_grid = tab_cont # 保持引用以便后续清理

	# 按分类分组
	var category_commands: Dictionary = {} # category -> Array[{id, name}]
	for cmd_def in CDU.COMMAND_TYPES:
		var cat: String = cmd_def.get("category", "其他")
		if not category_commands.has(cat):
			category_commands[cat] = []
		category_commands[cat].append(cmd_def)

	# 按 COMMAND_CATEGORIES 顺序创建 Tab
	for cat_name in CDU.COMMAND_CATEGORIES:
		if not category_commands.has(cat_name):
			continue
		var cmds: Array = category_commands[cat_name]

		var scroll := ScrollContainer.new()
		scroll.name = cat_name
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab_cont.add_child(scroll)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)

		for cmd_def in cmds:
			var btn := Button.new()
			btn.text = cmd_def["name"]
			btn.custom_minimum_size = Vector2(120, 36)
			btn.pressed.connect(_on_command_type_button_pressed.bind(cmd_def["id"]))
			grid.add_child(btn)


# ============ 标签页数据访问 ============

## 获取当前节点的命令标签页数组
func _get_node_command_tabs() -> Array:
	if selected_node == null:
		return []
	if selected_node is AVGSharedNodeRef and not selected_node.is_unique:
		var project = StorageManager.current_project
		if project:
			var resolved: Resource = selected_node.get_resolved_node(project)
			if resolved and "command_tabs" in resolved and resolved.command_tabs != null:
				return resolved.command_tabs
		return []
	if not "command_tabs" in selected_node or selected_node.command_tabs == null:
		selected_node.command_tabs = []
	return selected_node.command_tabs


## 判断当前命令是否只读
func _is_commands_read_only() -> bool:
	return selected_node is AVGSharedNodeRef and not selected_node.is_unique


## 获取当前标签页
func _get_current_tab() -> Dictionary:
	var tabs: Array = _get_node_command_tabs()
	if current_tab_index >= 0 and current_tab_index < tabs.size():
		return tabs[current_tab_index]
	return {}


# ============ 刷新 UI ============

## 刷新命令标签页（节点切换时调用）
func refresh_tabs() -> void:
	if tab_container == null:
		return
	for child in tab_container.get_children():
		child.queue_free()
	if selected_node == null:
		_update_controls_enabled(true)
		refresh_command_list()
		return
	var read_only: bool = _is_commands_read_only()
	var tabs: Array = _get_node_command_tabs()
	for i in range(tabs.size()):
		var tab_button := Button.new()
		tab_button.text = "标签%d" % (i + 1)
		tab_button.toggle_mode = true
		tab_button.button_pressed = (i == current_tab_index)
		tab_button.pressed.connect(_on_tab_button_pressed.bind(i))
		tab_container.add_child(tab_button)
	_update_controls_enabled(not read_only)
	_refresh_tab_settings()
	refresh_command_list()


func _update_controls_enabled(enabled: bool) -> void:
	if add_tab_button:
		add_tab_button.disabled = not enabled
	if delete_tab_button:
		delete_tab_button.disabled = not enabled
	if add_condition_button:
		add_condition_button.disabled = not enabled
	if delete_condition_button:
		delete_condition_button.disabled = not enabled
	if mode_option:
		mode_option.disabled = not enabled
	if delete_command_button:
		delete_command_button.disabled = not enabled


func _refresh_tab_settings() -> void:
	var tab: Dictionary = _get_current_tab()
	_refresh_condition_tree()
	if mode_option:
		var mode: int = tab.get("mode", 0)
		mode_option.select(mode)


## 刷新命令列表（Tree结构）
func refresh_command_list() -> void:
	if command_tree == null:
		return
	command_tree.clear()
	current_command_index = -1
	var tree_root: TreeItem = command_tree.create_item()
	var tab: Dictionary = _get_current_tab()
	var commands: Array = tab.get("commands", [])
	var read_only: bool = _is_commands_read_only()
	_build_command_tree(tree_root, commands, "")
	if not read_only:
		_add_empty_item(tree_root, commands.size(), "")
	elif commands.is_empty():
		var hint_item: TreeItem = command_tree.create_item(tree_root)
		hint_item.set_text(0, "(只读 - 请先唯一化)")
		hint_item.set_custom_color(0, Color(0.6, 0.4, 0.4))
		hint_item.set_selectable(0, false)
	command_list_refreshed.emit()


## 递归构建命令树
func _build_command_tree(parent: TreeItem, commands: Array, prefix: String) -> void:
	for i in range(commands.size()):
		var cmd = commands[i]
		var cmd_type: String
		if cmd is Dictionary:
			cmd_type = cmd.get("command_type", "unknown")
		elif cmd != null:
			cmd_type = cmd.command_type
		else:
			cmd_type = "unknown"
		var index_str: String = "%s%d" % [prefix, i + 1] if prefix.is_empty() else "%s.%d" % [prefix, i + 1]
		if cmd_type == "IF":
			_build_if_block(parent, cmd, i, index_str)
		elif cmd_type == "CHOICE":
			_build_choice_block(parent, cmd, i, index_str)
		else:
			var item: TreeItem = command_tree.create_item(parent)
			var display_text: String = "%s. %s" % [index_str, CDU.get_command_display(cmd)]
			item.set_text(0, display_text)
			item.set_metadata(0, {"type": "command", "index": i, "path": prefix})


func _build_if_block(parent: TreeItem, cmd: Resource, index: int, index_str: String) -> void:
	var cond_cmds: Array = cmd.params.get("condition_commands", [])
	var condition_text: String = ""
	if not cond_cmds.is_empty():
		condition_text = CDU.get_condition_summary(cond_cmds)
	else:
		condition_text = cmd.params.get("condition", "条件")
	var if_item: TreeItem = command_tree.create_item(parent)
	if_item.set_text(0, "%s. 如果 [%s]" % [index_str, condition_text])
	if_item.set_metadata(0, {"type": "IF", "index": index, "path": ""})
	var if_commands: Array = cmd.params.get("if_commands", [])
	_build_command_tree(if_item, if_commands, index_str)
	_add_empty_item(if_item, if_commands.size(), index_str)
	var has_else: bool = cmd.params.get("has_else", false)
	if has_else:
		var else_label: TreeItem = command_tree.create_item(if_item)
		else_label.set_text(0, "[否则]")
		else_label.set_metadata(0, {"type": "else_label", "index": index, "path": ""})
		else_label.set_selectable(0, false)
		else_label.set_custom_color(0, Color(0.7, 0.7, 0.5))
		var else_commands: Array = cmd.params.get("else_commands", [])
		for j in range(else_commands.size()):
			var else_cmd = else_commands[j]
			var else_cmd_type: String
			if else_cmd is Dictionary:
				else_cmd_type = else_cmd.get("command_type", "unknown")
			elif else_cmd != null:
				else_cmd_type = else_cmd.command_type
			else:
				else_cmd_type = "unknown"
			var else_index_str: String = "%s.%d" % [index_str, if_commands.size() + j + 1]
			if else_cmd_type == "IF":
				_build_if_block(if_item, else_cmd, j, else_index_str)
			else:
				var item: TreeItem = command_tree.create_item(if_item)
				var display_text: String = "%s. %s" % [else_index_str, CDU.get_command_display(else_cmd)]
				item.set_text(0, display_text)
				item.set_metadata(0, {"type": "command", "index": j, "path": index_str + "_else"})
		_add_empty_item(if_item, if_commands.size() + else_commands.size(), index_str + "_else")


func _build_choice_block(parent: TreeItem, cmd: Resource, index: int, index_str: String) -> void:
	var choices: Array = cmd.params.get("choices", []) if cmd.params else []
	var choice_item: TreeItem = command_tree.create_item(parent)
	choice_item.set_text(0, "%s. 选项 (%d个)" % [index_str, choices.size()])
	choice_item.set_metadata(0, {"type": "CHOICE", "index": index, "path": ""})
	for ci in range(choices.size()):
		var choice: Dictionary = choices[ci] if choices[ci] is Dictionary else {}
		var choice_text: String = choice.get("text", "")
		var cond_cmds: Array = choice.get("condition_commands", [])
		var hide_unmet: bool = choice.get("hidden_when_unmet", false)
		var label_parts: Array[String] = []
		label_parts.append("选项%d: \"%s\"" % [ci + 1, choice_text])
		if not cond_cmds.is_empty():
			var cond_text: String = CDU.get_condition_summary(cond_cmds)
			var mode_text: String = "隐藏" if hide_unmet else "灰暗"
			label_parts.append("[条件: %s, %s]" % [cond_text, mode_text])
		var choice_node: TreeItem = command_tree.create_item(choice_item)
		choice_node.set_text(0, " ".join(label_parts))
		choice_node.set_metadata(0, {"type": "choice_branch", "index": index, "choice_index": ci, "path": ""})
		choice_node.set_custom_color(0, Color(0.6, 0.85, 1.0))
		var sub_commands: Array = choice.get("commands", [])
		var choice_prefix: String = "%s_choice%d" % [index_str, ci]
		_build_command_tree(choice_node, sub_commands, choice_prefix)
		_add_empty_item(choice_node, sub_commands.size(), choice_prefix)


func _add_empty_item(parent: TreeItem, index: int, prefix: String) -> void:
	var item: TreeItem = command_tree.create_item(parent)
	item.set_text(0, "[空白 - 双击添加]")
	item.set_metadata(0, {"type": "empty", "index": index, "path": prefix})
	item.set_custom_color(0, Color(0.5, 0.5, 0.5))


# ============ 条件树 ============

func _refresh_condition_tree() -> void:
	if condition_tree == null or condition_editor == null:
		return
	var tab: Dictionary = _get_current_tab()
	var cond_cmds: Array = tab.get("condition_commands", [])
	condition_editor.build_condition_tree(condition_tree, cond_cmds)


func _on_add_condition_pressed() -> void:
	if selected_node == null or _is_commands_read_only():
		return
	var tab: Dictionary = _get_current_tab()
	if tab.is_empty():
		return
	if not tab.has("condition_commands"):
		tab["condition_commands"] = []
	var done_cb: Callable = func(): _refresh_condition_tree()
	condition_editor.add_condition_to(tab["condition_commands"], done_cb)


func _on_delete_condition_pressed() -> void:
	if selected_node == null or condition_tree == null or _is_commands_read_only():
		return
	var selected: TreeItem = condition_tree.get_selected()
	if selected == null:
		return
	var meta_raw = selected.get_metadata(0)
	if meta_raw == null or not meta_raw is Dictionary:
		return
	var meta: Dictionary = meta_raw
	if meta.is_empty() or not meta.has("index"):
		return
	var tab: Dictionary = _get_current_tab()
	var cond_cmds: Array = tab.get("condition_commands", [])
	var idx: int = meta.get("index", -1)
	if idx >= 0 and idx < cond_cmds.size():
		cond_cmds.remove_at(idx)
		tab["condition_commands"] = cond_cmds
		_refresh_condition_tree()


func _on_condition_item_activated() -> void:
	if condition_tree == null or _is_commands_read_only() or condition_editor == null:
		return
	var selected: TreeItem = condition_tree.get_selected()
	if selected == null:
		return
	var meta_raw = selected.get_metadata(0)
	if meta_raw == null or not meta_raw is Dictionary:
		return
	var meta: Dictionary = meta_raw
	if meta.is_empty() or not meta.has("index"):
		return
	var tab: Dictionary = _get_current_tab()
	var cond_cmds: Array = tab.get("condition_commands", [])
	var idx: int = meta.get("index", -1)
	if idx < 0 or idx >= cond_cmds.size():
		return
	var cmd: Resource = cond_cmds[idx]
	if cmd.command_type == "CHECK_VAR":
		var done_cb: Callable = func(): _refresh_condition_tree()
		condition_editor.edit_condition(cmd, idx, done_cb)


# ============ 标签页操作 ============

func _on_tab_button_pressed(index: int) -> void:
	current_tab_index = index
	for i in range(tab_container.get_child_count()):
		var btn: Button = tab_container.get_child(i)
		btn.button_pressed = (i == index)
	_refresh_tab_settings()
	refresh_command_list()


func _on_add_tab_pressed() -> void:
	if selected_node == null:
		return
	var tabs: Array = _get_node_command_tabs()
	var new_tab: Dictionary = {"condition_commands": [], "mode": 0, "commands": []}
	tabs.append(new_tab)
	selected_node.command_tabs = tabs
	current_tab_index = tabs.size() - 1
	refresh_tabs()


func _on_delete_tab_pressed() -> void:
	if selected_node == null:
		return
	var tabs: Array = _get_node_command_tabs()
	if tabs.size() <= 1:
		return
	tabs.remove_at(current_tab_index)
	selected_node.command_tabs = tabs
	current_tab_index = max(0, current_tab_index - 1)
	refresh_tabs()


func _on_mode_changed(index: int) -> void:
	var tab: Dictionary = _get_current_tab()
	if tab.is_empty():
		return
	tab["mode"] = index


# ============ 命令树事件 ============

func _on_tree_item_selected() -> void:
	var selected: TreeItem = command_tree.get_selected()
	if selected == null:
		current_command_index = -1
		return
	var meta: Dictionary = selected.get_metadata(0)
	if meta.get("type") == "empty":
		current_command_index = -1
	else:
		current_command_index = meta.get("index", -1)


func _on_tree_item_activated() -> void:
	var selected: TreeItem = command_tree.get_selected()
	if selected == null:
		return
	if _is_commands_read_only():
		return
	var meta: Dictionary = selected.get_metadata(0)
	var item_type: String = meta.get("type", "")
	var path: String = meta.get("path", "")
	var index: int = meta.get("index", -1)
	if item_type == "empty":
		_show_add_command_dialog(meta)
	elif item_type == "CHOICE" or item_type == "choice_branch":
		var cmd: Resource = _resolve_command(path, index)
		var focus_choice: int = meta.get("choice_index", -1) if item_type == "choice_branch" else -1
		if cmd != null:
			choice_edit_requested.emit(cmd, focus_choice)
	elif item_type == "command" or item_type == "IF":
		var cmd: Resource = _resolve_command(path, index)
		if cmd != null:
			_show_command_param_dialog(cmd)


# ============ 命令增删 ============

func _on_command_type_button_pressed(command_type: String) -> void:
	var pending_path: String = _pending_add_meta.get("path", "")
	var inserted_index: int = _add_command_of_type(command_type)
	if add_command_dialog:
		add_command_dialog.hide()
	if inserted_index < 0:
		return
	# 解析刚插入的命令对象
	var cmd: Resource = _resolve_command(pending_path, inserted_index)
	if cmd == null:
		return
	# 打开对应的编辑器
	if command_type == "CHOICE":
		choice_edit_requested.emit(cmd, -1)
	else:
		_show_command_param_dialog(cmd)


func _on_add_command_dialog_closed() -> void:
	if add_command_dialog:
		add_command_dialog.hide()


func _show_add_command_dialog(meta: Dictionary) -> void:
	_pending_add_meta = meta
	if add_command_dialog:
		add_command_dialog.popup_centered()


func _add_command_of_type(command_type: String) -> int:
	if selected_node == null:
		return -1
	var tab: Dictionary = _get_current_tab()
	if tab.is_empty():
		return -1
	var commands: Array = tab.get("commands", [])
	var new_cmd: Resource = CDU.create_command(command_type)
	var path: String = _pending_add_meta.get("path", "")
	var insert_index: int = _pending_add_meta.get("index", commands.size())
	if path.is_empty():
		if insert_index >= commands.size():
			commands.append(new_cmd)
			insert_index = commands.size() - 1
		else:
			commands.insert(insert_index, new_cmd)
		tab["commands"] = commands
	else:
		_insert_nested_command(commands, path, insert_index, new_cmd)
	_pending_add_meta = {}
	refresh_command_list()
	return insert_index


func _on_delete_command_pressed() -> void:
	var selected: TreeItem = command_tree.get_selected() if command_tree else null
	if selected == null:
		return
	var meta: Dictionary = selected.get_metadata(0)
	var item_type: String = meta.get("type", "")
	if item_type == "empty" or item_type == "else":
		return
	var tab: Dictionary = _get_current_tab()
	if tab.is_empty():
		return
	var commands: Array = tab.get("commands", [])
	var path: String = meta.get("path", "")
	var index: int = meta.get("index", -1)
	if index < 0:
		return
	# 删除选项分支
	if item_type == "choice_branch":
		var choice_index: int = meta.get("choice_index", -1)
		if index >= 0 and index < commands.size() and choice_index >= 0:
			var choice_cmd: Resource = commands[index]
			if choice_cmd.command_type == "CHOICE":
				var choices: Array = choice_cmd.params.get("choices", [])
				if choice_index < choices.size():
					choices.remove_at(choice_index)
					choice_cmd.params["choices"] = choices
		current_command_index = -1
		refresh_command_list()
		return
	if path.is_empty():
		if index < commands.size():
			commands.remove_at(index)
			tab["commands"] = commands
	else:
		_remove_nested_command(commands, path, index)
	current_command_index = -1
	refresh_command_list()


## 从嵌套路径 + index 获取实际命令对象
func _get_nested_command(commands: Array, path: String, index: int) -> Resource:
	var parts: PackedStringArray = path.split("_")
	var cmd_index_str: String = parts[0]
	var suffix: String = parts[1] if parts.size() > 1 else ""
	var indices: PackedStringArray = cmd_index_str.split(".")
	var target_commands: Array = commands
	var target_cmd: Resource = null
	for i in range(indices.size()):
		var idx: int = int(indices[i]) - 1
		if idx >= 0 and idx < target_commands.size():
			var raw_cmd: Variant = target_commands[idx]
			if raw_cmd is Dictionary:
				raw_cmd = AVGCommand.new(raw_cmd.get("command_type", ""), raw_cmd.get("params", {}))
				target_commands[idx] = raw_cmd
			elif not raw_cmd is Resource:
				return null
			target_cmd = raw_cmd
			if i < indices.size() - 1:
				if target_cmd.command_type == "IF":
					target_commands = target_cmd.params.get("if_commands", [])
	if target_cmd == null:
		return null
	# CHOICE 路径
	if suffix.begins_with("choice") and target_cmd.command_type == "CHOICE":
		var choice_idx: int = int(suffix.substr(6))
		var choices: Array = target_cmd.params.get("choices", [])
		if choice_idx >= 0 and choice_idx < choices.size():
			var choice: Dictionary = choices[choice_idx]
			var sub_commands: Array = choice.get("commands", [])
			if parts.size() > 2:
				var remaining_path: String = "_".join(parts.slice(2))
				return _get_nested_command(sub_commands, remaining_path, index)
			elif index >= 0 and index < sub_commands.size():
				var raw_cmd: Variant = sub_commands[index]
				if raw_cmd is Dictionary:
					raw_cmd = AVGCommand.new(raw_cmd.get("command_type", ""), raw_cmd.get("params", {}))
					sub_commands[index] = raw_cmd
				return raw_cmd as Resource
		return null
	# IF 路径
	if target_cmd.command_type == "IF":
		var target_array: Array
		if suffix == "else":
			target_array = target_cmd.params.get("else_commands", [])
		else:
			target_array = target_cmd.params.get("if_commands", [])
		if index >= 0 and index < target_array.size():
			var raw_cmd: Variant = target_array[index]
			if raw_cmd is Dictionary:
				raw_cmd = AVGCommand.new(raw_cmd.get("command_type", ""), raw_cmd.get("params", {}))
				target_array[index] = raw_cmd
			return raw_cmd as Resource
	return null


## 在嵌套路径中插入命令
func _insert_nested_command(commands: Array, path: String, index: int, cmd: Resource) -> void:
	var parts: PackedStringArray = path.split("_")
	var cmd_index_str: String = parts[0]
	var suffix: String = parts[1] if parts.size() > 1 else ""
	var indices: PackedStringArray = cmd_index_str.split(".")
	var target_commands: Array = commands
	var target_cmd: Resource = null
	for i in range(indices.size()):
		var idx: int = int(indices[i]) - 1
		if idx >= 0 and idx < target_commands.size():
			target_cmd = target_commands[idx]
			if i < indices.size() - 1:
				if target_cmd.command_type == "IF":
					target_commands = target_cmd.params.get("if_commands", [])
	if target_cmd == null:
		return
	# CHOICE 路径
	if suffix.begins_with("choice") and target_cmd.command_type == "CHOICE":
		var choice_idx: int = int(suffix.substr(6))
		var choices: Array = target_cmd.params.get("choices", [])
		if choice_idx >= 0 and choice_idx < choices.size():
			var choice: Dictionary = choices[choice_idx]
			var sub_commands: Array = choice.get("commands", [])
			if parts.size() > 2:
				var remaining_path: String = "_".join(parts.slice(2))
				_insert_nested_command(sub_commands, remaining_path, index, cmd)
			else:
				if index >= sub_commands.size():
					sub_commands.append(cmd)
				else:
					sub_commands.insert(index, cmd)
				choice["commands"] = sub_commands
		return
	# IF 路径
	if target_cmd.command_type == "IF":
		var target_array: Array
		if suffix == "else":
			target_array = target_cmd.params.get("else_commands", [])
			if index >= target_array.size():
				target_array.append(cmd)
			else:
				target_array.insert(index, cmd)
			target_cmd.params["else_commands"] = target_array
		else:
			target_array = target_cmd.params.get("if_commands", [])
			if index >= target_array.size():
				target_array.append(cmd)
			else:
				target_array.insert(index, cmd)
			target_cmd.params["if_commands"] = target_array


## 从嵌套路径中删除命令
func _remove_nested_command(commands: Array, path: String, index: int) -> void:
	var parts: PackedStringArray = path.split("_")
	var cmd_index_str: String = parts[0]
	var suffix: String = parts[1] if parts.size() > 1 else ""
	var indices: PackedStringArray = cmd_index_str.split(".")
	var target_commands: Array = commands
	var target_cmd: Resource = null
	for i in range(indices.size()):
		var idx: int = int(indices[i]) - 1
		if idx >= 0 and idx < target_commands.size():
			target_cmd = target_commands[idx]
			if i < indices.size() - 1 and target_cmd.command_type == "IF":
				target_commands = target_cmd.params.get("if_commands", [])
	if target_cmd == null:
		return
	# CHOICE 路径
	if suffix.begins_with("choice") and target_cmd.command_type == "CHOICE":
		var choice_idx: int = int(suffix.substr(6))
		var choices: Array = target_cmd.params.get("choices", [])
		if choice_idx >= 0 and choice_idx < choices.size():
			var choice: Dictionary = choices[choice_idx]
			var sub_commands: Array = choice.get("commands", [])
			if parts.size() > 2:
				var remaining_path: String = "_".join(parts.slice(2))
				_remove_nested_command(sub_commands, remaining_path, index)
			else:
				if index < sub_commands.size():
					sub_commands.remove_at(index)
					choice["commands"] = sub_commands
		return
	# IF 路径
	if target_cmd.command_type == "IF":
		var target_array: Array
		if suffix == "else":
			target_array = target_cmd.params.get("else_commands", [])
			if index < target_array.size():
				target_array.remove_at(index)
				target_cmd.params["else_commands"] = target_array
		else:
			target_array = target_cmd.params.get("if_commands", [])
			if index < target_array.size():
				target_array.remove_at(index)
				target_cmd.params["if_commands"] = target_array


# ============ 命令参数对话框 ============

## 获取 CommandRegistry（懒初始化）
func _get_registry() -> RefCounted:
	if _registry == null:
		_registry = CommandRegistryClass.get_instance()
		if _registry.handler_count() == 0:
			CommandInitializerClass.register_all_commands(_registry)
	return _registry


## 根据 path 和 index 解析实际命令对象（统一入口）
## path 为空 → 顶层命令；path 非空 → 嵌套命令
func _resolve_command(path: String, index: int) -> Resource:
	var tab: Dictionary = _get_current_tab()
	if tab.is_empty():
		return null
	var commands: Array = tab.get("commands", [])
	if path.is_empty():
		if index >= 0 and index < commands.size():
			return commands[index]
		return null
	return _get_nested_command(commands, path, index)


func _show_command_param_dialog(cmd: Resource) -> void:
	if cmd == null:
		return
	_editing_cmd = cmd
	_param_controls.clear()

	if param_container == null:
		return
	for child in param_container.get_children():
		child.queue_free()

	# 标题
	var title_label := Label.new()
	title_label.text = "命令: %s" % cmd.command_type
	param_container.add_child(title_label)

	# 从 registry 获取 schema
	var registry: RefCounted = _get_registry()
	var schema = registry.get_schema(cmd.command_type)
	_editing_schema = schema

	# IF 命令 — 内联条件编辑器 + 否则分支开关（schema 为空但有专用编辑器）
	if cmd.command_type == "IF":
		_show_if_param_dialog(cmd)
		return

	if schema == null or schema.params.is_empty():
		var hint := Label.new()
		hint.text = "(此命令无可编辑参数)"
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		param_container.add_child(hint)
		if command_param_dialog:
			command_param_dialog.popup_centered(Vector2i(450, 200))
		return

	# CHOICE 有专用编辑器
	if cmd.command_type == "CHOICE":
		var hint := Label.new()
		hint.text = "(请使用专用编辑器)"
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		param_container.add_child(hint)
		if command_param_dialog:
			command_param_dialog.popup_centered(Vector2i(450, 200))
		return

	# 添加滚动容器
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	param_container.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_vbox)

	var params: Dictionary = cmd.params if cmd.params else {}

	for param_def in schema.params:
		var pname: String = param_def.name
		var ptype: String = param_def.type
		var current_value: Variant = params.get(pname, param_def.default_value)

		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size.y = 32

		# 标签
		var label := Label.new()
		var required_mark: String = "*" if param_def.required else ""
		label.text = "%s%s:" % [param_def.get_display_name(), required_mark]
		label.custom_minimum_size.x = 130
		label.tooltip_text = "%s (%s)" % [param_def.description, pname]
		hbox.add_child(label)

		# 根据类型创建控件
		var control: Control = _create_param_control(pname, ptype, param_def, current_value)
		if control:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(control)
			_param_controls[pname] = control

		scroll_vbox.add_child(hbox)

	# 计算对话框高度
	var row_count: int = schema.params.size()
	var dialog_height: int = clampi(120 + row_count * 40, 250, 600)

	# 通用条件显示：初始化 visible_when + 绑定 choices 变化回调
	_apply_visible_when_rules(schema)

	if command_param_dialog:
		command_param_dialog.popup_centered(Vector2i(500, dialog_height))


## IF 命令专用编辑器 — 条件列表 + 否则分支开关
func _show_if_param_dialog(cmd: Resource) -> void:
	if param_container == null or condition_editor == null:
		return
	var params: Dictionary = cmd.params if cmd.params else {}
	if cmd.params == null:
		cmd.params = {}

	# 确保 condition_commands 数组存在
	if not cmd.params.has("condition_commands"):
		cmd.params["condition_commands"] = []

	# --- 条件列表标签 ---
	var cond_label := Label.new()
	cond_label.text = "条件:"
	param_container.add_child(cond_label)

	# --- 条件树 ---
	_if_condition_tree = Tree.new()
	_if_condition_tree.custom_minimum_size = Vector2(0, 120)
	_if_condition_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_if_condition_tree.hide_root = true
	param_container.add_child(_if_condition_tree)

	# 构建条件树
	condition_editor.build_condition_tree(_if_condition_tree, cmd.params["condition_commands"])

	# 双击条件项 → 编辑
	_if_condition_tree.item_activated.connect(func():
		var selected: TreeItem = _if_condition_tree.get_selected()
		if selected == null:
			return
		var meta_raw = selected.get_metadata(0)
		if meta_raw == null or not meta_raw is Dictionary:
			return
		var meta: Dictionary = meta_raw
		if not meta.has("index"):
			return
		var idx: int = meta.get("index", -1)
		var cond_cmds: Array = cmd.params.get("condition_commands", [])
		if idx < 0 or idx >= cond_cmds.size():
			return
		var cond_cmd: Resource = cond_cmds[idx]
		if cond_cmd.command_type == "CHECK_VAR":
			var done_cb: Callable = func():
				condition_editor.build_condition_tree(_if_condition_tree, cmd.params["condition_commands"])
			condition_editor.edit_condition(cond_cmd, idx, done_cb)
	)

	# --- 条件按钮行 ---
	var btn_hbox := HBoxContainer.new()
	var add_cond_btn := Button.new()
	add_cond_btn.text = "添加条件"
	add_cond_btn.pressed.connect(func():
		var done_cb: Callable = func():
			condition_editor.build_condition_tree(_if_condition_tree, cmd.params["condition_commands"])
		condition_editor.add_condition_to(cmd.params["condition_commands"], done_cb)
	)
	btn_hbox.add_child(add_cond_btn)

	var del_cond_btn := Button.new()
	del_cond_btn.text = "删除条件"
	del_cond_btn.pressed.connect(func():
		if _if_condition_tree == null:
			return
		var selected: TreeItem = _if_condition_tree.get_selected()
		if selected == null:
			return
		var meta_raw = selected.get_metadata(0)
		if meta_raw == null or not meta_raw is Dictionary:
			return
		var meta: Dictionary = meta_raw
		if not meta.has("index"):
			return
		var idx: int = meta.get("index", -1)
		var cond_cmds: Array = cmd.params.get("condition_commands", [])
		if idx >= 0 and idx < cond_cmds.size():
			cond_cmds.remove_at(idx)
			condition_editor.build_condition_tree(_if_condition_tree, cond_cmds)
	)
	btn_hbox.add_child(del_cond_btn)
	param_container.add_child(btn_hbox)

	# --- 否则分支开关 ---
	_if_has_else_check = CheckBox.new()
	_if_has_else_check.text = "包含「否则」分支"
	_if_has_else_check.button_pressed = params.get("has_else", false)
	param_container.add_child(_if_has_else_check)

	if command_param_dialog:
		command_param_dialog.popup_centered(Vector2i(500, 400))


## 根据参数类型创建编辑控件
func _create_param_control(pname: String, ptype: String, param_def: Resource, current_value: Variant) -> Control:
	match ptype:
		"string":
			if param_def.hint == "multiline":
				var text_edit := TextEdit.new()
				text_edit.text = str(current_value) if current_value != null else ""
				text_edit.custom_minimum_size.y = 60
				text_edit.placeholder_text = param_def.description
				text_edit.set_meta("param_type", "multiline")
				return text_edit
			var input := LineEdit.new()
			input.text = str(current_value) if current_value != null else ""
			input.placeholder_text = param_def.description
			input.set_meta("param_type", "string")
			# ref_type 辅助选择：在 LineEdit 旁加 "..." 按钮
			if param_def.ref_type != "":
				var hbox := HBoxContainer.new()
				hbox.set_meta("param_type", "string")
				input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(input)
				hbox.set_meta("input", input)
				var browse_btn := Button.new()
				browse_btn.text = "..."
				browse_btn.custom_minimum_size.x = 36
				browse_btn.pressed.connect(_on_browse_ref.bind(input, param_def.ref_type))
				hbox.add_child(browse_btn)
				return hbox
			return input

		"character_ref":
			var option := OptionButton.new()
			option.set_meta("param_type", "character_ref")
			option.add_item("(无)", 0)
			var project: Resource = StorageManager.current_project
			var selected_idx: int = 0
			if project and project.characters:
				for i in range(project.characters.size()):
					var ch: Resource = project.characters[i]
					var ch_name: String = ch.display_name if ch.display_name != "" else ch.character_name
					var text: String = "%s (%s)" % [ch_name, ch.character_id]
					option.add_item(text)
					option.set_item_metadata(i + 1, ch.character_id)
					if str(current_value) == ch.character_id:
						selected_idx = i + 1
			option.select(selected_idx)
			return option

		"scene_ref":
			var hbox := HBoxContainer.new()
			hbox.set_meta("param_type", "scene_ref")
			var input := LineEdit.new()
			input.text = str(current_value) if current_value != null else ""
			input.placeholder_text = "场景ID"
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			input.set_meta("param_type", "scene_ref")
			hbox.add_child(input)
			hbox.set_meta("input", input)
			var browse_btn := Button.new()
			browse_btn.text = "..."
			browse_btn.custom_minimum_size.x = 36
			browse_btn.pressed.connect(_on_browse_scene.bind(input))
			hbox.add_child(browse_btn)
			return hbox

		"variable_ref":
			var btn := Button.new()
			btn.set_meta("param_type", "variable_ref")
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# 解析当前值为显示文本
			var current_var_id: String = str(current_value) if current_value != null else ""
			if not current_var_id.is_empty():
				var display: String = CDU.resolve_variable_display(current_var_id, "")
				btn.text = display if display != "?" else current_var_id
			else:
				btn.text = "(点击选择)"
			btn.set_meta("variable_id", current_var_id)
			btn.pressed.connect(_on_variable_ref_button_pressed.bind(btn))
			return btn

		"int":
			var spin := SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 1
			spin.value = int(current_value) if current_value != null else 0
			spin.set_meta("param_type", "int")
			return spin

		"float":
			var spin := SpinBox.new()
			spin.min_value = -999999.0
			spin.max_value = 999999.0
			spin.step = 0.01
			spin.value = float(current_value) if current_value != null else 0.0
			spin.set_meta("param_type", "float")
			return spin

		"bool":
			var check := CheckBox.new()
			check.button_pressed = bool(current_value) if current_value != null else false
			check.set_meta("param_type", "bool")
			return check

		"choices":
			var option := OptionButton.new()
			var options: Array = param_def.options
			var selected_idx: int = 0
			for i in range(options.size()):
				var opt_text: String = str(options[i])
				option.add_item(opt_text)
				if str(current_value) == opt_text:
					selected_idx = i
			option.select(selected_idx)
			option.set_meta("param_type", "choices")
			option.set_meta("options", options)
			option.set_meta("param_name", pname)
			option.item_selected.connect(_on_choices_param_changed.bind(pname))
			return option

		"color":
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(80, 28)
			if current_value is Color:
				picker.color = current_value
			elif current_value is String and not current_value.is_empty():
				picker.color = Color.from_string(str(current_value), Color.BLACK)
			else:
				picker.color = param_def.default_value if param_def.default_value is Color else Color.BLACK
			picker.set_meta("param_type", "color")
			return picker

		"vector2":
			var vec_hbox := HBoxContainer.new()
			var x_spin := SpinBox.new()
			x_spin.min_value = -10.0
			x_spin.max_value = 10.0
			x_spin.step = 0.01
			x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var y_spin := SpinBox.new()
			y_spin.min_value = -10.0
			y_spin.max_value = 10.0
			y_spin.step = 0.01
			y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if current_value is Vector2:
				x_spin.value = current_value.x
				y_spin.value = current_value.y
			vec_hbox.add_child(x_spin)
			var sep := Label.new()
			sep.text = ","
			vec_hbox.add_child(sep)
			vec_hbox.add_child(y_spin)
			vec_hbox.set_meta("param_type", "vector2")
			vec_hbox.set_meta("x_spin", x_spin)
			vec_hbox.set_meta("y_spin", y_spin)
			return vec_hbox

		"texture", "audio":
			var hbox := HBoxContainer.new()
			var filter: String = "image" if ptype == "texture" else "audio"
			hbox.set_meta("param_type", ptype)
			var input := LineEdit.new()
			input.text = ""
			if current_value is String:
				input.text = current_value
			elif current_value is Resource and current_value != null:
				input.text = current_value.resource_path
			input.placeholder_text = "资源路径"
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			input.set_meta("param_type", ptype)
			hbox.add_child(input)
			hbox.set_meta("input", input)
			var browse_btn := Button.new()
			browse_btn.text = "..."
			browse_btn.custom_minimum_size.x = 36
			browse_btn.pressed.connect(_on_browse_asset.bind(input, filter))
			hbox.add_child(browse_btn)
			return hbox

		"variant":
			var input := LineEdit.new()
			input.text = str(current_value) if current_value != null else ""
			input.placeholder_text = param_def.description
			input.set_meta("param_type", "variant")
			return input

		_:
			var input := LineEdit.new()
			input.text = str(current_value) if current_value != null else ""
			input.set_meta("param_type", "string")
			return input


## 通用 choices 参数变化回调 — 更新所有依赖此参数的 visible_when 规则
func _on_choices_param_changed(_index: int, _source_param: String) -> void:
	if _editing_schema == null:
		return
	_apply_visible_when_rules(_editing_schema)


## 应用所有 visible_when 规则（初始化 + 参数变化时调用）
func _apply_visible_when_rules(schema: Resource) -> void:
	for param_def in schema.params:
		if not "visible_when" in param_def:
			continue
		var rule: String = param_def.visible_when
		if rule.is_empty():
			continue
		if not _param_controls.has(param_def.name):
			continue
		var should_show: bool = _evaluate_visible_when(rule)
		_param_controls[param_def.name].get_parent().visible = should_show


## 解析 visible_when 表达式: "param_name == value" 或 "param_name != value"
## 支持逗号分隔多值: "param_name == a,b,c"
func _evaluate_visible_when(rule: String) -> bool:
	var op: String = ""
	var parts: PackedStringArray
	if " == " in rule:
		op = "=="
		parts = rule.split(" == ", false, 1)
	elif " != " in rule:
		op = "!="
		parts = rule.split(" != ", false, 1)
	else:
		return true

	if parts.size() != 2:
		return true

	var dep_param: String = parts[0].strip_edges()
	var expected_values: PackedStringArray = parts[1].strip_edges().split(",")

	# 获取依赖参数的当前值
	var current_value: String = _get_param_current_value(dep_param)

	var matched: bool = false
	for ev in expected_values:
		if current_value == ev.strip_edges():
			matched = true
			break

	return matched if op == "==" else not matched


## 获取参数控件的当前值（字符串形式）
func _get_param_current_value(param_name: String) -> String:
	if not _param_controls.has(param_name):
		return ""
	var ctrl: Control = _param_controls[param_name]
	if ctrl is OptionButton:
		return ctrl.get_item_text(ctrl.selected)
	elif ctrl is LineEdit:
		return ctrl.text
	elif ctrl is CheckBox:
		return "true" if ctrl.button_pressed else "false"
	elif ctrl is SpinBox:
		return str(ctrl.value)
	elif ctrl is Button:
		return ctrl.get_meta("variable_id", "")
	return ""


# ============ 变量选择器（variable_ref 按钮） ============

## 当前正在编辑的 variable_ref 按钮（用于 var_picker 回调）
var _active_var_ref_button: Button = null

## variable_ref 按钮点击 → 打开变量选择器
func _on_variable_ref_button_pressed(btn: Button) -> void:
	if var_picker == null:
		return
	_active_var_ref_button = btn
	var current_id: String = btn.get_meta("variable_id", "")
	# 连接一次性信号
	if not var_picker.is_connected("variable_selected", _on_var_picker_selected):
		var_picker.variable_selected.connect(_on_var_picker_selected)
	var_picker.open_with_preselect(current_id, current_scene)


## 变量选择器选择完成回调
func _on_var_picker_selected(var_id: String, var_key: String) -> void:
	if _active_var_ref_button != null and is_instance_valid(_active_var_ref_button):
		_active_var_ref_button.set_meta("variable_id", var_id)
		_active_var_ref_button.text = CDU.resolve_variable_display(var_id, var_key)
	_active_var_ref_button = null


# ============ 资源选择器 ============

## 通用 ref_type 辅助选择按钮回调
func _on_browse_ref(target_input: LineEdit, ref_type: String) -> void:
	match ref_type:
		"character_ref", "variable_ref", "event_ref", "shared_node_ref", "node_ref", "label_ref":
			_show_ref_picker_popup(target_input, ref_type)
		"scene_ref":
			_on_browse_scene(target_input)
		"texture":
			_on_browse_asset(target_input, "image")
		"audio":
			_on_browse_asset(target_input, "audio")
		_:
			push_warning("CommandTabPanel: Unknown ref_type '%s'" % ref_type)


## 弹出轻量选择列表（character_ref / variable_ref / event_ref / shared_node_ref / node_ref / label_ref）
func _show_ref_picker_popup(target_input: LineEdit, ref_type: String) -> void:
	var project: Resource = StorageManager.current_project
	if project == null:
		return
	var parent_node: Node = _get_dialog_parent()
	if parent_node == null:
		return
	# 构建选项列表: [{id, label}]
	var items: Array[Dictionary] = []
	var popup_title: String = "选择"
	match ref_type:
		"character_ref":
			popup_title = "选择角色"
			if project.characters:
				for ch in project.characters:
					var ch_name: String = ch.display_name if ch.display_name != "" else ch.character_name
					items.append({"id": ch.character_id, "label": "%s (%s)" % [ch_name, ch.character_id]})
		"variable_ref":
			popup_title = "选择变量"
			if project.variables:
				for v in project.variables:
					var v_label: String = AVGVariable.get_key(v)
					if v_label.is_empty():
						v_label = v.variable_id
					items.append({"id": v.variable_id, "label": "%s (%s)" % [v_label, v.variable_id]})
		"event_ref":
			popup_title = "选择事件"
			if project.events:
				for ev in project.events:
					var ev_name: String = ev.event_name if "event_name" in ev else ""
					var ev_id: String = ev.event_id if "event_id" in ev else ""
					var label: String = "%s (%s)" % [ev_name, ev_id] if ev_name != "" else ev_id
					items.append({"id": ev_id, "label": label})
		"shared_node_ref":
			popup_title = "选择公共节点"
			if project.shared_nodes:
				for sn in project.shared_nodes:
					var sn_name: String = sn.node_name if "node_name" in sn else ""
					var sn_id: String = sn.node_id if "node_id" in sn else ""
					var label: String = "%s (%s)" % [sn_name, sn_id] if sn_name != "" else sn_id
					items.append({"id": sn_id, "label": label})
		"node_ref":
			popup_title = "选择节点"
			# 从当前场景的节点树中收集节点 ID
			items = _collect_scene_node_ids()
		"label_ref":
			popup_title = "选择标签"
			# 从当前场景的命令中扫描 LABEL 命令
			items = _collect_scene_labels()
	if items.is_empty():
		return
	# 创建弹窗
	var popup := Window.new()
	popup.title = popup_title
	popup.size = Vector2i(350, 300)
	popup.exclusive = true
	popup.unresizable = false
	parent_node.add_child(popup)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	popup.add_child(vbox)
	var item_list := ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for item in items:
		item_list.add_item(item["label"])
	vbox.add_child(item_list)
	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	btn_bar.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	btn_bar.add_child(cancel_btn)
	vbox.add_child(btn_bar)
	# 回调
	var on_ok := func() -> void:
		var sel_indices: PackedInt32Array = item_list.get_selected_items()
		if sel_indices.size() > 0:
			var idx: int = sel_indices[0]
			target_input.text = items[idx]["id"]
		popup.hide()
		popup.queue_free()
	var on_cancel := func() -> void:
		popup.hide()
		popup.queue_free()
	ok_btn.pressed.connect(on_ok)
	cancel_btn.pressed.connect(on_cancel)
	popup.close_requested.connect(on_cancel)
	item_list.item_activated.connect(func(_idx: int) -> void: on_ok.call())
	popup.popup_centered()


## 场景选择按钮回调
func _on_browse_scene(target_input: LineEdit) -> void:
	var project: Resource = StorageManager.current_project
	if project == null:
		return
	# 需要一个 Node 作为弹窗父节点
	var parent_node: Node = _get_dialog_parent()
	if parent_node == null:
		return
	var current_id: String = target_input.text.strip_edges()
	var dialog: Window = SceneSelectorDialogClass.popup_selector(parent_node, project, current_id)
	dialog.scene_confirmed.connect(func(scene_id: String) -> void:
		target_input.text = scene_id
	)


## 资源浏览按钮回调（texture / audio）
func _on_browse_asset(target_input: LineEdit, category: String) -> void:
	var project: Resource = StorageManager.current_project
	if project == null:
		return
	var parent_node: Node = _get_dialog_parent()
	if parent_node == null:
		return
	_resource_picker_target_input = target_input
	_resource_picker_filter = category
	_ensure_resource_picker_dialog(parent_node)
	# 设置过滤并刷新
	if _resource_picker_panel:
		_resource_picker_panel.filter_category = category
		_resource_picker_panel.set_project(project)
	if _resource_picker_dialog:
		_resource_picker_dialog.title = "选择图片" if category == "image" else "选择音频"
		_resource_picker_dialog.popup_centered(Vector2i(700, 500))


## 获取弹窗父节点（从 command_param_dialog 向上找 Node）
func _get_dialog_parent() -> Node:
	if command_param_dialog and is_instance_valid(command_param_dialog):
		return command_param_dialog
	return null


## 懒初始化资源选择弹窗
func _ensure_resource_picker_dialog(parent_node: Node) -> void:
	if _resource_picker_dialog != null and is_instance_valid(_resource_picker_dialog):
		return
	_resource_picker_dialog = Window.new()
	_resource_picker_dialog.title = "选择资源"
	_resource_picker_dialog.size = Vector2i(700, 500)
	_resource_picker_dialog.exclusive = true
	_resource_picker_dialog.unresizable = false
	_resource_picker_dialog.min_size = Vector2i(500, 300)
	parent_node.add_child(_resource_picker_dialog)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	_resource_picker_dialog.add_child(vbox)

	_resource_picker_panel = ResourceLibraryPanelScene.instantiate()
	_resource_picker_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_picker_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_resource_picker_panel)

	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.pressed.connect(_on_resource_picker_ok)
	btn_bar.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_on_resource_picker_cancel)
	btn_bar.add_child(cancel_btn)
	vbox.add_child(btn_bar)

	_resource_picker_dialog.close_requested.connect(_on_resource_picker_cancel)


func _on_resource_picker_ok() -> void:
	if _resource_picker_panel and _resource_picker_panel.has_method("get_selected_path"):
		var path: String = _resource_picker_panel.get_selected_path()
		if not path.is_empty() and _resource_picker_target_input != null:
			_resource_picker_target_input.text = path
	_on_resource_picker_cancel()


func _on_resource_picker_cancel() -> void:
	if _resource_picker_dialog:
		_resource_picker_dialog.hide()
	_resource_picker_target_input = null


## 从当前场景节点树收集所有 node_id
func _collect_scene_node_ids() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_scene == null or not "nodes" in current_scene:
		return result
	_collect_node_ids_recursive(current_scene.nodes, result)
	return result


func _collect_node_ids_recursive(nodes: Array, result: Array[Dictionary]) -> void:
	for node in nodes:
		if node == null:
			continue
		var nid: String = node.node_id if "node_id" in node else ""
		var nname: String = node.node_name if "node_name" in node else ""
		if not nid.is_empty():
			var label: String = "%s (%s)" % [nname, nid] if nname != "" else nid
			result.append({"id": nid, "label": label})
		if "children" in node and node.children != null:
			_collect_node_ids_recursive(node.children, result)


## 从当前节点当前标签页的命令中扫描 LABEL 命令，收集标签名
func _collect_scene_labels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tab: Dictionary = _get_current_tab()
	if tab.is_empty():
		return result
	var cmds: Array = tab.get("commands", [])
	_collect_labels_from_commands(cmds, result)
	return result


func _collect_labels_from_commands(commands: Array, result: Array[Dictionary]) -> void:
	for cmd in commands:
		if cmd == null:
			continue
		if cmd.command_type == "LABEL":
			var label_name: String = cmd.params.get("name", "") if cmd.params else ""
			if not label_name.is_empty():
				result.append({"id": label_name, "label": label_name})
		# 递归扫描 IF 的子命令
		if cmd.command_type == "IF" and cmd.params:
			var if_cmds: Array = cmd.params.get("if_commands", [])
			_collect_labels_from_commands(if_cmds, result)
			var else_cmds: Array = cmd.params.get("else_commands", [])
			_collect_labels_from_commands(else_cmds, result)
		# 递归扫描 CHOICE 的子命令
		if cmd.command_type == "CHOICE" and cmd.params:
			var choices: Array = cmd.params.get("choices", [])
			for choice in choices:
				if choice is Dictionary:
					var sub_cmds: Array = choice.get("commands", [])
					_collect_labels_from_commands(sub_cmds, result)


## 从控件读取参数值
func _read_param_value(control: Control, ptype: String) -> Variant:
	var meta_type: String = control.get_meta("param_type", "string") if control.has_meta("param_type") else ptype
	match meta_type:
		"string", "scene_ref":
			if control is LineEdit:
				return control.text.strip_edges()
			# HBoxContainer with input meta (scene_ref browse)
			if control.has_meta("input"):
				var input: LineEdit = control.get_meta("input")
				return input.text.strip_edges()
			return ""
		"multiline":
			if control is TextEdit:
				return control.text
			return ""
		"character_ref":
			if control is OptionButton:
				var idx: int = control.selected
				if idx <= 0:
					return ""
				var meta = control.get_item_metadata(idx)
				return str(meta) if meta != null else ""
			return ""
		"variable_ref":
			if control is Button:
				return control.get_meta("variable_id", "")
			if control is OptionButton:
				var idx: int = control.selected
				if idx <= 0:
					return ""
				var meta = control.get_item_metadata(idx)
				return str(meta) if meta != null else ""
			return ""
		"int":
			if control is SpinBox:
				return int(control.value)
			return 0
		"float":
			if control is SpinBox:
				return control.value
			return 0.0
		"bool":
			if control is CheckBox:
				return control.button_pressed
			return false
		"choices":
			if control is OptionButton and control.selected >= 0:
				return control.get_item_text(control.selected)
			return ""
		"color":
			if control is ColorPickerButton:
				return control.color
			return Color.BLACK
		"vector2":
			if control.has_meta("x_spin") and control.has_meta("y_spin"):
				var x_spin: SpinBox = control.get_meta("x_spin")
				var y_spin: SpinBox = control.get_meta("y_spin")
				return Vector2(x_spin.value, y_spin.value)
			return Vector2.ZERO
		"texture", "audio":
			if control is LineEdit:
				return control.text.strip_edges()
			if control.has_meta("input"):
				var input: LineEdit = control.get_meta("input")
				return input.text.strip_edges()
			return ""
		"variant":
			if control is LineEdit:
				var text: String = control.text.strip_edges()
				if text.is_valid_float():
					return text.to_float()
				if text.is_valid_int():
					return text.to_int()
				return text
			return ""
		_:
			if control is LineEdit:
				return control.text.strip_edges()
			return ""


func _on_param_ok_pressed() -> void:
	if _editing_cmd != null:
		# IF 命令：保存 has_else（condition_commands 已在编辑时直接修改）
		if _editing_cmd.command_type == "IF" and _if_has_else_check != null:
			_editing_cmd.params["has_else"] = _if_has_else_check.button_pressed

		# 通用参数保存
		if not _param_controls.is_empty():
			var registry: RefCounted = _get_registry()
			var schema = registry.get_schema(_editing_cmd.command_type)
			if schema:
				for param_def in schema.params:
					var pname: String = param_def.name
					if _param_controls.has(pname):
						var control: Control = _param_controls[pname]
						_editing_cmd.params[pname] = _read_param_value(control, param_def.type)
	_editing_cmd = null
	_param_controls.clear()
	if command_param_dialog:
		command_param_dialog.hide()
	refresh_command_list()


func _on_param_cancel_pressed() -> void:
	_editing_cmd = null
	_param_controls.clear()
	if command_param_dialog:
		command_param_dialog.hide()
