class_name SceneWindow
extends RefCounted

const APP_ID: String = "avg_player"
const PLAYER_SCENE_PATH: String = "res://scenes/date_events/date_event_player.tscn"


static func open(title: String, scene_package: Dictionary, playback_callback: Callable) -> Dictionary:
	return _open_player_window(title, playback_callback, "play_scene_package", [
		str(scene_package.get("session_id", "")),
		scene_package,
	])


static func open_event(title: String, session_id: String, event_request: Dictionary, playback_callback: Callable) -> Dictionary:
	return _open_player_window(title, playback_callback, "play_event", [
		session_id,
		event_request,
	])


static func _open_player_window(title: String, playback_callback: Callable, playback_method: String, playback_args: Array) -> Dictionary:

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var app_manager: Node = tree.root.get_node_or_null("/root/AppManager")
	if app_manager == null:
		return {}
	if not app_manager.has_method("launch_app"):
		return {}

	var window: Control = app_manager.launch_app(APP_ID, true)
	if window == null:
		return {}
	var player: Control = _find_player(window)
	if player == null:
		if app_manager.has_method("close_app"):
			app_manager.close_app(APP_ID)
		return {}

	_configure_window(window, title)
	if app_manager.has_method("lock_app_window"):
		app_manager.lock_app_window(APP_ID)

	# 启用截图捕获（首次播放）
	if player.has_method("enable_thumbnail_capture"):
		player.enable_thumbnail_capture()

	if player.has_signal("playback_finished"):
		player.playback_finished.connect(playback_callback, CONNECT_ONE_SHOT)
	if player.has_method(playback_method):
		player.call_deferred(playback_method, playback_args[0], playback_args[1])

	return {"window": window, "player": player}


static func _configure_window(window: Control, title: String) -> void:
	window.custom_minimum_size = Vector2(1024, 768)
	if "window_title" in window:
		window.window_title = title
	var viewport := window.get_viewport()
	if viewport != null:
		window.size = viewport.get_visible_rect().size * 0.9
	if window.has_method("center_in_screen"):
		window.center_in_screen()


static func _find_player(window: Control) -> Control:
	if window == null or not is_instance_valid(window):
		return null
	var content_container := window.get_node_or_null("ContentContainer") as Control
	if content_container != null:
		for child in content_container.get_children():
			if child is Control and (child as Control).has_method("play_scene_package"):
				return child as Control
	for child in window.get_children():
		if child is Control and (child as Control).has_method("play_scene_package"):
			return child as Control
	return null


static func close(_window: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var app_manager: Node = tree.root.get_node_or_null("/root/AppManager")
	if app_manager != null and app_manager.has_method("unlock_app_window"):
		app_manager.unlock_app_window(APP_ID)


static func minimize(on_finished: Callable = Callable()) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var app_manager: Node = tree.root.get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	if not app_manager.is_app_running(APP_ID):
		return false
	var window: Control = app_manager.running_apps.get(APP_ID, null)
	if window == null or not is_instance_valid(window):
		return false
	if window.is_minimized:
		if on_finished.is_valid():
			on_finished.call_deferred()
		return true

	if app_manager.has_method("unlock_app_window"):
		app_manager.unlock_app_window(APP_ID)

	var window_manager: Node = app_manager.window_manager
	if window_manager == null:
		return false

	if on_finished.is_valid() and window_manager.has_signal("window_minimized"):
		var callable_ref: Array = []  # 用数组包装，让 lambda 能引用自身
		var finished_callable: Callable = func(minimized_window: Control) -> void:
			if minimized_window != window:
				return
			if callable_ref.size() > 0 and window_manager.window_minimized.is_connected(callable_ref[0]):
				window_manager.window_minimized.disconnect(callable_ref[0])
			on_finished.call()
		callable_ref.append(finished_callable)
		window_manager.window_minimized.connect(finished_callable)

	if window.has_signal("minimize_requested"):
		window.call_deferred("emit_signal", "minimize_requested")
		return true

	if window_manager.has_method("minimize_window"):
		window_manager.minimize_window(window)
		if on_finished.is_valid():
			on_finished.call_deferred()
		return true

	return false


static func force_close() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var app_manager: Node = tree.root.get_node_or_null("/root/AppManager")
	if app_manager != null and app_manager.has_method("close_app"):
		app_manager.close_app(APP_ID)
