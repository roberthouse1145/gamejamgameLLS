class_name AVGKnowledgeTools extends RefCounted
## 为动态 AVG 与角色对话提供只读剧情知识查询。


static func register_read_only(ai_service: Node) -> void:
	ai_service.register_tool("kb_read", "读取游戏的世界观、角色、故事与备注文档。", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "story", "notes"], "description": "可选的文档分类；省略时只列出文档标题。"},
			"doc_id": {"type": "string", "description": "可选的文档 ID；提供后返回该文档全文。"},
			"tags": {"type": "array", "items": {"type": "string"}, "description": "可选标签，返回包含任一标签的文档。"}
		}
	}, func(args: Dictionary) -> Variant: return _kb_read(args), {
		"fields": ["success", "data", "note", "error"]
	})


static func build_index_context() -> String:
	var response := _kb_read({})
	if not bool(response.get("success", false)):
		return ""
	var docs: Array = response.get("data", [])
	if docs.is_empty():
		return ""
	var lines: PackedStringArray = ["## 剧情设定索引"]
	for raw_doc in docs:
		if not raw_doc is Dictionary:
			continue
		var doc: Dictionary = raw_doc
		var doc_id := str(doc.get("doc_id", "")).strip_edges()
		var title := str(doc.get("title", doc_id)).strip_edges()
		var category := str(doc.get("category", "")).strip_edges()
		if doc_id.is_empty():
			continue
		lines.append("- %s | %s | %s" % [doc_id, category, title])
	return "\n".join(lines)


static func _get_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/KnowledgeBaseManager")


static func _kb_read(args: Dictionary) -> Dictionary:
	var manager := _get_manager()
	if manager == null:
		return {"success": false, "error": "KnowledgeBaseManager not available."}

	var doc_id: String = str(args.get("doc_id", "")).strip_edges()
	var category: String = str(args.get("category", "")).strip_edges()
	var tags: Array = args.get("tags", [])
	if not doc_id.is_empty():
		var doc: Dictionary = manager.get_document(doc_id)
		if doc.is_empty():
			return {"success": false, "error": "Document not found: %s" % doc_id}
		return {"success": true, "data": _sanitize_doc(doc, true)}

	var docs: Array = manager.get_documents(category, tags)
	var include_content: bool = not category.is_empty()
	var result: Array = []
	for doc in docs:
		if doc is Dictionary:
			result.append(_sanitize_doc(doc, include_content))
	var response: Dictionary = {"success": true, "data": result}
	if not include_content:
		response["note"] = "当前只列出标题；使用 doc_id 或 category 可读取全文。"
	return response


static func _sanitize_doc(doc: Dictionary, include_content: bool) -> Dictionary:
	var result: Dictionary = {
		"doc_id": doc.get("doc_id", ""),
		"title": doc.get("title", ""),
		"category": doc.get("category", ""),
		"doc_kind": doc.get("doc_kind", "canonical"),
		"state": doc.get("state", "confirmed"),
	}
	var tags: Array = doc.get("tags", [])
	if not tags.is_empty():
		result["tags"] = tags
	if include_content:
		result["content"] = doc.get("content", "")
	return result
