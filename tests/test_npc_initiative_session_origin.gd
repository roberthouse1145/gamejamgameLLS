extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	var date_manager: Node = get_node_or_null("/root/DateManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var transit: Node = get_node_or_null("/root/TransitManager")
	if chat == null or date_manager == null or glm == null or transit == null:
		print("[FAIL] missing required autoload")
		return

	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	if date_manager.has_method("reset_runtime_state"):
		date_manager.reset_runtime_state()
	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()

	var channel = chat.get_channel("dm_lin_xia")
	if channel == null:
		print("[FAIL] dm_lin_xia channel missing")
		return
	var before_count: int = channel.messages.size()

	var events: Array = date_manager.get_available_events()
	if events.is_empty():
		print("[FAIL] no date events available")
		return

	var first_event: Dictionary = events[0]
	var event_id: String = str(first_event.get("event_id", first_event.get("location_id", ""))).strip_edges()
	if event_id.is_empty():
		print("[FAIL] selected date event has no id")
		return

	var result: Dictionary = date_manager.begin_date(event_id, 0.1, true)
	if not bool(result.get("success", false)):
		print("[FAIL] begin_date(skip_departure=true) failed: %s" % str(result.get("error", "")))
		return

	var session_id: String = str(result.get("session_id", "")).strip_edges()
	var snapshot: Dictionary = date_manager.get_session_snapshot(session_id)
	if str(snapshot.get("session_origin", "")) == "npc_initiative":
		print("[OK] session origin marked as npc_initiative")
	else:
		print("[FAIL] session origin mismatch: %s" % str(snapshot.get("session_origin", "")))

	await get_tree().process_frame
	await get_tree().process_frame

	channel = chat.get_channel("dm_lin_xia")
	var leaked_player_card: bool = false
	for i in range(before_count, channel.messages.size()):
		var msg: Dictionary = channel.messages[i]
		if str(msg.get("sender_id", "")) == "player" and msg.get("card", null) is Dictionary:
			leaked_player_card = true
			break

	if leaked_player_card:
		print("[FAIL] npc initiative session injected a player activity card")
	else:
		print("[OK] npc initiative session did not inject a player activity card")

	await get_tree().create_timer(0.7).timeout

	if transit.has_method("has_active_transit") and transit.has_active_transit():
		var active: Dictionary = transit.get_active_transit()
		if str(active.get("session_id", "")) == session_id:
			print("[OK] npc initiative session starts transit")
		else:
			print("[FAIL] active transit session mismatch: %s" % str(active.get("session_id", "")))
	else:
		print("[FAIL] npc initiative session did not start transit")
