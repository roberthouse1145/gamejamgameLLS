extends Node
## StorageManager Autoload
## 管理项目文件的保存和加载，支持三种存储模式：
## - user://projects/ - 用户项目（运行时可读写）
## - res://templates/ - 范例项目（只读，可复制到user://）
## - res://projects/ - 开发者模式项目（仅编辑器内可写）

# 预加载AVGProject类（确保类型可用）
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")

# 存储路径常量
const USER_PROJECTS_PATH: String = "user://projects/"
const RES_TEMPLATES_PATH: String = "res://templates/"
const RES_PROJECTS_PATH: String = "res://projects/" # 开发者模式
const RUNTIME_RUN_ROOT_PATH: String = "user://run/"
const RUNTIME_PLAYER_PROJECT_PATH: String = RUNTIME_RUN_ROOT_PATH + "player_project/"
const ASSET_MANIFEST_RELATIVE_PATH: String = "manifests/asset_aliases.json"
const IMPORTABLE_ASSET_TYPES: Dictionary = {
	"background": {
		"bucket": "backgrounds",
		"base_dir": "assets/images/background",
		"prefix": "bg",
		"category": "image",
	},
	"image": {
		"bucket": "images",
		"base_dir": "assets/images/illustrations",
		"prefix": "img",
		"category": "image",
	},
	"cg": {
		"bucket": "images",
		"base_dir": "assets/images/cg",
		"prefix": "cg",
		"category": "image",
	},
	"bgm": {
		"bucket": "bgm",
		"base_dir": "assets/audio/bgm",
		"prefix": "bgm",
		"category": "audio",
	},
	"sfx": {
		"bucket": "sfx",
		"base_dir": "assets/audio/sfx",
		"prefix": "sfx",
		"category": "audio",
	},
}

# 当前项目路径
var current_project_path: String = ""

# 当前打开的项目（全局状态，供所有APP访问）
var current_project: Resource = null

# 运行期固定挂载的玩家工程目录
var runtime_project_path: String = ""

# 信号：当前项目改变时发出
signal current_project_changed(project: Resource)

# 信号：项目内容被修改时发出（用于跨APP同步UI）
signal project_content_changed()

# 开发者模式默认项目名（templates 目录下的文件夹名）
const DEFAULT_PROJECT_NAME: String = "tutorial_project"

# 开发者模式开关
# 编辑器中运行 = true（默认值），打包后强制 false
var developer_mode: bool = true


func _ready() -> void:
	if not OS.has_feature("editor"):
		developer_mode = false

	if developer_mode:
		print("[StorageManager] Developer mode enabled")
		_auto_load_default_project()


## 开发者模式下自动加载默认项目
## 从 res://templates/tutorial_project/ 加载教程项目作为默认项目
func _auto_load_default_project() -> void:
	var default_path: String = RES_TEMPLATES_PATH + DEFAULT_PROJECT_NAME + "/"
	var project_file: String = default_path + "project.tres"
	
	if not ResourceLoader.exists(project_file):
		push_warning("[StorageManager] Default project not found: " + project_file)
		return
	
	var project: Resource = load_project(default_path)
	if project == null:
		push_warning("[StorageManager] Failed to load default project")
		return
	
	set_current_project(project)
	print("[StorageManager] Auto-loaded default project: " + project.project_name)


## 获取项目保存路径
## 根据developer_mode决定保存位置
## - 开发者模式: res://projects/
## - 普通模式: user://projects/
func get_save_path(project: Resource) -> String:
	if not runtime_project_path.is_empty():
		return runtime_project_path
	if developer_mode:
		# If the project is already loaded from a specific path (e.g., templates), save it back there
		if not current_project_path.is_empty() and current_project_path.begins_with("res://"):
			return current_project_path
		return RES_PROJECTS_PATH + project.project_name + "/"
	else:
		return USER_PROJECTS_PATH + project.project_name + "/"


## 创建新项目
## 返回一个新的AVGProject实例，设置项目名称
func create_project(project_name: String) -> Resource:
	var project: Resource = AVGProjectClass.new()
	project.project_name = project_name
	return project


## 运行期挂载玩家工程到 user://run/player_project/
## 如果不存在，则从默认模板初始化；模板缺失时回退到空工程
func mount_runtime_project(template_name: String = DEFAULT_PROJECT_NAME) -> Error:
	runtime_project_path = RUNTIME_PLAYER_PROJECT_PATH

	var project_file_path: String = runtime_project_path + "project.tres"
	if not ResourceLoader.exists(project_file_path):
		var init_err: Error = _initialize_runtime_project(template_name)
		if init_err != OK:
			runtime_project_path = ""
			return init_err

	var project: Resource = load_project(runtime_project_path)
	if project == null:
		runtime_project_path = ""
		return ERR_CANT_OPEN

	set_current_project(project)
	print("[StorageManager] Mounted runtime project: %s" % runtime_project_path)
	return OK


func reset_runtime_state(emit_change: bool = false) -> void:
	current_project_path = ""
	current_project = null
	runtime_project_path = ""
	if emit_change:
		current_project_changed.emit(null)


## 保存项目到文件系统
## 将项目保存为.tres资源文件
## 返回Error.OK表示成功，其他值表示失败
func save_project(project: Resource) -> Error:
	var save_path: String = get_save_path(project)
	
	# 确保目录存在
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null and not developer_mode:
		return ERR_CANT_CREATE
	
	# 创建项目目录结构
	var base_path: String = USER_PROJECTS_PATH if not developer_mode else RES_PROJECTS_PATH
	if not DirAccess.dir_exists_absolute(base_path):
		var base_err: Error = DirAccess.make_dir_recursive_absolute(base_path)
		if base_err != OK:
			return base_err
	
	if not DirAccess.dir_exists_absolute(save_path):
		var path_err: Error = DirAccess.make_dir_recursive_absolute(save_path)
		if path_err != OK:
			return path_err
	
	# 创建子目录
	var subdirs: Array[String] = ["scenes", "characters", "events", "variables", "assets", "assets/images", "assets/audio", "assets/fonts", "documents", "documents/plot", "documents/characters", "documents/scripts", "documents/guides", "manifests"]
	for subdir: String in subdirs:
		var subdir_path: String = save_path + subdir
		if not DirAccess.dir_exists_absolute(subdir_path):
			var subdir_err: Error = DirAccess.make_dir_recursive_absolute(subdir_path)
			if subdir_err != OK:
				push_warning("Failed to create subdirectory: " + subdir_path)
	
	# 保存项目文件
	var project_file_path: String = save_path + "project.tres"
	if project != null and "project_root_path" in project:
		project.set("project_root_path", save_path)
	var subresource_err: Error = _save_external_project_resources(project, save_path)
	if subresource_err != OK:
		return subresource_err
	var save_err: Error = ResourceSaver.save(project, project_file_path)
	if save_err == OK:
		current_project_path = save_path
	
	return save_err


## 加载项目
## 从指定路径加载AVGProject资源
## project_path: 项目目录路径（如 "user://projects/my_game/" 或 "res://templates/tutorial/"）
## 返回加载的AVGProject，如果加载失败返回null
func load_project(project_path: String) -> Resource:
	# 确保路径以/结尾
	if not project_path.ends_with("/"):
		project_path += "/"
	
	var project_file_path: String = project_path + "project.tres"
	
	# 检查项目文件是否存在
	if not ResourceLoader.exists(project_file_path):
		push_error("Project file not found: " + project_file_path)
		return null
	
	# 加载项目资源
	var project: Resource = ResourceLoader.load(project_file_path)
	if project == null:
		push_error("Failed to load project: " + project_file_path)
		return null

	# 更新当前项目路径
	current_project_path = project_path
	if project != null and "project_root_path" in project:
		project.set("project_root_path", project_path)

	return project


## 列出用户项目
## 扫描 user://projects/ 目录，返回所有项目目录名称
## 返回项目名称数组（不包含完整路径）
func list_user_projects() -> Array[String]:
	var projects: Array[String] = []
	
	# 打开用户项目目录
	var dir: DirAccess = DirAccess.open(USER_PROJECTS_PATH)
	if dir == null:
		# 目录不存在或无法访问，返回空数组
		return projects
	
	# 遍历目录
	dir.list_dir_begin()
	var dir_name: String = dir.get_next()
	while dir_name != "":
		# 只处理目录，跳过文件和隐藏目录
		if dir.current_is_dir() and not dir_name.begins_with("."):
			# 检查是否包含project.tres文件（验证是有效项目）
			var project_file: String = USER_PROJECTS_PATH + dir_name + "/project.tres"
			if ResourceLoader.exists(project_file):
				projects.append(dir_name)
		dir_name = dir.get_next()
	dir.list_dir_end()
	
	return projects


## 列出范例项目
## 扫描 res://templates/ 目录，返回所有范例项目目录名称
## 返回项目名称数组（不包含完整路径）
func list_template_projects() -> Array[String]:
	var templates: Array[String] = []
	print("[StorageManager] list_template_projects() called")
	print("[StorageManager] Looking in: ", RES_TEMPLATES_PATH)
	
	# 打开范例项目目录
	var dir: DirAccess = DirAccess.open(RES_TEMPLATES_PATH)
	if dir == null:
		# 目录不存在或无法访问，返回空数组
		print("[StorageManager] ERROR: Cannot open templates directory!")
		print("[StorageManager] DirAccess error: ", DirAccess.get_open_error())
		return templates
	
	print("[StorageManager] Successfully opened templates directory")
	
	# 遍历目录
	dir.list_dir_begin()
	var dir_name: String = dir.get_next()
	while dir_name != "":
		print("[StorageManager] Found item: ", dir_name, " is_dir: ", dir.current_is_dir())
		# 只处理目录，跳过文件和隐藏目录
		if dir.current_is_dir() and not dir_name.begins_with("."):
			# 检查是否包含project.tres文件（验证是有效项目）
			var project_file: String = RES_TEMPLATES_PATH + dir_name + "/project.tres"
			print("[StorageManager] Checking for: ", project_file)
			if ResourceLoader.exists(project_file):
				print("[StorageManager] Valid template found: ", dir_name)
				templates.append(dir_name)
			else:
				print("[StorageManager] No project.tres found for: ", dir_name)
		dir_name = dir.get_next()
	dir.list_dir_end()
	
	print("[StorageManager] Total templates found: ", templates.size())
	return templates


## 复制范例项目到用户目录
## 将 res://templates/{template_name}/ 复制到 user://projects/{new_name}/
## template_name: 范例项目名称（目录名）
## new_name: 新项目名称
## 返回Error.OK表示成功，其他值表示失败
func copy_template_to_user(template_name: String, new_name: String) -> Error:
	var target_path: String = USER_PROJECTS_PATH + new_name + "/"
	return _copy_template_to_path(template_name, target_path, new_name, true)


## 递归复制目录
## 将source_dir下的所有文件和子目录复制到target_dir
## 返回Error.OK表示成功
func _copy_directory_recursive(source_dir: String, target_dir: String) -> Error:
	var dir: DirAccess = DirAccess.open(source_dir)
	if dir == null:
		return ERR_CANT_OPEN
	
	# 确保目标目录存在
	if not DirAccess.dir_exists_absolute(target_dir):
		var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(target_dir)
		if mkdir_err != OK:
			return mkdir_err
	
	# 遍历源目录
	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	while item_name != "":
		# 跳过隐藏文件和目录
		if not item_name.begins_with("."):
			var source_item: String = source_dir + item_name
			var target_item: String = target_dir + item_name
			
			if dir.current_is_dir():
				# 递归复制子目录
				var subdir_err: Error = _copy_directory_recursive(source_item + "/", target_item + "/")
				if subdir_err != OK:
					dir.list_dir_end()
					return subdir_err
			else:
				# 复制文件
				var copy_err: Error = _copy_file(source_item, target_item)
				if copy_err != OK:
					dir.list_dir_end()
					return copy_err
		
		item_name = dir.get_next()
	dir.list_dir_end()
	
	return OK


## 复制单个文件
## 从source_path复制到target_path
## 支持资源文件(.tres, .tscn)和普通文件
func _copy_file(source_path: String, target_path: String) -> Error:
	# 对于资源文件，使用ResourceLoader/ResourceSaver
	if source_path.ends_with(".tres") or source_path.ends_with(".tscn"):
		if ResourceLoader.exists(source_path):
			var resource: Resource = ResourceLoader.load(source_path)
			if resource != null:
				return ResourceSaver.save(resource, target_path)
			else:
				# 资源加载失败，尝试作为普通文件复制
				return _copy_file_binary(source_path, target_path)
		else:
			return ERR_FILE_NOT_FOUND
	else:
		# 普通文件使用二进制复制
		return _copy_file_binary(source_path, target_path)


## 二进制方式复制文件
## 用于非资源文件（图片、音频等）
func _copy_file_binary(source_path: String, target_path: String) -> Error:
	# 读取源文件
	var file_read: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file_read == null:
		return FileAccess.get_open_error()
	
	var content: PackedByteArray = file_read.get_buffer(file_read.get_length())
	file_read.close()
	
	# 写入目标文件
	var file_write: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if file_write == null:
		return FileAccess.get_open_error()
	
	file_write.store_buffer(content)
	file_write.close()
	
	return OK


## 递归删除目录
## 用于清理失败的复制操作
func _remove_directory_recursive(dir_path: String) -> Error:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return ERR_CANT_OPEN
	
	# 遍历并删除所有内容
	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	while item_name != "":
		if not item_name.begins_with("."):
			var item_path: String = dir_path + item_name
			if dir.current_is_dir():
				# 递归删除子目录
				_remove_directory_recursive(item_path + "/")
				DirAccess.remove_absolute(item_path)
			else:
				# 删除文件
				DirAccess.remove_absolute(item_path)
		item_name = dir.get_next()
	dir.list_dir_end()
	
	# 删除目录本身
	return DirAccess.remove_absolute(dir_path)


func _initialize_runtime_project(template_name: String) -> Error:
	if not DirAccess.dir_exists_absolute(RUNTIME_PLAYER_PROJECT_PATH):
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(RUNTIME_PLAYER_PROJECT_PATH)
		if dir_err != OK:
			return dir_err

	var normalized_template_name: String = template_name.strip_edges()
	if normalized_template_name.is_empty():
		normalized_template_name = DEFAULT_PROJECT_NAME

	var template_project_file: String = RES_TEMPLATES_PATH + normalized_template_name + "/project.tres"
	if ResourceLoader.exists(template_project_file):
		var copy_err: Error = _copy_template_to_path(normalized_template_name, RUNTIME_PLAYER_PROJECT_PATH)
		if copy_err == OK:
			return OK
		push_warning("[StorageManager] Failed to seed runtime project from template, fallback to blank project")

	current_project_path = RUNTIME_PLAYER_PROJECT_PATH
	var blank_project: Resource = create_project("player_project")
	return save_project(blank_project)


func _copy_template_to_path(template_name: String, target_path: String, project_name_override: String = "", fail_if_target_exists: bool = false) -> Error:
	var source_path: String = RES_TEMPLATES_PATH + template_name + "/"

	# 验证范例项目存在
	if not DirAccess.dir_exists_absolute(source_path):
		push_error("Template not found: " + source_path)
		return ERR_FILE_NOT_FOUND

	# 验证范例项目包含project.tres
	var source_project_file: String = source_path + "project.tres"
	if not ResourceLoader.exists(source_project_file):
		push_error("Template project.tres not found: " + source_project_file)
		return ERR_FILE_NOT_FOUND

	# 检查目标项目是否已存在
	if fail_if_target_exists and DirAccess.dir_exists_absolute(target_path):
		push_error("Target project already exists: " + target_path)
		return ERR_ALREADY_EXISTS

	if not DirAccess.dir_exists_absolute(target_path):
		var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(target_path)
		if mkdir_err != OK:
			push_error("Failed to create target directory: " + target_path)
			return mkdir_err

	# 递归复制所有文件和目录
	var copy_err: Error = _copy_directory_recursive(source_path, target_path)
	if copy_err != OK:
		push_error("Failed to copy template files")
		if fail_if_target_exists:
			_remove_directory_recursive(target_path)
		return copy_err

	var override_name: String = project_name_override.strip_edges()
	if override_name.is_empty():
		return OK

	var target_project_file: String = target_path + "project.tres"
	var project: Resource = ResourceLoader.load(target_project_file)
	if project != null:
		project.project_name = override_name
		if "project_root_path" in project:
			project.set("project_root_path", target_path)
		var save_err: Error = ResourceSaver.save(project, target_project_file)
		if save_err != OK:
			push_warning("Failed to update project name in copied project")
	return OK


## 设置当前项目
## 供FileManager等调用，会发出信号通知所有监听者
func set_current_project(project: Resource) -> void:
	print("[StorageManager] set_current_project: %s" % (project.project_name if project else "null"))
	current_project = project
	if current_project != null and "project_root_path" in current_project and not current_project_path.is_empty():
		current_project.set("project_root_path", current_project_path)
	current_project_changed.emit(project)


## 获取当前项目
func get_current_project() -> Resource:
	return current_project


## 通知所有APP项目内容已修改（UI需要刷新）
func notify_content_changed() -> void:
	project_content_changed.emit()


# =============================================================================
# 资源文件管理 — 操作当前项目的 assets/ 目录
# =============================================================================

## 图片扩展名
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg", "bmp"]
## 音频扩展名
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]
## 字体扩展名
const FONT_EXTENSIONS: Array[String] = ["ttf", "otf"]
## 所有支持的扩展名
const ALL_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg", "bmp", "ogg", "mp3", "wav", "ttf", "otf"]


## 获取当前项目的 assets 根路径（绝对路径）
func get_assets_path() -> String:
	if current_project_path.is_empty():
		return ""
	return current_project_path + "assets/"


## 将相对路径转为绝对路径
func resolve_asset_path(relative_path: String) -> String:
	if current_project_path.is_empty():
		return ""
	return current_project_path + relative_path


## 从绝对路径转为项目内相对路径
func to_relative_path(absolute_path: String) -> String:
	if current_project_path.is_empty():
		return absolute_path
	if absolute_path.begins_with(current_project_path):
		return absolute_path.substr(current_project_path.length())
	return absolute_path


## 列出指定目录下的文件和子目录
## relative_dir: 相对于项目根的路径，如 "assets/images/"
## 返回 {"dirs": Array[String], "files": Array[Dictionary]}
## 每个 file: {"name": String, "path": String, "extension": String}
func list_directory(relative_dir: String) -> Dictionary:
	var result: Dictionary = {"dirs": [], "files": []}
	var abs_path: String = resolve_asset_path("").get_base_dir() + "/" + relative_dir if not relative_dir.is_empty() else get_assets_path()
	
	# 修正：直接拼接
	abs_path = current_project_path + relative_dir
	
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
				if ext in ALL_EXTENSIONS:
					result["files"].append({
						"name": item_name,
						"path": relative_dir + item_name,
						"extension": ext,
					})
		item_name = dir.get_next()
	dir.list_dir_end()
	
	# 排序
	result["dirs"].sort()
	result["files"].sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	return result


## 在 assets 下创建文件夹
## relative_dir: 相对于项目根的路径，如 "assets/images/characters/"
func make_directory(relative_dir: String) -> Error:
	var abs_path: String = current_project_path + relative_dir
	return DirAccess.make_dir_recursive_absolute(abs_path)


## 删除资源文件
## relative_path: 相对于项目根的路径
func delete_asset(relative_path: String) -> Error:
	var abs_path: String = current_project_path + relative_path
	return DirAccess.remove_absolute(abs_path)


## 删除空文件夹
func delete_directory(relative_dir: String) -> Error:
	var abs_path: String = current_project_path + relative_dir
	# 检查是否为空
	var dir: DirAccess = DirAccess.open(abs_path)
	if dir == null:
		return ERR_CANT_OPEN
	dir.list_dir_begin()
	var item: String = dir.get_next()
	while item != "":
		if not item.begins_with("."):
			dir.list_dir_end()
			return ERR_ALREADY_IN_USE # 非空目录
		item = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(abs_path)


## 导入外部文件到项目 assets
## source_path: 系统绝对路径
## target_relative_path: 相对于项目根的目标路径，如 "assets/images/bg.png"
func import_asset(source_path: String, target_relative_path: String) -> Error:
	var abs_target: String = current_project_path + target_relative_path
	# 确保目标目录存在
	var target_dir: String = abs_target.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var err: Error = DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			return err
	return _copy_file_binary(source_path, abs_target)


## 从项目路径加载图片为 Texture2D
## relative_path: 相对于项目根的路径
## res:// 路径使用 ResourceLoader（支持 .import 导入的资源）
## user:// 路径使用 Image.load_from_file()
func import_project_asset(source_path: String, asset_type: String, alias: String = "", target_subdir: String = "", overwrite: bool = false) -> Dictionary:
	if current_project_path.is_empty():
		return {"success": false, "error": "未打开项目"}

	var normalized_type: String = asset_type.strip_edges().to_lower()
	if not IMPORTABLE_ASSET_TYPES.has(normalized_type):
		return {
			"success": false,
			"error": "不支持的 asset_type: %s" % asset_type,
			"supported_types": IMPORTABLE_ASSET_TYPES.keys(),
		}

	var normalized_source_path: String = source_path.strip_edges()
	if normalized_source_path.is_empty():
		return {"success": false, "error": "source_path 不能为空"}

	var source_file_name: String = normalized_source_path.get_file()
	if source_file_name.is_empty():
		return {"success": false, "error": "无法从 source_path 推断文件名"}

	var ext: String = source_file_name.get_extension().to_lower()
	var detected_category: String = get_file_category(ext)
	if detected_category == "unknown":
		return {"success": false, "error": "不支持的文件扩展名: %s" % ext}

	var config: Dictionary = IMPORTABLE_ASSET_TYPES[normalized_type]
	var expected_category: String = str(config.get("category", "")).strip_edges()
	if expected_category != detected_category:
		return {
			"success": false,
			"error": "asset_type=%s 与文件扩展名 .%s 不匹配" % [normalized_type, ext],
		}

	var normalized_subdir: String = _normalize_asset_subdir(target_subdir)
	var base_dir: String = str(config.get("base_dir", "")).strip_edges()
	var target_dir_parts: Array[String] = [base_dir]
	if not normalized_subdir.is_empty():
		target_dir_parts.append(normalized_subdir)
	var target_relative_dir: String = "/".join(target_dir_parts)
	var target_relative_path: String = target_relative_dir + "/" + source_file_name
	var abs_target_path: String = current_project_path + target_relative_path
	if FileAccess.file_exists(abs_target_path) and not overwrite:
		return {
			"success": false,
			"error": "目标文件已存在: %s" % target_relative_path,
		}

	var bucket_name: String = str(config.get("bucket", "")).strip_edges()
	var alias_prefix: String = str(config.get("prefix", "")).strip_edges()
	var manifest_prepare: Dictionary = _prepare_asset_manifest_entry(bucket_name, alias, target_relative_path, alias_prefix, overwrite)
	if not bool(manifest_prepare.get("success", false)):
		return manifest_prepare

	var import_err: Error = import_asset(normalized_source_path, target_relative_path)
	if import_err != OK:
		return {
			"success": false,
			"error": "资源导入失败",
			"error_code": import_err,
		}

	var save_manifest_err: Error = _save_asset_manifest_to_disk(manifest_prepare.get("manifest", {}))
	if save_manifest_err != OK:
		DirAccess.remove_absolute(abs_target_path)
		return {
			"success": false,
			"error": "写入 asset_aliases.json 失败",
			"error_code": save_manifest_err,
		}

	AVGAssetManifestClass.clear_cache()
	notify_content_changed()

	return {
		"success": true,
		"asset_type": normalized_type,
		"bucket": bucket_name,
		"alias": str(manifest_prepare.get("alias", "")).strip_edges(),
		"relative_path": target_relative_path,
		"absolute_path": abs_target_path,
	}


func load_texture_from_path(relative_path: String, project: Resource = null, project_root_override: String = "") -> Texture2D:
	if relative_path.is_empty():
		return null
	var project_root: String = _resolve_project_root(project, project_root_override)
	if project_root.is_empty() and not relative_path.begins_with("res://") and not relative_path.begins_with("user://"):
		return null
	var abs_path: String = _resolve_texture_path(relative_path, project_root)
	# res:// 路径：使用 ResourceLoader（Godot 已导入的资源）
	if abs_path.begins_with("res://"):
		if ResourceLoader.exists(abs_path):
			var res = ResourceLoader.load(abs_path)
			if res is Texture2D:
				return res
		push_warning("StorageManager: Failed to load texture from res://: %s" % abs_path)
		return null
	# user:// 路径：使用 Image.load_from_file()
	var image: Image = Image.new()
	var err: Error = image.load(ProjectSettings.globalize_path(abs_path))
	if err != OK:
		push_warning("StorageManager: Failed to load texture: %s" % abs_path)
		return null
	return ImageTexture.create_from_image(image)


## 从 user:// 路径加载音频
func load_audio_from_path(relative_path: String, project: Resource = null, project_root_override: String = "") -> AudioStream:
	if relative_path.is_empty():
		return null
	var project_root: String = _resolve_project_root(project, project_root_override)
	if project_root.is_empty() and not relative_path.begins_with("res://") and not relative_path.begins_with("user://"):
		return null
	var abs_path: String = _resolve_audio_path(relative_path, project_root)
	var ext: String = abs_path.get_extension().to_lower()
	if abs_path.begins_with("res://"):
		if not ResourceLoader.exists(abs_path):
			push_warning("StorageManager: Failed to load audio from res://: %s" % abs_path)
			return null
		var resource: Resource = ResourceLoader.load(abs_path)
		if resource is AudioStream:
			return resource
		return null
	
	# 读取文件数据
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		push_warning("StorageManager: Failed to open audio: %s" % abs_path)
		return null
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	
	match ext:
		"ogg":
			var stream: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_buffer(data)
			return stream
		"mp3":
			var stream: AudioStreamMP3 = AudioStreamMP3.new()
			stream.data = data
			return stream
		"wav":
			# WAV 需要更复杂的解析，暂时返回 null
			push_warning("StorageManager: WAV loading not fully supported yet")
			return null
		_:
			return null


## 获取文件类型分类
func get_file_category(extension: String) -> String:
	var ext: String = extension.to_lower()
	if ext in IMAGE_EXTENSIONS:
		return "image"
	elif ext in AUDIO_EXTENSIONS:
		return "audio"
	elif ext in FONT_EXTENSIONS:
		return "font"
	return "unknown"


func get_asset_manifest(project: Resource = null, project_root_override: String = "") -> Dictionary:
	var project_root: String = _resolve_project_root(project, project_root_override)
	return AVGAssetManifestClass.load_manifest(project_root)


func clear_asset_manifest_cache() -> void:
	AVGAssetManifestClass.clear_cache()


func build_asset_prompt(project: Resource = null, project_root_override: String = "") -> String:
	var project_root: String = _resolve_project_root(project, project_root_override)
	var target_project: Resource = project if project != null else current_project
	return AVGAssetManifestClass.build_llm_prompt_block(project_root, target_project)


func _resolve_project_root(project: Resource = null, project_root_override: String = "") -> String:
	if not project_root_override.is_empty():
		return project_root_override if project_root_override.ends_with("/") else project_root_override + "/"
	if project != null and "project_root_path" in project:
		var project_root: String = str(project.get("project_root_path")).strip_edges()
		if not project_root.is_empty():
			return project_root if project_root.ends_with("/") else project_root + "/"
	return current_project_path


func _resolve_texture_path(asset_ref: String, project_root: String) -> String:
	var resolved: String = AVGAssetManifestClass.resolve_texture_path(asset_ref, project_root)
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		return resolved
	return project_root + resolved


func _resolve_audio_path(asset_ref: String, project_root: String) -> String:
	var resolved: String = AVGAssetManifestClass.resolve_audio_path(asset_ref, project_root)
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		return resolved
	return project_root + resolved


func _prepare_asset_manifest_entry(bucket_name: String, requested_alias: String, relative_path: String, alias_prefix: String, overwrite: bool) -> Dictionary:
	AVGAssetManifestClass.clear_cache()
	var manifest: Dictionary = get_asset_manifest(current_project, current_project_path)
	var bucket_variant: Variant = manifest.get(bucket_name, {})
	var bucket: Dictionary = bucket_variant.duplicate(true) if bucket_variant is Dictionary else {}
	var alias_explicitly_requested: bool = not requested_alias.strip_edges().is_empty()
	var final_alias: String = ""

	if alias_explicitly_requested:
		final_alias = _normalize_asset_alias(requested_alias, alias_prefix)
		if final_alias.is_empty():
			return {"success": false, "error": "alias 为空或格式非法"}
		if bucket.has(final_alias):
			var existing_path: String = str(bucket.get(final_alias, "")).strip_edges()
			if existing_path != relative_path and not overwrite:
				return {
					"success": false,
					"error": "alias 已存在且指向其他资源: %s -> %s" % [final_alias, existing_path],
				}
	else:
		var base_name: String = relative_path.get_file().get_basename()
		final_alias = _generate_unique_asset_alias(base_name, alias_prefix, bucket, relative_path)

	bucket[final_alias] = relative_path
	manifest[bucket_name] = bucket
	return {"success": true, "alias": final_alias, "manifest": manifest}


func _save_asset_manifest_to_disk(manifest: Dictionary) -> Error:
	var manifest_dir: String = current_project_path + "manifests"
	if not DirAccess.dir_exists_absolute(manifest_dir):
		var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(manifest_dir)
		if mkdir_err != OK:
			return mkdir_err

	var manifest_path: String = current_project_path + ASSET_MANIFEST_RELATIVE_PATH
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	return OK


func _generate_unique_asset_alias(base_name: String, alias_prefix: String, bucket: Dictionary, target_relative_path: String) -> String:
	var normalized_base: String = _normalize_asset_alias(base_name, alias_prefix)
	if normalized_base.is_empty():
		normalized_base = alias_prefix

	var candidate: String = normalized_base
	var suffix: int = 2
	while bucket.has(candidate) and str(bucket.get(candidate, "")).strip_edges() != target_relative_path:
		candidate = "%s_%d" % [normalized_base, suffix]
		suffix += 1
	return candidate


func _normalize_asset_alias(raw_alias: String, alias_prefix: String) -> String:
	var normalized: String = _sanitize_ascii_identifier(raw_alias)
	var trimmed_prefix: String = alias_prefix.strip_edges().to_lower()
	if normalized.is_empty():
		return trimmed_prefix
	if not trimmed_prefix.is_empty() and not normalized.begins_with(trimmed_prefix + "_") and normalized != trimmed_prefix:
		normalized = "%s_%s" % [trimmed_prefix, normalized]
	if _starts_with_digit(normalized):
		normalized = "%s_%s" % [trimmed_prefix if not trimmed_prefix.is_empty() else "asset", normalized]
	return normalized


func _normalize_asset_subdir(raw_subdir: String) -> String:
	var normalized_input: String = raw_subdir.strip_edges().replace("\\", "/")
	if normalized_input.is_empty():
		return ""
	var parts: PackedStringArray = normalized_input.split("/", false)
	var cleaned_parts: Array[String] = []
	for part in parts:
		var cleaned_part: String = _sanitize_ascii_identifier(part)
		if cleaned_part.is_empty():
			continue
		cleaned_parts.append(cleaned_part)
	return "/".join(cleaned_parts)


func _sanitize_ascii_identifier(raw_value: String) -> String:
	var lower_value: String = raw_value.strip_edges().to_lower()
	var result: String = ""
	var previous_was_separator: bool = false
	for i in lower_value.length():
		var codepoint: int = lower_value.unicode_at(i)
		var is_letter: bool = codepoint >= 97 and codepoint <= 122
		var is_digit: bool = codepoint >= 48 and codepoint <= 57
		var is_underscore: bool = codepoint == 95
		var is_separator: bool = codepoint == 45 or codepoint == 32 or codepoint == 46 or codepoint == 47 or codepoint == 92
		if is_letter or is_digit:
			result += char(codepoint)
			previous_was_separator = false
		elif is_underscore or is_separator:
			if not result.is_empty() and not previous_was_separator:
				result += "_"
				previous_was_separator = true
	return result.strip_edges().trim_suffix("_")


func _starts_with_digit(value: String) -> bool:
	if value.is_empty():
		return false
	var first_codepoint: int = value.unicode_at(0)
	return first_codepoint >= 48 and first_codepoint <= 57


func _save_external_project_resources(project: Resource, project_root: String) -> Error:
	if project == null:
		return OK
	var resources: Array[Resource] = []
	_collect_project_resources(project, resources)
	var visited: Dictionary = {}
	for resource in resources:
		if resource == null:
			continue
		var resource_path: String = str(resource.resource_path).strip_edges()
		if resource_path.is_empty() or resource_path.contains("::") or not resource_path.begins_with(project_root):
			continue
		if visited.has(resource_path):
			continue
		visited[resource_path] = true
		var save_err: Error = ResourceSaver.save(resource, resource_path)
		if save_err != OK:
			push_warning("[StorageManager] Failed to save subresource: %s" % resource_path)
			return save_err
	return OK


func _collect_project_resources(project: Resource, out_resources: Array[Resource]) -> void:
	if project == null:
		return
	if "dialog_settings" in project and project.dialog_settings != null:
		out_resources.append(project.dialog_settings)
	if "title_config" in project and project.title_config != null:
		out_resources.append(project.title_config)
	if "game_ui_config" in project and project.game_ui_config != null:
		out_resources.append(project.game_ui_config)
	for scene in project.scenes:
		if scene is Resource:
			out_resources.append(scene)
	for character in project.characters:
		if character is Resource:
			out_resources.append(character)
	for variable in project.variables:
		if variable is Resource:
			out_resources.append(variable)
	for event in project.events:
		if event is Resource:
			out_resources.append(event)
	for shared_node in project.shared_nodes:
		if shared_node is Resource:
			out_resources.append(shared_node)
	for config in project.screen_configs.values():
		if config is Resource:
			out_resources.append(config)
