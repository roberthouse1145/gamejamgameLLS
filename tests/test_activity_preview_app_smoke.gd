extends Control

const HOME_APP_SCENE: PackedScene = preload("res://scenes/apps/home/home_app.tscn")
const PART_TIME_APP_SCENE: PackedScene = preload("res://scenes/apps/part_time/part_time_app.tscn")
const MAP_APP_SCENE: PackedScene = preload("res://scenes/apps/map/map_app.tscn")
const SBEAM_APP_SCENE: PackedScene = preload("res://scenes/apps/sbeam/sbeam_app.tscn")


func _ready() -> void:
	print("=== Activity Preview App Smoke Test ===")
	_spawn_app("home", HOME_APP_SCENE, Vector2(0, 0))
	_spawn_app("part_time", PART_TIME_APP_SCENE, Vector2(0, 0))
	_spawn_app("map", MAP_APP_SCENE, Vector2(0, 0))
	_spawn_app("sbeam", SBEAM_APP_SCENE, Vector2(0, 0))
	await get_tree().process_frame
	print("=== Activity Preview App Smoke Test Done ===")


func _spawn_app(label: String, scene: PackedScene, pos: Vector2) -> void:
	var instance := scene.instantiate() as Control
	if instance == null:
		push_error("FAIL: %s instantiate returned null" % label)
		return
	instance.position = pos
	add_child(instance)
	print("  OK: spawned %s" % label)
