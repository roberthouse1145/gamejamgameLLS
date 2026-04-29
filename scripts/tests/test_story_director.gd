extends Node

const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const TopicManagerClass = preload("res://scripts/chat/topic_manager.gd")
const StoryScriptParserClass = preload("res://scripts/story/story_script_parser.gd")


class MockStoryAVGGenerator extends Node:
	signal scene_generated(session_id: String, package: Dictionary)

	var last_session: Dictionary = {}
	var request_count: int = 0

	func is_available() -> bool:
		return true

	func generate_for_session(session_id: String, session: Dictionary) -> bool:
		request_count += 1
		last_session = session.duplicate(true)
		call_deferred("_emit_generated", session_id, session)
		return true

	func _emit_generated(session_id: String, session: Dictionary) -> void:
		scene_generated.emit(session_id, {
			"session_id": session_id,
			"title": str(session.get("scene_window_title", "测试剧情")),
			"project": Resource.new(),
			"scene": Resource.new(),
			"scene_outline": str(session.get("story_scene_prompt", "")),
			"choice_labels": {},
			"choice_var_id": "var_001",
		})


class MockSceneWindowAdapter extends RefCounted:
	var opened_titles: Array[String] = []
	var opened_packages: Array[Dictionary] = []
	var minimize_calls: int = 0

	func open(title: String, scene_package: Dictionary, playback_callback: Callable) -> Dictionary:
		opened_titles.append(title)
		opened_packages.append(scene_package.duplicate(true))
		playback_callback.call_deferred(str(scene_package.get("session_id", "")), {
			"success": true,
			"summary": "mock finished",
		})
		return {"window": null}

	func minimize(on_finished: Callable = Callable()) -> bool:
		minimize_calls += 1
		if on_finished.is_valid():
			on_finished.call_deferred()
		return true


class MockProjectPreviewAdapter extends RefCounted:
	var started_preview_ids: Array[String] = []
	var last_action: Dictionary = {}

	func start_preview(preview_id: String, action: Dictionary, finished_callback: Callable) -> bool:
		started_preview_ids.append(preview_id)
		last_action = action.duplicate(true)
		if bool(action.get("simulate_closed", false)):
			finished_callback.call_deferred({
				"completed": false,
				"closed": true,
				"end_reason": "closed",
				"project_name": "Test Project",
			})
		else:
			finished_callback.call_deferred({
				"completed": true,
				"closed": false,
				"end_reason": "completed",
				"scene_id": "final_scene",
				"project_name": "Test Project",
			})
		return true

func _ready() -> void:
	print("=== StoryDirector Test ===")

	var sd: Node = get_node_or_null("/root/StoryDirector")
	if sd == null:
		print("[FAIL] StoryDirector autoload not found")
		return

	print("[OK] StoryDirector autoload found")
	print("[INFO] Testing activity guidance...")
	sd.clear_activity_guidance()
	sd.set_activity_guidance("date", "test guidance")
	print("  peek date guidance: %s (expect test guidance)" % sd.peek_activity_guidance("date"))
	print("  consume date guidance: %s (expect test guidance)" % sd.consume_activity_guidance("date"))
	print("  peek after consume: %s (expect empty)" % sd.peek_activity_guidance("date"))
	sd.set_activity_guidance("part_time", "persist guidance", false)
	var save_data: Dictionary = sd.get_save_data()
	sd.clear_activity_guidance()
	sd.load_run_state(save_data)
	print("  restored persistent guidance: %s (expect persist guidance)" % sd.peek_activity_guidance("part_time"))
	sd.clear_activity_guidance()
	var prompt_builder := AVGScenePromptBuilderClass.new()
	var preview_prompt := prompt_builder.build_normal_date_prompt_from_session({
		"activity_type": "date",
		"location": {
			"location_id": "test_location",
			"title": "测试地点",
			"description": "测试描述",
			"base_activity": "你们在这里随便走走。"
		},
		"entry_id": "test_location",
		"start_day": 1,
		"phase_after_action": "MORNING",
		"story_guidance_prompt": "这是导演指导测试。",
	})
	print("  prompt contains guidance: %s (expect true)" % str(preview_prompt.contains("这是导演指导测试。")))

	# 检查章节加载
	var chapters: Dictionary = sd._chapters
	print("[INFO] Loaded chapters: %d" % chapters.size())
	for chapter_id in chapters:
		var chapter: Resource = chapters[chapter_id]
		print("  - %s: %s (%d steps)" % [chapter_id, chapter.chapter_name, chapter.steps.size()])
		for step in chapter.steps:
			print("    step: %s -> next: %s (wait: %s)" % [step.step_id, step.next, str(step.wait_for.get("type", ""))])

	# 检查 AppManager 访问控制
	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		print("[FAIL] AppManager not found")
		return

	print("[OK] AppManager found")
	print("[INFO] Testing whitelist...")
	var test_list: Array[String] = ["linkchat"]
	am.set_app_whitelist(test_list)
	print("  linkchat accessible: %s (expect true)" % str(am.is_app_accessible("linkchat")))
	print("  browser accessible: %s (expect false)" % str(am.is_app_accessible("browser")))
	am.clear_app_access_restriction()
	print("  after clear, browser accessible: %s (expect true)" % str(am.is_app_accessible("browser")))

	# 测试启动章节（不实际执行，只验证加载和进入第一步）
	if chapters.has("day1"):
		print("[INFO] Testing start_chapter('day1')...")
		sd.step_entered.connect(func(cid: String, sid: String) -> void:
			print("  [SIGNAL] step_entered: %s / %s" % [cid, sid])
		)
		sd.start_chapter("day1")
		print("  current_step: %s" % (sd.current_step.step_id if sd.current_step else "null"))
		print("  _waiting: %s" % str(sd._waiting))
	else:
		print("[SKIP] No day1 chapter found")

	print("[INFO] Testing auto trigger evaluation...")
	sd.reset_runtime_state()
	var parser_result := StoryScriptParserClass.parse("""
chapter: parser_branch_test
name: Parser Branch Test

=== parser_branch_test_01 ===
wait: topic_completed
  topic_id: parser_topic
capture:
  topic_failed: result.topic_failed
next_conditions:
  topic_failed == false -> accepted
  default -> rejected
""")
	var parser_steps: Array = parser_result.get("steps", [])
	var parsed_conditions: Array = []
	if parser_steps.size() > 0 and parser_steps[0] is Dictionary:
		parsed_conditions = (parser_steps[0] as Dictionary).get("next_conditions", [])
	print("  parser next_conditions count: %s (expect 2)" % str(parsed_conditions.size()))
	if parsed_conditions.size() > 0:
		print("  parser first branch next: %s (expect accepted)" % str((parsed_conditions[0] as Dictionary).get("next", "")))
	var topic_manager := TopicManagerClass.new()
	add_child(topic_manager)
	var normalized_topic := ChatTopicClass.new()
	normalized_topic.topic_id = "normalized_topic"
	normalized_topic.channel_id = "normalized_topic_channel"
	topic_manager.activate_topic(normalized_topic)
	topic_manager.complete_topic(normalized_topic, {"summary": "ok"})
	print("  topic result default topic_failed: %s (expect false)" % str(bool(normalized_topic.result_variables.get("topic_failed", true))))
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		print("[SKIP] GameLoopManager not found")
	else:
		glm.current_day = 3
		glm.time_phase = 0
		sd.completed_chapters["day1"] = true
		sd.set_variable("signup_completed", true)

		var auto_chapter := StoryChapterClass.new()
		auto_chapter.chapter_id = "test_auto_trigger"
		auto_chapter.chapter_name = "自动触发测试"
		auto_chapter.priority = 99
		auto_chapter.trigger = {
			"min_day": 3,
			"phase": "MORNING",
			"required_chapters": ["day1"],
			"conditions": ["signup_completed == true"],
		}

		var auto_step := StoryStepClass.new()
		auto_step.step_id = "test_auto_trigger_01"
		auto_step.wait_for = {
			"type": "variable_equals",
			"key": "auto_trigger_ack",
			"value": true,
		}
		auto_chapter.steps.append(auto_step)
		sd._chapters[auto_chapter.chapter_id] = auto_chapter

		var started: bool = sd.evaluate_triggers()
		print("  auto trigger started: %s (expect true)" % str(started))
		print("  current_chapter: %s (expect test_auto_trigger)" % (sd.current_chapter.chapter_id if sd.current_chapter else "null"))
		sd.set_variable("auto_trigger_ack", true)
		await _flush_frames(2)

	print("[INFO] Testing direct story AVG playback...")
	sd.reset_runtime_state()
	var mock_generator := MockStoryAVGGenerator.new()
	var mock_window := MockSceneWindowAdapter.new()
	sd._story_avg_generator = mock_generator
	sd._story_avg_scene_adapter = mock_window
	var transit_manager: Node = get_node_or_null("/root/TransitManager")
	var story_avg_transit_ids: Array[String] = []
	if transit_manager != null and transit_manager.has_signal("transit_started"):
		transit_manager.transit_started.connect(func(transit_id: String, _payload: Dictionary) -> void:
			if transit_id.begins_with("story_avg_generation_"):
				story_avg_transit_ids.append(transit_id)
		)

	var direct_chapter := StoryChapterClass.new()
	direct_chapter.chapter_id = "test_direct_story_avg"
	direct_chapter.chapter_name = "直接剧情 AVG"

	var direct_step := StoryStepClass.new()
	direct_step.step_id = "test_direct_story_avg_01"
	direct_step.description = "直接播放剧情 AVG"
	direct_step.actions = [{
		"type": "play_avg",
		"scene_id": "direct_story_avg",
		"title": "突发事件",
		"prompt": "外星人突然入侵，抓走了女友，玩家必须立刻追上去。",
		"guidance_prompt": "节奏要快，第一屏就进入危机。",
	}]
	direct_step.wait_for = {"type": "avg_scene_ended", "scene_id": "direct_story_avg"}
	direct_step.capture = {"direct_avg_summary": "outcome.summary"}
	direct_chapter.steps.append(direct_step)
	sd._chapters[direct_chapter.chapter_id] = direct_chapter
	sd.start_chapter(direct_chapter.chapter_id)
	await _flush_frames(6)
	print("  direct AVG request count: %s (expect 1)" % str(mock_generator.request_count))
	print("  direct AVG transit started: %s (expect true)" % str(not story_avg_transit_ids.is_empty()))
	print("  direct AVG activity_type: %s (expect story)" % str(mock_generator.last_session.get("activity_type", "")))
	print("  direct AVG summary captured: %s (expect mock finished)" % str(sd.get_variable("direct_avg_summary", "")))

	print("[INFO] Testing topic -> branch -> story AVG...")
	sd.reset_runtime_state()
	var branch_generator := MockStoryAVGGenerator.new()
	var branch_window := MockSceneWindowAdapter.new()
	sd._story_avg_generator = branch_generator
	sd._story_avg_scene_adapter = branch_window
	var ap_before: int = -1
	if glm != null:
		glm.current_ap = max(2, glm.current_ap)
		ap_before = glm.current_ap

	var branch_chapter := StoryChapterClass.new()
	branch_chapter.chapter_id = "test_branch_story_avg"
	branch_chapter.chapter_name = "话题分支剧情 AVG"

	var gate_step := StoryStepClass.new()
	gate_step.step_id = "gate"
	gate_step.wait_for = {"type": "topic_completed", "topic_id": "story_invite_gate"}
	gate_step.capture = {
		"invite_rejected": "result.topic_failed",
	}
	gate_step.next_conditions = [
		{"if": "invite_rejected == false", "next": "play_avg"},
		{"default": true, "next": "decline"},
	]

	var play_step := StoryStepClass.new()
	play_step.step_id = "play_avg"
	play_step.actions = [{
		"type": "play_avg",
		"scene_id": "invite_story_avg",
		"title": "邀约后续",
		"prompt": "根据刚才整段邀约对话继续推进，不要丢掉玩家答应时的语气、犹豫和亲密边界。",
		"include_chat_history": false,
	}]
	play_step.wait_for = {"type": "avg_scene_ended", "scene_id": "invite_story_avg"}
	play_step.capture = {"invite_avg_summary": "outcome.summary"}
	play_step.next = "cleanup"

	var cleanup_step := StoryStepClass.new()
	cleanup_step.step_id = "cleanup"
	cleanup_step.actions = [{
		"type": "minimize_app_window",
		"app_id": "avg_player",
	}, {
		"type": "consume_ap",
		"amount": 1,
		"action_type": "story",
		"detail": "invite_story_avg",
	}]
	cleanup_step.next = "done"

	var decline_step := StoryStepClass.new()
	decline_step.step_id = "decline"
	decline_step.actions = [{
		"type": "set_variable",
		"key": "invite_declined_branch",
		"value": true,
	}]
	decline_step.next = "done"

	var done_step := StoryStepClass.new()
	done_step.step_id = "done"

	branch_chapter.steps.append(gate_step)
	branch_chapter.steps.append(play_step)
	branch_chapter.steps.append(cleanup_step)
	branch_chapter.steps.append(decline_step)
	branch_chapter.steps.append(done_step)
	sd._chapters[branch_chapter.chapter_id] = branch_chapter
	sd.start_chapter(branch_chapter.chapter_id)

	var topic := ChatTopicClass.new()
	topic.topic_id = "story_invite_gate"
	topic.channel_id = "dm_lin_xia"
	sd._on_wait_topic_completed(topic, {
		"topic_failed": false,
		"summary": "玩家答应了，想继续看看会发生什么。",
		"conversation_messages": [
			{"speaker_id": "npc_lin_xia", "speaker_name": "林夏", "content": "今晚别走了，好不好？"},
			{"speaker_id": "player", "speaker_name": "玩家", "content": "好，我陪你。"},
		],
	})
	await _flush_frames(6)
	print("  branched AVG request count: %s (expect 1)" % str(branch_generator.request_count))
	print("  branched AVG captured conversation: %s (expect true)" % str((branch_generator.last_session.get("story_trigger_conversation", []) as Array).size() >= 2))
	print("  branched AVG minimized after finish: %s (expect 1)" % str(branch_window.minimize_calls))
	if glm != null and ap_before >= 0:
		print("  branched AVG AP consumed: %s (expect 1)" % str(ap_before - glm.current_ap))
	print("  branched AVG summary captured: %s (expect mock finished)" % str(sd.get_variable("invite_avg_summary", "")))
	print("  decline branch untouched: %s (expect false)" % str(bool(sd.get_variable("invite_declined_branch", false))))

	print("[INFO] Testing project preview orchestration...")
	sd.reset_runtime_state()
	var preview_adapter := MockProjectPreviewAdapter.new()
	sd._project_preview_adapter = preview_adapter

	var preview_chapter := StoryChapterClass.new()
	preview_chapter.chapter_id = "test_project_preview"
	preview_chapter.chapter_name = "试玩玩家工程"

	var preview_step := StoryStepClass.new()
	preview_step.step_id = "preview"
	preview_step.actions = [{
		"type": "preview_current_project",
		"preview_id": "girlfriend_demo",
	}]
	preview_step.wait_for = {"type": "project_preview_finished", "preview_id": "girlfriend_demo"}
	preview_step.capture = {
		"project_preview_completed": "payload.completed",
		"project_preview_scene_id": "payload.scene_id",
	}
	preview_step.next = "after_preview"

	var after_preview_step := StoryStepClass.new()
	after_preview_step.step_id = "after_preview"
	after_preview_step.actions = [{
		"type": "set_variable",
		"key": "girlfriend_review_ready",
		"value": true,
	}]

	preview_chapter.steps.append(preview_step)
	preview_chapter.steps.append(after_preview_step)
	sd._chapters[preview_chapter.chapter_id] = preview_chapter
	sd.start_chapter(preview_chapter.chapter_id)
	await _flush_frames(4)
	print("  project preview started count: %s (expect 1)" % str(preview_adapter.started_preview_ids.size()))
	print("  project preview completed captured: %s (expect true)" % str(bool(sd.get_variable("project_preview_completed", false))))
	print("  project preview scene captured: %s (expect final_scene)" % str(sd.get_variable("project_preview_scene_id", "")))
	print("  project review step entered: %s (expect true)" % str(bool(sd.get_variable("girlfriend_review_ready", false))))

	print("[INFO] Testing project preview manual close...")
	sd.reset_runtime_state()
	var closed_preview_adapter := MockProjectPreviewAdapter.new()
	sd._project_preview_adapter = closed_preview_adapter

	var closed_preview_chapter := StoryChapterClass.new()
	closed_preview_chapter.chapter_id = "test_project_preview_closed"
	closed_preview_chapter.chapter_name = "试玩玩家工程-手动关闭"

	var closed_preview_step := StoryStepClass.new()
	closed_preview_step.step_id = "preview"
	closed_preview_step.actions = [{
		"type": "preview_current_project",
		"preview_id": "girlfriend_demo_closed",
		"simulate_closed": true,
	}]
	closed_preview_step.wait_for = {"type": "project_preview_finished", "preview_id": "girlfriend_demo_closed"}
	closed_preview_step.capture = {
		"project_preview_closed": "payload.closed",
		"project_preview_end_reason": "payload.end_reason",
	}
	closed_preview_step.next = "after_close"

	var after_close_step := StoryStepClass.new()
	after_close_step.step_id = "after_close"
	after_close_step.actions = [{
		"type": "set_variable",
		"key": "girlfriend_review_after_close_ready",
		"value": true,
	}]

	closed_preview_chapter.steps.append(closed_preview_step)
	closed_preview_chapter.steps.append(after_close_step)
	sd._chapters[closed_preview_chapter.chapter_id] = closed_preview_chapter
	sd.start_chapter(closed_preview_chapter.chapter_id)
	await _flush_frames(4)
	print("  project preview close captured: %s (expect true)" % str(bool(sd.get_variable("project_preview_closed", false))))
	print("  project preview close reason: %s (expect closed)" % str(sd.get_variable("project_preview_end_reason", "")))
	print("  project review after close entered: %s (expect true)" % str(bool(sd.get_variable("girlfriend_review_after_close_ready", false))))
	sd._project_preview_adapter = null

	print("=== Test Complete ===")


func _flush_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
