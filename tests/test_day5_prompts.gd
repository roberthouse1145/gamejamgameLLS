extends Node

const TOPIC_PATHS: PackedStringArray = [
	"res://resources/story/topics/day5_night_demo_ready.tres",
	"res://resources/story/topics/day5_night_review.tres",
	"res://resources/story/topics/day5_night_sleep_invite.tres",
	"res://resources/story/topics/day5_night_bad_confront.tres",
]

const PROMPT_KEYS: PackedStringArray = [
	"story/day5_night_sleep",
	"story/day5_night_bad_breakup",
]


func _ready() -> void:
	print("=== Day5 Prompt Resource Test ===")
	_test_topics_load()
	_test_story_prompts_resolve()
	print("=== Day5 Prompt Resource Test Done ===")


func _test_topics_load() -> void:
	for path in TOPIC_PATHS:
		var resource: Resource = ResourceLoader.load(path)
		_assert_true("topic loads: %s" % path, resource != null)
		if resource == null:
			continue
		_assert_true("topic has system_prompt: %s" % path, str(resource.get("system_prompt")).strip_edges() != "")


func _test_story_prompts_resolve() -> void:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	_assert_true("PromptManager exists", prompt_manager != null)
	if prompt_manager == null:
		return
	for key in PROMPT_KEYS:
		var has_prompt: bool = bool(prompt_manager.call("has_prompt", key))
		_assert_true("prompt exists: %s" % key, has_prompt)
		if not has_prompt:
			continue
		var content: String = str(prompt_manager.call("resolve", key)).strip_edges()
		_assert_true("prompt resolves: %s" % key, content != "")


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s" % label)
