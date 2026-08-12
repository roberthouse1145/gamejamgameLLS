extends Node
## 通用剧情锁。锁只描述运行期约束，不拥有具体剧情或 APP 状态。

signal locks_changed(snapshot: Dictionary)

var _locks: Dictionary = {}


func acquire_lock(owner_id: String, config: Dictionary) -> bool:
	var normalized_owner: String = owner_id.strip_edges()
	if normalized_owner.is_empty():
		return false
	_locks[normalized_owner] = _normalize_config(config)
	_emit_changed()
	return true


func update_lock(owner_id: String, patch: Dictionary) -> bool:
	var normalized_owner: String = owner_id.strip_edges()
	if not _locks.has(normalized_owner):
		return false
	var updated: Dictionary = (_locks[normalized_owner] as Dictionary).duplicate(true)
	for key: Variant in patch:
		updated[key] = patch[key]
	_locks[normalized_owner] = _normalize_config(updated)
	_emit_changed()
	return true


func release_lock(owner_id: String) -> bool:
	var normalized_owner: String = owner_id.strip_edges()
	if not _locks.erase(normalized_owner):
		return false
	_emit_changed()
	return true


func has_lock(owner_id: String = "") -> bool:
	var normalized_owner: String = owner_id.strip_edges()
	return not _locks.is_empty() if normalized_owner.is_empty() else _locks.has(normalized_owner)


func can_consume_time(requester_id: String = "") -> bool:
	var normalized_requester: String = requester_id.strip_edges()
	for owner_value: Variant in _locks:
		var owner_id: String = str(owner_value)
		var config: Dictionary = _locks[owner_value] as Dictionary
		if bool(config.get("block_time_actions", false)) and owner_id != normalized_requester:
			return false
	return true


func can_launch_app(app_id: String) -> bool:
	var normalized_app_id: String = app_id.strip_edges()
	for config_value: Variant in _locks.values():
		if not config_value is Dictionary:
			continue
		var config: Dictionary = config_value
		if not bool(config.get("restrict_apps", false)):
			continue
		var allowed_apps: Array[String] = _string_array(config.get("allowed_apps", []))
		if normalized_app_id not in allowed_apps:
			return false
	return true


func can_close_app(app_id: String) -> bool:
	var normalized_app_id: String = app_id.strip_edges()
	for config_value: Variant in _locks.values():
		if not config_value is Dictionary:
			continue
		var protected_apps: Array[String] = _string_array((config_value as Dictionary).get("protected_apps", []))
		if normalized_app_id in protected_apps:
			return false
	return true


func get_reason() -> String:
	for config_value: Variant in _locks.values():
		if config_value is Dictionary:
			var reason: String = str((config_value as Dictionary).get("reason", "")).strip_edges()
			if not reason.is_empty():
				return reason
	return "剧情正在进行"


func get_snapshot() -> Dictionary:
	return _locks.duplicate(true)


func reset_runtime_state() -> void:
	if _locks.is_empty():
		return
	_locks.clear()
	_emit_changed()


func _normalize_config(config: Dictionary) -> Dictionary:
	return {
		"block_time_actions": bool(config.get("block_time_actions", false)),
		"restrict_apps": bool(config.get("restrict_apps", false)),
		"allowed_apps": _string_array(config.get("allowed_apps", [])),
		"protected_apps": _string_array(config.get("protected_apps", [])),
		"reason": str(config.get("reason", "剧情正在进行")).strip_edges(),
	}


func _emit_changed() -> void:
	var snapshot: Dictionary = get_snapshot()
	locks_changed.emit(snapshot)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			var normalized: String = str(item).strip_edges()
			if not normalized.is_empty() and normalized not in result:
				result.append(normalized)
	return result
