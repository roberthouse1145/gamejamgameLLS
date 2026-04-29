class_name DateEventBuilder extends RefCounted

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const AVGDialogSettingsClass = preload("res://scripts/avg/resources/avg_dialog_settings.gd")
const AVGGameUIConfigClass = preload("res://scripts/avg/resources/avg_game_ui_config.gd")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

const IMPORTANT_EVENTS_PATH: String = "res://resources/data/date_important_events.json"
const VAR_CHOICE_ID: String = "var_001"
const VAR_AFFECTION_DELTA: String = "var_002"

var _templates: Array[Dictionary] = []


func _init() -> void:
	_load_templates()


func has_event_for_session(session: Dictionary, played_events: Dictionary = {}) -> bool:
	return not _select_event(session, played_events).is_empty()


func build_event_request(session: Dictionary, played_events: Dictionary = {}) -> Dictionary:
	var event_def := _select_event(session, played_events)
	if event_def.is_empty():
		return {"success": false, "error": "no_matching_event"}

	var scene: Resource = _build_scene(session, event_def)
	var project: Resource = _build_project(session, scene)
	var outcomes: Dictionary = _build_outcomes(event_def)

	return {
		"success": true,
		"event_id": str(event_def.get("event_id", "")),
		"title": str(event_def.get("title", "Important Date")),
		"window_title": str(event_def.get("window_title", "重要约会")),
		"project": project,
		"scene": scene,
		"outcomes": outcomes,
	}


func _load_templates() -> void:
	_templates.clear()
	if not FileAccess.file_exists(IMPORTANT_EVENTS_PATH):
		push_warning("[DateEventBuilder] Missing templates: %s" % IMPORTANT_EVENTS_PATH)
		return

	var file := FileAccess.open(IMPORTANT_EVENTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[DateEventBuilder] Failed to open templates")
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		push_warning("[DateEventBuilder] Invalid template format")
		return

	for item in parsed:
		if item is Dictionary:
			_templates.append((item as Dictionary).duplicate(true))


func _select_event(session: Dictionary, played_events: Dictionary) -> Dictionary:
	var location_id := str(session.get("location_id", "")).strip_edges()
	for template in _templates:
		if str(template.get("location_id", "")) != location_id:
			continue
		var event_id := str(template.get("event_id", "")).strip_edges()
		if event_id.is_empty():
			continue
		var trigger := str(template.get("trigger", "always")).strip_edges()
		if trigger == "first_visit" and played_events.get(event_id, false):
			continue
		return template.duplicate(true)
	return {}


func _build_project(session: Dictionary, scene: Resource) -> Resource:
	var project := AVGProjectClass.new()
	project.project_name = "date_event_%s" % str(session.get("session_id", "temp"))
	project.resolution = Vector2i(2560, 1440)
	project.dialog_settings = _build_dialog_settings()
	project.game_ui_config = AVGGameUIConfigClass.new()
	project.scenes = [scene]
	project.characters = []
	project.events = []
	project.variables = [
		_make_variable(VAR_CHOICE_ID, "important_choice_id", 0, "Selected important date choice"),
		_make_variable(VAR_AFFECTION_DELTA, "important_affection_delta", 0, "Affection delta from important date"),
	]
	project.shared_nodes = []
	project.screen_configs = {}
	return project


func _build_dialog_settings() -> Resource:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var narrative_manager: Node = tree.root.get_node_or_null("NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("duplicate_dialog_settings"):
		var dialog_settings: Resource = narrative_manager.duplicate_dialog_settings()
		if dialog_settings != null:
			return dialog_settings
	return AVGDialogSettingsClass.new()


func _build_scene(session: Dictionary, event_def: Dictionary) -> Resource:
	var root := AVGRootNodeClass.new()
	root.node_id = "root"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(2560, 1440)
	root.command_tabs = [{
		"commands": _build_commands(session, event_def),
		"condition_commands": [],
		"mode": 0,
	}]

	var scene := AVGSceneClass.new()
	scene.scene_id = str(event_def.get("event_id", "date_event"))
	scene.scene_name = str(event_def.get("title", "Important Date"))
	scene.nodes = [root]
	return scene


func _build_commands(session: Dictionary, event_def: Dictionary) -> Array:
	var commands: Array = []
	var intro_lines: Array = event_def.get("intro_lines", [])
	for line in intro_lines:
		commands.append(_dialogue_from_variant(line, session, event_def))

	var choice_prompt: Variant = event_def.get("choice_prompt", {})
	if choice_prompt is Dictionary and not (choice_prompt as Dictionary).is_empty():
		commands.append(_dialogue_from_variant(choice_prompt, session, event_def))

	var choice_entries: Array = []
	var choices: Array = event_def.get("choices", [])
	for choice in choices:
		if not choice is Dictionary:
			continue
		var choice_def: Dictionary = choice
		var branch_commands: Array = [
			_set_variable(VAR_CHOICE_ID, int(choice_def.get("choice_id", 0))),
			_set_variable(VAR_AFFECTION_DELTA, int(choice_def.get("affection_delta", 0))),
		]
		for line in choice_def.get("lines", []):
			branch_commands.append(_dialogue_from_variant(line, session, event_def))
		choice_entries.append({
			"text": str(choice_def.get("text", "继续")),
			"commands": branch_commands,
		})

	if not choice_entries.is_empty():
		commands.append(_choice(choice_entries))

	for line in event_def.get("outro_lines", []):
		commands.append(_dialogue_from_variant(line, session, event_def))

	return commands


func _build_outcomes(event_def: Dictionary) -> Dictionary:
	var outcomes: Dictionary = {}
	for choice in event_def.get("choices", []):
		if not choice is Dictionary:
			continue
		var choice_def: Dictionary = choice
		var choice_id := int(choice_def.get("choice_id", 0))
		outcomes[choice_id] = {
			"text": str(choice_def.get("text", "")),
			"summary": str(choice_def.get("summary", "")),
			"affection_delta": int(choice_def.get("affection_delta", 0)),
			"tag": str(choice_def.get("result_tag", "")),
		}
	return outcomes


func _dialogue_from_variant(line: Variant, session: Dictionary, event_def: Dictionary) -> Resource:
	var speaker: String = ""
	var text: String = ""
	if line is Dictionary:
		speaker = str(line.get("speaker", ""))
		text = str(line.get("text", ""))
	else:
		text = str(line)
	text = _interpolate_text(text, session, event_def)
	return _command("DIALOGUE", {
		"speaker": speaker,
		"text": text,
	})


func _interpolate_text(text: String, session: Dictionary, event_def: Dictionary) -> String:
	var location: Dictionary = session.get("location", {})
	var resolved_text := text
	resolved_text = resolved_text.replace("{location_title}", str(location.get("title", "")))
	resolved_text = resolved_text.replace("{event_title}", str(event_def.get("title", "")))
	return resolved_text


func _choice(choices: Array) -> Resource:
	return _command("CHOICE", {"choices": choices})


func _set_variable(variable_id: String, value: int) -> Resource:
	return _command("SET_VARIABLE", {
		"variable_id": variable_id,
		"operation": "set",
		"value_source": "constant",
		"value": value,
	})


func _command(command_type: String, params: Dictionary) -> Resource:
	var command := AVGCommandClass.new()
	command.command_type = command_type
	command.params = params
	return command


func _make_variable(variable_id: String, variable_name: String, default_value: int, description: String) -> Resource:
	var variable := AVGVariableClass.new()
	variable.variable_id = variable_id
	AVGVariableClass.apply_key(variable, variable_name)
	variable.default_value = default_value
	variable.description = description
	return variable
