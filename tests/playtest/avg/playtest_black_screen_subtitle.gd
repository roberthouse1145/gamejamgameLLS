extends Control

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")

const SOURCE_PROJECT_PATH: String = "res://narrative_projects/main_story/project.tres"
const SOURCE_PROJECT_ROOT: String = "res://narrative_projects/main_story/"

# ─────────────────────────────────────────────
# 测试用例列表：每项对应一个 DSL 片段
# ─────────────────────────────────────────────
const TEST_CASES: Array = [
	{
		"label": "① 入场: fade（默认）",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="fade")
# => TextBlock(speaker="char_001", expression="default")
> [入场效果: fade] 淡入登场。
char_001.hide(exit_effect="fade")
"""
	},
	{
		"label": "② 入场: slide_from_left  /  离场: slide_to_right",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="slide_from_left")


"""
	},
	{
		"label": "③ 入场: slide_from_right  /  离场: slide_to_left",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="slide_from_right")
# => TextBlock(speaker="char_001", expression="default")
> [入场: slide_from_right] 从右侧滑入。
char_001.hide(exit_effect="slide_to_left")
# => TextBlock()
> [离场: slide_to_left] 向左滑出。
"""
	},
	{
		"label": "④ 入场: slide_from_top  /  离场: slide_to_bottom",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="slide_from_top")
# => TextBlock(speaker="char_001", expression="default")
> [入场: slide_from_top] 从上方滑入。
char_001.hide(exit_effect="slide_to_bottom")
# => TextBlock()
> [离场: slide_to_bottom] 向下滑出。
"""
	},
	{
		"label": "⑤ 入场: slide_from_bottom  /  离场: slide_to_top",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="slide_from_bottom")
# => TextBlock(speaker="char_001", expression="default")
> [入场: slide_from_bottom] 从下方滑入。
char_001.hide(exit_effect="slide_to_top")
# => TextBlock()
> [离场: slide_to_top] 向上滑出。
"""
	},
	{
		"label": "⑥ 入场: pop_in  /  离场: pop_out",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="pop_in")
# => TextBlock(speaker="char_001", expression="default")
> [入场: pop_in] 弹性缩放入场。
char_001.hide(exit_effect="pop_out")
# => TextBlock()
> [离场: pop_out] 弹性缩放离场。
"""
	},
	{
		"label": "⑦ 入场: none（瞬现）  /  离场: none（瞬消）",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="center", emotion="default", enter_effect="none")
# => TextBlock(speaker="char_001", expression="default")
> [入场: none] 瞬间出现，无动画。
char_001.hide(exit_effect="none")
# => TextBlock()
> [离场: none] 瞬间消失，无动画。
"""
	},
	{
		"label": "⑧ 多角色同屏：左右分别 slide_from_left / slide_from_right",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="left", emotion="default", enter_effect="slide_from_left")
char_001.show(position="right", emotion="default", enter_effect="slide_from_right")
# => TextBlock()
> [多角色] 两人同时从两侧滑入。
char_001.hide(exit_effect="slide_to_left")
"""
	},
	{
		"label": "⑨ 位置测试：far_left / far_right / center",
		"dsl": """bg.show("bg003a", fade_duration=0.4)
char_001.show(position="far_left", emotion="default", enter_effect="fade")
# => TextBlock()
> [位置: far_left]
char_001.hide(exit_effect="fade")
char_001.show(position="center", emotion="default", enter_effect="fade")
# => TextBlock()
> [位置: center]
char_001.hide(exit_effect="fade")
char_001.show(position="far_right", emotion="default", enter_effect="fade")
# => TextBlock()
> [位置: far_right]
char_001.hide(exit_effect="fade")
"""
	},
	{
		"label": "⑩ 综合：screen.fade + 多效果串联",
		"dsl": """screen.fade(direction="in", duration=0.4)
bg.show("bg003a", fade_duration=0.4)
char_001.show(position="left", emotion="default", enter_effect="slide_from_left")
# => TextBlock(speaker="char_001", expression="default")
> [综合测试] 从左滑入。
char_001.hide(exit_effect="slide_to_left")
char_001.show(position="right", emotion="default", enter_effect="pop_in")
# => TextBlock(speaker="char_001", expression="default")
> 弹入右侧。
char_001.hide(exit_effect="pop_out")
char_001.show(position="center", emotion="default", enter_effect="slide_from_bottom")
# => TextBlock(speaker="char_001", expression="default")
> 从下方滑入中央。
char_001.effect("bounce")
# => TextBlock(speaker="char_001", expression="default")
> 弹跳效果。
char_001.hide(exit_effect="fade")
screen.fade(direction="out", duration=0.5)
"""
	},
]

@onready var replay_button: Button = %ReplayButton
@onready var status_label: Label = %StatusLabel
@onready var dsl_view: TextEdit = %DslView
@onready var scene_runner: Control = %AVGSceneRunner
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var case_label: Label = %CaseLabel

var _parser: RefCounted = ParserClass.new()
var _test_project: Resource = null
var _current_case: int = 0


func _ready() -> void:
	replay_button.pressed.connect(_play_current)
	prev_button.pressed.connect(_prev_case)
	next_button.pressed.connect(_next_case)
	_update_ui()
	call_deferred("_play_current")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_play_current()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_prev_case()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_next_case()
				get_viewport().set_input_as_handled()


func _prev_case() -> void:
	_current_case = (_current_case - 1 + TEST_CASES.size()) % TEST_CASES.size()
	_update_ui()
	_play_current()


func _next_case() -> void:
	_current_case = (_current_case + 1) % TEST_CASES.size()
	_update_ui()
	_play_current()


func _update_ui() -> void:
	var entry: Dictionary = TEST_CASES[_current_case]
	case_label.text = "%d / %d  %s" % [_current_case + 1, TEST_CASES.size(), entry["label"]]
	dsl_view.text = entry["dsl"]
	prev_button.disabled = false
	next_button.disabled = false


func _play_current() -> void:
	var entry: Dictionary = TEST_CASES[_current_case]
	var dsl: String = entry["dsl"]

	var parse_result: Dictionary = _parser.parse(dsl)
	var errors: Array = parse_result.get("errors", [])
	if not errors.is_empty():
		_show_parse_error(errors)
		return

	var commands: Array = parse_result.get("commands", [])
	_test_project = _build_test_project()
	var test_scene: Resource = _build_test_scene(commands)
	if _test_project == null or test_scene == null:
		status_label.text = "测试场景构建失败"
		return

	_test_project.scenes = [test_scene]

	if scene_runner.has_method("reset"):
		scene_runner.reset()
	if scene_runner.has_method("load_project"):
		scene_runner.load_project(_test_project)
	if scene_runner.has_method("load_scene"):
		scene_runner.load_scene(test_scene)
	if scene_runner.has_method("start"):
		scene_runner.start()

	status_label.text = "播放中。点击推进对白；← → 切换用例；R 重播。"


func _show_parse_error(errors: Array) -> void:
	var lines: Array[String] = ["DSL 解析失败："]
	for entry in errors:
		if entry is Dictionary:
			lines.append("- line %s: %s" % [str(entry.get("line", "?")), str(entry.get("message", entry))])
		else:
			lines.append("- %s" % str(entry))
	status_label.text = "\n".join(lines)


func _build_test_project() -> Resource:
	var source_project: Resource = load(SOURCE_PROJECT_PATH)
	var project: Resource = null
	if source_project != null:
		project = source_project.duplicate(true)
	else:
		project = AVGProjectClass.new()
	if project == null:
		return null
	project.project_name = "char_show_hide_effect_test"
	project.project_root_path = SOURCE_PROJECT_ROOT
	project.events = []
	project.shared_nodes = []
	return project


func _build_test_scene(commands: Array) -> Resource:
	var root := AVGRootNodeClass.new()
	root.node_id = "root"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(2560, 1440)
	root.command_tabs = [{
		"commands": commands.duplicate(true),
		"condition_commands": [],
		"mode": 0
	}]

	var scene := AVGSceneClass.new()
	scene.scene_id = "char_show_hide_effect_test"
	scene.scene_name = "Character Show/Hide Effect Test"
	scene.nodes = [root]
	scene.local_variables = []
	return scene
