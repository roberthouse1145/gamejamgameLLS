class_name ChatProjectContextBuilder extends RefCounted
## LinkChat 协作者项目上下文构建器
##
## KB 注入策略（与 Lore 系统对齐，目的都是减少 LLM 幻觉）：
##   - **索引段**：常驻全部文档的一行式索引（doc_id + title + tags），
##     让 LLM 知道项目里有什么、能用 kb_read 工具按需取详
##   - **命中段**：基于扫描文本（chat_history + 玩家本轮消息 + topic 文本）
##     做关键词命中（title / tags 包含匹配），命中文档**注入完整 content**
##   - 不再做"前 90 字"形式化摘要——那既不够 LLM 索引、也丢失关键事实

const AVGDevWorkOrderToolsClass = preload("res://scripts/avg/dev_tools/work_order_tools.gd")
const NPCCharacterClass = preload("res://scripts/chat/resources/npc_character.gd")

## 命中段预算
const KB_MAX_HITS: int = 3
const KB_MAX_HIT_CONTENT_CHARS: int = 4500
## 触发关键词最小长度（防止单字符误匹配）
const KB_MIN_KEY_LEN: int = 2
## 扫描时取最近多少条 chat_history（与 Lore 一致）
const KB_SCAN_HISTORY_COUNT: int = 10
## doc_kind 优先级——越靠前越优先注入
const KB_DOC_KIND_PRIORITY: Array[String] = [
	"canonical",
	"backbone",
	"brief",
	"decision_log",
	"reference",
	"open_questions",
]


func build_for_channel(_channel: Resource, npcs: Array, scan_text: String = "") -> String:
	if npcs.size() != 1:
		return ""
	return build_for_chat(npcs[0], scan_text)


func build_for_chat(raw_npc: Variant, scan_text: String = "") -> String:
	var npc = _resolve_npc(raw_npc)
	if npc == null or not npc.can_access_project_context():
		return ""

	var sections: PackedStringArray = [
		"## 项目共享上下文",
		"你是这个项目的协作搭档，可以参考以下只读摘要来回答玩家关于当前开发进度、已有设定和后台工单的问题。",
		"如果摘要不够用，可以调用只读工具进一步确认；不要把这里没有的信息说成既定事实。",
	]

	var dev_cycle_summary := build_dev_cycle_context()
	if not dev_cycle_summary.is_empty():
		sections.append("### 开发循环\n%s" % dev_cycle_summary)

	var work_order_summary := build_work_order_context()
	if not work_order_summary.is_empty():
		sections.append("### 工单状态\n%s" % work_order_summary)

	var kb_block := build_kb_context(scan_text)
	if not kb_block.is_empty():
		sections.append(kb_block)

	return "\n\n".join(sections).strip_edges()


func build_dev_cycle_context() -> String:
	var dcm: Node = _get_autoload("DevCycleManager")
	if dcm == null:
		return "- 开发循环信息当前不可用"

	var lines: PackedStringArray = []
	var current_day: int = int(dcm.call("_get_current_day")) if dcm.has_method("_get_current_day") else 1
	var order_active: bool = dcm.is_order_active() if dcm.has_method("is_order_active") else false
	lines.append("- 当前天数：Day %d" % current_day)
	lines.append("- 已完成任务数：%d" % (dcm.get_completed_count() if dcm.has_method("get_completed_count") else 0))
	lines.append("- 当前是否有后台工单在执行：%s" % ("是" if order_active else "否"))

	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	if visible_tasks.is_empty():
		lines.append("- 当前没有可见 dev work")
	else:
		lines.append("- 当前可见 dev work：")
		for task in visible_tasks:
			lines.append("  - [%s] %s" % [
				str(task.get("status", "")),
				str(task.get("title", "")),
			])

	return "\n".join(lines)


func build_work_order_context() -> String:
	var summary_result: Dictionary = AVGDevWorkOrderToolsClass._wo_list_order_summaries({"limit": 8})
	if not bool(summary_result.get("success", false)):
		return "- 当前无法读取工单摘要"

	var lines: PackedStringArray = []
	var rows: Array = summary_result.get("data", [])
	if rows.is_empty():
		lines.append("- 当前没有工单")
		return "\n".join(lines)

	lines.append("- 当前工单总数：%d" % int(summary_result.get("total_orders", rows.size())))
	for row in rows:
		if not row is Dictionary:
			continue
		lines.append("  - [%s/%s] %s" % [
			str(row.get("surface_status", row.get("status", ""))),
			str(row.get("inner_status", "")),
			str(row.get("title", "")),
		])
	return "\n".join(lines)


## KB 注入入口。返回包含「索引段 + 命中段」的完整 KB 文本。
## scan_text 为空时只输出索引段（命中段空）。
func build_kb_context(scan_text: String = "") -> String:
	var kb: Node = _get_autoload("KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_documents"):
		return "### 项目知识库\n- 当前知识库不可用"

	var docs: Array = kb.get_documents()
	if docs.is_empty():
		return "### 项目知识库\n- 当前知识库为空"

	var sorted_docs: Array = docs.duplicate()
	sorted_docs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("doc_id", "")) < str(b.get("doc_id", ""))
	)

	var sections: PackedStringArray = []
	sections.append("### 项目设定索引\n%s" % _build_kb_index(sorted_docs))

	var matches: Array = _match_kb_docs(scan_text, sorted_docs)
	if not matches.is_empty():
		sections.append("### 当前对话相关条目\n%s" % _build_kb_matches(matches))

	return "\n\n".join(sections)


## 构建索引段：每篇一行 `- [category] [doc_id=...] title (tags: a/b/c)`
static func _build_kb_index(sorted_docs: Array) -> String:
	var lines: PackedStringArray = []
	for doc in sorted_docs:
		var doc_id := str(doc.get("doc_id", "")).strip_edges()
		var title := str(doc.get("title", "")).strip_edges()
		var category := str(doc.get("category", "")).strip_edges()
		var tags: Array = doc.get("tags", [])
		var tags_part := ""
		if tags is Array and not tags.is_empty():
			var tag_strs: PackedStringArray = []
			for t in tags:
				var ts := str(t).strip_edges()
				if not ts.is_empty():
					tag_strs.append(ts)
			if not tag_strs.is_empty():
				tags_part = " (tags: %s)" % "/".join(tag_strs)
		lines.append("- [%s] [doc_id=%s] %s%s" % [category, doc_id, title, tags_part])
	lines.append("")
	lines.append("如需深读某条目，可调用 kb_read(doc_id=\"...\") 取全文。")
	return "\n".join(lines)


## 命中段：每篇文档完整 content。
## 上游已经按 doc_kind 优先级排序、限制条数。
static func _build_kb_matches(matched_docs: Array) -> String:
	var blocks: PackedStringArray = []
	for doc in matched_docs:
		var doc_id := str(doc.get("doc_id", "")).strip_edges()
		var title := str(doc.get("title", "")).strip_edges()
		var category := str(doc.get("category", "")).strip_edges()
		var content := str(doc.get("content", "")).strip_edges()
		blocks.append("#### [%s] %s (doc_id=%s)\n%s" % [category, title, doc_id, content])
	return "\n\n".join(blocks)


## 关键词匹配：扫描 scan_text，对每篇文档的 title / tags 做小写包含匹配。
## 返回命中文档数组，按 doc_kind 优先级 + doc_id 排序，应用 KB_MAX_HITS / KB_MAX_HIT_CONTENT_CHARS 预算。
static func _match_kb_docs(scan_text: String, sorted_docs: Array) -> Array:
	var normalized_scan := scan_text.strip_edges().to_lower()
	if normalized_scan.is_empty():
		return []

	var candidates: Array = []
	for doc in sorted_docs:
		if _doc_matches_scan(doc, normalized_scan):
			candidates.append(doc)

	if candidates.is_empty():
		return []

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := KB_DOC_KIND_PRIORITY.find(str(a.get("doc_kind", "canonical")))
		var pb := KB_DOC_KIND_PRIORITY.find(str(b.get("doc_kind", "canonical")))
		# find 返回 -1 时（doc_kind 不在白名单），排到最后
		if pa < 0:
			pa = KB_DOC_KIND_PRIORITY.size()
		if pb < 0:
			pb = KB_DOC_KIND_PRIORITY.size()
		if pa != pb:
			return pa < pb
		return str(a.get("doc_id", "")) < str(b.get("doc_id", ""))
	)

	var picked: Array = []
	var total_chars: int = 0
	for doc in candidates:
		if picked.size() >= KB_MAX_HITS:
			break
		var content := str(doc.get("content", "")).strip_edges()
		if total_chars + content.length() > KB_MAX_HIT_CONTENT_CHARS and not picked.is_empty():
			break
		picked.append(doc)
		total_chars += content.length()
	return picked


## 单篇文档是否被扫描文本命中：title / tags 任一包含匹配（小写、最小长度门槛）。
static func _doc_matches_scan(doc: Dictionary, normalized_scan: String) -> bool:
	var title := str(doc.get("title", "")).strip_edges().to_lower()
	if title.length() >= KB_MIN_KEY_LEN and normalized_scan.contains(title):
		return true
	var tags: Array = doc.get("tags", [])
	if tags is Array:
		for tag in tags:
			var tag_str := str(tag).strip_edges().to_lower()
			if tag_str.length() >= KB_MIN_KEY_LEN and normalized_scan.contains(tag_str):
				return true
	return false


## 构建用于关键词命中的扫描文本：玩家本轮消息 + 最近 chat_history + topic 文本。
## 与 Lore 系统的扫描文本范围一致——保持两套机制对相同消息有相同的"上下文视野"。
static func build_chat_scan_text(
	chat_history: Array[Dictionary],
	player_messages: Array[String],
	topic: ChatTopic,
) -> String:
	var parts: Array[String] = []
	for msg in player_messages:
		var text := str(msg).strip_edges()
		if not text.is_empty():
			parts.append(text)

	var history_slice: Array[Dictionary] = chat_history.slice(-KB_SCAN_HISTORY_COUNT)
	for msg in history_slice:
		if not msg is Dictionary:
			continue
		var sender := str(msg.get("sender_name", "")).strip_edges()
		var content := str(msg.get("content", "")).strip_edges()
		var line := "%s %s" % [sender, content]
		if msg.has("card") and msg["card"] is Dictionary:
			var card: Dictionary = msg["card"]
			var hint := str(card.get("hint", "")).strip_edges()
			if not hint.is_empty():
				line += " " + hint
		parts.append(line.strip_edges())

	if topic != null:
		var topic_parts: Array[String] = []
		var sys_prompt := str(topic.system_prompt).strip_edges()
		if not sys_prompt.is_empty():
			topic_parts.append(sys_prompt)
		var goal := str(topic.goal_description).strip_edges()
		if not goal.is_empty():
			topic_parts.append(goal)
		if not topic_parts.is_empty():
			parts.append("\n".join(topic_parts))

	return "\n".join(parts)


func build_dev_cycle_snapshot() -> Dictionary:
	var dcm: Node = _get_autoload("DevCycleManager")
	if dcm == null:
		return {"success": false, "error": "DevCycleManager not available."}

	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	var task_summaries: Array[Dictionary] = []
	for task in visible_tasks:
		var runtime_type: String = str(task.get("task_type", "")).strip_edges()
		if dcm.has_method("_describe_task_runtime_type"):
			runtime_type = str(dcm.call("_describe_task_runtime_type", task))
		task_summaries.append({
			"task_id": str(task.get("task_id", "")),
			"title": str(task.get("title", "")),
			"status": str(task.get("status", "")),
			"task_type": runtime_type,
		})

	return {
		"success": true,
		"data": {
			"current_day": int(dcm.call("_get_current_day")) if dcm.has_method("_get_current_day") else 1,
			"visible_tasks": task_summaries,
			"completed_task_count": dcm.get_completed_count() if dcm.has_method("get_completed_count") else 0,
			"queue_size": dcm.get_queue_size() if dcm.has_method("get_queue_size") else 0,
			"order_active": dcm.is_order_active() if dcm.has_method("is_order_active") else false,
			"plan_generated": dcm.is_plan_generated() if dcm.has_method("is_plan_generated") else false,
			"plan_generating": dcm.is_plan_generating() if dcm.has_method("is_plan_generating") else false,
		}
	}


func _resolve_npc(raw_npc: Variant) -> Variant:
	var npc := raw_npc as NPCCharacter
	if npc != null:
		return npc
	if raw_npc is Array and not (raw_npc as Array).is_empty():
		npc = (raw_npc as Array)[0] as NPCCharacter
		if npc != null:
			return npc
	return null


func _get_autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)
