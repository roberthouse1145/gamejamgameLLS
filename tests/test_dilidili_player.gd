extends Control

## Dilidili AVG player UI smoke test.
## Instantiates the player directly and validates the single live-room home,
## playback page, and public method contract.

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
	for unique_name in ["TopBar", "PlaybackPage", "AVGSceneRunner", "TitleLabel",
						"PreviewContainer", "PreviewViewport", "ContentArea",
						"StreamingPage", "StreamingAVGPlayer"]:
		var node: Node = player.get_node_or_null("%" + unique_name)
		if node == null:
			push_error("FAIL: unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])

	# Public API sanity — methods must still be callable by scene_window.gd.
	for method in ["play_event", "play_scene_package", "play_stream_package", "navigate_to"]:
		if not player.has_method(method):
			push_error("FAIL: missing method %s" % method)
		else:
			print("  OK: method present -> %s" % method)

	# Signal contract.
	if not player.has_signal("playback_finished"):
		push_error("FAIL: playback_finished signal missing")
	else:
		print("  OK: signal present -> playback_finished")

	if player.get_node_or_null("%NavHistoryBtn") != null or player.get_node_or_null("%HistoryPage") != null:
		push_error("FAIL: dilidili should not expose history UI")
	else:
		print("  OK: history UI removed")

	player.navigate_to(player.Page.HOME)
	await get_tree().process_frame
	_assert_page_state(player, true, false, "home")
	player.navigate_to(player.Page.PLAYBACK)
	await get_tree().process_frame
	_assert_page_state(player, false, true, "playback")
	player.navigate_to(player.Page.STREAMING)
	await get_tree().process_frame
	_assert_page_state(player, true, false, "streaming")
	player.navigate_to(player.Page.HOME)
	await get_tree().process_frame
	_assert_page_state(player, true, false, "home again")

	print("=== dilidili player smoke done ===")


func _assert_page_state(player: Control, streaming_visible: bool, playback_visible: bool, label: String) -> void:
	var streaming_page: Control = player.get_node_or_null("%StreamingPage") as Control
	var playback_page: Control = player.get_node_or_null("%PlaybackPage") as Control
	if streaming_page == null or streaming_page.visible != streaming_visible:
		push_error("FAIL: StreamingPage visibility wrong on %s" % label)
	if playback_page == null or playback_page.visible != playback_visible:
		push_error("FAIL: PlaybackPage visibility wrong on %s" % label)
	if streaming_page != null and playback_page != null:
		print("  OK: %s page visibility streaming=%s playback=%s" % [label, str(streaming_page.visible), str(playback_page.visible)])
