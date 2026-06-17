class_name AVGDevProjectTools extends RefCounted
## AVG Dev AI — 项目 + 流程控制工具集
## 提供 project_info / project_save / preview_scene / finish

const StoryReachabilityAnalyzerClass = preload("res://scripts/avg/dev_tools/story_reachability_analyzer.gd")
const AVGTitleConfigClass = preload("res://scripts/avg/resources/avg_title_config.gd")


# =============================================================================
# 工具注册
# =============================================================================

static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("project_info", "获取当前项目基础信息（名称、分辨率、场景数、角色数、变量数等）", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_info(args), {
		"fields": ["success", "data.project_name", "data.resolution", "data.scene_count", "data.character_count", "data.variable_count", "data.event_count", "data.initial_scene_id", "data.initial_scene_name", "error"]
	})

	ai_service.register_tool("project_save", "保存当前项目并通知 UI 刷新", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_save(args), {
		"fields": ["success", "error"]
	})

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
	}, func(args: Dictionary) -> Variant: return _import_project_asset(args), {
		"fields": ["success", "alias", "asset_type", "target_path", "message", "error"]
	})

	ai_service.register_tool("preview_scene", "触发游戏内预览模式，让玩家试玩指定场景", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "要预览的场景 ID（如 scene_001）"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _preview_scene(args), {
		"fields": ["success", "message", "error"]
	})

	_register_initial_scene_tool(ai_service)
	_register_scene_analysis_tools(ai_service)

	ai_service.register_tool("finish", "结束当前任务，将工作摘要返回给主 Agent。Sub-Agent 完成工作后必须调用此工具", {
		"type": "object",
		"properties": {
			"summary": {"type": "string", "description": "工作摘要：描述做了什么、创建/修改了哪些资源"}
		},
		"required": ["summary"]
	}, func(args: Dictionary) -> Variant: return _finish(args), {
		"fields": ["success", "summary", "error"]
	})


## Sub-agent registration: project_info + project_save + finish (no preview)
static func register_save_only(ai_service: Node, include_project_info: bool = true) -> void:
	if include_project_info:
		ai_service.register_tool("project_info", "Get project overview (name, resolution, counts)", {
			"type": "object",
			"properties": {},
		}, func(args: Dictionary) -> Variant: return _project_info(args), {
			"fields": ["success", "data.project_name", "data.resolution", "data.scene_count", "data.character_count", "data.variable_count", "data.event_count", "data.initial_scene_id", "data.initial_scene_name", "error"]
		})

	ai_service.register_tool("project_save", "Save project and notify UI", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _project_save(args), {
		"fields": ["success", "error"]
	})

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
	}, func(args: Dictionary) -> Variant: return _import_project_asset(args), {
		"fields": ["success", "alias", "asset_type", "target_path", "message", "error"]
	})

	ai_service.register_tool("finish", "End your task and return summary to parent agent. You MUST call this when done.", {
		"type": "object",
		"properties": {
			"summary": {"type": "string", "description": "Work summary: what was created/modified"}
		},
		"required": ["summary"]
	}, func(args: Dictionary) -> Variant: return _finish(args), {
		"fields": ["success", "summary", "error"]
	})

	_register_initial_scene_tool(ai_service)
	_register_scene_analysis_tools(ai_service)

	ai_service.register_tool("list_assets", "列出当前项目的可用资源文件与 alias（背景图、非角色图片、CG、BGM、SFX、角色表情/服装信息）。在编写 DSL 脚本前必须先调用此工具查询可用资源，禁止编造不存在的资源名！", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["all", "backgrounds", "images", "cg", "bgm", "sfx", "characters"], "description": "要查询的资源类别，默认 all"}
		},
	}, func(args: Dictionary) -> Variant: return _list_assets(args), {
		"fields": ["success", "data", "error"]
	})


## Main agent registration: preview_scene only (sub-agents handle the rest)
static func register_preview_and_finish(ai_service: Node, include_project_info: bool = true) -> void:
	ai_service.register_tool("preview_scene", "Let the player playtest a specific scene", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "Scene ID to preview"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _preview_scene(args), {
		"fields": ["success", "message", "error"]
	})

	if include_project_info:
		ai_service.register_tool("project_info", "Get project overview", {
			"type": "object",
			"properties": {},
		}, func(args: Dictionary) -> Variant: return _project_info(args), {
			"fields": ["success", "data.project_name", "data.resolution", "data.scene_count", "data.character_count", "data.variable_count", "data.event_count", "data.initial_scene_id", "data.initial_scene_name", "error"]
		})

	_register_initial_scene_tool(ai_service)
	_register_scene_analysis_tools(ai_service)

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
	}, func(args: Dictionary) -> Variant: return _import_project_asset(args), {
		"fields": ["success", "alias", "asset_type", "target_path", "message", "error"]
	})


static func _register_scene_analysis_tools(ai_service: Node) -> void:
	ai_service.register_tool("list_scene_catalog", "列出场景目录摘要。只返回场景 ID、名称、备注，以及初始场景/孤立场景等导航信息，适合快速定位要修改的场景。", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _list_scene_catalog(args), {
		"fields": ["success", "data", "entry_scene_id", "error"]
	})

	ai_service.register_tool("analyze_story_reachability", "分析当前 AVG 项目的伪运行可达性，检测孤立场景、不可达分支，以及依赖未知运行时条件的路径。", {
		"type": "object",
		"properties": {
			"max_total_states": {"type": "integer", "description": "可选。最多展开多少个场景状态，默认 256。"},
			"max_command_steps": {"type": "integer", "description": "可选。单路径最多遍历多少条命令，默认 512。"},
		},
	}, func(args: Dictionary) -> Variant: return _analyze_story_reachability(args), {
		"fields": ["success", "data.entry_scene_id", "data.scene_catalog", "data.unreachable_scenes", "data.warnings", "error"]
	})


static func _register_initial_scene_tool(ai_service: Node) -> void:
	ai_service.register_tool("set_initial_scene", "设置 AVG 项目的初始场景（title_config.first_scene_id），并自动保存。适用于创建新开场、重排主线入口、修复初始场景断链。", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "要设为初始场景的 scene_id"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _set_initial_scene(args), {
		"fields": ["success", "scene_id", "scene_name", "message", "error"]
	})


static func build_character_casting_skill_tools() -> Array[Dictionary]:
	return [
		{
			"name": "list_character_shells",
			"description": "列出当前项目中可用于绑定新角色的预置角色壳子，并标明哪些已经被占用。",
			"schema": {
				"type": "object",
				"properties": {
					"only_available": {"type": "boolean", "description": "若为 true，只返回未占用的预置角色壳子。默认 false。"}
				},
			},
			"callback": func(args: Dictionary) -> Variant: return _list_character_shells(args),
			"llm_view": {"fields": ["success", "data", "count", "available_count", "error"]},
		},
		{
			"name": "occupy_character_shell",
			"description": "将一个未占用的预置角色壳子绑定给当前角色，并同步写入 character_name / display_name / profile / character_key。注意：character_name 是 DSL/系统引用名，必须是 ASCII 标识符；display_name 才是游戏内显示名。该操作会自动保存项目。",
			"schema": {
				"type": "object",
				"properties": {
					"character_id": {"type": "string", "description": "要占用的角色壳子 ID（如 char_001）。"},
					"character_key": {"type": "string", "description": "项目内逻辑角色 key，例如 protagonist / rival / heroine_main。"},
					"character_name": {"type": "string", "description": "写入项目资源的稳定角色名，供 DSL / Writer / 系统引用。必须是 ASCII 标识符，例如 LinXia / Hero01。"},
					"display_name": {"type": "string", "description": "游戏内显示名。可以是中文；省略时默认等于 character_name。"},
					"profile": {"type": "string", "description": "与当前 KB 角色设定一致的简短外观/气质摘要。"}
				},
				"required": ["character_id", "character_key", "character_name", "profile"]
			},
			"callback": func(args: Dictionary) -> Variant: return _occupy_character_shell(args),
			"llm_view": {"fields": ["success", "character", "message", "error"]},
		},
	]


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
			"initial_scene_id": _get_initial_scene_id(project),
			"initial_scene_name": _get_scene_name_by_id(project, _get_initial_scene_id(project)),
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
				"note": s.scene_note if "scene_note" in s else "",
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

	var save_err: Error = sm.save_project(sm.current_project)
	if save_err != OK:
		return {"success": false, "error": "项目保存失败: %s" % save_err}
	sm.project_content_changed.emit()
	return {"success": true, "message": "项目与知识库已保存"}


# =============================================================================
# character shell casting
# =============================================================================

static func _list_character_shells(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}
	if not ("characters" in project):
		return {"success": false, "error": "当前项目没有 characters 数组"}

	var only_available: bool = bool(args.get("only_available", false))
	var items: Array[Dictionary] = []
	for character in project.characters:
		if character == null:
			continue
		var item: Dictionary = _build_character_shell_entry(character)
		if only_available and bool(item.get("occupied", false)):
			continue
		items.append(item)

	return {
		"success": true,
		"data": items,
		"count": items.size(),
		"available_count": _count_available_shells(items),
	}


static func _occupy_character_shell(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}
	if not ("characters" in project):
		return {"success": false, "error": "当前项目没有 characters 数组"}

	var target_id: String = str(args.get("character_id", "")).strip_edges()
	var target_key: String = AVGCharacter.normalize_character_key(str(args.get("character_key", "")))
	var target_name: String = str(args.get("character_name", args.get("name", ""))).strip_edges()
	var target_display_name: String = str(args.get("display_name", "")).strip_edges()
	var target_profile: String = str(args.get("profile", "")).strip_edges()

	if target_id.is_empty():
		return {"success": false, "error": "character_id 不能为空"}
	if target_key.is_empty():
		return {"success": false, "error": "character_key 不能为空，且必须是可归一化的标识符"}
	if target_name.is_empty():
		return {"success": false, "error": "character_name 不能为空"}
	if not _is_valid_dsl_character_name(target_name):
		return {"success": false, "error": "character_name 必须是 ASCII 标识符（仅字母/数字/下划线，且以字母开头），例如 LinXia / Hero01"}
	if target_profile.is_empty():
		return {"success": false, "error": "profile 不能为空"}
	if target_display_name.is_empty():
		target_display_name = target_name

	var target_character: Resource = null
	for character in project.characters:
		if character == null:
			continue
		var character_id: String = str(character.character_id if "character_id" in character else "").strip_edges()
		if character_id == target_id:
			target_character = character
			break
	if target_character == null:
		return {"success": false, "error": "角色壳子不存在: %s" % target_id}

	var target_existing_key: String = AVGCharacter.normalize_character_key(str(target_character.character_key if "character_key" in target_character else ""))
	var target_is_placeholder: bool = AVGCharacter.looks_like_template_shell(target_character)
	if not target_existing_key.is_empty() and target_existing_key != target_key:
		return {"success": false, "error": "角色壳子 %s 已被 key=%s 占用" % [target_id, target_existing_key]}
	if target_existing_key.is_empty() and not target_is_placeholder:
		return {"success": false, "error": "角色壳子 %s 已被自定义占用，不能覆盖" % target_id}

	for character in project.characters:
		if character == null or character == target_character:
			continue
		var existing_key: String = AVGCharacter.normalize_character_key(str(character.character_key if "character_key" in character else ""))
		if existing_key == target_key:
			var existing_id: String = str(character.character_id if "character_id" in character else "").strip_edges()
			return {"success": false, "error": "character_key 已被其他角色占用: %s -> %s" % [target_key, existing_id]}

	target_character.character_key = target_key
	target_character.character_name = target_name
	target_character.display_name = target_display_name
	target_character.profile = target_profile

	var save_result: Dictionary = _project_save({})
	if not bool(save_result.get("success", false)):
		return save_result

	return {
		"success": true,
		"character": _build_character_shell_entry(target_character),
		"message": "角色壳子已占用并保存",
	}


static func _is_valid_dsl_character_name(raw_name: String) -> bool:
	var name: String = raw_name.strip_edges()
	if name.is_empty():
		return false
	for i in name.length():
		var codepoint: int = name.unicode_at(i)
		var is_upper: bool = codepoint >= 65 and codepoint <= 90
		var is_lower: bool = codepoint >= 97 and codepoint <= 122
		var is_digit: bool = codepoint >= 48 and codepoint <= 57
		var is_underscore: bool = codepoint == 95
		if i == 0:
			if not is_upper and not is_lower:
				return false
			continue
		if not is_upper and not is_lower and not is_digit and not is_underscore:
			return false
	return true


static func _build_character_shell_entry(character: Resource) -> Dictionary:
	var character_id: String = str(character.character_id if "character_id" in character else "").strip_edges()
	var character_key: String = AVGCharacter.normalize_character_key(str(character.character_key if "character_key" in character else ""))
	var placeholder_shell: bool = AVGCharacter.looks_like_template_shell(character)
	var occupied: bool = not character_key.is_empty() or not placeholder_shell
	var occupancy_reason: String = ""
	if not character_key.is_empty():
		occupancy_reason = "bound"
	elif occupied:
		occupancy_reason = "customized"
	else:
		occupancy_reason = "available"
	return {
		"id": character_id,
		"character_key": character_key,
		"character_name": str(character.character_name if "character_name" in character else "").strip_edges(),
		"display_name": str(character.display_name if "display_name" in character else "").strip_edges(),
		"profile": str(character.profile if "profile" in character else "").strip_edges(),
		"placeholder_shell": placeholder_shell,
		"occupied": occupied,
		"occupancy_reason": occupancy_reason,
	}


static func _count_available_shells(items: Array[Dictionary]) -> int:
	var count: int = 0
	for item in items:
		if not bool(item.get("occupied", false)):
			count += 1
	return count


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


static func _set_initial_scene(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var scene_id: String = str(args.get("scene_id", "")).strip_edges()
	if scene_id.is_empty():
		return {"success": false, "error": "scene_id 不能为空"}

	var target_scene: Resource = null
	if "scenes" in project:
		for scene in project.scenes:
			if scene == null:
				continue
			var existing_id: String = str(scene.scene_id if "scene_id" in scene else "").strip_edges()
			if existing_id == scene_id:
				target_scene = scene
				break
	if target_scene == null:
		return {"success": false, "error": "场景不存在: %s" % scene_id}

	if not ("title_config" in project) or project.title_config == null:
		project.title_config = AVGTitleConfigClass.new()
	project.title_config.first_scene_id = scene_id

	var save_result: Dictionary = _project_save({})
	if not bool(save_result.get("success", false)):
		return save_result

	return {
		"success": true,
		"scene_id": scene_id,
		"scene_name": str(target_scene.scene_name if "scene_name" in target_scene else "").strip_edges(),
		"message": "初始场景已设置并保存",
	}


static func _list_scene_catalog(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}
	var analyzer := StoryReachabilityAnalyzerClass.new()
	return analyzer.build_scene_catalog(project, args)


static func _analyze_story_reachability(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}
	var analyzer := StoryReachabilityAnalyzerClass.new()
	return analyzer.analyze(project, args)


static func _get_initial_scene_id(project: Resource) -> String:
	if project == null or not ("title_config" in project) or project.title_config == null:
		return ""
	return str(project.title_config.first_scene_id if "first_scene_id" in project.title_config else "").strip_edges()


static func _get_scene_name_by_id(project: Resource, scene_id: String) -> String:
	if project == null or scene_id.is_empty() or not ("scenes" in project):
		return ""
	for scene in project.scenes:
		if scene == null:
			continue
		var existing_id: String = str(scene.scene_id if "scene_id" in scene else "").strip_edges()
		if existing_id == scene_id:
			return str(scene.scene_name if "scene_name" in scene else "").strip_edges()
	return ""


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
