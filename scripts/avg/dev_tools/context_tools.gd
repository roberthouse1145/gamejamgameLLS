class_name AVGDevContextTools extends RefCounted

const KBToolsClass = preload("res://scripts/avg/dev_tools/kb_tools.gd")
const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")
const ScriptToolsClass = preload("res://scripts/avg/dev_tools/script_tools.gd")
const ProjectToolsClass = preload("res://scripts/avg/dev_tools/project_tools.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")


static func register_gather_scene_context(ai_service: Node) -> void:
	ai_service.register_tool("gather_scene_context", "批量收集 Writer/Executor 常用上下文：可一次获取指定场景的 DSL、相关 KB 文档、资源 alias、角色名册、变量列表、场景目录和可达性摘要。当前变量系统只允许 int / string：布尔请用 0/1，float 会被截断成 int。混用 string 和 int 做比较时，set_scene_script 会给 warning，运行时会把空字符串视为 0、非空字符串视为 1。优先使用此工具，避免连续调用多个只读工具。", {
		"type": "object",
		"properties": {
			"scene_ids": {
				"type": "array",
				"items": {"type": "string"},
				"description": "可选。需要读取 DSL 的 scene_id 列表。"
			},
			"kb_category": {
				"type": "string",
				"enum": ["world", "characters", "story", "notes"],
				"description": "可选。要读取的 KB 分类。"
			},
			"kb_doc_ids": {
				"type": "array",
				"items": {"type": "string"},
				"description": "可选。要精确读取的 KB doc_id 列表。"
			},
			"kb_tags": {
				"type": "array",
				"items": {"type": "string"},
				"description": "可选。KB 标签过滤。"
			},
			"asset_categories": {
				"type": "array",
				"items": {"type": "string", "enum": ["backgrounds", "images", "cg", "bgm", "sfx", "characters"]},
				"description": "可选。需要一并返回的资源类别列表。"
			},
			"include_characters": {
				"type": "boolean",
				"description": "是否返回角色名册（character_id / character_name / display_name / expressions / outfits）。"
			},
			"include_variables": {
				"type": "boolean",
				"description": "是否返回变量列表。"
			},
			"include_scene_catalog": {
				"type": "boolean",
				"description": "是否返回场景目录摘要。"
			},
			"include_reachability": {
				"type": "boolean",
				"description": "是否返回可达性摘要。通常在修跳转或补开场时使用。"
			}
		}
	}, func(args: Dictionary) -> Variant: return _gather_scene_context(args), {
		"fields": ["success", "data", "error"]
	})


static func register_batch_patch_scene_scripts(ai_service: Node) -> void:
	ai_service.register_tool("batch_patch_scene_scripts", "批量修改多个场景脚本。每个 patch 可以是 patch 模式（old_dsl/new_dsl）或 replace 模式（dsl）。适合批量修跳转、批量替换资源引用、批量修表情名。", {
		"type": "object",
		"properties": {
			"patches": {
				"type": "array",
				"description": "批量脚本修改列表。",
				"items": {
					"type": "object",
					"properties": {
						"scene_id": {"type": "string", "description": "目标场景 ID"},
						"mode": {"type": "string", "enum": ["patch", "replace"], "description": "patch=局部替换，replace=整段替换"},
						"old_dsl": {"type": "string", "description": "patch 模式：待替换旧片段"},
						"new_dsl": {"type": "string", "description": "patch 模式：替换后新片段"},
						"dsl": {"type": "string", "description": "replace 模式：完整 DSL"}
					},
					"required": ["scene_id", "mode"]
				}
			},
			"stop_on_error": {
				"type": "boolean",
				"description": "若为 true，某个 patch 失败后立即停止。默认 false。"
			}
		},
		"required": ["patches"]
	}, func(args: Dictionary) -> Variant: return _batch_patch_scene_scripts(args), {
		"fields": ["success", "results", "patched_count", "failed_count", "error"]
	})


static func _gather_scene_context(args: Dictionary) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {"success": false, "error": "未打开项目"}

	var data: Dictionary = {}
	var scene_ids: Array = args.get("scene_ids", [])
	if scene_ids is Array and not scene_ids.is_empty():
		data["scenes"] = _collect_scenes(project, scene_ids)

	var kb_doc_ids: Array = args.get("kb_doc_ids", [])
	var kb_category: String = str(args.get("kb_category", "")).strip_edges()
	var kb_tags: Array = args.get("kb_tags", [])
	var kb_payload := _collect_kb_payload(kb_doc_ids, kb_category, kb_tags)
	if not kb_payload.is_empty():
		data["kb"] = kb_payload

	var asset_categories: Array = args.get("asset_categories", [])
	if asset_categories is Array and not asset_categories.is_empty():
		data["assets"] = _collect_assets(asset_categories)

	if bool(args.get("include_characters", false)):
		data["characters"] = _collect_character_roster(project)

	if bool(args.get("include_variables", false)):
		data["variables"] = _collect_variables(project)
		data["variable_system"] = {
			"value_types": [AVGVariableClass.VALUE_TYPE_INT, AVGVariableClass.VALUE_TYPE_STRING],
			"bool_encoding": "0_or_1",
			"float_policy": "coerce_to_int",
			"mixed_string_int_compare_runtime": {
				"empty_string": 0,
				"non_empty_string": 1,
			},
		}

	if bool(args.get("include_scene_catalog", false)):
		var catalog_result: Dictionary = ProjectToolsClass._list_scene_catalog({})
		if bool(catalog_result.get("success", false)):
			data["scene_catalog"] = catalog_result.get("data", [])
			data["entry_scene_id"] = catalog_result.get("entry_scene_id", "")
		else:
			data["scene_catalog_error"] = catalog_result.get("error", "")

	if bool(args.get("include_reachability", false)):
		var reachability_result: Dictionary = ProjectToolsClass._analyze_story_reachability({})
		if bool(reachability_result.get("success", false)):
			var reach_data: Dictionary = reachability_result.get("data", {})
			data["reachability"] = {
				"entry_scene_id": reach_data.get("entry_scene_id", ""),
				"unreachable_scene_ids": _extract_scene_ids(reach_data.get("unreachable_scenes", [])),
				"warnings": reach_data.get("warnings", []),
			}
		else:
			data["reachability_error"] = reachability_result.get("error", "")

	return {"success": true, "data": data}


static func _batch_patch_scene_scripts(args: Dictionary) -> Dictionary:
	var patches: Array = args.get("patches", [])
	if patches.is_empty():
		return {"success": false, "error": "patches 不能为空"}

	var stop_on_error: bool = bool(args.get("stop_on_error", false))
	var results: Array[Dictionary] = []
	var all_success: bool = true

	for patch in patches:
		if not (patch is Dictionary):
			results.append({"success": false, "error": "patch 条目必须是对象"})
			all_success = false
			if stop_on_error:
				break
			continue

		var patch_dict: Dictionary = patch
		var tool_args: Dictionary = {
			"scene_id": str(patch_dict.get("scene_id", "")).strip_edges(),
			"mode": str(patch_dict.get("mode", "patch")).strip_edges(),
		}
		if tool_args["mode"] == "replace":
			tool_args["dsl"] = str(patch_dict.get("dsl", ""))
		else:
			tool_args["old_dsl"] = str(patch_dict.get("old_dsl", ""))
			tool_args["new_dsl"] = str(patch_dict.get("new_dsl", ""))

		var patch_result: Dictionary = ScriptToolsClass._set_scene_script(tool_args)
		var row: Dictionary = {
			"scene_id": tool_args["scene_id"],
			"mode": tool_args["mode"],
			"success": bool(patch_result.get("success", false)),
		}
		if patch_result.has("message"):
			row["message"] = patch_result.get("message", "")
		if patch_result.has("error"):
			row["error"] = patch_result.get("error", "")
		results.append(row)
		if not bool(row.get("success", false)):
			all_success = false
			if stop_on_error:
				break

	return {
		"success": all_success,
		"results": results,
		"patched_count": _count_successes(results),
		"failed_count": results.size() - _count_successes(results),
	}


static func _collect_scenes(project: Resource, scene_ids: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw_scene_id in scene_ids:
		var scene_id: String = str(raw_scene_id).strip_edges()
		if scene_id.is_empty():
			continue
		var scene: Resource = DBToolsClass._find_item_by_id(project.scenes, "scene_id", scene_id)
		if scene == null:
			rows.append({"scene_id": scene_id, "missing": true})
			continue
		rows.append({
			"scene_id": scene_id,
			"scene_name": scene.scene_name if "scene_name" in scene else "",
			"scene_note": scene.scene_note if "scene_note" in scene else "",
			"folder": scene.folder if "folder" in scene else "",
			"is_placeholder": DBToolsClass.is_placeholder_scene(scene),
			"dsl": DBToolsClass.get_root_dsl(scene, project),
		})
	return rows


static func _collect_kb_payload(kb_doc_ids: Array, kb_category: String, kb_tags: Array) -> Dictionary:
	var payload: Dictionary = {}
	var docs: Array = []

	if kb_doc_ids is Array and not kb_doc_ids.is_empty():
		for raw_doc_id in kb_doc_ids:
			var doc_id: String = str(raw_doc_id).strip_edges()
			if doc_id.is_empty():
				continue
			var doc_result: Dictionary = KBToolsClass._kb_read({"doc_id": doc_id})
			if bool(doc_result.get("success", false)):
				docs.append(doc_result.get("data", {}))
			else:
				docs.append({"doc_id": doc_id, "missing": true, "error": doc_result.get("error", "")})
		payload["docs"] = docs
		return payload

	if kb_category.is_empty():
		return payload

	var category_result: Dictionary = KBToolsClass._kb_read({
		"category": kb_category,
		"tags": kb_tags if kb_tags is Array else [],
	})
	if bool(category_result.get("success", false)):
		payload["category"] = kb_category
		payload["docs"] = category_result.get("data", [])
	else:
		payload["category"] = kb_category
		payload["error"] = category_result.get("error", "")
	return payload


static func _collect_assets(asset_categories: Array) -> Dictionary:
	var result: Dictionary = {}
	var category_list: Array[String] = []
	for entry in asset_categories:
		var category: String = str(entry).strip_edges()
		if category.is_empty() or category_list.has(category):
			continue
		category_list.append(category)

	for category in category_list:
		var asset_result: Dictionary = ProjectToolsClass._list_assets({"category": category})
		if not bool(asset_result.get("success", false)):
			result[category + "_error"] = asset_result.get("error", "")
			continue
		var data: Dictionary = asset_result.get("data", {})
		for key in data.keys():
			if key == "alias_usage":
				continue
			result[key] = data[key]
	return result


static func _collect_character_roster(project: Resource) -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	if project == null or not ("characters" in project):
		return roster
	for character in project.characters:
		if character == null:
			continue
		var expressions: Array = []
		var outfits: Array = []
		if "sprites" in character and character.sprites is Dictionary:
			for expr_name in character.sprites.keys():
				var normalized_expr: String = str(expr_name)
				if "__" in normalized_expr:
					var parts: PackedStringArray = normalized_expr.split("__", false, 1)
					if parts.size() == 2:
						normalized_expr = str(parts[1])
				if not expressions.has(normalized_expr):
					expressions.append(normalized_expr)
		if "available_outfits" in character and character.available_outfits is Array:
			for outfit_name in character.available_outfits:
				var normalized_outfit: String = str(outfit_name)
				if not outfits.has(normalized_outfit):
					outfits.append(normalized_outfit)
		if "default_outfit" in character:
			var default_outfit: String = str(character.default_outfit)
			if not default_outfit.is_empty() and not outfits.has(default_outfit):
				outfits.append(default_outfit)
		roster.append({
			"character_id": character.character_id if "character_id" in character else "",
			"character_name": character.character_name if "character_name" in character else "",
			"display_name": character.display_name if "display_name" in character else "",
			"character_key": character.character_key if "character_key" in character else "",
			"profile": character.profile if "profile" in character else "",
			"expressions": expressions,
			"outfits": outfits,
		})
	return roster


static func _collect_variables(project: Resource) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if project == null or not ("variables" in project):
		return rows
	for variable in project.variables:
		if variable == null:
			continue
		rows.append({
			"variable_id": variable.variable_id if "variable_id" in variable else "",
			"variable_key": variable.variable_key if "variable_key" in variable else "",
			"display_name": variable.display_name if "display_name" in variable else "",
			"value_type": AVGVariableClass.get_value_type(variable),
			"default_value": variable.default_value if "default_value" in variable else 0,
		})
	return rows


static func _extract_scene_ids(rows: Array) -> Array[String]:
	var ids: Array[String] = []
	for row in rows:
		if row is Dictionary:
			var row_dict: Dictionary = row
			var scene_id: String = str(row_dict.get("scene_id", "")).strip_edges()
			if not scene_id.is_empty():
				ids.append(scene_id)
	return ids


static func _count_successes(results: Array[Dictionary]) -> int:
	var count: int = 0
	for row in results:
		if bool(row.get("success", false)):
			count += 1
	return count
