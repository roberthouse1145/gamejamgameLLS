extends Node

const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")

const DEFAULT_PROJECT_PATH: String = "res://narrative_projects/avg_template/"

var current_project_path: String = ""
var current_project: Resource = null
var developer_mode: bool = true

signal current_project_changed(project: Resource)


func _ready() -> void:
	if not OS.has_feature("editor"):
		developer_mode = false
	_auto_load_default_project()


func _auto_load_default_project() -> void:
	var project: Resource = load_project(DEFAULT_PROJECT_PATH)
	if project == null:
		push_warning("[NarrativeProjectManager] Failed to load default narrative project")
		return
	set_current_project(project, DEFAULT_PROJECT_PATH)
	print("[NarrativeProjectManager] Loaded default narrative project: %s" % project.project_name)


func load_project(project_path: String) -> Resource:
	var normalized_path: String = _normalize_project_path(project_path)
	if normalized_path.is_empty():
		return null

	var project_file_path: String = normalized_path + "project.tres"
	if not ResourceLoader.exists(project_file_path):
		push_warning("[NarrativeProjectManager] Project file not found: %s" % project_file_path)
		return null

	var project: Resource = ResourceLoader.load(project_file_path)
	if project == null:
		push_warning("[NarrativeProjectManager] Failed to load project: %s" % project_file_path)
		return null

	if "project_root_path" in project:
		project.set("project_root_path", normalized_path)
	return project


func set_current_project(project: Resource, project_path: String = "") -> void:
	current_project = project
	current_project_path = _normalize_project_path(project_path)
	if project != null and "project_root_path" in project and not current_project_path.is_empty():
		project.set("project_root_path", current_project_path)
	current_project_changed.emit(project)


func save_project(project: Resource = null) -> Error:
	if is_runtime_read_only():
		push_warning("[NarrativeProjectManager] Runtime mode is read-only; refusing to save narrative project")
		return ERR_CANT_CREATE

	var target_project: Resource = project if project != null else current_project
	if target_project == null:
		return ERR_INVALID_PARAMETER

	var normalized_path: String = current_project_path
	if normalized_path.is_empty() and "project_root_path" in target_project:
		normalized_path = _normalize_project_path(str(target_project.get("project_root_path")))
	if normalized_path.is_empty():
		normalized_path = DEFAULT_PROJECT_PATH

	if "project_root_path" in target_project:
		target_project.set("project_root_path", normalized_path)

	var subresource_err: Error = _save_external_project_resources(target_project, normalized_path)
	if subresource_err != OK:
		return subresource_err

	var save_err: Error = ResourceSaver.save(target_project, normalized_path + "project.tres")
	if save_err == OK:
		current_project = target_project
		current_project_path = normalized_path
		current_project_changed.emit(target_project)
	return save_err


func get_asset_manifest() -> Dictionary:
	return AVGAssetManifestClass.load_manifest(current_project_path)


func resolve_texture_path(asset_ref: String) -> String:
	return AVGAssetManifestClass.resolve_texture_path(asset_ref, current_project_path)


func resolve_audio_path(asset_ref: String) -> String:
	return AVGAssetManifestClass.resolve_audio_path(asset_ref, current_project_path)


func build_asset_prompt() -> String:
	return AVGAssetManifestClass.build_llm_prompt_block(current_project_path, current_project)


func has_current_project() -> bool:
	return current_project != null


func is_runtime_read_only() -> bool:
	return not developer_mode


func duplicate_current_project() -> Resource:
	if current_project == null:
		return null
	return current_project.duplicate(true)


func duplicate_dialog_settings() -> Resource:
	if current_project == null:
		return null
	if not ("dialog_settings" in current_project):
		return null
	var dialog_settings: Resource = current_project.dialog_settings
	if dialog_settings == null:
		return null
	return dialog_settings.duplicate(true)


func _normalize_project_path(project_path: String) -> String:
	var trimmed_path: String = project_path.strip_edges()
	if trimmed_path.is_empty():
		return ""
	return trimmed_path if trimmed_path.ends_with("/") else trimmed_path + "/"


func _save_external_project_resources(project: Resource, project_root: String) -> Error:
	var resources: Array[Resource] = []
	_collect_project_resources(project, resources)
	var visited: Dictionary = {}
	for resource in resources:
		if resource == null:
			continue
		var resource_path: String = str(resource.resource_path).strip_edges()
		if resource_path.is_empty() or resource_path.contains("::") or not resource_path.begins_with(project_root):
			continue
		if visited.has(resource_path):
			continue
		visited[resource_path] = true
		var save_err: Error = ResourceSaver.save(resource, resource_path)
		if save_err != OK:
			push_warning("[NarrativeProjectManager] Failed to save subresource: %s" % resource_path)
			return save_err
	return OK


func _collect_project_resources(project: Resource, out_resources: Array[Resource]) -> void:
	if project == null:
		return
	if "dialog_settings" in project and project.dialog_settings != null:
		out_resources.append(project.dialog_settings)
	if "title_config" in project and project.title_config != null:
		out_resources.append(project.title_config)
	if "game_ui_config" in project and project.game_ui_config != null:
		out_resources.append(project.game_ui_config)
	for scene in project.scenes:
		if scene is Resource:
			out_resources.append(scene)
	for character in project.characters:
		if character is Resource:
			out_resources.append(character)
	for variable in project.variables:
		if variable is Resource:
			out_resources.append(variable)
	for event in project.events:
		if event is Resource:
			out_resources.append(event)
	for shared_node in project.shared_nodes:
		if shared_node is Resource:
			out_resources.append(shared_node)
	for config in project.screen_configs.values():
		if config is Resource:
			out_resources.append(config)
