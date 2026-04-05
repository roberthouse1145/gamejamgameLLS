extends Control

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")
const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")
const CharacterDisplayClass = preload("res://scripts/avg/runtime/character_display.gd")


class MockProject extends Resource:
	var characters: Array = []


var _parser: RefCounted = ParserClass.new()
var _validator: RefCounted = ValidatorClass.new()
var _all_passed: bool = true
var _character_display: CharacterDisplay = null


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Stage Set Layout Test ===")
	_test_parser_stage_set()
	_test_validator_stage_set()
	await _test_character_display_stage_set()

	if _all_passed:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ SOME TESTS FAILED")

	print("=== Tests Complete ===")


func _test_parser_stage_set() -> void:
	var result: Dictionary = _parser.parse('stage.set("LinXia", "Shopkeeper", emotions="happy,neutral", outfits="casual,_")')
	_assert_true("parser success", bool(result.get("success", false)), str(result.get("errors", [])))
	if not bool(result.get("success", false)):
		return

	var commands: Array = result.get("commands", [])
	_assert_true("parser command count", commands.size() == 1, "count=%d" % commands.size())
	if commands.is_empty():
		return

	var command: AVGCommand = commands[0]
	var characters: Array = command.params.get("characters", [])
	_assert_equal("parser command_type", command.command_type, "STAGE_SET")
	_assert_equal("parser characters size", characters.size(), 2)
	_assert_equal("parser first character", str(characters[0]), "LinXia")
	_assert_equal("parser second character", str(characters[1]), "Shopkeeper")
	_assert_equal("parser characters_csv", str(command.params.get("characters_csv", "")), "LinXia,Shopkeeper")
	_assert_equal("parser emotions", str(command.params.get("emotions", "")), "happy,neutral")
	_assert_equal("parser outfits", str(command.params.get("outfits", "")), "casual,_")


func _test_validator_stage_set() -> void:
	var project := MockProject.new()
	project.characters = [_make_character("char_linxia", "LinXia", "林夏"), _make_character("char_shopkeeper", "Shopkeeper", "店员")]

	var valid_command := AVGCommandClass.new("STAGE_SET", {
		"characters": ["LinXia", "Shopkeeper"],
		"emotions": "happy,neutral",
		"outfits": "casual,uniform",
	})
	var valid_result: Dictionary = _validator.validate_commands([valid_command], project, "res://")
	_assert_true("validator accepts valid stage_set", bool(valid_result.get("ok", false)), str(valid_result.get("errors", [])))

	var invalid_command := AVGCommandClass.new("STAGE_SET", {
		"characters": ["LinXia", "Shopkeeper"],
		"emotions": "happy",
	})
	var invalid_result: Dictionary = _validator.validate_commands([invalid_command], project, "res://")
	_assert_true("validator rejects mismatched emotions", not bool(invalid_result.get("ok", true)), "expected mismatch error")
	_assert_true(
		"validator mismatch error text",
		_errors_contain(invalid_result.get("errors", []), "emotions count"),
		str(invalid_result.get("errors", []))
	)


func _test_character_display_stage_set() -> void:
	_character_display = CharacterDisplayClass.new()
	_character_display.name = "CharacterDisplay"
	add_child(_character_display)
	await get_tree().process_frame

	_character_display.set_design_resolution(Vector2(1000, 1000))
	_character_display.set_character_data({
		"char_linxia": {
			"character_name": "LinXia",
			"display_name": "林夏",
			"available_outfits": ["casual", "uniform"],
			"default_outfit": "casual",
			"sprites": {
				"default": _make_test_texture(120, 260, Color(1.0, 0.6, 0.7, 1.0)),
				"happy": _make_test_texture(120, 260, Color(0.6, 0.9, 1.0, 1.0)),
				"smile": _make_test_texture(120, 260, Color(0.8, 1.0, 0.6, 1.0)),
				"surprised": _make_test_texture(120, 260, Color(1.0, 0.9, 0.5, 1.0)),
			},
		},
		"char_shopkeeper": {
			"character_name": "Shopkeeper",
			"display_name": "店员",
			"available_outfits": ["uniform"],
			"default_outfit": "uniform",
			"sprites": {
				"default": _make_test_texture(110, 250, Color(0.8, 0.8, 1.0, 1.0)),
				"neutral": _make_test_texture(110, 250, Color(0.7, 0.7, 0.9, 1.0)),
			},
		},
	})

	_character_display.stage_set(["LinXia"], "happy", "casual", 0.0)
	await get_tree().process_frame

	var lin_state: Dictionary = _character_display.get_character_state("LinXia")
	_assert_true("single visible", _character_display.is_character_visible("LinXia"), "LinXia should be visible")
	_assert_vector2_eq("single center", _vector_from_variant(lin_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))
	_assert_equal("single emotion", str(lin_state.get("current_emotion", "")), "happy")

	_character_display.stage_set(["LinXia", "Shopkeeper"], "smile,neutral", "casual,uniform", 0.0)
	await get_tree().process_frame

	lin_state = _character_display.get_character_state("LinXia")
	var shop_state: Dictionary = _character_display.get_character_state("Shopkeeper")
	_assert_vector2_eq("double left slot", _vector_from_variant(lin_state.get("position_ratio", Vector2.ZERO)), Vector2(0.33, 0.5))
	_assert_vector2_eq("double right slot", _vector_from_variant(shop_state.get("position_ratio", Vector2.ZERO)), Vector2(0.67, 0.5))
	_assert_true("shopkeeper visible", _character_display.is_character_visible("Shopkeeper"), "Shopkeeper should be visible")
	_assert_equal("double LinXia emotion", str(lin_state.get("current_emotion", "")), "smile")
	_assert_equal("double Shopkeeper emotion", str(shop_state.get("current_emotion", "")), "neutral")

	_character_display.stage_set(["LinXia"], "surprised", "_", 0.0)
	await get_tree().process_frame

	lin_state = _character_display.get_character_state("LinXia")
	_assert_true("shopkeeper hidden after relayout", not _character_display.is_character_visible("Shopkeeper"), "Shopkeeper should be hidden")
	_assert_vector2_eq("return center after exit", _vector_from_variant(lin_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))
	_assert_equal("exit relayout keeps new emotion", str(lin_state.get("current_emotion", "")), "surprised")


func _make_character(character_id: String, character_name: String, display_name: String) -> Resource:
	var character := AVGCharacterClass.new()
	character.character_id = character_id
	character.character_name = character_name
	character.display_name = display_name
	character.default_outfit = "casual" if character_name == "LinXia" else "uniform"
	var outfits: Array[String] = []
	if character_name == "LinXia":
		outfits.append("casual")
		outfits.append("uniform")
	else:
		outfits.append("uniform")
	character.available_outfits = outfits
	character.sprites = {
		"default": _make_test_texture(64, 128, Color(1.0, 0.6, 0.7, 1.0)),
		"happy": _make_test_texture(64, 128, Color(0.6, 0.9, 1.0, 1.0)),
		"smile": _make_test_texture(64, 128, Color(0.8, 1.0, 0.6, 1.0)),
		"surprised": _make_test_texture(64, 128, Color(1.0, 0.9, 0.5, 1.0)),
		"neutral": _make_test_texture(64, 128, Color(0.7, 0.7, 0.9, 1.0)),
	}
	return character


func _make_test_texture(width: int, height: int, color: Color) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _vector_from_variant(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _errors_contain(errors: Array, needle: String) -> bool:
	for entry in errors:
		if str(entry).find(needle) != -1:
			return true
	return false


func _assert_true(label: String, condition: bool, details: String = "") -> void:
	if condition:
		print("PASS: %s" % label)
		return

	_all_passed = false
	if details.is_empty():
		print("FAIL: %s" % label)
	else:
		print("FAIL: %s -- %s" % [label, details])


func _assert_equal(label: String, actual: Variant, expected: Variant) -> void:
	_assert_true(label, actual == expected, "expected=%s actual=%s" % [str(expected), str(actual)])


func _assert_vector2_eq(label: String, actual: Vector2, expected: Vector2) -> void:
	_assert_true(
		label,
		actual.is_equal_approx(expected),
		"expected=%s actual=%s" % [str(expected), str(actual)]
	)
