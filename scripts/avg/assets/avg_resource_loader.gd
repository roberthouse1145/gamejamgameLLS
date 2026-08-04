class_name AVGResourceLoader extends RefCounted
## 通过游戏本体的固定素材清单加载 AVG 资源。

const AVGAssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")


static func load_texture(asset_ref: String) -> Texture2D:
	var resolved_path := AVGAssetManifestClass.resolve_texture_path(asset_ref)
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


static func load_audio(asset_ref: String) -> AudioStream:
	var resolved_path := AVGAssetManifestClass.resolve_audio_path(asset_ref)
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
