class_name ResourceLibraryPanel extends VBoxContainer
## Resource Library Panel
## 资源库面板 - 管理项目 assets/ 下的图片、音频、字体
## 左侧文件夹树 + 右侧资源网格/列表 + 预览

signal resource_selected(relative_path: String)

var _project: Resource = null
var _project_root_override: String = ""
## 当前选中的文件夹相对路径（相对于项目根，如 "assets/images/"）
var _current_dir: String = "assets/"
## 当前选中的资源相对路径
var _selected_resource_path: String = ""
## 文件类型过滤（空字符串=不过滤，"image"/"audio"/"font" 等）
var filter_category: String = ""

# UI — 全部在 _ready 中通过 find_child 获取
var folder_tree: Tree = null
var resource_grid: ItemList = null
var preview_texture: TextureRect = null
var preview_label: Label = null
var play_audio_button: Button = null
var import_button: Button = null
var delete_button: Button = null
var new_folder_button: Button = null
var delete_folder_button: Button = null
var import_file_dialog: FileDialog = null
var new_folder_dialog: ConfirmationDialog = null
var new_folder_name_input: LineEdit = null

var _audio_player: AudioStreamPlayer = null
## folder tree item -> relative dir path
var _tree_item_to_path: Dictionary = {}


func _ready() -> void:
	_resolve_ui()
	_setup_connections()
	_setup_audio_player()


func _resolve_ui() -> void:
	folder_tree = find_child("FolderTree", true, false) as Tree
	resource_grid = find_child("ResourceGrid", true, false) as ItemList
	preview_texture = find_child("PreviewTexture", true, false) as TextureRect
	preview_label = find_child("PreviewLabel", true, false) as Label
	play_audio_button = find_child("PlayAudioButton", true, false) as Button
	import_button = find_child("ImportButton", true, false) as Button
	delete_button = find_child("DeleteButton", true, false) as Button
	new_folder_button = find_child("NewFolderButton", true, false) as Button
	delete_folder_button = find_child("DeleteFolderButton", true, false) as Button
	import_file_dialog = find_child("ImportFileDialog", true, false) as FileDialog
	new_folder_dialog = find_child("NewFolderDialog", true, false) as ConfirmationDialog
	new_folder_name_input = find_child("NewFolderNameInput", true, false) as LineEdit


func _setup_connections() -> void:
	if folder_tree:
		folder_tree.item_selected.connect(_on_folder_selected)
	if resource_grid:
		resource_grid.item_selected.connect(_on_resource_selected)
		resource_grid.item_activated.connect(_on_resource_activated)
	if import_button:
		import_button.pressed.connect(_on_import_pressed)
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if new_folder_button:
		new_folder_button.pressed.connect(_on_new_folder_pressed)
	if delete_folder_button:
		delete_folder_button.pressed.connect(_on_delete_folder_pressed)
	if play_audio_button:
		play_audio_button.pressed.connect(_on_play_audio_pressed)
	if import_file_dialog:
		import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		import_file_dialog.filters = PackedStringArray([
			"*.png, *.jpg, *.jpeg, *.webp, *.svg ; 图片",
			"*.ogg, *.mp3, *.wav ; 音频",
			"*.ttf, *.otf ; 字体",
		])
		import_file_dialog.files_selected.connect(_on_files_imported)
	if new_folder_dialog:
		new_folder_dialog.confirmed.connect(_on_new_folder_confirmed)


func _setup_audio_player() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)


# =============================================================================
# Public API
# =============================================================================

func set_project(project: Resource) -> void:
	_project = project
	_project_root_override = _resolve_project_root(project)
	_current_dir = "assets/"
	_selected_resource_path = ""
	_refresh_folder_tree()
	_refresh_resource_grid()
	_clear_preview()
	_update_buttons()


func get_project() -> Resource:
	return _project


func set_project_root(project_root: String) -> void:
	_project_root_override = project_root.strip_edges()


## 获取当前选中的资源相对路径
func get_selected_path() -> String:
	return _selected_resource_path


# =============================================================================
# Folder Tree
# =============================================================================

func _refresh_folder_tree() -> void:
	if folder_tree == null:
		return
	folder_tree.clear()
	_tree_item_to_path.clear()

	var project_root: String = _get_project_root()
	if project_root.is_empty():
		return

	# 确保 assets 目录存在
	var assets_abs: String = project_root + "assets/"
	if not DirAccess.dir_exists_absolute(assets_abs):
		DirAccess.make_dir_recursive_absolute(assets_abs)

	var root_item: TreeItem = folder_tree.create_item()
	root_item.set_text(0, "assets")
	_tree_item_to_path[root_item] = "assets/"

	_build_folder_tree_recursive(root_item, "assets/")

	# 展开根节点
	root_item.collapsed = false

	# 选中当前目录
	_select_tree_item_by_path(_current_dir)


func _build_folder_tree_recursive(parent_item: TreeItem, relative_dir: String) -> void:
	var listing: Dictionary = _list_directory(relative_dir)
	var dirs: Array = listing.get("dirs", [])

	for dir_name in dirs:
		var child_path: String = relative_dir + dir_name + "/"
		var child_item: TreeItem = folder_tree.create_item(parent_item)
		child_item.set_text(0, dir_name)
		_tree_item_to_path[child_item] = child_path
		_build_folder_tree_recursive(child_item, child_path)
		child_item.collapsed = false


func _select_tree_item_by_path(target_path: String) -> void:
	for item in _tree_item_to_path:
		if _tree_item_to_path[item] == target_path:
			item.select(0)
			return


func _on_folder_selected() -> void:
	var selected: TreeItem = folder_tree.get_selected()
	if selected == null:
		return
	if _tree_item_to_path.has(selected):
		_current_dir = _tree_item_to_path[selected]
	_selected_resource_path = ""
	_refresh_resource_grid()
	_clear_preview()
	_update_buttons()


# =============================================================================
# Resource Grid
# =============================================================================

func _refresh_resource_grid() -> void:
	if resource_grid == null:
		return
	resource_grid.clear()

	if _get_project_root().is_empty():
		return

	var listing: Dictionary = _list_directory(_current_dir)
	var files: Array = listing.get("files", [])

	for file_info in files:
		var file_name: String = file_info["name"]
		var file_path: String = file_info["path"]
		var ext: String = file_info["extension"]
		var category: String = StorageManager.get_file_category(ext)

		# 按类型过滤
		if not filter_category.is_empty() and category != filter_category:
			continue

		# 尝试加载缩略图
		var icon: Texture2D = null
		if category == "image":
			icon = StorageManager.load_texture_from_path(file_path, _project, _project_root_override)

		if icon:
			resource_grid.add_item(file_name, icon)
		else:
			resource_grid.add_item(file_name)

		resource_grid.set_item_metadata(resource_grid.item_count - 1, file_path)

	_update_buttons()


func _on_resource_selected(index: int) -> void:
	if resource_grid == null:
		return
	_selected_resource_path = resource_grid.get_item_metadata(index)
	_update_preview()
	_update_buttons()
	resource_selected.emit(_selected_resource_path)


func _on_resource_activated(_index: int) -> void:
	# 双击 = 确认选择（供外部弹窗使用）
	resource_selected.emit(_selected_resource_path)


# =============================================================================
# Preview
# =============================================================================

func _clear_preview() -> void:
	if preview_texture:
		preview_texture.texture = null
		preview_texture.visible = false
	if preview_label:
		preview_label.text = ""
	if play_audio_button:
		play_audio_button.visible = false
	_stop_audio()


func _update_preview() -> void:
	if _selected_resource_path.is_empty():
		_clear_preview()
		return

	var ext: String = _selected_resource_path.get_extension().to_lower()
	var category: String = StorageManager.get_file_category(ext)
	var file_name: String = _selected_resource_path.get_file()

	if preview_label:
		preview_label.text = file_name

	match category:
		"image":
			var tex: Texture2D = StorageManager.load_texture_from_path(_selected_resource_path, _project, _project_root_override)
			if preview_texture and tex:
				preview_texture.texture = tex
				preview_texture.visible = true
			if play_audio_button:
				play_audio_button.visible = false
		"audio":
			if preview_texture:
				preview_texture.visible = false
			if play_audio_button:
				play_audio_button.visible = true
				play_audio_button.text = "播放"
		"font":
			if preview_texture:
				preview_texture.visible = false
			if play_audio_button:
				play_audio_button.visible = false
		_:
			_clear_preview()


# =============================================================================
# Actions
# =============================================================================

func _on_import_pressed() -> void:
	if import_file_dialog:
		import_file_dialog.popup_centered(Vector2i(600, 400))


func _on_files_imported(paths: PackedStringArray) -> void:
	for source_path in paths:
		var file_name: String = source_path.get_file()
		var target_relative: String = _current_dir + file_name
		var err: Error = _import_asset(source_path, target_relative)
		if err != OK:
			push_warning("ResourceLibrary: Failed to import %s" % file_name)
	_refresh_resource_grid()


func _on_delete_pressed() -> void:
	if _selected_resource_path.is_empty():
		return
	_delete_asset(_selected_resource_path)
	_selected_resource_path = ""
	_refresh_resource_grid()
	_clear_preview()
	_update_buttons()


func _on_new_folder_pressed() -> void:
	if new_folder_name_input:
		new_folder_name_input.text = ""
	if new_folder_dialog:
		new_folder_dialog.popup_centered()
		if new_folder_name_input:
			new_folder_name_input.grab_focus()


func _on_new_folder_confirmed() -> void:
	var folder_name: String = ""
	if new_folder_name_input:
		folder_name = new_folder_name_input.text.strip_edges()
	if folder_name.is_empty():
		return
	# 不允许特殊字符
	folder_name = folder_name.replace("/", "").replace("\\", "").replace(".", "")
	if folder_name.is_empty():
		return
	var new_path: String = _current_dir + folder_name + "/"
	_make_directory(new_path)
	_refresh_folder_tree()
	_select_tree_item_by_path(new_path)
	_current_dir = new_path
	_refresh_resource_grid()


func _on_delete_folder_pressed() -> void:
	if _current_dir == "assets/":
		return  # 不能删除根目录
	var err: Error = _delete_directory(_current_dir)
	if err == OK:
		# 回到父目录
		var parent: String = _current_dir.trim_suffix("/")
		parent = parent.get_base_dir()
		if not parent.ends_with("/"):
			parent += "/"
		_current_dir = parent
		_refresh_folder_tree()
		_refresh_resource_grid()
	else:
		push_warning("ResourceLibrary: Cannot delete non-empty folder")


func _on_play_audio_pressed() -> void:
	if _selected_resource_path.is_empty() or _audio_player == null:
		return
	if _audio_player.playing:
		_stop_audio()
	else:
		var audio: AudioStream = StorageManager.load_audio_from_path(_selected_resource_path, _project, _project_root_override)
		if audio:
			_audio_player.stream = audio
			_audio_player.play()
			if play_audio_button:
				play_audio_button.text = "停止"


func _stop_audio() -> void:
	if _audio_player:
		_audio_player.stop()
	if play_audio_button:
		play_audio_button.text = "播放"


func _update_buttons() -> void:
	var has_selection: bool = not _selected_resource_path.is_empty()
	if delete_button:
		delete_button.disabled = not has_selection
	if delete_folder_button:
		delete_folder_button.disabled = (_current_dir == "assets/")
	if import_button:
		import_button.disabled = _get_project_root().is_empty()


func _get_project_root() -> String:
	if not _project_root_override.is_empty():
		return _project_root_override
	if _project != null and "project_root_path" in _project:
		return str(_project.get("project_root_path")).strip_edges()
	return StorageManager.current_project_path


func _resolve_project_root(project: Resource) -> String:
	if project != null and "project_root_path" in project:
		return str(project.get("project_root_path")).strip_edges()
	return ""


func _list_directory(relative_dir: String) -> Dictionary:
	var project_root: String = _get_project_root()
	if project_root.is_empty() or project_root == StorageManager.current_project_path:
		return StorageManager.list_directory(relative_dir)

	var result: Dictionary = {"dirs": [], "files": []}
	var abs_path: String = project_root + relative_dir
	var dir: DirAccess = DirAccess.open(abs_path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	while item_name != "":
		if not item_name.begins_with("."):
			if dir.current_is_dir():
				result["dirs"].append(item_name)
			else:
				var ext: String = item_name.get_extension().to_lower()
				if ext in StorageManager.ALL_EXTENSIONS:
					result["files"].append({
						"name": item_name,
						"path": relative_dir + item_name,
						"extension": ext,
					})
		item_name = dir.get_next()
	dir.list_dir_end()

	result["dirs"].sort()
	result["files"].sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	return result


func _make_directory(relative_dir: String) -> Error:
	var project_root: String = _get_project_root()
	if project_root.is_empty() or project_root == StorageManager.current_project_path:
		return StorageManager.make_directory(relative_dir)
	return DirAccess.make_dir_recursive_absolute(project_root + relative_dir)


func _delete_asset(relative_path: String) -> Error:
	var project_root: String = _get_project_root()
	if project_root.is_empty() or project_root == StorageManager.current_project_path:
		return StorageManager.delete_asset(relative_path)
	return DirAccess.remove_absolute(project_root + relative_path)


func _delete_directory(relative_dir: String) -> Error:
	var project_root: String = _get_project_root()
	if project_root.is_empty() or project_root == StorageManager.current_project_path:
		return StorageManager.delete_directory(relative_dir)

	var abs_path: String = project_root + relative_dir
	var dir: DirAccess = DirAccess.open(abs_path)
	if dir == null:
		return ERR_CANT_OPEN
	dir.list_dir_begin()
	var item: String = dir.get_next()
	while item != "":
		if not item.begins_with("."):
			dir.list_dir_end()
			return ERR_ALREADY_IN_USE
		item = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(abs_path)


func _import_asset(source_path: String, target_relative_path: String) -> Error:
	var project_root: String = _get_project_root()
	if project_root.is_empty() or project_root == StorageManager.current_project_path:
		return StorageManager.import_asset(source_path, target_relative_path)

	var abs_target: String = project_root + target_relative_path
	var target_dir: String = abs_target.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var err: Error = DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			return err

	var file_read: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file_read == null:
		return FileAccess.get_open_error()
	var content: PackedByteArray = file_read.get_buffer(file_read.get_length())
	file_read.close()

	var file_write: FileAccess = FileAccess.open(abs_target, FileAccess.WRITE)
	if file_write == null:
		return FileAccess.get_open_error()
	file_write.store_buffer(content)
	file_write.close()
	return OK
