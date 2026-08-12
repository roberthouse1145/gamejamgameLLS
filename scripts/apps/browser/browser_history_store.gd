class_name BrowserHistoryStore extends RefCounted
## 浏览历史的内存索引与磁盘持久化。页面生成和浏览器 UI 不属于此类。

var persist_history: bool = true

var _history_path: String = ""
var _entries: Array[Dictionary] = []
var _counter: int = 0


func _init(history_path: String) -> void:
	_history_path = history_path


func load_from_disk() -> void:
	_entries.clear()
	_counter = 0
	if not FileAccess.file_exists(_history_path):
		return
	var file: FileAccess = FileAccess.open(_history_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_counter = int(parsed.get("next_id", 0))
	_assign_entries(parsed.get("entries", []))


func get_entries(limit: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = _entries.duplicate(true)
	result.reverse()
	if limit > 0 and result.size() > limit:
		result.resize(limit)
	return result


func get_entry(entry_id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if str(entry.get("entry_id", "")) == entry_id:
			return entry.duplicate(true)
	return {}


func add_entry(
	url: String,
	title: String,
	page: Dictionary,
	prefix: String = "browser"
) -> Dictionary:
	_counter += 1
	var entry: Dictionary = {
		"entry_id": "%s_%04d" % [prefix, _counter],
		"title": title,
		"url": url,
		"summary": title,
		"timestamp": int(Time.get_unix_time_from_system()),
		"page_snapshot": page.duplicate(true),
	}
	_entries.append(entry)
	_save_to_disk()
	return entry.duplicate(true)


func get_run_state() -> Dictionary:
	return {
		"history_entries": _entries.duplicate(true),
		"history_counter": _counter,
	}


func load_run_state(data: Dictionary) -> void:
	_entries.clear()
	_assign_entries(data.get("history_entries", []))
	_counter = int(data.get("history_counter", _entries.size()))


func clear(clear_persistent_history: bool) -> void:
	if not clear_persistent_history:
		return
	_entries.clear()
	_counter = 0
	_save_to_disk()


func _assign_entries(value: Variant) -> void:
	if not value is Array:
		return
	for entry_value: Variant in value:
		if entry_value is Dictionary:
			_entries.append(entry_value.duplicate(true))


func _save_to_disk() -> void:
	if not persist_history:
		return
	var directory: String = _history_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(_history_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"next_id": _counter, "entries": _entries}, "  "))
	file.close()
