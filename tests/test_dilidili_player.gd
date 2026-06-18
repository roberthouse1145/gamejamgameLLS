extends Control

## Dilidili AVG player UI smoke test.
## Instantiates the player directly and validates that the TopBar layout,
## home/history pages, and unique node names all resolve so the rename
## refactor doesn't silently break the public contract.

const PLAYER_SCENE: PackedScene = preload("res://scenes/date_events/date_event_player.tscn")


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
						"TitleLabel", "PreviewContainer", "PreviewViewport", "ContentArea",
						"StreamingPage", "StreamingAVGPlayer"]:
		var node: Node = player.get_node_or_null("%" + unique_name)
		if node == null:
			push_error("FAIL: unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])

	# Public API sanity — methods must still be callable by scene_window.gd.
	for method in ["play_event", "play_scene_package", "play_stream_package", "enable_thumbnail_capture",
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
		elif bool((history[0] as Dictionary).get("has_replay", false)):
			push_error("FAIL: history entry should not expose replay availability")
		else:
			print("  OK: DateManager history records lightweight text entry")

	# Navigate through the three pages so the new TopBar-driven visibility
	# switching is exercised at least once.
	player.navigate_to(player.Page.HOME)
	await get_tree().process_frame
	player.navigate_to(player.Page.HISTORY)
	await get_tree().process_frame
	player.navigate_to(player.Page.PLAYBACK)
	await get_tree().process_frame
	player.navigate_to(player.Page.STREAMING)
	await get_tree().process_frame
	player.navigate_to(player.Page.HOME)
	await get_tree().process_frame

	print("=== dilidili player smoke done ===")
