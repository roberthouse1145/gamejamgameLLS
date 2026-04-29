extends Node

const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _storage: Node = null
var _created_scene_id: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== db create custom scene_id test ===")

	_storage = get_node_or_null("/root/StorageManager")
	if _storage == null:
		_fail("StorageManager autoload", "未找到 /root/StorageManager")
		_print_summary()
		return

	var mount_err: Error = _storage.mount_runtime_project()
	_assert("mount_runtime_project", mount_err == OK, "error=%s" % mount_err)
	if mount_err != OK:
		_print_summary()
		return

	var create_result: Dictionary = DBToolsClass._db_create({
		"type": "scenes",
		"fields": {
			"scene_id": "scene_01_academy_gate",
			"scene_name": "学园大门",
			"scene_note": "测试自定义 scene_id"
		}
	})
	_assert("custom scene_id create succeeds", bool(create_result.get("success", false)), str(create_result))
	_assert("custom scene_id returned", str(create_result.get("id", "")) == "scene_01_academy_gate", str(create_result))
	if bool(create_result.get("success", false)):
		_created_scene_id = str(create_result.get("id", "")).strip_edges()

	var scene_list: Dictionary = DBToolsClass._db_list({"type": "scenes"})
	var found_scene: bool = false
	for entry in scene_list.get("data", []):
		if str(entry.get("id", "")) == "scene_01_academy_gate":
			found_scene = true
			break
	_assert("custom scene_id present in db_list", found_scene, str(scene_list))

	var get_result: Dictionary = DBToolsClass._db_get({
		"type": "scenes",
		"id": "scene_01_academy_gate"
	})
	_assert("db_get scene returns root_dsl field", bool(get_result.get("success", false)) and get_result.get("data", {}).has("root_dsl"), str(get_result))
	_assert("db_get scene returns dsl alias field", bool(get_result.get("success", false)) and get_result.get("data", {}).has("dsl"), str(get_result))

	var update_dsl_result: Dictionary = DBToolsClass._db_update({
		"type": "scenes",
		"id": "scene_01_academy_gate",
		"fields": {
			"root_dsl": "screen.fade(direction=\"in\", duration=0.2)\nscene.jump(\"scene_01_academy_gate\")"
		}
	})
	_assert("db_update accepts root_dsl alias for scene script", bool(update_dsl_result.get("success", false)), str(update_dsl_result))

	var verify_update_result: Dictionary = DBToolsClass._db_get({
		"type": "scenes",
		"id": "scene_01_academy_gate"
	})
	var updated_dsl: String = str(verify_update_result.get("data", {}).get("root_dsl", ""))
	_assert("scene root_dsl actually updated", updated_dsl.contains("scene.jump(\"scene_01_academy_gate\")"), str(verify_update_result))

	var rename_result: Dictionary = DBToolsClass._db_update({
		"type": "scenes",
		"id": "scene_01_academy_gate",
		"fields": {
			"scene_id": "scene_renamed_gate"
		}
	})
	_assert("db_update rejects scene_id mutation", not bool(rename_result.get("success", false)), str(rename_result))

	_cleanup_created_scene()
	_print_summary()


func _cleanup_created_scene() -> void:
	if _created_scene_id.is_empty():
		return
	DBToolsClass._db_delete({"type": "scenes", "id": _created_scene_id})


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
	_cleanup_created_scene()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
