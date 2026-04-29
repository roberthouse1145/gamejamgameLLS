class_name TestDesktop extends Desktop

enum TestRoute {
	SLEEP_INVITE,
	PROJECT_PREVIEW,
	DAY7_NIGHT,
	NO,
}

@export_enum("一起睡邀约", "试玩当前工程", "Day7夜晚","NO") var test_route: int = TestRoute.DAY7_NIGHT


func _resolve_test_chapter_id() -> String:
	
	match test_route:
		TestRoute.SLEEP_INVITE:
			return "test_sleep_invite"
		TestRoute.PROJECT_PREVIEW:
			return "test_project_preview"
		TestRoute.DAY7_NIGHT:
			return "day7_night"
		_:
			return "day7_night"


func _after_desktop_ready() -> void:
	return
	while not Input.is_action_just_pressed("ui_down"):
		await get_tree().process_frame

	var chapter_id: String = _resolve_test_chapter_id()
	var run_manager: Node = get_node_or_null("/root/CampaignRunManager")
	if run_manager != null and run_manager.has_method("ensure_campaign_started"):
		run_manager.ensure_campaign_started(chapter_id)
		return

	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("start_chapter"):
		story_director.start_chapter(chapter_id)
