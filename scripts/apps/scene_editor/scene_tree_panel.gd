class_name SceneTreePanel extends VBoxContainer
## Scene Tree Panel Component
## Displays AVGNode hierarchy using Tree control with icons, visibility toggle, and context menu.

const AVGCanvasLayerNodeClass = preload("res://scripts/avg/resources/nodes/avg_canvas_layer_node.gd")

# Signals
signal node_selected(node: Resource)
signal node_moved(node: Resource, new_parent: Resource, index: int)
signal node_visibility_changed(node: Resource, visible: bool)

# Current scene reference
var _scene: Resource = null  # AVGScene
# Map of TreeItem to AVGNode
var _item_to_node: Dictionary = {}
# Map of AVGNode to TreeItem
var _node_to_item: Dictionary = {}
# Clipboard for copy/paste
var _clipboard_node: Resource = null

# Button indices
const BUTTON_VISIBLE: int = 0

# Context menu item IDs
enum ContextMenuItem {
	ADD_CHILD,
	COPY,
	PASTE,
	DELETE,
	SEPARATOR,
	MOVE_UP,
	MOVE_DOWN,
	MAKE_UNIQUE,
}

# UI References
@onready var tree: Tree = %Tree
@onready var toolbar: HBoxContainer = %Toolbar
@onready var add_button: Button = %AddButton
@onready var delete_button: Button = %DeleteButton
@onready var move_up_button: Button = %MoveUpButton
@onready var move_down_button: Button = %MoveDownButton
@onready var context_menu: PopupMenu = %ContextMenu


func _ready() -> void:
	_setup_tree()
	_setup_toolbar()
	_setup_context_menu()


func _setup_tree() -> void:
	if tree:
		print("[SceneTreePanel] _setup_tree: tree found")
		tree.item_selected.connect(_on_item_selected)
		tree.button_clicked.connect(_on_tree_button_clicked)
		tree.item_mouse_selected.connect(_on_item_mouse_selected)
		tree.allow_rmb_select = true  # 允许右键选中，触发 item_mouse_selected
		
		# 设置列
		tree.columns = 2
		tree.set_column_expand(0, true)  # 名称列扩展
		tree.set_column_expand(1, false)  # 按钮列固定
		tree.set_column_custom_minimum_width(1, 30)
		
		# Enable drag and drop
		tree.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)
	else:
		print("[SceneTreePanel] _setup_tree: tree is NULL")


func _setup_toolbar() -> void:
	if add_button:
		add_button.pressed.connect(_on_add_pressed)
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if move_up_button:
		move_up_button.pressed.connect(_on_move_up_pressed)
	if move_down_button:
		move_down_button.pressed.connect(_on_move_down_pressed)


func _setup_context_menu() -> void:
	if context_menu == null:
		return
	
	context_menu.clear()
	context_menu.add_item("添加子节点", ContextMenuItem.ADD_CHILD)
	context_menu.add_separator()
	context_menu.add_item("复制", ContextMenuItem.COPY)
	context_menu.add_item("粘贴", ContextMenuItem.PASTE)
	context_menu.add_separator()
	context_menu.add_item("删除", ContextMenuItem.DELETE)
	context_menu.add_separator()
	context_menu.add_item("上移", ContextMenuItem.MOVE_UP)
	context_menu.add_item("下移", ContextMenuItem.MOVE_DOWN)
	context_menu.add_separator()
	context_menu.add_item("唯一化", ContextMenuItem.MAKE_UNIQUE)
	
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)


## Set the scene to display
func set_scene(scene: Resource) -> void:
	_scene = scene
	_rebuild_tree()


## Get the currently selected node
func get_selected_node() -> Resource:
	if tree == null:
		return null
	
	var selected: TreeItem = tree.get_selected()
	if selected and _item_to_node.has(selected):
		return _item_to_node[selected]
	return null


## Select a specific node in the tree
func select_node(node: Resource) -> void:
	if node == null or tree == null:
		return
	
	if _node_to_item.has(node):
		var item: TreeItem = _node_to_item[node]
		item.select(0)
		tree.scroll_to_item(item)


## Rebuild the entire tree
func _rebuild_tree() -> void:
	if tree == null:
		return
	
	tree.clear()
	_item_to_node.clear()
	_node_to_item.clear()
	
	if _scene == null:
		return
	
	# 隐藏树的根节点，直接显示场景中的节点
	tree.hide_root = true
	var root: TreeItem = tree.create_item()
	
	# Add all nodes directly under hidden root
	for node in _scene.nodes:
		_add_node_to_tree(node, root)


## Add a node and its children to the tree
func _add_node_to_tree(node: Resource, parent_item: TreeItem) -> TreeItem:
	var item: TreeItem = tree.create_item(parent_item)
	
	# 第一列：图标和名称
	var display_name: String = node.node_name
	if node is AVGSharedNodeRef:
		var ref_display: String = node.shared_node_name
		# 从项目中获取最新名称
		var project = StorageManager.current_project
		if project and not node.shared_node_id.is_empty():
			var resolved: Resource = node.get_resolved_node(project)
			if resolved:
				ref_display = resolved.node_name
		display_name = "%s [%s]" % [node.node_name, ref_display]
		if node.is_unique:
			display_name += " (唯一)"
	
	item.set_text(0, display_name)
	item.set_icon(0, _get_icon_for_node(node))
	item.set_metadata(0, node)
	
	# 第二列：可见性按钮
	var visible_icon: Texture2D = _get_visibility_icon(node.visible)
	item.add_button(1, visible_icon, BUTTON_VISIBLE, false, "切换可见性")
	
	_item_to_node[item] = node
	_node_to_item[node] = item
	
	# SharedNodeRef 不展开子节点（除非已唯一化）
	if node is AVGSharedNodeRef and not node.is_unique:
		# 非唯一：显示 SharedNodeRef 自己的 children（场景内添加的子节点）
		# 模板内部的子节点不显示（那是模板定义的）
		for child in node.children:
			_add_node_to_tree(child, item)
	elif node is AVGSharedNodeRef and node.is_unique and node.unique_data != null:
		# 唯一化后显示 unique_data 的子节点
		for child in node.unique_data.children:
			_add_node_to_tree(child, item)
	else:
		# Add children recursively
		for child in node.children:
			_add_node_to_tree(child, item)
	
	# 默认展开
	item.collapsed = false
	
	return item


## Get icon for node type
func _get_icon_for_node(node: Resource) -> Texture2D:
	# 尝试获取编辑器图标
	var icon_name: String = "Node"
	
	if node is AVGRootNode:
		icon_name = "Node2D"
	elif node is AVGSharedNodeRef:
		icon_name = "PackedScene"
	elif node is AVGCharacterNode:
		icon_name = "Sprite2D"
	else:
		icon_name = "Control"
	
	if Engine.is_editor_hint():
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			var base_control = editor_interface.get_base_control()
			if base_control:
				return base_control.get_theme_icon(icon_name, "EditorIcons")
	
	# 运行时创建简单图标
	return _create_node_type_icon(node)


## Create a simple node type icon at runtime
func _create_node_type_icon(node: Resource) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var color: Color = Color(0.7, 0.7, 0.7, 1.0)
	
	# Different colors for different node types
	if node is AVGRootNode:
		color = Color(0.2, 0.6, 0.9, 1.0)  # Blue
	elif node is AVGSharedNodeRef:
		color = Color(0.2, 0.9, 0.9, 1.0)  # Cyan
	elif node is AVGCharacterNode:
		color = Color(0.9, 0.6, 0.2, 1.0)  # Orange
	elif node is AVGCanvasLayerNodeClass:
		color = Color(0.9, 0.3, 0.9, 1.0)  # Purple
	else:
		color = Color(0.5, 0.7, 0.9, 1.0)  # Light blue
	
	# Draw a simple square icon
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 14):
		for y in range(2, 14):
			img.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(img)


## Get visibility icon
func _get_visibility_icon(node_visible: bool) -> Texture2D:
	# 尝试获取编辑器图标
	if Engine.is_editor_hint():
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			var base_control = editor_interface.get_base_control()
			if base_control:
				var icon_name: String = "GuiVisibilityVisible" if node_visible else "GuiVisibilityHidden"
				return base_control.get_theme_icon(icon_name, "EditorIcons")
	
	# 运行时创建简单图标
	return _create_visibility_icon(node_visible)


## Create a simple visibility icon at runtime
func _create_visibility_icon(node_visible: bool) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var color: Color = Color(1, 1, 1, 1) if node_visible else Color(0.5, 0.5, 0.5, 0.5)
	
	# Draw a simple eye shape
	img.fill(Color(0, 0, 0, 0))
	for x in range(3, 13):
		for y in range(5, 11):
			var dist: float = abs(y - 8)
			if dist <= 3 - abs(x - 8) * 0.3:
				img.set_pixel(x, y, color)
	# Eye center
	if node_visible:
		for x in range(6, 10):
			for y in range(6, 10):
				if Vector2(x, y).distance_to(Vector2(8, 8)) < 2:
					img.set_pixel(x, y, Color(0.2, 0.2, 0.2, 1))
	
	return ImageTexture.create_from_image(img)


## Handle tree item selection
func _on_item_selected() -> void:
	var node: Resource = get_selected_node()
	if node:
		node_selected.emit(node)
		# 如果是根节点，禁用删除按钮
		if delete_button:
			delete_button.disabled = (node is AVGRootNode)


## Handle tree button click (visibility toggle)
func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if column != 1 or id != BUTTON_VISIBLE or mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	
	if not _item_to_node.has(item):
		return
	
	var node: Resource = _item_to_node[item]
	node.visible = not node.visible
	
	# 更新按钮图标
	var new_icon: Texture2D = _get_visibility_icon(node.visible)
	item.set_button(1, BUTTON_VISIBLE, new_icon)
	
	node_visibility_changed.emit(node, node.visible)


## Handle right-click on item
func _on_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	print("[SceneTreePanel] _on_item_mouse_selected: pos=%s, button=%d" % [mouse_position, mouse_button_index])
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	
	var sel_node: Resource = get_selected_node()
	print("[SceneTreePanel] Selected node: %s" % (sel_node.node_name if sel_node else "null"))
	if sel_node == null:
		return
	
	# 更新菜单项状态
	_update_context_menu_state(sel_node)
	
	# 显示菜单
	var popup_pos: Vector2i = Vector2i(get_screen_position() + mouse_position)
	print("[SceneTreePanel] Popup at: %s, context_menu: %s" % [popup_pos, context_menu])
	context_menu.position = popup_pos
	context_menu.popup()


## Update context menu item states
func _update_context_menu_state(node: Resource) -> void:
	if context_menu == null:
		return
	
	# 根节点不能删除
	var is_root: bool = node is AVGRootNode
	var idx_delete: int = context_menu.get_item_index(ContextMenuItem.DELETE)
	if idx_delete >= 0:
		context_menu.set_item_disabled(idx_delete, is_root)
	
	# 粘贴：只有剪贴板有内容时才启用
	var idx_paste: int = context_menu.get_item_index(ContextMenuItem.PASTE)
	if idx_paste >= 0:
		context_menu.set_item_disabled(idx_paste, _clipboard_node == null)
	
	# 唯一化：只有 SharedNodeRef 且未唯一化时才启用
	var idx_make_unique: int = context_menu.get_item_index(ContextMenuItem.MAKE_UNIQUE)
	if idx_make_unique >= 0:
		var can_make_unique: bool = node is AVGSharedNodeRef and not node.is_unique
		context_menu.set_item_disabled(idx_make_unique, not can_make_unique)
	
	# 添加子节点：所有节点都可以（SharedNodeRef 也可以有场景内子节点）
	var idx_add_child: int = context_menu.get_item_index(ContextMenuItem.ADD_CHILD)
	if idx_add_child >= 0:
		context_menu.set_item_disabled(idx_add_child, false)


## Handle context menu selection
func _on_context_menu_id_pressed(id: int) -> void:
	var selected_node: Resource = get_selected_node()
	if selected_node == null:
		return
	
	match id:
		ContextMenuItem.ADD_CHILD:
			_on_add_child_to_node(selected_node)
		ContextMenuItem.COPY:
			_on_copy_node(selected_node)
		ContextMenuItem.PASTE:
			_on_paste_node(selected_node)
		ContextMenuItem.DELETE:
			_on_delete_pressed()
		ContextMenuItem.MOVE_UP:
			_on_move_up_pressed()
		ContextMenuItem.MOVE_DOWN:
			_on_move_down_pressed()
		ContextMenuItem.MAKE_UNIQUE:
			_on_make_unique(selected_node)


## Add child to selected node
func _on_add_child_to_node(parent_node: Resource) -> void:
	var parent_editor = _get_scene_editor()
	if parent_editor and parent_editor.has_method("show_add_node_dialog_for_parent"):
		parent_editor.show_add_node_dialog_for_parent(parent_node)
	elif parent_editor and parent_editor.has_method("show_add_node_dialog"):
		parent_editor.show_add_node_dialog()


## Copy node to clipboard
func _on_copy_node(node: Resource) -> void:
	if node is AVGRootNode:
		print("[SceneTreePanel] Cannot copy root node")
		return
	
	# 深拷贝节点
	_clipboard_node = _deep_copy_node(node)
	print("[SceneTreePanel] Copied node: %s" % node.node_name)


## Paste node from clipboard
func _on_paste_node(parent_node: Resource) -> void:
	if _clipboard_node == null:
		return
	
	# 获取场景编辑器以访问当前场景
	var parent_editor = _get_scene_editor()
	var scene_nodes: Array = []
	if parent_editor and parent_editor.current_scene:
		scene_nodes = parent_editor.current_scene.nodes
	
	# 创建副本
	var new_node: Resource = _deep_copy_node(_clipboard_node, scene_nodes)
	
	# 确保同层级不重名
	var base_name: String = _clipboard_node.node_name
	new_node.node_name = _make_unique_sibling_name(base_name, parent_node.children)
	
	# 添加到父节点
	parent_node.children.append(new_node)
	
	print("[SceneTreePanel] Pasted node: %s" % new_node.node_name)
	
	_rebuild_tree()
	select_node(new_node)
	
	# 通知场景编辑器刷新预览
	if parent_editor and parent_editor.has_method("_refresh_preview"):
		parent_editor._refresh_preview()


## Deep copy a node and its children (使用补位制生成 ID)
func _deep_copy_node(node: Resource, scene_nodes: Array = []) -> Resource:
	var new_node: Resource = node.duplicate(true)
	
	# 使用补位制生成新 ID
	var used_nums: Array[int] = AVGNode.collect_used_node_nums(scene_nodes, "node_")
	var next_num: int = AVGNode.next_available_num(used_nums)
	new_node.node_id = AVGNode.make_node_id(next_num)
	
	# 递归复制子节点
	var new_children: Array[AVGNode] = []
	for child in node.children:
		# 更新 used_nums 以避免子节点 ID 冲突
		used_nums.append(next_num)
		new_children.append(_deep_copy_node(child, scene_nodes))
	new_node.children = new_children
	
	return new_node


## Get scene editor reference
func _get_scene_editor() -> Node:
	var parent_editor = get_parent()
	while parent_editor and not parent_editor is SceneEditor:
		parent_editor = parent_editor.get_parent()
	return parent_editor


## Handle add button
func _on_add_pressed() -> void:
	var parent_editor = _get_scene_editor()
	if parent_editor:
		parent_editor.show_add_node_dialog()


## Handle delete button
func _on_delete_pressed() -> void:
	var parent_editor = _get_scene_editor()
	if parent_editor:
		parent_editor.show_delete_dialog()


## Handle move up button
func _on_move_up_pressed() -> void:
	var parent_editor = _get_scene_editor()
	if parent_editor:
		parent_editor.move_node_up()


## Handle move down button
func _on_move_down_pressed() -> void:
	var parent_editor = _get_scene_editor()
	if parent_editor:
		parent_editor.move_node_down()


# ============ Drag and drop support ============

func _get_drag_data(at_position: Vector2) -> Variant:
	var item: TreeItem = tree.get_item_at_position(at_position)
	if item == null or not _item_to_node.has(item):
		return null
	
	var node: Resource = _item_to_node[item]
	
	# 不能拖拽根节点
	if node is AVGRootNode:
		return null
	
	# Create drag preview
	var preview := Label.new()
	preview.text = node.node_name
	set_drag_preview(preview)
	
	return {"type": "avg_node", "node": node, "item": item}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if data == null or not data is Dictionary:
		return false
	if not data.has("type") or data["type"] != "avg_node":
		return false
	
	var target_item: TreeItem = tree.get_item_at_position(at_position)
	if target_item == null:
		return false
	
	# Can't drop on itself
	if data["item"] == target_item:
		return false
	
	var drag_node: Resource = data["node"]
	
	# Check if target is a descendant of drag node (prevent circular reference)
	if _item_to_node.has(target_item):
		var target_node: Resource = _item_to_node[target_item]
		if _is_descendant_of(target_node, drag_node):
			return false
	
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	
	var node: Resource = data["node"]
	var target_item: TreeItem = tree.get_item_at_position(at_position)
	var target_node: Resource = null
	
	if _item_to_node.has(target_item):
		target_node = _item_to_node[target_item]
	
	# Remove from current parent
	_remove_node_from_parent(node)
	
	# Add to new parent
	if target_node:
		target_node.children.append(node)
	
	node_moved.emit(node, target_node, -1)
	_rebuild_tree()
	select_node(node)
	
	# 刷新预览
	var parent_editor = _get_scene_editor()
	if parent_editor and parent_editor.has_method("_refresh_preview"):
		parent_editor._refresh_preview()


## Check if node is a descendant of potential_ancestor
func _is_descendant_of(node: Resource, potential_ancestor: Resource) -> bool:
	for child in potential_ancestor.children:
		if child == node:
			return true
		if _is_descendant_of(node, child):
			return true
	return false


## Remove a node from its current parent
func _remove_node_from_parent(node: Resource) -> void:
	if _scene == null:
		return
	
	# Try scene root
	var index: int = _scene.nodes.find(node)
	if index >= 0:
		_scene.nodes.remove_at(index)
		return
	
	# Try children of all nodes
	_remove_from_children_recursive(_scene.nodes, node)


func _remove_from_children_recursive(nodes: Array, target: Resource) -> bool:
	for parent_node in nodes:
		var index: int = parent_node.children.find(target)
		if index >= 0:
			parent_node.children.remove_at(index)
			return true
		if _remove_from_children_recursive(parent_node.children, target):
			return true
	return false


## 生成不重复的兄弟节点名称
func _make_unique_sibling_name(base_name: String, siblings: Array) -> String:
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


## Make SharedNodeRef unique (convert to independent copy)
func _on_make_unique(node: Resource) -> void:
	if not node is AVGSharedNodeRef:
		return
	if node.is_unique:
		return
	
	# Get project from scene editor
	var parent_editor = _get_scene_editor()
	if parent_editor == null:
		return
	
	var project: Resource = StorageManager.current_project
	if project == null:
		return
	
	# Call make_unique on the node
	node.make_unique(project)
	
	print("[SceneTreePanel] Made node unique: %s" % node.node_name)
	
	_rebuild_tree()
	select_node(node)
	
	# Refresh preview
	if parent_editor.has_method("_refresh_preview"):
		parent_editor._refresh_preview()
