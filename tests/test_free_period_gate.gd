extends Node

const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Free Period Gate Test ===")

	var chat: Node = get_node_or_null("/root/ChatManager")
	var story: Node = get_node_or_null("/root/StoryDirector")
	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if chat == null or story == null or home == null or wom == null or glm == null:
		print("[FAIL] missing required autoload")
		return

	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	if story.has_method("reset_runtime_state"):
		story.reset_runtime_state()
	if home.has_method("reset_runtime_state"):
		home.reset_runtime_state()
	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()

	if not ActivityLockUtilsClass.is_free_period():
		print("[FAIL] clean runtime should be free period")
		return
	print("[OK] clean runtime is free period")

	var topic := ChatTopicClass.new()
	topic.topic_id = "free_gate_test_topic"
	topic.topic_type = "casual_interaction"
	topic.display_title = "测试聊天占用"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "dm_lin_xia"
	topic.system_prompt = "测试"
	topic.goal_description = "测试"
	topic.max_turns = 1
	topic.timeout_seconds = 0
	if not chat.activate_topic(topic):
		print("[FAIL] failed to activate test topic")
		return
	await get_tree().process_frame
	if ActivityLockUtilsClass.is_free_period():
		print("[FAIL] active linkchat topic should block free period")
		return
	print("[OK] active linkchat topic blocks free period")

	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	await get_tree().process_frame

	var rest_result: Dictionary = home.begin_activity("rest")
	if not bool(rest_result.get("success", false)):
		print("[FAIL] failed to start home rest activity")
		return
	await get_tree().process_frame
	if ActivityLockUtilsClass.is_free_period():
		print("[FAIL] home activity chain should block free period")
		return
	print("[OK] home activity chain blocks free period")

	if home.has_method("reset_runtime_state"):
		home.reset_runtime_state()
	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	await get_tree().process_frame

	story.current_chapter = Resource.new()
	if ActivityLockUtilsClass.is_free_period():
		print("[FAIL] active story should block free period")
		return
	print("[OK] active story blocks free period")
	story.current_chapter = null

	story.current_chapter = Resource.new()
	var clarify_topic := ChatTopicClass.new()
	clarify_topic.channel_id = "dm_lin_xia"
	if bool(wom.call("_can_activate_clarification", clarify_topic)):
		print("[FAIL] clarification should not activate outside free period")
		return
	print("[OK] clarification follows free period gate")
	story.current_chapter = null

	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	if story.has_method("reset_runtime_state"):
		story.reset_runtime_state()
	if home.has_method("reset_runtime_state"):
		home.reset_runtime_state()
	print("[OK] Free period gate test passed")
