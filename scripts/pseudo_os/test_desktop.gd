class_name TestDesktop extends Desktop

enum TestRoute {
	SLEEP_INVITE,
	PROJECT_PREVIEW,
	DAY5_NIGHT,
	NO,
}

const INITIAL_DEV_WORK_TEMPLATE_PATH: String = "res://resources/dev_work/story_tasks/lock_creative_direction.json"
const INITIAL_DEV_WORK_TASK_ID: String = "lock_creative_direction"

@export_enum("一起睡邀约", "试玩当前工程", "Day5夜晚","NO") var test_route: int = TestRoute.NO
@export var inject_initial_dev_work: bool = true
@export var allow_manual_story_start: bool = false


func _resolve_test_chapter_id() -> String:
	match test_route:
		TestRoute.SLEEP_INVITE:
			return "test_sleep_invite"
		TestRoute.PROJECT_PREVIEW:
			return "test_project_preview"
		TestRoute.DAY5_NIGHT:
			return "day5_night"
		_:
			return "day5_night"


func _after_desktop_ready() -> void:
	if inject_initial_dev_work:
		_ensure_initial_dev_work()

	if not allow_manual_story_start or test_route == TestRoute.NO:
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


func _ensure_initial_dev_work() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or not dcm.has_method("add_dynamic_task"):
		push_warning("[TestDesktop] DevCycleManager not available; initial Dev Work was not injected")
		return

	if dcm.has_method("get_task"):
		var existing: Dictionary = dcm.get_task(INITIAL_DEV_WORK_TASK_ID)
		if not existing.is_empty():
			return

	var task_def: Dictionary = _load_dev_work_template_dict(INITIAL_DEV_WORK_TEMPLATE_PATH)
	if task_def.is_empty():
		push_warning("[TestDesktop] Failed to load initial Dev Work template: %s" % INITIAL_DEV_WORK_TEMPLATE_PATH)
		return

	var added_id: String = str(dcm.add_dynamic_task(task_def))
	if added_id.is_empty():
		push_warning("[TestDesktop] Failed to inject initial Dev Work task: %s" % INITIAL_DEV_WORK_TASK_ID)
	else:
		print("[TestDesktop] Initial Dev Work injected: %s" % added_id)


func _load_dev_work_template_dict(path: String) -> Dictionary:
	var p: String = path.strip_edges()
	if p.is_empty() or not FileAccess.file_exists(p):
		return {}
	var file := FileAccess.open(p, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}
