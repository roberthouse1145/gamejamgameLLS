extends Node
## BithubManager
## 独立维护玩家本次运行内可见的“提交记录”和里程碑快照。
## 当前项目还没有正式存档系统，因此 Bithub 不做任何隐式磁盘持久化。

signal repository_changed()
signal commit_recorded(commit: Dictionary)
signal milestone_created(milestone: Dictionary)
signal milestone_play_started(milestone_id: String)
signal milestone_play_finished(milestone_id: String)

const APP_ID: String = "bithub"
const FALLBACK_REPO_KEY: String = "default"

var _ai_service: AIService = null
var _pending_commit_requests: Dictionary = {}
var _state: Dictionary = {
	"repo_key": FALLBACK_REPO_KEY,
	"commits": [],
	"milestones": [],
}
var _restoring_project: bool = false
var _preview_restore_context: Dictionary = {}
var _runtime_milestone_projects: Dictionary = {}


func _ready() -> void:
	_setup_ai_service()
	_connect_work_order_manager()
	if StorageManager != null:
		StorageManager.current_project_changed.connect(_on_current_project_changed)
	_reset_state_for_current_project()


func get_commits() -> Array:
	return (_state.get("commits", []) as Array).duplicate(true)


func get_milestones() -> Array:
	return (_state.get("milestones", []) as Array).duplicate(true)


func get_commit(commit_id: String) -> Dictionary:
	for commit in _state.get("commits", []):
		if commit is Dictionary and str(commit.get("commit_id", "")) == commit_id:
			return (commit as Dictionary).duplicate(true)
	return {}


func get_milestone(milestone_id: String) -> Dictionary:
	for milestone in _state.get("milestones", []):
		if milestone is Dictionary and str(milestone.get("milestone_id", "")) == milestone_id:
			return (milestone as Dictionary).duplicate(true)
	return {}


func reset_runtime_state() -> void:
	_pending_commit_requests.clear()
	_preview_restore_context.clear()
	_runtime_milestone_projects.clear()
	_restoring_project = false
	_reset_state_for_current_project()


func create_milestone(milestone_name: String, entry_scene_id: String = "", commit_id: String = "") -> Dictionary:
	var normalized_name: String = milestone_name.strip_edges()
	if normalized_name.is_empty():
		normalized_name = "可玩里程碑"

	var milestone_id: String = _build_id("milestone", normalized_name)
	var snapshot_project: Resource = _create_runtime_project_snapshot()
	if snapshot_project == null:
		push_warning("[BithubManager] Failed to create runtime milestone snapshot")
		return {}
	_runtime_milestone_projects[milestone_id] = snapshot_project

	var milestone: Dictionary = {
		"milestone_id": milestone_id,
		"commit_id": commit_id,
		"name": normalized_name,
		"entry_scene_id": entry_scene_id.strip_edges(),
		"created_at": int(Time.get_unix_time_from_system()),
	}
	var milestones: Array = _state.get("milestones", [])
	milestones.push_front(milestone)
	_state["milestones"] = milestones
	repository_changed.emit()
	milestone_created.emit(milestone.duplicate(true))
	return milestone.duplicate(true)


func play_milestone(milestone_id: String) -> bool:
	var milestone: Dictionary = get_milestone(milestone_id)
	if milestone.is_empty():
		push_warning("[BithubManager] Milestone not found: %s" % milestone_id)
		return false

	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("launch_app"):
		push_warning("[BithubManager] AppManager unavailable for milestone play")
		return false

	var previous_project: Resource = StorageManager.current_project
	var previous_path: String = StorageManager.current_project_path
	var snapshot_project: Resource = _runtime_milestone_projects.get(milestone_id, null)
	if snapshot_project == null:
		push_warning("[BithubManager] Runtime milestone snapshot missing: %s" % milestone_id)
		_restore_project(previous_project, previous_path)
		return false

	_preview_restore_context = {
		"milestone_id": milestone_id,
		"previous_project": previous_project,
		"previous_path": previous_path,
	}
	_restoring_project = true
	StorageManager.set_current_project(snapshot_project)
	_restoring_project = false

	var window: Control = app_mgr.launch_app("game_previewer", true)
	if window == null:
		_finish_milestone_play()
		return false

	var previewer: Node = _find_game_previewer_node(window)
	if previewer == null or not previewer.has_method("start_story_preview"):
		_finish_milestone_play()
		return false

	var completed_cb := Callable(self, "_on_milestone_preview_completed")
	if previewer.has_signal("preview_completed") and not previewer.preview_completed.is_connected(completed_cb):
		previewer.preview_completed.connect(completed_cb, CONNECT_ONE_SHOT)

	var app_closed_cb := Callable(self, "_on_preview_app_closed")
	if app_mgr.has_signal("app_closed") and not app_mgr.app_closed.is_connected(app_closed_cb):
		app_mgr.app_closed.connect(app_closed_cb)

	var entry_scene_id: String = str(milestone.get("entry_scene_id", "")).strip_edges()
	var started: bool = bool(previewer.call("start_story_preview", entry_scene_id, false))
	if not started:
		_finish_milestone_play()
		return false

	milestone_play_started.emit(milestone_id)
	return true


func record_commit_for_order(order_id: String, order: Resource = null) -> void:
	var normalized_order_id: String = order_id.strip_edges()
	if normalized_order_id.is_empty() or _has_commit_for_order(normalized_order_id):
		return

	if order == null:
		var wom: Node = get_node_or_null("/root/WorkOrderManager")
		if wom != null and wom.has_method("get_order"):
			order = wom.get_order(normalized_order_id)

	var draft: Dictionary = _build_commit_draft(normalized_order_id, order)
	if _should_use_llm():
		var request_id: String = _ai_service.chat_simple(_build_commit_prompt(draft), _build_commit_system_prompt())
		if not request_id.is_empty():
			_pending_commit_requests[request_id] = draft
			return

	_finalize_commit(draft, _build_fallback_commit_text(draft))


func _setup_ai_service() -> void:
	_ai_service = AIService.new()
	_ai_service.name = "BithubAIService"
	add_child(_ai_service)
	var config_mgr := AIConfigManager.get_instance()
	if config_mgr != null:
		config_mgr.apply_to_service(_ai_service, "work_order")
	_ai_service.request_completed.connect(_on_ai_request_completed)
	_ai_service.request_failed.connect(_on_ai_request_failed)


func _connect_work_order_manager() -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null or not wom.has_signal("order_status_changed"):
		return
	if not wom.order_status_changed.is_connected(_on_order_status_changed):
		wom.order_status_changed.connect(_on_order_status_changed)


func _on_current_project_changed(_project: Resource) -> void:
	if _restoring_project:
		return
	_reset_state_for_current_project()


func _on_order_status_changed(order_id: String, _old_status: String, new_status: String) -> void:
	if new_status != "completed":
		return
	record_commit_for_order(order_id)


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if not _pending_commit_requests.has(request_id):
		return
	var draft: Dictionary = _pending_commit_requests[request_id]
	_pending_commit_requests.erase(request_id)
	var content: String = AIService.extract_content(response).strip_edges()
	if content.is_empty():
		content = _build_fallback_commit_text(draft)
	_finalize_commit(draft, content)


func _on_ai_request_failed(request_id: String, _error: String) -> void:
	if not _pending_commit_requests.has(request_id):
		return
	var draft: Dictionary = _pending_commit_requests[request_id]
	_pending_commit_requests.erase(request_id)
	_finalize_commit(draft, _build_fallback_commit_text(draft))


func _finalize_commit(draft: Dictionary, raw_message: String) -> void:
	var message_data: Dictionary = _parse_commit_message(raw_message, draft)
	var commit: Dictionary = draft.duplicate(true)
	commit["title"] = str(message_data.get("title", draft.get("title", ""))).strip_edges()
	commit["message"] = str(message_data.get("message", draft.get("message", ""))).strip_edges()
	if commit["title"].is_empty():
		commit["title"] = "完成一次开发提交"
	if commit["message"].is_empty():
		commit["message"] = "后台工单完成，项目向前推进了一步。"

	var commits: Array = _state.get("commits", [])
	commits.push_front(commit)
	_state["commits"] = commits
	repository_changed.emit()
	commit_recorded.emit(commit.duplicate(true))
	_show_commit_notification(commit)
	_maybe_create_milestone_from_commit(commit)


func _build_commit_draft(order_id: String, order: Resource) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var title: String = "完成工单"
	var description: String = ""
	var metadata: Dictionary = {}
	if order != null:
		if "title" in order:
			title = str(order.title)
		if "description" in order:
			description = str(order.description)
		if "metadata" in order and order.metadata is Dictionary:
			metadata = (order.metadata as Dictionary).duplicate(true)
	return {
		"commit_id": _build_id("commit", order_id),
		"order_id": order_id,
		"title": title,
		"message": description,
		"created_at": now,
		"tags": [],
		"milestone_id": "",
		"order_metadata": metadata,
	}


func _build_commit_system_prompt() -> String:
	return "你是游戏内 Bithub 的提交信息生成器。请生成用于叙事渲染的 commit 文案，不要暴露真实后台实现、LLM、隐藏工单或内部黑箱。只输出两行 DSL，不要 Markdown 代码块：\ntitle: 一句简短提交标题\nmessage: 1-2 句面向玩家的项目进展说明"


func _build_commit_prompt(draft: Dictionary) -> String:
	return "工单标题：%s\n工单描述：%s\n请写成像 GitHub commit 一样的项目进展记录。" % [
		str(draft.get("title", "")),
		str(draft.get("message", "")),
	]


func _build_fallback_commit_text(draft: Dictionary) -> String:
	var title: String = str(draft.get("title", "")).strip_edges()
	if title.is_empty():
		title = "完成一次开发提交"
	return "title: 完成：%s\nmessage: 后台开发完成了一项工作，项目状态已经推进到新的稳定点。" % title


func _parse_commit_message(raw_text: String, draft: Dictionary) -> Dictionary:
	var text: String = _strip_commit_dsl_fence(raw_text)
	var title: String = ""
	var message: String = ""
	var collecting_message: bool = false
	var message_lines: PackedStringArray = []

	for raw_line in text.split("\n"):
		var line: String = str(raw_line).strip_edges()
		var title_field: Dictionary = _read_commit_dsl_field(line, "title")
		if bool(title_field.get("matched", false)):
			title = str(title_field.get("value", "")).strip_edges()
			collecting_message = false
			continue

		var message_field: Dictionary = _read_commit_dsl_field(line, "message")
		if bool(message_field.get("matched", false)):
			message = str(message_field.get("value", "")).strip_edges()
			collecting_message = message.is_empty()
			message_lines.clear()
			continue

		if collecting_message:
			message_lines.append(str(raw_line).strip_edges())

	if message.is_empty() and not message_lines.is_empty():
		message = "\n".join(message_lines).strip_edges()
	if title.is_empty():
		title = str(draft.get("title", "")).strip_edges()
	if message.is_empty():
		message = str(draft.get("message", "")).strip_edges()
	return {
		"title": title,
		"message": message,
	}


func _strip_commit_dsl_fence(raw_text: String) -> String:
	var text: String = raw_text.strip_edges()
	if not text.begins_with("```"):
		return text

	var lines: PackedStringArray = text.split("\n")
	var end_index: int = lines.size()
	if end_index > 1 and str(lines[end_index - 1]).strip_edges() == "```":
		end_index -= 1

	var body_lines: PackedStringArray = []
	for i in range(1, end_index):
		body_lines.append(str(lines[i]))
	return "\n".join(body_lines).strip_edges()


func _read_commit_dsl_field(line: String, expected_key: String) -> Dictionary:
	var text: String = line.strip_edges()
	var colon_index: int = text.find(":")
	var full_colon_index: int = text.find("：")
	if full_colon_index >= 0 and (colon_index < 0 or full_colon_index < colon_index):
		colon_index = full_colon_index
	if colon_index < 0:
		return {"matched": false, "value": ""}

	var key: String = text.substr(0, colon_index).strip_edges().to_lower()
	if key != expected_key:
		return {"matched": false, "value": ""}
	return {
		"matched": true,
		"value": text.substr(colon_index + 1).strip_edges(),
	}


func _maybe_create_milestone_from_commit(commit: Dictionary) -> void:
	var metadata: Dictionary = commit.get("order_metadata", {})
	if metadata.is_empty():
		return
	var milestone_name: String = str(metadata.get("bithub_milestone_name", metadata.get("milestone_name", ""))).strip_edges()
	var should_create: bool = bool(metadata.get("bithub_milestone", false)) or not milestone_name.is_empty()
	if not should_create:
		return
	if milestone_name.is_empty():
		milestone_name = str(commit.get("title", "可玩里程碑"))
	var milestone: Dictionary = create_milestone(
		milestone_name,
		str(metadata.get("entry_scene_id", "")),
		str(commit.get("commit_id", ""))
	)
	if not milestone.is_empty():
		commit["milestone_id"] = str(milestone.get("milestone_id", ""))


func _has_commit_for_order(order_id: String) -> bool:
	for commit in _state.get("commits", []):
		if commit is Dictionary and str(commit.get("order_id", "")) == order_id:
			return true
	return false


func _should_use_llm() -> bool:
	if _ai_service == null:
		return false
	var config_mgr := AIConfigManager.get_instance()
	if config_mgr != null and config_mgr.has_method("is_background_llm_disabled"):
		return not bool(config_mgr.is_background_llm_disabled())
	return true


func _reset_state_for_current_project() -> void:
	_state = {
		"repo_key": _get_repo_key(),
		"commits": [],
		"milestones": [],
	}
	_runtime_milestone_projects.clear()
	repository_changed.emit()


func _get_repo_key() -> String:
	var source: String = ""
	if StorageManager != null:
		source = StorageManager.current_project_path
		if source.is_empty() and StorageManager.current_project != null and "project_name" in StorageManager.current_project:
			source = str(StorageManager.current_project.project_name)
	if source.strip_edges().is_empty():
		return FALLBACK_REPO_KEY
	return "repo_%d" % abs(source.hash())


func _build_id(prefix: String, id_seed: String) -> String:
	var now: int = int(Time.get_unix_time_from_system())
	return "%s_%d_%06x" % [prefix, now, abs((id_seed + str(now)).hash()) & 0xFFFFFF]


func _create_runtime_project_snapshot() -> Resource:
	if StorageManager == null or StorageManager.current_project == null:
		return null
	return StorageManager.current_project.duplicate(true)


func _show_commit_notification(commit: Dictionary) -> void:
	var desktop: Node = get_tree().get_first_node_in_group("desktop")
	if desktop == null or not desktop.has_method("show_system_notification"):
		return
	desktop.call(
		"show_system_notification",
		"main 有新推送",
		str(commit.get("title", "")),
		"info",
		5.0
	)


func _find_game_previewer_node(root: Node) -> Node:
	if root == null:
		return null
	if root is GamePreviewer:
		return root
	for child in root.get_children():
		var result: Node = _find_game_previewer_node(child)
		if result != null:
			return result
	return null


func _on_milestone_preview_completed(_payload: Dictionary = {}) -> void:
	_finish_milestone_play()


func _on_preview_app_closed(app_id: String) -> void:
	if app_id != "game_previewer":
		return
	_finish_milestone_play()


func _finish_milestone_play() -> void:
	if _preview_restore_context.is_empty():
		return
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr != null and app_mgr.has_signal("app_closed"):
		var app_closed_cb := Callable(self, "_on_preview_app_closed")
		if app_mgr.app_closed.is_connected(app_closed_cb):
			app_mgr.app_closed.disconnect(app_closed_cb)
	var milestone_id: String = str(_preview_restore_context.get("milestone_id", ""))
	_restore_project(
		_preview_restore_context.get("previous_project", null),
		str(_preview_restore_context.get("previous_path", ""))
	)
	_preview_restore_context.clear()
	milestone_play_finished.emit(milestone_id)


func _restore_project(project: Resource, project_path: String) -> void:
	_restoring_project = true
	StorageManager.current_project_path = project_path
	StorageManager.set_current_project(project)
	_restoring_project = false
