class_name GameDesktop extends Desktop





func _after_desktop_ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var run_manager: Node = get_node_or_null("/root/CampaignRunManager")
	if run_manager != null and run_manager.has_method("ensure_campaign_started"):
		run_manager.ensure_campaign_started("day1")
		return
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("start_chapter"):
		story_director.start_chapter("day1")
