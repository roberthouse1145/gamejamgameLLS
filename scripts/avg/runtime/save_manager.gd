class_name AVGSaveManager extends RefCounted
## 存档/读档管理器
## 将游戏状态保存到 user://saves/<project_name>/ 目录。
## 每个存档槽保存为一个 JSON 文件。

const SAVE_DIR_BASE: String = "user://saves/"

## 存档槽数据结构
## {
##   "slot_index": int,
##   "timestamp": String,
##   "scene_id": String,
##   "scene_name": String,
##   "command_index": int,
##   "variables": Dictionary,
##   "history": Array,
##   "speaker": String,
##   "text": String,
##   "background_path": String,
## }

## 项目名称（用于存档目录）
var _project_name: String = ""


## 设置项目名称
func set_project_name(p_name: String) -> void:
	_project_name = p_name.to_snake_case().replace(" ", "_")
	_ensure_save_dir()


## 获取存档目录路径
func _get_save_dir() -> String:
	return SAVE_DIR_BASE + _project_name + "/"


## 确保存档目录存在
func _ensure_save_dir() -> void:
	var dir_path: String = _get_save_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## 保存游戏到指定槽位
func save_game(slot_index: int, game_state: Dictionary) -> Error:
	if _project_name.is_empty():
		push_error("AVGSaveManager: project name not set")
		return ERR_UNCONFIGURED

	_ensure_save_dir()
	var save_data: Dictionary = game_state.duplicate()
	save_data["slot_index"] = slot_index
	save_data["timestamp"] = Time.get_datetime_string_from_system()

	var file_path: String = _get_save_dir() + "save_%03d.json" % slot_index
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("AVGSaveManager: Cannot open file for writing: %s" % file_path)
		return FileAccess.get_open_error()

	var json_str: String = JSON.stringify(save_data, "\t")
	file.store_string(json_str)
	file.close()
	print("[AVGSaveManager] Saved to slot %d: %s" % [slot_index, file_path])
	return OK


## 读取指定槽位的存档
func load_game(slot_index: int) -> Dictionary:
	var file_path: String = _get_save_dir() + "save_%03d.json" % slot_index
	if not FileAccess.file_exists(file_path):
		return {}

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("AVGSaveManager: Cannot open file for reading: %s" % file_path)
		return {}

	var json_str: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(json_str)
	if err != OK:
		push_error("AVGSaveManager: JSON parse error in %s: %s" % [file_path, json.get_error_message()])
		return {}

	return json.data as Dictionary


## 删除指定槽位的存档
func delete_save(slot_index: int) -> Error:
	var file_path: String = _get_save_dir() + "save_%03d.json" % slot_index
	if not FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(file_path)


## 获取所有存档槽的摘要信息
## 返回 {slot_index: {timestamp, scene_name, speaker, text}} 或空
func get_all_slot_summaries(max_slots: int = 12) -> Dictionary:
	var result: Dictionary = {}
	for i in range(max_slots):
		var data: Dictionary = load_game(i)
		if data.is_empty():
			continue
		result[i] = {
			"timestamp": data.get("timestamp", ""),
			"scene_name": data.get("scene_name", ""),
			"speaker": data.get("speaker", ""),
			"text": data.get("text", ""),
		}
	return result


## 检查槽位是否有存档
func has_save(slot_index: int) -> bool:
	var file_path: String = _get_save_dir() + "save_%03d.json" % slot_index
	return FileAccess.file_exists(file_path)
