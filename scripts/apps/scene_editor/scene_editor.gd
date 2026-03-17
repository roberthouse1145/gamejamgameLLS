class_name SceneEditor extends Control
## Scene Editor Application — 场景编辑器（协调器）
## 负责：场景加载/保存、节点增删移动、子面板/控制器的初始化和信号路由

signal scene_changed(scene: Resource)
signal scene_saved()

# 当前编辑的场景
var current_scene: Resource = null
# 当前选中的节点
var selected_node: Resource = null

# 子控制器脚本预加载
const VariablePickerControllerScript = preload("res://scripts/apps/scene_editor/variable_picker_dialog.gd")
const ConditionEditorControllerScript = preload("res://scripts/apps/scene_editor/condition_editor.gd")
const ChoiceEditorDialogScript = preload("res://scripts/apps/scene_editor/choice_editor_dialog.gd")
const CommandTabControllerScript = preload("res://scripts/apps/scene_editor/command_tab_panel.gd")

# 子控制器
var _var_picker: RefCounted = null
var _condition_editor: RefCounted = null
var _choice_editor: RefCounted = null
var _command_tab: RefCounted = null

# 左侧面板
@onready var tree_panel: Control = %SceneTreePanel
@onready var scene_file_panel: Control = %SceneFilePanel

# 中间面板
@onready var preview_panel: Control = %ScenePreviewPanel
@onready var property_panel: Control = %NodePropertyPanel

# 工具栏
@onready var save_button: Button = $VBoxContainer/Toolbar/SaveButton

# 对话框（节点操作）
@onready var add_node_dialog: ConfirmationDialog = %AddNodeDialog
@onready var node_type_option: OptionButton = %NodeTypeOption
@onready var node_name_input: LineEdit = %NodeNameInput

# 待添加节点的父节点
var _pending_parent_node: Resource = null


func _ready() -> void:
	_init_controllers()
	_setup_connections()

	StorageManager.current_project_changed.connect(_on_project_changed)
	StorageManager.project_content_changed.connect(_on_project_content_changed)


## 初始化所有子控制器
func _init_controllers() -> void:
	# 1. 变量选择器
	_var_picker = VariablePickerControllerScript.new()
	_var_picker.initialize({
		"dialog": %VariablePickerDialog,
		"list": %VarPickerList,
		"select_btn": %VarPickerSelectButton,
		"cancel_btn": %VarPickerCancelButton,
		"add_btn": %VarPickerAddButton,
		"delete_btn": %VarPickerDeleteButton,
		"editor": %VarPickerEditor,
	})

	# 2. 条件编辑器
	_condition_editor = ConditionEditorControllerScript.new()
	_condition_editor.initialize({
		"cond_cmd_dialog": %ConditionCommandDialog,
		"cond_param_dialog": %ConditionParamDialog,
		"cond_param_container": %CondParamContainer,
		"cond_param_ok_btn": %CondParamOkButton,
		"cond_param_cancel_btn": %CondParamCancelButton,
		"check_var_btn": %CheckVarButton,
		"cond_if_btn": %CondIfButton,
		"check_hover_btn": %CheckHoverButton,
		"check_click_btn": %CheckClickButton,
		"cond_cancel_btn": %CondCancelButton,
		"var_picker": _var_picker,
	})

	# 3. 选项编辑器
	_choice_editor = ChoiceEditorDialogScript.new()
	_choice_editor.initialize(self, _condition_editor)

	# 4. 命令标签页控制器
	_command_tab = CommandTabControllerScript.new()
	_command_tab.initialize({
		"tab_container": %TabContainer,
		"add_tab_btn": %AddTabButton,
		"delete_tab_btn": %DeleteTabButton,
		"add_condition_btn": %AddConditionButton,
		"delete_condition_btn": %DeleteConditionButton,
		"condition_tree": %ConditionTree,
		"mode_option": %ModeOption,
		"command_tree": %CommandTree,
		"delete_command_btn": %DeleteCommandButton,
		"add_command_dialog": %AddCommandDialog,
		"command_button_grid": %CommandButtonGrid,
		"add_command_cancel_btn": %AddCommandCancelButton,
		"command_param_dialog": %CommandParamDialog,
		"param_container": %ParamContainer,
		"param_ok_btn": %OkButton,
		"param_cancel_btn": %CancelButton,
		"condition_editor": _condition_editor,
		"var_picker": _var_picker,
	})


## 连接面板信号
func _setup_connections() -> void:
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if scene_file_panel:
		scene_file_panel.scene_double_clicked.connect(_on_scene_double_clicked)
	if tree_panel:
		tree_panel.node_selected.connect(_on_node_selected)
		tree_panel.node_visibility_changed.connect(_on_node_visibility_changed)
	if preview_panel:
		preview_panel.node_clicked.connect(_on_preview_node_clicked)
		preview_panel.node_moved.connect(_on_preview_node_moved)
	if property_panel:
		property_panel.property_changed.connect(_on_property_changed)
	if add_node_dialog:
		add_node_dialog.confirmed.connect(_on_add_node_dialog_confirmed)

	# 子控制器信号
	_command_tab.choice_edit_requested.connect(_on_choice_edit_requested)
	_choice_editor.choice_changed.connect(_on_choice_changed)


# ============ 场景操作 ============

func set_scene(scene: Resource) -> void:
	current_scene = scene
	selected_node = null
	_command_tab.selected_node = null
	_command_tab.current_scene = scene
	_command_tab.current_tab_index = 0
	if _condition_editor:
		_condition_editor.current_scene = scene
	if _var_picker:
		_var_picker.set_current_scene(scene)

	_refresh_tree()
	_refresh_preview()
	_command_tab.refresh_tabs()
	_clear_property_panel()
	scene_changed.emit(scene)


func _refresh_tree() -> void:
	if tree_panel and current_scene:
		tree_panel.set_scene(current_scene)


func _refresh_preview() -> void:
	if preview_panel and current_scene:
		preview_panel.set_scene(current_scene)


func _clear_property_panel() -> void:
	if property_panel:
		property_panel.set_node(null)


func _on_save_pressed() -> void:
	if current_scene == null:
		return
	var project = StorageManager.current_project
	if project:
		StorageManager.save_project(project)
	scene_saved.emit()


# ============ 全局事件 ============

func _on_project_changed(_project: Resource) -> void:
	current_scene = null
	selected_node = null
	_command_tab.selected_node = null
	_command_tab.current_scene = null
	if _condition_editor:
		_condition_editor.current_scene = null
	if _var_picker:
		_var_picker.set_current_scene(null)
	_refresh_tree()
	_command_tab.refresh_tabs()


func _on_project_content_changed() -> void:
	_refresh_tree()
	_refresh_preview()
	if selected_node is AVGSharedNodeRef:
		_command_tab.refresh_tabs()


func _on_scene_double_clicked(scene: Resource) -> void:
	set_scene(scene)


# ============ 节点选择 ============

func _on_node_selected(node: Resource) -> void:
	selected_node = node
	_command_tab.selected_node = node
	_command_tab.current_tab_index = 0

	if property_panel:
		property_panel.set_node(node)
	if preview_panel:
		preview_panel.highlight_node(node)
	_command_tab.refresh_tabs()


func _on_preview_node_clicked(node: Resource) -> void:
	selected_node = node
	_command_tab.selected_node = node
	_command_tab.current_tab_index = 0

	if property_panel:
		property_panel.set_node(node)
	if tree_panel:
		tree_panel.select_node(node)
	if preview_panel:
		preview_panel.highlight_node(node)
	_command_tab.refresh_tabs()


func _on_preview_node_moved(node: Resource, _new_position: Vector2) -> void:
	if property_panel and selected_node == node:
		property_panel.refresh()


func _on_node_visibility_changed(node: Resource, _node_visible: bool) -> void:
	if preview_panel:
		preview_panel.refresh_node(node)
	if property_panel and selected_node == node:
		property_panel.refresh()


func _on_property_changed(node: Resource, prop: String, _value: Variant) -> void:
	if node and prop in ["norm_position", "norm_size"]:
		var project = StorageManager.current_project
		var resolution: Vector2 = Vector2(2560, 1440)
		if project and "resolution" in project:
			resolution = Vector2(project.resolution)
		node.sync_pixel_values(resolution)
	_refresh_preview()
	if prop == "visible" or prop == "node_name":
		_refresh_tree()
		if tree_panel and node:
			tree_panel.select_node(node)


# ============ 子控制器信号路由 ============

func _on_choice_edit_requested(cmd: Resource, focus_choice: int) -> void:
	if cmd == null:
		return
	_choice_editor.open(cmd, focus_choice)


func _on_choice_changed() -> void:
	_command_tab.refresh_command_list()


# ============ 节点增删移动 ============

func show_add_node_dialog() -> void:
	if current_scene == null:
		return
	_pending_parent_node = selected_node if selected_node else _find_root_node()
	_show_add_node_dialog_internal()


func show_add_node_dialog_for_parent(parent_node: Resource) -> void:
	if current_scene == null:
		return
	_pending_parent_node = parent_node
	_show_add_node_dialog_internal()


func _show_add_node_dialog_internal() -> void:
	if node_type_option:
		node_type_option.clear()
		node_type_option.add_item("通用节点", 0)
		node_type_option.add_item("角色节点", 1)
		node_type_option.add_item("画布层", 2)
		var project = StorageManager.current_project
		if project and project.shared_nodes.size() > 0:
			node_type_option.add_separator()
			for i in range(project.shared_nodes.size()):
				var shared_node = project.shared_nodes[i]
				var nid: String = shared_node.node_id if "node_id" in shared_node else ""
				if not nid.is_empty():
					node_type_option.add_item("公共: %s(%s)" % [nid, shared_node.node_name], 100 + i)
				else:
					node_type_option.add_item("公共: %s" % shared_node.node_name, 100 + i)
	if node_name_input:
		node_name_input.text = "NewNode"
	if add_node_dialog:
		add_node_dialog.popup_centered()
		if node_name_input:
			node_name_input.grab_focus()
			node_name_input.select_all()


func _on_add_node_dialog_confirmed() -> void:
	if current_scene == null:
		return
	var node_name_text: String = node_name_input.text.strip_edges() if node_name_input else "NewNode"
	if node_name_text.is_empty():
		node_name_text = "NewNode"
	var type_index: int = node_type_option.selected if node_type_option else 0
	var type_id: int = node_type_option.get_item_id(type_index) if node_type_option else 0
	var new_node: Resource = null

	if type_id >= 100:
		var shared_index: int = type_id - 100
		var project = StorageManager.current_project
		if project and shared_index < project.shared_nodes.size():
			var shared_node = project.shared_nodes[shared_index]
			new_node = load("res://scripts/avg/resources/nodes/avg_shared_node_ref.gd").new()
			new_node.shared_node_id = shared_node.node_id
			new_node.shared_node_name = shared_node.node_name
			new_node.is_unique = false
			node_name_text = shared_node.node_name
	else:
		match type_id:
			0: new_node = load("res://scripts/avg/resources/avg_node.gd").new()
			1: new_node = load("res://scripts/avg/resources/nodes/avg_character_node.gd").new()
			2: new_node = load("res://scripts/avg/resources/nodes/avg_canvas_layer_node.gd").new()
			_: new_node = load("res://scripts/avg/resources/avg_node.gd").new()
	if new_node == null:
		return

	var used_nums: Array[int] = AVGNode.collect_used_node_nums(current_scene.nodes, "node_")
	var next_num: int = AVGNode.next_available_num(used_nums)
	new_node.node_id = AVGNode.make_node_id(next_num)
	new_node.node_name = node_name_text
	if not new_node is AVGSharedNodeRef:
		new_node.command_tabs = [{"condition_commands": [], "mode": 0, "commands": []}]

	var parent_node: Resource = _pending_parent_node if _pending_parent_node else _find_root_node()
	var siblings: Array = parent_node.children if parent_node else current_scene.nodes
	new_node.node_name = _make_unique_name(node_name_text, siblings)

	if parent_node:
		parent_node.children.append(new_node)
	else:
		current_scene.nodes.append(new_node)

	_pending_parent_node = null
	_refresh_tree()
	_refresh_preview()
	if tree_panel:
		tree_panel.select_node(new_node)


func show_delete_dialog() -> void:
	if selected_node == null:
		return
	if selected_node is AVGRootNode:
		return
	var delete_dialog: ConfirmationDialog = get_node_or_null("%DeleteConfirmDialog")
	if delete_dialog == null:
		delete_dialog = ConfirmationDialog.new()
		delete_dialog.name = "DeleteConfirmDialog"
		add_child(delete_dialog)
		delete_dialog.confirmed.connect(_on_delete_node_confirmed)
	delete_dialog.dialog_text = "确定要删除节点 '%s' 吗？" % selected_node.node_name
	delete_dialog.popup_centered()


func _on_delete_node_confirmed() -> void:
	if selected_node == null or current_scene == null:
		return
	_remove_node_from_scene(selected_node)
	selected_node = null
	_command_tab.selected_node = null
	_refresh_tree()
	_refresh_preview()
	_command_tab.refresh_tabs()
	_clear_property_panel()


func move_node_up() -> void:
	if selected_node == null or current_scene == null:
		return
	var index: int = current_scene.nodes.find(selected_node)
	if index > 0:
		current_scene.nodes.remove_at(index)
		current_scene.nodes.insert(index - 1, selected_node)
		_refresh_tree()
		tree_panel.select_node(selected_node)


func move_node_down() -> void:
	if selected_node == null or current_scene == null:
		return
	var index: int = current_scene.nodes.find(selected_node)
	if index >= 0 and index < current_scene.nodes.size() - 1:
		current_scene.nodes.remove_at(index)
		current_scene.nodes.insert(index + 1, selected_node)
		_refresh_tree()
		tree_panel.select_node(selected_node)


# ============ 辅助函数 ============

func _find_root_node() -> Resource:
	if current_scene == null:
		return null
	for node in current_scene.nodes:
		if node is AVGRootNode:
			return node
	return null


## 查找节点的父节点（在场景节点树中）
func _find_parent_of(target: Resource) -> Resource:
	if current_scene == null:
		return null
	for node in current_scene.nodes:
		if node == target:
			return null  # 顶层节点没有父节点
		var found: Resource = _find_parent_in_children(node, target)
		if found:
			return found
	return null


func _find_parent_in_children(parent: Resource, target: Resource) -> Resource:
	for child in parent.children:
		if child == target:
			return parent
		var found: Resource = _find_parent_in_children(child, target)
		if found:
			return found
	return null


func _make_unique_name(base_name: String, siblings: Array) -> String:
	var existing_names: Array = []
	for sibling in siblings:
		existing_names.append(sibling.node_name)
	if base_name not in existing_names:
		return base_name
	var counter: int = 2
	while true:
		var candidate: String = "%s%d" % [base_name, counter]
		if candidate not in existing_names:
			return candidate
		counter += 1
	return base_name


func _remove_node_from_scene(node: Resource) -> void:
	if current_scene == null:
		return
	var index: int = current_scene.nodes.find(node)
	if index >= 0:
		current_scene.nodes.remove_at(index)
		return
	_remove_from_children(current_scene.nodes, node)


func _remove_from_children(nodes: Array, target: Resource) -> bool:
	for parent_node in nodes:
		var index: int = parent_node.children.find(target)
		if index >= 0:
			parent_node.children.remove_at(index)
			return true
		if _remove_from_children(parent_node.children, target):
			return true
	return false
