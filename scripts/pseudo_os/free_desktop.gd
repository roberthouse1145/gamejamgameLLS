class_name FreeDesktop extends Desktop

const INITIAL_BGM_PATH: String = "res://Assets/sounds/bgm/优哉游哉(loop).wav"
const INITIAL_DEV_WORK_TEMPLATE_PATH: String = "res://resources/dev_work/story_tasks/lock_creative_direction.json"
const INITIAL_DEV_WORK_TASK_ID: String = "lock_creative_direction"


func _after_desktop_ready() -> void:
	_clear_active_story()
	_clear_story_app_restriction()
	_play_initial_bgm()
	_ensure_initial_dev_work()
	if pre_generate_activity_catalogs_on_ready:
		pre_generate_activity_catalogs()


func _clear_active_story() -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("reset_runtime_state"):
		story_director.reset_runtime_state()


func _clear_story_app_restriction() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null and app_manager.has_method("clear_app_access_restriction"):
		app_manager.clear_app_access_restriction()


func _play_initial_bgm() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play_bgm"):
		return
	if not ResourceLoader.exists(INITIAL_BGM_PATH):
		push_warning("[FreeDesktop] Initial BGM not found: %s" % INITIAL_BGM_PATH)
		return
	var stream: AudioStream = load(INITIAL_BGM_PATH)
	audio.play_bgm(stream, 2.0)
	print("[FreeDesktop] Initial BGM started: %s" % INITIAL_BGM_PATH)


func _ensure_initial_dev_work() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or not dcm.has_method("add_dynamic_task"):
		push_warning("[FreeDesktop] DevCycleManager not available; initial Dev Work was not injected")
		return

	if dcm.has_method("get_task"):
		var existing: Dictionary = dcm.get_task(INITIAL_DEV_WORK_TASK_ID)
		if not existing.is_empty():
			return

	var task_def: Dictionary = _load_dev_work_template_dict(INITIAL_DEV_WORK_TEMPLATE_PATH)
	if task_def.is_empty():
		push_warning("[FreeDesktop] Failed to load initial Dev Work template: %s" % INITIAL_DEV_WORK_TEMPLATE_PATH)
		return

	var added_id: String = str(dcm.add_dynamic_task(task_def))
	if added_id.is_empty():
		push_warning("[FreeDesktop] Failed to inject initial Dev Work task: %s" % INITIAL_DEV_WORK_TASK_ID)


func _load_dev_work_template_dict(path: String) -> Dictionary:
	var file_path: String = path.strip_edges()
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}
