extends Node

func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var storage: Node = get_node_or_null("/root/StorageManager")
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if storage == null or kb == null:
		print("[FAIL] project_save persists KB test missing autoloads")
		return

	if storage.has_method("_remove_directory_recursive"):
		if DirAccess.dir_exists_absolute("user://run/trunk/"):
			storage._remove_directory_recursive("user://run/trunk/")
		if DirAccess.dir_exists_absolute("user://run/player_project/"):
			storage._remove_directory_recursive("user://run/player_project/")
	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()

	var mount_err: Error = storage.mount_runtime_project("tutorial_project")
	if mount_err != OK:
		print("[FAIL] Failed to mount runtime project: %s" % mount_err)
		return

	var doc_id: String = "agent_project_save_%d" % Time.get_ticks_msec()
	var expected_doc_path: String = str(storage.current_project_path).path_join("knowledge_base").path_join("docs").path_join(doc_id + ".json")
	if FileAccess.file_exists(expected_doc_path):
		DirAccess.remove_absolute(expected_doc_path)

	kb.upsert_document(doc_id, "Agent Save KB Probe", "验证 project_save 会同时保存 KB。", "notes", ["agent-save"], "tester")

	var existed_before_save: bool = FileAccess.file_exists(expected_doc_path)
	var save_err: Error = storage.save_project(storage.current_project)
	var exists_after_save: bool = FileAccess.file_exists(expected_doc_path)
	var result_ok: bool = save_err == OK

	if not existed_before_save:
		print("PASS  kb doc not written before project_save")
	else:
		print("FAIL  kb doc unexpectedly existed before project_save")

	if result_ok:
		print("PASS  StorageManager.save_project returned success")
	else:
		print("FAIL  StorageManager.save_project failed: %s" % str(save_err))

	if exists_after_save:
		print("PASS  project_save persisted knowledge base doc")
	else:
		print("FAIL  kb doc missing after project_save: %s" % expected_doc_path)

	var pass_count: int = 0
	if not existed_before_save:
		pass_count += 1
	if result_ok:
		pass_count += 1
	if exists_after_save:
		pass_count += 1
	print("SUMMARY  pass=%d fail=%d" % [pass_count, 3 - pass_count])
