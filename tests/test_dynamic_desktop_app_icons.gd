extends Control

const DesktopScene = preload("res://scenes/pseudo_os/desktop.tscn")

var _desktop: Desktop = null


func _ready() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	_assert(app_manager != null, "AppManager is available")
	if app_manager == null:
		return

	_desktop = DesktopScene.instantiate() as Desktop
	_assert(_desktop != null, "desktop can be instantiated")
	if _desktop == null:
		return
	add_child(_desktop)
	await _desktop.desktop_ready
	await get_tree().process_frame

	_assert(_desktop.desktop_icons.size() == 1, "default desktop exposes one infrastructure app")
	_assert(_desktop.desktop_icons.has("avg_player"), "AVG player icon is visible")

	var icon := _desktop.desktop_icons.get("avg_player") as DesktopIcon
	_assert(icon != null, "AVG player icon instance is available")
	if icon == null:
		return
	icon.set_selected(true)
	await get_tree().process_frame
	_assert(icon.is_selected, "icon can be selected")

	app_manager.set_app_desktop_visible("avg_player", false)
	await get_tree().process_frame
	_assert(not _desktop.desktop_icons.has("avg_player"), "runtime visibility can hide an app")

	app_manager.set_app_desktop_visible("avg_player", true)
	await get_tree().process_frame
	_assert(_desktop.desktop_icons.has("avg_player"), "runtime visibility can restore an app")


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		push_error("[FAIL] %s" % message)
