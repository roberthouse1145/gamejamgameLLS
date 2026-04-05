extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Free Period Status Warning Test ===")

	var gm: Node = get_node_or_null("/root/GameManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var chat: Node = get_node_or_null("/root/ChatManager")
	var story: Node = get_node_or_null("/root/StoryDirector")
	if gm == null or glm == null or chat == null or story == null:
		print("[FAIL] missing required autoload")
		return

	if gm.has_method("reset_runtime_state"):
		gm.reset_runtime_state()
	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()
	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	if story.has_method("reset_runtime_state"):
		story.reset_runtime_state()

	gm.auto_request_status_warning_reply = false

	gm.stress = 85
	await get_tree().process_frame
	await get_tree().process_frame

	if not chat.has_method("has_active_topic") or not chat.has_active_topic("dm_lin_xia"):
		print("[FAIL] free period danger should activate a warning topic")
		gm.auto_request_status_warning_reply = true
		return

	var topic: Resource = chat.get_active_topic("dm_lin_xia")
	if topic == null:
		print("[FAIL] warning topic should be readable")
		gm.auto_request_status_warning_reply = true
		return
	if str(topic.get("topic_type")) != "casual_interaction":
		print("[FAIL] warning topic type mismatch")
		gm.auto_request_status_warning_reply = true
		return
	var context_data: Dictionary = topic.context_data if topic != null else {}
	if str(context_data.get("status_warning_type", "")) != "stress":
		print("[FAIL] warning topic should record stress warning type")
		gm.auto_request_status_warning_reply = true
		return
	print("[OK] free period stress danger activates warning topic")

	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	if gm.has_method("reset_runtime_state"):
		gm.reset_runtime_state()
	if story.has_method("reset_runtime_state"):
		story.reset_runtime_state()

	story.current_chapter = Resource.new()
	gm.stress = 85
	await get_tree().process_frame
	await get_tree().process_frame

	if chat.has_method("has_active_topic") and chat.has_active_topic("dm_lin_xia"):
		print("[FAIL] active story should block free period warning topic")
		gm.auto_request_status_warning_reply = true
		return
	print("[OK] active story blocks free period warning topic")

	story.current_chapter = null
	gm.auto_request_status_warning_reply = true
	print("[OK] Free period status warning test passed")
