extends Node
## 游戏本体的轻量剧情知识库。运行时只读，编辑器中可持久化。

signal data_loaded()
signal data_saved()
signal document_changed(doc_id: String)

const KNOWLEDGE_BASE_FILE: String = "res://resources/avg/knowledge_base.json"
const VALID_CATEGORIES: Array[String] = ["world", "characters", "story", "notes"]

var documents: Array[Dictionary] = []
var _id_counter: int = 0


func _ready() -> void:
	load_data()


func get_documents(category: String = "", tags: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for doc in documents:
		if not category.is_empty() and str(doc.get("category", "")) != category:
			continue
		if not tags.is_empty() and not _has_any_tag(doc.get("tags", []), tags):
			continue
		result.append(doc.duplicate(true))
	return result


func get_document(doc_id: String) -> Dictionary:
	for doc in documents:
		if str(doc.get("doc_id", "")) == doc_id:
			return doc.duplicate(true)
	return {}


func get_categories() -> Array[String]:
	var result: Array[String] = []
	for doc in documents:
		var category := str(doc.get("category", ""))
		if not category.is_empty() and not result.has(category):
			result.append(category)
	return result


func upsert_document(doc_id: String, title: String, content: String, category: String,
		tags: Array = [], author: String = "", metadata: Dictionary = {}) -> void:
	var normalized_id := doc_id.strip_edges()
	if normalized_id.is_empty():
		return
	var updated := {
		"doc_id": normalized_id,
		"title": title.strip_edges(),
		"content": content,
		"category": _normalize_category(category),
		"tags": _normalize_tags(tags),
		"author": author.strip_edges(),
		"updated_at": Time.get_datetime_string_from_system(true),
	}
	for key in metadata:
		updated[key] = metadata[key]
	for index in range(documents.size()):
		if str(documents[index].get("doc_id", "")) == normalized_id:
			documents[index] = updated
			document_changed.emit(normalized_id)
			return
	documents.append(updated)
	document_changed.emit(normalized_id)


func delete_document(doc_id: String) -> bool:
	for index in range(documents.size()):
		if str(documents[index].get("doc_id", "")) == doc_id:
			documents.remove_at(index)
			document_changed.emit(doc_id)
			return true
	return false


func generate_doc_id(category: String) -> String:
	_id_counter += 1
	return "%s_%d_%d" % [_normalize_category(category), Time.get_ticks_msec(), _id_counter]


func load_data() -> void:
	documents.clear()
	if not FileAccess.file_exists(KNOWLEDGE_BASE_FILE):
		data_loaded.emit()
		return
	var file := FileAccess.open(KNOWLEDGE_BASE_FILE, FileAccess.READ)
	if file == null:
		data_loaded.emit()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		for raw_doc in parsed.get("documents", []):
			if raw_doc is Dictionary:
				documents.append(_normalize_document(raw_doc))
	data_loaded.emit()


func save_data() -> Error:
	if not OS.has_feature("editor"):
		return ERR_CANT_CREATE
	var file := FileAccess.open(KNOWLEDGE_BASE_FILE, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"documents": documents}, "  "))
	file.close()
	data_saved.emit()
	return OK


func _normalize_document(raw_doc: Dictionary) -> Dictionary:
	return {
		"doc_id": str(raw_doc.get("doc_id", "")).strip_edges(),
		"title": str(raw_doc.get("title", "")).strip_edges(),
		"content": str(raw_doc.get("content", "")),
		"category": _normalize_category(str(raw_doc.get("category", ""))),
		"tags": _normalize_tags(raw_doc.get("tags", [])),
		"author": str(raw_doc.get("author", "")).strip_edges(),
		"updated_at": str(raw_doc.get("updated_at", "")).strip_edges(),
	}


func _normalize_category(category: String) -> String:
	var normalized := category.strip_edges().to_lower()
	return normalized if VALID_CATEGORIES.has(normalized) else "notes"


func _normalize_tags(raw_tags: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_tag in raw_tags:
		var tag := str(raw_tag).strip_edges()
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	return result


func _has_any_tag(raw_doc_tags: Array, wanted_tags: Array) -> bool:
	for tag in wanted_tags:
		if raw_doc_tags.has(tag):
			return true
	return false
