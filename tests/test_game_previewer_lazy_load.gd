extends Node

const GamePreviewerScene = preload("res://scenes/apps/game_previewer/game_previewer.tscn")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")

var _previewer: Control = null


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Game Previewer Lazy Load Test ===")

	_previewer = GamePreviewerScene.instantiate()
	add_child(_previewer)
	await get_tree().process_frame

	var runner: Node = _previewer.call("get_scene_runner")
	if runner == null:
		print("[FAIL] previewer scene runner missing")
		return

	var project := AVGProjectClass.new()
	project.project_name = "Lazy Load Test"
	project.scenes = [_make_scene("scene_001", "测试场景")]

	_previewer.call("set_project", project)
	await get_tree().process_frame

	if runner.get("current_project") != null:
		print("[FAIL] set_project should not eagerly load runner project")
		return
	print("[OK] set_project does not eagerly load runner project")

	_previewer.call("start_preview")
	await get_tree().process_frame

	if runner.get("current_project") != project:
		print("[FAIL] start_preview should load runner project")
		return
	print("[OK] start_preview lazily loads runner project")

	project.scenes.append(_make_scene("scene_002", "第二场景"))
	StorageManager.notify_content_changed()
	await get_tree().process_frame

	if _previewer.get("_runner_loaded_project") != null:
		print("[FAIL] project content change should invalidate loaded runner project")
		return

	var scene_selector := _previewer.find_child("SceneSelector", true, false) as OptionButton
	if scene_selector == null:
		print("[FAIL] scene selector missing")
		return
	if scene_selector.item_count != 2:
		print("[FAIL] project content change should refresh scene selector, got=%d" % scene_selector.item_count)
		return
	print("[OK] project content change invalidates runner cache and refreshes selector")


func _make_scene(scene_id: String, scene_name: String) -> Resource:
	var scene := AVGSceneClass.new()
	scene.scene_id = scene_id
	scene.scene_name = scene_name
	scene.nodes = []
	return scene
