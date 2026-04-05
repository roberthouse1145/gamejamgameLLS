extends Node

const StoryCompilerClass = preload("res://scripts/story/story_compiler.gd")
const StoryChapterIndexClass = preload("res://scripts/story/resources/story_chapter_index.gd")
const StoryScriptParserClass = preload("res://scripts/story/story_script_parser.gd")

func _ready() -> void:
	print("=== StoryScriptParser Test ===")
	_test_parse_day1()
	_test_compiled_index()
	print("=== All Tests Done ===")


func _test_parse_day1() -> void:
	# 解析 .txt 文件
	var story_data: Dictionary = StoryScriptParserClass.parse_file("res://resources/story/chapters/day1.txt")
	if story_data.is_empty():
		print("FAIL: story_data is empty")
		return

	# 解析 .json 文件
	var json_file: FileAccess = FileAccess.open("res://resources/story/chapters/day1.json", FileAccess.READ)
	if json_file == null:
		print("FAIL: cannot open day1.json")
		return
	var json_data: Dictionary = JSON.parse_string(json_file.get_as_text())
	json_file.close()

	# 比较章节头部
	_assert_eq("chapter_id", story_data.get("chapter_id"), json_data.get("chapter_id"))
	_assert_eq("chapter_name", story_data.get("chapter_name"), json_data.get("chapter_name"))
	_assert_eq("next_chapter", story_data.get("next_chapter"), json_data.get("next_chapter"))

	# 比较步骤数量
	var story_steps: Array = story_data.get("steps", [])
	var json_steps: Array = json_data.get("steps", [])
	_assert_eq("step count", story_steps.size(), json_steps.size())

	# 逐步骤比较
	var count: int = mini(story_steps.size(), json_steps.size())
	for i in range(count):
		var ss: Dictionary = story_steps[i]
		var js: Dictionary = json_steps[i]
		var sid: String = ss.get("step_id", "?")
		_assert_eq("%s.step_id" % sid, ss.get("step_id"), js.get("step_id"))
		_assert_eq("%s.next" % sid, ss.get("next", ""), js.get("next", ""))

		# 比较 actions 数量
		var sa: Array = ss.get("actions", [])
		var ja: Array = js.get("actions", [])
		_assert_eq("%s.actions.size" % sid, sa.size(), ja.size())

		# 比较每个 action 的 type
		for ai in range(mini(sa.size(), ja.size())):
			_assert_eq("%s.action[%d].type" % [sid, ai], sa[ai].get("type"), ja[ai].get("type"))
			if sa[ai].get("type") == "set_app_access":
				_assert_true("%s.action[%d].apps is array" % [sid, ai], sa[ai].get("apps", []) is Array)

		# 比较 wait_for.type
		var sw: Dictionary = ss.get("wait_for", {})
		var jw: Dictionary = js.get("wait_for", {})
		_assert_eq("%s.wait_for.type" % sid, sw.get("type"), jw.get("type"))

		# 比较 capture 键集合
		var sc: Dictionary = ss.get("capture", {})
		var jc: Dictionary = js.get("capture", {})
		if jc.size() > 0 or sc.size() > 0:
			_assert_eq("%s.capture.keys" % sid, sc.keys(), jc.keys())

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


func _test_compiled_index() -> void:
	var index_resource: Resource = StoryCompilerClass.compile_all()
	if index_resource == null or not (index_resource is StoryChapterIndexClass):
		print("FAIL: compiled index resource is invalid")
		return

	var chapter_ids: Array[String] = index_resource.get_chapter_ids()
	_assert_eq("compiled chapter count", chapter_ids.size(), 1)
	_assert_eq("compiled chapter id", chapter_ids[0] if not chapter_ids.is_empty() else "", "day1")
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
	_assert_eq("loaded compiled step count", loaded_chapter.steps.size(), 10)
	var first_action_apps: Variant = loaded_chapter.steps[0].actions[1].get("apps", [])
	_assert_true("compiled apps is array", first_action_apps is Array)
	_assert_eq("compiled apps first value", first_action_apps[0] if first_action_apps.size() > 0 else "", "linkchat")


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
