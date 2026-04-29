extends Node

const OLD_TOPIC_PATH: String = "res://resources/story/topics/day1_date_suggest.tres"
const NEXT_TOPIC_PATH: String = "res://resources/story/topics/day1_team_react.tres"
const CHANNEL_ID: String = "dm_lin_xia"


func _ready() -> void:
	print("=== StoryDirector Topic Overlap Test ===")
	var sd: Node = get_node_or_null("/root/StoryDirector")
	var chat: Node = get_node_or_null("/root/ChatManager")
	if sd == null or chat == null:
		print("[FAIL] required autoloads exist")
		return

	await _test_wait_event_completes_current_topic_before_next_topic(sd, chat)
	await _test_new_story_topic_supersedes_unfinished_story_topic(sd, chat)
	_reset(sd, chat)
	print("=== StoryDirector Topic Overlap Test Done ===")


func _test_wait_event_completes_current_topic_before_next_topic(sd: Node, chat: Node) -> void:
	print("[CASE] wait event completes old topic before advancing")
	_reset(sd, chat)

	var chapter := StoryChapter.new()
	chapter.chapter_id = "test_topic_wait_event_overlap"
	chapter.chapter_name = "Topic wait event overlap"

	var first := StoryStep.new()
	first.step_id = "open_app_from_topic"
	first.actions = [{
		"type": "activate_topic",
		"topic_path": OLD_TOPIC_PATH,
		"npc_speaks_first": false,
		"open_linkchat_mode": "silent",
	}]
	first.wait_for = {"type": "app_opened", "app_id": "browser"}
	first.next = "next_topic"

	var next := StoryStep.new()
	next.step_id = "next_topic"
	next.actions = [{
		"type": "activate_topic",
		"topic_path": NEXT_TOPIC_PATH,
		"npc_speaks_first": false,
		"open_linkchat_mode": "silent",
	}]
	next.wait_for = {"type": "topic_completed", "topic_id": "day1_team_react"}

	chapter.steps.append(first)
	chapter.steps.append(next)
	sd._chapters[chapter.chapter_id] = chapter

	sd.start_chapter(chapter.chapter_id)
	var old_active: ChatTopic = chat.get_active_topic(CHANNEL_ID)
	_assert_true("old topic is active", old_active != null and old_active.topic_id == "day1_date_suggest")
	chat.set("_waiting_for_ai", true)
	chat.set("_waiting_channel_id", CHANNEL_ID)
	chat.set("_pending_request_id", "req_overlap_test")

	sd._on_wait_app_opened("browser", null)
	await _flush_frames(3)

	var active: ChatTopic = chat.get_active_topic(CHANNEL_ID)
	_assert_true("old pending AI request is cancelled", not chat.is_waiting_for_ai() and chat.get_waiting_channel_id().is_empty())
	_assert_true("new topic activates after app signal", active != null and active.topic_id == "day1_team_react")
	_assert_true("story waits for real new topic completion", sd._waiting and sd.current_step != null and sd.current_step.step_id == "next_topic")

	chat.topic_manager.complete_topic(active, {"summary": "done"})
	await _flush_frames(3)
	_assert_true("chapter completes after new topic completion", sd.current_chapter == null and not sd._waiting)


func _test_new_story_topic_supersedes_unfinished_story_topic(sd: Node, chat: Node) -> void:
	print("[CASE] new story topic supersedes unfinished story topic")
	_reset(sd, chat)

	var old_topic: ChatTopic = _load_topic(OLD_TOPIC_PATH)
	_assert_true("old topic loads", old_topic != null)
	if old_topic == null:
		return
	chat.activate_topic(old_topic)
	_assert_true("manual old topic is active", chat.get_active_topic(CHANNEL_ID) == old_topic)

	var chapter := StoryChapter.new()
	chapter.chapter_id = "test_topic_supersede"
	chapter.chapter_name = "Topic supersede"

	var step := StoryStep.new()
	step.step_id = "activate_next"
	step.actions = [{
		"type": "activate_topic",
		"topic_path": NEXT_TOPIC_PATH,
		"npc_speaks_first": false,
		"open_linkchat_mode": "silent",
	}]
	step.wait_for = {"type": "topic_completed", "topic_id": "day1_team_react"}
	chapter.steps.append(step)
	sd._chapters[chapter.chapter_id] = chapter

	sd.start_chapter(chapter.chapter_id)
	var active: ChatTopic = chat.get_active_topic(CHANNEL_ID)
	_assert_true("old story topic is no longer active", not old_topic.is_active)
	_assert_true("next story topic is active", active != null and active.topic_id == "day1_team_react")
	_assert_true("story waits on activated next topic", sd._waiting and sd.current_step == step)

	chat.topic_manager.complete_topic(active, {"summary": "done"})
	await _flush_frames(3)
	_assert_true("superseded flow completes without deadlock", sd.current_chapter == null and not sd._waiting)


func _load_topic(path: String) -> ChatTopic:
	var loaded: Resource = ResourceLoader.load(path)
	if loaded == null:
		return null
	return loaded.duplicate(true) as ChatTopic


func _reset(sd: Node, chat: Node) -> void:
	if sd.has_method("reset_runtime_state"):
		sd.reset_runtime_state()
	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)


func _flush_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s" % label)
