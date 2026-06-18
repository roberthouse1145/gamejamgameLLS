class_name AVGDevGameEditorTools extends RefCounted
## High-level WorkOrderAgent tools that behave like a compact AVG game editor.

const KBToolsClass = preload("res://scripts/avg/dev_tools/kb_tools.gd")
const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")
const ScriptToolsClass = preload("res://scripts/avg/dev_tools/script_tools.gd")
const ProjectToolsClass = preload("res://scripts/avg/dev_tools/project_tools.gd")
const ContextToolsClass = preload("res://scripts/avg/dev_tools/context_tools.gd")
const AVGTitleConfigClass = preload("res://scripts/avg/resources/avg_title_config.gd")


static func register_work_order_tools(ai_service: Node) -> void:
	_register_kb_tools(ai_service)
	_register_get_project_context(ai_service)
	_register_upsert_scene(ai_service)
	_register_edit_scenes(ai_service)
	_register_upsert_character(ai_service)
	_register_upsert_variable(ai_service)
	_register_upsert_event(ai_service)
	_register_import_project_asset(ai_service)


static func _register_kb_tools(ai_service: Node) -> void:
	KBToolsClass.register_read_only(ai_service)
	ai_service.register_tool("kb_write", "创建或更新游戏设定知识库文档。用于落实世界观、角色、人设、路线稿、实现稿等文本产物。", {
		"type": "object",
		"properties": {
			"doc_id": {"type": "string", "description": "文档 ID。留空则自动生成。"},
			"title": {"type": "string", "description": "文档标题。"},
			"content": {"type": "string", "description": "文档正文。"},
			"category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "文档分类。"},
			"tags": {"type": "array", "items": {"type": "string"}, "description": "可选标签。"},
			"doc_kind": {"type": "string", "enum": ["canonical", "brief", "open_questions", "backbone", "decision_log", "reference"], "description": "可选文档用途。"},
			"state": {"type": "string", "enum": ["draft", "confirmed", "superseded"], "description": "可选状态。"}
		},
		"required": ["title", "content", "category"]
	}, func(args: Dictionary) -> Variant: return KBToolsClass._kb_write(args), {
		"fields": ["success", "doc_id", "error"]
	}, {"effect": "write"})


static func _register_get_project_context(ai_service: Node) -> void:
	ai_service.register_tool("get_project_context", "一次读取 WorkOrderAgent 常用项目上下文：项目概览、KB、场景 DSL、角色、变量、资源、场景目录、故事大纲、可达性。优先用它减少多轮查询。", {
		"type": "object",
		"properties": {
			"scene_ids": {"type": "array", "items": {"type": "string"}, "description": "可选。要读取完整 DSL 的场景 ID。"},
			"kb_category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "可选。读取某类 KB 正文。"},
			"kb_doc_ids": {"type": "array", "items": {"type": "string"}, "description": "可选。精确读取的 KB doc_id 列表。"},
			"kb_tags": {"type": "array", "items": {"type": "string"}, "description": "可选。KB 标签过滤。"},
			"asset_categories": {"type": "array", "items": {"type": "string", "enum": ["backgrounds", "images", "cg", "bgm", "sfx", "characters"]}, "description": "可选。资源类别。"},
			"include_project_info": {"type": "boolean", "description": "是否返回项目概览。默认 true。"},
			"include_characters": {"type": "boolean", "description": "是否返回角色名册。"},
			"include_variables": {"type": "boolean", "description": "是否返回变量列表。"},
			"include_scene_catalog": {"type": "boolean", "description": "是否返回场景目录。"},
			"include_story_outline": {"type": "boolean", "description": "是否返回全项目叙事大纲。"},
			"include_reachability": {"type": "boolean", "description": "是否返回剧情可达性摘要。"}
		}
	}, func(args: Dictionary) -> Variant: return _get_project_context(args), {
		"fields": ["success", "data", "error"]
	}, {"effect": "read"})


static func _register_upsert_scene(ai_service: Node) -> void:
	ai_service.register_tool("upsert_scene", "创建或更新一个 AVG 场景，并可写入完整 DSL。用于替代 db_create/db_update/set_scene_script。DSL parse 失败时不会覆盖已有脚本。", {
		"type": "object",
		"properties": {
			"scene_id": {"type": "string", "description": "可选。目标场景 ID；不存在时创建，留空时自动生成。"},
			"scene_name": {"type": "string", "description": "可选。场景名。"},
			"scene_note": {"type": "string", "description": "可选。场景备注。"},
			"folder": {"type": "string", "description": "可选。场景文件夹。"},
			"dsl": {"type": "string", "description": "可选。完整 DSL；传入空字符串会清空脚本。"},
			"set_as_initial": {"type": "boolean", "description": "是否设为项目初始场景。"},
			"include_reachability": {"type": "boolean", "description": "是否强制返回可达性摘要。"}
		}
	}, func(args: Dictionary) -> Variant: return _upsert_scene(args), {
		"fields": ["success", "scene_id", "changed", "parse_errors", "semantic_errors", "warnings", "auto_created_variable_keys", "auto_created_placeholder_scene_ids", "reachability", "error"]
	}, {"effect": "write"})


static func _register_edit_scenes(ai_service: Node) -> void:
	ai_service.register_tool("edit_scenes", "批量修改场景。每条 edit 支持 replace 或 patch DSL，并可同步更新 scene_name/scene_note/folder。适合整合跳转、结尾和批量修补。", {
		"type": "object",
		"properties": {
			"edits": {
				"type": "array",
				"items": {
					"type": "object",
					"properties": {
						"scene_id": {"type": "string", "description": "目标场景 ID。"},
						"mode": {"type": "string", "enum": ["replace", "patch"], "description": "replace=整段 DSL，patch=片段替换。"},
						"dsl": {"type": "string", "description": "replace 模式完整 DSL。"},
						"old_dsl": {"type": "string", "description": "patch 模式旧片段。"},
						"new_dsl": {"type": "string", "description": "patch 模式新片段。"},
						"scene_name": {"type": "string", "description": "可选。场景名。"},
						"scene_note": {"type": "string", "description": "可选。场景备注。"},
						"folder": {"type": "string", "description": "可选。场景文件夹。"}
					},
					"required": ["scene_id", "mode"]
				}
			},
			"stop_on_error": {"type": "boolean", "description": "默认 false。为 true 时遇到失败立即停止。"},
			"include_reachability": {"type": "boolean", "description": "是否强制返回批量修改后的可达性摘要。"}
		},
		"required": ["edits"]
	}, func(args: Dictionary) -> Variant: return _edit_scenes(args), {
		"fields": ["success", "results", "patched_count", "failed_count", "reachability", "error"]
	}, {"effect": "write"})


static func _register_upsert_character(ai_service: Node) -> void:
	ai_service.register_tool("upsert_character", "绑定或更新角色数据。若不提供 character_id，会优先占用一个未绑定预置角色壳，没有可用壳时创建新角色。", {
		"type": "object",
		"properties": {
			"character_id": {"type": "string", "description": "可选。目标角色壳 ID。"},
			"character_key": {"type": "string", "description": "角色逻辑 key，例如 protagonist / heroine_blue。"},
			"character_name": {"type": "string", "description": "DSL 引用名，必须是 ASCII 标识符。"},
			"display_name": {"type": "string", "description": "游戏内显示名，可中文。"},
			"profile": {"type": "string", "description": "角色简介。"}
		}
	}, func(args: Dictionary) -> Variant: return _upsert_character(args), {
		"fields": ["success", "character", "created", "occupied_shell", "error"]
	}, {"effect": "write"})


static func _register_upsert_variable(ai_service: Node) -> void:
	ai_service.register_tool("upsert_variable", "创建或更新 AVG 路线变量。变量只支持 int/string；布尔请用 0/1。", {
		"type": "object",
		"properties": {
			"variable_id": {"type": "string", "description": "可选。变量 ID。"},
			"variable_key": {"type": "string", "description": "稳定变量 key。"},
			"value_type": {"type": "string", "enum": ["int", "string"], "description": "变量类型。"},
			"default_value": {"description": "默认值。"},
			"description": {"type": "string", "description": "变量说明。"}
		}
	}, func(args: Dictionary) -> Variant: return _upsert_variable(args), {
		"fields": ["success", "variable", "created", "error"]
	}, {"effect": "write"})


static func _register_upsert_event(ai_service: Node) -> void:
	ai_service.register_tool("upsert_event", "创建或更新轻量事件，可选写入事件 DSL。DSL parse 失败时不会写入。", {
		"type": "object",
		"properties": {
			"event_id": {"type": "string", "description": "可选。事件 ID。"},
			"event_name": {"type": "string", "description": "事件名。"},
			"dsl": {"type": "string", "description": "可选。事件 DSL。"}
		}
	}, func(args: Dictionary) -> Variant: return _upsert_event(args), {
		"fields": ["success", "event", "created", "parse_errors", "warnings", "auto_created_variable_keys", "error"]
	}, {"effect": "write"})


static func _register_import_project_asset(ai_service: Node) -> void:
	ai_service.register_tool("import_project_asset", "导入外部素材到当前项目，并写入 asset alias。仅在工单明确给出外部资源路径时使用。", {
		"type": "object",
		"properties": {
			"source_path": {"type": "string", "description": "外部文件路径，支持绝对路径、res://、user://。"},
			"asset_type": {"type": "string", "enum": ["background", "image", "cg", "bgm", "sfx"], "description": "资源类型。"},
			"alias": {"type": "string", "description": "可选 alias。"},
			"target_subdir": {"type": "string", "description": "可选目标子目录。"},
			"overwrite": {"type": "boolean", "description": "是否允许覆盖。"}
		},
		"required": ["source_path", "asset_type"]
	}, func(args: Dictionary) -> Variant: return ProjectToolsClass._import_project_asset(args), {
		"fields": ["success", "alias", "asset_type", "target_path", "message", "error"]
	}, {"effect": "write"})


static func _get_project_context(args: Dictionary) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var data: Dictionary = {}
	if bool(args.get("include_project_info", true)):
		var info_result: Dictionary = ProjectToolsClass._project_info({})
		if bool(info_result.get("success", false)):
			data["project"] = info_result.get("data", {})
		else:
			data["project_error"] = info_result.get("error", "")

	var gather_args: Dictionary = {
		"scene_ids": args.get("scene_ids", []),
		"kb_category": str(args.get("kb_category", "")).strip_edges(),
		"kb_doc_ids": args.get("kb_doc_ids", []),
		"kb_tags": args.get("kb_tags", []),
		"asset_categories": args.get("asset_categories", []),
		"include_characters": bool(args.get("include_characters", false)),
		"include_variables": bool(args.get("include_variables", false)),
		"include_scene_catalog": bool(args.get("include_scene_catalog", false)),
		"include_reachability": bool(args.get("include_reachability", false)),
	}
	var gathered: Dictionary = ContextToolsClass._gather_scene_context(gather_args)
	if bool(gathered.get("success", false)):
		_merge_dict(data, gathered.get("data", {}))
	else:
		data["context_error"] = gathered.get("error", "")

	if bool(args.get("include_story_outline", false)):
		var outline_result: Dictionary = DBToolsClass._get_story_outline({})
		if bool(outline_result.get("success", false)):
			data["story_outline"] = outline_result.get("data", "")
		else:
			data["story_outline_error"] = outline_result.get("error", "")

	return {"success": true, "data": data}


static func _upsert_scene(args: Dictionary) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var requested_scene_id: String = str(args.get("scene_id", "")).strip_edges()
	var has_dsl: bool = args.has("dsl")
	var dsl: String = str(args.get("dsl", ""))
	if has_dsl and not dsl.strip_edges().is_empty():
		var parse_check: Dictionary = _parse_dsl(dsl)
		if not bool(parse_check.get("success", false)):
			return _scene_failure_result(requested_scene_id, "DSL 解析失败", parse_check.get("errors", []), parse_check.get("warnings", []))

	var scene: Resource = _find_scene(project, requested_scene_id) if not requested_scene_id.is_empty() else null
	var created: bool = false
	var changed: bool = false
	if scene == null:
		var create_fields: Dictionary = _extract_scene_fields(args, true)
		if not requested_scene_id.is_empty():
			create_fields["scene_id"] = requested_scene_id
		var create_result: Dictionary = DBToolsClass._db_create({"type": "scenes", "fields": create_fields})
		if not bool(create_result.get("success", false)):
			return {"success": false, "scene_id": requested_scene_id, "changed": false, "error": create_result.get("error", "")}
		requested_scene_id = str(create_result.get("id", requested_scene_id)).strip_edges()
		scene = _find_scene(project, requested_scene_id)
		created = true
		changed = true
	else:
		var update_fields: Dictionary = _extract_scene_fields(args, false)
		if not update_fields.is_empty():
			var update_result: Dictionary = DBToolsClass._db_update({"type": "scenes", "id": requested_scene_id, "fields": update_fields})
			if not bool(update_result.get("success", false)):
				return {"success": false, "scene_id": requested_scene_id, "changed": false, "error": update_result.get("error", "")}
			changed = true

	var script_result: Dictionary = {}
	if has_dsl:
		script_result = ScriptToolsClass._set_scene_script({
			"scene_id": requested_scene_id,
			"mode": "replace",
			"dsl": dsl,
		})
		if not bool(script_result.get("success", false)):
			return _scene_failure_result(requested_scene_id, str(script_result.get("error", "DSL 写入失败")), script_result.get("parse_errors", []), script_result.get("warnings", []))
		changed = true

	var initial_set: bool = false
	if bool(args.get("set_as_initial", false)):
		_set_initial_scene_without_save(project, requested_scene_id)
		initial_set = true
		changed = true

	var reachability: Dictionary = {}
	if bool(args.get("include_reachability", false)) or initial_set or (has_dsl and _dsl_touches_scene_links(dsl)):
		reachability = _reachability_summary()

	var result: Dictionary = _scene_success_result(requested_scene_id, changed, script_result, reachability)
	result["created"] = created
	result["initial_scene_set"] = initial_set
	return result


static func _edit_scenes(args: Dictionary) -> Dictionary:
	var edits: Array = args.get("edits", [])
	if edits.is_empty():
		return {"success": false, "error": "edits 不能为空"}

	var stop_on_error: bool = bool(args.get("stop_on_error", false))
	var results: Array[Dictionary] = []
	var any_link_change: bool = bool(args.get("include_reachability", false))
	var success_count: int = 0

	for edit in edits:
		if not (edit is Dictionary):
			results.append({"success": false, "error": "edit 条目必须是对象"})
			if stop_on_error:
				break
			continue

		var edit_dict: Dictionary = edit
		var mode: String = str(edit_dict.get("mode", "replace")).strip_edges()
		var row: Dictionary = {}
		if mode == "patch":
			row = _patch_scene(edit_dict)
			any_link_change = any_link_change or _dsl_touches_scene_links(str(edit_dict.get("new_dsl", "")))
		else:
			row = _upsert_scene({
				"scene_id": str(edit_dict.get("scene_id", "")).strip_edges(),
				"scene_name": str(edit_dict.get("scene_name", "")).strip_edges(),
				"scene_note": str(edit_dict.get("scene_note", "")).strip_edges(),
				"folder": str(edit_dict.get("folder", "")).strip_edges(),
				"dsl": str(edit_dict.get("dsl", "")),
			})
			any_link_change = any_link_change or _dsl_touches_scene_links(str(edit_dict.get("dsl", "")))

		results.append(row)
		if bool(row.get("success", false)):
			success_count += 1
		elif stop_on_error:
			break

	var reachability: Dictionary = {}
	if any_link_change:
		reachability = _reachability_summary()

	return {
		"success": success_count == results.size(),
		"results": results,
		"patched_count": success_count,
		"failed_count": results.size() - success_count,
		"reachability": reachability,
	}


static func _patch_scene(edit: Dictionary) -> Dictionary:
	var scene_id: String = str(edit.get("scene_id", "")).strip_edges()
	var patch_result: Dictionary = ScriptToolsClass._set_scene_script({
		"scene_id": scene_id,
		"mode": "patch",
		"old_dsl": str(edit.get("old_dsl", "")),
		"new_dsl": str(edit.get("new_dsl", "")),
	})
	if not bool(patch_result.get("success", false)):
		return _scene_failure_result(scene_id, str(patch_result.get("error", "patch 失败")), patch_result.get("parse_errors", []), patch_result.get("warnings", []))

	var metadata_result: Dictionary = _apply_scene_metadata(scene_id, edit)
	if not bool(metadata_result.get("success", true)):
		return metadata_result

	return _scene_success_result(scene_id, true, patch_result, {})


static func _upsert_character(args: Dictionary) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var character_id: String = str(args.get("character_id", "")).strip_edges()
	var character_key: String = AVGCharacter.normalize_character_key(str(args.get("character_key", "")))
	var character_name: String = str(args.get("character_name", "")).strip_edges()
	var display_name: String = str(args.get("display_name", "")).strip_edges()
	var profile: String = str(args.get("profile", "")).strip_edges()
	if display_name.is_empty():
		display_name = character_name
	if not character_name.is_empty() and not ProjectToolsClass._is_valid_dsl_character_name(character_name):
		return {"success": false, "error": "character_name 必须是 ASCII 标识符，且以字母开头"}
	if not character_key.is_empty():
		var conflict: Resource = _find_character_by_key(project, character_key)
		if conflict != null and (character_id.is_empty() or str(conflict.character_id) != character_id):
			return {"success": false, "error": "character_key 已存在: %s" % character_key}

	var target: Resource = _find_character_by_id(project, character_id) if not character_id.is_empty() else null
	var occupied_shell: bool = false
	var created: bool = false
	if target == null and character_id.is_empty():
		target = _find_available_character_shell(project)
		occupied_shell = target != null
	if target == null and not character_id.is_empty():
		return {"success": false, "error": "角色不存在: %s" % character_id}

	var fields: Dictionary = {}
	if not character_key.is_empty():
		fields["character_key"] = character_key
	if not character_name.is_empty():
		fields["character_name"] = character_name
	if not display_name.is_empty():
		fields["display_name"] = display_name
	if not profile.is_empty():
		fields["profile"] = profile

	var write_result: Dictionary = {}
	if target != null:
		write_result = DBToolsClass._db_update({"type": "characters", "id": str(target.character_id), "fields": fields})
	else:
		if not fields.has("character_name"):
			fields["character_name"] = "Character"
		write_result = DBToolsClass._db_create({"type": "characters", "fields": fields})
		created = true

	if not bool(write_result.get("success", false)):
		return {"success": false, "error": write_result.get("error", "")}

	var written_id: String = str(write_result.get("id", str(target.character_id if target != null else ""))).strip_edges()
	var written: Resource = _find_character_by_id(project, written_id)
	return {
		"success": true,
		"character": _character_payload(written),
		"created": created,
		"occupied_shell": occupied_shell,
	}


static func _upsert_variable(args: Dictionary) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var variable_id: String = str(args.get("variable_id", "")).strip_edges()
	var variable_key: String = AVGVariable.normalize_key(str(args.get("variable_key", "")))
	var target: Resource = DBToolsClass._find_item_by_id(project.variables, "variable_id", variable_id) if not variable_id.is_empty() else null
	if target == null and not variable_key.is_empty():
		target = DBToolsClass._find_variable_by_key(project, variable_key)
	if target == null and variable_key.is_empty():
		return {"success": false, "error": "variable_key 不能为空"}

	var fields: Dictionary = {}
	if not variable_key.is_empty():
		fields["variable_key"] = variable_key
	if args.has("value_type"):
		fields["value_type"] = str(args.get("value_type", "int"))
	if args.has("default_value"):
		fields["default_value"] = args.get("default_value")
	if args.has("description"):
		fields["description"] = str(args.get("description", ""))

	var created: bool = false
	var write_result: Dictionary = {}
	if target != null:
		write_result = DBToolsClass._db_update({"type": "variables", "id": str(target.variable_id), "fields": fields})
	else:
		write_result = DBToolsClass._db_create({"type": "variables", "fields": fields})
		created = true
	if not bool(write_result.get("success", false)):
		return {"success": false, "error": write_result.get("error", "")}

	var written_id: String = str(write_result.get("id", str(target.variable_id if target != null else ""))).strip_edges()
	var written: Resource = DBToolsClass._find_item_by_id(project.variables, "variable_id", written_id)
	return {"success": true, "variable": DBToolsClass._resource_to_dict(written, "variables"), "created": created}


static func _upsert_event(args: Dictionary) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var dsl: String = str(args.get("dsl", ""))
	if args.has("dsl") and not dsl.strip_edges().is_empty():
		var parse_check: Dictionary = _parse_dsl(dsl)
		if not bool(parse_check.get("success", false)):
			return {
				"success": false,
				"parse_errors": parse_check.get("errors", []),
				"warnings": parse_check.get("warnings", []),
				"error": "DSL 解析失败",
			}

	var event_id: String = str(args.get("event_id", "")).strip_edges()
	var target: Resource = DBToolsClass._find_item_by_id(project.events, "event_id", event_id) if not event_id.is_empty() else null
	var fields: Dictionary = {}
	if args.has("event_name"):
		fields["event_name"] = str(args.get("event_name", "")).strip_edges()
	elif target == null:
		fields["event_name"] = "Event"
	if args.has("dsl"):
		fields["dsl"] = dsl

	var created: bool = false
	var write_result: Dictionary = {}
	if target != null:
		write_result = DBToolsClass._db_update({"type": "events", "id": event_id, "fields": fields})
	else:
		write_result = DBToolsClass._db_create({"type": "events", "fields": fields})
		created = true
	if not bool(write_result.get("success", false)):
		return {"success": false, "error": write_result.get("error", "")}

	var written_id: String = str(write_result.get("id", event_id)).strip_edges()
	var written: Resource = DBToolsClass._find_item_by_id(project.events, "event_id", written_id)
	var parse_warnings: Array = []
	if args.has("dsl"):
		parse_warnings = _parse_dsl(dsl).get("warnings", [])
	return {
		"success": true,
		"event": DBToolsClass._resource_to_dict(written, "events"),
		"created": created,
		"parse_errors": [],
		"warnings": parse_warnings,
		"auto_created_variable_keys": write_result.get("auto_created_variable_keys", []),
	}


static func _extract_scene_fields(args: Dictionary, for_create: bool) -> Dictionary:
	var fields: Dictionary = {}
	for key in ["scene_name", "scene_note", "folder"]:
		if args.has(key):
			var value: String = str(args.get(key, "")).strip_edges()
			if not value.is_empty() or not for_create:
				fields[key] = value
	if for_create:
		if not fields.has("scene_name"):
			var scene_id: String = str(args.get("scene_id", "")).strip_edges()
			fields["scene_name"] = scene_id if not scene_id.is_empty() else "New Scene"
		if not fields.has("scene_note"):
			fields["scene_note"] = "WorkOrderAgent 自动创建场景"
	return fields


static func _apply_scene_metadata(scene_id: String, args: Dictionary) -> Dictionary:
	var fields: Dictionary = _extract_scene_fields(args, false)
	if fields.is_empty():
		return {"success": true}
	var update_result: Dictionary = DBToolsClass._db_update({"type": "scenes", "id": scene_id, "fields": fields})
	if not bool(update_result.get("success", false)):
		return {"success": false, "scene_id": scene_id, "changed": false, "error": update_result.get("error", "")}
	return {"success": true}


static func _scene_success_result(scene_id: String, changed: bool, script_result: Dictionary, reachability: Dictionary) -> Dictionary:
	return {
		"success": true,
		"scene_id": scene_id,
		"changed": changed,
		"parse_errors": script_result.get("parse_errors", []),
		"semantic_errors": script_result.get("semantic_errors", []),
		"warnings": script_result.get("warnings", []),
		"auto_created_variable_keys": script_result.get("auto_created_variable_keys", []),
		"auto_created_placeholder_scene_ids": script_result.get("auto_created_placeholder_scene_ids", []),
		"skipped_placeholder_scene_ids": script_result.get("skipped_placeholder_scene_ids", []),
		"reachability": reachability,
	}


static func _scene_failure_result(scene_id: String, error: String, parse_errors: Array, warnings: Array) -> Dictionary:
	return {
		"success": false,
		"scene_id": scene_id,
		"changed": false,
		"error": error,
		"parse_errors": parse_errors,
		"semantic_errors": [],
		"warnings": warnings,
		"auto_created_variable_keys": [],
		"auto_created_placeholder_scene_ids": [],
		"reachability": {},
	}


static func _parse_dsl(dsl: String) -> Dictionary:
	var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
	var parser = ParserClass.new()
	return parser.parse(dsl)


static func _find_scene(project: Resource, scene_id: String) -> Resource:
	if project == null or scene_id.is_empty() or not ("scenes" in project):
		return null
	return DBToolsClass._find_item_by_id(project.scenes, "scene_id", scene_id)


static func _set_initial_scene_without_save(project: Resource, scene_id: String) -> void:
	if project == null:
		return
	if not ("title_config" in project) or project.title_config == null:
		project.title_config = AVGTitleConfigClass.new()
	project.title_config.first_scene_id = scene_id


static func _reachability_summary() -> Dictionary:
	var reach_result: Dictionary = ProjectToolsClass._analyze_story_reachability({})
	if not bool(reach_result.get("success", false)):
		return {"success": false, "error": reach_result.get("error", "")}
	var data: Dictionary = reach_result.get("data", {})
	return {
		"success": true,
		"entry_scene_id": data.get("entry_scene_id", ""),
		"unreachable_scenes": data.get("unreachable_scenes", []),
		"warnings": data.get("warnings", []),
	}


static func _dsl_touches_scene_links(dsl: String) -> bool:
	var lowered: String = dsl.to_lower()
	return lowered.contains("scene.jump") or lowered.contains("jump_scene")


static func _find_character_by_id(project: Resource, character_id: String) -> Resource:
	if project == null or character_id.is_empty() or not ("characters" in project):
		return null
	return DBToolsClass._find_item_by_id(project.characters, "character_id", character_id)


static func _find_character_by_key(project: Resource, character_key: String) -> Resource:
	if project == null or character_key.is_empty() or not ("characters" in project):
		return null
	var normalized_key: String = AVGCharacter.normalize_character_key(character_key)
	for character in project.characters:
		if character == null:
			continue
		if AVGCharacter.normalize_character_key(str(character.character_key if "character_key" in character else "")) == normalized_key:
			return character
	return null


static func _find_available_character_shell(project: Resource) -> Resource:
	if project == null or not ("characters" in project):
		return null
	for character in project.characters:
		if character == null:
			continue
		if AVGCharacter.looks_like_template_shell(character):
			return character
	return null


static func _character_payload(character: Resource) -> Dictionary:
	if character == null:
		return {}
	return DBToolsClass._resource_to_dict(character, "characters")


static func _merge_dict(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[key] = source[key]
