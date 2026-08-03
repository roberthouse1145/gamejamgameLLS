extends Control

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")
const AVGDSLValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")

class MockProject extends Resource:
	var characters: Array = []


func _ready() -> void:
	print("=== AVG DSL Character Reference Validator Test ===")

	var character := AVGCharacterClass.new()
	character.character_id = "char_a"
	character.character_name = "CharacterA"
	character.display_name = "Display A"
	character.sprites = {
		"default": _make_test_texture(64, 128, Color(1.0, 0.6, 0.7, 1.0)),
		"smile": _make_test_texture(64, 128, Color(0.6, 0.9, 1.0, 1.0)),
	}
	character.available_outfits = ["uniform"]
	character.default_outfit = "uniform"

	var project := MockProject.new()
	project.characters = [character]

	var commands: Array = [
		AVGCommandClass.new("SHOW_CHARACTER", {"character_id": "Display A", "emotion": "smile", "outfit": "uniform"}),
		AVGCommandClass.new("CHANGE_EXPRESSION", {"character_id": "CharacterA", "expression": "smile"}),
		AVGCommandClass.new("CHANGE_OUTFIT", {"character_id": "Display A", "outfit": "uniform", "emotion": "default"}),
	]

	var validator := AVGDSLValidatorClass.new()
	var result: Dictionary = validator.validate_commands(commands, project, "res://")

	if not bool(result.get("ok", false)):
		push_error("AVG DSL validator did not accept display_name / character_name references")
		print("[FAIL] validator rejected non-id character references")
		print("  errors: %s" % str(result.get("errors", [])))
		return

	print("[OK] AVG DSL validator accepts character_id, character_name, and display_name")
	print("  summary: %s" % str(result.get("summary", "")))


func _make_test_texture(width: int, height: int, color: Color) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
