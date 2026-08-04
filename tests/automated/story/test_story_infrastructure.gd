extends Node

const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const StoryScriptParserClass = preload("res://scripts/story/story_script_parser.gd")
const StoryCompilerClass = preload("res://scripts/story/story_compiler.gd")

var _failures: int = 0


func _ready() -> void:
	_test_story_parser()
	_test_story_compiler()
	await _test_topic_story_flow()

	if _failures == 0:
		print("[PASS] story infrastructure")
	else:
		push_error("[FAIL] story infrastructure: %d checks failed" % _failures)


func _test_story_parser() -> void:
	var parsed: Dictionary = StoryScriptParserClass.parse("""
chapter: neutral_chapter
name: Neutral Chapter

=== opening ===
[set_variable]
  key: opened
  value: true
wait: immediate
""")
	_check(parsed.get("chapter_id") == "neutral_chapter", "story parser keeps chapter id")
	var steps: Array = parsed.get("steps", [])
	_check(steps.size() == 1, "story parser creates one step")
	if steps.size() == 1:
		var actions: Array = steps[0].get("actions", [])
		_check(actions.size() == 1 and actions[0].get("type") == "set_variable", "story parser keeps action type")


func _test_story_compiler() -> void:
	var chapter: Resource = StoryCompilerClass.build_chapter_from_dict({
		"chapter_id": "compiled_chapter",
		"chapter_name": "Compiled Chapter",
		"steps": [{
			"step_id": "compiled_step",
			"actions": [{"type": "set_variable", "key": "compiled", "value": true}],
			"wait_for": {"type": "immediate"},
		}],
	})
	_check(chapter != null and chapter.chapter_id == "compiled_chapter", "story compiler builds a chapter resource")
	_check(chapter != null and chapter.get_step("compiled_step") != null, "story compiler builds step resources")


func _test_topic_story_flow() -> void:
	var director: Node = get_node_or_null("/root/StoryDirector")
	_check(director != null, "StoryDirector autoload exists")
	if director == null:
		return

	director.reset_runtime_state()
	var topic_manager: TopicManager = director.get_topic_manager() as TopicManager
	_check(topic_manager != null, "TopicManager is available through StoryDirector")
	if topic_manager == null:
		return
	topic_manager.reset_runtime_state(true)

	var chapter: StoryChapter = StoryChapterClass.new()
	chapter.chapter_id = "test_story_infrastructure"
	chapter.chapter_name = "Test Story Infrastructure"

	var topic_step: StoryStep = StoryStepClass.new()
	topic_step.step_id = "topic"
	topic_step.actions = [{
		"type": "activate_topic",
		"topic_id": "neutral_topic",
		"channel_id": "neutral_channel",
		"mode": ChatTopic.Mode.LOCAL,
		"local_script": "player: 已阅读。\nEND viewed",
	}]
	topic_step.wait_for = {"type": "topic_completed", "topic_id": "neutral_topic"}
	topic_step.capture = {"topic_result": "result.result_id"}
	topic_step.next = "finish"

	var finish_step: StoryStep = StoryStepClass.new()
	finish_step.step_id = "finish"
	finish_step.actions = [{"type": "set_variable", "key": "story_finished", "value": true}]
	finish_step.wait_for = {"type": "immediate"}

	chapter.steps = [topic_step, finish_step]
	_check(director.register_chapter(chapter), "chapter registration succeeds")
	_check(director.start_chapter(chapter.chapter_id), "chapter starts")
	_check(topic_manager.has_active_topic("neutral_channel"), "activate_topic creates an active topic")

	var topic: ChatTopic = topic_manager.get_active_topic("neutral_channel")
	_check(topic != null and topic.topic_id == "neutral_topic", "active topic keeps its identity")
	if topic != null:
		_check(topic_manager.advance_topic("neutral_channel"), "topic advances after its message is displayed")

	await get_tree().process_frame
	await get_tree().process_frame
	_check(director.get_variable("topic_result") == "viewed", "topic result is captured")
	_check(director.get_variable("story_finished") == true, "next story step executes")
	_check(director.completed_chapters.has(chapter.chapter_id), "chapter completion is recorded")

	var saved: Dictionary = director.get_save_data()
	director.reset_runtime_state()
	_check(director.load_save_data(saved), "story state reload succeeds")
	_check(director.get_variable("topic_result") == "viewed", "story variables survive reload")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)
