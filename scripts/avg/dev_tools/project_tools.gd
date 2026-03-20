class_name AVGDevProjectTools extends RefCounted
## AVG Dev AI — 项目 + 流程控制工具集
## 提供 project_info / project_save / preview_scene / finish


# =============================================================================
# 工具注册
# =============================================================================

static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("project_info", "获取当前项目基础信息（名称、分辨率、场景数、角色数、变量数等）", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_info(args))

	ai_service.register_tool("project_save", "保存当前项目并通知 UI 刷新", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_save(args))

	ai_service.register_tool("import_project_asset", "导入外部资源到当前项目，并自动写入 asset_aliases.json。适用于 LLM 将图片/BGM/SFX 等素材纳入玩家工程。", {
		"type": "object",
		"properties": {
			"source_path": {"type": "string", "description": "外部文件路径。可以是系统绝对路径，也可以是 res:// 或 user:// 路径"},
			"asset_type": {"type": "string", "enum": ["background", "image", "cg", "bgm", "sfx"], "description": "资源类型，决定导入目录和 alias bucket"},
			"alias": {"type": "string", "description": "可选。希望写入的 alias；若省略则自动生成"},
			"target_subdir": {"type": "string", "description": "可选。导入到默认目录下的子目录，例如 generated/day3"},
			"overwrite": {"type": "boolean", "description": "若为 true，则允许覆盖同名目标文件或同名 alias"},
		},
		"required": ["source_path", "asset_type"]
	}, func(args: Dictionary) -> Variant: return _import_project_asset(args))

	ai_service.register_tool("preview_scene", "触发游戏内预览模式，让玩家试玩指定场景", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "要预览的场景 ID（如 scene_001）"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _preview_scene(args))

	ai_service.register_tool("finish", "结束当前任务，将工作摘要返回给主 Agent。Sub-Agent 完成工作后必须调用此工具", {
		"type": "object",
		"properties": {
			"summary": {"type": "string", "description": "工作摘要：描述做了什么、创建/修改了哪些资源"}
		},
		"required": ["summary"]
	}, func(args: Dictionary) -> Variant: return _finish(args))


## Sub-agent registration: project_info + project_save + finish (no preview)
static func register_save_only(ai_service: Node) -> void:
	ai_service.register_tool("project_info", "Get project overview (name, resolution, counts)", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_info(args))

	ai_service.register_tool("project_save", "Save project and notify UI", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_save(args))

	ai_service.register_tool("import_project_asset", "Import an external asset into the current project and auto-update asset_aliases.json.", {
		"type": "object",
		"properties": {
			"source_path": {"type": "string", "description": "Absolute path, res:// path, or user:// path to the source file"},
			"asset_type": {"type": "string", "enum": ["background", "image", "cg", "bgm", "sfx"], "description": "Asset type that controls target directory and manifest bucket"},
			"alias": {"type": "string", "description": "Optional requested alias; auto-generated if omitted"},
			"target_subdir": {"type": "string", "description": "Optional subdirectory inside the default import folder"},
			"overwrite": {"type": "boolean", "description": "Whether to allow overwriting an existing target file or alias"},
		},
		"required": ["source_path", "asset_type"]
	}, func(args: Dictionary) -> Variant: return _import_project_asset(args))

	ai_service.register_tool("finish", "End your task and return summary to parent agent. You MUST call this when done.", {
		"type": "object",
		"properties": {
			"summary": {"type": "string", "description": "Work summary: what was created/modified"}
		},
		"required": ["summary"]
	}, func(args: Dictionary) -> Variant: return _finish(args))

	ai_service.register_tool("list_assets", "列出当前项目的可用资源文件与 alias（背景图、非角色图片、CG、BGM、SFX、角色表情/服装信息）。在编写 DSL 脚本前必须先调用此工具查询可用资源，禁止编造不存在的资源名！", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["all", "backgrounds", "images", "cg", "bgm", "sfx", "characters"], "description": "要查询的资源类别，默认 all"}
		},
	}, func(args: Dictionary) -> Variant: return _list_assets(args))


## Main agent registration: preview_scene only (sub-agents handle the rest)
static func register_preview_and_finish(ai_service: Node) -> void:
	ai_service.register_tool("preview_scene", "Let the player playtest a specific scene", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "Scene ID to preview"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _preview_scene(args))

	ai_service.register_tool("project_info", "Get project overview", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_info(args))

	ai_service.register_tool("import_project_asset", "Import an external asset into the current project and auto-update asset_aliases.json.", {
		"type": "object",
		"properties": {
			"source_path": {"type": "string", "description": "Absolute path, res:// path, or user:// path to the source file"},
			"asset_type": {"type": "string", "enum": ["background", "image", "cg", "bgm", "sfx"], "description": "Asset type that controls target directory and manifest bucket"},
			"alias": {"type": "string", "description": "Optional requested alias; auto-generated if omitted"},
			"target_subdir": {"type": "string", "description": "Optional subdirectory inside the default import folder"},
			"overwrite": {"type": "boolean", "description": "Whether to allow overwriting an existing target file or alias"},
		},
		"required": ["source_path", "asset_type"]
	}, func(args: Dictionary) -> Variant: return _import_project_asset(args))


# =============================================================================
# project_info
# =============================================================================

static func _project_info(_args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var info: Dictionary = {
		"success": true,
		"data": {
			"project_name": project.project_name if "project_name" in project else "",
			"resolution": {
				"width": project.resolution.x if "resolution" in project else 0,
				"height": project.resolution.y if "resolution" in project else 0,
			},
			"scene_count": project.scenes.size() if "scenes" in project else 0,
			"character_count": project.characters.size() if "characters" in project else 0,
			"variable_count": project.variables.size() if "variables" in project else 0,
			"event_count": project.events.size() if "events" in project else 0,
		}
	}

	# 列出所有场景名（概览）
	var scene_list: Array = []
	if "scenes" in project:
		for s in project.scenes:
			if s == null:
				continue
			scene_list.append({
				"id": s.scene_id if "scene_id" in s else "",
				"name": s.scene_name if "scene_name" in s else "",
			})
	info.data["scenes"] = scene_list

	return info


# =============================================================================
# project_save
# =============================================================================

static func _project_save(_args: Dictionary) -> Dictionary:
	var sm: Node = AVGDevDBTools.get_autoload("StorageManager")
	if sm == null:
		return {"success": false, "error": "StorageManager 未找到"}

	if sm.current_project == null:
		return {"success": false, "error": "未打开项目"}

	sm.save_project(sm.current_project)
	sm.project_content_changed.emit()
	return {"success": true, "message": "项目已保存"}


# =============================================================================
# import_project_asset
# =============================================================================

static func _import_project_asset(args: Dictionary) -> Dictionary:
	var sm: Node = AVGDevDBTools.get_autoload("StorageManager")
	if sm == null:
		return {"success": false, "error": "StorageManager 未找到"}

	if not sm.has_method("import_project_asset"):
		return {"success": false, "error": "当前 StorageManager 不支持资源导入"}

	var source_path: String = str(args.get("source_path", "")).strip_edges()
	var asset_type: String = str(args.get("asset_type", "")).strip_edges()
	var alias: String = str(args.get("alias", "")).strip_edges()
	var target_subdir: String = str(args.get("target_subdir", "")).strip_edges()
	var overwrite: bool = bool(args.get("overwrite", false))

	var result: Dictionary = sm.import_project_asset(source_path, asset_type, alias, target_subdir, overwrite)
	if not bool(result.get("success", false)):
		return result

	result["message"] = "资源已导入，可优先使用 alias=%s" % str(result.get("alias", ""))
	return result


# =============================================================================
# preview_scene
# =============================================================================

static func _preview_scene(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var scene_id: String = args.get("scene_id", "")

	# 验证场景存在
	var found: bool = false
	if "scenes" in project:
		for s in project.scenes:
			if s != null and "scene_id" in s and s.scene_id == scene_id:
				found = true
				break

	if not found:
		return {"success": false, "error": "场景 '%s' 未找到" % scene_id}

	# TODO: 预览信号发出机制待实现
	return {"success": true, "message": "预览请求已发送: " + scene_id}


# =============================================================================
# finish
# =============================================================================

static func _finish(args: Dictionary) -> Dictionary:
	var summary: String = args.get("summary", "")
	# finish 工具的返回值会被 ChatAgent 的 _extract_result_tag 处理
	# 只需要在 content 中输出 <result> 标签即可
	return {"success": true, "summary": summary}


# =============================================================================
# list_assets — 列出项目可用的资源文件
# =============================================================================

static func _list_assets(args: Dictionary) -> Dictionary:
	var sm: Node = AVGDevDBTools.get_autoload("StorageManager")
	if sm == null:
		return {"success": false, "error": "StorageManager 未找到"}
	
	var base_path: String = sm.current_project_path
	if base_path.is_empty():
		return {"success": false, "error": "未打开项目"}
	
	var project: Resource = AVGDevDBTools.get_project()
	var category: String = args.get("category", "all")
	var result: Dictionary = {"success": true, "data": {}}
	var manifest: Dictionary = {}
	if sm.has_method("get_asset_manifest"):
		manifest = sm.get_asset_manifest(project, base_path)
	result.data["alias_usage"] = "如果返回了 background_aliases/image_aliases/cg_aliases/bgm_aliases/sfx_aliases，优先在 DSL 中使用 alias；如果没有 alias，再使用原始资源名。禁止写 res:// 完整路径。"
	
	# 背景图、BGM、SFX：扫描项目文件夹
	# current_project_path 在开发者模式下指向 res://templates/...（可扫描）
	# 在导出后指向 user://projects/...（同样可扫描）
	if category == "all" or category == "backgrounds":
		result.data["backgrounds"] = _scan_files(base_path + "assets/images/background/")
		result.data["background_aliases"] = _extract_aliases(manifest, "backgrounds")

	if category == "all" or category == "images":
		result.data["images"] = _scan_visual_files(base_path + "assets/images/", false)
		result.data["image_aliases"] = _extract_filtered_aliases(manifest, "images", false)

	if category == "all" or category == "cg":
		result.data["cg"] = _scan_visual_files(base_path + "assets/images/", true)
		result.data["cg_aliases"] = _extract_filtered_aliases(manifest, "images", true)
	
	if category == "all" or category == "bgm":
		result.data["bgm"] = _scan_files(base_path + "assets/audio/bgm/")
		result.data["bgm_aliases"] = _extract_aliases(manifest, "bgm")
	
	if category == "all" or category == "sfx":
		result.data["sfx"] = _scan_files(base_path + "assets/audio/sfx/")
		result.data["sfx_aliases"] = _extract_aliases(manifest, "sfx")
	
	# 角色表情：从 AVGCharacter.sprites 字典读取（不扫描文件系统）
	if category == "all" or category == "characters":
		var char_data: Dictionary = {}
		if project != null and "characters" in project:
			for c in project.characters:
				if c == null:
					continue
				var cid: String = c.character_id if "character_id" in c else ""
				var cname: String = c.character_name if "character_name" in c else ""
				var expressions: Array = []
				var outfits: Array = []
				if "sprites" in c and c.sprites is Dictionary:
					for expr_name in c.sprites.keys():
						var normalized_expr: String = str(expr_name)
						if "__" in normalized_expr:
							var parts: PackedStringArray = normalized_expr.split("__", false, 1)
							if parts.size() == 2:
								normalized_expr = str(parts[1])
						if not expressions.has(normalized_expr):
							expressions.append(normalized_expr)
				if "available_outfits" in c and c.available_outfits is Array:
					for outfit_name in c.available_outfits:
						var normalized_outfit: String = str(outfit_name)
						if not outfits.has(normalized_outfit):
							outfits.append(normalized_outfit)
				if "default_outfit" in c:
					var default_outfit: String = str(c.default_outfit)
					if not default_outfit.is_empty() and not outfits.has(default_outfit):
						outfits.append(default_outfit)
				char_data[cid] = {"name": cname, "expressions": expressions, "outfits": outfits}
		result.data["characters"] = char_data
	
	return result


## 扫描目录，返回文件名列表（去掉 .import 后缀）
static func _scan_files(dir_path: String) -> Array:
	var files: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			files.append(file_name.get_basename()) # 去掉扩展名，只留名字
		file_name = dir.get_next()
	dir.list_dir_end()
	return files


static func _extract_aliases(manifest: Dictionary, bucket_name: String) -> Array:
	var aliases: Array = []
	var bucket: Dictionary = manifest.get(bucket_name, {})
	for key in bucket.keys():
		aliases.append(str(key))
	aliases.sort()
	return aliases


static func _extract_filtered_aliases(manifest: Dictionary, bucket_name: String, cg_only: bool) -> Array:
	var aliases: Array = []
	var bucket: Dictionary = manifest.get(bucket_name, {})
	for key in bucket.keys():
		var alias_name: String = str(key).strip_edges()
		var value: String = str(bucket.get(key, "")).strip_edges().to_lower()
		var is_cg_alias: bool = _looks_like_cg(alias_name) or "/cg/" in value or "/cgs/" in value
		if is_cg_alias != cg_only:
			continue
		aliases.append(alias_name)
	aliases.sort()
	return aliases


static func _scan_visual_files(root_dir_path: String, cg_only: bool) -> Array:
	var files: Array = []
	var seen: Dictionary = {}
	_scan_visual_dir_recursive(root_dir_path, "", cg_only, seen, files)
	files.sort()
	return files


static func _scan_visual_dir_recursive(abs_dir: String, relative_dir: String, cg_only: bool, seen: Dictionary, out_files: Array) -> void:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var child_name: String = dir.get_next()
	while child_name != "":
		if child_name == "." or child_name == ".." or child_name.begins_with("."):
			child_name = dir.get_next()
			continue
		var child_relative: String = child_name if relative_dir.is_empty() else relative_dir + "/" + child_name
		if dir.current_is_dir():
			if _should_skip_visual_dir(child_relative, cg_only):
				child_name = dir.get_next()
				continue
			_scan_visual_dir_recursive(abs_dir + "/" + child_name, child_relative, cg_only, seen, out_files)
		else:
			if child_name.ends_with(".import") or child_name.begins_with("."):
				child_name = dir.get_next()
				continue
			var base_name: String = child_name.get_basename()
			var belongs_to_cg: bool = _looks_like_cg(child_relative)
			if belongs_to_cg != cg_only:
				child_name = dir.get_next()
				continue
			if seen.has(base_name):
				child_name = dir.get_next()
				continue
			seen[base_name] = true
			out_files.append(base_name)
		child_name = dir.get_next()
	dir.list_dir_end()


static func _should_skip_visual_dir(relative_dir: String, cg_only: bool) -> bool:
	var normalized: String = relative_dir.to_lower()
	if normalized.begins_with("background") or normalized.begins_with("character"):
		return true
	var is_cg_dir: bool = normalized == "cg" or normalized.begins_with("cg/") or normalized == "cgs" or normalized.begins_with("cgs/")
	if cg_only:
		return not is_cg_dir
	return is_cg_dir


static func _looks_like_cg(path_or_name: String) -> bool:
	var normalized: String = path_or_name.to_lower()
	return normalized == "cg" or normalized.begins_with("cg_") or "/cg/" in normalized or normalized == "cgs" or "/cgs/" in normalized
