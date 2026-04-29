extends Node

const ProjectToolsClass = preload("res://scripts/avg/dev_tools/project_tools.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _storage: Node = null
var _restored: bool = false
var _target_character: Resource = null
var _original_fields: Dictionary = {}


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== character shell casting test ===")

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

	var available_before: Dictionary = ProjectToolsClass._list_character_shells({"only_available": true})
	var available_items: Array = available_before.get("data", [])
	_assert("list available shells", bool(available_before.get("success", false)) and not available_items.is_empty(), str(available_before))
	if not bool(available_before.get("success", false)) or available_items.is_empty():
		_print_summary()
		return

	var target_entry: Dictionary = available_items[0]
	var target_id: String = str(target_entry.get("id", "")).strip_edges()
	_target_character = _find_character_by_id(target_id)
	_assert("target shell exists", _target_character != null, target_id)
	if _target_character == null:
		_print_summary()
		return

	_original_fields = {
		"character_key": str(_target_character.character_key if "character_key" in _target_character else ""),
		"character_name": str(_target_character.character_name if "character_name" in _target_character else ""),
		"display_name": str(_target_character.display_name if "display_name" in _target_character else ""),
		"profile": str(_target_character.profile if "profile" in _target_character else ""),
	}

	var unique_suffix: String = str(Time.get_unix_time_from_system()).replace(".", "_")
	var role_key: String = "test_role_%s" % unique_suffix
	var role_name: String = "TestHero%s" % unique_suffix.right(6)
	var display_name: String = "测试主角%s" % unique_suffix.right(6)
	var profile: String = "冷静克制的学院优等生，习惯把压力藏起来，对外礼貌，对内有很强的自我要求。"

	var occupy_result: Dictionary = ProjectToolsClass._occupy_character_shell({
		"character_id": target_id,
		"character_key": role_key,
		"character_name": role_name,
		"display_name": display_name,
		"profile": profile,
	})
	_assert("occupy shell succeeds", bool(occupy_result.get("success", false)), str(occupy_result))
	if bool(occupy_result.get("success", false)):
		var bound_character: Dictionary = occupy_result.get("character", {})
		_assert("occupied key stored", str(bound_character.get("character_key", "")) == role_key, str(bound_character))
		_assert("occupied character_name stored as ascii dsl key", str(bound_character.get("character_name", "")) == role_name, str(bound_character))
		_assert("occupied display_name stored as localized label", str(bound_character.get("display_name", "")) == display_name, str(bound_character))
		_assert("occupied shell marked", bool(bound_character.get("occupied", false)), str(bound_character))

	var available_after: Dictionary = ProjectToolsClass._list_character_shells({"only_available": true})
	var still_available: bool = false
	for entry in available_after.get("data", []):
		if str(entry.get("id", "")) == target_id:
			still_available = true
			break
	_assert("occupied shell removed from available list", not still_available, str(available_after))

	var overwrite_result: Dictionary = ProjectToolsClass._occupy_character_shell({
		"character_id": target_id,
		"character_key": "other_role_%s" % unique_suffix,
		"character_name": "OverwriteTest",
		"display_name": "覆盖测试",
		"profile": "不应覆盖成功",
	})
	_assert("occupied shell cannot be overwritten", not bool(overwrite_result.get("success", false)), str(overwrite_result))

	var invalid_name_result: Dictionary = ProjectToolsClass._occupy_character_shell({
		"character_id": target_id,
		"character_key": "invalid_name_%s" % unique_suffix,
		"character_name": "林晓月",
		"display_name": "林晓月",
		"profile": "不应因为中文 character_name 而成功",
	})
	_assert("non-ascii character_name rejected", not bool(invalid_name_result.get("success", false)), str(invalid_name_result))

	var duplicate_key_tested: bool = false
	for entry in available_after.get("data", []):
		var other_id: String = str(entry.get("id", "")).strip_edges()
		if other_id.is_empty() or other_id == target_id:
			continue
		duplicate_key_tested = true
		var duplicate_key_result: Dictionary = ProjectToolsClass._occupy_character_shell({
			"character_id": other_id,
			"character_key": role_key,
			"character_name": "DuplicateKeyTest",
			"display_name": "重复 Key 测试",
			"profile": "不应因为 key 冲突而成功",
		})
		_assert("duplicate character_key rejected", not bool(duplicate_key_result.get("success", false)), str(duplicate_key_result))
		break
	_assert("duplicate key test had fallback slot", duplicate_key_tested, str(available_after))

	_restore_target_character()
	_print_summary()


func _find_character_by_id(character_id: String) -> Resource:
	if _storage == null or _storage.current_project == null or not ("characters" in _storage.current_project):
		return null
	for character in _storage.current_project.characters:
		if character == null:
			continue
		var existing_id: String = str(character.character_id if "character_id" in character else "").strip_edges()
		if existing_id == character_id:
			return character
	return null


func _restore_target_character() -> void:
	if _restored or _target_character == null:
		return
	if "character_key" in _target_character:
		_target_character.character_key = str(_original_fields.get("character_key", ""))
	if "character_name" in _target_character:
		_target_character.character_name = str(_original_fields.get("character_name", ""))
	if "display_name" in _target_character:
		_target_character.display_name = str(_original_fields.get("display_name", ""))
	if "profile" in _target_character:
		_target_character.profile = str(_original_fields.get("profile", ""))
	if _storage != null and _storage.current_project != null:
		_storage.save_project(_storage.current_project)
		if _storage.has_signal("project_content_changed"):
			_storage.project_content_changed.emit()
	_restored = true


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
	_restore_target_character()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
