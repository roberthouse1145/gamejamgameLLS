extends Node

const AVGScenePromptBuilderClass = preload("res://scripts/activity/avg_scene_prompt_builder.gd")

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

	print("=== Test Complete ===")
