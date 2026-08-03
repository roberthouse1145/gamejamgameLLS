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
	_test_parser_stage_enter_exit()
	_test_validator_stage_set()
	_test_validator_stage_enter_exit()
	await _test_character_display_stage_set()
	await _test_character_display_stage_enter_exit()
	await _test_text_npc_stage_fallbacks()

	if _all_passed:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ SOME TESTS FAILED")

	print("=== Tests Complete ===")


func _test_parser_stage_set() -> void:
	var result: Dictionary = _parser.parse('stage.set("CharacterA", "CharacterB", emotions="happy,neutral", outfits="casual,_")')
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
	_assert_equal("parser first character", str(characters[0]), "CharacterA")
	_assert_equal("parser second character", str(characters[1]), "CharacterB")
	_assert_equal("parser characters_csv", str(command.params.get("characters_csv", "")), "CharacterA,CharacterB")
	_assert_equal("parser emotions", str(command.params.get("emotions", "")), "happy,neutral")
	_assert_equal("parser outfits", str(command.params.get("outfits", "")), "casual,_")


func _test_parser_stage_enter_exit() -> void:
	var enter_result: Dictionary = _parser.parse('stage.enter("CharacterA", "CharacterB", emotions="happy,neutral", outfits="casual,uniform")')
	_assert_true("stage.enter parser success", bool(enter_result.get("success", false)), str(enter_result.get("errors", [])))
	if bool(enter_result.get("success", false)):
		var enter_command: AVGCommand = enter_result.get("commands", [])[0]
		_assert_equal("stage.enter command_type", enter_command.command_type, "STAGE_ENTER")
		_assert_equal("stage.enter characters_csv", str(enter_command.params.get("characters_csv", "")), "CharacterA,CharacterB")
		_assert_equal("stage.enter emotions", str(enter_command.params.get("emotions", "")), "happy,neutral")

	var exit_result: Dictionary = _parser.parse('stage.exit("CharacterB")')
	_assert_true("stage.exit parser success", bool(exit_result.get("success", false)), str(exit_result.get("errors", [])))
	if bool(exit_result.get("success", false)):
		var exit_command: AVGCommand = exit_result.get("commands", [])[0]
		_assert_equal("stage.exit command_type", exit_command.command_type, "STAGE_EXIT")
		_assert_equal("stage.exit characters_csv", str(exit_command.params.get("characters_csv", "")), "CharacterB")


func _test_validator_stage_set() -> void:
	var project := MockProject.new()
	project.characters = [_make_character("char_a", "CharacterA", "角色甲"), _make_character("char_b", "CharacterB", "角色乙")]

	var valid_command := AVGCommandClass.new("STAGE_SET", {
		"characters": ["CharacterA", "CharacterB"],
		"emotions": "happy,neutral",
		"outfits": "casual,uniform",
	})
	var valid_result: Dictionary = _validator.validate_commands([valid_command], project, "res://")
	_assert_true("validator accepts valid stage_set", bool(valid_result.get("ok", false)), str(valid_result.get("errors", [])))

	var invalid_command := AVGCommandClass.new("STAGE_SET", {
		"characters": ["CharacterA", "CharacterB"],
		"emotions": "happy",
	})
	var invalid_result: Dictionary = _validator.validate_commands([invalid_command], project, "res://")
	_assert_true("validator rejects mismatched emotions", not bool(invalid_result.get("ok", true)), "expected mismatch error")
	_assert_true(
		"validator mismatch error text",
		_errors_contain(invalid_result.get("errors", []), "emotions count"),
		str(invalid_result.get("errors", []))
	)

func _test_validator_stage_enter_exit() -> void:
	var project := MockProject.new()
	project.characters = [_make_character("char_a", "CharacterA", "角色甲"), _make_character("char_b", "CharacterB", "角色乙")]

	var valid_enter := AVGCommandClass.new("STAGE_ENTER", {
		"characters": ["CharacterA", "CharacterB"],
		"emotions": "happy,neutral",
	})
	var enter_result: Dictionary = _validator.validate_commands([valid_enter], project, "res://")
	_assert_true("validator accepts valid stage_enter", bool(enter_result.get("ok", false)), str(enter_result.get("errors", [])))

	var invalid_enter := AVGCommandClass.new("STAGE_ENTER", {
		"characters": ["CharacterA", "CharacterB"],
		"emotions": "happy",
	})
	var invalid_enter_result: Dictionary = _validator.validate_commands([invalid_enter], project, "res://")
	_assert_true("validator rejects mismatched stage_enter emotions", not bool(invalid_enter_result.get("ok", true)), "expected mismatch error")

	var valid_exit := AVGCommandClass.new("STAGE_EXIT", {
		"characters": ["CharacterB"],
	})
	var exit_result: Dictionary = _validator.validate_commands([valid_exit], project, "res://")
	_assert_true("validator accepts valid stage_exit", bool(exit_result.get("ok", false)), str(exit_result.get("errors", [])))

	var text_npc_enter := AVGCommandClass.new("STAGE_ENTER", {
		"characters": ["老板娘"],
	})
	var text_npc_enter_result: Dictionary = _validator.validate_commands([text_npc_enter], project, "res://")
	_assert_true("validator allows text npc stage_enter fallback", bool(text_npc_enter_result.get("ok", false)), str(text_npc_enter_result))
	_assert_true(
		"validator warns on text npc stage_enter",
		_errors_contain(text_npc_enter_result.get("warnings", []), "text-only NPC"),
		str(text_npc_enter_result.get("warnings", []))
	)

	var text_npc_exit := AVGCommandClass.new("STAGE_EXIT", {
		"characters": ["老板娘"],
	})
	var text_npc_exit_result: Dictionary = _validator.validate_commands([text_npc_exit], project, "res://")
	_assert_true("validator allows text npc stage_exit fallback", bool(text_npc_exit_result.get("ok", false)), str(text_npc_exit_result))
	_assert_true(
		"validator warns on text npc stage_exit",
		_errors_contain(text_npc_exit_result.get("warnings", []), "text-only NPC"),
		str(text_npc_exit_result.get("warnings", []))
	)


func _test_character_display_stage_set() -> void:
	_character_display = CharacterDisplayClass.new()
	_character_display.name = "CharacterDisplay"
	add_child(_character_display)
	await get_tree().process_frame

	_character_display.set_design_resolution(Vector2(1000, 1000))
	_character_display.set_character_data({
		"char_character_a": {
			"character_name": "CharacterA",
			"display_name": "角色甲",
			"available_outfits": ["casual", "uniform"],
			"default_outfit": "casual",
			"sprites": {
				"default": _make_test_texture(120, 260, Color(1.0, 0.6, 0.7, 1.0)),
				"happy": _make_test_texture(120, 260, Color(0.6, 0.9, 1.0, 1.0)),
				"smile": _make_test_texture(120, 260, Color(0.8, 1.0, 0.6, 1.0)),
				"surprised": _make_test_texture(120, 260, Color(1.0, 0.9, 0.5, 1.0)),
			},
		},
		"char_character_b": {
			"character_name": "CharacterB",
			"display_name": "角色乙",
			"available_outfits": ["uniform"],
			"default_outfit": "uniform",
			"sprites": {
				"default": _make_test_texture(110, 250, Color(0.8, 0.8, 1.0, 1.0)),
				"neutral": _make_test_texture(110, 250, Color(0.7, 0.7, 0.9, 1.0)),
			},
		},
	})

	_character_display.stage_set(["CharacterA"], "happy", "casual", 0.0)
	await get_tree().process_frame

	var character_a_state: Dictionary = _character_display.get_character_state("CharacterA")
	_assert_true("single visible", _character_display.is_character_visible("CharacterA"), "CharacterA should be visible")
	_assert_vector2_eq("single center", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))
	_assert_equal("single emotion", str(character_a_state.get("current_emotion", "")), "happy")

	_character_display.stage_set(["CharacterA", "CharacterB"], "smile,neutral", "casual,uniform", 0.0)
	await get_tree().process_frame

	character_a_state = _character_display.get_character_state("CharacterA")
	var character_b_state: Dictionary = _character_display.get_character_state("CharacterB")
	_assert_vector2_eq("double left slot", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.35, 0.5))
	_assert_vector2_eq("double right slot", _vector_from_variant(character_b_state.get("position_ratio", Vector2.ZERO)), Vector2(0.65, 0.5))
	_assert_true("character_b visible", _character_display.is_character_visible("CharacterB"), "CharacterB should be visible")
	_assert_equal("double CharacterA emotion", str(character_a_state.get("current_emotion", "")), "smile")
	_assert_equal("double CharacterB emotion", str(character_b_state.get("current_emotion", "")), "neutral")

	_character_display.stage_set(["CharacterA"], "surprised", "_", 0.0)
	await get_tree().process_frame

	character_a_state = _character_display.get_character_state("CharacterA")
	_assert_true("character_b hidden after relayout", not _character_display.is_character_visible("CharacterB"), "CharacterB should be hidden")
	_assert_vector2_eq("return center after exit", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))
	_assert_equal("exit relayout keeps new emotion", str(character_a_state.get("current_emotion", "")), "surprised")


func _test_character_display_stage_enter_exit() -> void:
	_character_display.hide_all(0.0)
	await get_tree().process_frame

	_character_display.stage_enter(["CharacterA"], "happy", "casual", 0.0)
	await get_tree().process_frame
	var character_a_state: Dictionary = _character_display.get_character_state("CharacterA")
	_assert_vector2_eq("stage.enter single center", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))
	_assert_equal("stage.enter single emotion", str(character_a_state.get("current_emotion", "")), "happy")

	_character_display.stage_enter(["CharacterB"], "neutral", "uniform", 0.0)
	await get_tree().process_frame
	character_a_state = _character_display.get_character_state("CharacterA")
	var character_b_state: Dictionary = _character_display.get_character_state("CharacterB")
	_assert_vector2_eq("stage.enter relayout left", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.35, 0.5))
	_assert_vector2_eq("stage.enter relayout right", _vector_from_variant(character_b_state.get("position_ratio", Vector2.ZERO)), Vector2(0.65, 0.5))
	_assert_equal("stage.enter new emotion", str(character_b_state.get("current_emotion", "")), "neutral")

	_character_display.stage_exit(["CharacterA"], 0.0)
	await get_tree().process_frame
	character_b_state = _character_display.get_character_state("CharacterB")
	_assert_true("stage.exit hides CharacterA", not _character_display.is_character_visible("CharacterA"), "CharacterA should be hidden")
	_assert_vector2_eq("stage.exit recenters remaining", _vector_from_variant(character_b_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))


func _test_text_npc_stage_fallbacks() -> void:
	_character_display.hide_all(0.0)
	await get_tree().process_frame

	_character_display.stage_set(["CharacterA"], "happy", "casual", 0.0)
	await get_tree().process_frame

	var character_a_state: Dictionary = _character_display.get_character_state("CharacterA")
	_assert_vector2_eq("text npc baseline center", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))

	_character_display.stage_enter(["老板娘"], "neutral", "_", 0.0)
	await get_tree().process_frame
	character_a_state = _character_display.get_character_state("CharacterA")
	_assert_true("text npc stage_enter keeps CharacterA visible", _character_display.is_character_visible("CharacterA"), "CharacterA should stay visible")
	_assert_vector2_eq("text npc stage_enter does not relayout", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))

	_character_display.stage_set(["CharacterA", "老板娘"], "surprised,neutral", "casual,_", 0.0)
	await get_tree().process_frame
	character_a_state = _character_display.get_character_state("CharacterA")
	_assert_vector2_eq("mixed text npc stage_set ignores empty slot", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))
	_assert_equal("mixed text npc stage_set keeps valid emotion", str(character_a_state.get("current_emotion", "")), "surprised")

	_character_display.stage_set(["老板娘"], "neutral", "_", 0.0)
	await get_tree().process_frame
	_assert_true("text npc only stage_set becomes no-op", _character_display.is_character_visible("CharacterA"), "CharacterA should remain visible")
	character_a_state = _character_display.get_character_state("CharacterA")
	_assert_vector2_eq("text npc only stage_set keeps layout", _vector_from_variant(character_a_state.get("position_ratio", Vector2.ZERO)), Vector2(0.5, 0.5))


func _make_character(character_id: String, character_name: String, display_name: String) -> Resource:
	var character := AVGCharacterClass.new()
	character.character_id = character_id
	character.character_name = character_name
	character.display_name = display_name
	character.default_outfit = "casual" if character_name == "CharacterA" else "uniform"
	var outfits: Array[String] = []
	if character_name == "CharacterA":
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
# End of test helpers.
