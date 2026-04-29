extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var campaign: Node = get_node_or_null("/root/CampaignRunManager")
	var storage: Node = get_node_or_null("/root/StorageManager")
	if campaign == null or storage == null:
		print("[FAIL] CampaignRun debug resume test missing autoloads")
		return

	if storage.has_method("_remove_directory_recursive") and DirAccess.dir_exists_absolute("user://run/"):
		storage._remove_directory_recursive("user://run/")
	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()

	var mount_err: Error = storage.mount_runtime_project("tutorial_project")
	if mount_err != OK:
		print("[FAIL] Failed to seed runtime project: %s" % mount_err)
		return

	var stale_file_path: String = "user://run/player_project/resume_probe.txt"
	var stale_dir_path: String = stale_file_path.get_base_dir() + "/"
	if not DirAccess.dir_exists_absolute(stale_dir_path):
		var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(stale_dir_path)
		if mkdir_err != OK:
			print("[FAIL] Failed to create probe directory: %s" % stale_dir_path)
			return

	var file: FileAccess = FileAccess.open(stale_file_path, FileAccess.WRITE)
	if file == null:
		print("[FAIL] Failed to seed probe file: %s" % stale_file_path)
		return
	file.store_string("resume")
	file.close()

	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()
	storage.developer_mode = false
	campaign.set_debug_runtime_resume_on_boot_override(true)
	campaign._prepare_runtime_boot_for_current_mode()
	await get_tree().process_frame

	var stale_preserved: bool = FileAccess.file_exists(stale_file_path)
	var runtime_path: String = str(storage.runtime_project_path).strip_edges()
	var current_path: String = str(storage.current_project_path).strip_edges()
	var project_loaded: bool = storage.current_project != null
	var debug_resume_enabled: bool = campaign.is_debug_runtime_resume_on_boot_enabled()
	var boot_mode_is_not_fresh: bool = not bool(campaign._should_prepare_fresh_runtime_boot())

	if stale_preserved:
		print("PASS  debug resume kept existing runtime project files")
	else:
		print("FAIL  debug resume unexpectedly cleared runtime project files")

	if runtime_path == "user://run/player_project/":
		print("PASS  debug resume remounted player_project")
	else:
		print("FAIL  runtime_project_path mismatch: %s" % runtime_path)

	if current_path == "user://run/player_project/":
		print("PASS  debug resume current project points at player_project")
	else:
		print("FAIL  current_project_path mismatch: %s" % current_path)

	if project_loaded:
		print("PASS  debug resume loaded existing runtime project")
	else:
		print("FAIL  current project was not loaded during debug resume")

	if debug_resume_enabled:
		print("PASS  debug resume flag enabled")
	else:
		print("FAIL  debug resume flag was not enabled")

	if boot_mode_is_not_fresh:
		print("PASS  debug resume boot skips fresh reset")
	else:
		print("FAIL  debug resume boot still requested fresh reset")

	campaign.clear_debug_runtime_resume_on_boot_override()

	var pass_count: int = 0
	if stale_preserved:
		pass_count += 1
	if runtime_path == "user://run/player_project/":
		pass_count += 1
	if current_path == "user://run/player_project/":
		pass_count += 1
	if project_loaded:
		pass_count += 1
	if debug_resume_enabled:
		pass_count += 1
	if boot_mode_is_not_fresh:
		pass_count += 1
	print("SUMMARY  pass=%d fail=%d" % [pass_count, 6 - pass_count])
