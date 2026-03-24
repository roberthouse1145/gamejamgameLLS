class_name ActivityLockUtils
extends RefCounted

const DEFAULT_EVENT_BLOCK_REASON: String = "当前有事件正在进行，请先等待反馈。"
const DEFAULT_CHAT_BLOCK_REASON: String = "当前有对话事件正在等待回复，请先等待反馈。"

static var _busy_sources: Dictionary = {}


static func register_busy_source(
		source_id: String,
		node: Node,
		busy_method: String = "has_any_pending_sessions",
		reason: String = DEFAULT_EVENT_BLOCK_REASON) -> void:
	var normalized_id := source_id.strip_edges()
	if normalized_id.is_empty() or node == null or busy_method.strip_edges().is_empty():
		return
	_busy_sources[normalized_id] = {
		"node_ref": weakref(node),
		"busy_method": busy_method,
		"reason": reason if not reason.is_empty() else DEFAULT_EVENT_BLOCK_REASON,
	}


static func unregister_busy_source(source_id: String) -> void:
	var normalized_id := source_id.strip_edges()
	if normalized_id.is_empty():
		return
	_busy_sources.erase(normalized_id)


static func get_blocking_reason(context: Node) -> String:
	if context == null:
		return ""
	var blocking_reason := _find_registered_blocking_reason()
	if not blocking_reason.is_empty():
		return blocking_reason
	return ""


static func notify_blocked(context: Node, reason: String) -> void:
	if context == null or reason.is_empty():
		return
	var desktop: Node = context.get_node_or_null("/root/Desktop")
	if desktop == null:
		desktop = context.get_tree().root.find_child("Desktop", true, false)
	if desktop != null and desktop.has_method("show_system_notification"):
		desktop.show_system_notification("无法执行操作", reason)


static func _find_registered_blocking_reason() -> String:
	var stale_ids: Array[String] = []
	for source_id in _busy_sources.keys():
		var entry: Dictionary = _busy_sources.get(source_id, {})
		var node_ref: WeakRef = entry.get("node_ref", null)
		var node: Object = node_ref.get_ref() if node_ref != null else null
		if node == null or not is_instance_valid(node):
			stale_ids.append(source_id)
			continue
		var busy_method: String = str(entry.get("busy_method", "")).strip_edges()
		if busy_method.is_empty() or not node.has_method(busy_method):
			continue
		if bool(node.call(busy_method)):
			return str(entry.get("reason", DEFAULT_EVENT_BLOCK_REASON))
	for source_id in stale_ids:
		_busy_sources.erase(source_id)
	return ""