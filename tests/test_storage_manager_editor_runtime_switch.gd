extends Node

const EDITOR_RUNTIME_SETTING: String = "application/run/debug_use_runtime_project_in_editor"

var _pass_count: int = 0
var _fail_count: int = 0
var _original_setting: Variant = false


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null:
		print("[FAIL] StorageManager editor runtime switch test missing autoload")
		return

	_original_setting = ProjectSettings.get_setting(EDITOR_RUNTIME_SETTING, false)
	storage.developer_mode = true

	_cleanup_runtime_project(storage)
	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()

	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, false)
	if storage.has_method("_auto_load_default_project"):
		storage._auto_load_default_project()
	await get_tree().process_frame

	var template_path: String = str(storage.current_project_path).strip_edges()
	var template_runtime_path: String = str(storage.runtime_project_path).strip_edges()
	_assert("editor default boot loads template project", template_path.begins_with("res://templates/tutorial_project/"), template_path)
	_assert("editor default boot keeps runtime path empty", template_runtime_path.is_empty(), template_runtime_path)
	_assert("editor default boot loads project resource", storage.current_project != null, "current_project is null")

	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()
	_cleanup_runtime_project(storage)

	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, true)
	if storage.has_method("_auto_load_default_project"):
		storage._auto_load_default_project()
	await get_tree().process_frame

	var runtime_path: String = str(storage.current_project_path).strip_edges()
	var mounted_runtime_path: String = str(storage.runtime_project_path).strip_edges()
	_assert("editor runtime switch mounts player_project", runtime_path == "user://run/player_project/", runtime_path)
	_assert("editor runtime switch stores runtime path", mounted_runtime_path == "user://run/player_project/", mounted_runtime_path)
	_assert("editor runtime switch loads runtime project resource", storage.current_project != null, "current_project is null")
	_assert("editor runtime switch creates runtime project file", FileAccess.file_exists("user://run/player_project/project.tres"), "user://run/player_project/project.tres")

	_restore_environment(storage)
	_print_summary()


func _cleanup_runtime_project(storage: Node) -> void:
	if storage.has_method("_remove_directory_recursive") and DirAccess.dir_exists_absolute("user://run/player_project/"):
		storage._remove_directory_recursive("user://run/player_project/")


func _restore_environment(storage: Node) -> void:
	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, _original_setting)
	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()
	if storage.has_method("_auto_load_default_project"):
		storage._auto_load_default_project()


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		if detail.is_empty():
			print("FAIL  %s" % label)
		else:
			print("FAIL  %s -- %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
