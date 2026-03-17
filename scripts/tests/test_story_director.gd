extends Node

func _ready() -> void:
	print("=== StoryDirector Test ===")

	var sd: Node = get_node_or_null("/root/StoryDirector")
	if sd == null:
		print("[FAIL] StoryDirector autoload not found")
		return

	print("[OK] StoryDirector autoload found")

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
