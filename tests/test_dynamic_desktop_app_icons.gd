extends Control

const DesktopScene = preload("res://scenes/pseudo_os/game_desktop.tscn")

var _desktop: Desktop = null


func _ready() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		push_error("[TestDynamicDesktopAppIcons] AppManager not found")
		return

	_desktop = DesktopScene.instantiate() as Desktop
	if _desktop == null:
		push_error("[TestDynamicDesktopAppIcons] Failed to instantiate desktop")
		return

	_desktop.name = "DesktopUnderTest"
	_desktop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_desktop)

	await _desktop.desktop_ready
	await get_tree().process_frame

	print("[TestDynamicDesktopAppIcons] Start")
	_assert(not _desktop.desktop_icons.has("scene_editor"), "scene_editor starts hidden on game desktop")
	_assert(_desktop.desktop_icons.has("desktop_pet"), "desktop_pet starts visible on game desktop")
	_assert(_desktop.desktop_icons.has("linkchat"), "linkchat starts visible on game desktop")

	var desktop_pet_icon := _desktop.desktop_icons.get("desktop_pet") as DesktopIcon
	var linkchat_icon := _desktop.desktop_icons.get("linkchat") as DesktopIcon
	_assert(desktop_pet_icon != null, "desktop_pet icon instance is available")
	_assert(linkchat_icon != null, "linkchat icon instance is available")

	desktop_pet_icon.set_selected(true)
	await get_tree().process_frame
	_assert(desktop_pet_icon.is_selected, "desktop_pet enters selected state after click")

	linkchat_icon.set_selected(true)
	await get_tree().process_frame
	_assert(linkchat_icon.is_selected, "linkchat becomes the active selected icon")
	_assert(not desktop_pet_icon.is_selected, "selecting another icon clears the previous selection")

	var background_click := InputEventMouseButton.new()
	background_click.button_index = MOUSE_BUTTON_LEFT
	background_click.pressed = true
	background_click.position = Vector2(4, 4)
	background_click.global_position = Vector2(4, 4)
	_desktop._input(background_click)
	await get_tree().process_frame
	_assert(not linkchat_icon.is_selected, "clicking desktop blank space clears icon selection")

	app_manager.set_app_desktop_visible("scene_editor", true)
	await get_tree().process_frame
	_assert(_desktop.desktop_icons.has("scene_editor"), "scene_editor icon appears after visibility override")

	app_manager.set_app_desktop_visible("scene_editor", false)
	await get_tree().process_frame
	_assert(not _desktop.desktop_icons.has("scene_editor"), "scene_editor icon disappears after hiding")

	app_manager.unregister_app("desktop_pet", false)
	await get_tree().process_frame
	_assert(not _desktop.desktop_icons.has("desktop_pet"), "desktop_pet icon disappears after uninstall")

	var reinstall_ok: bool = app_manager.install_app_from_path("res://resources/apps/desktop_pet_app.tres")
	await get_tree().process_frame
	_assert(reinstall_ok, "desktop_pet reinstall succeeds")
	_assert(_desktop.desktop_icons.has("desktop_pet"), "desktop_pet icon returns after reinstall")

	print("[TestDynamicDesktopAppIcons] Finished")
	print("[TestDynamicDesktopAppIcons] Keep window open for manual inspection if needed")


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	push_error("[FAIL] %s" % message)
