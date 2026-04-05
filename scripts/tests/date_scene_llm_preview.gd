extends Control

const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")
const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")

const PREVIEW_PROMPT_KEY: String = "date_scene_dsl_preview"
const PREVIEW_SOURCE_KEY: String = "date_scene_preview_source"
const PREVIEW_ASSET_KEY: String = "date_scene_asset_manifest"
const HEROINE_TEMPLATE_PATH: String = "res://templates/tutorial_project/characters/alice.tres"
const MAX_GENERATION_ATTEMPTS: int = 3
@export var auto_run_on_ready: bool = true
@export var preferred_location_id: String = "park"

@onready var location_select: OptionButton = %LocationSelect
@onready var generate_button: Button = %GenerateButton
@onready var play_button: Button = %PlayButton
@onready var status_label: Label = %StatusLabel
@onready var prompt_view: TextEdit = %PromptView
@onready var response_view: TextEdit = %ResponseView
@onready var validation_view: TextEdit = %ValidationView
@onready var scene_runner: Control = %AVGSceneRunner

var _builder: RefCounted = null
var _parser: RefCounted = null
var _validator: RefCounted = null
var _ai_service: AIService = null
var _locations: Array[Dictionary] = []
var _last_request_id: String = ""
var _base_prompt: String = ""
var _last_prompt: String = ""
var _config_ready: bool = false
var _last_parsed_commands: Array = []
var _preview_project: Resource = null
var _preview_scene: Resource = null
var _generation_attempt: int = 0


func _ready() -> void:
	_builder = AVGScenePromptBuilderClass.new()
	_parser = ParserClass.new()
	_validator = ValidatorClass.new()
	generate_button.pressed.connect(_on_generate_pressed)
	play_button.pressed.connect(_on_play_pressed)
	play_button.disabled = true
	_setup_ai_service()
	_load_locations()
	if auto_run_on_ready:
		call_deferred("_auto_run_preview")


func _setup_ai_service() -> void:
	_ai_service = AIService.new()
	_ai_service.name = "DateSceneLLMPreviewAI"
	add_child(_ai_service)
	_ai_service.request_completed.connect(_on_ai_request_completed)
	_ai_service.request_failed.connect(_on_ai_request_failed)

	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		_config_ready = config_mgr.apply_to_service(_ai_service, "avg_dev_writer")
		if not _config_ready:
			_config_ready = config_mgr.apply_to_service(_ai_service, "chat_default")

	if _config_ready:
		_set_status("AI 配置已加载，准备生成普通约会 DSL。", Color(0.71, 0.86, 0.98, 1.0))
	else:
		_set_status("未加载到可用 AI 配置，无法发起真实请求。", Color(1.0, 0.66, 0.4, 1.0))


func _load_locations() -> void:
	_locations.clear()
	location_select.clear()

	var date_manager: Node = get_node_or_null("/root/DateManager")
	if date_manager != null and date_manager.has_method("get_available_locations"):
		var available: Variant = date_manager.get_available_locations()
		if available is Array:
			for item in available:
				if item is Dictionary:
					_locations.append(item.duplicate(true))

	for index in range(_locations.size()):
		var location: Dictionary = _locations[index]
		var title: String = str(location.get("title", location.get("location_id", "unknown")))
		location_select.add_item(title, index)
		if str(location.get("location_id", "")) == preferred_location_id:
			location_select.select(index)

	if _locations.is_empty():
		_set_status("没有读取到约会地点数据。", Color(1.0, 0.56, 0.56, 1.0))


func _auto_run_preview() -> void:
	if _config_ready and not _locations.is_empty():
		_generate_preview()


func _on_generate_pressed() -> void:
	_generate_preview()


func _on_play_pressed() -> void:
	_play_preview_scene()


func _generate_preview() -> void:
	if not _config_ready or _ai_service == null:
		_set_status("AI 配置不可用，无法发起请求。", Color(1.0, 0.56, 0.56, 1.0))
		return
	if _locations.is_empty():
		_set_status("地点列表为空，无法生成预览。", Color(1.0, 0.56, 0.56, 1.0))
		return
	if not _last_request_id.is_empty():
		_set_status("上一条请求尚未完成。", Color(1.0, 0.82, 0.47, 1.0))
		return

	var selected_index: int = clampi(location_select.selected, 0, _locations.size() - 1)
	var location: Dictionary = _locations[selected_index]
	var session: Dictionary = _build_preview_session(location)
	_base_prompt = _build_preview_prompt(session)
	_last_prompt = _base_prompt
	_generation_attempt = 0
	_last_parsed_commands.clear()
	_preview_project = null
	_preview_scene = null
	play_button.disabled = true
	response_view.text = ""
	validation_view.text = ""
	prompt_view.text = _base_prompt

	if _base_prompt.is_empty():
		_set_status("普通约会 DSL prompt 为空。", Color(1.0, 0.56, 0.56, 1.0))
		return

	_request_generation(_base_prompt)


func _request_generation(prompt_text: String) -> void:
	_generation_attempt += 1
	_last_prompt = prompt_text
	prompt_view.text = prompt_text

	print("[DateSceneLLMPreview] PROMPT_BEGIN")
	print(prompt_text)
	print("[DateSceneLLMPreview] PROMPT_END")

	var options: Dictionary = {
		"temperature": 0.75,
		"max_tokens": 2400
	}
	_last_request_id = _ai_service.chat_simple(prompt_text, _build_system_prompt(), options)
	_set_status(
		"LLM DSL 请求已发出（第 %d/%d 次）。" % [_generation_attempt, MAX_GENERATION_ATTEMPTS],
		Color(0.73, 0.88, 1.0, 1.0)
	)


func _build_system_prompt() -> String:
	return "你是一个擅长写 Galgame 日常约会片段的 AVG DSL 写手。请只输出能被 AVG DSL V2 解析器直接解析的 DSL 本体。"


func _build_preview_session(location: Dictionary) -> Dictionary:
	var location_copy: Dictionary = location.duplicate(true)
	var location_id: String = str(location_copy.get("location_id", "")).strip_edges()
	var session_id: String = "preview_%s" % location_id
	return {
		"session_id": session_id,
		"location_id": location_id,
		"location": location_copy,
		"start_day": _get_current_day(),
		"phase_after_action": _get_phase_name(),
		"detail_prompt": str(location_copy.get("detail_prompt", "")).strip_edges(),
	}


func _build_preview_prompt(session: Dictionary) -> String:
	if _builder == null or not _builder.has_method("build_normal_date_prompt_from_session"):
		return ""

	var base_prompt: String = str(_builder.build_normal_date_prompt_from_session(session)).strip_edges()
	if base_prompt.is_empty():
		return ""

	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager == null or not prompt_manager.has_method("resolve_with_vars"):
		return base_prompt

	var ctx: Dictionary = {
		PREVIEW_SOURCE_KEY: base_prompt,
		PREVIEW_ASSET_KEY: _build_asset_prompt_block(),
	}
	if prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(PREVIEW_PROMPT_KEY):
		return str(prompt_manager.resolve_with_vars(PREVIEW_PROMPT_KEY, ctx)).strip_edges()
	return base_prompt


func _build_asset_prompt_block() -> String:
	var narrative_manager: Node = get_node_or_null("/root/NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("build_asset_prompt"):
		var narrative_prompt: String = str(narrative_manager.build_asset_prompt()).strip_edges()
		if not narrative_prompt.is_empty():
			return narrative_prompt

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage != null and storage.has_method("build_asset_prompt"):
		return str(storage.build_asset_prompt()).strip_edges()

	return "本次没有读取到素材清单。"


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		return int(glm.get("current_day"))
	return 1


func _get_phase_name() -> String:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_phase_name"):
		return str(glm.get_phase_name(glm.get("time_phase"))).strip_edges()
	return "UNKNOWN"


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _last_request_id:
		return
	_last_request_id = ""

	var raw_text: String = AIService.extract_content(response).strip_edges()
	response_view.text = raw_text
	print("[DateSceneLLMPreview] RESPONSE_BEGIN")
	print(raw_text)
	print("[DateSceneLLMPreview] RESPONSE_END")

	var result: Dictionary = _validate_dsl(raw_text)
	validation_view.text = str(result.get("summary", ""))
	print("[DateSceneLLMPreview] VALIDATION: %s" % str(result.get("summary", "")))

	if bool(result.get("ok", false)):
		_finalize_valid_dsl(result.get("commands", []))
		return

	if _generation_attempt < MAX_GENERATION_ATTEMPTS:
		validation_view.text += "\n\n准备自动重试..."
		_request_generation(_build_retry_prompt_v2(result))
		return

	play_button.disabled = true
	_set_status("DSL 未通过校验，已用完重试次数。", Color(1.0, 0.66, 0.4, 1.0))


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _last_request_id:
		return
	_last_request_id = ""
	response_view.text = ""
	validation_view.text = "请求失败：%s" % error
	print("[DateSceneLLMPreview] REQUEST_FAILED: %s" % error)
	_set_status("LLM 请求失败。", Color(1.0, 0.56, 0.56, 1.0))


func _validate_dsl(raw_text: String) -> Dictionary:
	var sanitized: String = _strip_code_fences(raw_text)
	if sanitized.is_empty():
		return {"ok": false, "summary": "空返回。", "errors": ["空返回。"]}
	if _parser == null or not _parser.has_method("parse"):
		return {"ok": false, "summary": "DSL 解析器不可用。", "errors": ["DSL 解析器不可用。"]}

	var parse_result: Dictionary = _parser.parse(sanitized)
	if not bool(parse_result.get("success", false)):
		var parse_errors: Array = parse_result.get("errors", [])
		var first_error: String = "未知错误"
		if not parse_errors.is_empty() and parse_errors[0] is Dictionary:
			var error_entry: Dictionary = parse_errors[0]
			first_error = "第 %d 行：%s" % [int(error_entry.get("line", 0)), str(error_entry.get("message", ""))]
		return {
			"ok": false,
			"summary": "DSL 解析失败：%s" % first_error,
			"errors": [first_error],
		}

	var commands: Array = parse_result.get("commands", [])
	var counts: Dictionary = _count_command_types(commands)
	var errors: Array[String] = []
	if int(counts.get("DIALOGUE", 0)) == 0:
		errors.append("没有对白命令")
	if int(counts.get("CHOICE", 0)) > 0:
		errors.append("不允许使用 ChoiceBlock")
	if int(counts.get("CHANGE_BACKGROUND", 0)) == 0:
		errors.append("没有背景命令")
	if int(counts.get("SHOW_CHARACTER", 0)) == 0:
		errors.append("没有角色出场命令")
	if int(counts.get("CHANGE_EXPRESSION", 0)) == 0 and int(counts.get("SCREEN_FADE", 0)) == 0 and int(counts.get("WAIT_TIME", 0)) == 0:
		errors.append("没有表情变化、淡入淡出或停顿")

	var semantic_result: Dictionary = _validate_semantics(commands)
	var semantic_errors: Array = semantic_result.get("errors", [])
	for entry in semantic_errors:
		errors.append(str(entry))

	var summary: String = "DSL 解析通过。commands=%d | dialogue=%d | choice=%d | bg=%d | show=%d | expr=%d | fade=%d | wait=%d" % [
		commands.size(),
		int(counts.get("DIALOGUE", 0)),
		int(counts.get("CHOICE", 0)),
		int(counts.get("CHANGE_BACKGROUND", 0)),
		int(counts.get("SHOW_CHARACTER", 0)),
		int(counts.get("CHANGE_EXPRESSION", 0)),
		int(counts.get("SCREEN_FADE", 0)),
		int(counts.get("WAIT_TIME", 0))
	]
	if not errors.is_empty():
		summary += "\n错误：\n- " + "\n- ".join(PackedStringArray(errors))

	return {
		"ok": errors.is_empty(),
		"summary": summary,
		"commands": commands,
		"errors": errors,
	}


func _validate_semantics(commands: Array) -> Dictionary:
	var validation_project: Resource = _build_preview_project()
	var project_root_path: String = ""
	if validation_project != null and "project_root_path" in validation_project:
		project_root_path = str(validation_project.get("project_root_path")).strip_edges()
	if project_root_path.is_empty():
		var narrative_manager: Node = get_node_or_null("/root/NarrativeProjectManager")
		if narrative_manager != null:
			project_root_path = str(narrative_manager.get("current_project_path")).strip_edges()

	if _validator == null or not _validator.has_method("validate_commands"):
		return {"ok": true, "errors": [], "summary": "validator unavailable"}

	return _validator.validate_commands(commands, validation_project, project_root_path, {
		"min_choice_count": 0,
		"max_choice_count": 0,
	})


func _build_retry_prompt(result: Dictionary) -> String:
	var error_lines: Array = result.get("errors", [])
	var retry_lines: Array[String] = []
	retry_lines.append(_base_prompt)
	retry_lines.append("")
	retry_lines.append("上一次输出未通过校验。请完整重写整段 DSL，不要只修补局部。")
	retry_lines.append("必须修复以下问题：")
	if error_lines.is_empty():
		retry_lines.append("- 输出未满足预览场景的结构或素材约束。")
	else:
		for entry in error_lines:
			retry_lines.append("- %s" % str(entry))
	retry_lines.append("仍然只能输出 DSL 本体，不能输出解释、markdown 或代码块。")
	return "\n".join(retry_lines).strip_edges()


func _build_retry_prompt_v2(result: Dictionary) -> String:
	var error_lines: Array = result.get("errors", [])
	var retry_lines: Array[String] = []
	retry_lines.append(_base_prompt)
	retry_lines.append("")
	retry_lines.append("上一次输出未通过校验。请完整重写整段 DSL，不要只修补局部。")
	retry_lines.append("必须修复以下问题：")
	if error_lines.is_empty():
		retry_lines.append("- 输出未满足预览场景的结构或素材约束。")
	else:
		for entry in error_lines:
			retry_lines.append("- %s" % str(entry))
	if error_lines.has("没有角色出场命令"):
		retry_lines.append("- 第一条出现 char_001 对白之前，必须先写 char_001.show(position=\"left\"/\"center\"/\"right\", emotion=\"...\")。")
		retry_lines.append("- 不允许让 char_001 在未出场时直接说话。")
	retry_lines.append("仍然只能输出 DSL 本体，不能输出解释、markdown 或代码块。")
	return "\n".join(retry_lines).strip_edges()


func _finalize_valid_dsl(commands: Array) -> void:
	_last_parsed_commands = commands.duplicate(true)
	_build_preview_scene_package()
	play_button.disabled = _preview_project == null or _preview_scene == null
	_set_status("DSL 已通过校验，正在交给 AVGRunner。", Color(0.66, 0.92, 0.72, 1.0))
	call_deferred("_play_preview_scene")


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


func _count_command_types(commands: Array) -> Dictionary:
	var counts: Dictionary = {}
	for command in commands:
		var command_type: String = ""
		if command != null:
			command_type = str(command.command_type)
		if command_type.is_empty():
			continue
		counts[command_type] = int(counts.get(command_type, 0)) + 1
	return counts


func _build_preview_scene_package() -> void:
	if _last_parsed_commands.is_empty():
		_preview_project = null
		_preview_scene = null
		return

	var project: Resource = _build_preview_project()
	var root := AVGRootNodeClass.new()
	root.node_id = "root"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(1920, 1080)
	root.command_tabs = [ {
		"commands": _last_parsed_commands.duplicate(true),
		"condition_commands": [],
		"mode": 0
	}]

	var scene := AVGSceneClass.new()
	scene.scene_id = "date_preview_scene"
	scene.scene_name = "Date DSL Preview"
	scene.nodes = [root]
	scene.local_variables = []

	if project != null:
		project.project_name = "date_dsl_preview"
		project.scenes = [scene]

	_preview_project = project
	_preview_scene = scene


func _build_preview_project() -> Resource:
	var current_project: Resource = null
	var narrative_manager: Node = get_node_or_null("/root/NarrativeProjectManager")
	if narrative_manager != null:
		current_project = narrative_manager.get("current_project")
	if current_project == null:
		var storage: Node = get_node_or_null("/root/StorageManager")
		if storage != null:
			current_project = storage.get("current_project")

	var project: Resource = null
	if current_project != null:
		project = current_project.duplicate(true)
	else:
		project = AVGProjectClass.new()

	if project == null:
		return null

	if project.characters.is_empty():
		var heroine: Resource = _build_preview_heroine()
		project.characters = [heroine] if heroine != null else []
	project.events = []
	project.variables = []
	project.shared_nodes = []
	project.screen_configs = {}
	return project


func _build_preview_heroine() -> Resource:
	if not ResourceLoader.exists(HEROINE_TEMPLATE_PATH):
		return null
	var template: Resource = load(HEROINE_TEMPLATE_PATH)
	if template == null:
		return null
	var heroine: Resource = template.duplicate(true)
	heroine.display_name = "林夏"
	heroine.character_name = "LinXia"
	heroine.profile = "Placeholder heroine for date DSL preview."
	return heroine


func _play_preview_scene() -> void:
	if scene_runner == null or _preview_project == null or _preview_scene == null:
		return
	if scene_runner.has_method("reset"):
		scene_runner.reset()
	if scene_runner.has_method("load_project"):
		scene_runner.load_project(_preview_project)
	if scene_runner.has_method("load_scene"):
		scene_runner.load_scene(_preview_scene)
	if scene_runner.has_method("start"):
		scene_runner.start()


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.modulate = color
