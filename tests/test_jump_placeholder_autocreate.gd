extends Node

const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")
const ScriptToolsClass = preload("res://scripts/avg/dev_tools/script_tools.gd")
const AnalyzerClass = preload("res://scripts/avg/dev_tools/story_reachability_analyzer.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _storage: Node = null
var _created_scene_ids: Array[String] = []


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== jump placeholder autocreate test ===")

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
			"scene_id": "scene_01_intro",
			"scene_name": "开场",
			"scene_note": "测试 jump 自动补空壳"
		}
	})
	_assert("create source scene", bool(create_result.get("success", false)), str(create_result))
	if not bool(create_result.get("success", false)):
		_print_summary()
		return
	_created_scene_ids.append("scene_01_intro")

	var set_result: Dictionary = ScriptToolsClass._set_scene_script({
		"scene_id": "scene_01_intro",
		"mode": "replace",
		"dsl": "screen.fade(direction=\"in\", duration=0.2)\n> 开场测试\nscene.jump(\"scene_02_followup\")"
	})
	_assert("set scene script succeeds", bool(set_result.get("success", false)), str(set_result))
	var set_message: String = str(set_result.get("message", ""))
	_assert("set scene script reports placeholder creation", set_message.contains("已自动创建占位场景"), set_message)

	var scene_list: Dictionary = DBToolsClass._db_list({"type": "scenes"})
	var found_placeholder: bool = false
	for entry in scene_list.get("data", []):
		if str(entry.get("id", "")) == "scene_02_followup":
			found_placeholder = true
			break
	_assert("placeholder scene created", found_placeholder, str(scene_list))
	if found_placeholder:
		_created_scene_ids.append("scene_02_followup")

	var placeholder_get: Dictionary = DBToolsClass._db_get({
		"type": "scenes",
		"id": "scene_02_followup"
	})
	var placeholder_data: Dictionary = placeholder_get.get("data", {})
	_assert("placeholder scene note marked", str(placeholder_data.get("scene_note", "")).begins_with(DBToolsClass.PLACEHOLDER_SCENE_NOTE_PREFIX), str(placeholder_get))
	_assert("placeholder scene dsl empty", str(placeholder_data.get("root_dsl", "")).strip_edges().is_empty(), str(placeholder_get))

	var analyzer := AnalyzerClass.new()
	var catalog_result: Dictionary = analyzer.build_scene_catalog(DBToolsClass.get_project())
	var by_id: Dictionary = {}
	for row in catalog_result.get("data", []):
		by_id[str(row.get("scene_id", ""))] = row
	_assert("catalog marks placeholder scene", bool(by_id.get("scene_02_followup", {}).get("is_placeholder", false)), str(catalog_result))

	var fill_placeholder_result: Dictionary = ScriptToolsClass._set_scene_script({
		"scene_id": "scene_02_followup",
		"mode": "replace",
		"dsl": "screen.fade(direction=\"in\", duration=0.2)\n> 占位场景已被正式实现"
	})
	_assert("fill placeholder scene succeeds", bool(fill_placeholder_result.get("success", false)), str(fill_placeholder_result))

	var implemented_get: Dictionary = DBToolsClass._db_get({
		"type": "scenes",
		"id": "scene_02_followup"
	})
	var implemented_data: Dictionary = implemented_get.get("data", {})
	_assert("implemented scene clears placeholder note", not str(implemented_data.get("scene_note", "")).begins_with(DBToolsClass.PLACEHOLDER_SCENE_NOTE_PREFIX), str(implemented_get))
	_assert("implemented scene dsl not empty", not str(implemented_data.get("root_dsl", "")).strip_edges().is_empty(), str(implemented_get))

	var catalog_after_result: Dictionary = analyzer.build_scene_catalog(DBToolsClass.get_project())
	var by_id_after: Dictionary = {}
	for row in catalog_after_result.get("data", []):
		by_id_after[str(row.get("scene_id", ""))] = row
	_assert("catalog clears placeholder flag after implementation", not bool(by_id_after.get("scene_02_followup", {}).get("is_placeholder", false)), str(catalog_after_result))

	_cleanup_created_scenes()
	_print_summary()


func _cleanup_created_scenes() -> void:
	var seen: Dictionary = {}
	for i in range(_created_scene_ids.size() - 1, -1, -1):
		var scene_id: String = _created_scene_ids[i]
		if scene_id.is_empty() or seen.has(scene_id):
			continue
		seen[scene_id] = true
		DBToolsClass._db_delete({"type": "scenes", "id": scene_id})


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
	_cleanup_created_scenes()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
