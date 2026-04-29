class_name ActivityLockUtils
extends RefCounted

const DesktopNotificationUtilsClass = preload("res://scripts/pseudo_os/desktop_notification_utils.gd")

const DEFAULT_EVENT_BLOCK_REASON: String = "当前有事件正在进行，请先等待反馈。"
const DEFAULT_CHAT_BLOCK_REASON: String = "当前有对话事件正在等待回复，请先等待反馈。"
const DEFAULT_NARRATIVE_BLOCK_REASON: String = "当前叙事阶段无法进行此活动。"
const DEFAULT_FREE_PERIOD_BLOCK_REASON: String = "当前还有事件在进行，暂时不是自由时段。"
const STORY_FREE_PERIOD_BLOCK_REASON: String = "当前剧情事件正在进行，请先跟着当前节奏推进。"

static var _busy_sources: Dictionary = {}
static var _free_period_blockers: Dictionary = {}

# ── 叙事活动锁 ──
# mode: "" (无锁) | "whitelist" (仅允许列表内) | "blacklist" (禁止列表内)
static var _narrative_lock_mode: String = ""
static var _narrative_lock_activities: Array[String] = []
static var _narrative_lock_reason: String = ""


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


static func register_free_period_blocker(
		source_id: String,
		node: Node,
		busy_method: String = "has_any_pending_sessions",
		reason: String = DEFAULT_FREE_PERIOD_BLOCK_REASON) -> void:
	var normalized_id := source_id.strip_edges()
	if normalized_id.is_empty() or node == null or busy_method.strip_edges().is_empty():
		return
	_free_period_blockers[normalized_id] = {
		"node_ref": weakref(node),
		"busy_method": busy_method,
		"reason": reason if not reason.is_empty() else DEFAULT_FREE_PERIOD_BLOCK_REASON,
	}


static func unregister_free_period_blocker(source_id: String) -> void:
	var normalized_id := source_id.strip_edges()
	if normalized_id.is_empty():
		return
	_free_period_blockers.erase(normalized_id)


static func get_blocking_reason(context: Node) -> String:
	if context == null:
		return ""
	var blocking_reason := _find_registered_blocking_reason(_busy_sources)
	if not blocking_reason.is_empty():
		return blocking_reason
	return ""


static func notify_blocked(_context: Node, reason: String) -> void:
	if reason.is_empty():
		return
	DesktopNotificationUtilsClass.show_system_notification("无法执行操作", reason, "warning", 5.0)


static func _find_registered_blocking_reason(registry: Dictionary) -> String:
	var stale_ids: Array[String] = []
	for source_id in registry.keys():
		var entry: Dictionary = registry.get(source_id, {})
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
		registry.erase(source_id)
	return ""


static func get_free_period_block_reason() -> String:
	var busy_reason := _find_registered_blocking_reason(_busy_sources)
	if not busy_reason.is_empty():
		return busy_reason

	var extra_reason := _find_registered_blocking_reason(_free_period_blockers)
	if not extra_reason.is_empty():
		return extra_reason

	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() != null else null
	if root != null:
		var story: Node = root.get_node_or_null("StoryDirector")
		if story != null:
			if story.has_method("is_taking_control") and bool(story.call("is_taking_control")):
				return STORY_FREE_PERIOD_BLOCK_REASON
			if "current_chapter" in story and story.current_chapter != null:
				return STORY_FREE_PERIOD_BLOCK_REASON
	return ""


static func is_free_period() -> bool:
	return get_free_period_block_reason().is_empty()


# ── 叙事活动锁 API ──

## 设置叙事活动锁。
## mode: "whitelist" — 仅允许 activities 中列出的活动类型。
##        "blacklist" — 禁止 activities 中列出的活动类型，其余放行。
## activities: 活动类型标识列表，如 ["date", "part_time", "gift", "minigame", "sbeam"]
##             也支持 HomeActivity 的具体 ID，如 "chat_deep", "personal"。
##             Browser 行动也可使用聚合类型 "browser"、action_type（如 "community"）
##             或具体 action_id（如 "watch_event"）。
##             传 "life" 可整体锁定所有在家活动。
## reason: 拒绝理由（展示给玩家），为空时使用默认文案。
static func set_narrative_lock(mode: String, activities: Array[String], reason: String = "") -> void:
	_narrative_lock_mode = mode if mode in ["whitelist", "blacklist"] else ""
	_narrative_lock_activities = activities.duplicate()
	_narrative_lock_reason = reason if not reason.is_empty() else DEFAULT_NARRATIVE_BLOCK_REASON


## 清除叙事活动锁，恢复自由活动。
static func clear_narrative_lock() -> void:
	_narrative_lock_mode = ""
	_narrative_lock_activities.clear()
	_narrative_lock_reason = ""


## 查询一组活动别名是否被叙事锁阻止。
## whitelist: 任一别名被允许即放行。
## blacklist: 任一别名命中即拦截。
static func get_narrative_blocking_reason_for_any(activity_types: Array[String]) -> String:
	if _narrative_lock_mode.is_empty():
		return ""

	var normalized_types: Array[String] = []
	for activity_type in activity_types:
		var normalized_type := activity_type.strip_edges()
		if normalized_type.is_empty() or normalized_type in normalized_types:
			continue
		normalized_types.append(normalized_type)

	if normalized_types.is_empty():
		return ""

	match _narrative_lock_mode:
		"whitelist":
			for activity_type in normalized_types:
				if activity_type in _narrative_lock_activities:
					return ""
			return _narrative_lock_reason
		"blacklist":
			for activity_type in normalized_types:
				if activity_type in _narrative_lock_activities:
					return _narrative_lock_reason
			return ""
	return ""


## 查询指定活动类型是否被叙事锁阻止。返回空字符串表示放行。
## activity_type: 活动类型标识 (如 "date", "part_time", "life", "chat_deep" 等)
static func get_narrative_blocking_reason(activity_type: String) -> String:
	var activity_types: Array[String] = []
	activity_types.append(activity_type)
	return get_narrative_blocking_reason_for_any(activity_types)
