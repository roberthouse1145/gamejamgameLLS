class_name TestDay1BriefDesktop extends Desktop

@export var chapter_id: String = "test_day1_brief"
@export var auto_start_chapter: bool = true


func _after_desktop_ready() -> void:
	if not auto_start_chapter:
		return
	await get_tree().process_frame
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("start_chapter"):
		story_director.start_chapter(chapter_id)
		return
	push_warning("[TestDay1BriefDesktop] StoryDirector not available")
