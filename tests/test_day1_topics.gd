extends Node

const DATE_SUGGEST_TOPIC_PATH: String = "res://resources/story/topics/day1_date_suggest.tres"


func _ready() -> void:
	print("=== Day1 Topic Resource Test ===")
	_test_date_suggest_topic_is_one_shot()
	print("=== Day1 Topic Resource Test Done ===")


func _test_date_suggest_topic_is_one_shot() -> void:
	var topic: Resource = ResourceLoader.load(DATE_SUGGEST_TOPIC_PATH)
	_assert_true("date suggest topic loads", topic != null)
	if topic == null:
		return

	var prompt: String = str(topic.get("system_prompt"))
	var context_data: Dictionary = topic.get("context_data")
	_assert_true("date suggest auto completes after first reply", bool(context_data.get("complete_after_first_reply", false)))
	_assert_true("date suggest requires complete marker", prompt.contains("[TOPIC_COMPLETE]"))
	_assert_true("date suggest forbids asking destination", prompt.contains("不要问“你想去哪”"))
	_assert_true("date suggest points to map app", prompt.contains("地图 APP"))


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s" % label)
