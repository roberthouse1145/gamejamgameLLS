extends Node

const ProjectToolsClass = preload("res://scripts/avg/dev_tools/project_tools.gd")
const AssetManifestClass = preload("res://scripts/avg/assets/avg_asset_manifest.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== import_project_asset test ===")

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null:
		_fail("StorageManager autoload", "未找到 /root/StorageManager")
		_print_summary()
		return

	var mount_err: Error = storage.mount_runtime_project()
	_assert("mount_runtime_project", mount_err == OK, "error=%s" % mount_err)
	if mount_err != OK:
		_print_summary()
		return

	if storage.has_method("clear_asset_manifest_cache"):
		storage.clear_asset_manifest_cache()

	var unique_id: String = str(Time.get_unix_time_from_system()).replace(".", "_")
	var requested_alias: String = "test_reward_card_%s" % unique_id
	var source_path: String = ProjectSettings.globalize_path("res://Assets/icons/icon_money.png")
	var target_subdir: String = "tests/generated_%s" % unique_id

	var manifest_before: Dictionary = storage.get_asset_manifest()
	var image_bucket_before: Dictionary = manifest_before.get("images", {})
	_assert("alias absent before import", not image_bucket_before.has(requested_alias), "alias=%s" % requested_alias)

	var result: Dictionary = ProjectToolsClass._import_project_asset({
		"source_path": source_path,
		"asset_type": "image",
		"alias": requested_alias,
		"target_subdir": target_subdir,
	})
	_assert("tool import success", bool(result.get("success", false)), str(result))
	if not bool(result.get("success", false)):
		_print_summary()
		return

	var relative_path: String = str(result.get("relative_path", ""))
	var absolute_path: String = str(result.get("absolute_path", ""))
	var final_alias: String = str(result.get("alias", ""))
	_assert("alias returned", final_alias == "img_%s" % requested_alias, "alias=%s" % final_alias)
	_assert("file copied", FileAccess.file_exists(absolute_path), absolute_path)

	var manifest_after: Dictionary = storage.get_asset_manifest()
	var image_bucket_after: Dictionary = manifest_after.get("images", {})
	_assert("alias visible after import", image_bucket_after.get(final_alias, "") == relative_path, str(image_bucket_after))

	var manifest_path: String = storage.current_project_path + "manifests/asset_aliases.json"
	var manifest_file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		_fail("manifest file readable", manifest_path)
	else:
		var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
		manifest_file.close()
		if parsed is Dictionary:
			var disk_bucket: Dictionary = parsed.get("images", {})
			_assert("manifest persisted to disk", disk_bucket.get(final_alias, "") == relative_path, str(disk_bucket))
		else:
			_fail("manifest persisted to disk", "JSON parse failed")

	var resolved_path: String = AssetManifestClass.resolve_texture_path(final_alias, storage.current_project_path)
	_assert("alias resolves to imported file", resolved_path == absolute_path, "resolved=%s expected=%s" % [resolved_path, absolute_path])

	_print_summary()


func _assert(assert_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % assert_name)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [assert_name, detail])


func _fail(assert_name: String, detail: String) -> void:
	_fail_count += 1
	print("FAIL  %s  %s" % [assert_name, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
