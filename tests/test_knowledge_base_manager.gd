extends Node


func _ready() -> void:
	var manager: Node = get_node_or_null("/root/KnowledgeBaseManager")
	_assert(manager != null, "KnowledgeBaseManager is available")
	if manager == null:
		return

	var original_documents: Array = manager.documents.duplicate(true)
	manager.documents.clear()
	manager.upsert_document(
		"world_rule",
		"世界规则",
		"门只会在钟声结束后打开。",
		"world",
		["door", "clock"],
	)
	_assert(manager.get_documents().size() == 1, "document can be inserted")
	_assert(manager.get_documents("world").size() == 1, "category filter works")
	_assert(manager.get_documents("", ["clock"]).size() == 1, "tag filter works")
	_assert(str(manager.get_document("world_rule").get("title", "")) == "世界规则", "document lookup works")
	_assert(manager.delete_document("world_rule"), "document can be deleted")
	manager.documents.clear()
	for document in original_documents:
		manager.documents.append(document)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		push_error("[FAIL] %s" % message)
