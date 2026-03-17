extends Node
## LLMKnowledgeBaseManager Autoload
## 独立管理"LLM定稿库"——玩家与林夏对齐后由系统写入的快照版本。
## Worker LLM 执行任务时只读取此库，完全不看玩家的灵感本 (KnowledgeBaseManager)。
##
## 存储路径: user://projects/<name>/llm_knowledge_base/llm_kb.json
## 结构: { "world": {...}, "characters": {...id->entry...}, "beats": {...id->entry...} }

signal data_loaded()
signal entry_confirmed(category: String, entry_id: String)

const LLM_KB_DIR := "llm_knowledge_base"
const LLM_KB_FILE := "llm_kb.json"

## The confirmed snapshot store.
## Format mirrors KnowledgeBaseData but is a plain Dictionary to keep things lightweight.
## {
##   "world": { "game_title": "...", "synopsis": "..." },
##   "characters": { "char_001": {...}, "char_002": {...} },
##   "beats": { "beat_001": {...}, "beat_002": {...} }
## }
var _data: Dictionary = {
	"world": {},
	"characters": {},
	"beats": {}
}

var _storage_manager: Node = null
var _current_file_path: String = ""

func _ready() -> void:
	call_deferred("_init_manager")

func _init_manager() -> void:
	_storage_manager = get_node_or_null("/root/StorageManager")
	if _storage_manager:
		_storage_manager.current_project_changed.connect(_on_project_changed)
		if _storage_manager.current_project_path != "":
			_load()

func _on_project_changed(_project: Resource) -> void:
	_load()

# =============================================================================
# Public API
# =============================================================================

## 快照一条 Player KB 条目到 LLM KB.
## category: "world" | "characters" | "beats"
## entry_id: For world, ignored. For characters/beats, the ID.
## data: The dictionary snapshot to store.
func snapshot_entry(category: String, entry_id: String, data: Dictionary) -> bool:
	match category:
		"world":
			_data["world"] = data.duplicate(true)
		"characters":
			if entry_id.is_empty():
				push_error("[LLMKnowledgeBaseManager] snapshot_entry: entry_id required for characters")
				return false
			_data["characters"][entry_id] = data.duplicate(true)
		"beats":
			if entry_id.is_empty():
				push_error("[LLMKnowledgeBaseManager] snapshot_entry: entry_id required for beats")
				return false
			_data["beats"][entry_id] = data.duplicate(true)
		_:
			push_error("[LLMKnowledgeBaseManager] Unknown category: %s" % category)
			return false

	print("[LLMKnowledgeBaseManager] Confirmed: %s/%s" % [category, entry_id])
	_save()
	entry_confirmed.emit(category, entry_id)
	return true


## 读取一条 LLM KB 条目.
## 返回 dict 或 null.
func get_entry(category: String, entry_id: String) -> Variant:
	match category:
		"world": return _data["world"].duplicate(true)
		"characters": return _data["characters"].get(entry_id, null)
		"beats": return _data["beats"].get(entry_id, null)
	return null


## 读取某分类下所有条目 (用于 kb_read source=llm).
## 返回 Array[Dictionary] for characters/beats, raw dict for world.
func get_all(category: String) -> Variant:
	match category:
		"world": return _data["world"].duplicate(true)
		"characters": return _data["characters"].values().map(func(v): return v.duplicate(true))
		"beats": return _data["beats"].values().map(func(v): return v.duplicate(true))
	return []


## 清空某分类 (例如玩家想完全抛弃旧定稿重新来过)
func clear_category(category: String) -> void:
	if category in _data:
		_data[category] = {} if category != "world" else {}
		_save()
		print("[LLMKnowledgeBaseManager] Cleared category: %s" % category)


## 列出某分类所有 ID (characters / beats)
func list_ids(category: String) -> Array[String]:
	var ids: Array[String] = []
	if category in _data and typeof(_data[category]) == TYPE_DICTIONARY:
		for key in _data[category]:
			ids.append(key)
	return ids

# =============================================================================
# Persistence
# =============================================================================

func _save() -> void:
	if _current_file_path.is_empty():
		return
	var dir_path = _current_file_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file = FileAccess.open(_current_file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_data, "\t"))
		file.close()
	else:
		push_error("[LLMKnowledgeBaseManager] Failed to save: %s" % _current_file_path)


func _load() -> void:
	if _storage_manager == null or _storage_manager.current_project_path.is_empty():
		return
	var dir_path = _storage_manager.current_project_path.path_join(LLM_KB_DIR)
	_current_file_path = dir_path.path_join(LLM_KB_FILE)

	# Reset to defaults
	_data = {"world": {}, "characters": {}, "beats": {}}

	var file = FileAccess.open(_current_file_path, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		file.close()
		var json = JSON.new()
		if json.parse(json_str) == OK and typeof(json.data) == TYPE_DICTIONARY:
			for key in ["world", "characters", "beats"]:
				if json.data.has(key):
					_data[key] = json.data[key]
			print("[LLMKnowledgeBaseManager] Loaded from: %s" % _current_file_path)
		else:
			push_warning("[LLMKnowledgeBaseManager] Failed to parse JSON, using empty store.")
	else:
		print("[LLMKnowledgeBaseManager] No LLM KB found, starting fresh.")

	data_loaded.emit()
