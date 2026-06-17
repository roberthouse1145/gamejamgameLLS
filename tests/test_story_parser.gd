extends Node

const StoryCompilerClass = preload("res://scripts/story/story_compiler.gd")
const StoryChapterIndexClass = preload("res://scripts/story/resources/story_chapter_index.gd")
const StoryScriptParserClass = preload("res://scripts/story/story_script_parser.gd")

func _ready() -> void:
	print("=== StoryScriptParser Test ===")
	_test_parse_day1()
	_test_parse_day2_trigger()
	_test_parse_trigger_header()
	_test_compiled_index()
	print("=== All Tests Done ===")


func _test_parse_day1() -> void:
	# 解析 .txt 文件
	var story_data: Dictionary = StoryScriptParserClass.parse_file("res://resources/story/chapters/day1.txt")
	if story_data.is_empty():
		print("FAIL: story_data is empty")
		return

	_assert_eq("chapter_id", story_data.get("chapter_id"), "day1")
	_assert_eq("chapter_name", story_data.get("chapter_name"), "第一天 - 帧语大赛报名")
	_assert_eq("next_chapter", story_data.get("next_chapter"), "day2")

	var story_steps: Array = story_data.get("steps", [])
	_assert_eq("step count", story_steps.size(), 11)
	var last_step: Dictionary = story_steps[story_steps.size() - 1]
	var brief_step: Dictionary = story_steps[7]  # day1_08_open_brief
	var plan_step: Dictionary = story_steps[6]  # day1_07_afternoon_plan
	_assert_eq("last step", last_step.get("step_id", ""), "day1_11_date_avg")
	_assert_eq("last wait type", last_step.get("wait_for", {}).get("type", ""), "date_completed")
	_assert_eq("plan wait type", plan_step.get("wait_for", {}).get("type", ""), "topic_completed")
	_assert_eq("plan wait topic", plan_step.get("wait_for", {}).get("topic_id", ""), "day1_night_plan")
	_assert_eq("brief step id", brief_step.get("step_id", ""), "day1_08_open_brief")
	_assert_eq("brief wait type", brief_step.get("wait_for", {}).get("type", ""), "dev_task_completed")
	_assert_eq("brief wait task", brief_step.get("wait_for", {}).get("task_id", ""), "lock_creative_direction")
	_assert_eq("brief next", brief_step.get("next", ""), "day1_09_night_date_suggest")

	# 打印 story 解析结果摘要
	print("\n--- Story parse summary ---")
	print("chapter_id: %s" % story_data.get("chapter_id"))
	print("chapter_name: %s" % story_data.get("chapter_name"))
	print("steps: %d" % story_steps.size())
	for step in story_steps:
		var actions: Array = step.get("actions", [])
		var action_types: PackedStringArray = []
		for a in actions:
			action_types.append(str(a.get("type", "?")))
		print("  %s -> %s | actions: [%s] | wait: %s" % [
			step.get("step_id", "?"),
			step.get("next", ""),
			", ".join(action_types),
			step.get("wait_for", {}).get("type", "?")
		])


func _test_parse_day2_trigger() -> void:
	var story_data: Dictionary = StoryScriptParserClass.parse_file("res://resources/story/chapters/day2.txt")
	if story_data.is_empty():
		print("FAIL: day2 story_data is empty")
		return

	var trigger: Dictionary = story_data.get("trigger", {})
	_assert_eq("day2.chapter_id", story_data.get("chapter_id"), "day2")
	_assert_eq("day2.next_chapter", story_data.get("next_chapter"), "")
	_assert_eq("day2.trigger.day", trigger.get("day", 0), 2)
	_assert_eq("day2.trigger.phase", trigger.get("phase", ""), "MORNING")
	_assert_true("day2.trigger.required_chapters is array", trigger.get("required_chapters", []) is Array)
	_assert_eq("day2.trigger.required_chapters size", trigger.get("required_chapters", []).size(), 1)
	_assert_eq("day2.trigger.required_chapters[0]", trigger.get("required_chapters", [""])[0], "day1")


func _test_parse_trigger_header() -> void:
	var source := """chapter: trigger_probe
name: Trigger Probe
desc: 测试章节级触发器
priority: 30
trigger:
  min_day: 7
  phase: night
  required_chapters: day1, day3
  excluded_chapters: epilogue
  conditions: signup_completed == true, affection >= 50
next_chapter:

=== trigger_probe_01 ===
wait: immediate
->
"""

	var story_data: Dictionary = StoryScriptParserClass.parse(source)
	var trigger: Dictionary = story_data.get("trigger", {})
	_assert_eq("trigger.chapter_id", story_data.get("chapter_id", ""), "trigger_probe")
	_assert_eq("trigger.priority", story_data.get("priority", 0), 30)
	_assert_eq("trigger.min_day", trigger.get("min_day", 0), 7)
	_assert_eq("trigger.phase", trigger.get("phase", ""), "NIGHT")
	_assert_true("trigger.required_chapters is array", trigger.get("required_chapters", []) is Array)
	_assert_true("trigger.excluded_chapters is array", trigger.get("excluded_chapters", []) is Array)
	_assert_true("trigger.conditions is array", trigger.get("conditions", []) is Array)
	_assert_eq("trigger.required_chapters.size", trigger.get("required_chapters", []).size(), 2)
	_assert_eq("trigger.conditions.size", trigger.get("conditions", []).size(), 2)


func _test_compiled_index() -> void:
	var index_resource: Resource = StoryCompilerClass.compile_all()
	if index_resource == null or not (index_resource is StoryChapterIndexClass):
		print("FAIL: compiled index resource is invalid")
		return

	var chapter_ids: Array[String] = index_resource.get_chapter_ids()
	_assert_true("compiled contains day1", chapter_ids.has("day1"))
	_assert_true("compiled contains day2", chapter_ids.has("day2"))
	_assert_true("compiled contains test_dev", chapter_ids.has("test_dev"))
	_assert_eq("compiled source path", index_resource.chapter_sources.get("day1", ""), "res://resources/story/chapters/day1.txt")

	var loaded_index: Resource = StoryCompilerClass.load_index_resource()
	if loaded_index == null or not (loaded_index is StoryChapterIndexClass):
		print("FAIL: loaded index resource is invalid")
		return

	var loaded_chapter: Resource = loaded_index.get_chapter("day1")
	if loaded_chapter == null:
		print("FAIL: day1 missing from compiled index")
		return

	_assert_eq("loaded compiled chapter_id", loaded_chapter.chapter_id, "day1")
	_assert_eq("loaded compiled next_chapter", loaded_chapter.next_chapter, "day2")
	_assert_eq("loaded compiled step count", loaded_chapter.steps.size(), 11)
	_assert_eq("loaded compiled priority", loaded_chapter.priority, 0)
	_assert_true("loaded compiled trigger empty", loaded_chapter.trigger.is_empty())
	var first_action_apps: Variant = loaded_chapter.steps[0].actions[1].get("apps", [])
	_assert_true("compiled apps is array", first_action_apps is Array)
	_assert_eq("compiled apps first value", first_action_apps[0] if first_action_apps.size() > 0 else "", "linkchat")

	var loaded_day2: Resource = loaded_index.get_chapter("day2")
	if loaded_day2 == null:
		print("FAIL: day2 missing from compiled index")
		return
	_assert_eq("loaded day2 next_chapter", loaded_day2.next_chapter, "")
	_assert_eq("loaded day2 trigger day", loaded_day2.trigger.get("day", 0), 2)
	_assert_eq("loaded day2 trigger phase", loaded_day2.trigger.get("phase", ""), "MORNING")
	_assert_eq("loaded day2 required chapter", loaded_day2.trigger.get("required_chapters", [""])[0], "day1")


func _assert_eq(label: String, got: Variant, expected: Variant) -> void:
	if str(got) == str(expected):
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s — got [%s] expected [%s]" % [label, str(got), str(expected)])


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s" % label)
