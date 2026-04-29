extends Control

const RunnerScene = preload("res://scenes/avg_runtime/avg_scene_runner.tscn")

const IMAGE_A_PATH: String = "res://Assets/images/app_icons/icon_knowledge_base.png"
const IMAGE_B_PATH: String = "res://Assets/heroine01_cos01.png"

var _runner: Control = null


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Image layer transition runtime test ===")

	_runner = RunnerScene.instantiate()
	_runner.name = "AVGSceneRunner"
	add_child(_runner)
	await get_tree().process_frame

	_runner.show_image("cg", IMAGE_A_PATH, Vector2.ZERO, Vector2.ONE, 0.0, 10, "instant")
	await get_tree().process_frame

	if not _runner._displayed_images.has("cg"):
		print("[FAIL] initial cg image was not shown")
		return

	var first_node: TextureRect = _runner._displayed_images["cg"]
	_runner.show_image("cg", IMAGE_B_PATH, Vector2.ZERO, Vector2.ONE, 1.0, 10, "crossfade")
	await get_tree().process_frame

	if not _runner._image_transition_overlays.has("cg"):
		print("[FAIL] crossfade should keep old cg as overlay during transition")
		return
	if not _runner._displayed_images.has("cg"):
		print("[FAIL] cg should remain registered during crossfade")
		return

	var second_node: TextureRect = _runner._displayed_images["cg"]
	if second_node == first_node:
		print("[FAIL] crossfade should create a new target node")
		return

	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame

	var overlay_node: TextureRect = _runner._image_transition_overlays.get("cg", null)
	if overlay_node == null or not is_instance_valid(overlay_node):
		print("[FAIL] overlay node should still exist mid-transition")
		return
	if overlay_node.modulate.a >= 0.99:
		print("[FAIL] overlay alpha should already be decreasing during crossfade")
		return

	await get_tree().create_timer(1.0).timeout
	await get_tree().process_frame

	if _runner._image_transition_overlays.has("cg"):
		print("[FAIL] crossfade overlay should be cleaned up after transition")
		return
	if not _runner._displayed_images.has("cg"):
		print("[FAIL] cg should still be displayed after crossfade")
		return
	if str(_runner._displayed_images["cg"].get_meta("image_path", "")) != IMAGE_B_PATH:
		print("[FAIL] cg image path should update to the new texture")
		return

	_runner.hide_image("cg", 0.1, "fade")
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame

	if _runner._displayed_images.has("cg"):
		print("[FAIL] cg should be removed after fade hide")
		return

	print("[OK] image layer supports cg crossfade replacement and fade hide")
