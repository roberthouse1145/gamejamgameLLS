class_name TestDesktop extends Desktop


func _after_desktop_ready() -> void:
	await get_tree().create_timer(1.0).timeout

	# ── 启动测试章节 ──
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("start_chapter"):
		story_director.start_chapter("test_brief")
