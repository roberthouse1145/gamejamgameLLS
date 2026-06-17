class_name AVGDevContextTools extends RefCounted

const KBToolsClass = preload("res://scripts/avg/dev_tools/kb_tools.gd")
const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")
const ScriptToolsClass = preload("res://scripts/avg/dev_tools/script_tools.gd")
const ProjectToolsClass = preload("res://scripts/avg/dev_tools/project_tools.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

const DEFAULT_INDEX_ITEM_LIMIT: int = 80
const INDEX_TEXT_PREVIEW_CHARS: int = 120


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


## 构建后台工单 Agent 的稳定项目索引前缀。
## 只包含定位信息，不包含 KB 正文或完整 DSL；全文仍由 kb_read/gather_scene_context 按需获取。
static func build_work_order_project_index(max_items_per_section: int = DEFAULT_INDEX_ITEM_LIMIT) -> String:
	var vars: Dictionary = build_work_order_project_index_vars(max_items_per_section)
	var prompt_manager: Node = _get_prompt_manager()
	if prompt_manager != null and prompt_manager.has_method("resolve_with_vars"):
		if not prompt_manager.has_method("has_prompt") or prompt_manager.has_prompt("work_order_project_index"):
			var resolved: String = str(prompt_manager.resolve_with_vars("work_order_project_index", vars)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return _build_work_order_project_index_fallback(vars)


static func build_work_order_project_index_vars(max_items_per_section: int = DEFAULT_INDEX_ITEM_LIMIT) -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return {
			"work_order_project_summary": "- 当前未打开 AVG 项目，索引不可用。",
			"work_order_kb_index": "- （无）",
			"work_order_scene_index": "- （无）",
			"work_order_character_index": "- （无）",
			"work_order_variable_index": "- （无）",
			"work_order_asset_index": "- （无）",
		}

	var project_name: String = str(project.project_name if "project_name" in project else "").strip_edges()
	var summary_lines: Array[String] = []
	if not project_name.is_empty():
		summary_lines.append("- project_name: %s" % project_name)
	summary_lines.append("- scenes=%d characters=%d variables=%d events=%d" % [
		(project.scenes.size() if "scenes" in project and project.scenes is Array else 0),
		(project.characters.size() if "characters" in project and project.characters is Array else 0),
		(project.variables.size() if "variables" in project and project.variables is Array else 0),
		(project.events.size() if "events" in project and project.events is Array else 0),
	])

	return {
		"work_order_project_summary": "\n".join(summary_lines).strip_edges(),
		"work_order_kb_index": "\n".join(_build_kb_index_lines(max_items_per_section)).strip_edges(),
		"work_order_scene_index": "\n".join(_build_scene_index_lines(project, max_items_per_section)).strip_edges(),
		"work_order_character_index": "\n".join(_build_character_index_lines(project, max_items_per_section)).strip_edges(),
		"work_order_variable_index": "\n".join(_build_variable_index_lines(project, max_items_per_section)).strip_edges(),
		"work_order_asset_index": "\n".join(_build_asset_index_lines(max_items_per_section)).strip_edges(),
	}


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


static func _build_kb_index_lines(limit: int) -> Array[String]:
	var read_result: Dictionary = KBToolsClass._kb_read({})
	if not bool(read_result.get("success", false)):
		return ["- KB 不可用：%s" % str(read_result.get("error", ""))]
	var docs: Array = read_result.get("data", [])
	var rows: Array[Dictionary] = []
	for doc in docs:
		if not (doc is Dictionary):
			continue
		var doc_dict: Dictionary = doc
		rows.append({
			"doc_id": str(doc_dict.get("doc_id", "")).strip_edges(),
			"title": str(doc_dict.get("title", "")).strip_edges(),
			"category": str(doc_dict.get("category", "")).strip_edges(),
			"doc_kind": str(doc_dict.get("doc_kind", "")).strip_edges(),
			"state": str(doc_dict.get("state", "")).strip_edges(),
			"tags": _sorted_string_array(doc_dict.get("tags", [])),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ak: String = "%s/%s/%s" % [a.get("category", ""), a.get("doc_id", ""), a.get("title", "")]
		var bk: String = "%s/%s/%s" % [b.get("category", ""), b.get("doc_id", ""), b.get("title", "")]
		return ak < bk
	)
	var lines: Array[String] = []
	for i in range(mini(limit, rows.size())):
		var row: Dictionary = rows[i]
		var tags: Array[String] = row.get("tags", [])
		var suffix: String = ""
		if not tags.is_empty():
			suffix = " tags=%s" % ", ".join(tags)
		lines.append("- %s | %s | %s | kind=%s state=%s%s" % [
			str(row.get("category", "")),
			str(row.get("doc_id", "")),
			str(row.get("title", "")),
			str(row.get("doc_kind", "")),
			str(row.get("state", "")),
			suffix,
		])
	_append_limit_notice(lines, rows.size(), limit)
	return _ensure_non_empty_lines(lines)


static func _build_scene_index_lines(project: Resource, limit: int) -> Array[String]:
	var rows: Array[Dictionary] = []
	if project != null and "scenes" in project and project.scenes is Array:
		for scene in project.scenes:
			if scene == null:
				continue
			var scene_id: String = str(scene.scene_id if "scene_id" in scene else "").strip_edges()
			rows.append({
				"scene_id": scene_id,
				"scene_name": str(scene.scene_name if "scene_name" in scene else "").strip_edges(),
				"folder": str(scene.folder if "folder" in scene else "").strip_edges(),
				"scene_note": _one_line(str(scene.scene_note if "scene_note" in scene else ""), INDEX_TEXT_PREVIEW_CHARS),
				"is_placeholder": DBToolsClass.is_placeholder_scene(scene),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("scene_id", "")) < str(b.get("scene_id", ""))
	)
	var lines: Array[String] = []
	for i in range(mini(limit, rows.size())):
		var row: Dictionary = rows[i]
		var flags: Array[String] = []
		if bool(row.get("is_placeholder", false)):
			flags.append("placeholder")
		var folder: String = str(row.get("folder", ""))
		if not folder.is_empty():
			flags.append("folder=%s" % folder)
		var suffix: String = ""
		if not flags.is_empty():
			suffix += " [%s]" % ", ".join(flags)
		var note: String = str(row.get("scene_note", ""))
		if not note.is_empty():
			suffix += " - %s" % note
		lines.append("- %s | %s%s" % [str(row.get("scene_id", "")), str(row.get("scene_name", "")), suffix])
	_append_limit_notice(lines, rows.size(), limit)
	return _ensure_non_empty_lines(lines)


static func _build_character_index_lines(project: Resource, limit: int) -> Array[String]:
	var rows: Array[Dictionary] = _collect_character_roster(project)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ak: String = "%s/%s" % [a.get("character_name", ""), a.get("character_id", "")]
		var bk: String = "%s/%s" % [b.get("character_name", ""), b.get("character_id", "")]
		return ak < bk
	)
	var lines: Array[String] = []
	for i in range(mini(limit, rows.size())):
		var row: Dictionary = rows[i]
		var expressions: Array[String] = _sorted_string_array(row.get("expressions", []))
		var outfits: Array[String] = _sorted_string_array(row.get("outfits", []))
		lines.append("- %s | %s | display=%s | key=%s | expressions=%s | outfits=%s" % [
			str(row.get("character_id", "")),
			str(row.get("character_name", "")),
			str(row.get("display_name", "")),
			str(row.get("character_key", "")),
			_join_or_dash(expressions),
			_join_or_dash(outfits),
		])
	_append_limit_notice(lines, rows.size(), limit)
	return _ensure_non_empty_lines(lines)


static func _build_variable_index_lines(project: Resource, limit: int) -> Array[String]:
	var rows: Array[Dictionary] = _collect_variables(project)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("variable_key", "")) < str(b.get("variable_key", ""))
	)
	var lines: Array[String] = []
	for i in range(mini(limit, rows.size())):
		var row: Dictionary = rows[i]
		lines.append("- %s | id=%s | type=%s | default=%s | display=%s" % [
			str(row.get("variable_key", "")),
			str(row.get("variable_id", "")),
			str(row.get("value_type", "")),
			str(row.get("default_value", "")),
			str(row.get("display_name", "")),
		])
	_append_limit_notice(lines, rows.size(), limit)
	return _ensure_non_empty_lines(lines)


static func _build_asset_index_lines(limit: int) -> Array[String]:
	var assets: Dictionary = _collect_assets(["backgrounds", "images", "cg", "bgm", "sfx"])
	if assets.is_empty():
		return ["- 当前没有可用资源索引，Writer 仍需调用 gather_scene_context 或 list_assets 确认资源。"]
	var sections: Array[String] = []
	var keys: Array[String] = [
		"background_aliases", "image_aliases", "cg_aliases", "bgm_aliases", "sfx_aliases",
		"backgrounds", "images", "cg", "bgm", "sfx",
	]
	for key in keys:
		if not assets.has(key):
			continue
		var items: Array[String] = _sorted_string_array(assets.get(key, []))
		if items.is_empty():
			continue
		sections.append("- %s: %s" % [key, _join_limited(items, limit)])
	return _ensure_non_empty_lines(sections)


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


static func _get_prompt_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PromptManager")


static func _build_work_order_project_index_fallback(vars: Dictionary) -> String:
	return "\n\n".join([
		"# 项目索引（稳定前缀）",
		"用途：帮助后台工单 Agent 快速定位 KB、角色、变量、场景与资源 alias。这里只是索引，不是全文事实来源；需要正文或完整 DSL 时再调用工具。",
		str(vars.get("work_order_project_summary", "")).strip_edges(),
		"## KB 文档索引\n\n%s" % str(vars.get("work_order_kb_index", "")).strip_edges(),
		"## 场景索引\n\n%s" % str(vars.get("work_order_scene_index", "")).strip_edges(),
		"## 角色索引\n\n%s" % str(vars.get("work_order_character_index", "")).strip_edges(),
		"## 变量索引\n\n%s" % str(vars.get("work_order_variable_index", "")).strip_edges(),
		"## 资源 Alias / 文件索引\n\n%s" % str(vars.get("work_order_asset_index", "")).strip_edges(),
	]).strip_edges()


static func _sorted_string_array(raw_items: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_items is Array:
		for item in raw_items:
			var text: String = str(item).strip_edges()
			if text.is_empty() or result.has(text):
				continue
			result.append(text)
	result.sort()
	return result


static func _join_or_dash(items: Array[String]) -> String:
	if items.is_empty():
		return "-"
	return ", ".join(items)


static func _join_limited(items: Array[String], limit: int) -> String:
	var clipped: Array[String] = []
	for i in range(mini(limit, items.size())):
		clipped.append(items[i])
	var text: String = ", ".join(clipped)
	if items.size() > limit:
		text += " ... (+%d more)" % (items.size() - limit)
	return text


static func _append_limit_notice(lines: Array[String], total_count: int, limit: int) -> void:
	if total_count > limit:
		lines.append("- ... (+%d more; use tools for the full list)" % (total_count - limit))


static func _ensure_non_empty_lines(lines: Array[String]) -> Array[String]:
	if lines.is_empty():
		return ["- （无）"]
	return lines


static func _one_line(text: String, max_chars: int) -> String:
	var normalized: String = text.replace("\r", " ").replace("\n", " ").strip_edges()
	while "  " in normalized:
		normalized = normalized.replace("  ", " ")
	if max_chars > 0 and normalized.length() > max_chars:
		return normalized.left(max_chars) + "..."
	return normalized
