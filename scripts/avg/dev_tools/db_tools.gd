class_name AVGDevDBTools extends RefCounted


const NARRATIVE_COMMANDS: Array[String] = [
	"DIALOGUE", "CHOICE", "LABEL", "JUMP_LABEL", "JUMP_SCENE",
	"SET_VARIABLE", "IF", "CHECK_VAR", "CALL_EVENT",
]


static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("db_list", "List all entries of a type: scenes/characters/variables/events", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"}
		},
		"required": ["type"]
	}, func(args: Dictionary) -> Variant: return _db_list(args))

	ai_service.register_tool("db_get", "Get full details of one entry. Scenes include Root DSL script", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"}
		},
		"required": ["type", "id"]
	}, func(args: Dictionary) -> Variant: return _db_get(args))

	ai_service.register_tool("db_create", "Create new entry with auto-assigned ID. Scenes accept dsl field", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"fields": {"type": "object", "description": "entry field data"}
		},
		"required": ["type", "fields"]
	}, func(args: Dictionary) -> Variant: return _db_create(args))

	ai_service.register_tool("db_update", "Partially update fields of an entry", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"},
			"fields": {"type": "object", "description": "fields to update"}
		},
		"required": ["type", "id", "fields"]
	}, func(args: Dictionary) -> Variant: return _db_update(args))

	ai_service.register_tool("db_delete", "Delete an entry", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"}
		},
		"required": ["type", "id"]
	}, func(args: Dictionary) -> Variant: return _db_delete(args))

	ai_service.register_tool("get_story_outline", "Get narrative-only text from all scenes (dialogue, choices, variables; no SFX/BGM/effects)", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _get_story_outline(args))


static func register_read_only(ai_service: Node) -> void:
	ai_service.register_tool("db_list", "List all entries of a type: scenes/characters/variables/events", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"}
		},
		"required": ["type"]
	}, func(args: Dictionary) -> Variant: return _db_list(args))

	ai_service.register_tool("db_get", "Get full details of one entry. Scenes include Root DSL script", {
		"type": "object",
		"properties": {
			"type": {"type": "string", "enum": ["scenes", "characters", "variables", "events"], "description": "data type"},
			"id": {"type": "string", "description": "entry ID"}
		},
		"required": ["type", "id"]
	}, func(args: Dictionary) -> Variant: return _db_get(args))

	ai_service.register_tool("get_story_outline", "Get narrative-only text from all scenes (dialogue, choices, variables; no SFX/BGM/effects)", {
		"type": "object",
		"properties": {},
	}, func(args: Dictionary) -> Variant: return _get_story_outline(args))


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
		"variables": return "variable_name"
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


static func get_root_dsl(scene: Resource) -> String:
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
	return serializer.serialize(commands)


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
		if name_f in item:
			entry["name"] = item.get(name_f)
		if type == "scenes" and "folder" in item:
			entry["folder"] = item.folder
		if type == "variables":
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
				data["root_dsl"] = get_root_dsl(item)
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
		"scenes": return _create_scene(arr, fields)
		"characters": return _create_character(arr, fields)
		"variables": return _create_variable(arr, fields)
		"events": return _create_event(arr, fields)
		_: return {"success": false, "error": "Unknown type: " + type}


static func _create_scene(arr: Array, fields: Dictionary) -> Dictionary:
	var scene: AVGScene = AVGScene.new()
	scene.scene_id = AVGScene.next_available_id(arr)
	scene.scene_name = fields.get("scene_name", fields.get("name", "New Scene"))
	scene.folder = fields.get("folder", "")
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
			root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": result.commands, "condition_commands": []}]
		else:
			return {"success": false, "error": "DSL parse error: " + str(result.errors)}
	arr.append(scene)
	return {"success": true, "id": scene.scene_id, "name": scene.scene_name}


static func _create_character(arr: Array, fields: Dictionary) -> Dictionary:
	var c: AVGCharacter = AVGCharacter.new()
	c.character_id = AVGCharacter.make_id(_next_slot(arr, "char_", 5))
	c.character_name = fields.get("character_name", fields.get("name", "Character"))
	c.display_name = fields.get("display_name", "")
	c.profile = fields.get("profile", "")
	arr.append(c)
	return {"success": true, "id": c.character_id, "name": c.character_name}


static func _create_variable(arr: Array, fields: Dictionary) -> Dictionary:
	var v: AVGVariable = AVGVariable.new()
	v.variable_id = AVGVariable.make_id(_next_slot(arr, "var_", 4))
	v.variable_name = fields.get("variable_name", fields.get("name", ""))
	v.default_value = fields.get("default_value", 0)
	v.description = fields.get("description", "")
	arr.append(v)
	return {"success": true, "id": v.variable_id, "name": v.variable_name}


static func _create_event(arr: Array, fields: Dictionary) -> Dictionary:
	var ev: AVGEvent = AVGEvent.new()
	ev.event_id = AVGEvent.make_id(_next_slot(arr, "event_", 6))
	ev.event_name = fields.get("event_name", fields.get("name", "New Event"))
	var dsl: String = fields.get("dsl", "")
	if not dsl.is_empty():
		var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
		var parser = ParserClass.new()
		var result: Dictionary = parser.parse(dsl)
		if result.success:
			ev.commands = result.commands
		else:
			return {"success": false, "error": "DSL parse error: " + str(result.errors)}
	arr.append(ev)
	return {"success": true, "id": ev.event_id, "name": ev.event_name}


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
			if type == "scenes" and fields.has("dsl"):
				var root: Resource = find_root_node(item)
				if root == null:
					return {"success": false, "error": "Scene has no root node"}
				var ParserClass = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
				var parser = ParserClass.new()
				var result: Dictionary = parser.parse(fields.get("dsl", ""))
				if not result.success:
					return {"success": false, "error": "DSL parse error: " + str(result.errors)}
				root.command_tabs = [ {"mode": 0, "condition_type": 0, "commands": result.commands, "condition_commands": []}]
				fields.erase("dsl")
			# Normalize short aliases to actual field names
			var name_f: String = get_name_field(type)
			if fields.has("name") and not fields.has(name_f):
				fields[name_f] = fields["name"]
				fields.erase("name")
			for key in fields:
				if key == id_f: continue
				if key in item: item.set(key, fields[key])
			return {"success": true, "id": id}
	return {"success": false, "error": "%s '%s' not found" % [type, id]}


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
				outline += serializer.serialize(narr) + "\n"
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


static func _resource_to_dict(item: Resource, type: String) -> Dictionary:
	var data: Dictionary = {}
	var id_f: String = get_id_field(type)
	var name_f: String = get_name_field(type)
	if id_f in item: data["id"] = item.get(id_f)
	if name_f in item: data["name"] = item.get(name_f)
	match type:
		"scenes":
			if "folder" in item: data["folder"] = item.folder
		"characters":
			if "display_name" in item: data["display_name"] = item.display_name
			if "profile" in item: data["profile"] = item.profile
		"variables":
			if "default_value" in item: data["default_value"] = item.default_value
			if "description" in item: data["description"] = item.description
		"events":
			if "commands" in item and item.commands.size() > 0:
				var s: AVGDSLSerializer = AVGDSLSerializer.new()
				data["dsl"] = s.serialize(item.commands)
	return data
