class_name SceneFilePanel extends VBoxContainer
## Scene File Panel
## 显示项目中的场景列表，支持文件夹分组、新建/删除场景

const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")

signal scene_selected(scene: Resource)
signal scene_double_clicked(scene: Resource)

# 当前项目
var current_project: Resource = null

# UI引用
@onready var toolbar: HBoxContainer = $Toolbar
@onready var new_scene_button: Button = $Toolbar/NewSceneButton
@onready var new_folder_button: Button = $Toolbar/NewFolderButton
@onready var delete_button: Button = $Toolbar/DeleteButton
@onready var scene_tree: Tree = $SceneTree

# 对话框
var new_scene_dialog: ConfirmationDialog = null
var new_folder_dialog: ConfirmationDialog = null
var delete_dialog: ConfirmationDialog = null
var scene_name_input: LineEdit = null
var folder_name_input: LineEdit = null

# 场景数据结构: { "folder_name": [scene1, scene2], "": [root_scenes] }
var _scene_folders: Dictionary = {}
var _selected_item: TreeItem = null


func _ready() -> void:
	print("[SceneFilePanel] _ready() called")
	_setup_ui()
	_setup_connections()
	_setup_dialogs()
	
	# 监听全局项目变化
	StorageManager.current_project_changed.connect(_on_project_changed)
	if StorageManager.current_project != null:
		set_project(StorageManager.current_project)


func _setup_ui() -> void:
	if scene_tree:
		scene_tree.hide_root = true
		scene_tree.select_mode = Tree.SELECT_SINGLE


func _setup_connections() -> void:
	if new_scene_button:
		new_scene_button.pressed.connect(_on_new_scene_pressed)
	if new_folder_button:
		new_folder_button.pressed.connect(_on_new_folder_pressed)
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if scene_tree:
		scene_tree.item_selected.connect(_on_item_selected)
		scene_tree.item_activated.connect(_on_item_activated)


func _setup_dialogs() -> void:
	# 新建场景对话框
	new_scene_dialog = ConfirmationDialog.new()
	new_scene_dialog.title = "新建场景"
	new_scene_dialog.size = Vector2i(300, 120)
	var scene_vbox := VBoxContainer.new()
	var scene_label := Label.new()
	scene_label.text = "场景名称:"
	scene_name_input = LineEdit.new()
	scene_name_input.placeholder_text = "new_scene"
	scene_vbox.add_child(scene_label)
	scene_vbox.add_child(scene_name_input)
	new_scene_dialog.add_child(scene_vbox)
	new_scene_dialog.confirmed.connect(_on_new_scene_confirmed)
	add_child(new_scene_dialog)
	
	# 新建文件夹对话框
	new_folder_dialog = ConfirmationDialog.new()
	new_folder_dialog.title = "新建文件夹"
	new_folder_dialog.size = Vector2i(300, 120)
	var folder_vbox := VBoxContainer.new()
	var folder_label := Label.new()
	folder_label.text = "文件夹名称:"
	folder_name_input = LineEdit.new()
	folder_name_input.placeholder_text = "new_folder"
	folder_vbox.add_child(folder_label)
	folder_vbox.add_child(folder_name_input)
	new_folder_dialog.add_child(folder_vbox)
	new_folder_dialog.confirmed.connect(_on_new_folder_confirmed)
	add_child(new_folder_dialog)
	
	# 删除确认对话框
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "确认删除"
	delete_dialog.size = Vector2i(300, 100)
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(delete_dialog)


## 设置项目
func set_project(project: Resource) -> void:
	print("[SceneFilePanel] set_project: %s" % (project.project_name if project else "null"))
	current_project = project
	_refresh_tree()


## 刷新场景树
func _refresh_tree() -> void:
	if scene_tree == null:
		return
	
	scene_tree.clear()
	_scene_folders.clear()
	
	if current_project == null:
		print("[SceneFilePanel] No project loaded")
		return
	
	var root: TreeItem = scene_tree.create_item()
	
	# 组织场景到文件夹
	_organize_scenes()
	
	# 先添加文件夹
	for folder_name in _scene_folders.keys():
		if folder_name == "":
			continue  # 根目录场景稍后添加
		
		var folder_item: TreeItem = scene_tree.create_item(root)
		folder_item.set_text(0, "📁 " + folder_name)
		folder_item.set_meta("type", "folder")
		folder_item.set_meta("folder_name", folder_name)
		
		# 添加文件夹中的场景
		for scene in _scene_folders[folder_name]:
			_add_scene_item(folder_item, scene)
	
	# 添加根目录的场景
	if _scene_folders.has(""):
		for scene in _scene_folders[""]:
			_add_scene_item(root, scene)
	
	print("[SceneFilePanel] Tree refreshed, total scenes: %d" % current_project.scenes.size())


## 组织场景到文件夹结构
func _organize_scenes() -> void:
	_scene_folders = {"": []}  # 根目录
	
	if current_project == null or current_project.scenes == null:
		return
	
	for scene in current_project.scenes:
		if scene == null:
			continue
		
		var folder: String = scene.folder if "folder" in scene and scene.folder else ""
		
		if not _scene_folders.has(folder):
			_scene_folders[folder] = []
		
		_scene_folders[folder].append(scene)


## 添加场景项到树
func _add_scene_item(parent: TreeItem, scene: Resource) -> TreeItem:
	var item: TreeItem = scene_tree.create_item(parent)
	var scene_name: String = scene.scene_name if "scene_name" in scene else "Unnamed"
	if DBToolsClass.is_placeholder_scene(scene):
		scene_name += " [占位]"
	item.set_text(0, "🎬 " + scene_name)
	item.set_meta("type", "scene")
	item.set_meta("scene", scene)
	return item


## 处理项目变化
func _on_project_changed(project: Resource) -> void:
	set_project(project)


## 新建场景按钮
func _on_new_scene_pressed() -> void:
	print("[SceneFilePanel] New scene button pressed")
	if current_project == null:
		push_warning("No project loaded")
		return
	
	scene_name_input.text = "scene_%d" % (current_project.scenes.size() + 1)
	new_scene_dialog.popup_centered()
	scene_name_input.grab_focus()
	scene_name_input.select_all()


## 新建文件夹按钮
func _on_new_folder_pressed() -> void:
	print("[SceneFilePanel] New folder button pressed")
	folder_name_input.text = "new_folder"
	new_folder_dialog.popup_centered()
	folder_name_input.grab_focus()
	folder_name_input.select_all()


## 删除按钮
func _on_delete_pressed() -> void:
	print("[SceneFilePanel] Delete button pressed")
	if _selected_item == null:
		return
	
	var item_type: String = _selected_item.get_meta("type", "")
	if item_type == "scene":
		var scene = _selected_item.get_meta("scene")
		delete_dialog.dialog_text = "确定要删除场景 '%s' 吗？" % scene.scene_name
	elif item_type == "folder":
		var folder_name: String = _selected_item.get_meta("folder_name")
		delete_dialog.dialog_text = "确定要删除文件夹 '%s' 及其中的所有场景吗？" % folder_name
	else:
		return
	
	delete_dialog.popup_centered()


## 确认新建场景
func _on_new_scene_confirmed() -> void:
	var scene_name: String = scene_name_input.text.strip_edges()
	if scene_name.is_empty():
		return
	
	print("[SceneFilePanel] Creating new scene: %s" % scene_name)
	
	# 创建新场景
	var AVGSceneClass = load("res://scripts/avg/resources/avg_scene.gd")
	var new_scene: Resource = AVGSceneClass.new()
	new_scene.scene_id = "scene_" + str(Time.get_unix_time_from_system()).replace(".", "_")
	new_scene.scene_name = scene_name
	
	# 如果选中了文件夹，放入该文件夹
	if _selected_item != null and _selected_item.get_meta("type", "") == "folder":
		new_scene.folder = _selected_item.get_meta("folder_name")
	
	# 创建根节点（使用 AVGRootNode）
	var AVGRootNodeClass = load("res://scripts/avg/resources/nodes/avg_root_node.gd")
	var root_node: Resource = AVGRootNodeClass.new()
	root_node.node_id = "root"
	root_node.node_name = "Root"
	# 从项目获取分辨率
	var resolution: Vector2 = Vector2(2560, 1440)
	if current_project and "resolution" in current_project:
		resolution = Vector2(current_project.resolution)
	root_node.position = Vector2.ZERO
	root_node.size = resolution
	root_node.command_tabs = [{
		"condition_type": 0,
		"condition_var": "",
		"condition_op": ">=",
		"condition_value": 0,
		"mode": 0,
		"commands": []
	}]
	new_scene.nodes.append(root_node)
	
	# 添加到项目
	current_project.scenes.append(new_scene)
	
	_refresh_tree()
	
	# 选中并打开新场景
	scene_double_clicked.emit(new_scene)


## 确认新建文件夹
func _on_new_folder_confirmed() -> void:
	var folder_name: String = folder_name_input.text.strip_edges()
	if folder_name.is_empty():
		return
	
	print("[SceneFilePanel] Creating new folder: %s" % folder_name)
	
	# 文件夹只是一个分组概念，不需要实际创建
	# 只需要刷新树即可（如果有场景使用这个文件夹名）
	# 为了让空文件夹也显示，我们需要在项目中记录文件夹列表
	if not _scene_folders.has(folder_name):
		_scene_folders[folder_name] = []
	
	_refresh_tree()


## 确认删除
func _on_delete_confirmed() -> void:
	if _selected_item == null or current_project == null:
		return
	
	var item_type: String = _selected_item.get_meta("type", "")
	
	if item_type == "scene":
		var scene = _selected_item.get_meta("scene")
		var index: int = current_project.scenes.find(scene)
		if index >= 0:
			current_project.scenes.remove_at(index)
			print("[SceneFilePanel] Deleted scene: %s" % scene.scene_name)
	elif item_type == "folder":
		var folder_name: String = _selected_item.get_meta("folder_name")
		# 删除文件夹中的所有场景
		var to_remove: Array = []
		for scene in current_project.scenes:
			if scene.folder == folder_name:
				to_remove.append(scene)
		for scene in to_remove:
			current_project.scenes.erase(scene)
		print("[SceneFilePanel] Deleted folder: %s with %d scenes" % [folder_name, to_remove.size()])
	
	_selected_item = null
	_refresh_tree()


## 选中项
func _on_item_selected() -> void:
	_selected_item = scene_tree.get_selected()
	if _selected_item == null:
		return
	
	var item_type: String = _selected_item.get_meta("type", "")
	if item_type == "scene":
		var scene = _selected_item.get_meta("scene")
		print("[SceneFilePanel] Scene selected: %s" % scene.scene_name)
		scene_selected.emit(scene)


## 双击项（打开场景）
func _on_item_activated() -> void:
	if _selected_item == null:
		return
	
	var item_type: String = _selected_item.get_meta("type", "")
	if item_type == "scene":
		var scene = _selected_item.get_meta("scene")
		print("[SceneFilePanel] Scene double-clicked: %s" % scene.scene_name)
		scene_double_clicked.emit(scene)
	elif item_type == "folder":
		# 展开/折叠文件夹
		_selected_item.collapsed = not _selected_item.collapsed
