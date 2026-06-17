extends Node

const GamePreviewerScene = preload("res://scenes/apps/game_previewer/game_previewer.tscn")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")


func _ready() -> void:
	print("=== GamePreviewer Test ===")

	var previewer: Control = GamePreviewerScene.instantiate()
	add_child(previewer)
	await _flush_frames(2)

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null or storage.get("current_project") == null:
		print("[SKIP] StorageManager current_project unavailable")
		return

	previewer.call("set_project", storage.get("current_project"))
	var preview_completed_payloads: Array[Dictionary] = []
	previewer.preview_completed.connect(func(payload: Dictionary) -> void:
		preview_completed_payloads.append(payload.duplicate(true))
	)

	previewer.is_playing = true
	previewer.scene_runner.is_running = true
	previewer.call("_on_scene_ended", "scene_jump_source")
	await _flush_frames(2)
	print("  jump scene ignored as preview end: %s (expect true)" % str(preview_completed_payloads.is_empty()))
	print("  preview still playing after jump: %s (expect true)" % str(bool(previewer.get("is_playing"))))

	previewer.scene_runner.is_running = false
	previewer.call("_on_scene_ended", "scene_final")
	await _flush_frames(2)
	print("  preview completed after final end: %s (expect 1)" % str(preview_completed_payloads.size()))
	if not preview_completed_payloads.is_empty():
		print("  final end scene id: %s (expect scene_final)" % str(preview_completed_payloads[0].get("scene_id", "")))

	preview_completed_payloads.clear()
	previewer.is_playing = true
	var natural_scene := AVGSceneClass.new()
	natural_scene.scene_id = "scene_natural_end"
	previewer.scene_runner.current_scene = natural_scene
	previewer.scene_runner.is_running = true
	previewer.scene_runner._is_blocked = false
	previewer.scene_runner._main_index = 1
	previewer.scene_runner._main_queue = [1]
	previewer.scene_runner._call_stack.clear()
	if previewer.scene_runner.choice_display != null and previewer.scene_runner.choice_display.has_method("clear_choices"):
		previewer.scene_runner.choice_display.clear_choices()
	if previewer.scene_runner.dialog_box != null:
		previewer.scene_runner.dialog_box.visible = false
	await _flush_frames(2)
	print("  natural playback complete triggered: %s (expect 1)" % str(preview_completed_payloads.size()))
	if not preview_completed_payloads.is_empty():
		print("  natural end scene id: %s (expect scene_natural_end)" % str(preview_completed_payloads[0].get("scene_id", "")))

	previewer.queue_free()
	print("=== Test Complete ===")


func _flush_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame