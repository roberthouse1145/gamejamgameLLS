class_name AVGResourceLoader extends RefCounted
## 解析 AVG 项目资产别名，并从 res:// 或 user:// 加载运行时资源。

const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")


static func load_texture(asset_ref: String, project: Resource = null, project_root_override: String = "") -> Texture2D:
	var resolved_path := _resolve_path(asset_ref, project, project_root_override, false)
	if resolved_path.is_empty():
		return null
	if resolved_path.begins_with("res://"):
		if not ResourceLoader.exists(resolved_path):
			return null
		return ResourceLoader.load(resolved_path) as Texture2D
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(resolved_path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func load_audio(asset_ref: String, project: Resource = null, project_root_override: String = "") -> AudioStream:
	var resolved_path := _resolve_path(asset_ref, project, project_root_override, true)
	if resolved_path.is_empty():
		return null
	if resolved_path.begins_with("res://"):
		if not ResourceLoader.exists(resolved_path):
			return null
		return ResourceLoader.load(resolved_path) as AudioStream
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	match resolved_path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(data)
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = data
			return stream
	return null


static func _resolve_path(asset_ref: String, project: Resource, project_root_override: String, audio: bool) -> String:
	var normalized_ref := asset_ref.strip_edges()
	if normalized_ref.is_empty():
		return ""
	var project_root := _resolve_project_root(project, project_root_override)
	var resolved := ""
	if audio:
		resolved = AVGAssetManifestClass.resolve_audio_path(normalized_ref, project_root)
	else:
		resolved = AVGAssetManifestClass.resolve_texture_path(normalized_ref, project_root)
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		return resolved
	if project_root.is_empty():
		return ""
	return project_root.path_join(resolved)


static func _resolve_project_root(project: Resource, project_root_override: String) -> String:
	var root := project_root_override.strip_edges()
	if root.is_empty() and project != null and "project_root_path" in project:
		root = str(project.get("project_root_path")).strip_edges()
	if root.is_empty():
		return ""
	return root if root.ends_with("/") else root + "/"
