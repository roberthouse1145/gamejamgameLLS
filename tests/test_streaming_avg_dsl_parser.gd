extends Node

const ParserClass = preload("res://scripts/date_events/streaming_avg_dsl_parser.gd")
const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")


class MockProject extends Resource:
	var characters: Array = []


func _ready() -> void:
	print("=== Streaming AVG DSL parser test ===")
	var parser := ParserClass.new()

	var valid_script := """
@stream "买了老游嘛" host=LinXia viewers=228 day="第3天"
bg bg_apartment_living
host LinXia happy casual
say "abcdef" speed=6 hold=1.0
chat "今天直播爷青回！" delay=0.2
emotion soft_smile
wait 0.6
end
"""
	var result: Dictionary = parser.parse(valid_script)
	if not bool(result.get("success", false)):
		push_error("FAIL: valid script should parse: %s" % parser.errors_to_text(result.get("errors", [])))
		return
	print("  OK: valid script parsed")

	var meta: Dictionary = result.get("meta", {})
	if str(meta.get("title", "")) != "买了老游嘛" or int(meta.get("viewers", 0)) != 228 or str(meta.get("day_label", "")) != "第3天":
		push_error("FAIL: stream meta not parsed correctly: %s" % str(meta))
	else:
		print("  OK: stream meta parsed")

	var subtitle: Dictionary = {}
	for event in result.get("events", []):
		if event is Dictionary and str((event as Dictionary).get("type", "")) == "subtitle":
			subtitle = event as Dictionary
			break
	if subtitle.is_empty():
		push_error("FAIL: subtitle event not found")
	else:
		var duration := float(subtitle.get("duration", 0.0))
		if absf(duration - 2.0) > 0.001:
			push_error("FAIL: subtitle duration should be 2.0, got %.3f" % duration)
		else:
			print("  OK: subtitle timing defaults and overrides parsed")

	var asset_result: Dictionary = parser.validate_assets(result.get("events", []), _make_project(), "res://narrative_projects/main_story/")
	if not bool(asset_result.get("success", false)):
		push_error("FAIL: indexed assets should validate: %s" % parser.errors_to_text(asset_result.get("errors", [])))
	else:
		print("  OK: indexed background alias and character_name validated")

	_expect_failure(parser, "dance 1\nend", "unknown command")
	_expect_failure(parser, "@stream title=\"x\" host=LinXia\nsay\nend", "old stream title parameter")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nsay\nend", "missing say text")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nbg \"res://narrative_projects/main_story/Assets/background/bg_apartment_living.jpg\"\nend", "background path")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nhost char_001 happy casual\nend", "character_id host")
	_expect_failure(parser, "@stream \"x\" host=char_001\nend", "character_id stream host")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nchat \"hello\" user=\"观众A\"\nend", "chat user parameter")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nend summary=\"nope\"", "end summary parameter")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nhost.show \"LinXia\" x=0.5\nend", "host.show command")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nhost LinXia happy casual x=0.5\nend", "host x parameter")
	_expect_failure(parser, "@stream \"x\" host=LinXia\nsay \"hello\" duration=1.0\nend", "say duration parameter")

	print("=== Streaming AVG DSL parser test done ===")


func _make_project() -> Resource:
	var project := MockProject.new()
	var character := AVGCharacterClass.new()
	character.character_id = "char_001"
	character.character_name = "LinXia"
	character.display_name = "林夏"
	character.default_outfit = "casual"
	character.available_outfits = ["casual", "loungewear", "maid"]
	character.sprites = {
		"default": "res://narrative_projects/main_story/Assets/girl_friend/mirai_casual01.png",
		"happy": "res://narrative_projects/main_story/Assets/girl_friend/mirai_casual04.png",
		"soft_smile": "res://narrative_projects/main_story/Assets/girl_friend/mirai_casual08.png",
	}
	character.emotion_slots = {
		"default": "01",
		"happy": "04",
		"soft_smile": "08",
	}
	project.characters = [character]
	return project


func _expect_failure(parser: RefCounted, script: String, label: String) -> void:
	var result: Dictionary = parser.parse(script)
	if bool(result.get("success", false)):
		push_error("FAIL: %s should fail" % label)
	else:
		print("  OK: %s rejected" % label)
