class_name AVGDevDBTools extends RefCounted


const NARRATIVE_COMMANDS: Array[String] = [
	"DIALOGUE", "CHOICE", "LABEL", "JUMP_LABEL", "JUMP_SCENE",
	"SET_VARIABLE", "IF", "CHECK_VAR", "CALL_EVENT",
]
const PLACEHOLDER_SCENE_NOTE_PREFIX: String = "[AUTO PLACEHOLDER]"
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")


static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("db_list", "List all entries of a type: scenes/characters/variables/events", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"}
		},
		"required": ["type"]
	}, func(args: Dictionary) -> Variant: return _db_list(args), {
		"fields": ["success", "data", "count", "error"]
	})

	ai_service.register_tool("db_get", "Get full details of one entry. Scenes include Root DSL script", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"}
		},
		"required": ["type", "id"]
	}, func(args: Dictionary) -> Variant: return _db_get(args), {
		"fields": ["success", "data", "error"]
	})

	ai_service.register_tool("db_create", "Create new entry. Scenes may provide a custom scene_id; events/scenes accept dsl field, and undefined variable keys used in that DSL are auto-created with default 0.", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"fields": {"type": "object", "description": "entry field data"}
		},
		"required": ["type", "fields"]
	}, func(args: Dictionary) -> Variant: return _db_create(args), {
		"fields": ["success", "id", "name", "auto_created_variable_keys", "auto_created_placeholder_scene_ids", "skipped_placeholder_scene_ids", "error"]
	})

	ai_service.register_tool("db_update", "Partially update fields of an entry", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"},
			"fields": {"type": "object", "description": "fields to update"}
		},
		"required": ["type", "id", "fields"]
	}, func(args: Dictionary) -> Variant: return _db_update(args), {
		"fields": ["success", "id", "name", "auto_created_variable_keys", "auto_created_placeholder_scene_ids", "skipped_placeholder_scene_ids", "error"]
	})

	ai_service.register_tool("db_delete", "Delete an entry", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"}
		},
		"required": ["type", "id"]
	}, func(args: Dictionary) -> Variant: return _db_delete(args), {
		"fields": ["success", "id", "error"]
	})

	ai_service.register_tool("get_story_outline", "Get narrative-only text from all scenes (dialogue, choices, variables; no SFX/BGM/effects)", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _get_story_outline(args), {
		"fields": ["success", "data", "error"]
	})


static func register_read_only(ai_service: Node) -> void:
	ai_service.register_tool("db_list", "List all entries of a type: scenes/characters/variables/events", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"}
		},
		"required": ["type"]
	}, func(args: Dictionary) -> Variant: return _db_list(args), {
		"fields": ["success", "data", "count", "error"]
	})

	ai_service.register_tool("db_get", "Get full details of one entry. Scenes include Root DSL script", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"}
		},
		"required": ["type", "id"]
	}, func(args: Dictionary) -> Variant: return _db_get(args), {
		"fields": ["success", "data", "error"]
	})

	ai_service.register_tool("get_story_outline", "Get narrative-only text from all scenes (dialogue, choices, variables; no SFX/BGM/effects)", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _get_story_outline(args), {
		"fields": ["success", "data", "error"]
	})


# --- Public helpers (used by script_tools / project_tools) ---

static func get_project() -> Resource:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var sm: Node = tree.root.get_node_or_null("/root/StorageManager")
	if sm == null:
		return null
	return sm.current_project


static func get_autoload(aname: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/" + aname)


static func get_array(project: Resource, type: String) -> Array:
	match type:
		"scenes": return project.scenes
		"characters": return project.characters
		"variables": return project.variables
		"events": return project.events
		_: return []


static func get_id_field(type: String) -> String:
	match type:
		"scenes": return "scene_id"
		"characters": return "character_id"
		"variables": return "variable_id"
		"events": return "event_id"
		_: return ""


static func get_name_field(type: String) -> String:
	match type:
		"scenes": return "scene_name"
		"characters": return "character_name"
		"variables": return "variable_key"
		"events": return "event_name"
		_: return ""


static func find_root_node(scene: Resource) -> Resource:
	if not "nodes" in scene or scene.nodes == null:
		return null
	for node in scene.nodes:
		if node is AVGRootNode:
			return node
	if scene.nodes.size() > 0:
		return scene.nodes[0]
	return null


static func get_root_dsl(scene: Resource, project: Resource = null) -> String:
	var root: Resource = find_root_node(scene)
	if root == null:
		return ""
	if not "command_tabs" in root or root.command_tabs == null or root.command_tabs.is_empty():
		return ""
	var tab: Dictionary = root.command_tabs[0]
	var commands: Array = tab.get("commands", [])
	if commands.is_empty():
		return ""
	var serializer: AVGDSLSerializer = AVGDSLSerializer.new()
	return serializer.serialize(commands, 0, _build_variable_lookup(project))


static func is_placeholder_scene(scene: Resource) -> bool:
	if scene == null:
		return false
	var note: String = str(scene.scene_note if "scene_note" in scene else "").strip_edges()
	return note.begins_with(PLACEHOLDER_SCENE_NOTE_PREFIX)


static func clear_placeholder_marker_if_implemented(scene: Resource) -> void:
	if scene == null or not is_placeholder_scene(scene):
		return
	var root: Resource = find_root_node(scene)
	if root == null or not ("command_tabs" in root) or root.command_tabs == null or root.command_tabs.is_empty():
		return
	var commands: Array = (root.command_tabs[0] as Dictionary).get("commands", [])
	if commands.is_empty():
		return
	scene.scene_note = ""


static func ensure_placeholder_scenes_for_commands(project: Resource, source_scene: Resource, commands: Array) -> Dictionary:
	var result: Dictionary = {
		"created_scene_ids": [],
		"skipped_invalid_scene_ids": [],
	}
	if project == null or not ("scenes" in project):
		return result

	var target_scene_ids: Array[String] = collect_jump_scene_targets(commands)
	var source_scene_id: String = ""
	var source_folder: String = ""
	if source_scene != null:
		source_scene_id = str(source_scene.scene_id if "scene_id" in source_scene else "").strip_edges()
		source_folder = str(source_scene.folder if "folder" in source_scene else "").strip_edges()

	for target_scene_id in target_scene_ids:
		if target_scene_id.is_empty() or target_scene_id == source_scene_id:
			continue
		if _find_item_by_id(project.scenes, "scene_id", target_scene_id) != null:
			continue
		if not _is_valid_custom_id(target_scene_id):
			result["skipped_invalid_scene_ids"].append(target_scene_id)
			continue

		var placeholder_scene: AVGScene = AVGScene.new()
		placeholder_scene.scene_id = target_scene_id
		placeholder_scene.scene_name = target_scene_id
		placeholder_scene.folder = source_folder
		placeholder_scene.scene_note = "%s 由场景 %s 的跳转自动创建，待实现" % [
			PLACEHOLDER_SCENE_NOTE_PREFIX,
			source_scene_id if not source_scene_id.is_empty() else "unknown",
		]

		var root: Resource = AVGRootNodeClass.new()
		root.node_id = "node_001"
		root.node_name = "Root"
		root.command_tabs = [{
			"mode": 0,
			"condition_type": 0,
			"commands": [],
			"condition_commands": [],
		}]
		placeholder_scene.nodes = [root]
		project.scenes.append(placeholder_scene)
		result["created_scene_ids"].append(target_scene_id)

	return result


static func collect_jump_scene_targets(commands: Array) -> Array[String]:
	var targets: Array[String] = []
	_collect_jump_scene_targets_recursive(commands, targets)
	return targets


static func _collect_jump_scene_targets_recursive(commands: Array, targets: Array[String]) -> void:
	for cmd in commands:
		var command_type: String = ""
		var params: Dictionary = {}
		if cmd is Resource and "command_type" in cmd:
			command_type = str(cmd.command_type)
			params = cmd.params if cmd.params is Dictionary else {}
		elif cmd is Dictionary:
			command_type = str(cmd.get("command_type", ""))
			params = cmd.get("params", {})
		if command_type == "JUMP_SCENE":
			var scene_id: String = str(params.get("scene_id", "")).strip_edges()
			if not scene_id.is_empty() and not targets.has(scene_id):
				targets.append(scene_id)
		elif command_type == "IF":
			_collect_jump_scene_targets_recursive(params.get("if_commands", []), targets)
			_collect_jump_scene_targets_recursive(params.get("else_commands", []), targets)
		elif command_type == "CHOICE":
			for choice in params.get("choices", []):
				if choice is Dictionary:
					_collect_jump_scene_targets_recursive(choice.get("commands", []), targets)


# --- db_list ---

static func _db_list(args: Dictionary) -> Dictionary:
	var project: Resource = get_project()
	if project == null:
		return {"success": false, "error": "No project open"}
	var type: String = args.get("type", "")
	var arr: Array = get_array(project, type)
	var id_f: String = get_id_field(type)
	var name_f: String = get_name_field(type)
	var items: Array = []
	for item in arr:
		if item == null:
			continue
		var entry: Dictionary = {}
		if id_f in item:
			entry["id"] = item.get(id_f)
		if type == "variables":
			entry["name"] = AVGVariable.get_key(item)
		elif name_f in item:
			entry["name"] = item.get(name_f)
		if type == "characters":
			var character_key: String = AVGCharacter.normalize_character_key(str(item.character_key if "character_key" in item else ""))
			var is_placeholder_shell: bool = AVGCharacter.looks_like_template_shell(item)
			entry["key"] = character_key
			entry["occupied"] = not character_key.is_empty() or not is_placeholder_shell
			entry["profile"] = str(item.profile if "profile" in item else "").strip_edges()
		if type == "scenes" and "folder" in item:
			entry["folder"] = item.folder
		if type == "variables":
			entry["key"] = AVGVariable.get_key(item)
			entry["value_type"] = AVGVariable.get_value_type(item)
			entry["default_value"] = item.default_value if "default_value" in item else 0
		items.append(entry)
	return {"success": true, "data": items, "count": items.size()}


# --- db_get ---

static func _db_get(args: Dictionary) -> Dictionary:
	var project: Resource = get_project()
	if project == null:
		return {"success": false, "error": "No project open"}
	var type: String = args.get("type", "")
	var id: String = args.get("id", "")
	var arr: Array = get_array(project, type)
	var id_f: String = get_id_field(type)
	for item in arr:
		if item == null:
			continue
		if id_f in item and item.get(id_f) == id:
			var data: Dictionary = _resource_to_dict(item, type)
			if type == "scenes":
				data["root_dsl"] = get_root_dsl(item, project)
				data["dsl"] = data["root_dsl"]
			return {"success": true, "data": data}
	return {"success": false, "error": "%s '%s' not found" % [type, id]}


# --- db_create ---

static func _db_create(args: Dictionary) -> Dictionary:
	var project: Resource = get_project()
	if project == null:
		return {"success": false, "error": "No project open"}
	var type: String = args.get("type", "")
	var fields: Dictionary = args.get("fields", {})
	var arr: Array = get_array(project, type)
	match type:
		"scenes": return _create_scene(project, arr, fields)
		"characters": return _create_character(arr, fields)
		"variables": return _create_variable(project, arr, fields)
		"events": return _create_event(project, arr, fields)
		_: return {"success": false, "error": "Unknown type: " + type}


static func _create_scene(project: Resource, arr: Array, fields: Dictionary) -> Dictionary:
	var scene: AVGScene = AVGScene.new()
	var requested_scene_id: String = str(fields.get("scene_id", "")).strip_edges()
	if requested_scene_id.is_empty():
		scene.scene_id = AVGScene.next_available_id(arr)
	else:
		if not _is_valid_custom_id(requested_scene_id):
			return {"success": false, "error": "scene_id 格式非法。只允许字母、数字、下划线，且必须以字母开头"}
		if _find_item_by_id(arr, "scene_id", requested_scene_id) != null:
			return {"success": false, "error": "scene_id 已存在: " + requested_scene_id}
		scene.scene_id = requested_scene_id
	scene.scene_name = fields.get("scene_name", fields.get("name", "New Scene"))
	scene.folder = fields.get("folder", "")
	scene.scene_note = fields.get("scene_note", "")
	var root: AVGRootNode = AVGRootNode.new()
	root.node_id = "node_001"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	scene.nodes = [root]
	var dsl: String = fields.get("dsl", "")
	if not dsl.is_empty():
		var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
		var parser = ParserClass.new()
		var result: Dictionary = parser.parse(dsl)
		if result.success:
			var ensure_result: Dictionary = ensure_variables_for_commands(project, result.commands)
			root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": result.commands, "condition_commands": []}]
			scene.set_meta("auto_created_variable_keys", ensure_result.get("created_keys", []))
		else:
			return {"success": false, "error": "DSL parse error: " + str(result.errors)}
	arr.append(scene)
	var placeholder_result: Dictionary = {}
	if not dsl.is_empty():
		placeholder_result = ensure_placeholder_scenes_for_commands(project, scene, root.command_tabs[0].get("commands", []))
		clear_placeholder_marker_if_implemented(scene)
	var created_keys: Array = scene.get_meta("auto_created_variable_keys", [])
	scene.remove_meta("auto_created_variable_keys")
	return {
		"success": true,
		"id": scene.scene_id,
		"name": scene.scene_name,
		"auto_created_variable_keys": created_keys,
		"auto_created_placeholder_scene_ids": placeholder_result.get("created_scene_ids", []),
		"skipped_placeholder_scene_ids": placeholder_result.get("skipped_invalid_scene_ids", []),
	}


static func _create_character(arr: Array, fields: Dictionary) -> Dictionary:
	var c: AVGCharacter = AVGCharacter.new()
	c.character_id = AVGCharacter.make_id(_next_slot(arr, "char_", 5))
	c.character_key = AVGCharacter.normalize_character_key(str(fields.get("character_key", fields.get("key", ""))))
	c.character_name = fields.get("character_name", fields.get("name", "Character"))
	c.display_name = fields.get("display_name", "")
	c.profile = fields.get("profile", "")
	arr.append(c)
	return {"success": true, "id": c.character_id, "name": c.character_name}


static func _create_variable(project: Resource, arr: Array, fields: Dictionary) -> Dictionary:
	var v: AVGVariable = AVGVariable.new()
	var normalized_fields: Dictionary = _normalize_variable_fields(fields)
	var requested_key: String = str(normalized_fields.get("variable_key", "")).strip_edges()
	if requested_key.is_empty():
		return {"success": false, "error": "variable_key is required"}
	if _find_variable_by_key(project, requested_key) != null:
		return {"success": false, "error": "Variable key already exists: " + requested_key}
	v.variable_id = AVGVariable.make_id(_next_slot(arr, "var_", 4))
	AVGVariable.apply_key(v, requested_key)
	v.value_type = normalized_fields.get("value_type", AVGVariable.VALUE_TYPE_INT)
	v.default_value = normalized_fields.get("default_value", AVGVariable.make_default_value_for_type(v.value_type))
	v.description = normalized_fields.get("description", "")
	arr.append(v)
	return {"success": true, "id": v.variable_id, "name": v.variable_key, "key": v.variable_key}


static func _create_event(project: Resource, arr: Array, fields: Dictionary) -> Dictionary:
	var ev: AVGEvent = AVGEvent.new()
	ev.event_id = AVGEvent.make_id(_next_slot(arr, "event_", 6))
	ev.event_name = fields.get("event_name", fields.get("name", "New Event"))
	var dsl: String = fields.get("dsl", "")
	if not dsl.is_empty():
		var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
		var parser = ParserClass.new()
		var result: Dictionary = parser.parse(dsl)
		if result.success:
			var ensure_result: Dictionary = ensure_variables_for_commands(project, result.commands)
			ev.commands = result.commands
			ev.set_meta("auto_created_variable_keys", ensure_result.get("created_keys", []))
		else:
			return {"success": false, "error": "DSL parse error: " + str(result.errors)}
	arr.append(ev)
	var created_keys: Array = ev.get_meta("auto_created_variable_keys", [])
	ev.remove_meta("auto_created_variable_keys")
	return {"success": true, "id": ev.event_id, "name": ev.event_name, "auto_created_variable_keys": created_keys}


static func _next_slot(arr: Array, prefix: String, prefix_len: int) -> int:
	var used: Array[int] = []
	for item in arr:
		if item == null:
			continue
		var id_val: String = ""
		if "character_id" in item: id_val = item.character_id
		elif "variable_id" in item: id_val = item.variable_id
		elif "event_id" in item: id_val = item.event_id
		if id_val.begins_with(prefix):
			var ns: String = id_val.substr(prefix_len)
			if ns.is_valid_int():
				used.append(ns.to_int())
	used.sort()
	var n: int = 1
	for u in used:
		if u == n: n += 1
		elif u > n: break
	return n


# --- db_update ---

static func _db_update(args: Dictionary) -> Dictionary:
	var project: Resource = get_project()
	if project == null:
		return {"success": false, "error": "No project open"}
	var type: String = args.get("type", "")
	var id: String = args.get("id", "")
	var fields: Dictionary = args.get("fields", {})
	var arr: Array = get_array(project, type)
	var id_f: String = get_id_field(type)
	for item in arr:
		if item == null:
			continue
		if id_f in item and item.get(id_f) == id:
			if type == "scenes" and fields.has("root_dsl") and not fields.has("dsl"):
				fields["dsl"] = fields.get("root_dsl", "")
				fields.erase("root_dsl")
			if type == "scenes" and fields.has("dsl"):
				var root: Resource = find_root_node(item)
				if root == null:
					return {"success": false, "error": "Scene has no root node"}
				var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
				var parser = ParserClass.new()
				var result: Dictionary = parser.parse(fields.get("dsl", ""))
				if not result.success:
					return {"success": false, "error": "DSL parse error: " + str(result.errors)}
				var ensure_result: Dictionary = ensure_variables_for_commands(project, result.commands)
				root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": result.commands, "condition_commands": []}]
				item.set_meta("auto_created_variable_keys", ensure_result.get("created_keys", []))
				var placeholder_result: Dictionary = ensure_placeholder_scenes_for_commands(project, item, result.commands)
				item.set_meta("auto_created_placeholder_scene_ids", placeholder_result.get("created_scene_ids", []))
				item.set_meta("skipped_placeholder_scene_ids", placeholder_result.get("skipped_invalid_scene_ids", []))
				clear_placeholder_marker_if_implemented(item)
				fields.erase("dsl")
			elif type == "events" and fields.has("dsl"):
				var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
				var parser = ParserClass.new()
				var result: Dictionary = parser.parse(fields.get("dsl", ""))
				if not result.success:
					return {"success": false, "error": "DSL parse error: " + str(result.errors)}
				var ensure_result: Dictionary = ensure_variables_for_commands(project, result.commands)
				item.commands = result.commands
				item.set_meta("auto_created_variable_keys", ensure_result.get("created_keys", []))
				fields.erase("dsl")
			if fields.has(id_f):
				var requested_id: String = str(fields.get(id_f, "")).strip_edges()
				if not requested_id.is_empty() and requested_id != id:
					return {"success": false, "error": "%s 不能通过 db_update 修改；请在 db_create 时指定，或继续使用原 ID '%s'" % [id_f, id]}
				fields.erase(id_f)
			# Normalize short aliases to actual field names
			var name_f: String = get_name_field(type)
			if fields.has("name") and not fields.has(name_f):
				fields[name_f] = fields["name"]
				fields.erase("name")
			if type == "characters":
				if fields.has("key") and not fields.has("character_key"):
					fields["character_key"] = fields["key"]
					fields.erase("key")
				if fields.has("character_key"):
					fields["character_key"] = AVGCharacter.normalize_character_key(str(fields.get("character_key", "")))
			if type == "variables":
				fields = _normalize_variable_fields(fields)
				if fields.has("variable_key"):
					var requested_key: String = str(fields.get("variable_key", "")).strip_edges()
					var conflict: Resource = _find_variable_by_key(project, requested_key)
					if conflict != null and conflict != item:
						return {"success": false, "error": "Variable key already exists: " + requested_key}
			var applied_field_count: int = 0
			for key in fields:
				if key == id_f: continue
				if key in item:
					item.set(key, fields[key])
					applied_field_count += 1
			if applied_field_count == 0 and not fields.is_empty():
				return {"success": false, "error": "未识别或未应用任何可更新字段: %s" % str(fields.keys())}
			if type == "variables":
				AVGVariable.apply_key(item, AVGVariable.get_key(item))
			var created_keys: Array = item.get_meta("auto_created_variable_keys", [])
			item.remove_meta("auto_created_variable_keys")
			var placeholder_scene_ids: Array = item.get_meta("auto_created_placeholder_scene_ids", [])
			item.remove_meta("auto_created_placeholder_scene_ids")
			var skipped_placeholder_scene_ids: Array = item.get_meta("skipped_placeholder_scene_ids", [])
			item.remove_meta("skipped_placeholder_scene_ids")
			return {
				"success": true,
				"id": id,
				"auto_created_variable_keys": created_keys,
				"auto_created_placeholder_scene_ids": placeholder_scene_ids,
				"skipped_placeholder_scene_ids": skipped_placeholder_scene_ids,
			}
	return {"success": false, "error": "%s '%s' not found" % [type, id]}


static func _find_item_by_id(arr: Array, id_field: String, target_id: String) -> Variant:
	for item in arr:
		if item == null:
			continue
		if id_field in item and str(item.get(id_field)).strip_edges() == target_id:
			return item
	return null


static func _is_valid_custom_id(raw_id: String) -> bool:
	var id_text: String = raw_id.strip_edges()
	if id_text.is_empty():
		return false
	for i in id_text.length():
		var codepoint: int = id_text.unicode_at(i)
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


# --- db_delete ---

static func _db_delete(args: Dictionary) -> Dictionary:
	var project: Resource = get_project()
	if project == null:
		return {"success": false, "error": "No project open"}
	var type: String = args.get("type", "")
	var id: String = args.get("id", "")
	var arr: Array = get_array(project, type)
	var id_f: String = get_id_field(type)
	for i in range(arr.size()):
		var item: Variant = arr[i]
		if item == null: continue
		if id_f in item and item.get(id_f) == id:
			arr.remove_at(i)
			return {"success": true, "id": id}
	return {"success": false, "error": "%s '%s' not found" % [type, id]}


# --- get_story_outline ---

static func _get_story_outline(_args: Dictionary) -> Dictionary:
	var project: Resource = get_project()
	if project == null:
		return {"success": false, "error": "No project open"}
	var serializer: AVGDSLSerializer = AVGDSLSerializer.new()
	var variable_lookup: Dictionary = _build_variable_lookup(project)
	var outline: String = ""
	for scene in project.scenes:
		if scene == null:
			continue
		var sname: String = scene.scene_name if "scene_name" in scene else ""
		var sid: String = scene.scene_id if "scene_id" in scene else ""
		outline += "=== Scene: %s (%s) ===\n" % [sname, sid]
		var root: Resource = find_root_node(scene)
		if root != null and "command_tabs" in root and root.command_tabs.size() > 0:
			var tab: Dictionary = root.command_tabs[0]
			var cmds: Array = tab.get("commands", [])
			var narr: Array = _filter_narrative(cmds)
			if narr.size() > 0:
				outline += serializer.serialize(narr, 0, variable_lookup) + "\n"
			else:
				outline += "(empty)\n"
		else:
			outline += "(empty)\n"
		outline += "\n"
	if outline.is_empty():
		outline = "(no scenes)"
	return {"success": true, "data": outline}


static func _filter_narrative(commands: Array) -> Array:
	var result: Array = []
	for cmd in commands:
		if cmd == null: continue
		var ct: String = ""
		var p: Dictionary = {}
		if cmd is Resource and "command_type" in cmd:
			ct = cmd.command_type
			p = cmd.params if cmd.params != null else {}
		elif cmd is Dictionary:
			ct = cmd.get("command_type", "")
			p = cmd.get("params", {})
		else:
			continue
		if ct not in NARRATIVE_COMMANDS: continue
		if ct == "IF":
			var fp: Dictionary = p.duplicate()
			if p.has("if_commands"):
				fp["if_commands"] = _filter_narrative(p.if_commands)
			if p.has("else_commands"):
				fp["else_commands"] = _filter_narrative(p.else_commands)
			result.append(AVGCommand.new(ct, fp))
		elif ct == "CHOICE":
			var fp: Dictionary = p.duplicate()
			if p.has("choices"):
				var fc: Array = []
				for ch in p.choices:
					var cd: Dictionary = ch.duplicate() if ch is Dictionary else {}
					if cd.has("commands"):
						cd["commands"] = _filter_narrative(cd.commands)
					fc.append(cd)
				fp["choices"] = fc
			result.append(AVGCommand.new(ct, fp))
		else:
			result.append(cmd)
	return result


static func _build_variable_lookup(project: Resource) -> Dictionary:
	var lookup: Dictionary = {}
	if project == null or not "variables" in project or project.variables == null:
		return lookup
	for variable in project.variables:
		if variable == null:
			continue
		var variable_id: String = str(variable.variable_id if "variable_id" in variable else "").strip_edges()
		var variable_key: String = AVGVariable.get_key(variable)
		if variable_id.is_empty() or variable_key.is_empty():
			continue
		lookup[variable_id] = variable_key
	return lookup


static func _normalize_variable_fields(fields: Dictionary) -> Dictionary:
	var normalized: Dictionary = fields.duplicate(true)
	var raw_key: String = str(normalized.get("variable_key", normalized.get("variable_name", normalized.get("name", "")))).strip_edges()
	if not raw_key.is_empty():
		var normalized_key: String = AVGVariable.normalize_key(raw_key)
		normalized["variable_key"] = normalized_key
		normalized["variable_name"] = normalized_key
	var has_default_value: bool = normalized.has("default_value")
	var resolved_type: String = AVGVariable.normalize_value_type(normalized.get("value_type", ""), normalized.get("default_value", null))
	normalized["value_type"] = resolved_type
	if has_default_value:
		normalized["default_value"] = AVGVariable.coerce_storage_value(normalized.get("default_value", null), resolved_type)
	elif resolved_type == AVGVariable.VALUE_TYPE_STRING:
		normalized["default_value"] = ""
	return normalized


static func _find_variable_by_key(project: Resource, variable_key: String) -> Resource:
	if project == null or not "variables" in project or project.variables == null:
		return null
	var normalized_key: String = AVGVariable.normalize_key(variable_key)
	for variable in project.variables:
		if variable == null:
			continue
		if AVGVariable.get_key(variable) == normalized_key:
			return variable
	return null


static func ensure_variables_for_commands(project: Resource, commands: Array) -> Dictionary:
	if project == null:
		return {"created": [], "created_keys": []}
	if not "variables" in project or project.variables == null:
		project.variables = []

	var variables: Array = project.variables
	var by_id: Dictionary = {}
	var by_key: Dictionary = {}
	for variable in variables:
		if variable == null:
			continue
		var variable_id: String = str(variable.variable_id if "variable_id" in variable else "").strip_edges()
		var variable_key: String = AVGVariable.get_key(variable)
		if variable_id.is_empty() or variable_key.is_empty():
			continue
		AVGVariable.apply_key(variable, variable_key)
		by_id[variable_id] = variable
		by_key[variable_key] = variable

	var created: Array[Dictionary] = []
	_ensure_variables_in_command_list(commands, variables, by_id, by_key, created)

	var created_keys: Array[String] = []
	for entry in created:
		created_keys.append(str(entry.get("key", "")))
	return {"created": created, "created_keys": created_keys}


static func _ensure_variables_in_command_list(commands: Array, project_variables: Array, by_id: Dictionary, by_key: Dictionary, created: Array[Dictionary]) -> void:
	for command in commands:
		if command == null:
			continue

		var command_type: String = ""
		var params: Dictionary = {}
		if command is Resource and "command_type" in command:
			command_type = str(command.command_type)
			params = command.params if command.params is Dictionary else {}
		elif command is Dictionary:
			command_type = str(command.get("command_type", ""))
			params = command.get("params", {})
		else:
			continue

		match command_type:
			"SET_VARIABLE":
				_ensure_variable_ref(params, "variable_id", "variable_key", project_variables, by_id, by_key, created)
				if str(params.get("value_source", "constant")) == "constant":
					_infer_auto_created_variable_type(params, "variable_id", "variable_key", params.get("value", 0), by_id, by_key, created)
				if str(params.get("value_source", "constant")) == "variable":
					_ensure_variable_ref(params, "source_variable_id", "source_variable_key", project_variables, by_id, by_key, created)
			"CHECK_VAR":
				_ensure_variable_ref(params, "variable_id", "variable_key", project_variables, by_id, by_key, created)
				if str(params.get("value_source", "constant")) == "constant":
					_infer_auto_created_variable_type(params, "variable_id", "variable_key", params.get("value", 0), by_id, by_key, created)
				if str(params.get("value_source", "constant")) == "variable":
					_ensure_variable_ref(params, "source_variable_id", "source_variable_key", project_variables, by_id, by_key, created)
			"IF":
				_ensure_variables_in_command_list(params.get("condition_commands", []), project_variables, by_id, by_key, created)
				_ensure_variables_in_command_list(params.get("if_condition_commands", []), project_variables, by_id, by_key, created)
				_ensure_variables_in_command_list(params.get("else_condition_commands", []), project_variables, by_id, by_key, created)
				_ensure_variables_in_command_list(params.get("if_commands", []), project_variables, by_id, by_key, created)
				_ensure_variables_in_command_list(params.get("else_commands", []), project_variables, by_id, by_key, created)
			"CHOICE":
				for choice in params.get("choices", []):
					if choice is Dictionary:
						_ensure_variables_in_command_list(choice.get("condition_commands", []), project_variables, by_id, by_key, created)
						_ensure_variables_in_command_list(choice.get("commands", []), project_variables, by_id, by_key, created)


static func _ensure_variable_ref(params: Dictionary, id_field: String, key_field: String, project_variables: Array, by_id: Dictionary, by_key: Dictionary, created: Array[Dictionary]) -> void:
	if params == null:
		return

	var raw_id: String = str(params.get(id_field, "")).strip_edges()
	var raw_key: String = str(params.get(key_field, params.get("variable_name", ""))).strip_edges()

	if not raw_id.is_empty() and by_id.has(raw_id):
		var existing_by_id: Resource = by_id[raw_id]
		var resolved_key: String = AVGVariable.get_key(existing_by_id)
		params[id_field] = raw_id
		params[key_field] = resolved_key
		params["variable_name"] = resolved_key
		return

	if raw_key.is_empty() and not raw_id.is_empty():
		if raw_id.begins_with("var_"):
			raw_key = raw_id
		else:
			raw_key = AVGVariable.normalize_key(raw_id)
	if raw_key.is_empty():
		return

	var normalized_key: String = AVGVariable.normalize_key(raw_key)
	if by_key.has(normalized_key):
		var existing: Resource = by_key[normalized_key]
		params[id_field] = str(existing.variable_id if "variable_id" in existing else "")
		params[key_field] = normalized_key
		params["variable_name"] = normalized_key
		return

	var new_variable: AVGVariable = AVGVariable.new()
	new_variable.variable_id = AVGVariable.make_id(_next_slot(project_variables, "var_", 4))
	AVGVariable.apply_key(new_variable, normalized_key)
	new_variable.value_type = AVGVariable.VALUE_TYPE_INT
	new_variable.default_value = 0
	new_variable.description = "Auto-created from DSL"
	project_variables.append(new_variable)
	by_id[new_variable.variable_id] = new_variable
	by_key[normalized_key] = new_variable
	created.append({"id": new_variable.variable_id, "key": normalized_key})

	params[id_field] = new_variable.variable_id
	params[key_field] = normalized_key
	params["variable_name"] = normalized_key


static func _resource_to_dict(item: Resource, type: String) -> Dictionary:
	var data: Dictionary = {}
	var id_f: String = get_id_field(type)
	var name_f: String = get_name_field(type)
	if id_f in item: data["id"] = item.get(id_f)
	if type == "variables":
		data["name"] = AVGVariable.get_key(item)
	elif name_f in item:
		data["name"] = item.get(name_f)
	match type:
		"scenes":
			if "folder" in item: data["folder"] = item.folder
			if "scene_note" in item: data["scene_note"] = item.scene_note
		"characters":
			if "character_key" in item: data["character_key"] = AVGCharacter.normalize_character_key(str(item.character_key))
			if "display_name" in item: data["display_name"] = item.display_name
			if "profile" in item: data["profile"] = item.profile
			data["placeholder_shell"] = AVGCharacter.looks_like_template_shell(item)
			data["occupied"] = not str(data.get("character_key", "")).strip_edges().is_empty() or not bool(data.get("placeholder_shell", false))
		"variables":
			data["key"] = AVGVariable.get_key(item)
			data["value_type"] = AVGVariable.get_value_type(item)
			if "default_value" in item: data["default_value"] = item.default_value
			if "description" in item: data["description"] = item.description
		"events":
			if "commands" in item and item.commands.size() > 0:
				var s: AVGDSLSerializer = AVGDSLSerializer.new()
				data["dsl"] = s.serialize(item.commands, 0, _build_variable_lookup(get_project()))
	return data


static func _infer_auto_created_variable_type(params: Dictionary, id_field: String, key_field: String, literal_value: Variant, by_id: Dictionary, by_key: Dictionary, created: Array[Dictionary]) -> void:
	if not (literal_value is String):
		return
	var variable: Resource = _resolve_variable_from_params(params, id_field, key_field, by_id, by_key)
	if variable == null or not _was_created_in_current_pass(variable, created):
		return
	variable.value_type = AVGVariable.VALUE_TYPE_STRING
	variable.default_value = ""


static func _resolve_variable_from_params(params: Dictionary, id_field: String, key_field: String, by_id: Dictionary, by_key: Dictionary) -> Resource:
	var variable_id: String = str(params.get(id_field, "")).strip_edges()
	if not variable_id.is_empty() and by_id.has(variable_id):
		return by_id[variable_id]
	var variable_key: String = AVGVariable.normalize_key(str(params.get(key_field, params.get("variable_name", ""))).strip_edges())
	if not variable_key.is_empty() and by_key.has(variable_key):
		return by_key[variable_key]
	return null


static func _was_created_in_current_pass(variable: Resource, created: Array[Dictionary]) -> bool:
	if variable == null or not ("variable_id" in variable):
		return false
	var variable_id: String = str(variable.variable_id).strip_edges()
	for entry in created:
		if str(entry.get("id", "")).strip_edges() == variable_id:
			return true
	return false
