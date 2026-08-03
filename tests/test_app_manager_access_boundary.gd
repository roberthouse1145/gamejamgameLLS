extends Control

var _wm: WindowManager = null


func _ready() -> void:
	print("=== AppManager Access Boundary Test ===")

	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)

	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_wm.window_container = container

	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		print("[FAIL] AppManager missing")
		return

	app_manager.window_manager = _wm
	if app_manager.has_method("close_app"):
		app_manager.close_app("avg_player", true)

	var whitelist: Array[String] = []
	app_manager.set_app_whitelist(whitelist)
	_assert_true("AVG player is inaccessible under an empty whitelist", not app_manager.is_app_accessible("avg_player"))

	var window: Control = app_manager.launch_app("avg_player", true)
	_assert_true("forced launch bypasses runtime access whitelist", window != null)

	if app_manager.has_method("close_app"):
		app_manager.close_app("avg_player", true)
	app_manager.clear_app_access_restriction()


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("[OK] %s" % label)
	else:
		print("[FAIL] %s" % label)
