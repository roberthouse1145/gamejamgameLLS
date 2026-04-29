extends Node

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const HOME_APP_SCENE: PackedScene = preload("res://resources/apps/home_app.tres").entry_scene


class BusyBlocker extends Node:
	var busy: bool = true

	func is_busy() -> bool:
		return busy


func _ready() -> void:
	print("=== Home App Availability Test ===")
	_test_rest_button_reflects_manager_availability()
	print("=== All tests passed ===")


func _test_rest_button_reflects_manager_availability() -> void:
	var blocker := BusyBlocker.new()
	add_child(blocker)
	ActivityLockUtilsClass.register_free_period_blocker("home_app_test_blocker", blocker, "is_busy", "测试占用中")

	var instance := HOME_APP_SCENE.instantiate() as Control
	assert(instance != null)
	add_child(instance)
	await get_tree().process_frame
	instance.call("_refresh")
	await get_tree().process_frame

	var sleep_button: Button = instance.get("_sleep_button")
	var message_label: Label = instance.get("_message_label")
	assert(sleep_button != null)
	assert(message_label != null)
	assert(sleep_button.disabled)
	assert(sleep_button.text == "暂时不能休息")
	assert(message_label.text == "测试占用中")

	ActivityLockUtilsClass.unregister_free_period_blocker("home_app_test_blocker")
	instance.queue_free()
	blocker.queue_free()

	print("  PASS: _test_rest_button_reflects_manager_availability")
