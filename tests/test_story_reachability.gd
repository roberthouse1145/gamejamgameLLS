extends Node

const AnalyzerClass = preload("res://scripts/avg/dev_tools/story_reachability_analyzer.gd")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")
const AVGTitleConfigClass = preload("res://scripts/avg/resources/avg_title_config.gd")


func _ready() -> void:
	print("=== Story Reachability Analyzer Test ===")
	_run_test()


func _run_test() -> void:
	var project := AVGProjectClass.new()
	project.project_name = "Reachability Test"

	var score := AVGVariableClass.new()
	score.variable_id = "var_0001"
	AVGVariableClass.apply_key(score, "score")
	score.default_value = 0
	var branch_value := AVGVariableClass.new()
	branch_value.variable_id = "var_0002"
	AVGVariableClass.apply_key(branch_value, "branch_value")
	branch_value.default_value = 1.0
	var route_a := AVGVariableClass.new()
	route_a.variable_id = "var_0003"
	AVGVariableClass.apply_key(route_a, "route_a_score")
	route_a.default_value = 3
	var route_b := AVGVariableClass.new()
	route_b.variable_id = "var_0004"
	AVGVariableClass.apply_key(route_b, "route_b_score")
	route_b.default_value = 1
	project.variables = [score, branch_value, route_a, route_b]

	var title_config := AVGTitleConfigClass.new()
	title_config.first_scene_id = "scene_001"
	project.title_config = title_config

	project.scenes = [
		_make_scene("scene_001", "开场", [
			AVGCommandClass.new("SET_VARIABLE", {"variable_id": "var_0001", "operation": "set", "value_source": "constant", "value": 0}),
			AVGCommandClass.new("IF", {
				"condition_commands": [AVGCommandClass.new("CHECK_VAR", {"variable_id": "var_0001", "operator": ">=", "value_source": "constant", "value": 1})],
				"if_commands": [AVGCommandClass.new("JUMP_SCENE", {"scene_id": "scene_002"})],
				"has_else": true,
				"else_commands": [AVGCommandClass.new("JUMP_SCENE", {"scene_id": "scene_003"})],
			}),
		], "初始场景"),
		_make_scene("scene_002", "不应抵达", [], "需要 score>=1"),
		_make_scene("scene_003", "可达分支", [
			AVGCommandClass.new("IF", {
				"condition_commands": [AVGCommandClass.new("CHECK_CLICK", {"node_id": "node_button"})],
				"if_commands": [AVGCommandClass.new("JUMP_SCENE", {"scene_id": "scene_005"})],
				"has_else": false,
			}),
		], "正常进入"),
		_make_scene("scene_004", "孤立场景", [], "没有任何入口"),
		_make_scene("scene_005", "交互可达", [
			AVGCommandClass.new("IF", {
				"condition_commands": [AVGCommandClass.new("CHECK_VAR", {"variable_id": "var_0001", "operator": "<=", "value_source": "game_data", "game_data_key": "scene_count"})],
				"if_commands": [AVGCommandClass.new("JUMP_SCENE", {"scene_id": "scene_006"})],
				"has_else": false,
			}),
		], "依赖交互与 game_data"),
		_make_scene("scene_006", "game_data 可达", [], "通过 game_data 条件进入"),
		_make_scene("scene_007", "类型不兼容比较", [
			AVGCommandClass.new("IF", {
				"condition_commands": [AVGCommandClass.new("CHECK_VAR", {"variable_id": "var_0002", "operator": ">", "value_source": "constant", "value": "route_a"})],
				"if_commands": [AVGCommandClass.new("JUMP_SCENE", {"scene_id": "scene_008"})],
				"has_else": false,
			}),
		], "模拟 LLM 把字符串拿来做大小比较"),
		_make_scene("scene_008", "类型不兼容目标", [], "不应因分析器崩溃"),
		_make_scene("scene_009", "变量对变量比较", [
			AVGCommandClass.new("IF", {
				"condition_commands": [AVGCommandClass.new("CHECK_VAR", {
					"variable_id": "var_0003",
					"operator": ">",
					"value_source": "variable",
					"source_variable_id": "var_0004",
				})],
				"if_commands": [AVGCommandClass.new("JUMP_SCENE", {"scene_id": "scene_010"})],
				"has_else": false,
			}),
		], "route_a_score 大于 route_b_score"),
		_make_scene("scene_010", "变量对变量目标", [], "应保持可分析"),
	]

	var analyzer := AnalyzerClass.new()
	var result: Dictionary = analyzer.analyze(project)
	if not bool(result.get("success", false)):
		push_error("Reachability analyzer failed: %s" % str(result))
		return

	var data: Dictionary = result.get("data", {})
	var rows: Array = data.get("scene_catalog", [])
	var by_id: Dictionary = {}
	for row in rows:
		by_id[str(row.get("scene_id", ""))] = row

	_assert_true("scene_001 is initial", bool(by_id["scene_001"].get("is_initial", false)))
	_assert_true("scene_003 reachable", str(by_id["scene_003"].get("reachability_status", "")) == "reachable")
	_assert_true("scene_004 isolated", bool(by_id["scene_004"].get("is_isolated", false)))
	_assert_true("scene_002 unreachable", str(by_id["scene_002"].get("reachability_status", "")) == "unreachable")
	_assert_true("scene_005 reachable through click condition", str(by_id["scene_005"].get("reachability_status", "")) == "reachable")
	_assert_true("scene_006 reachable through game_data condition", str(by_id["scene_006"].get("reachability_status", "")) == "reachable")
	_assert_true("scene_007 remains analyzable", by_id.has("scene_007"))
	_assert_true("scene_009 remains analyzable", by_id.has("scene_009"))

	var unreachable_branches: Array = data.get("unreachable_branches", [])
	var found_if_true: bool = false
	for branch in unreachable_branches:
		if str(branch.get("branch_type", "")) == "if_true" and str(branch.get("status", "")) == "unreachable":
			found_if_true = true
	_assert_true("unreachable IF true branch recorded", found_if_true)


func _make_scene(scene_id: String, scene_name: String, commands: Array, note: String) -> Resource:
	var scene := AVGSceneClass.new()
	scene.scene_id = scene_id
	scene.scene_name = scene_name
	scene.scene_note = note

	var root := AVGRootNodeClass.new()
	root.node_id = "node_001"
	root.node_name = "Root"
	root.command_tabs = [{
		"mode": 0,
		"condition_type": 0,
		"commands": commands,
		"condition_commands": [],
	}]
	scene.nodes = [root]
	return scene


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s" % label)
