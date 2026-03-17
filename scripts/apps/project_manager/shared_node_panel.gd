class_name SharedNodePanel extends HSplitContainer
## Shared Node Panel
## 公共节点编辑面板 - 设计可复用的节点模板
## 根节点不能是 AVGRootNode，根节点 position 固定为 (0,0)
## 包含预览面板（中心为0,0）和命令编辑界面

const AVGCanvasLayerNodeClass = preload("res://scripts/avg/resources/nodes/avg_canvas_layer_node.gd")

signal content_changed()

# 预加载工具类和控制器
const CDU = preload("res://scripts/apps/scene_editor/command_display_utils.gd")
const CommandTabControllerScript = preload("res://scripts/apps/scene_editor/command_tab_panel.gd")
const ConditionEditorControllerScript = preload("res://scripts/apps/scene_editor/condition_editor.gd")
const VariablePickerControllerScript = preload("res://scripts/apps/scene_editor/variable_picker_dialog.gd")
const ChoiceEditorDialogScript = preload("res://scripts/apps/scene_editor/choice_editor_dialog.gd")

var _project: Resource = null
var _selected_shared_index: int = -1
var _selected_node: Resource = null
var _item_to_node: Dictionary = {}
var _node_to_item: Dictionary = {}
var _node_to_control: Dictionary = {}  # AVGNode -> preview Control
var _adding_shared_root: bool = false  # true=新增公共节点根, false=添加子节点

# 子控制器
var _var_picker: RefCounted = null
var _condition_editor: RefCounted = null
var _choice_editor: RefCounted = null
var _command_tab: RefCounted = null

# UI References - resolved in _ready via find_child for robustness
var add_button: Button = null
var delete_button: Button = null
var node_list: ItemList = null
var add_node_button: Button = null
var delete_node_button: Button = null
var node_tree: Tree = null
var preview_viewport: SubViewport = null
var nodes_container: Control = null
var center_marker: Control = null
var property_editor_container: VBoxContainer = null
var tab_container: HBoxContainer = null
var add_tab_button: Button = null
var delete_tab_button: Button = null
var condition_option: OptionButton = null  # unused, kept for compat
var mode_option: OptionButton = null
var command_tree: Tree = null
var delete_command_button: Button = null
var add_node_dialog: ConfirmationDialog = null
var node_type_option: OptionButton = null
var node_name_input: LineEdit = null
var add_command_dialog: Window = null
var command_button_grid: GridContainer = null

var _property_editor: Control = null
var _highlight_rect: ColorRect = null
var preview_wrapper: Control = null
var preview_container: SubViewportContainer = null

# Project resolution for preview
var _project_resolution: Vector2 = Vector2(2560, 1440)

# Drag state
var _dragging: bool = false
var _drag_node: Resource = null
var _drag_offset: Vector2 = Vector2.ZERO

const BUTTON_VISIBLE: int = 0


func _ready() -> void:
	_resolve_ui_references()
	_init_controllers()
	_setup_connections()
	_setup_property_editor()
	_setup_preview()
	_setup_options()


func _resolve_ui_references() -> void:
	add_button = find_child("AddButton", true, false) as Button
	delete_button = find_child("DeleteButton", true, false) as Button
	node_list = find_child("NodeList", true, false) as ItemList
	add_node_button = find_child("AddNodeButton", true, false) as Button
	delete_node_button = find_child("DeleteNodeButton", true, false) as Button
	node_tree = find_child("NodeTree", true, false) as Tree
	preview_wrapper = find_child("PreviewWrapper", true, false) as Control
	preview_container = find_child("PreviewContainer", true, false) as SubViewportContainer
	preview_viewport = find_child("PreviewViewport", true, false) as SubViewport
	nodes_container = find_child("NodesContainer", true, false) as Control
	center_marker = find_child("CenterMarker", true, false) as Control
	property_editor_container = find_child("PropertyEditor", true, false) as VBoxContainer
	tab_container = find_child("TabContainer", true, false) as HBoxContainer
	add_tab_button = find_child("AddTabButton", true, false) as Button
	delete_tab_button = find_child("DeleteTabButton", true, false) as Button
	mode_option = find_child("ModeOption", true, false) as OptionButton
	command_tree = find_child("CommandTree", true, false) as Tree
	delete_command_button = find_child("DeleteCommandButton", true, false) as Button
	add_node_dialog = find_child("AddNodeDialog", true, false) as ConfirmationDialog
	node_type_option = find_child("NodeTypeOption", true, false) as OptionButton
	node_name_input = find_child("NodeNameInput", true, false) as LineEdit
	add_command_dialog = find_child("AddCommandDialog", true, false) as Window
	command_button_grid = find_child("CommandButtonGrid", true, false) as GridContainer


## 初始化子控制器
func _init_controllers() -> void:
	# 1. 变量选择器
	_var_picker = VariablePickerControllerScript.new()
	var var_picker_dialog: Window = find_child("VariablePickerDialog", true, false) as Window
	var var_picker_list: ItemList = find_child("VarPickerList", true, false) as ItemList
	var var_picker_select_btn: Button = find_child("VarPickerSelectButton", true, false) as Button
	var var_picker_cancel_btn: Button = find_child("VarPickerCancelButton", true, false) as Button
	var var_picker_add_btn: Button = find_child("VarPickerAddButton", true, false) as Button
	var var_picker_delete_btn: Button = find_child("VarPickerDeleteButton", true, false) as Button
	var var_picker_editor: Control = find_child("VarPickerEditor", true, false) as Control
	
	if var_picker_dialog:
		_var_picker.initialize({
			"dialog": var_picker_dialog,
			"list": var_picker_list,
			"select_btn": var_picker_select_btn,
			"cancel_btn": var_picker_cancel_btn,
			"add_btn": var_picker_add_btn,
			"delete_btn": var_picker_delete_btn,
			"editor": var_picker_editor,
		})

	# 2. 条件编辑器
	_condition_editor = ConditionEditorControllerScript.new()
	var cond_cmd_dialog: Window = find_child("ConditionCommandDialog", true, false) as Window
	var cond_param_dialog: Window = find_child("ConditionParamDialog", true, false) as Window
	var cond_param_container: VBoxContainer = find_child("CondParamContainer", true, false) as VBoxContainer
	var cond_param_ok_btn: Button = find_child("CondParamOkButton", true, false) as Button
	var cond_param_cancel_btn: Button = find_child("CondParamCancelButton", true, false) as Button
	var check_var_btn: Button = find_child("CheckVarButton", true, false) as Button
	var cond_if_btn: Button = find_child("CondIfButton", true, false) as Button
	var check_hover_btn: Button = find_child("CheckHoverButton", true, false) as Button
	var check_click_btn: Button = find_child("CheckClickButton", true, false) as Button
	var cond_cancel_btn: Button = find_child("CondCancelButton", true, false) as Button
	
	if cond_cmd_dialog:
		_condition_editor.initialize({
			"cond_cmd_dialog": cond_cmd_dialog,
			"cond_param_dialog": cond_param_dialog,
			"cond_param_container": cond_param_container,
			"cond_param_ok_btn": cond_param_ok_btn,
			"cond_param_cancel_btn": cond_param_cancel_btn,
			"check_var_btn": check_var_btn,
			"cond_if_btn": cond_if_btn,
			"check_hover_btn": check_hover_btn,
			"check_click_btn": check_click_btn,
			"cond_cancel_btn": cond_cancel_btn,
			"var_picker": _var_picker,
		})

	# 3. 选项编辑器
	_choice_editor = ChoiceEditorDialogScript.new()
	_choice_editor.initialize(self, _condition_editor)

	# 4. 命令标签页控制器
	_command_tab = CommandTabControllerScript.new()
	var add_condition_btn: Button = find_child("AddConditionButton", true, false) as Button
	var delete_condition_btn: Button = find_child("DeleteConditionButton", true, false) as Button
	var condition_tree: Tree = find_child("ConditionTree", true, false) as Tree
	var add_command_cancel_btn: Button = find_child("AddCommandCancelButton", true, false) as Button
	var command_param_dialog: Window = find_child("CommandParamDialog", true, false) as Window
	var param_container: VBoxContainer = find_child("ParamContainer", true, false) as VBoxContainer
	var param_ok_btn: Button = find_child("OkButton", true, false) as Button
	var param_cancel_btn: Button = find_child("CancelButton", true, false) as Button
	
	_command_tab.initialize({
		"tab_container": tab_container,
		"add_tab_btn": add_tab_button,
		"delete_tab_btn": delete_tab_button,
		"add_condition_btn": add_condition_btn,
		"delete_condition_btn": delete_condition_btn,
		"condition_tree": condition_tree,
		"mode_option": mode_option,
		"command_tree": command_tree,
		"delete_command_btn": delete_command_button,
		"add_command_dialog": add_command_dialog,
		"command_button_grid": command_button_grid,
		"add_command_cancel_btn": add_command_cancel_btn,
		"command_param_dialog": command_param_dialog,
		"param_container": param_container,
		"param_ok_btn": param_ok_btn,
		"param_cancel_btn": param_cancel_btn,
		"condition_editor": _condition_editor,
		"var_picker": _var_picker,
	})


func _setup_connections() -> void:
	if add_button:
		add_button.pressed.connect(_on_add_shared_node)
	if delete_button:
		delete_button.pressed.connect(_on_delete_shared_node)
	if node_list:
		node_list.item_selected.connect(_on_shared_node_selected)
	if add_node_button:
		add_node_button.pressed.connect(_on_add_child_node)
	if delete_node_button:
		delete_node_button.pressed.connect(_on_delete_child_node)
	if node_tree:
		node_tree.item_selected.connect(_on_tree_node_selected)
		node_tree.button_clicked.connect(_on_tree_button_clicked)
		node_tree.columns = 2
		node_tree.set_column_expand(0, true)
		node_tree.set_column_expand(1, false)
		node_tree.set_column_custom_minimum_width(1, 30)
	if add_node_dialog:
		add_node_dialog.confirmed.connect(_on_add_node_confirmed)

	# 子控制器信号
	if _command_tab:
		_command_tab.choice_edit_requested.connect(_on_choice_edit_requested)
	if _choice_editor:
		_choice_editor.choice_changed.connect(_on_choice_changed)


func _setup_property_editor() -> void:
	if property_editor_container == null:
		return
	var PropertyEditorClass = load("res://scripts/editor/property_editor.gd")
	_property_editor = PropertyEditorClass.new()
	property_editor_container.add_child(_property_editor)
	_property_editor.property_changed.connect(_on_property_changed)


func _setup_preview() -> void:
	if nodes_container:
		# NodesContainer 固定 size = 项目分辨率，通过 scale 缩放到 viewport 实际大小
		nodes_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		nodes_container.anchor_right = 0.0
		nodes_container.anchor_bottom = 0.0
		nodes_container.position = Vector2.ZERO
		nodes_container.size = _project_resolution
		_highlight_rect = ColorRect.new()
		_highlight_rect.color = Color(0.2, 0.6, 1.0, 0.3)
		_highlight_rect.visible = false
		_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nodes_container.add_child(_highlight_rect)
	# Connect wrapper resize to update viewport container size (aspect ratio)
	if preview_wrapper:
		preview_wrapper.resized.connect(_on_preview_wrapper_resized)
		call_deferred("_on_preview_wrapper_resized")
	# Connect viewport resize to sync NodesContainer scale
	if preview_viewport:
		preview_viewport.size_changed.connect(_on_viewport_resized)
		call_deferred("_on_viewport_resized")


## Update SubViewportContainer size to maintain aspect ratio within the wrapper
func _on_preview_wrapper_resized() -> void:
	if preview_wrapper == null or preview_container == null:
		return
	var available: Vector2 = preview_wrapper.size
	if available.x <= 0 or available.y <= 0:
		return
	var aspect: float = _project_resolution.x / _project_resolution.y
	var container_aspect: float = available.x / available.y
	var new_size: Vector2
	if container_aspect > aspect:
		new_size.y = available.y
		new_size.x = available.y * aspect
	else:
		new_size.x = available.x
		new_size.y = available.x / aspect
	preview_container.set_deferred("size", new_size)
	preview_container.set_deferred("position", (available - new_size) / 2)


func _on_viewport_resized() -> void:
	_sync_nodes_container_scale()
	_refresh_preview()


## 同步 NodesContainer 的 scale，使其内部坐标空间 = 项目分辨率
## 公共节点以中心为原点，所以 NodesContainer 的 position 偏移半个分辨率
func _sync_nodes_container_scale() -> void:
	if nodes_container == null or preview_viewport == null:
		return
	var vp_size: Vector2 = Vector2(preview_viewport.size)
	if vp_size.x <= 0 or vp_size.y <= 0 or _project_resolution.x <= 0:
		return
	nodes_container.size = _project_resolution
	var s: float = vp_size.x / _project_resolution.x
	nodes_container.scale = Vector2(s, s)
	# 公共节点根 position=(0,0) 应显示在 viewport 中心
	# Control.position 不受自身 scale 影响，是父空间坐标
	# 所以 NodesContainer 内部 (0,0) 在 viewport 中 = nodes_container.position
	nodes_container.position = vp_size / 2.0
	# CenterMarker 在 NodesContainer 内部 (0,0) 处
	if center_marker:
		center_marker.position = Vector2(-2, -2)


func _setup_options() -> void:
	# Placeholder for compatibility - actual setup done by controller
	pass


func set_project(project: Resource) -> void:
	_project = project
	_selected_shared_index = -1
	_selected_node = null
	if project and "resolution" in project:
		_project_resolution = Vector2(project.resolution)
	else:
		_project_resolution = Vector2(2560, 1440)
	if nodes_container:
		nodes_container.size = _project_resolution
	_on_preview_wrapper_resized()
	_sync_nodes_container_scale()
	_refresh_node_list()
	_clear_tree()
	_clear_preview()
	_clear_properties()
	_clear_commands()


func _refresh_node_list() -> void:
	if node_list == null:
		return
	node_list.clear()
	if _project == null:
		return
	for node in _project.shared_nodes:
		var nid: String = node.node_id if "node_id" in node else ""
		if not nid.is_empty():
			node_list.add_item("%s: %s" % [nid, node.node_name])
		else:
			node_list.add_item(node.node_name)


func _clear_tree() -> void:
	if node_tree:
		node_tree.clear()
	_item_to_node.clear()
	_node_to_item.clear()


func _clear_preview() -> void:
	_node_to_control.clear()
	if nodes_container:
		for child in nodes_container.get_children():
			if child != _highlight_rect and child != center_marker:
				child.queue_free()
	if _highlight_rect:
		_highlight_rect.visible = false


func _clear_properties() -> void:
	if _property_editor and _property_editor.has_method("set_target"):
		_property_editor.set_target(null)


func _clear_commands() -> void:
	if _command_tab:
		_command_tab.selected_node = null
		_command_tab.current_tab_index = 0
		_command_tab.refresh_tabs()


func _rebuild_tree() -> void:
	_clear_tree()
	if node_tree == null or _selected_shared_index < 0 or _project == null:
		return
	if _selected_shared_index >= _project.shared_nodes.size():
		return
	var root_node: Resource = _project.shared_nodes[_selected_shared_index]
	node_tree.hide_root = true
	var tree_root: TreeItem = node_tree.create_item()
	_add_node_to_tree(root_node, tree_root)


func _add_node_to_tree(node: Resource, parent_item: TreeItem) -> TreeItem:
	var item: TreeItem = node_tree.create_item(parent_item)
	item.set_text(0, node.node_name)
	item.set_icon(0, _create_node_type_icon(node))
	item.set_metadata(0, node)
	var visible_icon: Texture2D = _create_visibility_icon(node.visible)
	item.add_button(1, visible_icon, BUTTON_VISIBLE, false, "切换可见性")
	_item_to_node[item] = node
	_node_to_item[node] = item
	for child in node.children:
		_add_node_to_tree(child, item)
	item.collapsed = false
	return item


## Visibility button clicked in tree
func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if column != 1 or id != BUTTON_VISIBLE or mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if not _item_to_node.has(item):
		return
	var node: Resource = _item_to_node[item]
	node.visible = not node.visible
	var new_icon: Texture2D = _create_visibility_icon(node.visible)
	item.set_button(1, BUTTON_VISIBLE, new_icon)
	_refresh_preview()
	# Sync property panel if same node selected
	if _selected_node == node and _property_editor and _property_editor.has_method("refresh"):
		_property_editor.refresh()
	_emit_content_changed()


func _create_node_type_icon(node: Resource) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var color: Color = Color(0.4, 0.7, 1.0, 1.0)  # 通用节点: 蓝色
	if node is AVGCharacterNode:
		color = Color(0.9, 0.6, 0.2, 1.0)
	elif node is AVGCanvasLayerNodeClass:
		color = Color(0.9, 0.3, 0.9, 1.0)  # Purple
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 14):
		for y in range(2, 14):
			img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


func _create_visibility_icon(node_visible: bool) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var color: Color = Color(1, 1, 1, 1) if node_visible else Color(0.5, 0.5, 0.5, 0.5)
	img.fill(Color(0, 0, 0, 0))
	for x in range(3, 13):
		for y in range(5, 11):
			var dist: float = abs(y - 8)
			if dist <= 3 - abs(x - 8) * 0.3:
				img.set_pixel(x, y, color)
	if node_visible:
		for x in range(6, 10):
			for y in range(6, 10):
				if Vector2(x, y).distance_to(Vector2(8, 8)) < 2:
					img.set_pixel(x, y, Color(0.2, 0.2, 0.2, 1))
	return ImageTexture.create_from_image(img)


# ============ Preview ============

func _refresh_preview() -> void:
	_clear_preview()
	if _selected_shared_index < 0 or _project == null:
		return
	if _selected_shared_index >= _project.shared_nodes.size():
		return
	var root_node: Resource = _project.shared_nodes[_selected_shared_index]
	if nodes_container:
		_build_preview_node(root_node, null)
	_highlight_selected_node()


## 递归构建预览节点。坐标在项目分辨率空间内，NodesContainer.scale 自动缩放。
## 公共节点根 position=(0,0) 对应 NodesContainer 内部原点（viewport 中心）。
func _build_preview_node(node: Resource, parent_control: Control) -> void:
	var target_parent: Control = parent_control if parent_control else nodes_container
	if target_parent == null:
		return

	# AVGCanvasLayerNode — 逻辑容器，不渲染自身，直接渲染子节点
	if node is AVGCanvasLayerNodeClass:
		for child in node.children:
			_build_preview_node(child, target_parent)
		return

	var control := Control.new()
	control.name = node.node_name
	# 直接使用项目分辨率空间的像素坐标，不手动乘 scale
	control.position = node.calc_pixel_position(_project_resolution)
	control.size = node.calc_pixel_size(_project_resolution)
	control.visible = node.visible
	control.set_meta("avg_node", node)
	control.gui_input.connect(_on_preview_control_input.bind(node))
	control.mouse_filter = Control.MOUSE_FILTER_STOP

	# 统一渲染：style_box → texture → text
	# Layer 1: style_box
	if "style_box" in node and node.style_box != null and node.style_box.has_method("to_stylebox"):
		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_theme_stylebox_override("panel", node.style_box.to_stylebox())
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.add_child(panel)
	# Layer 2: texture
	if "texture" in node and node.texture != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = node.texture
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if "modulate" in node:
			tex_rect.modulate = node.modulate
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.add_child(tex_rect)
	# Layer 3: text
	if "text" in node and node.text != "":
		var label := Label.new()
		label.text = node.text
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		if "h_alignment" in node:
			label.horizontal_alignment = node.h_alignment as HorizontalAlignment
		if "v_alignment" in node:
			label.vertical_alignment = node.v_alignment as VerticalAlignment
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = true
		if "font_size" in node and node.font_size > 0:
			label.add_theme_font_size_override("font_size", node.font_size)
		if "font_color" in node:
			label.add_theme_color_override("font_color", node.font_color)
		if "outline_size" in node and node.outline_size > 0:
			label.add_theme_constant_override("outline_size", node.outline_size)
			label.add_theme_color_override("font_outline_color", node.outline_color)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.add_child(label)
	# Fallback: empty placeholder
	if control.get_child_count() == 0:
		var rect := ColorRect.new()
		rect.color = Color(0.3, 0.3, 0.3, 0.5)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.add_child(rect)
	# clip_contents
	if "clip_contents" in node and node.clip_contents:
		control.clip_contents = true

	target_parent.add_child(control)
	_node_to_control[node] = control

	# 子节点挂到父 Control 下，坐标相对于父节点
	for child in node.children:
		_build_preview_node(child, control)


func _on_preview_control_input(event: InputEvent, node: Resource) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Select node
			_selected_node = node
			if _property_editor and _property_editor.has_method("set_target"):
				_property_editor.set_target(node)
			if _command_tab:
				_command_tab.selected_node = node
				_command_tab.current_tab_index = 0
				_command_tab.refresh_tabs()
			_highlight_selected_node()
			# Select in tree
			if _node_to_item.has(node):
				_node_to_item[node].select(0)
			# Start drag (root node position is locked to 0,0)
			var root_node: Resource = _project.shared_nodes[_selected_shared_index] if _project and _selected_shared_index >= 0 and _selected_shared_index < _project.shared_nodes.size() else null
			if node != root_node:
				_dragging = true
				_drag_node = node
				var control: Control = _node_to_control.get(node)
				if control:
					_drag_offset = control.get_local_mouse_position()
		else:
			# End drag
			if _dragging and _drag_node != null:
				if _property_editor and _property_editor.has_method("refresh"):
					_property_editor.refresh()
				_emit_content_changed()
			_dragging = false
			_drag_node = null

	elif event is InputEventMouseMotion and _dragging and _drag_node != null:
		var control: Control = _node_to_control.get(_drag_node)
		if control:
			var parent_control: Control = control.get_parent() as Control
			if parent_control:
				var mouse_pos: Vector2 = parent_control.get_local_mouse_position()
				var new_pos: Vector2 = mouse_pos - _drag_offset
				control.position = new_pos
				# 坐标已经在项目分辨率空间内，直接更新
				_drag_node.set_position_from_pixels(new_pos, _project_resolution)
				_highlight_selected_node()


func _highlight_selected_node() -> void:
	if _highlight_rect == null or _selected_node == null:
		if _highlight_rect:
			_highlight_rect.visible = false
		return
	if not _node_to_control.has(_selected_node):
		_highlight_rect.visible = false
		return
	var control: Control = _node_to_control[_selected_node]
	if not is_instance_valid(control):
		_highlight_rect.visible = false
		return
	# 计算 control 在 NodesContainer 内的全局位置
	var global_pos: Vector2 = _get_control_position_in_container(control)
	_highlight_rect.position = global_pos
	_highlight_rect.size = control.size
	_highlight_rect.visible = true
	nodes_container.move_child(_highlight_rect, nodes_container.get_child_count() - 1)


## 获取 control 相对于 nodes_container 的累积位置
func _get_control_position_in_container(control: Control) -> Vector2:
	var pos: Vector2 = Vector2.ZERO
	var current: Control = control
	while current != null and current != nodes_container:
		pos += current.position
		current = current.get_parent() as Control
	return pos


# ============ Shared Node List Events ============

func _on_add_shared_node() -> void:
	if _project == null:
		return
	_adding_shared_root = true
	if node_type_option:
		node_type_option.clear()
		node_type_option.add_item("通用节点", 0)
		node_type_option.add_item("角色节点", 1)
		node_type_option.add_item("画布层", 2)
	if node_name_input:
		node_name_input.text = "SharedNode"
	if add_node_dialog:
		add_node_dialog.title = "新增公共节点"
		add_node_dialog.popup_centered()


func _on_delete_shared_node() -> void:
	if _project == null or _selected_shared_index < 0:
		return
	if _selected_shared_index >= _project.shared_nodes.size():
		return
	_project.shared_nodes.remove_at(_selected_shared_index)
	_selected_shared_index = -1
	_selected_node = null
	_refresh_node_list()
	_clear_tree()
	_clear_preview()
	_clear_properties()
	_clear_commands()
	_emit_content_changed()


func _on_shared_node_selected(index: int) -> void:
	_selected_shared_index = index
	_selected_node = null
	_rebuild_tree()
	_refresh_preview()
	_clear_properties()
	if _project and index >= 0 and index < _project.shared_nodes.size():
		_selected_node = _project.shared_nodes[index]
		if _property_editor and _property_editor.has_method("set_target"):
			_property_editor.set_target(_selected_node)
		if _command_tab:
			_command_tab.selected_node = _selected_node
			_command_tab.current_tab_index = 0
			_command_tab.refresh_tabs()
		_highlight_selected_node()
	else:
		_clear_commands()


# ============ Node Tree Events ============

func _on_tree_node_selected() -> void:
	var selected: TreeItem = node_tree.get_selected()
	if selected == null or not _item_to_node.has(selected):
		_selected_node = null
		_clear_properties()
		_clear_commands()
		return
	_selected_node = _item_to_node[selected]
	if _property_editor and _property_editor.has_method("set_target"):
		_property_editor.set_target(_selected_node)
	if _command_tab:
		_command_tab.selected_node = _selected_node
		_command_tab.current_tab_index = 0
		_command_tab.refresh_tabs()
	_highlight_selected_node()


func _on_add_child_node() -> void:
	if _project == null or _selected_shared_index < 0:
		return
	_adding_shared_root = false
	if node_type_option:
		node_type_option.clear()
		node_type_option.add_item("通用节点", 0)
		node_type_option.add_item("角色节点", 1)
		node_type_option.add_item("画布层", 2)
	if node_name_input:
		node_name_input.text = "NewNode"
	if add_node_dialog:
		add_node_dialog.title = "添加子节点"
		add_node_dialog.popup_centered()


func _on_delete_child_node() -> void:
	if _selected_node == null or _project == null or _selected_shared_index < 0:
		return
	var root_node: Resource = _project.shared_nodes[_selected_shared_index]
	if _selected_node == root_node:
		return
	_remove_node_recursive(root_node, _selected_node)
	_selected_node = null
	_rebuild_tree()
	_refresh_preview()
	_clear_properties()
	_clear_commands()
	_emit_content_changed()


func _on_add_node_confirmed() -> void:
	if _project == null:
		return
	var name_text: String = node_name_input.text.strip_edges() if node_name_input else "NewNode"
	if name_text.is_empty():
		name_text = "NewNode"
	var type_index: int = node_type_option.selected if node_type_option else 0
	var new_node: Resource = _create_node_by_type(type_index)
	
	# 使用补位制生成 ID
	if _adding_shared_root:
		var used_nums: Array[int] = AVGNode.collect_used_node_nums(_project.shared_nodes, "shared_")
		var next_num: int = AVGNode.next_available_num(used_nums)
		new_node.node_id = AVGNode.make_shared_id(next_num)
	else:
		# 子节点：收集当前公共节点树内所有已用的 node_ ID
		var root_node: Resource = _project.shared_nodes[_selected_shared_index] if _selected_shared_index >= 0 else null
		var used_nums: Array[int] = []
		if root_node:
			used_nums = AVGNode.collect_used_node_nums([root_node], "node_")
		var next_num: int = AVGNode.next_available_num(used_nums)
		new_node.node_id = AVGNode.make_node_id(next_num)
	
	new_node.command_tabs = [{"condition_commands": [], "mode": 0, "commands": []}]

	if _adding_shared_root:
		# 新增公共节点根
		new_node.node_name = _make_unique_name(name_text, _project.shared_nodes)
		new_node.norm_position = Vector2.ZERO
		new_node.norm_size = Vector2(0.1, 0.1)
		new_node.position = Vector2.ZERO
		new_node.size = Vector2(192, 108)  # 0.1 * 1920, 0.1 * 1080
		_project.shared_nodes.append(new_node)
		_refresh_node_list()
		node_list.select(_project.shared_nodes.size() - 1)
		_on_shared_node_selected(_project.shared_nodes.size() - 1)
	else:
		# 添加子节点
		if _selected_shared_index < 0:
			return
		var parent_node: Resource = _selected_node if _selected_node else _project.shared_nodes[_selected_shared_index]
		new_node.node_name = _make_unique_child_name(name_text, parent_node.children)
		parent_node.children.append(new_node)
		_rebuild_tree()
		_refresh_preview()

	_adding_shared_root = false
	_emit_content_changed()


## 根据类型索引创建节点
func _create_node_by_type(type_index: int) -> Resource:
	match type_index:
		0: return load("res://scripts/avg/resources/avg_node.gd").new()
		1: return load("res://scripts/avg/resources/nodes/avg_character_node.gd").new()
		2: return load("res://scripts/avg/resources/nodes/avg_canvas_layer_node.gd").new()
		_: return load("res://scripts/avg/resources/avg_node.gd").new()


func _on_property_changed(_prop_name: String, _old_value: Variant, _new_value: Variant) -> void:
	if _selected_node and _selected_shared_index >= 0 and _project:
		var root_node: Resource = _project.shared_nodes[_selected_shared_index]
		if _selected_node == root_node:
			_selected_node.norm_position = Vector2.ZERO
			_selected_node.position = Vector2.ZERO
			if _prop_name == "node_name":
				_refresh_node_list()
				if _selected_shared_index >= 0 and _selected_shared_index < node_list.item_count:
					node_list.select(_selected_shared_index)
		# 当归一化坐标变化时，同步像素值
		if _prop_name in ["norm_position", "norm_size"]:
			_selected_node.sync_pixel_values(_project_resolution)
	_rebuild_tree()
	_refresh_preview()
	_emit_content_changed()


# ============ Choice Editor ============

func _on_choice_edit_requested(cmd: Resource, focus_choice: int) -> void:
	if _command_tab == null or _choice_editor == null or cmd == null:
		return
	_choice_editor.open(cmd, focus_choice)


func _on_choice_changed() -> void:
	if _command_tab:
		_command_tab.refresh_command_list()
	_emit_content_changed()


# ============ Helpers ============

func _emit_content_changed() -> void:
	content_changed.emit()
	StorageManager.notify_content_changed()


func _remove_node_recursive(parent: Resource, target: Resource) -> bool:
	var idx: int = parent.children.find(target)
	if idx >= 0:
		parent.children.remove_at(idx)
		return true
	for child in parent.children:
		if _remove_node_recursive(child, target):
			return true
	return false


func _make_unique_name(base_name: String, nodes: Array) -> String:
	var existing: Array = []
	for n in nodes:
		existing.append(n.node_name)
	if base_name not in existing:
		return base_name
	var counter: int = 2
	while true:
		var candidate: String = "%s%d" % [base_name, counter]
		if candidate not in existing:
			return candidate
		counter += 1
	return base_name


func _make_unique_child_name(base_name: String, children: Array) -> String:
	return _make_unique_name(base_name, children)
