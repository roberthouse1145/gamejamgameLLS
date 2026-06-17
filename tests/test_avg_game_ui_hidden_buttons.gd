extends Control

const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGGameUIConfigClass = preload("res://scripts/avg/resources/avg_game_ui_config.gd")
const RunnerScene = preload("res://scenes/avg_runtime/avg_scene_runner.tscn")

var _pass_count: int = 0
var _fail_count: int = 0
var _runner: Control = null


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== AVG game UI hidden buttons test ===")

	_runner = RunnerScene.instantiate() as Control
	add_child(_runner)
	await get_tree().process_frame

	var hidden_project: Resource = _build_project(true)
	_runner.load_project(hidden_project)
	await get_tree().process_frame

	_assert("existing game_ui_config kept", hidden_project.game_ui_config != null, "game_ui_config should exist")
	_assert("hidden config keeps eight buttons", hidden_project.game_ui_config.buttons.size() == 8, "button count changed")
	_assert("hidden config remains hidden after load_project", _all_buttons_hidden(hidden_project.game_ui_config), "load_project reset visible_default")

	_runner._setup_game_ui_buttons()
	await get_tree().process_frame
	_assert("hidden runtime buttons create no button nodes", _game_ui_child_count() == 0, "hidden buttons were rendered")
	_assert("hidden runtime buttons leave action map empty", _runner.get("_game_ui_buttons").is_empty(), "hidden actions were registered")

	var mixed_project: Resource = _build_project(true)
	mixed_project.game_ui_config.buttons[0].visible_default = true
	_runner.load_project(mixed_project)
	await get_tree().process_frame

	_assert("mixed config keeps visible save button", mixed_project.game_ui_config.buttons[0].visible_default, "save visibility was reset")
	_assert("mixed config keeps hidden load button", not mixed_project.game_ui_config.buttons[1].visible_default, "load visibility was reset")
	_runner._setup_game_ui_buttons()
	await get_tree().process_frame
	_assert("mixed runtime buttons render one button", _game_ui_child_count() == 1, "mixed visibility did not drive rendered buttons")
	_assert("mixed runtime action map follows project", _runner.get("_game_ui_buttons").has("save"), "visible save action missing")

	var legacy_project: Resource = _build_project(false)
	_runner.load_project(legacy_project)
	await get_tree().process_frame

	_assert("missing config gets default config", legacy_project.game_ui_config != null, "missing game_ui_config was not created")
	_assert("default config gets eight buttons", legacy_project.game_ui_config.buttons.size() == 8, "default button count mismatch")
	_assert("default config remains visible", not _all_buttons_hidden(legacy_project.game_ui_config), "default buttons should remain visible")

	_runner._setup_game_ui_buttons()
	await get_tree().process_frame
	_assert("default runtime buttons render", _game_ui_child_count() == 8, "default buttons did not render")

	_print_summary()


func _build_project(with_hidden_game_ui: bool) -> Resource:
	var project := AVGProjectClass.new()
	project.project_name = "Game UI Hidden Buttons Test"
	project.resolution = Vector2i(1280, 720)
	project.scenes = [_make_scene()]
	if with_hidden_game_ui:
		var config := AVGGameUIConfigClass.new()
		config.init_defaults()
		for button in config.buttons:
			button.visible_default = false
		project.game_ui_config = config
	return project


func _make_scene() -> Resource:
	var scene := AVGSceneClass.new()
	scene.scene_id = "scene_game_ui_test"
	scene.scene_name = "Game UI Test"
	scene.nodes = []
	scene.local_variables = []
	return scene


func _all_buttons_hidden(config: Resource) -> bool:
	if config == null or config.buttons.is_empty():
		return false
	for button in config.buttons:
		if button.visible_default:
			return false
	return true


func _game_ui_child_count() -> int:
	var container: Node = _runner.get("_game_ui_container") as Node
	if container == null or not is_instance_valid(container):
		return -1
	return container.get_child_count()


func _assert(assert_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % assert_name)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [assert_name, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
