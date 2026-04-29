extends Node

const AVGSceneGeneratorClass = preload("res://scripts/activity/avg_scene_generator.gd")


func _ready() -> void:
	print("=== Story Scene DSL Prompt Test ===")

	var generator := AVGSceneGeneratorClass.new()
	add_child(generator)

	var session: Dictionary = {
		"activity_type": "story",
		"story_scene_prompt": "林夏在坏结局前夜彻底沉默下来，玩家试图接近她。",
		"story_scene_title": "算了吧",
		"scene_window_title": "算了吧",
		"start_day": 7,
		"phase_after_action": "NIGHT",
		"story_trigger_conversation": [
			{"speaker_name": "林夏", "content": "没戏的，别写了。"},
			{"speaker_name": "玩家", "content": "啊啊啊，为什么？"},
		],
	}

	var prompt: String = str(generator._build_prompt(session)).strip_edges()
	_assert_true("uses story preview wrapper", prompt.contains("剧情事件场景要求"))
	_assert_true("does not use date wrapper", not prompt.contains("普通约会场景要求"))
	_assert_true("marks history as reference only", prompt.contains("前情参考（仅用于承接，不要逐句照抄）"))
	_assert_true("forbids copying chat history", prompt.contains("不要把前情聊天记录逐句照抄"))
	_assert_true("forbids replaying chat logs", prompt.contains("不要先逐句复读一遍聊天记录再进入剧情"))

	print("=== Story Scene DSL Prompt Test Done ===")


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s" % label)
