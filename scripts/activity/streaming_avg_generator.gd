class_name StreamingAVGGenerator
extends Node

signal stream_generated(session_id: String, package: Dictionary)
signal stream_failed(session_id: String, error: String)

const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")
const ParserClass = preload("res://scripts/date_events/streaming_avg_dsl_parser.gd")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")

const PREVIEW_PROMPT_KEY: String = "story_streaming_avg_dsl_preview"
const WRITER_ROLE: String = "date_scene_writer"
const MAX_GENERATION_ATTEMPTS: int = 2

var _parser: RefCounted = ParserClass.new()
var _writer_service: AIService = null
var _writer_ready: bool = false
var _request_context_by_id: Dictionary = {}


func _ready() -> void:
	_setup_ai_service()


func is_available() -> bool:
	return _writer_ready and _writer_service != null


func generate_for_session(session_id: String, session: Dictionary) -> bool:
	if not is_available():
		return false
	if session_id.strip_edges().is_empty() or session.is_empty():
		return false
	var prompt_text: String = _build_prompt(session)
	if prompt_text.is_empty():
		stream_failed.emit(session_id, "empty_stream_prompt")
		return false
	var context: Dictionary = {
		"session_id": session_id,
		"session": session.duplicate(true),
		"base_prompt": prompt_text,
		"attempt": 0,
	}
	return _request_generation(context)


func _setup_ai_service() -> void:
	_writer_service = AIService.new()
	_writer_service.name = "StreamingAVGGeneratorWriter"
	add_child(_writer_service)
	_writer_service.request_completed.connect(_on_writer_completed)
	_writer_service.request_failed.connect(_on_writer_failed)

	var config_mgr := AIConfigManager.get_instance()
	_writer_ready = config_mgr.apply_to_service(_writer_service, WRITER_ROLE)
	if not _writer_ready:
		_writer_ready = config_mgr.apply_to_service(_writer_service, "chat_default")


func _build_prompt(session: Dictionary) -> String:
	var source: String = str(session.get("story_stream_prompt", session.get("stream_prompt", ""))).strip_edges()
	if source.is_empty():
		return ""

	var prompt_key: String = str(session.get("stream_preview_prompt_key", PREVIEW_PROMPT_KEY)).strip_edges()
	if prompt_key.is_empty():
		prompt_key = PREVIEW_PROMPT_KEY

	var ctx: Dictionary = {
		"streaming_scene_source": source,
		"streaming_asset_manifest": _build_asset_prompt_block(),
		"project_shared_context": AVGScenePromptBuilderClass.build_avg_project_shared_context(),
	}
	var prompt_manager: Node = _get_autoload("PromptManager")
	if prompt_manager != null and prompt_manager.has_method("has_prompt") and prompt_manager.has_method("resolve_with_vars"):
		if prompt_manager.has_prompt(prompt_key):
			return str(prompt_manager.resolve_with_vars(prompt_key, ctx)).strip_edges()

	return "\n".join(PackedStringArray([
		"Write a Streaming AVG DSL script.",
		"Return plain DSL text only.",
		"Use the lightweight index timeline commands shown here: @stream \"Title\" host=HostName viewers=228 day=\"第3天\", bg background_alias, host HostName happy casual, say \"text\", chat \"message\", emotion smile, wait 0.6, end.",
		"Use background alias keys from the asset index and character_name values from the character index.",
		"Write chat as message text with optional delay. The final line is end.",
		"",
		"Source:",
		source,
		"",
		"Assets:",
		str(ctx.get("streaming_asset_manifest", "")),
	])).strip_edges()


func _request_generation(context: Dictionary) -> bool:
	var updated_context: Dictionary = context.duplicate(true)
	updated_context["attempt"] = int(updated_context.get("attempt", 0)) + 1

	var messages: Array = [
		{"role": "system", "content": "You are a Streaming AVG DSL writer. Return plain lightweight index Streaming AVG DSL text only."},
		{"role": "user", "content": str(updated_context.get("base_prompt", ""))},
	]
	var request_id: String = _writer_service.chat(messages, {"temperature": 0.72})
	if request_id.is_empty():
		return false
	_request_context_by_id[request_id] = updated_context
	print("[StreamingAVGGenerator] Writer request sent: %s | attempt=%d" % [
		str(updated_context.get("session_id", "")),
		int(updated_context.get("attempt", 0)),
	])
	return true


func _on_writer_completed(request_id: String, response: Dictionary) -> void:
	if not _request_context_by_id.has(request_id):
		return
	var context: Dictionary = _request_context_by_id[request_id]
	_request_context_by_id.erase(request_id)

	var raw_text: String = AIService.extract_content(response).strip_edges()
	var script_text: String = _strip_code_fences(raw_text)
	var validation: Dictionary = _validate_stream_script(script_text)
	if bool(validation.get("ok", false)):
		var package: Dictionary = _build_stream_package(str(context.get("session_id", "")), script_text, validation, context.get("session", {}))
		if package.is_empty():
			stream_failed.emit(str(context.get("session_id", "")), "stream_package_failed")
			return
		stream_generated.emit(str(context.get("session_id", "")), package)
		return

	var attempt: int = int(context.get("attempt", 0))
	if attempt < MAX_GENERATION_ATTEMPTS:
		var retry_context: Dictionary = context.duplicate(true)
		retry_context["base_prompt"] = _build_retry_prompt(str(context.get("base_prompt", "")), validation)
		if _request_generation(retry_context):
			return

	stream_failed.emit(str(context.get("session_id", "")), str(validation.get("message", "stream_dsl_validation_failed")))


func _on_writer_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_context_by_id.has(request_id):
		return
	var context: Dictionary = _request_context_by_id[request_id]
	_request_context_by_id.erase(request_id)
	stream_failed.emit(str(context.get("session_id", "")), error)


func _validate_stream_script(script_text: String) -> Dictionary:
	if script_text.strip_edges().is_empty():
		return {"ok": false, "message": "empty_stream_dsl", "errors": ["empty_stream_dsl"]}
	var parse_result: Dictionary = _parser.parse(script_text)
	if not bool(parse_result.get("success", false)):
		var text: String = _parser.errors_to_text(parse_result.get("errors", []))
		return {
			"ok": false,
			"message": text if not text.is_empty() else "stream_dsl_parse_failed",
			"errors": parse_result.get("errors", []),
		}

	var asset_result: Dictionary = _parser.validate_assets(
		parse_result.get("events", []),
		_build_runtime_project(),
		_get_project_root_path()
	)
	if not bool(asset_result.get("success", false)):
		var asset_text: String = _parser.errors_to_text(asset_result.get("errors", []))
		return {
			"ok": false,
			"message": asset_text if not asset_text.is_empty() else "stream_asset_validation_failed",
			"errors": asset_result.get("errors", []),
		}

	return {
		"ok": true,
		"events": parse_result.get("events", []),
		"meta": parse_result.get("meta", {}),
		"errors": [],
	}


func _build_stream_package(session_id: String, script_text: String, validation: Dictionary, session: Dictionary) -> Dictionary:
	var project: Resource = _build_runtime_project()
	if project == null:
		return {}
	var meta: Dictionary = validation.get("meta", {})
	var title: String = str(session.get("scene_window_title", meta.get("title", "直播"))).strip_edges()
	if title.is_empty():
		title = "直播"
	return {
		"session_id": session_id,
		"title": title,
		"stream_script": script_text,
		"events": validation.get("events", []),
		"meta": meta,
		"project": project,
		"project_root_path": _get_project_root_path(),
	}


func _build_retry_prompt(base_prompt: String, validation: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(base_prompt)
	lines.append("")
	lines.append("The last Streaming AVG DSL failed validation. Rewrite the whole DSL and fix these issues:")
	var errors: Array = validation.get("errors", [])
	if errors.is_empty():
		lines.append("- The output did not satisfy the Streaming AVG DSL constraints.")
	else:
		for entry in errors:
			if entry is Dictionary:
				lines.append("- line %d: %s" % [int((entry as Dictionary).get("line", 0)), str((entry as Dictionary).get("message", ""))])
			else:
				lines.append("- %s" % str(entry))
	lines.append("")
	lines.append("Return the corrected lightweight index DSL as plain text.")
	return "\n".join(PackedStringArray(lines)).strip_edges()


func _build_asset_prompt_block() -> String:
	var narrative_manager: Node = _get_autoload("NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("build_asset_prompt"):
		var narrative_prompt: String = str(narrative_manager.build_asset_prompt()).strip_edges()
		if not narrative_prompt.is_empty():
			return narrative_prompt
	return "No asset manifest available."


func _build_runtime_project() -> Resource:
	var narrative_manager: Node = _get_autoload("NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("duplicate_current_project"):
		var narrative_project: Resource = narrative_manager.duplicate_current_project()
		if narrative_project != null:
			return narrative_project
	var storage: Node = _get_autoload("StorageManager")
	if storage != null and storage.get("current_project") is Resource:
		return (storage.get("current_project") as Resource).duplicate(true)
	return AVGProjectClass.new()


func _get_project_root_path() -> String:
	var narrative_manager: Node = _get_autoload("NarrativeProjectManager")
	if narrative_manager != null:
		var narrative_path: String = str(narrative_manager.get("current_project_path")).strip_edges()
		if not narrative_path.is_empty():
			return narrative_path
	var storage: Node = _get_autoload("StorageManager")
	if storage != null:
		var storage_path: String = str(storage.get("current_project_path")).strip_edges()
		if not storage_path.is_empty():
			return storage_path
		if storage.get("current_project") is Resource:
			var project: Resource = storage.get("current_project")
			if "project_root_path" in project:
				return str(project.project_root_path).strip_edges()
	return ""


func _get_autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _strip_code_fences(text: String) -> String:
	var sanitized: String = text.strip_edges()
	if sanitized.begins_with("```"):
		var lines: PackedStringArray = sanitized.split("\n")
		if lines.size() >= 2:
			lines.remove_at(0)
			if lines.size() > 0 and str(lines[lines.size() - 1]).strip_edges().begins_with("```"):
				lines.remove_at(lines.size() - 1)
			sanitized = "\n".join(lines).strip_edges()
	return sanitized
