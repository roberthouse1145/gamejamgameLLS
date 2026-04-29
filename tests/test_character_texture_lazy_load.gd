extends Control

const CharacterDisplayClass = preload("res://scripts/avg/runtime/character_display.gd")

var _character_display: CharacterDisplay = null
var _textures: Dictionary = {}
var _load_calls: Dictionary = {}


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Character Texture Lazy Load Test ===")

	_character_display = CharacterDisplayClass.new()
	_character_display.name = "CharacterDisplay"
	add_child(_character_display)
	await get_tree().process_frame

	_character_display.set_design_resolution(Vector2(1000, 1000))
	_character_display.set_texture_loader(Callable(self, "_mock_load_texture"))

	_textures = {
		"portrait_idle": _make_test_texture(100, 200, Color(1.0, 0.4, 0.6, 1.0)),
		"portrait_smile": _make_test_texture(120, 200, Color(0.4, 0.8, 1.0, 1.0)),
	}
	_character_display.set_character_data({
		"char_test": {
			"character_name": "LazyChar",
			"display_name": "Lazy Char",
			"sprites": {
				"default": "portrait_idle",
				"smile": "portrait_smile",
			},
		}
	})

	if not _load_calls.is_empty():
		print("[FAIL] set_character_data should not eagerly load textures")
		return

	_character_display.show_character("char_test", "center", "", 0.0)
	await get_tree().process_frame

	var sprite: TextureRect = _character_display.get_character_sprite("char_test")
	if sprite == null or sprite.texture != _textures["portrait_idle"]:
		print("[FAIL] default texture was not loaded on demand")
		return
	if int(_load_calls.get("portrait_idle", 0)) != 1:
		print("[FAIL] default texture load count mismatch: %s" % str(_load_calls))
		return
	print("[OK] default texture loads on demand")

	_character_display.change_expression("char_test", "smile", "instant", 0.0)
	await get_tree().process_frame
	if sprite.texture != _textures["portrait_smile"]:
		print("[FAIL] smile texture was not loaded on demand")
		return
	if int(_load_calls.get("portrait_smile", 0)) != 1:
		print("[FAIL] smile texture load count mismatch: %s" % str(_load_calls))
		return
	print("[OK] expression texture loads on demand")

	_character_display.change_expression("char_test", "default", "instant", 0.0)
	await get_tree().process_frame
	if sprite.texture != _textures["portrait_idle"]:
		print("[FAIL] default texture was not restored")
		return
	if int(_load_calls.get("portrait_idle", 0)) != 1:
		print("[FAIL] cached default texture should not reload: %s" % str(_load_calls))
		return
	print("[OK] previously loaded texture is reused from cache")


func _mock_load_texture(asset_ref: String) -> Texture2D:
	var key: String = asset_ref.strip_edges()
	_load_calls[key] = int(_load_calls.get(key, 0)) + 1
	return _textures.get(key, null)


func _make_test_texture(width: int, height: int, color: Color) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
