extends Node
## StoryDirector Autoload
## 叙事导演 — 驱动剧本步骤的状态机引擎
## 加载章节 → 逐步执行 actions → 等待 wait_for 条件 → 推进到下一步

const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const StoryChapterIndexClass = preload("res://scripts/story/resources/story_chapter_index.gd")
const StoryCompilerClass = preload("res://scripts/story/story_compiler.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const AVGSceneGeneratorClass = preload("res://scripts/activity/avg_scene_generator.gd")
const SceneWindowClass = preload("res://scripts/activity/scene_window.gd")

const _CONDITION_OPERATORS: Array[String] = [">=", "<=", "==", "!=", ">", "<"]
const STORY_AVG_GENERATION_TRANSIT_STAGES: Array[String] = [
	"正在整理刚才的对话上下文...",
	"LLM 正在生成 AVG 脚本...",
	"正在准备打开场景...",
]

# =============================================================================
# Signals
# =============================================================================

signal step_entered(chapter_id: String, step_id: String)
signal step_completed(chapter_id: String, step_id: String)
signal chapter_completed(chapter_id: String)
signal chapter_started(chapter_id: String)
signal story_variable_changed(key: String, value: Variant)
signal all_chapters_completed()
signal avg_scene_ended(scene_id: String, outcome: Dictionary)
signal project_preview_finished(preview_id: String, payload: Dictionary)

# =============================================================================
# State
# =============================================================================

## 当前章节
var current_chapter: Resource = null  # StoryChapter

## 当前步骤
var current_step: Resource = null  # StoryStep

## 剧情变量（跨步骤/跨章节持久化）
var story_variables: Dictionary = {}

## 已完成的步骤 ID 集合
var completed_steps: Dictionary = {}

## 已完成的章节 ID 集合
var completed_chapters: Dictionary = {}
var _pending_activity_guidance: Dictionary = {}

## 是否正在等待条件
var _waiting: bool = false

## 当前等待的信号连接（用于断开）
var _wait_connections: Array[Dictionary] = []

## 延迟计时器
var _delay_timer: Timer = null

## 是否已启动
var _started: bool = false

## 所有已加载的章节（chapter_id -> StoryChapter）
var _chapters: Dictionary = {}
var _trigger_scan_queued: bool = false
var _story_avg_generator: Node = null
var _story_avg_scene_adapter: Variant = null
var _story_avg_requests: Dictionary = {}
var _story_avg_counter: int = 0
var _project_preview_adapter: Variant = null
var _project_preview_sessions: Dictionary = {}
var _last_wait_payload: Dictionary = {}
var _current_step_action_failed: bool = false


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	_delay_timer = Timer.new()
	_delay_timer.one_shot = true
	add_child(_delay_timer)
	_load_all_chapters()
	_connect_trigger_sources()
	print("[StoryDirector] Initialized. %d chapters loaded." % _chapters.size())


# =============================================================================
# Public API
# =============================================================================

## 启动指定章节
func start_chapter(chapter_id: String) -> bool:
	var chapter: Resource = _chapters.get(chapter_id)
	if chapter == null:
		push_warning("[StoryDirector] Chapter not found: %s" % chapter_id)
		return false

	_disconnect_all_waits()
	_last_wait_payload.clear()
	current_chapter = chapter
	current_step = null
	_started = true

	print("[StoryDirector] ==== Chapter started: %s (%s) ====" % [chapter_id, chapter.chapter_name])
	chapter_started.emit(chapter_id)

	var first: Resource = chapter.get_first_step()
	if first == null:
		push_warning("[StoryDirector] Chapter has no steps: %s" % chapter_id)
		return false

	_enter_step(first)
	return true


## 设置剧情变量
func set_variable(key: String, value: Variant) -> void:
	story_variables[key] = value
	story_variable_changed.emit(key, value)


## 获取剧情变量
func get_variable(key: String, default: Variant = null) -> Variant:
	return story_variables.get(key, default)


## 手动推进到下一步（用于外部系统通知条件满足）
func notify_condition_met(condition_type: String, data: Dictionary = {}) -> void:
	if not _waiting or current_step == null:
		return
	var wait: Dictionary = current_step.wait_for
	if wait.get("type", "") != condition_type:
		return
	if not _match_wait_data(wait, data):
		return
	_on_wait_satisfied(data)


func submit_story_event(condition_type: String, data: Dictionary = {}, variables: Dictionary = {}) -> void:
	notify_condition_met(condition_type, data)
	for key in variables.keys():
		set_variable(str(key), variables[key])


func set_activity_guidance(activity_type: String, prompt: String, consume_once: bool = true) -> void:
	var normalized_type := activity_type.strip_edges()
	var normalized_prompt := prompt.strip_edges()
	if normalized_type.is_empty():
		push_warning("[StoryDirector] set_activity_guidance: empty activity_type")
		return
	if normalized_prompt.is_empty():
		_pending_activity_guidance.erase(normalized_type)
		return
	_pending_activity_guidance[normalized_type] = {
		"prompt": normalized_prompt,
		"consume_once": consume_once,
	}


func consume_activity_guidance(activity_type: String) -> String:
	var normalized_type := activity_type.strip_edges()
	if normalized_type.is_empty() or not _pending_activity_guidance.has(normalized_type):
		return ""
	var entry: Variant = _pending_activity_guidance.get(normalized_type, {})
	var guidance: Dictionary = entry if entry is Dictionary else {}
	var prompt := str(guidance.get("prompt", "")).strip_edges()
	if bool(guidance.get("consume_once", true)):
		_pending_activity_guidance.erase(normalized_type)
	return prompt


func peek_activity_guidance(activity_type: String) -> String:
	var normalized_type := activity_type.strip_edges()
	if normalized_type.is_empty() or not _pending_activity_guidance.has(normalized_type):
		return ""
	var entry: Variant = _pending_activity_guidance.get(normalized_type, {})
	var guidance: Dictionary = entry if entry is Dictionary else {}
	return str(guidance.get("prompt", "")).strip_edges()


func clear_activity_guidance(activity_type: String = "") -> void:
	var normalized_type := activity_type.strip_edges()
	if normalized_type.is_empty():
		_pending_activity_guidance.clear()
		return
	_pending_activity_guidance.erase(normalized_type)


## 获取当前状态摘要（存档用）
func get_save_data() -> Dictionary:
	return {
		"chapter_id": current_chapter.chapter_id if current_chapter else "",
		"step_id": current_step.step_id if current_step else "",
		"story_variables": story_variables.duplicate(true),
		"completed_steps": completed_steps.duplicate(true),
		"completed_chapters": completed_chapters.duplicate(true),
		"pending_activity_guidance": _pending_activity_guidance.duplicate(true),
	}


## 从存档恢复
func load_save_data(data: Dictionary) -> bool:
	story_variables = data.get("story_variables", {}).duplicate(true)
	completed_steps = data.get("completed_steps", {}).duplicate(true)
	completed_chapters = data.get("completed_chapters", {}).duplicate(true)
	_pending_activity_guidance = data.get("pending_activity_guidance", {}).duplicate(true)

	var chapter_id: String = str(data.get("chapter_id", ""))
	var step_id: String = str(data.get("step_id", ""))
	if chapter_id.is_empty():
		return false

	var chapter: Resource = _chapters.get(chapter_id)
	if chapter == null:
		push_warning("[StoryDirector] Save data references unknown chapter: %s" % chapter_id)
		return false

	current_chapter = chapter
	_started = true
	chapter_started.emit(chapter_id)

	if step_id.is_empty():
		var first: Resource = chapter.get_first_step()
		if first:
			_enter_step(first)
		return true

	var step: Resource = chapter.get_step(step_id)
	if step == null:
		push_warning("[StoryDirector] Save data references unknown step: %s" % step_id)
		return false

	_enter_step(step)
	return true


func get_run_state() -> Dictionary:
	return get_save_data()


func load_run_state(data: Dictionary) -> bool:
	story_variables = data.get("story_variables", {}).duplicate(true)
	completed_steps = data.get("completed_steps", {}).duplicate(true)
	completed_chapters = data.get("completed_chapters", {}).duplicate(true)
	_pending_activity_guidance = data.get("pending_activity_guidance", {}).duplicate(true)

	var chapter_id: String = str(data.get("chapter_id", "")).strip_edges()
	var step_id: String = str(data.get("step_id", "")).strip_edges()
	if chapter_id.is_empty():
		_disconnect_all_waits()
		current_chapter = null
		current_step = null
		_waiting = false
		_started = false
		_request_trigger_scan()
		return true

	if step_id.is_empty():
		return load_save_data({
			"chapter_id": chapter_id,
			"story_variables": story_variables,
			"completed_steps": completed_steps,
			"completed_chapters": completed_chapters,
			"pending_activity_guidance": _pending_activity_guidance,
		})
	return load_save_data(data)


## ── Prompt Provider 方法（供 PromptManager 的 JSON 绑定调用）──

func get_player_name_prompt() -> String:
	var real_name: String = str(get_variable("player_real_name", "")).strip_edges()
	var nickname: String = str(get_variable("player_name", "")).strip_edges()
	return real_name if not real_name.is_empty() else nickname


func get_player_web_name_prompt() -> String:
	return str(get_variable("player_name", "")).strip_edges()


func get_player_team_prompt() -> String:
	return str(get_variable("team_name", "")).strip_edges()


func get_player_college_prompt() -> String:
	return str(get_variable("player_college", "")).strip_edges()


## 当前是否仍由 StoryDirector 接管玩家节奏。
## 用于判断是否仍处于剧情强控，而不是判断是否存在剧情历史。
func is_taking_control() -> bool:
	return current_chapter != null or current_step != null or _waiting


func has_active_story() -> bool:
	return _started or current_chapter != null or current_step != null or not completed_steps.is_empty() or not completed_chapters.is_empty()


func evaluate_triggers() -> bool:
	return _try_start_triggered_chapter()


func reset_runtime_state() -> void:
	_disconnect_all_waits()
	if _delay_timer != null:
		_delay_timer.stop()
	current_chapter = null
	current_step = null
	story_variables.clear()
	completed_steps.clear()
	completed_chapters.clear()
	_pending_activity_guidance.clear()
	_waiting = false
	_started = false
	_story_avg_requests.clear()
	_story_avg_counter = 0
	_last_wait_payload.clear()


func rebuild_story_cache() -> bool:
	if OS.has_feature("template"):
		push_warning("[StoryDirector] rebuild_story_cache is unavailable in exported builds")
		return false

	var index_resource: Resource = StoryCompilerClass.compile_all()
	var rebuilt: bool = _load_compiled_chapters(index_resource)
	if rebuilt:
		_request_trigger_scan()
	return rebuilt


# =============================================================================
# Step Execution
# =============================================================================

func _enter_step(step: Resource) -> void:
	_disconnect_all_waits()
	current_step = step
	_waiting = false
	_current_step_action_failed = false

	print("[StoryDirector] >> Enter step: %s" % step.step_id)
	step_entered.emit(current_chapter.chapter_id, step.step_id)

	# 执行所有 actions
	for action in step.actions:
		_execute_action(action)
		if _current_step_action_failed:
			push_warning("[StoryDirector] Step action failed; wait setup skipped for %s" % step.step_id)
			return

	# 设置等待
	var wait_type: String = str(step.wait_for.get("type", "immediate"))
	if wait_type == "immediate":
		call_deferred("_advance")
	else:
		_waiting = true
		_setup_wait(step.wait_for)


func _advance() -> void:
	if current_step == null or current_chapter == null:
		return

	var old_step: Resource = current_step
	completed_steps[old_step.step_id] = true
	print("[StoryDirector] << Step completed: %s" % old_step.step_id)
	step_completed.emit(current_chapter.chapter_id, old_step.step_id)

	# 解析下一步
	var game_state: Dictionary = _collect_game_state()
	var next_id: String = old_step.resolve_next(story_variables, game_state)

	if next_id.is_empty():
		# 章节结束
		_complete_chapter()
		return

	var next_step: Resource = current_chapter.get_step(next_id)
	if next_step == null:
		push_warning("[StoryDirector] Next step not found: %s" % next_id)
		_complete_chapter()
		return

	_enter_step(next_step)


func _complete_chapter() -> void:
	if current_chapter == null:
		return

	var chapter_id: String = current_chapter.chapter_id
	completed_chapters[chapter_id] = true
	var next_chapter_id: String = current_chapter.next_chapter

	print("[StoryDirector] ==== Chapter completed: %s ====" % chapter_id)
	chapter_completed.emit(chapter_id)

	current_step = null
	current_chapter = null
	_started = false

	# 自动开始下一章节
	if not next_chapter_id.is_empty():
		call_deferred("start_chapter", next_chapter_id)
	elif _has_pending_triggered_chapters():
		_request_trigger_scan()
	else:
		all_chapters_completed.emit()


# =============================================================================
# Action Executors
# =============================================================================

func _execute_action(action: Dictionary) -> void:
	var action_type: String = str(action.get("type", ""))
	match action_type:
		"activate_topic":
			_action_activate_topic(action)
		"set_activity_guidance":
			_action_set_activity_guidance(action)
		"set_app_access":
			_action_set_app_access(action)
		"set_phase":
			_action_set_phase(action)
		"modify_stats":
			_action_modify_stats(action)
		"play_avg":
			_action_play_avg(action)
		"preview_current_project":
			_action_preview_current_project(action)
		"open_browser":
			_action_open_browser(action)
		"post_moment":
			_action_post_moment(action)
		"play_transit":
			_action_play_transit(action)
		"set_variable":
			_action_set_variable(action)
		"delay":
			_action_delay(action)
		"play_bgm":
			_action_play_bgm(action)
		"stop_bgm":
			_action_stop_bgm(action)
		"launch_app":
			_action_launch_app(action)
		"install_app":
			_action_install_app(action)
		"uninstall_app":
			_action_uninstall_app(action)
		"set_desktop_app_visibility":
			_action_set_desktop_app_visibility(action)
		"close_app":
			_action_close_app(action)
		"focus_app":
			_action_focus_app(action)
		"minimize_app_window":
			_action_minimize_app_window(action)
		"lock_app_window":
			_action_lock_app_window(action)
		"unlock_app_window":
			_action_unlock_app_window(action)
		"consume_ap":
			_action_consume_ap(action)
		"set_activity_lock":
			_action_set_activity_lock(action)
		"clear_activity_lock":
			_action_clear_activity_lock(action)
		"ensure_dev_work_task":
			_action_ensure_dev_work_task(action)
		"dispatch_work_order":
			_action_dispatch_work_order(action)
		"generate_work_order":
			_action_generate_work_order(action)
		_:
			push_warning("[StoryDirector] Unknown action type: %s" % action_type)


## activate_topic — 加载预制 Topic .tres 并激活
## { "type": "activate_topic", "topic_path": "res://...", "npc_speaks_first": true, "seed_message": "" }
func _action_activate_topic(action: Dictionary) -> void:
	var topic_path: String = _interpolate(str(action.get("topic_path", "")))
	if topic_path.is_empty():
		_fail_current_step_action("[StoryDirector] activate_topic: missing topic_path")
		return

	if not ResourceLoader.exists(topic_path):
		_fail_current_step_action("[StoryDirector] activate_topic: resource not found: %s" % topic_path)
		return

	var topic: ChatTopic = load(topic_path) as ChatTopic
	if topic == null:
		_fail_current_step_action("[StoryDirector] activate_topic: failed to load: %s" % topic_path)
		return

	# 注入剧情变量到 context_data
	for key in story_variables:
		if not topic.context_data.has(key):
			topic.context_data["story_" + key] = story_variables[key]

	# 对 system_prompt 做变量替换
	topic.system_prompt = _interpolate(topic.system_prompt)
	var open_linkchat_mode: String = _resolve_linkchat_open_mode(action, topic)
	topic.context_data["linkchat_open_mode"] = open_linkchat_mode

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("activate_topic"):
		_fail_current_step_action("[StoryDirector] activate_topic: ChatManager not available")
		return

	var already_active_topic: ChatTopic = _get_active_topic_for_chat(chat, topic.channel_id)
	if already_active_topic != null and already_active_topic.topic_id == topic.topic_id:
		print("[StoryDirector] Topic already active: %s" % topic.topic_id)
		_present_linkchat_topic(already_active_topic, open_linkchat_mode)
		return

	if not _prepare_topic_channel_for_activation(chat, topic, action):
		return

	_capture_topic_message_start_index(chat, topic)

	if not chat.activate_topic(topic):
		_fail_current_step_action("[StoryDirector] activate_topic: failed to activate topic %s" % topic.topic_id)
		return

	print("[StoryDirector] Topic activated: %s" % topic.topic_id)
	_present_linkchat_topic(topic, open_linkchat_mode)

	# NPC 主动发言
	if action.get("npc_speaks_first", false):
		if _should_use_scripted_topic_delivery(action, topic) and _deliver_scripted_topic_messages(chat, topic):
			return
		var seed_msg: String = _interpolate(str(action.get("seed_message", "")))
		var auto_store: bool = bool(action.get("auto_store", false))
		var auto_complete: bool = bool(action.get("auto_complete", false))
		auto_complete = auto_complete or bool(topic.context_data.get("complete_after_first_reply", false))
		if chat.has_method("request_topic_npc_reply"):
			if not chat.request_topic_npc_reply(topic.channel_id, seed_msg, auto_store, auto_complete):
				_cancel_active_topic(chat, topic, "initial_reply_request_failed")
				_fail_current_step_action("[StoryDirector] activate_topic: failed to request initial NPC reply for %s" % topic.topic_id)


func _prepare_topic_channel_for_activation(chat: Node, topic: ChatTopic, action: Dictionary) -> bool:
	var active_topic: ChatTopic = _get_active_topic_for_chat(chat, topic.channel_id)
	if active_topic == null:
		return true

	if active_topic.topic_id == topic.topic_id:
		return true

	if not _can_supersede_active_topic(active_topic, topic, action):
		_fail_current_step_action("[StoryDirector] activate_topic: channel %s is busy with active topic %s" % [topic.channel_id, active_topic.topic_id])
		return false

	if chat.has_method("cancel_pending_ai_request"):
		chat.cancel_pending_ai_request(topic.channel_id, "superseded_by_story_topic:%s" % topic.topic_id)
	if not _cancel_active_topic(chat, active_topic, "superseded_by_story_topic:%s" % topic.topic_id):
		_fail_current_step_action("[StoryDirector] activate_topic: failed to supersede active topic %s" % active_topic.topic_id)
		return false

	print("[StoryDirector] Superseded active story topic %s with %s on %s" % [
		active_topic.topic_id,
		topic.topic_id,
		topic.channel_id,
	])
	return true


func _get_active_topic_for_chat(chat: Node, channel_id: String) -> ChatTopic:
	if chat == null or not chat.has_method("get_active_topic"):
		return null
	return chat.get_active_topic(channel_id)


func _can_supersede_active_topic(active_topic: ChatTopic, next_topic: ChatTopic, action: Dictionary) -> bool:
	if bool(action.get("supersede_active_topic", true)) == false:
		return false
	return active_topic.topic_type == "story_event" and next_topic.topic_type == "story_event"


func _cancel_active_topic(chat: Node, topic: ChatTopic, reason: String) -> bool:
	if topic == null:
		return false
	if not ("topic_manager" in chat):
		return false
	var topic_manager: Variant = chat.get("topic_manager")
	if topic_manager == null or not topic_manager.has_method("cancel_topic"):
		return false
	topic_manager.cancel_topic(topic, reason)
	return true


func _fail_current_step_action(message: String) -> void:
	_current_step_action_failed = true
	push_warning(message)


func _action_set_activity_guidance(action: Dictionary) -> void:
	var activity_type := str(action.get("activity_type", action.get("activity", ""))).strip_edges()
	if activity_type.is_empty():
		push_warning("[StoryDirector] set_activity_guidance: missing activity_type")
		return

	var prompt_text := _resolve_activity_guidance_prompt(action)
	if prompt_text.is_empty():
		push_warning("[StoryDirector] set_activity_guidance: empty prompt for activity '%s'" % activity_type)
		return

	set_activity_guidance(activity_type, prompt_text, bool(action.get("consume_once", true)))
	print("[StoryDirector] Activity guidance set: %s" % activity_type)


## set_app_access — 控制 APP 白名单/黑名单
## { "type": "set_app_access", "mode": "whitelist", "apps": ["linkchat"] }
## { "type": "set_app_access", "mode": "all" }  — 解除限制
func _resolve_linkchat_open_mode(action: Dictionary, topic: ChatTopic) -> String:
	var action_mode: String = str(action.get("open_linkchat_mode", "")).strip_edges().to_lower()
	if action_mode in ["force", "notify", "silent"]:
		return action_mode

	var topic_mode: String = str(topic.context_data.get("linkchat_open_mode", "")).strip_edges().to_lower()
	if topic_mode in ["force", "notify", "silent"]:
		return topic_mode

	if topic.topic_type == "story_event":
		return "force"
	return "notify"


func _present_linkchat_topic(topic: ChatTopic, open_mode: String) -> void:
	if open_mode != "force":
		return

	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		return

	var linkchat_window: Control = null
	if app_mgr.has_method("focus_app"):
		linkchat_window = app_mgr.focus_app("linkchat", true)
	elif app_mgr.has_method("launch_app"):
		linkchat_window = app_mgr.launch_app("linkchat", true)

	_focus_linkchat_channel(linkchat_window, topic.channel_id)


func _focus_linkchat_channel(linkchat_window: Control, channel_id: String) -> void:
	if linkchat_window == null or not is_instance_valid(linkchat_window):
		return
	if not ("content" in linkchat_window):
		return

	var content: Variant = linkchat_window.content
	if not (content is Node):
		return

	var app: Node = content as Node
	if app.has_method("open_topic_channel"):
		app.call_deferred("open_topic_channel", channel_id)
	elif app.has_method("select_channel"):
		app.call_deferred("select_channel", channel_id)


func _deliver_scripted_topic_messages(chat: Node, topic: ChatTopic) -> bool:
	var raw_messages: Variant = topic.context_data.get("scripted_npc_messages", [])
	if not (raw_messages is Array) or (raw_messages as Array).is_empty():
		return false
	if not chat.has_method("store_npc_message_data"):
		return false

	var normalized_messages: Array[Dictionary] = []
	for entry in raw_messages:
		var message_data: Dictionary = _normalize_scripted_topic_message(entry, topic)
		if message_data.is_empty():
			continue
		chat.store_npc_message_data(topic.channel_id, message_data)
		normalized_messages.append(message_data)

	if normalized_messages.is_empty():
		return false

	if bool(topic.context_data.get("scripted_complete_after_delivery", false)):
		var summary: String = str(topic.context_data.get("scripted_completion_summary", "")).strip_edges()
		if summary.is_empty():
			summary = _extract_scripted_summary(normalized_messages)
		call_deferred("_complete_story_topic_after_scripted_delivery", topic, summary, normalized_messages)

	return true


func _should_use_scripted_topic_delivery(action: Dictionary, topic: ChatTopic) -> bool:
	if bool(action.get("use_scripted_messages", false)):
		return true
	return bool(topic.context_data.get("use_scripted_messages", false))


func _normalize_scripted_topic_message(entry: Variant, topic: ChatTopic) -> Dictionary:
	if entry is String:
		var content_text := _interpolate(str(entry).strip_edges())
		if content_text.is_empty():
			return {}
		return {
			"speaker": topic.npc_id,
			"content": content_text,
		}

	if not (entry is Dictionary):
		return {}

	var raw_entry: Dictionary = entry as Dictionary
	var normalized: Dictionary = {
		"speaker": str(raw_entry.get("speaker", topic.npc_id)).strip_edges(),
		"content": _interpolate(str(raw_entry.get("content", ""))),
	}
	if normalized["speaker"] == "":
		normalized["speaker"] = topic.npc_id
	if raw_entry.has("card") and raw_entry["card"] is Dictionary:
		normalized["card"] = _interpolate_dictionary(raw_entry["card"])
	return normalized


func _complete_story_topic_after_scripted_delivery(topic: ChatTopic, summary: String, messages: Array[Dictionary]) -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		return
	if not ("topic_manager" in chat):
		return

	var active_topic: ChatTopic = null
	if chat.has_method("get_active_topic"):
		active_topic = chat.get_active_topic(topic.channel_id)
	if active_topic == null or active_topic.topic_id != topic.topic_id:
		return

	var topic_manager: Variant = chat.get("topic_manager")
	if topic_manager != null and topic_manager.has_method("complete_topic"):
		topic_manager.complete_topic(active_topic, {
			"summary": summary,
			"messages": messages,
		})


func _extract_scripted_summary(messages: Array[Dictionary]) -> String:
	for i in range(messages.size() - 1, -1, -1):
		var content_text := str(messages[i].get("content", "")).replace("[TOPIC_COMPLETE]", "").strip_edges()
		if not content_text.is_empty():
			return content_text
	return ""


func _interpolate_dictionary(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in data.keys():
		var value: Variant = data[key]
		if value is String:
			result[key] = _interpolate(str(value))
		elif value is Dictionary:
			result[key] = _interpolate_dictionary(value)
		elif value is Array:
			result[key] = _interpolate_array(value as Array)
		else:
			result[key] = value
	return result


func _interpolate_array(items: Array) -> Array:
	var result: Array = []
	for item in items:
		if item is String:
			result.append(_interpolate(str(item)))
		elif item is Dictionary:
			result.append(_interpolate_dictionary(item))
		elif item is Array:
			result.append(_interpolate_array(item as Array))
		else:
			result.append(item)
	return result


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var normalized: String = str(item).strip_edges()
			if not normalized.is_empty():
				result.append(normalized)
		return result

	var single_value: String = str(value).strip_edges()
	if single_value.is_empty():
		return result
	result.append(single_value)
	return result


func _action_set_app_access(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		push_warning("[StoryDirector] set_app_access: AppManager not available")
		return

	var mode: String = str(action.get("mode", "all"))
	var app_ids: Array[String] = _to_string_array(action.get("apps", []))

	match mode:
		"whitelist":
			if app_mgr.has_method("set_app_whitelist"):
				app_mgr.set_app_whitelist(app_ids)
				print("[StoryDirector] App whitelist set: %s" % str(app_ids))
			else:
				push_warning("[StoryDirector] set_app_access: AppManager missing set_app_whitelist()")
		"blacklist":
			if app_mgr.has_method("set_app_blacklist"):
				app_mgr.set_app_blacklist(app_ids)
				print("[StoryDirector] App blacklist set: %s" % str(app_ids))
			else:
				push_warning("[StoryDirector] set_app_access: AppManager missing set_app_blacklist()")
		"all":
			if app_mgr.has_method("clear_app_access_restriction"):
				app_mgr.clear_app_access_restriction()
				print("[StoryDirector] App access restriction cleared")
		_:
			push_warning("[StoryDirector] set_app_access: unknown mode: %s" % mode)


## set_phase — 设置天数和时段
## { "type": "set_phase", "day": 1, "phase": "MORNING" }
func _action_set_phase(action: Dictionary) -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		push_warning("[StoryDirector] set_phase: GameLoopManager not available")
		return

	if action.has("day"):
		var day: int = int(action.get("day", 1))
		if glm.has_method("set_day"):
			glm.set_day(day)
		else:
			glm.current_day = day
			_sync_day_transition_overlay(day)
			print("[StoryDirector] Set day: %d (direct)" % day)

	if action.has("phase"):
		var phase_name: String = str(action.get("phase", "MORNING")).to_upper()
		# 使用 GameLoopManager 的 TimePhase enum
		var phase_value: int = -1
		match phase_name:
			"MORNING":
				phase_value = 0
			"AFTERNOON":
				phase_value = 1
			"NIGHT":
				phase_value = 2
		if phase_value >= 0:
			glm.time_phase = phase_value
			if glm.has_signal("phase_changed"):
				glm.phase_changed.emit(phase_value)
			print("[StoryDirector] Set phase: %s" % phase_name)


func _sync_day_transition_overlay(day: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var overlay: Node = tree.get_first_node_in_group("day_transition_overlay")
	if overlay == null or not is_instance_valid(overlay):
		return
	if overlay.has_method("sync_day_baseline"):
		overlay.call("sync_day_baseline", day)


## modify_stats — 修改 GameManager 数值
## { "type": "modify_stats", "changes": { "affection": 10, "stress": -5 } }
func _action_modify_stats(action: Dictionary) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		push_warning("[StoryDirector] modify_stats: GameManager not available")
		return

	var changes: Dictionary = action.get("changes", {})
	if gm.has_method("modify_stats"):
		gm.modify_stats(changes)
	else:
		for stat_name in changes:
			var delta: int = int(changes[stat_name])
			if stat_name in gm:
				gm.set(stat_name, int(gm.get(stat_name)) + delta)
	print("[StoryDirector] Stats modified: %s" % str(changes))


## play_avg — 播放 AVG 场景
## { "type": "play_avg", "project_path": "res://...", "scene_id": "..." }
func _action_play_avg(action: Dictionary) -> void:
	var logical_scene_id := _resolve_story_avg_scene_id(action)
	if _should_generate_story_avg(action):
		_start_generated_story_avg(action, logical_scene_id)
		return
	_start_prebuilt_story_avg(action, logical_scene_id)


## preview_current_project — 打开 GamePreviewer 并自动开始试玩当前 AVG 工程
## {
##   "type": "preview_current_project",
##   "preview_id": "lin_xia_demo",
##   "scene_id": "scene_001",
##   "use_title_screen": false,
##   "window_title": "试玩林夏的 Demo"
## }
func _action_preview_current_project(action: Dictionary) -> void:
	var preview_id: String = _resolve_project_preview_id(action)
	if _project_preview_adapter != null and _project_preview_adapter.has_method("start_preview"):
		_project_preview_sessions[preview_id] = {
			"preview_id": preview_id,
			"adapter": true,
		}
		var started_via_adapter: bool = bool(_project_preview_adapter.call(
			"start_preview",
			preview_id,
			action.duplicate(true),
			Callable(self, "_on_project_preview_adapter_completed").bind(preview_id)
		))
		if not started_via_adapter:
			_finish_project_preview_session(preview_id, {
				"completed": false,
				"error": "preview_adapter_start_failed",
			})
		return

	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("launch_app"):
		push_warning("[StoryDirector] preview_current_project: AppManager not available")
		_finish_project_preview_session(preview_id, {
			"completed": false,
			"error": "app_manager_unavailable",
		})
		return

	var window: Control = app_mgr.launch_app("game_previewer", true)
	if window == null:
		push_warning("[StoryDirector] preview_current_project: failed to launch game_previewer")
		_finish_project_preview_session(preview_id, {
			"completed": false,
			"error": "game_previewer_launch_failed",
		})
		return

	var previewer: Node = _find_game_previewer_node(window)
	if previewer == null:
		push_warning("[StoryDirector] preview_current_project: GamePreviewer content not found")
		_finish_project_preview_session(preview_id, {
			"completed": false,
			"error": "game_previewer_not_found",
		})
		return

	var window_title: String = _interpolate(str(action.get("window_title", action.get("title", "")))).strip_edges()
	if not window_title.is_empty() and "window_title" in window:
		window.window_title = window_title

	var session: Dictionary = {
		"preview_id": preview_id,
		"window": window,
		"previewer": previewer,
	}
	var preview_completed_cb := Callable(self, "_on_project_preview_completed").bind(preview_id)
	if previewer.has_signal("preview_completed") and not previewer.preview_completed.is_connected(preview_completed_cb):
		previewer.preview_completed.connect(preview_completed_cb, CONNECT_ONE_SHOT)
		session["preview_completed_cb"] = preview_completed_cb
	var app_closed_cb := Callable(self, "_on_project_preview_app_closed").bind(preview_id)
	if app_mgr.has_signal("app_closed") and not app_mgr.app_closed.is_connected(app_closed_cb):
		app_mgr.app_closed.connect(app_closed_cb)
		session["app_closed_cb"] = app_closed_cb
	_project_preview_sessions[preview_id] = session

	var scene_id: String = _interpolate(str(action.get("scene_id", ""))).strip_edges()
	var use_title_screen: bool = bool(action.get("use_title_screen", false))
	if not previewer.has_method("start_story_preview"):
		_finish_project_preview_session(preview_id, {
			"completed": false,
			"error": "game_previewer_missing_start_story_preview",
		})
		return
	var started: bool = bool(previewer.call("start_story_preview", scene_id, use_title_screen))
	if not started:
		_finish_project_preview_session(preview_id, {
			"completed": false,
			"error": "game_previewer_start_failed",
		})
		return

	print("[StoryDirector] Project preview started: %s" % preview_id)


func _should_generate_story_avg(action: Dictionary) -> bool:
	return action.has("prompt") or action.has("prompt_key") or action.has("scene_prompt") or action.has("scene_prompt_key")


func _start_generated_story_avg(action: Dictionary, logical_scene_id: String) -> void:
	var prompt_text := _resolve_story_avg_prompt(action)
	if prompt_text.is_empty():
		push_warning("[StoryDirector] play_avg: empty prompt for scene '%s'" % logical_scene_id)
		_emit_story_avg_completed_deferred(logical_scene_id, {
			"success": false,
			"error": "empty_story_avg_prompt",
		})
		return

	var generator := _ensure_story_avg_generator()
	if generator == null or not generator.has_method("generate_for_session"):
		push_warning("[StoryDirector] play_avg: AVGSceneGenerator unavailable")
		_emit_story_avg_completed_deferred(logical_scene_id, {
			"success": false,
			"error": "story_avg_generator_unavailable",
		})
		return

	var session_id := _reserve_story_avg_request(logical_scene_id, action)
	_maybe_start_story_avg_generation_transit(action, session_id, logical_scene_id)
	var session := _build_story_avg_session(action, logical_scene_id, prompt_text)
	if not generator.generate_for_session(session_id, session):
		_finish_story_avg_generation_transit(session_id, true)
		_story_avg_requests.erase(session_id)
		push_warning("[StoryDirector] play_avg: failed to request generation for '%s'" % logical_scene_id)
		_emit_story_avg_completed_deferred(logical_scene_id, {
			"success": false,
			"error": "story_avg_generation_request_failed",
		})
		return

	print("[StoryDirector] Direct AVG generation requested: %s" % logical_scene_id)


func _start_prebuilt_story_avg(action: Dictionary, logical_scene_id: String) -> void:
	var session_id := _reserve_story_avg_request(logical_scene_id, action)
	var package := _build_prebuilt_story_avg_package(action, session_id)
	if package.is_empty():
		_story_avg_requests.erase(session_id)
		push_warning("[StoryDirector] play_avg: invalid prebuilt AVG package for '%s'" % logical_scene_id)
		_emit_story_avg_completed_deferred(logical_scene_id, {
			"success": false,
			"error": "invalid_story_avg_package",
		})
		return
	_open_story_avg_package(session_id, package)


func _ensure_story_avg_generator() -> Node:
	if _story_avg_generator == null or not is_instance_valid(_story_avg_generator):
		_story_avg_generator = AVGSceneGeneratorClass.new()
		_story_avg_generator.name = "StoryAVGSceneGenerator"
		add_child(_story_avg_generator)
	if _story_avg_generator.has_signal("scene_generated") and not _story_avg_generator.is_connected("scene_generated", _on_story_avg_scene_generated):
		_story_avg_generator.connect("scene_generated", _on_story_avg_scene_generated)
	if _story_avg_generator.has_signal("scene_failed") and not _story_avg_generator.is_connected("scene_failed", _on_story_avg_scene_failed):
		_story_avg_generator.connect("scene_failed", _on_story_avg_scene_failed)
	return _story_avg_generator


func _reserve_story_avg_request(logical_scene_id: String, action: Dictionary) -> String:
	_story_avg_counter += 1
	var session_id := "story_avg_%04d" % _story_avg_counter
	_story_avg_requests[session_id] = {
		"scene_id": logical_scene_id,
		"title": _resolve_story_avg_window_title(action, logical_scene_id),
	}
	return session_id


func _build_story_avg_session(action: Dictionary, logical_scene_id: String, prompt_text: String) -> Dictionary:
	var game_state := _collect_game_state()
	var phase_name := str(game_state.get("phase", "MORNING")).strip_edges().to_lower()
	var session: Dictionary = {
		"activity_type": "story",
		"entry_id": logical_scene_id,
		"session_origin": "story_director",
		"scene_window_title": _resolve_story_avg_window_title(action, logical_scene_id),
		"scene_project_prefix": _resolve_story_avg_project_prefix(action),
		"story_scene_id": logical_scene_id,
		"story_scene_title": _resolve_story_avg_window_title(action, logical_scene_id),
		"story_scene_prompt": prompt_text,
		"story_scene_preamble": _resolve_story_avg_preamble(action),
		"story_guidance_prompt": _resolve_story_avg_guidance(action),
		"include_chat_history": bool(action.get("include_chat_history", false)),
		"allow_branching": bool(action.get("allow_branching", true)),
		"start_day": int(game_state.get("day", 1)),
		"phase_after_action": phase_name,
		"start_phase": phase_name,
	}
	var trigger_context := _build_story_trigger_context_from_last_wait_payload()
	if not trigger_context.is_empty():
		session.merge(trigger_context, true)

	var preview_prompt_key := _interpolate(str(action.get("scene_preview_prompt_key", ""))).strip_edges()
	if not preview_prompt_key.is_empty():
		session["scene_preview_prompt_key"] = preview_prompt_key

	var extra_context: Variant = action.get("session_context", {})
	if extra_context is Dictionary:
		session.merge(_interpolate_dictionary(extra_context), true)

	return session


func _capture_topic_message_start_index(chat: Node, topic: ChatTopic) -> void:
	if topic.context_data.has("message_start_index"):
		return
	if chat == null or not chat.has_method("get_channel"):
		topic.context_data["message_start_index"] = 0
		return
	var channel: Resource = chat.get_channel(str(topic.channel_id))
	if channel == null or not ("messages" in channel):
		topic.context_data["message_start_index"] = 0
		return
	topic.context_data["message_start_index"] = (channel.messages as Array).size()


func _build_story_trigger_context_from_last_wait_payload() -> Dictionary:
	if _last_wait_payload.is_empty():
		return {}
	var result: Variant = _last_wait_payload.get("result", {})
	if not (result is Dictionary):
		return {}
	var result_dict: Dictionary = result as Dictionary
	var context: Dictionary = {}
	var conversation: Variant = result_dict.get("conversation_messages", [])
	if conversation is Array and not (conversation as Array).is_empty():
		context["story_trigger_conversation"] = (conversation as Array).duplicate(true)
	var player_messages: Variant = result_dict.get("player_messages", [])
	if player_messages is Array and not (player_messages as Array).is_empty():
		context["story_trigger_player_messages"] = (player_messages as Array).duplicate(true)
	var npc_messages: Variant = result_dict.get("npc_messages", [])
	if npc_messages is Array and not (npc_messages as Array).is_empty():
		context["story_trigger_npc_messages"] = (npc_messages as Array).duplicate(true)
	return context


func _build_topic_conversation_messages(topic: ChatTopic, result: Dictionary) -> Array[Dictionary]:
	var conversation: Array[Dictionary] = []
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.has_method("get_channel"):
		var channel: Resource = chat.get_channel(str(topic.channel_id))
		if channel != null and ("messages" in channel):
			var start_index: int = int(topic.context_data.get("message_start_index", 0))
			var all_messages: Array = channel.messages
			for i in range(maxi(start_index, 0), all_messages.size()):
				var entry: Variant = all_messages[i]
				if not (entry is Dictionary):
					continue
				var data: Dictionary = entry as Dictionary
				var content: String = str(data.get("content", "")).replace("[TOPIC_COMPLETE]", "").replace("[TOPIC_FAILED]", "").strip_edges()
				if content.is_empty():
					continue
				var speaker_id: String = str(data.get("speaker", data.get("sender_id", ""))).strip_edges()
				if speaker_id.is_empty():
					speaker_id = "unknown"
				var speaker_name: String = str(data.get("sender_name", data.get("speaker_name", ""))).strip_edges()
				if speaker_name.is_empty() and chat.has_method("resolve_sender_name"):
					speaker_name = str(chat.call("resolve_sender_name", speaker_id)).strip_edges()
				conversation.append({
					"speaker_id": speaker_id,
					"speaker_name": speaker_name if not speaker_name.is_empty() else speaker_id,
					"content": content,
				})
	if not conversation.is_empty():
		return conversation
	var raw_messages: Variant = result.get("messages", [])
	if raw_messages is Array:
		for raw_message in raw_messages:
			if not (raw_message is Dictionary):
				continue
			var message: Dictionary = raw_message as Dictionary
			var content: String = str(message.get("content", "")).replace("[TOPIC_COMPLETE]", "").replace("[TOPIC_FAILED]", "").strip_edges()
			if content.is_empty():
				continue
			var speaker_id: String = str(message.get("speaker", message.get("sender_id", topic.npc_id))).strip_edges()
			conversation.append({
				"speaker_id": speaker_id,
				"speaker_name": speaker_id,
				"content": content,
			})
	return conversation


func _extract_player_messages_from_conversation(conversation: Array[Dictionary]) -> Array[String]:
	var player_messages: Array[String] = []
	for entry in conversation:
		var speaker_id: String = str(entry.get("speaker_id", "")).strip_edges()
		if speaker_id != "player":
			continue
		var content: String = str(entry.get("content", "")).strip_edges()
		if not content.is_empty():
			player_messages.append(content)
	return player_messages


func _extract_npc_messages_from_conversation(topic: ChatTopic, conversation: Array[Dictionary]) -> Array[String]:
	var npc_messages: Array[String] = []
	for entry in conversation:
		var speaker_id: String = str(entry.get("speaker_id", "")).strip_edges()
		if speaker_id == "player" or speaker_id == "system":
			continue
		if not topic.npc_id.is_empty() and speaker_id != topic.npc_id:
			continue
		var content: String = str(entry.get("content", "")).strip_edges()
		if not content.is_empty():
			npc_messages.append(content)
	return npc_messages


func _build_prebuilt_story_avg_package(action: Dictionary, session_id: String) -> Dictionary:
	var project_path := _interpolate(str(action.get("project_path", ""))).strip_edges()
	if project_path.is_empty() or not ResourceLoader.exists(project_path):
		return {}

	var project: Resource = load(project_path)
	if project == null or not ("scenes" in project):
		return {}

	var target_scene_id := _interpolate(str(action.get("scene_id", ""))).strip_edges()
	var selected_scene: Resource = null
	for scene in project.scenes:
		if scene == null:
			continue
		if target_scene_id.is_empty() or str(scene.scene_id) == target_scene_id or str(scene.scene_name) == target_scene_id:
			selected_scene = scene
			break

	if selected_scene == null and project.scenes.size() > 0:
		selected_scene = project.scenes[0]
	if selected_scene == null:
		return {}

	var title := _resolve_story_avg_window_title(action, str(selected_scene.scene_name))
	return {
		"session_id": session_id,
		"title": title,
		"project": project,
		"scene": selected_scene,
		"scene_outline": AVGSceneGeneratorClass.build_narrative_outline_from_scene(selected_scene),
		"choice_labels": {},
		"choice_var_id": "var_001",
	}


func _open_story_avg_package(session_id: String, scene_package: Dictionary) -> void:
	var request: Dictionary = _story_avg_requests.get(session_id, {}).duplicate(true)
	if request.is_empty():
		return

	_update_story_avg_generation_transit(session_id, 0.92)
	var result := _open_story_avg_window(
		str(request.get("title", scene_package.get("title", "剧情事件"))),
		scene_package,
		Callable(self, "_on_story_avg_playback_finished")
	)
	if result.is_empty():
		_finish_story_avg_generation_transit(session_id, true)
		_finish_story_avg_request(session_id, {
			"success": false,
			"error": "story_avg_window_open_failed",
		})
		return

	_finish_story_avg_generation_transit(session_id)
	request["scene_package"] = scene_package.duplicate(true)
	request["window"] = result.get("window", null)
	_story_avg_requests[session_id] = request
	print("[StoryDirector] Direct AVG playback started: %s" % str(request.get("scene_id", session_id)))


func _open_story_avg_window(title: String, scene_package: Dictionary, playback_callback: Callable) -> Dictionary:
	if _story_avg_scene_adapter != null and _story_avg_scene_adapter.has_method("open"):
		return _story_avg_scene_adapter.call("open", title, scene_package, playback_callback)
	return SceneWindowClass.open(title, scene_package, playback_callback)


func _on_story_avg_scene_generated(session_id: String, package: Dictionary) -> void:
	if not _story_avg_requests.has(session_id):
		return
	_update_story_avg_generation_transit(session_id, 0.72)
	var request: Dictionary = _story_avg_requests.get(session_id, {})
	var package_dup := package.duplicate(true)
	if request.has("title"):
		package_dup["title"] = str(request.get("title", package_dup.get("title", "剧情事件")))
	_open_story_avg_package(session_id, package_dup)


func _on_story_avg_scene_failed(session_id: String, error: String) -> void:
	if not _story_avg_requests.has(session_id):
		return
	_finish_story_avg_generation_transit(session_id, true)
	_finish_story_avg_request(session_id, {
		"success": false,
		"error": error,
	})


func _on_story_avg_playback_finished(session_id: String, outcome: Dictionary) -> void:
	if not _story_avg_requests.has(session_id):
		return
	_finish_story_avg_request(session_id, outcome)


func _finish_story_avg_request(session_id: String, outcome: Dictionary) -> void:
	var request: Dictionary = _story_avg_requests.get(session_id, {}).duplicate(true)
	_story_avg_requests.erase(session_id)
	if request.is_empty():
		return

	var logical_scene_id := str(request.get("scene_id", session_id)).strip_edges()
	var normalized_outcome := outcome.duplicate(true)
	normalized_outcome["session_id"] = session_id
	normalized_outcome["scene_id"] = logical_scene_id
	_emit_story_avg_completed_deferred(logical_scene_id, normalized_outcome)


func _emit_story_avg_completed_deferred(scene_id: String, outcome: Dictionary) -> void:
	call_deferred("emit_signal", "avg_scene_ended", scene_id, outcome)


func _resolve_story_avg_scene_id(action: Dictionary) -> String:
	var explicit_id: String = _interpolate(str(action.get("scene_id", ""))).strip_edges()
	if not explicit_id.is_empty():
		return explicit_id
	var chapter_id: String = current_chapter.chapter_id if current_chapter != null else "story"
	var step_id: String = current_step.step_id if current_step != null else "step"
	return "%s_%s" % [chapter_id, step_id]


func _resolve_story_avg_window_title(action: Dictionary, fallback: String) -> String:
	var title: String = _interpolate(str(action.get("window_title", action.get("title", "")))).strip_edges()
	if title.is_empty() and current_step != null:
		title = current_step.description.strip_edges()
	if title.is_empty():
		title = fallback
	return title


func _resolve_story_avg_project_prefix(action: Dictionary) -> String:
	var prefix: String = _interpolate(str(action.get("scene_project_prefix", "story_scene"))).strip_edges()
	if prefix.is_empty():
		return "story_scene"
	return prefix


func _resolve_story_avg_prompt(action: Dictionary) -> String:
	return _resolve_action_prompt(action, ["prompt_key", "scene_prompt_key"], ["prompt", "scene_prompt"])


func _resolve_story_avg_guidance(action: Dictionary) -> String:
	return _resolve_action_prompt(action, ["guidance_prompt_key"], ["guidance_prompt"])


func _resolve_project_preview_id(action: Dictionary) -> String:
	var explicit_id: String = _interpolate(str(action.get("preview_id", action.get("session_id", "")))).strip_edges()
	if not explicit_id.is_empty():
		return explicit_id
	var chapter_id: String = current_chapter.chapter_id if current_chapter != null else "story"
	var step_id: String = current_step.step_id if current_step != null else "preview"
	return "%s_%s_preview" % [chapter_id, step_id]


func _find_game_previewer_node(window: Control) -> Node:
	if window == null or not is_instance_valid(window):
		return null
	if "content" in window:
		var root_content: Variant = window.get("content")
		if root_content is Node and (root_content as Node).has_method("start_story_preview"):
			return root_content as Node
	for child in window.get_children():
		if child is Node:
			var result: Node = _find_game_previewer_node(child)
			if result != null:
				return result
	return null


func _on_project_preview_completed(payload: Dictionary, preview_id: String) -> void:
	var normalized_payload: Dictionary = payload.duplicate(true)
	normalized_payload["completed"] = bool(normalized_payload.get("completed", true))
	_finish_project_preview_session(preview_id, normalized_payload)


func _on_project_preview_adapter_completed(payload: Dictionary, preview_id: String) -> void:
	_on_project_preview_completed(payload, preview_id)


func _on_project_preview_app_closed(app_id: String, preview_id: String) -> void:
	if app_id != "game_previewer":
		return
	if not _project_preview_sessions.has(preview_id):
		return
	_finish_project_preview_session(preview_id, {
		"completed": false,
		"closed": true,
		"end_reason": "closed",
	})


func _finish_project_preview_session(preview_id: String, payload: Dictionary) -> void:
	var session: Dictionary = _project_preview_sessions.get(preview_id, {}).duplicate(true)
	if not session.is_empty():
		var app_mgr: Node = get_node_or_null("/root/AppManager")
		var app_closed_cb: Variant = session.get("app_closed_cb", null)
		if app_mgr != null and app_closed_cb is Callable and app_mgr.has_signal("app_closed") and app_mgr.app_closed.is_connected(app_closed_cb):
			app_mgr.app_closed.disconnect(app_closed_cb)
	_project_preview_sessions.erase(preview_id)
	call_deferred("emit_signal", "project_preview_finished", preview_id, payload.duplicate(true))


func _resolve_story_avg_preamble(action: Dictionary) -> String:
	return _resolve_action_prompt(action, ["preamble_key"], ["preamble"])


func _maybe_start_story_avg_generation_transit(action: Dictionary, session_id: String, logical_scene_id: String) -> void:
	if not bool(action.get("show_generation_transit", true)):
		return

	var transit: Node = get_node_or_null("/root/TransitManager")
	if transit == null or not transit.has_method("play_transit"):
		return

	var request: Dictionary = _story_avg_requests.get(session_id, {}).duplicate(true)
	if request.is_empty():
		return

	var transit_id := "story_avg_generation_%s" % session_id
	transit.call("play_transit", {
		"id": transit_id,
		"source": "story_director",
		"window_title": _resolve_story_avg_generation_transit_window_title(action),
		"title": _resolve_story_avg_generation_transit_title(action, logical_scene_id),
		"stages": _resolve_story_avg_generation_transit_stages(action),
		"icon": _interpolate(str(action.get("generation_transit_icon", "•"))).strip_edges(),
		"accent_color": _interpolate(str(action.get("generation_transit_accent_color", "#8FA5FF"))).strip_edges(),
		"bg_color": _interpolate(str(action.get("generation_transit_bg_color", "#FFFFFF"))).strip_edges(),
		"text_color": _interpolate(str(action.get("generation_transit_text_color", "#202124"))).strip_edges(),
		"subtext_color": _interpolate(str(action.get("generation_transit_subtext_color", "#5F6368"))).strip_edges(),
		"eta_active": _interpolate(str(action.get("generation_transit_eta_active", "生成中..."))).strip_edges(),
		"eta_done": _interpolate(str(action.get("generation_transit_eta_done", "即将打开"))).strip_edges(),
		"progress": 0.08,
	})
	request["generation_transit_id"] = transit_id
	_story_avg_requests[session_id] = request


func _update_story_avg_generation_transit(session_id: String, progress: float) -> void:
	var request: Dictionary = _story_avg_requests.get(session_id, {})
	var transit_id: String = str(request.get("generation_transit_id", "")).strip_edges()
	if transit_id.is_empty():
		return

	var transit: Node = get_node_or_null("/root/TransitManager")
	if transit == null or not transit.has_method("update_transit"):
		return

	transit.call("update_transit", transit_id, progress)


func _finish_story_avg_generation_transit(session_id: String, cancel: bool = false) -> void:
	var request: Dictionary = _story_avg_requests.get(session_id, {}).duplicate(true)
	var transit_id: String = str(request.get("generation_transit_id", "")).strip_edges()
	if transit_id.is_empty():
		return

	request.erase("generation_transit_id")
	_story_avg_requests[session_id] = request

	var transit: Node = get_node_or_null("/root/TransitManager")
	if transit == null:
		return
	if cancel and transit.has_method("cancel_transit"):
		transit.call("cancel_transit", transit_id)
		return
	if transit.has_method("finish_transit"):
		transit.call("finish_transit", transit_id)


func _resolve_story_avg_generation_transit_window_title(action: Dictionary) -> String:
	var title := _interpolate(str(action.get("generation_transit_window_title", "剧情生成中"))).strip_edges()
	if title.is_empty():
		return "剧情生成中"
	return title


func _resolve_story_avg_generation_transit_title(action: Dictionary, logical_scene_id: String) -> String:
	var title := _interpolate(str(action.get("generation_transit_title", ""))).strip_edges()
	if title.is_empty():
		title = _resolve_story_avg_window_title(action, logical_scene_id)
	if title.is_empty():
		title = "剧情生成中"
	return title


func _resolve_story_avg_generation_transit_stages(action: Dictionary) -> Array[String]:
	var raw_stages: Variant = action.get("generation_transit_stages", [])
	var stages: Array[String] = []
	if raw_stages is Array:
		for item in raw_stages:
			var text: String = _interpolate(str(item)).strip_edges()
			if not text.is_empty():
				stages.append(text)
	elif raw_stages is String:
		var text := _interpolate(str(raw_stages)).strip_edges()
		if not text.is_empty():
			stages.append(text)
	if stages.is_empty():
		return STORY_AVG_GENERATION_TRANSIT_STAGES.duplicate()
	return stages


## open_browser — 请求打开浏览器页面
## { "type": "open_browser", "url": "gamejam://signup" }
func _action_open_browser(action: Dictionary) -> void:
	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser == null:
		push_warning("[StoryDirector] open_browser: BrowserManager not available")
		return

	var url: String = _interpolate(str(action.get("url", "")))
	var design_prompt: String = _interpolate(str(action.get("design_prompt", "")))
	var page_context: String = _interpolate(str(action.get("page_context", "")))

	if browser.has_method("request_open_url"):
		browser.request_open_url(url, design_prompt, page_context)
		print("[StoryDirector] Browser open requested: %s" % url)


## post_moment — 发朋友圈
## { "type": "post_moment", "npc_id": "npc_lin_xia", "content": "...", "image_hint": "" }
func _action_post_moment(action: Dictionary) -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("post_moment"):
		push_warning("[StoryDirector] post_moment: ChatManager not available")
		return

	var npc_id: String = str(action.get("npc_id", "npc_lin_xia"))
	var content: String = _interpolate(str(action.get("content", "")))
	var image_hint: String = str(action.get("image_hint", ""))
	chat.post_moment(npc_id, content, image_hint)
	print("[StoryDirector] Moment posted by %s" % npc_id)


## play_transit — 播放一个独立于 App 的全局 transit 演出
## { "type": "play_transit", "id": "story_walk_home", "title": "回家路上",
##   "window_title": "转场", "stages": ["路灯亮起", "风有点凉", "快到了"],
##   "duration": 4.0, "icon": "•", "accent_color": "#8FA5FF" }
func _action_play_transit(action: Dictionary) -> void:
	var transit: Node = get_node_or_null("/root/TransitManager")
	if transit == null or not transit.has_method("play_timed_transit"):
		push_warning("[StoryDirector] play_transit: TransitManager not available")
		return

	var request: Dictionary = {
		"id": _interpolate(str(action.get("id", ""))),
		"source": "story_director",
		"window_title": _interpolate(str(action.get("window_title", "转场"))),
		"title": _interpolate(str(action.get("title", "进行中"))),
		"duration": float(action.get("duration", 3.0)),
		"icon": _interpolate(str(action.get("icon", "•"))),
		"accent_color": _interpolate(str(action.get("accent_color", "#8FA5FF"))),
		"bg_color": _interpolate(str(action.get("bg_color", "#FFFFFF"))),
		"text_color": _interpolate(str(action.get("text_color", "#202124"))),
		"subtext_color": _interpolate(str(action.get("subtext_color", "#5F6368"))),
		"eta_active": _interpolate(str(action.get("eta_active", "进行中..."))),
		"eta_done": _interpolate(str(action.get("eta_done", "即将完成"))),
	}
	var stages: Array[String] = []
	var raw_stages: Variant = action.get("stages", [])
	if raw_stages is Array:
		for item in raw_stages:
			var text: String = _interpolate(str(item)).strip_edges()
			if not text.is_empty():
				stages.append(text)
	request["stages"] = stages

	transit.play_timed_transit(request)
	print("[StoryDirector] Transit started: %s" % str(request.get("id", "")))


## set_variable — 设置剧情变量
## { "type": "set_variable", "key": "team_name", "value": "..." }
func _action_set_variable(action: Dictionary) -> void:
	var key: String = str(action.get("key", ""))
	var value: Variant = action.get("value", "")
	if not key.is_empty():
		set_variable(key, value)
		print("[StoryDirector] Variable set: %s = %s" % [key, str(value)])


## delay — 延迟后自动推进（仅当 wait_for 为 immediate 时有意义）
## { "type": "delay", "seconds": 2.0 }
func _action_delay(action: Dictionary) -> void:
	var seconds: float = float(action.get("seconds", 1.0))
	_delay_timer.wait_time = seconds
	_delay_timer.start()
	await _delay_timer.timeout


## play_bgm — 播放背景音乐
## { "type": "play_bgm", "path": "res://Assets/sounds/bgm/Blush (loop).ogg", "crossfade": 1.0 }
func _action_play_bgm(action: Dictionary) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play_bgm"):
		push_warning("[StoryDirector] play_bgm: AudioManager not available")
		return
	var path: String = _interpolate(str(action.get("path", "")))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("[StoryDirector] play_bgm: invalid path: %s" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("[StoryDirector] play_bgm: failed to load: %s" % path)
		return
	var crossfade: float = float(action.get("crossfade", 1.0))
	audio.play_bgm(stream, crossfade)
	print("[StoryDirector] BGM started: %s" % path)


## stop_bgm — 停止背景音乐
## { "type": "stop_bgm", "fade": 0.5 }
func _action_stop_bgm(action: Dictionary) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("stop_bgm"):
		return
	var fade: float = float(action.get("fade", 0.5))
	audio.stop_bgm(fade)
	print("[StoryDirector] BGM stopped")


## launch_app — 启动指定 APP
## { "type": "launch_app", "app_id": "browser" }
func _action_launch_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("launch_app"):
		return
	var app_id: String = str(action.get("app_id", ""))
	var force_launch: bool = bool(action.get("force", false))
	if not app_id.is_empty():
		app_mgr.launch_app(app_id, force_launch)
		print("[StoryDirector] App launched: %s" % app_id)


## install_app — 运行时安装/注册 APP，并可选择显示桌面图标或直接打开
## { "type": "install_app", "resource_path": "res://resources/apps/scene_editor_app.tres",
##   "show_on_desktop": true, "launch": false }
func _action_install_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		push_warning("[StoryDirector] install_app: AppManager not available")
		return

	var resource_path: String = _interpolate(str(action.get("resource_path", ""))).strip_edges()
	var app_id: String = str(action.get("app_id", "")).strip_edges()

	if not resource_path.is_empty():
		if not app_mgr.has_method("install_app_from_path") or not bool(app_mgr.install_app_from_path(resource_path)):
			push_warning("[StoryDirector] install_app: failed to install %s" % resource_path)
			return
		if app_id.is_empty() and app_mgr.has_method("get_registered_apps"):
			for definition in app_mgr.get_registered_apps():
				if definition != null and str(definition.resource_path) == resource_path:
					app_id = str(definition.app_id).strip_edges()
					break
	elif not app_id.is_empty():
		if app_mgr.has_method("is_app_registered") and not bool(app_mgr.is_app_registered(app_id)):
			push_warning("[StoryDirector] install_app: app '%s' is not registered and no resource_path was provided" % app_id)
			return
	else:
		push_warning("[StoryDirector] install_app: missing resource_path/app_id")
		return

	if app_id.is_empty():
		push_warning("[StoryDirector] install_app: could not resolve app_id")
		return

	if action.has("show_on_desktop") and app_mgr.has_method("set_app_desktop_visible"):
		app_mgr.set_app_desktop_visible(app_id, bool(action.get("show_on_desktop", true)))

	if bool(action.get("launch", false)) and app_mgr.has_method("launch_app"):
		app_mgr.launch_app(app_id, bool(action.get("force_launch", true)))

	print("[StoryDirector] App installed: %s" % app_id)


## uninstall_app — 运行时卸载/移除 APP
## { "type": "uninstall_app", "app_id": "scene_editor", "close_running": true }
func _action_uninstall_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("unregister_app"):
		push_warning("[StoryDirector] uninstall_app: AppManager not available")
		return

	var app_id: String = str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		push_warning("[StoryDirector] uninstall_app: missing app_id")
		return

	app_mgr.unregister_app(app_id, bool(action.get("close_running", true)))
	print("[StoryDirector] App uninstalled: %s" % app_id)


## set_desktop_app_visibility — 控制指定 APP 桌面图标显隐
## { "type": "set_desktop_app_visibility", "app_id": "scene_editor", "visible": true }
func _action_set_desktop_app_visibility(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("set_app_desktop_visible"):
		push_warning("[StoryDirector] set_desktop_app_visibility: AppManager not available")
		return

	var app_id: String = str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		push_warning("[StoryDirector] set_desktop_app_visibility: missing app_id")
		return

	app_mgr.set_app_desktop_visible(app_id, bool(action.get("visible", true)))
	print("[StoryDirector] Desktop app visibility changed: %s -> %s" % [app_id, str(bool(action.get("visible", true)))])


## close_app — 关闭指定 APP
## { "type": "close_app", "app_id": "browser" }
func _action_close_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("close_app"):
		return
	var app_id: String = str(action.get("app_id", ""))
	var force_close: bool = bool(action.get("force", false))
	if not app_id.is_empty():
		app_mgr.close_app(app_id, force_close)
		print("[StoryDirector] App closed: %s" % app_id)


func _action_focus_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("focus_app"):
		return
	var app_id: String = str(action.get("app_id", ""))
	var force_launch: bool = bool(action.get("force_launch", true))
	if not app_id.is_empty():
		app_mgr.focus_app(app_id, force_launch)
		print("[StoryDirector] App focused: %s" % app_id)


## minimize_app_window — 最小化指定 APP 窗口
## { "type": "minimize_app_window", "app_id": "avg_player" }
func _action_minimize_app_window(action: Dictionary) -> void:
	var app_id: String = _interpolate(str(action.get("app_id", SceneWindowClass.APP_ID))).strip_edges()
	if app_id.is_empty():
		push_warning("[StoryDirector] minimize_app_window: missing app_id")
		return

	if app_id == SceneWindowClass.APP_ID and _story_avg_scene_adapter != null and _story_avg_scene_adapter.has_method("minimize"):
		_story_avg_scene_adapter.call("minimize")
		print("[StoryDirector] App window minimized: %s" % app_id)
		return

	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("get_app_window"):
		push_warning("[StoryDirector] minimize_app_window: AppManager not available")
		return

	var window: Control = app_mgr.get_app_window(app_id)
	if window == null or not is_instance_valid(window):
		if not bool(action.get("ignore_missing", true)):
			push_warning("[StoryDirector] minimize_app_window: app not running: %s" % app_id)
		return

	if "is_minimized" in window and window.is_minimized:
		return

	if app_mgr.has_method("unlock_app_window"):
		app_mgr.unlock_app_window(app_id)

	var window_manager: Node = app_mgr.window_manager
	if window_manager != null and window_manager.has_method("minimize_window_with_callback"):
		window_manager.minimize_window_with_callback(window)
		print("[StoryDirector] App window minimized: %s" % app_id)
		return
	if window_manager != null and window_manager.has_method("minimize_window"):
		window_manager.minimize_window(window)
		print("[StoryDirector] App window minimized: %s" % app_id)
		return
	if window.has_method("minimize"):
		window.minimize()
		print("[StoryDirector] App window minimized: %s" % app_id)
		return

	push_warning("[StoryDirector] minimize_app_window: no minimize path for %s" % app_id)


func _action_lock_app_window(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("lock_app_window"):
		return
	var app_id: String = str(action.get("app_id", ""))
	if app_id.is_empty():
		return
	var lock_close: bool = bool(action.get("close_locked", true))
	var lock_minimize: bool = bool(action.get("minimize_locked", true))
	app_mgr.lock_app_window(app_id, lock_close, lock_minimize)
	if bool(action.get("focus", true)) and app_mgr.has_method("focus_app"):
		app_mgr.focus_app(app_id, false)
	print("[StoryDirector] App window locked: %s" % app_id)


func _action_unlock_app_window(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("unlock_app_window"):
		return
	var app_id: String = str(action.get("app_id", ""))
	if app_id.is_empty():
		return
	app_mgr.unlock_app_window(app_id)
	print("[StoryDirector] App window unlocked: %s" % app_id)


## consume_ap — 消耗行动力
## { "type": "consume_ap", "amount": 1, "action_type": "story", "detail": "sleep_invite" }
func _action_consume_ap(action: Dictionary) -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.has_method("consume_ap"):
		push_warning("[StoryDirector] consume_ap: GameLoopManager not available")
		return

	var raw_amount: Variant = action.get("amount", action.get("ap", action.get("ap_cost", 1)))
	var amount: int = 1
	if raw_amount is String:
		amount = int(_interpolate(str(raw_amount)).strip_edges())
	else:
		amount = int(raw_amount)
	if amount <= 0:
		push_warning("[StoryDirector] consume_ap: amount must be > 0")
		return

	var action_type: String = _interpolate(str(action.get("action_type", "story"))).strip_edges()
	if action_type.is_empty():
		action_type = "story"
	var detail: String = _interpolate(str(action.get("detail", current_step.step_id if current_step != null else "story"))).strip_edges()
	var consumed: bool = bool(glm.call("consume_ap", amount, action_type, detail))
	if not consumed:
		push_warning("[StoryDirector] consume_ap: failed to consume %d AP for %s" % [amount, detail])
		return

	print("[StoryDirector] Consumed AP: %d (%s / %s)" % [amount, action_type, detail])


## set_activity_lock — 叙事活动锁，按活动类型选择性禁用
## { "type": "set_activity_lock", "mode": "blacklist", "activities": ["date", "part_time", "gift"], "reason": "先把报名搞定" }
## { "type": "set_activity_lock", "mode": "whitelist", "activities": ["chat_casual", "rest"], "reason": "今天只能待在家里" }
## { "type": "set_activity_lock", "mode": "blacklist", "activities": ["browser", "follow_contest"], "reason": "先别分心发帖了" }
func _action_set_activity_lock(action: Dictionary) -> void:
	var mode: String = str(action.get("mode", "blacklist")).strip_edges().to_lower()
	var raw_activities: Variant = action.get("activities", [])
	var activities: Array[String] = []
	if raw_activities is Array:
		for a in raw_activities:
			var s: String = str(a).strip_edges()
			if not s.is_empty():
				activities.append(s)
	var reason: String = _interpolate(str(action.get("reason", "")))
	ActivityLockUtilsClass.set_narrative_lock(mode, activities, reason)
	print("[StoryDirector] Activity lock set: mode=%s, activities=%s" % [mode, str(activities)])


## clear_activity_lock — 解除叙事活动锁
## { "type": "clear_activity_lock" }
func _action_clear_activity_lock(_action: Dictionary) -> void:
	ActivityLockUtilsClass.clear_narrative_lock()
	print("[StoryDirector] Activity lock cleared")


## ensure_dev_work_task — 确保一项剧情安排的 Dev Work 已加入任务池
## { "type": "ensure_dev_work_task", "template_path": "res://resources/dev_work/story_tasks/day1_creative_brief.json" }
func _action_ensure_dev_work_task(action: Dictionary) -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or not dcm.has_method("add_dynamic_task"):
		push_warning("[StoryDirector] ensure_dev_work_task: DevCycleManager not available")
		return

	var task: Dictionary = {}
	var template_path := _interpolate(str(action.get("template_path", ""))).strip_edges()
	if not template_path.is_empty():
		task = _load_dev_work_task_template(template_path)
	if task.is_empty():
		push_warning("[StoryDirector] ensure_dev_work_task: empty task template")
		return

	task = _interpolate_dictionary(task)
	var task_id := str(task.get("task_id", "")).strip_edges()
	if task_id.is_empty():
		push_warning("[StoryDirector] ensure_dev_work_task: task_id missing")
		return

	if dcm.has_method("get_task"):
		var existing: Dictionary = dcm.get_task(task_id)
		if not existing.is_empty():
			print("[StoryDirector] Dev Work task already exists: %s" % task_id)
			return

	var added_id := str(dcm.add_dynamic_task(task))
	if added_id.is_empty():
		push_warning("[StoryDirector] ensure_dev_work_task: failed to add task %s" % task_id)
	else:
		print("[StoryDirector] Dev Work task ensured: %s" % added_id)


func _load_dev_work_task_template(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[StoryDirector] Dev Work task template not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[StoryDirector] Failed to open Dev Work task template: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	push_warning("[StoryDirector] Invalid Dev Work task template JSON: %s" % path)
	return {}


## dispatch_work_order — 直接创建并派发工单
## { "type": "dispatch_work_order", "title": "...", "description": "...",
##   "priority": 2, "save_order_id": "var_name" }
func _action_dispatch_work_order(action: Dictionary) -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[StoryDirector] dispatch_work_order: WorkOrderManager not found")
		return

	var order_title: String = _interpolate(str(action.get("title", "")))
	var order_desc: String = _interpolate(str(action.get("description", "")))
	if order_title.is_empty():
		push_warning("[StoryDirector] dispatch_work_order: missing title")
		return

	var order: Resource = wom.create_order(order_title, order_desc, {
		"source_type": "story_event",
		"source_id": str(action.get("id", "")),
	})
	order.priority = int(action.get("priority", 2))

	var save_var: String = str(action.get("save_order_id", ""))
	if not save_var.is_empty():
		set_variable(save_var, order.id)

	var dispatched: bool = wom.dispatch_order(order.id)
	if dispatched:
		print("[StoryDirector] Work order dispatched: %s (%s)" % [order.id, order_title])
	else:
		push_warning("[StoryDirector] dispatch_work_order: failed to dispatch %s" % order.id)


## generate_work_order — 通过 LLM 生成工单内容后自动派发
## { "type": "generate_work_order", "prompt": "...",
##   "priority": 2, "role": "work_order",
##   "save_order_id": "var_name" }
func _action_generate_work_order(action: Dictionary) -> void:
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[StoryDirector] generate_work_order: WorkOrderManager not found")
		return

	var user_prompt: String = _interpolate(str(action.get("prompt", "")))
	if user_prompt.is_empty():
		push_warning("[StoryDirector] generate_work_order: missing prompt")
		return

	# 收集 KB 摘要作为上下文
	var kb_context: String = _build_kb_context_for_generation()

	var system_prompt: String = _resolve_prompt_template(
		"work_order_generation_system",
		{"kb_context": kb_context},
		"你是游戏开发项目的任务拆解助手。只输出 JSON：{\"title\":\"工单标题\",\"description\":\"详细需求\"}\n\n当前项目知识库摘要：\n%s" % kb_context
	)

	# 创建一次性 AIService
	var ai: AIService = AIService.new()
	ai.name = "StoryDirectorGenWO"
	var role_name: String = str(action.get("role", "work_order"))
	add_child(ai)
	AIConfigManager.get_instance().apply_to_service(ai, role_name)

	var priority: int = int(action.get("priority", 2))
	var save_var: String = str(action.get("save_order_id", ""))

	# 异步回调
	ai.request_completed.connect(
		func(_request_id: String, response: Dictionary) -> void:
			_on_generate_work_order_completed(response, wom, priority, save_var)
			ai.queue_free()
	)
	ai.request_failed.connect(
		func(_request_id: String, error: String, _error_code: int) -> void:
			push_warning("[StoryDirector] generate_work_order LLM failed: %s" % error)
			ai.queue_free()
	)

	ai.chat_simple(user_prompt, system_prompt)


func _on_generate_work_order_completed(response: Dictionary, wom: Node, priority: int, save_var: String) -> void:
	var content: String = ""
	var choices: Array = response.get("choices", [])
	if choices.size() > 0:
		content = str(choices[0].get("message", {}).get("content", ""))

	if content.is_empty():
		push_warning("[StoryDirector] generate_work_order: empty LLM response")
		return

	# 清理 markdown 包裹
	content = content.strip_edges()
	if content.begins_with("```"):
		var first_nl: int = content.find("\n")
		if first_nl >= 0:
			content = content.substr(first_nl + 1)
		if content.ends_with("```"):
			content = content.substr(0, content.length() - 3).strip_edges()

	var json := JSON.new()
	if json.parse(content) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[StoryDirector] generate_work_order: failed to parse LLM JSON: %s" % content)
		return

	var data: Dictionary = json.data
	var title: String = str(data.get("title", ""))
	var desc: String = str(data.get("description", ""))
	if title.is_empty():
		push_warning("[StoryDirector] generate_work_order: LLM returned empty title")
		return

	var order: Resource = wom.create_order(title, desc, {
		"source_type": "story_event",
		"source_id": "generated",
	})
	order.priority = priority

	if not save_var.is_empty():
		set_variable(save_var, order.id)

	var dispatched: bool = wom.dispatch_order(order.id)
	if dispatched:
		print("[StoryDirector] Generated work order dispatched: %s (%s)" % [order.id, title])
	else:
		push_warning("[StoryDirector] generate_work_order: failed to dispatch %s" % order.id)


func _build_kb_context_for_generation() -> String:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		return "(知识库不可用)"
	var docs: Array = kb.get_documents()
	if docs.is_empty():
		return "(知识库为空)"
	var lines: PackedStringArray = []
	for doc in docs:
		lines.append("- [%s] %s: %s" % [
			str(doc.get("category", "")),
			str(doc.get("title", "")),
			str(doc.get("content", "")).left(100),
		])
	return "\n".join(lines)


# =============================================================================
# Wait System
# =============================================================================

func _setup_wait(wait: Dictionary) -> void:
	var wait_type: String = str(wait.get("type", ""))
	match wait_type:
		"topic_completed":
			_wait_on_signal("/root/ChatManager", "topic_completed", _on_wait_topic_completed)
		"url_opened":
			_wait_on_signal("/root/BrowserManager", "url_open_requested", _on_wait_url_opened)
		"app_opened":
			_wait_on_signal("/root/AppManager", "app_launched", _on_wait_app_opened)
		"date_started":
			_wait_on_signal("/root/DateManager", "date_started", _on_wait_date_started)
		"date_completed":
			_wait_on_signal("/root/DateManager", "date_completed", _on_wait_date_completed)
		"home_activity_started":
			_wait_on_signal("/root/HomeActivityManager", "activity_started", _on_wait_home_activity_started)
		"home_activity_completed":
			_wait_on_signal("/root/HomeActivityManager", "activity_completed", _on_wait_home_activity_completed)
		"avg_scene_ended":
			avg_scene_ended.connect(_on_wait_avg_scene_ended)
			_wait_connections.append({"signal": "avg_scene_ended", "callable": _on_wait_avg_scene_ended, "self": true})
		"project_preview_finished":
			project_preview_finished.connect(_on_wait_project_preview_finished)
			_wait_connections.append({"signal": "project_preview_finished", "callable": _on_wait_project_preview_finished, "self": true})
		"sbeam_completed":
			_wait_on_signal("/root/SbeamManager", "play_session_completed", _on_wait_sbeam_completed)
		"transit_completed":
			_wait_on_signal("/root/TransitManager", "transit_finished", _on_wait_transit_completed)
		"phase_reached":
			_wait_on_signal("/root/GameLoopManager", "phase_changed", _on_wait_phase_reached)
		"day_reached":
			_wait_on_signal("/root/GameLoopManager", "day_changed", _on_wait_day_reached)
		"variable_equals":
			# 由 set_variable / notify_condition_met 触发
			story_variable_changed.connect(_on_wait_variable_changed)
			_wait_connections.append({"signal": "story_variable_changed", "callable": _on_wait_variable_changed, "self": true})
		"work_order_completed":
			_wait_on_signal("/root/WorkOrderManager", "order_status_changed", _on_wait_work_order_completed)
		"work_order_dispatched":
			_wait_on_signal("/root/WorkOrderManager", "order_dispatched", _on_wait_work_order_dispatched)
		"dev_task_completed":
			if _is_expected_dev_task_completed():
				call_deferred("_on_wait_satisfied", {"already_completed": true})
			else:
				_wait_on_signal("/root/DevCycleManager", "task_status_changed", _on_wait_dev_task_completed)
		_:
			push_warning("[StoryDirector] Unknown wait type: %s" % wait_type)


func _wait_on_signal(node_path: String, signal_name: String, callback: Callable) -> void:
	var node: Node = get_node_or_null(node_path)
	if node == null:
		push_warning("[StoryDirector] Wait target not found: %s" % node_path)
		return
	if not node.has_signal(signal_name):
		push_warning("[StoryDirector] Signal not found: %s.%s" % [node_path, signal_name])
		return
	node.connect(signal_name, callback)
	_wait_connections.append({"node_path": node_path, "signal": signal_name, "callable": callback})


## 动态查找拥有指定信号的节点（用于 AVGSceneRunner 等非固定路径节点）
func _wait_on_signal_dynamic(signal_name: String, callback: Callable) -> void:
	# AVGSceneRunner 可能在不同位置，通过 group 或遍历查找
	var runners: Array[Node] = get_tree().get_nodes_in_group("avg_scene_runner")
	for runner in runners:
		if runner.has_signal(signal_name):
			runner.connect(signal_name, callback)
			_wait_connections.append({"node": runner, "signal": signal_name, "callable": callback})
			return
	push_warning("[StoryDirector] No node found with signal: %s" % signal_name)


func _disconnect_all_waits() -> void:
	for conn in _wait_connections:
		if conn.get("self", false):
			var sig_name: String = conn.get("signal", "")
			var cb: Callable = conn.get("callable")
			if cb != null and is_connected(sig_name, cb):
				disconnect(sig_name, cb)
		elif conn.has("node"):
			var node: Node = conn.get("node")
			if is_instance_valid(node) and node.is_connected(conn.get("signal", ""), conn.get("callable")):
				node.disconnect(conn.get("signal", ""), conn.get("callable"))
		elif conn.has("node_path"):
			var node: Node = get_node_or_null(conn.get("node_path", ""))
			if node != null and node.is_connected(conn.get("signal", ""), conn.get("callable")):
				node.disconnect(conn.get("signal", ""), conn.get("callable"))
	_wait_connections.clear()


# =============================================================================
# Wait Callbacks
# =============================================================================

func _on_wait_satisfied(data: Dictionary = {}) -> void:
	if not _waiting or current_step == null:
		return
	_waiting = false
	_last_wait_payload = data.duplicate(true)

	# 处理 capture
	if not current_step.capture.is_empty():
		for var_name in current_step.capture:
			var path: String = str(current_step.capture[var_name])
			var value: Variant = _extract_from_data(data, path)
			if value != null:
				set_variable(var_name, value)
				print("[StoryDirector] Captured: %s = %s" % [var_name, str(value)])

	call_deferred("_advance")


func _on_wait_topic_completed(topic: Resource, result: Dictionary) -> void:
	if current_step == null:
		return
	var expected_id: String = str(current_step.wait_for.get("topic_id", ""))
	if not expected_id.is_empty() and topic.topic_id != expected_id:
		return
	var enriched_result: Dictionary = result.duplicate(true)
	var conversation: Array[Dictionary] = _build_topic_conversation_messages(topic, enriched_result)
	if not conversation.is_empty():
		enriched_result["conversation_messages"] = conversation
		enriched_result["player_messages"] = _extract_player_messages_from_conversation(conversation)
		enriched_result["npc_messages"] = _extract_npc_messages_from_conversation(topic, conversation)
	_on_wait_satisfied({"topic": topic, "result": enriched_result})


func _on_wait_url_opened(url: String, _design_prompt: String, _page_context: String) -> void:
	if current_step == null:
		return
	var expected_url: String = _interpolate(str(current_step.wait_for.get("url", "")))
	if not expected_url.is_empty() and url != expected_url:
		return
	_complete_story_topic_for_current_step_url(url)
	_on_wait_satisfied({"url": url})


func _on_wait_dev_task_completed(task_id: String, new_status: String) -> void:
	if current_step == null:
		return
	if new_status != "completed":
		return
	var expected_task_id := _interpolate(str(current_step.wait_for.get("task_id", ""))).strip_edges()
	if not expected_task_id.is_empty() and task_id != expected_task_id:
		return
	_on_wait_satisfied({"task_id": task_id, "status": new_status})


func _is_expected_dev_task_completed() -> bool:
	if current_step == null:
		return false
	var expected_task_id := _interpolate(str(current_step.wait_for.get("task_id", ""))).strip_edges()
	if expected_task_id.is_empty():
		return false
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or not dcm.has_method("get_task"):
		return false
	var task: Dictionary = dcm.get_task(expected_task_id)
	return str(task.get("status", "")) == "completed"


func _on_wait_app_opened(app_id: String, _window: Control) -> void:
	if current_step == null:
		return
	var expected_app: String = str(current_step.wait_for.get("app_id", ""))
	if not expected_app.is_empty() and app_id != expected_app:
		return
	_complete_story_topic_for_current_step_event("玩家已打开 APP: %s" % app_id, {"app_id": app_id})
	_on_wait_satisfied({"app_id": app_id})


func _on_wait_date_started(session_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	_complete_story_topic_for_current_step_event("玩家已开始约会", {"session_id": session_id, "payload": payload})
	_on_wait_satisfied({"session_id": session_id, "payload": payload})


func _on_wait_date_completed(session_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	_complete_story_topic_for_current_step_event("玩家已完成约会", {"session_id": session_id, "payload": payload})
	_on_wait_satisfied({"session_id": session_id, "payload": payload})


func _on_wait_home_activity_started(activity_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	var expected_activity: String = str(current_step.wait_for.get("activity_id", "")).strip_edges()
	if not expected_activity.is_empty() and activity_id != expected_activity:
		return
	_complete_story_topic_for_current_step_event("玩家已开始活动: %s" % activity_id, {"activity_id": activity_id, "payload": payload})
	_on_wait_satisfied({"activity_id": activity_id, "payload": payload})


func _on_wait_home_activity_completed(activity_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	var expected_activity: String = str(current_step.wait_for.get("activity_id", "")).strip_edges()
	if not expected_activity.is_empty() and activity_id != expected_activity:
		return
	_complete_story_topic_for_current_step_event("玩家已完成活动: %s" % activity_id, {"activity_id": activity_id, "payload": payload})
	_on_wait_satisfied({"activity_id": activity_id, "payload": payload})


func _complete_story_topic_for_current_step_url(url: String) -> void:
	_complete_story_topic_for_current_step_event("玩家已打开 %s" % url, {"url": url})


func _complete_story_topic_for_current_step_event(summary: String, result: Dictionary = {}) -> bool:
	if current_step == null:
		return false

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		return false
	if not chat.has_method("get_active_topic"):
		return false
	if not ("topic_manager" in chat):
		return false

	for action in current_step.actions:
		if not (action is Dictionary):
			continue
		var action_dict: Dictionary = action as Dictionary
		if str(action_dict.get("type", "")) != "activate_topic":
			continue

		var topic_path: String = _interpolate(str(action_dict.get("topic_path", "")))
		if topic_path.is_empty() or not ResourceLoader.exists(topic_path):
			continue

		var topic_template: ChatTopic = load(topic_path) as ChatTopic
		if topic_template == null:
			continue

		var active_topic: ChatTopic = chat.get_active_topic(topic_template.channel_id)
		if active_topic == null:
			continue
		if active_topic.topic_id != topic_template.topic_id:
			continue

		var topic_manager: Variant = chat.get("topic_manager")
		if topic_manager == null or not topic_manager.has_method("complete_topic"):
			return false

		var normalized_result: Dictionary = result.duplicate(true)
		if not normalized_result.has("summary"):
			normalized_result["summary"] = summary
		if chat.has_method("cancel_pending_ai_request"):
			chat.cancel_pending_ai_request(active_topic.channel_id, "story_wait_event_completed_topic:%s" % active_topic.topic_id)
		topic_manager.complete_topic(active_topic, normalized_result)
		return true
	return false


func _on_wait_avg_scene_ended(scene_id: String, outcome: Dictionary = {}) -> void:
	if current_step == null:
		return
	var expected_scene: String = str(current_step.wait_for.get("scene_id", ""))
	if not expected_scene.is_empty() and scene_id != expected_scene:
		return
	_on_wait_satisfied({"scene_id": scene_id, "outcome": outcome})


func _on_wait_project_preview_finished(preview_id: String, payload: Dictionary = {}) -> void:
	if current_step == null:
		return
	var expected_preview_id: String = _interpolate(str(current_step.wait_for.get("preview_id", current_step.wait_for.get("session_id", "")))).strip_edges()
	if not expected_preview_id.is_empty() and preview_id != expected_preview_id:
		return
	_on_wait_satisfied({"preview_id": preview_id, "payload": payload})


func _on_wait_sbeam_completed(session_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	_on_wait_satisfied({"session_id": session_id, "payload": payload})


func _on_wait_transit_completed(transit_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	var expected_id: String = _interpolate(str(current_step.wait_for.get("id", current_step.wait_for.get("transit_id", "")))).strip_edges()
	if not expected_id.is_empty() and transit_id != expected_id:
		return
	_on_wait_satisfied({"transit_id": transit_id, "payload": payload})


func _on_wait_phase_reached(new_phase: int) -> void:
	if current_step == null:
		return
	var expected_phase: String = str(current_step.wait_for.get("phase", "")).to_upper()
	var phase_map: Dictionary = {"MORNING": 0, "AFTERNOON": 1, "NIGHT": 2}
	var expected_value: int = phase_map.get(expected_phase, -1)
	if expected_value >= 0 and new_phase != expected_value:
		return
	_on_wait_satisfied({"phase": new_phase})


func _on_wait_day_reached(new_day: int) -> void:
	if current_step == null:
		return
	var expected_day: int = int(current_step.wait_for.get("day", 0))
	if expected_day > 0 and new_day != expected_day:
		return
	_on_wait_satisfied({"day": new_day})


func _on_wait_variable_changed(key: String, value: Variant) -> void:
	if current_step == null:
		return
	var wait: Dictionary = current_step.wait_for
	var expected_key: String = str(wait.get("key", ""))
	if expected_key.is_empty() or key != expected_key:
		return
	var expected_value: Variant = wait.get("value", null)
	if expected_value != null and str(value) != str(expected_value):
		return
	_on_wait_satisfied({"key": key, "value": value})


func _on_wait_work_order_completed(order_id: String, old_status: String, new_status: String) -> void:
	if current_step == null:
		return
	if new_status != "completed":
		return
	var expected_id: String = _interpolate(str(current_step.wait_for.get("order_id", "")))
	if not expected_id.is_empty() and order_id != expected_id:
		return
	_on_wait_satisfied({"order_id": order_id, "old_status": old_status, "new_status": new_status})


func _on_wait_work_order_dispatched(order_id: String) -> void:
	if current_step == null:
		return
	var expected_id: String = _interpolate(str(current_step.wait_for.get("order_id", "")))
	if not expected_id.is_empty() and order_id != expected_id:
		return
	_on_wait_satisfied({"order_id": order_id})


# =============================================================================
# Chapter Loading
# =============================================================================

func _load_all_chapters() -> void:
	_chapters.clear()

	# 非导出模式（编辑器运行）：重新编译 .story/.json → .tres + 索引
	var index_resource: Resource = null
	if not OS.has_feature("template"):
		index_resource = StoryCompilerClass.compile_all()
	else:
		index_resource = StoryCompilerClass.load_index_resource()

	_load_compiled_chapters(index_resource)


func _load_compiled_chapters(index_resource: Resource) -> bool:
	_chapters.clear()
	if index_resource == null or not (index_resource is StoryChapterIndexClass):
		if OS.has_feature("template"):
			push_warning("[StoryDirector] story_index.tres not found in exported build. No chapters loaded.")
		else:
			print("[StoryDirector] No compiled story index available.")
		return false

	for chapter in index_resource.chapters:
		if chapter != null and chapter is StoryChapterClass and not chapter.chapter_id.is_empty():
			_chapters[chapter.chapter_id] = chapter
			print("[StoryDirector] Loaded chapter: %s (%s)" % [chapter.chapter_id, chapter.chapter_name])
		else:
			push_warning("[StoryDirector] Invalid compiled chapter entry in story_index.tres")

	return not _chapters.is_empty()


# =============================================================================
# Trigger Evaluation
# =============================================================================

func _connect_trigger_sources() -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		_connect_trigger_signal(glm, "day_changed", _on_trigger_day_changed)
		_connect_trigger_signal(glm, "phase_changed", _on_trigger_phase_changed)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		_connect_trigger_signal(gm, "stats_changed", _on_trigger_stats_changed)

	if has_signal("story_variable_changed") and not is_connected("story_variable_changed", _on_trigger_story_variable_changed):
		story_variable_changed.connect(_on_trigger_story_variable_changed)


func _connect_trigger_signal(node: Node, signal_name: String, callback: Callable) -> void:
	if node == null or not node.has_signal(signal_name):
		return
	if node.is_connected(signal_name, callback):
		return
	node.connect(signal_name, callback)


func _on_trigger_day_changed(_new_day: int) -> void:
	_request_trigger_scan()


func _on_trigger_phase_changed(_new_phase: int) -> void:
	_request_trigger_scan()


func _on_trigger_story_variable_changed(_key: String, _value: Variant) -> void:
	_request_trigger_scan()


func _on_trigger_stats_changed() -> void:
	_request_trigger_scan()


func _request_trigger_scan() -> void:
	if _trigger_scan_queued:
		return
	_trigger_scan_queued = true
	call_deferred("_flush_trigger_scan")


func _flush_trigger_scan() -> void:
	_trigger_scan_queued = false
	_try_start_triggered_chapter()


func _try_start_triggered_chapter() -> bool:
	if current_chapter != null or current_step != null or _waiting:
		return false

	var chapter: Resource = _get_next_triggered_chapter()
	if chapter == null:
		return false
	return start_chapter(chapter.chapter_id)


func _get_next_triggered_chapter() -> Resource:
	var selected: Resource = null
	var selected_priority: int = -2147483648
	var selected_id: String = ""

	for chapter_value in _chapters.values():
		if not (chapter_value is StoryChapterClass):
			continue
		var chapter: Resource = chapter_value
		if not _can_auto_trigger_chapter(chapter):
			continue

		var chapter_priority: int = int(chapter.priority)
		var chapter_id: String = str(chapter.chapter_id)
		if selected == null \
		or chapter_priority > selected_priority \
		or (chapter_priority == selected_priority and chapter_id.nocasecmp_to(selected_id) < 0):
			selected = chapter
			selected_priority = chapter_priority
			selected_id = chapter_id

	return selected


func _can_auto_trigger_chapter(chapter: Resource) -> bool:
	if chapter == null or not (chapter is StoryChapterClass):
		return false
	if chapter.trigger.is_empty():
		return false
	if bool(completed_chapters.get(chapter.chapter_id, false)):
		return false
	return _matches_chapter_trigger(chapter.trigger)


func _has_pending_triggered_chapters() -> bool:
	for chapter_value in _chapters.values():
		if not (chapter_value is StoryChapterClass):
			continue
		var chapter: Resource = chapter_value
		if chapter.trigger.is_empty():
			continue
		if bool(completed_chapters.get(chapter.chapter_id, false)):
			continue
		return true
	return false


func _matches_chapter_trigger(trigger: Dictionary) -> bool:
	if trigger.is_empty():
		return false

	var game_state: Dictionary = _collect_game_state()
	var current_day: int = int(game_state.get("current_day", 0))
	if trigger.has("day") and current_day != int(trigger.get("day", 0)):
		return false
	if trigger.has("min_day") and current_day < int(trigger.get("min_day", 0)):
		return false
	if trigger.has("max_day") and current_day > int(trigger.get("max_day", 0)):
		return false

	var current_phase: String = str(game_state.get("phase", "")).to_upper()
	var expected_phase: String = str(trigger.get("phase", "")).strip_edges().to_upper()
	if not expected_phase.is_empty() and current_phase != expected_phase:
		return false

	for required_chapter_id in _to_string_array(trigger.get("required_chapters", [])):
		if not bool(completed_chapters.get(required_chapter_id, false)):
			return false

	for excluded_chapter_id in _to_string_array(trigger.get("excluded_chapters", [])):
		if bool(completed_chapters.get(excluded_chapter_id, false)):
			return false

	for expr in _to_string_array(trigger.get("conditions", [])):
		if not _evaluate_story_condition(expr, story_variables, game_state):
			return false

	return true


func _evaluate_story_condition(expr: String, variables: Dictionary, game_state: Dictionary) -> bool:
	var stripped_expr: String = expr.strip_edges()
	if stripped_expr.is_empty():
		return false

	for op in _CONDITION_OPERATORS:
		var needle: String = " %s " % op
		var op_pos: int = stripped_expr.find(needle)
		if op_pos < 0:
			continue

		var left: String = stripped_expr.substr(0, op_pos).strip_edges()
		var right: String = stripped_expr.substr(op_pos + needle.length()).strip_edges()
		if left.is_empty() or right.is_empty():
			return false

		var actual: Variant = _resolve_condition_actual_value(left, variables, game_state)
		if actual == null:
			return false
		var expected: Variant = _parse_condition_literal(right)
		return _compare_condition_values(actual, expected, op)

	return false


func _resolve_condition_actual_value(key: String, variables: Dictionary, game_state: Dictionary) -> Variant:
	if key.begins_with("story."):
		return variables.get(key.substr(6), null)
	if key.begins_with("game."):
		return game_state.get(key.substr(5), null)
	if key.begins_with("completed_chapters."):
		return bool(completed_chapters.get(key.substr("completed_chapters.".length()), false))
	if key.begins_with("completed_steps."):
		return bool(completed_steps.get(key.substr("completed_steps.".length()), false))
	if variables.has(key):
		return variables.get(key)
	if game_state.has(key):
		return game_state.get(key)
	return null


func _parse_condition_literal(raw_value: String) -> Variant:
	var stripped_value: String = raw_value.strip_edges()
	if stripped_value.length() >= 2:
		var first_char: String = stripped_value.left(1)
		var last_char: String = stripped_value.right(1)
		if (first_char == '"' and last_char == '"') or (first_char == "'" and last_char == "'"):
			return stripped_value.substr(1, stripped_value.length() - 2)
	if stripped_value == "true":
		return true
	if stripped_value == "false":
		return false
	if stripped_value.is_valid_int():
		return stripped_value.to_int()
	if stripped_value.is_valid_float():
		return stripped_value.to_float()
	return stripped_value


func _compare_condition_values(actual: Variant, expected: Variant, op: String) -> bool:
	match op:
		"==":
			return _values_equal(actual, expected)
		"!=":
			return not _values_equal(actual, expected)
		">=", "<=", ">", "<":
			if not _is_numeric_variant(actual) or not _is_numeric_variant(expected):
				return false
			var actual_num: float = float(actual)
			var expected_num: float = float(expected)
			match op:
				">=":
					return actual_num >= expected_num
				"<=":
					return actual_num <= expected_num
				">":
					return actual_num > expected_num
				"<":
					return actual_num < expected_num
	return false


func _values_equal(actual: Variant, expected: Variant) -> bool:
	if _is_numeric_variant(actual) and _is_numeric_variant(expected):
		return is_equal_approx(float(actual), float(expected))
	if actual is bool or expected is bool:
		return _to_bool(actual) == _to_bool(expected)
	return str(actual) == str(expected)


func _is_numeric_variant(value: Variant) -> bool:
	return value is int or value is float


func _to_bool(value: Variant) -> bool:
	if value is bool:
		return value
	var normalized: String = str(value).strip_edges().to_lower()
	return normalized == "true" or normalized == "1"


# =============================================================================
# Utilities
# =============================================================================

## 模板变量替换：{key} → story_variables[key]
func _interpolate(text: String) -> String:
	var result: String = text
	for key in story_variables:
		result = result.replace("{%s}" % key, str(story_variables[key]))
	return result


func _resolve_activity_guidance_prompt(action: Dictionary) -> String:
	return _resolve_action_prompt(action, ["prompt_key"], ["prompt"])


func _resolve_action_prompt(action: Dictionary, prompt_key_fields: Array[String], prompt_text_fields: Array[String]) -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	var vars := story_variables.duplicate(true)

	for key_field in prompt_key_fields:
		var prompt_key := _interpolate(str(action.get(key_field, ""))).strip_edges()
		if prompt_key.is_empty():
			continue
		if prompt_manager != null and prompt_manager.has_method("resolve_with_vars") and prompt_manager.has_method("has_prompt"):
			if prompt_manager.has_prompt(prompt_key):
				return str(prompt_manager.resolve_with_vars(prompt_key, vars)).strip_edges()
			push_warning("[StoryDirector] prompt_key not found: %s" % prompt_key)
		else:
			push_warning("[StoryDirector] PromptManager unavailable for prompt_key '%s'" % prompt_key)

	for text_field in prompt_text_fields:
		var prompt_text := _interpolate(str(action.get(text_field, ""))).strip_edges()
		if prompt_text.is_empty():
			continue
		if prompt_manager != null and prompt_manager.has_method("resolve_template_with_vars"):
			return str(prompt_manager.resolve_template_with_vars(prompt_text, vars)).strip_edges()
		return prompt_text

	return ""


func _resolve_prompt_template(prompt_key: String, vars: Dictionary, fallback: String) -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager != null and prompt_manager.has_method("has_prompt") and prompt_manager.has_method("resolve_with_vars"):
		if prompt_manager.has_prompt(prompt_key):
			var resolved := str(prompt_manager.resolve_with_vars(prompt_key, vars)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return fallback


## 检查 wait_for 的附加数据是否匹配
func _match_wait_data(wait: Dictionary, data: Dictionary) -> bool:
	# 通用匹配：检查 wait 中除 type 外的字段是否在 data 中匹配
	for key in wait:
		if key == "type":
			continue
		if data.has(key) and str(data[key]) != _interpolate(str(wait[key])):
			return false
	return true


## 从嵌套 Dictionary 中按路径提取值
## 路径格式: "$.key1.key2" 或 "key1.key2"
func _extract_from_data(data: Dictionary, path: String) -> Variant:
	var clean: String = path.strip_edges()
	if clean.begins_with("$."):
		clean = clean.substr(2)

	var parts: PackedStringArray = clean.split(".")
	var current: Variant = data
	for part in parts:
		if current is Dictionary and current.has(part):
			current = current[part]
		else:
			return null
	return current


## 收集当前游戏状态（用于条件分支求值）
func _collect_game_state() -> Dictionary:
	var state: Dictionary = {}

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		for prop in ["affection", "stress", "passion", "money",
					"completion", "quality", "stability", "hype"]:
			if prop in gm:
				state[prop] = gm.get(prop)

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		state["current_day"] = glm.current_day
		state["day"] = glm.current_day
		state["time_phase"] = glm.time_phase
		if glm.has_method("get_phase_name"):
			state["phase"] = str(glm.get_phase_name(glm.time_phase)).to_upper()

	return state
