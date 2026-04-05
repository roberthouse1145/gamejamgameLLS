extends Control

const CharacterDisplayClass = preload("res://scripts/avg/runtime/character_display.gd")

var _character_display: CharacterDisplay = null


func _ready() -> void:
	print("=== Character Reference Resolution Test ===")
	_character_display = CharacterDisplayClass.new()
	_character_display.name = "CharacterDisplay"
	add_child(_character_display)
	await get_tree().process_frame

	_character_display.set_design_resolution(Vector2(1000, 1000))
	_character_display.set_character_data({
		"char_test": {
			"character_name": "LinXia",
			"display_name": "Lin Xia",
			"sprites": {
				"default": _make_test_texture(100, 200, Color(1.0, 0.4, 0.6, 1.0)),
				"smile": _make_test_texture(120, 200, Color(0.4, 0.8, 1.0, 1.0)),
			},
		}
	})

	_character_display.show_character("LinXia", "center", "", 0.0)
	await get_tree().process_frame

	var sprite_by_id: TextureRect = _character_display.get_character_sprite("char_test")
	var sprite_by_name: TextureRect = _character_display.get_character_sprite("LinXia")
	var resolved_display_name: String = _character_display.resolve_visible_character_id("Lin Xia")

	if sprite_by_id == null or sprite_by_name != sprite_by_id or resolved_display_name != "char_test":
		push_error("Character reference resolution failed during show")
		print("[FAIL] show_character did not normalize character_name/display_name")
		print("  sprite_by_id: %s" % str(sprite_by_id))
		print("  sprite_by_name_matches: %s" % str(sprite_by_name == sprite_by_id))
		print("  resolved_display_name: %s" % resolved_display_name)
		return

	var previous_texture: Texture2D = sprite_by_id.texture
	_character_display.change_expression("Lin Xia", "smile", "instant", 0.0)
	await get_tree().process_frame

	if sprite_by_id.texture == previous_texture:
		push_error("Character reference resolution failed during expression change")
		print("[FAIL] change_expression did not resolve display_name")
		return

	_character_display.hide_character("LinXia", 0.0)
	await get_tree().process_frame

	if _character_display.is_character_visible("char_test"):
		push_error("Character reference resolution failed during hide")
		print("[FAIL] hide_character did not resolve character_name")
		return

	print("[OK] CharacterDisplay resolves character_id, character_name, and display_name")
	print("  resolved_display_name: %s" % resolved_display_name)
	print("  expression_changed: %s" % str(sprite_by_id.texture != previous_texture))
	print("  hidden: %s" % str(not _character_display.is_character_visible("char_test")))


func _make_test_texture(width: int, height: int, color: Color) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
