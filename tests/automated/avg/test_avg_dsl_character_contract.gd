extends Node
## AVG DSL 文本说话者与立绘朝向的稳定契约。

const PARSER_CLASS = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const VALIDATOR_CLASS = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")
const GAME_DATA_CLASS = preload("res://scripts/avg/resources/avg_game_data.gd")
const CHARACTER_DISPLAY_SCENE = preload("res://scenes/avg_runtime/character_display.tscn")
const COMMAND_CONTEXT_CLASS = preload("res://scripts/avg/runtime/command_context.gd")
const COMMAND_REGISTRY_CLASS = preload("res://scripts/avg/commands/command_registry.gd")
const COMMAND_INITIALIZER_CLASS = preload("res://scripts/avg/commands/command_initializer.gd")

var _failures: int = 0


func _ready() -> void:
	_test_text_speaker_contract()
	await _test_flip_survives_stage_enter()
	if _failures == 0:
		print("[PASS] avg dsl character contract")
	else:
		push_error("[FAIL] avg dsl character contract: %d checks failed" % _failures)


func _test_text_speaker_contract() -> void:
	var parser := PARSER_CLASS.new()
	var validator := VALIDATOR_CLASS.new()
	var game_data: Resource = GAME_DATA_CLASS.load_game_data()
	var placeholder_parse: Dictionary = parser.parse("# => TextBlock(speaker=\"TextSpeaker\")\n> 拜托——拍到那一刻！")
	var placeholder_validation: Dictionary = validator.validate_commands(
		placeholder_parse.get("commands", []),
		game_data
	)
	_check(not bool(placeholder_validation.get("ok", true)), "TextSpeaker placeholder is rejected")
	_check(
		str(placeholder_validation.get("summary", "")).contains("reserved speaker placeholder"),
		"placeholder validation reports the speaker field"
	)

	var npc_parse: Dictionary = parser.parse("# => TextBlock(speaker=\"游客\")\n> 拜托——拍到那一刻！")
	var npc_validation: Dictionary = validator.validate_commands(npc_parse.get("commands", []), game_data)
	_check(bool(npc_validation.get("ok", false)), "actual text-only NPC display name remains valid")


func _test_flip_survives_stage_enter() -> void:
	var display := CHARACTER_DISPLAY_SCENE.instantiate() as CharacterDisplay
	add_child(display)
	display.set_design_resolution(Vector2(640, 360))
	var image := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	display.set_character_data({
		"ruan_yunyou": {
			"character_name": "柚柚",
			"display_name": "阮云柚",
			"sprites": {"default": texture},
			"default_outfit": "",
		},
		"lu_yuanyuan": {
			"character_name": "鸢鸢",
			"display_name": "陆鸢鸢",
			"sprites": {"default": texture},
			"default_outfit": "",
		},
	})

	var source := "stage.set(\"柚柚\", \"鸢鸢\", duration=0.05, enter_effect=\"fade\")\n鸢鸢.flip(flip=\"off\")\n柚柚.flip(flip=\"on\")"
	var parse_result: Dictionary = PARSER_CLASS.new().parse(source)
	var commands: Array = parse_result.get("commands", [])
	_check(bool(parse_result.get("success", false)), "stage and flip DSL parses")
	_check(commands.size() == 3, "stage and two flip commands are retained")
	if commands.size() == 3:
		_check(str(commands[1].command_type) == "FLIP_CHARACTER", "first flip maps to FLIP_CHARACTER")
		_check(str(commands[1].params.get("character_id", "")) == "鸢鸢", "flip keeps the character reference")
		_check(str(commands[2].params.get("flip", "")) == "on", "flip keeps the requested mode")

	var registry := COMMAND_REGISTRY_CLASS.get_instance()
	COMMAND_INITIALIZER_CLASS.register_all_commands(registry)
	var context := COMMAND_CONTEXT_CLASS.new()
	context.character_display = display
	for command: Resource in commands:
		var handler = registry.get_handler(str(command.command_type))
		if handler != null:
			handler.execute(command, context)
	await get_tree().create_timer(0.08).timeout

	var yunyou_sprite: TextureRect = display.get_character_sprite("柚柚")
	var yuanyuan_sprite: TextureRect = display.get_character_sprite("鸢鸢")
	_check(yunyou_sprite != null and yunyou_sprite.scale.x < 0.0, "flip on survives the stage enter tween")
	_check(yuanyuan_sprite != null and yuanyuan_sprite.scale.x > 0.0, "flip off keeps the default orientation")
	_check(bool(display.get_character_state("柚柚").get("flip", false)), "flip state is stored on the resolved character")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)
