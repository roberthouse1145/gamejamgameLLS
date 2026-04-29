class_name AVGDevKBTools extends RefCounted

## LLM 工具：统一文档模型的知识库读写

static func register_read_only(ai_service: Node) -> void:
	ai_service.register_tool("kb_read", "Read documents from the Game Design Knowledge Base. Categories: world, characters, story, notes.", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "Document category to filter by. Omit to list all documents (titles only)."},
			"doc_id": {"type": "string", "description": "Optional: fetch a specific document by ID. Returns full content."},
			"tags": {"type": "array", "items": {"type": "string"}, "description": "Optional: filter documents containing at least one of these tags."}
		}
	}, func(args: Dictionary) -> Variant: return _kb_read(args), {
		"fields": ["success", "data", "note", "error"]
	})


static func register_all(ai_service: Node) -> void:
	# Read
	ai_service.register_tool("kb_read", "Read documents from the Game Design Knowledge Base. Categories: world, characters, story, notes.", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "Document category to filter by. Omit to list all documents (titles only)."},
			"doc_id": {"type": "string", "description": "Optional: fetch a specific document by ID. Returns full content."},
			"tags": {"type": "array", "items": {"type": "string"}, "description": "Optional: filter documents containing at least one of these tags."}
		}
	}, func(args: Dictionary) -> Variant: return _kb_read(args), {
		"fields": ["success", "data", "note", "error"]
	})

	# Write
	ai_service.register_tool("kb_write", "Create or update a document in the Knowledge Base. If doc_id exists, updates it; otherwise creates new.", {
		"type": "object",
		"properties": {
			"doc_id": {"type": "string", "description": "Document ID. Leave empty to auto-generate a new ID."},
			"title": {"type": "string", "description": "Document title (e.g. character name, chapter title, concept name)."},
			"content": {"type": "string", "description": "Free-form text content of the document."},
			"category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "Document category."},
			"tags": {"type": "array", "items": {"type": "string"}, "description": "Optional tags for this document."},
			"doc_kind": {"type": "string", "enum": ["canonical", "brief", "open_questions", "backbone", "decision_log", "reference"], "description": "Optional document purpose metadata."},
			"state": {"type": "string", "enum": ["draft", "confirmed", "superseded"], "description": "Optional lifecycle state metadata."}
		},
		"required": ["title", "content", "category"]
	}, func(args: Dictionary) -> Variant: return _kb_write(args), {
		"fields": ["success", "doc_id", "error"]
	})

	# Delete
	ai_service.register_tool("kb_delete", "Delete a document from the Knowledge Base by its doc_id.", {
		"type": "object",
		"properties": {
			"doc_id": {"type": "string", "description": "The ID of the document to delete."}
		},
		"required": ["doc_id"]
	}, func(args: Dictionary) -> Variant: return _kb_delete(args), {
		"fields": ["success", "error"]
	})


static func _get_manager() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("/root/KnowledgeBaseManager")


static func _kb_read(args: Dictionary) -> Dictionary:
	var kbm := _get_manager()
	if kbm == null:
		return {"success": false, "error": "KnowledgeBaseManager not available."}

	var doc_id: String = args.get("doc_id", "")
	var category: String = args.get("category", "")
	var tags: Array = args.get("tags", [])

	# 按 doc_id 精确查询
	if not doc_id.is_empty():
		var doc: Dictionary = kbm.get_document(doc_id)
		if doc.is_empty():
			return {"success": false, "error": "Document not found: %s" % doc_id}
		return {"success": true, "data": _sanitize_doc(doc, true)}

	# 按分类/标签查询
	var docs: Array = kbm.get_documents(category, tags)

	# 如果没指定分类，只返回标题列表（防 token 爆炸）
	if category.is_empty():
		var summaries: Array = []
		for doc in docs:
			summaries.append(_sanitize_doc(doc, false))
		return {"success": true, "data": summaries, "note": "Showing titles only. Use doc_id or category to get full content."}

	# 指定了分类，返回完整内容
	var result: Array = []
	for doc in docs:
		result.append(_sanitize_doc(doc, true))
	return {"success": true, "data": result}


static func _kb_write(args: Dictionary) -> Dictionary:
	var kbm := _get_manager()
	if kbm == null:
		return {"success": false, "error": "KnowledgeBaseManager not available."}

	var doc_id: String = args.get("doc_id", "")
	var title: String = args.get("title", "")
	var content: String = args.get("content", "")
	var category: String = args.get("category", "")
	var tags: Array = args.get("tags", [])
	var metadata: Dictionary = {}
	for key in ["doc_kind", "state"]:
		if args.has(key):
			metadata[key] = args[key]

	if title.is_empty() or content.is_empty() or category.is_empty():
		return {"success": false, "error": "title, content, and category are required."}

	# 自动生成 doc_id
	if doc_id.is_empty():
		doc_id = kbm.generate_doc_id(category)

	kbm.upsert_document(doc_id, title, content, category, tags, "lin_xia", metadata)
	kbm.save_data()
	return {"success": true, "doc_id": doc_id}


static func _kb_delete(args: Dictionary) -> Dictionary:
	var kbm := _get_manager()
	if kbm == null:
		return {"success": false, "error": "KnowledgeBaseManager not available."}

	var doc_id: String = args.get("doc_id", "")
	if doc_id.is_empty():
		return {"success": false, "error": "doc_id is required."}

	var removed: bool = kbm.delete_document(doc_id)
	if removed:
		kbm.save_data()
		return {"success": true}
	return {"success": false, "error": "Document not found: %s" % doc_id}


## 清理文档，移除 UI 专属字段
static func _sanitize_doc(doc: Dictionary, include_content: bool) -> Dictionary:
	var result: Dictionary = {
		"doc_id": doc.get("doc_id", ""),
		"title": doc.get("title", ""),
		"category": doc.get("category", ""),
		"doc_kind": doc.get("doc_kind", "canonical"),
		"state": doc.get("state", "confirmed"),
	}
	var tags: Array = doc.get("tags", [])
	if tags.size() > 0:
		result["tags"] = tags
	if include_content:
		result["content"] = doc.get("content", "")
	return result
