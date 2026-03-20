extends Control

const HomeAppClass = preload("res://scripts/apps/home/home_app.gd")

var _wm: WindowManager = null


func _ready() -> void:
	print("=== Home App Launch Test ===")

	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)

	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_wm.window_container = container

	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		print("[FAIL] AppManager missing")
		return

	am.window_manager = _wm
	if not am.app_registry.has("home"):
		print("[FAIL] home app not registered")
		return

	var window: Control = am.launch_app("home")
	if window == null:
		print("[FAIL] home app failed to launch")
		return

	await get_tree().process_frame

	var content: Control = window.get("content")
	if content == null:
		print("[FAIL] home app content missing")
		return

	if content.get_script() == HomeAppClass:
		print("[OK] home app launched")
	else:
		print("[FAIL] launched content is not HomeApp")
