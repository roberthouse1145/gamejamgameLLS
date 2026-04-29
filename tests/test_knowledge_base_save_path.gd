extends Node
## 回归测试：KnowledgeBase 保存时不应直接写回 res://templates/...。


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	var storage: Node = get_node_or_null("/root/StorageManager")
	if kb == null or storage == null:
		print("[FAIL] KnowledgeBase save path test missing autoloads")
		return

	print("\n=== KnowledgeBase save path test ===")
	var initial_path: String = str(storage.current_project_path)
	print("initial_path=%s" % initial_path)

	if not initial_path.begins_with("res://"):
		print("[SKIP] 当前启动路径不是 template，无法验证 template->user 物化逻辑")
		return

	var doc_id: String = "kb_save_path_%d" % Time.get_ticks_msec()
	kb.upsert_document(doc_id, "KB Save Path Probe", "验证不要写回模板。", "notes", ["regression"], "tester")
	kb.save_data()

	var current_path: String = str(storage.current_project_path)
	var current_project_root: String = ""
	if storage.current_project != null and "project_root_path" in storage.current_project:
		current_project_root = str(storage.current_project.get("project_root_path")).strip_edges()

	var expected_doc_path: String = current_path.path_join("knowledge_base").path_join("docs").path_join(doc_id + ".json")
	var path_ok: bool = current_path.begins_with("user://projects/")
	var root_ok: bool = current_project_root == current_path
	var file_ok: bool = FileAccess.file_exists(expected_doc_path)

	if path_ok:
		print("PASS  current_project_path switched to user copy")
	else:
		print("FAIL  current_project_path still not writable: %s" % current_path)

	if root_ok:
		print("PASS  project_root_path synced")
	else:
		print("FAIL  project_root_path mismatch: %s" % current_project_root)

	if file_ok:
		print("PASS  knowledge base file saved under user project")
	else:
		print("FAIL  knowledge base file missing: %s" % expected_doc_path)

	var pass_count: int = 0
	if path_ok:
		pass_count += 1
	if root_ok:
		pass_count += 1
	if file_ok:
		pass_count += 1
	var fail_count: int = 3 - pass_count
	print("SUMMARY  pass=%d fail=%d" % [pass_count, fail_count])
