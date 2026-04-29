class_name AVGDevScriptTools extends RefCounted
## AVG Dev AI — 脚本工具集
## 提供 get_scene_script / set_scene_script
## 所有操作通过 DSLSerializer/DSLParser 读写 Root 节点 command_tab

const AVGDSLValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")


# =============================================================================
# 工具注册
# =============================================================================

static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("get_scene_script", "获取指定场景 Root 节点的完整 DSL 脚本文本", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "场景 ID（如 scene_001）"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _get_scene_script(args), {
		"fields": ["success", "data.scene_id", "data.dsl", "error"]
	})

	ai_service.register_tool("set_scene_script", "写入场景的 DSL 脚本。支持 replace（全替换）和 patch（片段替换）两种模式。DSL 中出现的未定义变量 key 会自动创建，默认优先按 int 初始化；如果首次使用就是字符串字面量，会自动推断为 string。当前变量系统只允许 int / string：布尔请用 0/1，float 会被截断成 int。混用 string 和 int 做比较时会在返回结果里给 warning，运行时会把空字符串视为 0、非空字符串视为 1。", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "场景 ID"},
			"mode": {
				"type": "string",
				"enum": ["replace", "patch"],
				"description": "模式：replace 全替换 / patch 查找替换片段"
			},
			"dsl": {"type": "string", "description": "replace 模式：完整的新 DSL 文本"},
			"old_dsl": {"type": "string", "description": "patch 模式：要被替换的旧 DSL 片段"},
			"new_dsl": {"type": "string", "description": "patch 模式：替换后的新 DSL 片段"}
		},
		"required": ["scene_id", "mode"]
	}, func(args: Dictionary) -> Variant: return _set_scene_script(args), {
		"fields": ["success", "message", "error"]
	})


static func register_read_only(ai_service: Node) -> void:
	ai_service.register_tool("get_scene_script", "获取指定场景 Root 节点的完整 DSL 脚本文本", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "场景 ID（如 scene_001）"}
		},
		"required": ["scene_id"]
	}, func(args: Dictionary) -> Variant: return _get_scene_script(args), {
		"fields": ["success", "data.scene_id", "data.dsl", "error"]
	})


# =============================================================================
# get_scene_script
# =============================================================================

static func _get_scene_script(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var scene_id: String = args.get("scene_id", "")
	var scene: Resource = _find_scene(project, scene_id)
	if scene == null:
		return {"success": false, "error": "场景 '%s' 未找到" % scene_id}

	var root: Resource = AVGDevDBTools.find_root_node(scene)
	if root == null:
		return {"success": false, "error": "场景没有 Root 节点"}

	var dsl: String = AVGDevDBTools.get_root_dsl(scene, project)
	return {"success": true, "data": {"scene_id": scene_id, "dsl": dsl}}


# =============================================================================
# set_scene_script
# =============================================================================

static func _set_scene_script(args: Dictionary) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var scene_id: String = args.get("scene_id", "")
	var mode: String = args.get("mode", "replace")

	var scene: Resource = _find_scene(project, scene_id)
	if scene == null:
		return {"success": false, "error": "场景 '%s' 未找到" % scene_id}

	var root: Resource = AVGDevDBTools.find_root_node(scene)
	if root == null:
		return {"success": false, "error": "场景没有 Root 节点"}

	match mode:
		"replace":
			return _set_script_replace(project, scene, root, args)
		"patch":
			return _set_script_patch(project, scene, root, args)
		_:
			return {"success": false, "error": "未知模式: " + mode}


static func _set_script_replace(project: Resource, scene: Resource, root: Resource, args: Dictionary) -> Dictionary:
	var dsl: String = args.get("dsl", "")
	if dsl.is_empty():
		# 清空脚本
		root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": [], "condition_commands": []}]
		return {"success": true, "message": "脚本已清空"}

	var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
	var parser = ParserClass.new()
	var result: Dictionary = parser.parse(dsl)
	if not result.success:
		return {"success": false, "error": "DSL 解析失败: " + str(result.errors)}

	var ensure_result: Dictionary = AVGDevDBTools.ensure_variables_for_commands(project, result.commands)
	var auto_created_keys: Array = ensure_result.get("created_keys", [])

	root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": result.commands, "condition_commands": []}]
	var placeholder_result: Dictionary = AVGDevDBTools.ensure_placeholder_scenes_for_commands(project, scene, result.commands)
	AVGDevDBTools.clear_placeholder_marker_if_implemented(scene)

	# 语义验证：检查资产引用是否存在
	var validation: Dictionary = _run_semantic_validation(result.commands)
	var msg: String = "脚本已替换（%d 条命令）" % result.commands.size()
	if not auto_created_keys.is_empty():
		msg += "\n\n已自动创建变量: %s" % ", ".join(PackedStringArray(auto_created_keys))
	var placeholder_scene_ids: Array = placeholder_result.get("created_scene_ids", [])
	if not placeholder_scene_ids.is_empty():
		msg += "\n\n已自动创建占位场景: %s" % ", ".join(PackedStringArray(placeholder_scene_ids))
	var skipped_placeholder_scene_ids: Array = placeholder_result.get("skipped_invalid_scene_ids", [])
	if not skipped_placeholder_scene_ids.is_empty():
		msg += "\n\n⚠ 未自动创建以下跳转目标（scene_id 格式非法）: %s" % ", ".join(PackedStringArray(skipped_placeholder_scene_ids))
	if not validation.errors.is_empty():
		msg += "\n\n⚠️ 语义验证发现 %d 个问题（脚本已保存，建议用 patch 模式修复）：" % validation.errors.size()
		for e in validation.errors:
			msg += "\n- " + e
	if not validation.warnings.is_empty():
		msg += "\n\n⚠ 警告："
		for w in validation.warnings:
			msg += "\n- " + w
	return {"success": true, "message": msg}


static func _set_script_patch(project: Resource, scene: Resource, root: Resource, args: Dictionary) -> Dictionary:
	var old_dsl: String = args.get("old_dsl", "")
	var new_dsl: String = args.get("new_dsl", "")

	if old_dsl.is_empty():
		return {"success": false, "error": "patch 模式需要 old_dsl 参数"}

	# 获取当前 DSL
	var serializer: RefCounted = AVGDSLSerializer.new()
	var current_commands: Array = []
	if "command_tabs" in root and root.command_tabs.size() > 0:
		current_commands = root.command_tabs[0].get("commands", [])
	var current_dsl: String = serializer.serialize(current_commands, 0, AVGDevDBTools._build_variable_lookup(project))

	# 查找替换
	var normalized_current: String = _normalize_dsl(current_dsl)
	var normalized_old: String = _normalize_dsl(old_dsl)

	if normalized_current.find(normalized_old) == -1:
		return {"success": false, "error": "未在当前脚本中找到要替换的片段。当前脚本:\n" + current_dsl}

	# 在原始文本中做替换（保留格式）
	var patched_dsl: String = current_dsl.replace(old_dsl.strip_edges(), new_dsl.strip_edges())

	# 如果精确替换失败，用 normalized 版本
	if patched_dsl == current_dsl:
		# 精确匹配失败，尝试按行归一化替换
		patched_dsl = _patch_by_lines(current_dsl, old_dsl, new_dsl)
		if patched_dsl == current_dsl:
			return {"success": false, "error": "替换失败：无法精确匹配旧片段"}

	var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
	var parser = ParserClass.new()
	var result: Dictionary = parser.parse(patched_dsl)
	if not result.success:
		return {"success": false, "error": "Patch 后 DSL 解析失败: " + str(result.errors)}

	var ensure_result: Dictionary = AVGDevDBTools.ensure_variables_for_commands(project, result.commands)
	var auto_created_keys: Array = ensure_result.get("created_keys", [])

	root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": result.commands, "condition_commands": []}]
	var placeholder_result: Dictionary = AVGDevDBTools.ensure_placeholder_scenes_for_commands(project, scene, result.commands)
	AVGDevDBTools.clear_placeholder_marker_if_implemented(scene)

	# 语义验证
	var validation: Dictionary = _run_semantic_validation(result.commands)
	var msg: String = "脚本已 patch（%d 条命令）" % result.commands.size()
	if not auto_created_keys.is_empty():
		msg += "\n\n已自动创建变量: %s" % ", ".join(PackedStringArray(auto_created_keys))
	var placeholder_scene_ids: Array = placeholder_result.get("created_scene_ids", [])
	if not placeholder_scene_ids.is_empty():
		msg += "\n\n已自动创建占位场景: %s" % ", ".join(PackedStringArray(placeholder_scene_ids))
	var skipped_placeholder_scene_ids: Array = placeholder_result.get("skipped_invalid_scene_ids", [])
	if not skipped_placeholder_scene_ids.is_empty():
		msg += "\n\n⚠ 未自动创建以下跳转目标（scene_id 格式非法）: %s" % ", ".join(PackedStringArray(skipped_placeholder_scene_ids))
	if not validation.errors.is_empty():
		msg += "\n\n⚠️ 语义验证发现 %d 个问题（脚本已保存，建议用 patch 模式修复）：" % validation.errors.size()
		for e in validation.errors:
			msg += "\n- " + e
	if not validation.warnings.is_empty():
		msg += "\n\n⚠ 警告："
		for w in validation.warnings:
			msg += "\n- " + w
	return {"success": true, "message": msg}


# =============================================================================
# 内部辅助
# =============================================================================

static func _find_scene(project: Resource, scene_id: String) -> Resource:
	for scene in project.scenes:
		if scene == null:
			continue
		if "scene_id" in scene and scene.scene_id == scene_id:
			return scene
	return null


## 归一化 DSL 文本（去除多余空白，用于模糊匹配）
static func _normalize_dsl(dsl: String) -> String:
	var lines: Array = []
	for line in dsl.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.is_empty():
			lines.append(stripped)
	return "\n".join(lines)


## 按行归一化后替换
static func _patch_by_lines(current_dsl: String, old_dsl: String, new_dsl: String) -> String:
	var current_lines: Array[String] = []
	for l in current_dsl.split("\n"):
		current_lines.append(l)
	var old_lines: Array[String] = []
	for l in old_dsl.strip_edges().split("\n"):
		var stripped: String = l.strip_edges()
		if not stripped.is_empty():
			old_lines.append(stripped)

	if old_lines.is_empty():
		return current_dsl

	# 查找匹配的起始位置
	for i in range(current_lines.size()):
		if current_lines[i].strip_edges() == old_lines[0]:
			# 检查后续行是否全部匹配
			var match_found: bool = true
			if i + old_lines.size() > current_lines.size():
				continue
			for j in range(old_lines.size()):
				if current_lines[i + j].strip_edges() != old_lines[j]:
					match_found = false
					break
			if match_found:
				# 替换
				var result_lines: Array[String] = []
				for k in range(i):
					result_lines.append(current_lines[k])
				for l in new_dsl.strip_edges().split("\n"):
					result_lines.append(l)
				for k in range(i + old_lines.size(), current_lines.size()):
					result_lines.append(current_lines[k])
				return "\n".join(result_lines)

	return current_dsl


## 运行语义验证（检查资产引用、角色、情绪等是否存在）
static func _run_semantic_validation(commands: Array) -> Dictionary:
	var project: Resource = AVGDevDBTools.get_project()
	if project == null:
		return {"errors": [], "warnings": ["无法获取项目信息，跳过语义验证"]}

	var storage_manager: Node = AVGDevDBTools.get_autoload("StorageManager")
	if storage_manager != null and storage_manager.has_method("clear_asset_manifest_cache"):
		storage_manager.clear_asset_manifest_cache()
	else:
		AVGDSLValidatorClass.AVGAssetManifestClass.clear_cache()

	var validator = AVGDSLValidatorClass.new()
	var project_root: String = AVGDSLValidatorClass.AVGAssetManifestClass.get_project_root_from_project(project)
	var result: Dictionary = validator.validate_commands(commands, project, project_root)
	var warnings: Array = result.get("warnings", []).duplicate()
	if not result.get("errors", []).is_empty():
		var current_project_path: String = ""
		if storage_manager != null and "current_project_path" in storage_manager:
			current_project_path = str(storage_manager.get("current_project_path")).strip_edges()
		warnings.append("验证使用 project_root_path=%s, current_project_path=%s" % [project_root, current_project_path])
		result["warnings"] = warnings

	return {"errors": result.get("errors", []), "warnings": result.get("warnings", [])}
