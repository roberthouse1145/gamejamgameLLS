extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var campaign: Node = get_node_or_null("/root/CampaignRunManager")
	var storage: Node = get_node_or_null("/root/StorageManager")
	if campaign == null or storage == null:
		print("[FAIL] CampaignRun fresh boot test missing autoloads")
		return

	var stale_file_path: String = "user://run/player_project/stale_probe.txt"
	var stale_dir_path: String = stale_file_path.get_base_dir() + "/"
	if not DirAccess.dir_exists_absolute(stale_dir_path):
		var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(stale_dir_path)
		if mkdir_err != OK:
			print("[FAIL] Failed to seed stale runtime directory: %s" % stale_dir_path)
			return

	var file: FileAccess = FileAccess.open(stale_file_path, FileAccess.WRITE)
	if file == null:
		print("[FAIL] Failed to seed stale runtime file: %s" % stale_file_path)
		return
	file.store_string("stale")
	file.close()

	campaign._prepare_fresh_runtime_boot()
	await get_tree().process_frame

	var stale_removed: bool = not FileAccess.file_exists(stale_file_path)
	var runtime_path: String = str(storage.runtime_project_path).strip_edges()
	var current_path: String = str(storage.current_project_path).strip_edges()
	var project_loaded: bool = storage.current_project != null
	var mode_ok: bool = str(campaign.get_startup_mode()) == "fresh_boot"

	if stale_removed:
		print("PASS  fresh boot cleared stale runtime files")
	else:
		print("FAIL  stale runtime file still exists: %s" % stale_file_path)

	if runtime_path == "user://run/player_project/":
		print("PASS  runtime project remounted to player_project")
	else:
		print("FAIL  runtime_project_path mismatch: %s" % runtime_path)

	if current_path == "user://run/player_project/":
		print("PASS  current project points at fresh runtime project")
	else:
		print("FAIL  current_project_path mismatch: %s" % current_path)

	if project_loaded:
		print("PASS  fresh runtime project loaded")
	else:
		print("FAIL  current project was not loaded after fresh boot")

	if mode_ok:
		print("PASS  startup mode marked as fresh_boot")
	else:
		print("FAIL  startup mode mismatch: %s" % str(campaign.get_startup_mode()))

	var pass_count: int = 0
	if stale_removed:
		pass_count += 1
	if runtime_path == "user://run/player_project/":
		pass_count += 1
	if current_path == "user://run/player_project/":
		pass_count += 1
	if project_loaded:
		pass_count += 1
	if mode_ok:
		pass_count += 1
	print("SUMMARY  pass=%d fail=%d" % [pass_count, 5 - pass_count])
