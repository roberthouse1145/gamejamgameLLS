class_name AVGSceneGenerator
extends Node

signal scene_generated(session_id: String, package: Dictionary)
signal scene_failed(session_id: String, error: String)

const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")
const AVGDSLSerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")
const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")
const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")

const PREVIEW_PROMPT_KEY: String = "date_scene_dsl_preview"
const PREVIEW_SOURCE_KEY: String = "date_scene_preview_source"
const PREVIEW_ASSET_KEY: String = "date_scene_asset_manifest"
const WRITER_ROLE: String = "date_scene_writer"
const MAX_GENERATION_ATTEMPTS: int = 3
const NORMAL_CHOICE_VAR_ID: String = "var_001"
const ALLOWED_COMMANDS: Array[String] = [
	"DIALOGUE",
	"CHOICE",
	"CHANGE_BACKGROUND",
	"SHOW_CHARACTER",
	"CHANGE_EXPRESSION",
	"CHANGE_OUTFIT",
	"SHOW_IMAGE",
	"HIDE_IMAGE",
	"SCREEN_FADE",
	"SET_TIME_OF_DAY",
	"WAIT_TIME",
	"CHARACTER_EFFECT",
]
const ALLOWED_POSITIONS: Array[String] = ["left", "center", "right"]
const OUTLINE_COMMAND_TYPES: PackedStringArray = [
	"DIALOGUE",
	"CHOICE",
	"IF",
	"LABEL",
	"JUMP_LABEL",
	"JUMP_SCENE",
	"CALL_EVENT",
]

var _builder: RefCounted = AVGScenePromptBuilderClass.new()
var _parser: RefCounted = ParserClass.new()
var _validator: RefCounted = ValidatorClass.new()
var _writer_service: AIService = null
var _writer_ready: bool = false
var _request_context_by_id: Dictionary = {}


func _ready() -> void:
	_setup_ai_services()


func is_available() -> bool:
	return _writer_ready and _writer_service != null


func generate_for_session(session_id: String, session: Dictionary) -> bool:
	if not is_available():
		return false
	if session_id.strip_edges().is_empty() or session.is_empty():
		return false

	var prompt_text: String = _build_prompt(session)
	if prompt_text.is_empty():
		scene_failed.emit(session_id, "empty_prompt")
		return false

	var context: Dictionary = {
		"session_id": session_id,
		"session": session.duplicate(true),
		"base_prompt": prompt_text,
		"attempt": 0,
	}
	print("[AVGSceneGenerator] Build prompt for %s" % session_id)
	return _request_generation(context)


func _setup_ai_services() -> void:
	_writer_service = AIService.new()
	_writer_service.name = "AVGSceneGeneratorWriter"
	add_child(_writer_service)
	_writer_service.request_completed.connect(_on_writer_completed)
	_writer_service.request_failed.connect(_on_writer_failed)

	var config_mgr := AIConfigManager.new()
	if not config_mgr.load_config():
		return

	_writer_ready = config_mgr.apply_to_service(_writer_service, WRITER_ROLE)
	if not _writer_ready:
		_writer_ready = config_mgr.apply_to_service(_writer_service, "avg_dev_writer")
	if not _writer_ready:
		_writer_ready = config_mgr.apply_to_service(_writer_service, "chat_default")


func _build_prompt(session: Dictionary) -> String:
	if _builder == null or not _builder.has_method("build_normal_date_prompt_from_session"):
		return ""

	var base_prompt: String = str(_builder.build_normal_date_prompt_from_session(session)).strip_edges()
	if base_prompt.is_empty():
		return ""

	var prompt_manager: Node = _get_autoload("PromptManager")
	if prompt_manager == null or not prompt_manager.has_method("register_prompt") or not prompt_manager.has_method("resolve"):
		return base_prompt

	var preview_source_key: String = str(session.get("scene_preview_source_key", PREVIEW_SOURCE_KEY)).strip_edges()
	if preview_source_key.is_empty():
		preview_source_key = PREVIEW_SOURCE_KEY
	var preview_asset_key: String = str(session.get("scene_asset_prompt_key", PREVIEW_ASSET_KEY)).strip_edges()
	if preview_asset_key.is_empty():
		preview_asset_key = PREVIEW_ASSET_KEY
	var preview_prompt_key: String = str(session.get("scene_preview_prompt_key", PREVIEW_PROMPT_KEY)).strip_edges()
	if preview_prompt_key.is_empty():
		preview_prompt_key = PREVIEW_PROMPT_KEY

	prompt_manager.register_prompt(preview_source_key, base_prompt)
	prompt_manager.register_prompt(preview_asset_key, _build_asset_prompt_block())
	if prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(preview_prompt_key):
		return str(prompt_manager.resolve(preview_prompt_key)).strip_edges()
	return base_prompt


func _build_asset_prompt_block() -> String:
	var narrative_manager: Node = _get_autoload("NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("build_asset_prompt"):
		var narrative_prompt: String = str(narrative_manager.build_asset_prompt()).strip_edges()
		if not narrative_prompt.is_empty():
			return narrative_prompt
	push_warning("[AVGSceneGenerator] NarrativeProjectManager asset prompt unavailable")
	return "No asset manifest available."


func _request_generation(context: Dictionary) -> bool:
	var prompt_text: String = str(context.get("base_prompt", "")).strip_edges()
	if prompt_text.is_empty():
		return false

	var updated_context: Dictionary = context.duplicate(true)
	updated_context["attempt"] = int(updated_context.get("attempt", 0)) + 1

	var request_id: String = _writer_service.chat_simple(prompt_text, _build_system_prompt(), {
		"temperature": 0.75,
		"max_tokens": 2400,
	})
	if request_id.is_empty():
		return false

	_request_context_by_id[request_id] = updated_context
	print("[AVGSceneGenerator] Writer request sent: %s | attempt=%d" % [
		str(updated_context.get("session_id", "")),
		int(updated_context.get("attempt", 0))
	])
	return true


func _build_system_prompt() -> String:
	return "You are an AVG DSL writer. Output only AVG DSL V2 content with no markdown fences or explanations."


func _on_writer_completed(request_id: String, response: Dictionary) -> void:
	if not _request_context_by_id.has(request_id):
		return
	var context: Dictionary = _request_context_by_id[request_id]
	_request_context_by_id.erase(request_id)

	var raw_text: String = AIService.extract_content(response).strip_edges()
	var reasoning_text: String = AIService.extract_reasoning_content(response).strip_edges()
	if not reasoning_text.is_empty():
		print("[AVGSceneGenerator] Writer reasoning: %s" % reasoning_text)
	var validation: Dictionary = _validate_dsl(raw_text)
	print("[AVGSceneGenerator] Writer response: %s | ok=%s | %s" % [
		str(context.get("session_id", "")),
		str(bool(validation.get("ok", false))),
		str(validation.get("summary", ""))
	])
	if bool(validation.get("ok", false)):
		_emit_scene_generated(str(context.get("session_id", "")), validation.get("commands", []), context.get("session", {}))
		return

	var attempt: int = int(context.get("attempt", 0))
	if attempt < MAX_GENERATION_ATTEMPTS:
		var retry_context: Dictionary = context.duplicate(true)
		retry_context["base_prompt"] = _build_retry_prompt(str(context.get("base_prompt", "")), validation)
		if _request_generation(retry_context):
			return

	scene_failed.emit(str(context.get("session_id", "")), str(validation.get("summary", "dsl_validation_failed")))


func _on_writer_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_context_by_id.has(request_id):
		return
	var context: Dictionary = _request_context_by_id[request_id]
	_request_context_by_id.erase(request_id)
	print("[AVGSceneGenerator] Writer request failed: %s | %s" % [str(context.get("session_id", "")), error])
	scene_failed.emit(str(context.get("session_id", "")), error)


func _validate_dsl(raw_text: String) -> Dictionary:
	var sanitized: String = _strip_code_fences(raw_text)
	if sanitized.is_empty():
		return {"ok": false, "summary": "empty_dsl", "errors": ["empty_dsl"]}

	var parse_result: Dictionary = _parser.parse(sanitized)
	if not bool(parse_result.get("success", false)):
		var parse_errors: Array = parse_result.get("errors", [])
		var first_error: String = "dsl_parse_failed"
		if not parse_errors.is_empty() and parse_errors[0] is Dictionary:
			var error_entry: Dictionary = parse_errors[0]
			first_error = "line %d: %s" % [int(error_entry.get("line", 0)), str(error_entry.get("message", ""))]
		return {
			"ok": false,
			"summary": first_error,
			"errors": [first_error],
		}

	var commands: Array = parse_result.get("commands", [])
	var semantic_result: Dictionary = _validator.validate_commands(
		commands,
		_build_runtime_project(),
		_get_project_root_path(),
		{
			"allowed_commands": ALLOWED_COMMANDS,
			"allowed_positions": ALLOWED_POSITIONS,
			"min_choice_count": 0,
			"max_choice_count": 0,
		}
	)
	if not bool(semantic_result.get("ok", false)):
		return {
			"ok": false,
			"summary": str(semantic_result.get("summary", "dsl_semantic_failed")),
			"errors": semantic_result.get("errors", []),
		}

	return {
		"ok": true,
		"summary": str(semantic_result.get("summary", "ok")),
		"commands": commands,
		"errors": [],
	}


func _build_retry_prompt(base_prompt: String, result: Dictionary) -> String:
	var error_lines: Array = result.get("errors", [])
	var retry_lines: Array[String] = []
	retry_lines.append(base_prompt)
	retry_lines.append("")
	retry_lines.append("The last DSL failed validation. Rewrite the whole DSL and fix these issues:")
	if error_lines.is_empty():
		retry_lines.append("- The output did not satisfy the structural or asset constraints.")
	else:
		for entry in error_lines:
			retry_lines.append("- %s" % str(entry))
	retry_lines.append("Still output only DSL.")
	return "\n".join(retry_lines).strip_edges()


func _emit_scene_generated(session_id: String, commands: Array, session: Dictionary = {}) -> void:
	var packaged: Dictionary = _build_scene_package(session_id, commands, session)
	if packaged.is_empty():
		scene_failed.emit(session_id, "scene_package_failed")
		return
	print("[AVGSceneGenerator] Scene package ready: %s | commands=%d" % [session_id, commands.size()])
	scene_generated.emit(session_id, packaged)


func _build_scene_package(session_id: String, commands: Array, session: Dictionary = {}) -> Dictionary:
	var instrumentation: Dictionary = _instrument_choice_commands(commands)
	var instrumented_commands: Array = instrumentation.get("commands", [])
	var choice_labels: Dictionary = instrumentation.get("choice_labels", {})

	var project: Resource = _build_runtime_project()
	if project == null:
		return {}

	var root := AVGRootNodeClass.new()
	root.node_id = "root"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(project.resolution) if project != null and "resolution" in project else Vector2(2560, 1440)
	root.command_tabs = [ {
		"commands": instrumented_commands,
		"condition_commands": [],
		"mode": 0,
	}]

	var scene := AVGSceneClass.new()
	var scene_prefix: String = str(session.get("scene_project_prefix", "date_scene")).strip_edges()
	if scene_prefix.is_empty():
		scene_prefix = "date_scene"
	var scene_title: String = str(session.get("scene_window_title", "约会中")).strip_edges()
	if scene_title.is_empty():
		scene_title = "约会中"
	scene.scene_id = "%s_%s" % [scene_prefix, session_id]
	scene.scene_name = scene_title
	scene.nodes = [root]
	scene.local_variables = []

	project.project_name = "%s_%s" % [scene_prefix, session_id]
	project.scenes = [scene]
	project.variables = _merge_project_variables(project.variables, [_make_choice_variable()])
	project.events = []
	project.shared_nodes = []

	return {
		"session_id": session_id,
		"title": scene_title,
		"project": project,
		"scene": scene,
		"scene_outline": build_narrative_outline(instrumented_commands),
		"choice_labels": choice_labels,
		"choice_var_id": NORMAL_CHOICE_VAR_ID,
	}


static func build_narrative_outline(commands: Array) -> String:
	var filtered_commands: Array = _filter_outline_commands(commands)
	if filtered_commands.is_empty():
		return ""
	var serializer := AVGDSLSerializerClass.new()
	return serializer.serialize(filtered_commands).strip_edges()


static func build_narrative_outline_from_scene(scene: Resource) -> String:
	if scene == null or not ("nodes" in scene) or scene.nodes == null:
		return ""
	var root: Resource = null
	for node in scene.nodes:
		if node is AVGRootNodeClass:
			root = node
			break
	if root == null and scene.nodes.size() > 0:
		root = scene.nodes[0]
	if root == null or not ("command_tabs" in root) or root.command_tabs == null or root.command_tabs.is_empty():
		return ""
	var first_tab: Dictionary = root.command_tabs[0]
	return build_narrative_outline(first_tab.get("commands", []))


static func _filter_outline_commands(commands: Array) -> Array:
	var result: Array = []
	for command in commands:
		if command == null:
			continue
		var command_type: String = _get_outline_command_type(command)
		if command_type.is_empty() or not OUTLINE_COMMAND_TYPES.has(command_type):
			continue
		if command is Resource:
			var clone: Resource = command.duplicate(true)
			if command_type == "CHOICE":
				var choice_params: Dictionary = clone.params if "params" in clone else {}
				var filtered_choices: Array = []
				for choice in choice_params.get("choices", []):
					var choice_dict: Dictionary = choice.duplicate(true) if choice is Dictionary else {}
					choice_dict["commands"] = _filter_outline_commands(choice_dict.get("commands", []))
					filtered_choices.append(choice_dict)
				choice_params["choices"] = filtered_choices
				clone.params = choice_params
			elif command_type == "IF":
				var if_params: Dictionary = clone.params if "params" in clone else {}
				if_params["if_commands"] = _filter_outline_commands(if_params.get("if_commands", []))
				if_params["else_commands"] = _filter_outline_commands(if_params.get("else_commands", []))
				clone.params = if_params
			result.append(clone)
			continue
		if command is Dictionary:
			var clone_dict: Dictionary = command.duplicate(true)
			if command_type == "CHOICE":
				var filtered_choice_dicts: Array = []
				for choice in clone_dict.get("params", {}).get("choices", []):
					var choice_dict: Dictionary = choice.duplicate(true) if choice is Dictionary else {}
					choice_dict["commands"] = _filter_outline_commands(choice_dict.get("commands", []))
					filtered_choice_dicts.append(choice_dict)
				var choice_params_dict: Dictionary = clone_dict.get("params", {}).duplicate(true)
				choice_params_dict["choices"] = filtered_choice_dicts
				clone_dict["params"] = choice_params_dict
			elif command_type == "IF":
				var if_params_dict: Dictionary = clone_dict.get("params", {}).duplicate(true)
				if_params_dict["if_commands"] = _filter_outline_commands(if_params_dict.get("if_commands", []))
				if_params_dict["else_commands"] = _filter_outline_commands(if_params_dict.get("else_commands", []))
				clone_dict["params"] = if_params_dict
			result.append(clone_dict)
	return result


static func _get_outline_command_type(command: Variant) -> String:
	if command is Resource and "command_type" in command:
		return str(command.command_type).strip_edges()
	if command is Dictionary:
		return str(command.get("command_type", "")).strip_edges()
	return ""


func _instrument_choice_commands(commands: Array) -> Dictionary:
	var cloned_commands: Array = []
	var choice_labels: Dictionary = {}

	for command in commands:
		if command == null:
			continue
		var clone: Resource = command.duplicate(true)
		if str(clone.command_type) == "CHOICE":
			var cloned_choices: Array = []
			var choices: Array = clone.params.get("choices", [])
			for choice_index in range(choices.size()):
				var choice: Dictionary = choices[choice_index] if choices[choice_index] is Dictionary else {}
				var updated_choice: Dictionary = choice.duplicate(true)
				var branch_commands: Array = []
				branch_commands.append(_make_set_variable_command(NORMAL_CHOICE_VAR_ID, choice_index + 1))
				for branch_command in updated_choice.get("commands", []):
					branch_commands.append(branch_command)
				updated_choice["commands"] = branch_commands
				cloned_choices.append(updated_choice)
				choice_labels[choice_index + 1] = str(updated_choice.get("text", ""))
			clone.params["choices"] = cloned_choices
		cloned_commands.append(clone)

	return {
		"commands": cloned_commands,
		"choice_labels": choice_labels,
	}


func _build_runtime_project() -> Resource:
	var narrative_manager: Node = _get_autoload("NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("duplicate_current_project"):
		var narrative_project: Resource = narrative_manager.duplicate_current_project()
		if narrative_project != null:
			return narrative_project

	return AVGProjectClass.new()


func _get_project_root_path() -> String:
	var narrative_manager: Node = _get_autoload("NarrativeProjectManager")
	if narrative_manager != null:
		var narrative_path: String = str(narrative_manager.get("current_project_path")).strip_edges()
		if not narrative_path.is_empty():
			return narrative_path
	return ""


func _merge_project_variables(existing_variables: Array, additions: Array) -> Array:
	var merged: Array = []
	var seen_ids: Dictionary = {}

	for variable in existing_variables:
		if variable == null:
			continue
		var variable_id: String = str(variable.get("variable_id") if "variable_id" in variable else "").strip_edges()
		if variable_id.is_empty() or seen_ids.has(variable_id):
			continue
		seen_ids[variable_id] = true
		merged.append(variable)

	for variable in additions:
		if variable == null:
			continue
		var variable_id: String = str(variable.get("variable_id") if "variable_id" in variable else "").strip_edges()
		if variable_id.is_empty() or seen_ids.has(variable_id):
			continue
		seen_ids[variable_id] = true
		merged.append(variable)

	return merged


func _make_choice_variable() -> Resource:
	var variable := AVGVariableClass.new()
	variable.variable_id = NORMAL_CHOICE_VAR_ID
	variable.variable_name = "date_choice_id"
	variable.default_value = 0
	variable.description = "Selected normal date choice"
	return variable


func _make_set_variable_command(variable_id: String, value: int) -> Resource:
	var command := AVGCommandClass.new()
	command.command_type = "SET_VARIABLE"
	command.params = {
		"variable_id": variable_id,
		"operation": "set",
		"value_source": "constant",
		"value": value,
	}
	return command


func _strip_code_fences(raw_text: String) -> String:
	var sanitized: String = raw_text.strip_edges()
	if sanitized.begins_with("```"):
		var lines: PackedStringArray = sanitized.split("\n")
		if lines.size() >= 3:
			lines.remove_at(0)
			if lines[lines.size() - 1].strip_edges() == "```":
				lines.remove_at(lines.size() - 1)
			sanitized = "\n".join(lines).strip_edges()
	return sanitized


func _get_autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)
