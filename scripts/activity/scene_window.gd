class_name SceneWindow
extends RefCounted

const PLAYER_SCENE_PATH: String = "res://scenes/date_events/date_event_player.tscn"


static func open(title: String, scene_package: Dictionary, playback_callback: Callable) -> Dictionary:
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	if player_scene == null:
		return {}
	var player: Control = player_scene.instantiate() as Control
	if player == null:
		return {}

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		player.queue_free()
		return {}
	var app_manager: Node = tree.root.get_node_or_null("/root/AppManager")
	if app_manager == null:
		player.queue_free()
		return {}
	var window_manager: Node = app_manager.get("window_manager")
	if window_manager == null or not window_manager.has_method("create_window"):
		player.queue_free()
		return {}

	var window: Control = window_manager.create_window(title, player)
	if window == null:
		player.queue_free()
		return {}

	window.custom_minimum_size = Vector2(1024, 768)
	window.size = window_manager.get_viewport().get_visible_rect().size * 0.9
	if window.has_method("center_in_screen"):
		window.center_in_screen()

	var close_button := window.get_node_or_null("TitleBar/ButtonContainer/CloseButton") as Button
	if close_button != null:
		close_button.visible = false
	var minimize_button := window.get_node_or_null("TitleBar/ButtonContainer/MinimizeButton") as Button
	if minimize_button != null:
		minimize_button.visible = false
	var maximize_button := window.get_node_or_null("TitleBar/ButtonContainer/MaximizeButton") as Button
	if maximize_button != null:
		maximize_button.visible = false
	window.set("resizable", false)

	if player.has_signal("playback_finished"):
		player.connect("playback_finished", playback_callback)
	if player.has_method("play_scene_package"):
		player.call("play_scene_package", scene_package.get("session_id", ""), scene_package)

	return {"window": window, "player": player}


static func close(window: Variant) -> void:
	if not (window is Control) or not is_instance_valid(window):
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var app_manager: Node = tree.root.get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.get("window_manager") if app_manager != null else null
	if window_manager != null and window_manager.has_method("close_window"):
		window_manager.close_window(window)
	else:
		(window as Control).queue_free()
