extends Control

const PLAYER_SCENE: PackedScene = preload("res://scenes/date_events/date_event_player.tscn")
const PROJECT_RES: Resource = preload("res://narrative_projects/main_story/project.tres")


func _ready() -> void:
	print("=== Streaming AVG player smoke ===")
	var player: Control = PLAYER_SCENE.instantiate() as Control
	if player == null:
		push_error("FAIL: DateEventPlayer instantiate returned null")
		return
	player.anchor_right = 1.0
	player.anchor_bottom = 1.0
	add_child(player)
	await get_tree().process_frame

	for unique_name in ["StreamingPage", "StreamingAVGPlayer"]:
		var node := player.get_node_or_null("%" + unique_name)
		if node == null:
			push_error("FAIL: unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])
	var stream_view: Control = player.get_node_or_null("%StreamingAVGPlayer") as Control
	for unique_name in ["StreamTitleLabel", "ChatList", "SkipButton"]:
		var node := stream_view.get_node_or_null("%" + unique_name) if stream_view != null else null
		if node == null:
			push_error("FAIL: streaming unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])

	if not player.has_method("play_stream_package"):
		push_error("FAIL: play_stream_package method missing")
		return

	var stream_script := """
@stream "Smoke Live" host=LinXia viewers=12 day="第1天"
bg bg_apartment_living
host LinXia happy casual
say "hi" speed=120 hold=0.01
chat "弹幕自动出现" delay=0.01
wait 0.01
end
"""
	var package := {
		"session_id": "stream_smoke",
		"title": "Smoke Live",
		"stream_script": stream_script,
		"project": PROJECT_RES.duplicate(true),
		"project_root_path": "res://narrative_projects/main_story/",
	}

	var finish_state := {
		"finished": false,
		"outcome": {},
	}
	player.playback_finished.connect(func(session_id: String, outcome: Dictionary) -> void:
		if session_id != "stream_smoke":
			return
		finish_state["finished"] = true
		finish_state["outcome"] = outcome.duplicate(true)
	)

	player.call("play_stream_package", "stream_smoke", package, false)
	await get_tree().process_frame
	var streaming_page: Control = player.get_node_or_null("%StreamingPage") as Control
	var playback_page: Control = player.get_node_or_null("%PlaybackPage") as Control
	if streaming_page == null or not streaming_page.visible:
		push_error("FAIL: StreamingPage should be visible during stream")
	else:
		print("  OK: StreamingPage visible")
	if playback_page != null and playback_page.visible:
		push_error("FAIL: PlaybackPage should stay hidden during stream")
	else:
		print("  OK: PlaybackPage hidden")

	var skip_button: Button = stream_view.get_node_or_null("%SkipButton") as Button if stream_view != null else null
	if skip_button != null:
		skip_button.pressed.emit()

	var elapsed := 0.0
	while not bool(finish_state.get("finished", false)) and elapsed < 3.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if not bool(finish_state.get("finished", false)):
		push_error("FAIL: streaming playback did not finish")
		return
	var finished_outcome: Dictionary = finish_state.get("outcome", {})
	if not bool(finished_outcome.get("success", false)):
		push_error("FAIL: streaming outcome should succeed: %s" % str(finished_outcome))
	else:
		print("  OK: streaming playback_finished emitted")

	var chat_list: VBoxContainer = stream_view.get_node_or_null("%ChatList") as VBoxContainer if stream_view != null else null
	if chat_list == null or chat_list.get_child_count() < 1:
		push_error("FAIL: chat message should be rendered")
	else:
		print("  OK: chat rendered")

	var return_elapsed := 0.0
	while return_elapsed < 1.7:
		await get_tree().process_frame
		return_elapsed += get_process_delta_time()
	var home_page: Control = player.get_node_or_null("%HomePage") as Control
	if home_page == null or not home_page.visible:
		push_error("FAIL: player should return home after stream")
	else:
		print("  OK: returned home after stream")

	print("=== Streaming AVG player smoke done ===")
