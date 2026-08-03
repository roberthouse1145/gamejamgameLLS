extends Control

const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _runner: Control = null


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== avg runner scene jump transition clear test ===")

	var runner_scene: PackedScene = load("res://scenes/avg_runtime/avg_scene_runner.tscn")
	if runner_scene == null:
		_fail("load avg scene runner", "无法加载 res://scenes/avg_runtime/avg_scene_runner.tscn")
		_print_summary()
		return

	_runner = runner_scene.instantiate() as Control
	add_child(_runner)
	await get_tree().process_frame

	var project: Resource = _build_test_project()
	_runner.load_project(project)
	await _assert_scene_jump_clears_characters(project, false)
	await _assert_scene_jump_clears_characters(project, true)

	_print_summary()


func _assert_scene_jump_clears_characters(project: Resource, use_transition: bool) -> void:
	_runner.reset()
	_runner.load_project(project)
	_runner.load_scene(project.scenes[0])
	await get_tree().process_frame

	var char_display: Node = _runner.character_display
	char_display.show_character("CharacterA", "center", "", 0.0)
	await get_tree().process_frame

	var label: String = "transition" if use_transition else "hard_cut"
	_assert("%s character visible before jump" % label, char_display.is_character_visible("char_test"), "旧场景角色没有成功显示")

	if use_transition:
		_runner.set_jump_transition("fade", 0.0, Color.BLACK)
	await _runner._on_scene_jump_requested("scene_b")
	await get_tree().process_frame

	_assert("%s current scene switched" % label, _runner.current_scene == project.scenes[1], "current_scene 没有切到 scene_b")
	_assert("%s jump clears visible characters" % label, not char_display.is_character_visible("char_test"), "切场景后旧角色仍然可见")


func _build_test_project() -> Resource:
	var character := AVGCharacterClass.new()
	character.character_id = "char_test"
	character.character_name = "CharacterA"
	character.display_name = "Display A"
	character.sprites = {
		"default": _make_test_texture(120, 240, Color(1.0, 0.5, 0.7, 1.0))
	}

	var project := AVGProjectClass.new()
	project.project_name = "Transition Jump Clear Test"
	project.resolution = Vector2i(1280, 720)
	project.characters = [character]
	project.scenes = [
		_make_scene("scene_a", "Scene A"),
		_make_scene("scene_b", "Scene B"),
	]
	return project


func _make_scene(scene_id: String, scene_name: String) -> Resource:
	var root := AVGRootNodeClass.new()
	root.node_id = "root_%s" % scene_id
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(1280, 720)

	var scene := AVGSceneClass.new()
	scene.scene_id = scene_id
	scene.scene_name = scene_name
	scene.nodes = [root]
	scene.local_variables = []
	return scene


func _make_test_texture(width: int, height: int, color: Color) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _assert(assert_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % assert_name)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [assert_name, detail])


func _fail(assert_name: String, detail: String) -> void:
	_fail_count += 1
	print("FAIL  %s  %s" % [assert_name, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
