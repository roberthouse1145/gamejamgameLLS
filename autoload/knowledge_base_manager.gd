extends Node
## KnowledgeBaseManager Autoload
## 统一文档模型的知识库管理器。
## 所有内容以自由文本文档形式存储，按 category 分类。
## 存储路径: <project_path>/knowledge_base/docs/{doc_id}.json（每文档独立文件）
## 索引文件: <project_path>/knowledge_base/index.json（元数据，不含 content）

signal data_loaded()
signal data_saved()
signal document_changed(doc_id: String)

## 有效的文档分类
const VALID_CATEGORIES: Array[String] = ["world", "characters", "story", "notes"]
const VALID_DOC_KINDS: Array[String] = [
	"canonical",
	"brief",
	"open_questions",
	"backbone",
	"decision_log",
	"reference",
]
const VALID_DOC_STATES: Array[String] = ["draft", "confirmed", "superseded"]

const KB_DIR_NAME = "knowledge_base"
const DOCS_DIR_NAME = "docs"
const INDEX_FILE_NAME = "index.json"
const LEGACY_FILE_NAME = "knowledge_base.json"

## 文档列表 — 每个元素是 Dictionary:
## { "doc_id": String, "title": String, "content": String,
##   "category": String, "tags": Array[String], "author": String,
##   "doc_kind": String, "state": String,
##   "updated_at": String,
##   "position_x": float, "position_y": float }  ← UI 卡片位置（可选）
var documents: Array[Dictionary] = []

var _storage_manager: Node = null
var _id_counter: int = 0

func _ready() -> void:
	call_deferred("_init_manager")

func _init_manager() -> void:
	_storage_manager = get_node_or_null("/root/StorageManager")
	if _storage_manager:
		_storage_manager.current_project_changed.connect(_on_project_changed)
		if _storage_manager.current_project_path != "":
			load_data()

func _on_project_changed(_project: Resource) -> void:
	load_data()

# =============================================================================
# Query API
# =============================================================================

## 按分类和标签查询文档。所有参数可选，省略则返回全部。
func get_documents(category: String = "", tags: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for doc in documents:
		if not category.is_empty() and doc.get("category", "") != category:
			continue
		if tags.size() > 0:
			var doc_tags: Array = doc.get("tags", [])
			var match_found := false
			for t in tags:
				if t in doc_tags:
					match_found = true
					break
			if not match_found:
				continue
		result.append(doc)
	return result

## 按 doc_id 获取单个文档。未找到返回空 Dictionary。
func get_document(doc_id: String) -> Dictionary:
	for doc in documents:
		if doc.get("doc_id", "") == doc_id:
			return doc
	return {}

## 获取当前所有已使用的分类列表
func get_categories() -> Array[String]:
	var cats: Array[String] = []
	for doc in documents:
		var cat: String = doc.get("category", "")
		if not cat.is_empty() and cat not in cats:
			cats.append(cat)
	return cats

# =============================================================================
# Write API
# =============================================================================

## 创建或更新文档。doc_id 已存在则更新，不存在则创建。
func upsert_document(doc_id: String, title: String, content: String,
		category: String, tags: Array = [], author: String = "", metadata: Dictionary = {}) -> void:
	var now: String = Time.get_datetime_string_from_system(true)
	for i in range(documents.size()):
		if documents[i].get("doc_id", "") == doc_id:
			var updated_doc: Dictionary = documents[i].duplicate(true)
			updated_doc["title"] = title
			updated_doc["content"] = content
			updated_doc["category"] = category
			if tags.size() > 0:
				updated_doc["tags"] = tags
			if not author.is_empty():
				updated_doc["author"] = author
			for key in metadata:
				updated_doc[key] = metadata[key]
			updated_doc["updated_at"] = now
			documents[i] = _normalize_document(updated_doc)
			document_changed.emit(doc_id)
			return
	# 创建新文档
	var doc: Dictionary = {
		"doc_id": doc_id,
		"title": title,
		"content": content,
		"category": category,
		"tags": tags,
		"author": author if not author.is_empty() else "player",
		"updated_at": now,
		"position_x": randf_range(50.0, 400.0),
		"position_y": randf_range(50.0, 400.0),
	}
	for key in metadata:
		doc[key] = metadata[key]
	documents.append(_normalize_document(doc))
	document_changed.emit(doc_id)

## 删除文档
func delete_document(doc_id: String) -> bool:
	for i in range(documents.size()):
		if documents[i].get("doc_id", "") == doc_id:
			documents.remove_at(i)
			document_changed.emit(doc_id)
			return true
	return false

## 生成唯一 doc_id（基于分类前缀 + 时间戳）
func generate_doc_id(category: String) -> String:
	category = _normalize_category(category)
	_id_counter += 1
	return "%s_%s_%d" % [category, str(Time.get_ticks_msec()), _id_counter]

# =============================================================================
# Persistence — 每文档独立文件
# =============================================================================

func _get_kb_dir() -> String:
	return _storage_manager.current_project_path.path_join(KB_DIR_NAME)

func _get_docs_dir() -> String:
	return _get_kb_dir().path_join(DOCS_DIR_NAME)

func _get_index_path() -> String:
	return _get_kb_dir().path_join(INDEX_FILE_NAME)

func _get_legacy_path() -> String:
	return _get_kb_dir().path_join(LEGACY_FILE_NAME)

func load_data() -> void:
	if _storage_manager == null or _storage_manager.current_project_path.is_empty():
		return

	documents = []
	var docs_dir: String = _get_docs_dir()
	var legacy_path: String = _get_legacy_path()

	# 优先加载新格式（docs/ 目录）
	if DirAccess.dir_exists_absolute(docs_dir):
		_load_from_docs_dir(docs_dir)
	# 回退到旧单文件格式
	elif FileAccess.file_exists(legacy_path):
		_load_from_legacy_file(legacy_path)
	else:
		print("[KnowledgeBaseManager] No knowledge base found. Starting fresh.")

	data_loaded.emit()

func _load_from_docs_dir(docs_dir: String) -> void:
	var dir := DirAccess.open(docs_dir)
	if dir == null:
		push_warning("[KnowledgeBaseManager] Cannot open docs dir: %s" % docs_dir)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var file_path: String = docs_dir.path_join(file_name)
			var doc: Dictionary = _read_json_file(file_path)
			if not doc.is_empty() and doc.has("doc_id"):
				documents.append(_normalize_document(doc))
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[KnowledgeBaseManager] Loaded %d documents from %s" % [documents.size(), docs_dir])

func _load_from_legacy_file(file_path: String) -> void:
	print("[KnowledgeBaseManager] Found legacy single-file KB, migrating...")
	var data: Dictionary = _read_json_file(file_path)
	if data.is_empty():
		return

	if data.has("documents"):
		for d in data["documents"]:
			if d is Dictionary:
				documents.append(_normalize_document(d))
	else:
		_migrate_legacy(data)

	# 迁移：保存为新格式，保留旧文件作为备份
	save_data()
	# 重命名旧文件为 .bak
	var bak_path: String = file_path + ".bak"
	var da := DirAccess.open(file_path.get_base_dir())
	if da:
		da.rename(file_path, bak_path)
		print("[KnowledgeBaseManager] Legacy file backed up to %s" % bak_path)

func save_data() -> Error:
	if _storage_manager == null or _storage_manager.current_project_path.is_empty():
		return ERR_UNCONFIGURED

	if _storage_manager.has_method("ensure_writable_project_root"):
		var writable_err: Error = _storage_manager.ensure_writable_project_root()
		if writable_err != OK:
			push_error("[KnowledgeBaseManager] Failed to switch project to writable root: %s" % error_string(writable_err))
			return writable_err

	var docs_dir: String = _get_docs_dir()
	# 确保 docs/ 目录存在
	if not DirAccess.dir_exists_absolute(docs_dir):
		var err := DirAccess.make_dir_recursive_absolute(docs_dir)
		if err != OK:
			push_error("[KnowledgeBaseManager] Failed to create directory: %s" % docs_dir)
			return err

	# 收集当前有效的 doc_id（用于清理已删除的文档文件）
	var active_ids: Dictionary = {}
	for i in range(documents.size()):
		var doc := _normalize_document(documents[i])
		documents[i] = doc
		var doc_id: String = doc.get("doc_id", "")
		if doc_id.is_empty():
			continue
		active_ids[doc_id] = true
		_write_doc_file(docs_dir, doc)

	# 清理已删除文档的文件
	_cleanup_deleted_docs(docs_dir, active_ids)

	# 写 index.json（元数据，不含 content）
	_write_index()

	data_saved.emit()
	print("[KnowledgeBaseManager] Saved %d documents to %s" % [documents.size(), docs_dir])
	return OK

func _write_doc_file(docs_dir: String, doc: Dictionary) -> void:
	var doc_id: String = doc.get("doc_id", "")
	var file_name: String = _sanitize_filename(doc_id) + ".json"
	var file_path: String = docs_dir.path_join(file_name)
	var tmp_path: String = file_path + ".tmp"

	# 原子写入：先写 .tmp，成功后重命名
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[KnowledgeBaseManager] Failed to write: %s" % tmp_path)
		return
	file.store_string(JSON.stringify(doc, "\t"))
	file.close()

	var da := DirAccess.open(docs_dir)
	if da:
		# 如果目标文件已存在，先删除（Godot 的 rename 不会自动覆盖）
		if FileAccess.file_exists(file_path):
			da.remove(file_name)
		da.rename(tmp_path, file_path)

func _write_index() -> void:
	var index_path: String = _get_index_path()
	var entries: Array[Dictionary] = []
	for doc in documents:
		var normalized_doc := _normalize_document(doc)
		entries.append({
			"doc_id": normalized_doc.get("doc_id", ""),
			"title": normalized_doc.get("title", ""),
			"category": normalized_doc.get("category", ""),
			"tags": normalized_doc.get("tags", []),
			"author": normalized_doc.get("author", ""),
			"doc_kind": normalized_doc.get("doc_kind", "canonical"),
			"state": normalized_doc.get("state", "confirmed"),
			"updated_at": normalized_doc.get("updated_at", ""),
			"position_x": normalized_doc.get("position_x", 0.0),
			"position_y": normalized_doc.get("position_y", 0.0),
		})
	var payload: Dictionary = {"documents": entries}

	var tmp_path: String = index_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload, "\t"))
		file.close()
		var da := DirAccess.open(index_path.get_base_dir())
		if da:
			if FileAccess.file_exists(index_path):
				da.remove(INDEX_FILE_NAME)
			da.rename(tmp_path, index_path)

func _cleanup_deleted_docs(docs_dir: String, active_ids: Dictionary) -> void:
	var dir := DirAccess.open(docs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var doc_id: String = file_name.get_basename()
			if not active_ids.has(doc_id):
				dir.remove(file_name)
				print("[KnowledgeBaseManager] Cleaned up deleted doc: %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

## 读取单个 JSON 文件，返回 Dictionary。失败返回空 Dictionary。
func _read_json_file(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var json_str := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_str) == OK and typeof(json.data) == TYPE_DICTIONARY:
		return json.data
	push_warning("[KnowledgeBaseManager] Failed to parse: %s" % file_path)
	return {}

## 将 doc_id 转为安全文件名（替换非法字符）
func _sanitize_filename(doc_id: String) -> String:
	var safe: String = doc_id
	for ch in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		safe = safe.replace(ch, "_")
	return safe


func _normalize_document(raw_doc: Dictionary) -> Dictionary:
	var doc: Dictionary = raw_doc.duplicate(true)
	doc["category"] = _normalize_category(str(doc.get("category", "")))

	var doc_kind: String = str(doc.get("doc_kind", "")).strip_edges()
	if doc_kind.is_empty():
		doc_kind = _infer_doc_kind_from_doc(doc)
	elif doc_kind not in VALID_DOC_KINDS:
		doc_kind = "canonical"
	doc["doc_kind"] = doc_kind

	var state: String = str(doc.get("state", "")).strip_edges()
	if state.is_empty():
		state = _infer_doc_state_from_doc(doc)
	elif state not in VALID_DOC_STATES:
		state = "confirmed"
	doc["state"] = state

	if not doc.has("tags") or not (doc.get("tags", []) is Array):
		doc["tags"] = []
	if str(doc.get("author", "")).strip_edges().is_empty():
		doc["author"] = "player"
	if not doc.has("updated_at"):
		doc["updated_at"] = Time.get_datetime_string_from_system(true)
	if not doc.has("position_x"):
		doc["position_x"] = randf_range(50.0, 400.0)
	if not doc.has("position_y"):
		doc["position_y"] = randf_range(50.0, 400.0)

	return doc


func _normalize_category(category: String) -> String:
	var normalized := category.strip_edges()
	if normalized.is_empty():
		return "notes"
	if VALID_CATEGORIES.has(normalized):
		return normalized
	if normalized == "creative_brief":
		return "notes"
	return "notes"


func _infer_doc_kind_from_doc(doc: Dictionary) -> String:
	var doc_id: String = str(doc.get("doc_id", "")).strip_edges()
	var raw_category: String = str(doc.get("category", "")).strip_edges()
	if raw_category == "creative_brief" or doc_id == "creative_brief":
		return "brief"
	match doc_id:
		"open_design_questions":
			return "open_questions"
		"seed_development_backbone":
			return "backbone"
		_:
			return "canonical"


func _infer_doc_state_from_doc(doc: Dictionary) -> String:
	var content: String = str(doc.get("content", "")).strip_edges()
	if content.is_empty():
		return "draft"
	return "confirmed"

# =============================================================================
# Legacy Migration — 旧格式 → 统一文档模型
# =============================================================================

func _migrate_legacy(data: Dictionary) -> void:
	print("[KnowledgeBaseManager] Migrating legacy KB format...")
	var now: String = Time.get_datetime_string_from_system(true)

	# world (game_title + synopsis → 一篇 world 文档)
	var game_title: String = data.get("game_title", "")
	var synopsis: String = data.get("synopsis", "")
	if not game_title.is_empty() or not synopsis.is_empty():
		documents.append(_normalize_document({
			"doc_id": "world_core",
			"title": game_title if not game_title.is_empty() else "核心策划案",
			"content": synopsis,
			"category": "world",
			"tags": ["世界观"],
			"author": "player",
			"updated_at": now,
			"position_x": 100.0,
			"position_y": 100.0,
		}))

	# characters → 每个角色一篇 characters 文档
	var chars: Array = data.get("characters", [])
	for c in chars:
		var cid: String = c.get("character_id", generate_doc_id("characters"))
		documents.append(_normalize_document({
			"doc_id": cid,
			"title": c.get("full_name", "Unknown"),
			"content": c.get("personality", c.get("notes", "")),
			"category": "characters",
			"tags": [],
			"author": c.get("author", "player"),
			"updated_at": now,
			"position_x": c.get("position_x", randf_range(50.0, 400.0)),
			"position_y": c.get("position_y", randf_range(50.0, 400.0)),
		}))

	# beats → 每个节拍一篇 story 文档
	var beats: Array = data.get("beats", [])
	for b in beats:
		var bid: String = b.get("beat_id", generate_doc_id("story"))
		documents.append(_normalize_document({
			"doc_id": bid,
			"title": b.get("title", "Untitled"),
			"content": b.get("content", ""),
			"category": "story",
			"tags": [],
			"author": b.get("author", "player"),
			"updated_at": now,
			"position_x": b.get("position_x", randf_range(50.0, 400.0)),
			"position_y": b.get("position_y", randf_range(50.0, 400.0)),
		}))

	# 迁移后自动保存新格式
	print("[KnowledgeBaseManager] Migration complete: %d documents." % documents.size())
