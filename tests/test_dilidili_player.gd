extends Control

## Dilidili AVG player UI smoke test.
## Instantiates the player directly and validates that the TopBar layout,
## home/history pages, and unique node names all resolve so the rename
## refactor doesn't silently break the public contract.

const PLAYER_SCENE: PackedScene = preload("res://scenes/date_events/date_event_player.tscn")
const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")


func _ready() -> void:
	print("=== dilidili player smoke ===")
	var player: Control = PLAYER_SCENE.instantiate() as Control
	if player == null:
		push_error("FAIL: player scene instantiate returned null")
		return
	player.anchor_right = 1.0
	player.anchor_bottom = 1.0
	add_child(player)
	await get_tree().process_frame

	# Required unique nodes must exist after the UI refactor.
	for unique_name in ["TopBar", "NavHomeBtn", "NavHistoryBtn", "HomePage", "HistoryPage",
						"PlaybackPage", "HomeContent", "HistoryList", "AVGSceneRunner",
						"TitleLabel", "PreviewContainer", "PreviewViewport", "ContentArea"]:
		var node: Node = player.get_node_or_null("%" + unique_name)
		if node == null:
			push_error("FAIL: unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])

	# Public API sanity — methods must still be callable by scene_window.gd.
	for method in ["play_event", "play_scene_package", "enable_thumbnail_capture",
				   "navigate_to", "get_cover_image"]:
		if not player.has_method(method):
			push_error("FAIL: missing method %s" % method)
		else:
			print("  OK: method present -> %s" % method)

	# Signal contract.
	if not player.has_signal("playback_finished"):
		push_error("FAIL: playback_finished signal missing")
	else:
		print("  OK: signal present -> playback_finished")

	var date_manager := get_node_or_null("/root/DateManager")
	if date_manager != null and date_manager.has_method("reset_runtime_state") and date_manager.has_method("get_avg_history"):
		date_manager.reset_runtime_state()
		player.call("_add_history_entry", "test_session_once", "测试剧情", "", "测试结果")
		var history: Array = date_manager.get_avg_history()
		if history.size() != 1:
			push_error("FAIL: player should add one DateManager history entry, got %d" % history.size())
		else:
			print("  OK: DateManager history records once per player entry")

		date_manager.reset_runtime_state()
		var replay_package := _build_replay_package("test_replay_session")
		player.set("_scene_package", replay_package)
		player.set("_event_request", {})
		player.call("_add_history_entry", "test_replay_session", "重播测试", "", "重播结果")
		var replay_history: Array = date_manager.get_avg_history()
		var replay_available: bool = replay_history.size() == 1 and bool((replay_history[0] as Dictionary).get("has_replay", false))
		if not replay_available:
			push_error("FAIL: history entry should expose replay availability")
		else:
			print("  OK: history entry exposes replay availability")

		player.call("_replay_history_entry", replay_history[0])
		await get_tree().process_frame
		var playback_page := player.get_node_or_null("%PlaybackPage") as Control
		var replay_started: bool = playback_page != null and playback_page.visible
		var history_after_replay: Array = date_manager.get_avg_history()
		if not replay_started:
			push_error("FAIL: replay should navigate to playback page")
		elif history_after_replay.size() != 1:
			push_error("FAIL: replay should not add another history entry, got %d" % history_after_replay.size())
		else:
			print("  OK: replay starts playback without duplicating history")

	# Navigate through the three pages so the new TopBar-driven visibility
	# switching is exercised at least once.
	player.navigate_to(player.Page.HOME)
	await get_tree().process_frame
	player.navigate_to(player.Page.HISTORY)
	await get_tree().process_frame
	player.navigate_to(player.Page.PLAYBACK)
	await get_tree().process_frame
	player.navigate_to(player.Page.HOME)
	await get_tree().process_frame

	print("=== dilidili player smoke done ===")


func _build_replay_package(session_id: String) -> Dictionary:
	var project := AVGProjectClass.new()
	project.project_name = "replay_test_project"
	project.resolution = Vector2i(2560, 1440)
	var choice_variable := AVGVariableClass.new()
	choice_variable.variable_id = "var_001"
	AVGVariableClass.apply_key(choice_variable, "choice")
	choice_variable.default_value = 0

	var root := AVGRootNodeClass.new()
	root.node_id = "root"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(2560, 1440)
	root.command_tabs = [{
		"commands": [],
		"condition_commands": [],
		"mode": 0,
	}]

	var scene := AVGSceneClass.new()
	scene.scene_id = "scene_replay_test"
	scene.scene_name = "Replay Test"
	scene.nodes = [root]
	project.scenes = [scene]
	project.variables = [choice_variable]

	return {
		"session_id": session_id,
		"title": "Replay Test",
		"project": project,
		"scene": scene,
		"scene_outline": "",
		"choice_labels": {},
		"choice_var_id": "var_001",
	}
