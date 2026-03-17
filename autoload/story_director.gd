extends Node
## StoryDirector Autoload
## 叙事导演 — 驱动剧本步骤的状态机引擎
## 加载章节 → 逐步执行 actions → 等待 wait_for 条件 → 推进到下一步

const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")

const CHAPTERS_DIR: String = "res://resources/story/chapters/"

# =============================================================================
# Signals
# =============================================================================

signal step_entered(chapter_id: String, step_id: String)
signal step_completed(chapter_id: String, step_id: String)
signal chapter_completed(chapter_id: String)
signal chapter_started(chapter_id: String)
signal story_variable_changed(key: String, value: Variant)
signal all_chapters_completed()

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


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	_delay_timer = Timer.new()
	_delay_timer.one_shot = true
	add_child(_delay_timer)
	_load_all_chapters()
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


## 获取当前状态摘要（存档用）
func get_save_data() -> Dictionary:
	return {
		"chapter_id": current_chapter.chapter_id if current_chapter else "",
		"step_id": current_step.step_id if current_step else "",
		"story_variables": story_variables.duplicate(true),
		"completed_steps": completed_steps.duplicate(true),
		"completed_chapters": completed_chapters.duplicate(true),
	}


## 从存档恢复
func load_save_data(data: Dictionary) -> bool:
	story_variables = data.get("story_variables", {}).duplicate(true)
	completed_steps = data.get("completed_steps", {}).duplicate(true)
	completed_chapters = data.get("completed_chapters", {}).duplicate(true)

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

	var chapter_id: String = str(data.get("chapter_id", "")).strip_edges()
	var step_id: String = str(data.get("step_id", "")).strip_edges()
	if chapter_id.is_empty():
		_disconnect_all_waits()
		current_chapter = null
		current_step = null
		_waiting = false
		_started = false
		return true

	if step_id.is_empty():
		return load_save_data({
			"chapter_id": chapter_id,
			"story_variables": story_variables,
			"completed_steps": completed_steps,
			"completed_chapters": completed_chapters,
		})
	return load_save_data(data)


func has_active_story() -> bool:
	return _started or current_chapter != null or current_step != null or not completed_steps.is_empty() or not completed_chapters.is_empty()


func reset_runtime_state() -> void:
	_disconnect_all_waits()
	if _delay_timer != null:
		_delay_timer.stop()
	current_chapter = null
	current_step = null
	story_variables.clear()
	completed_steps.clear()
	completed_chapters.clear()
	_waiting = false
	_started = false


# =============================================================================
# Step Execution
# =============================================================================

func _enter_step(step: Resource) -> void:
	_disconnect_all_waits()
	current_step = step
	_waiting = false

	print("[StoryDirector] >> Enter step: %s" % step.step_id)
	step_entered.emit(current_chapter.chapter_id, step.step_id)

	# 执行所有 actions
	for action in step.actions:
		_execute_action(action)

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
		"set_app_access":
			_action_set_app_access(action)
		"set_phase":
			_action_set_phase(action)
		"modify_stats":
			_action_modify_stats(action)
		"play_avg":
			_action_play_avg(action)
		"open_browser":
			_action_open_browser(action)
		"post_moment":
			_action_post_moment(action)
		"set_variable":
			_action_set_variable(action)
		"delay":
			_action_delay(action)
		"launch_app":
			_action_launch_app(action)
		"close_app":
			_action_close_app(action)
		"focus_app":
			_action_focus_app(action)
		"lock_app_window":
			_action_lock_app_window(action)
		"unlock_app_window":
			_action_unlock_app_window(action)
		_:
			push_warning("[StoryDirector] Unknown action type: %s" % action_type)


## activate_topic — 加载预制 Topic .tres 并激活
## { "type": "activate_topic", "topic_path": "res://...", "npc_speaks_first": true, "seed_message": "" }
func _action_activate_topic(action: Dictionary) -> void:
	var topic_path: String = _interpolate(str(action.get("topic_path", "")))
	if topic_path.is_empty():
		push_warning("[StoryDirector] activate_topic: missing topic_path")
		return

	if not ResourceLoader.exists(topic_path):
		push_warning("[StoryDirector] activate_topic: resource not found: %s" % topic_path)
		return

	var topic: ChatTopic = load(topic_path) as ChatTopic
	if topic == null:
		push_warning("[StoryDirector] activate_topic: failed to load: %s" % topic_path)
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
		push_warning("[StoryDirector] activate_topic: ChatManager not available")
		return

	if not chat.activate_topic(topic):
		push_warning("[StoryDirector] activate_topic: failed to activate topic %s" % topic.topic_id)
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
			chat.request_topic_npc_reply(topic.channel_id, seed_msg, auto_store, auto_complete)


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


func _action_set_app_access(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		push_warning("[StoryDirector] set_app_access: AppManager not available")
		return

	var mode: String = str(action.get("mode", "all"))
	var apps: Array = action.get("apps", [])

	match mode:
		"whitelist":
			if app_mgr.has_method("set_app_whitelist"):
				var app_ids: Array[String] = []
				for a in apps:
					app_ids.append(str(a))
				app_mgr.set_app_whitelist(app_ids)
				print("[StoryDirector] App whitelist set: %s" % str(app_ids))
			else:
				push_warning("[StoryDirector] set_app_access: AppManager missing set_app_whitelist()")
		"blacklist":
			if app_mgr.has_method("set_app_blacklist"):
				var app_ids: Array[String] = []
				for a in apps:
					app_ids.append(str(a))
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
	# TODO: 与 AVGSceneRunner / NarrativeProjectManager 集成
	var project_path: String = _interpolate(str(action.get("project_path", "")))
	var scene_id: String = _interpolate(str(action.get("scene_id", "")))
	print("[StoryDirector] play_avg: project=%s scene=%s (TODO: implement)" % [project_path, scene_id])


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
		"avg_scene_ended":
			_wait_on_signal_dynamic("scene_ended", _on_wait_avg_scene_ended)
		"phase_reached":
			_wait_on_signal("/root/GameLoopManager", "phase_changed", _on_wait_phase_reached)
		"day_reached":
			_wait_on_signal("/root/GameLoopManager", "day_changed", _on_wait_day_reached)
		"variable_equals":
			# 由 set_variable / notify_condition_met 触发
			story_variable_changed.connect(_on_wait_variable_changed)
			_wait_connections.append({"signal": "story_variable_changed", "callable": _on_wait_variable_changed, "self": true})
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
	_on_wait_satisfied({"topic": topic, "result": result})


func _on_wait_url_opened(url: String, _design_prompt: String, _page_context: String) -> void:
	if current_step == null:
		return
	var expected_url: String = _interpolate(str(current_step.wait_for.get("url", "")))
	if not expected_url.is_empty() and url != expected_url:
		return
	_complete_story_topic_for_current_step_url(url)
	_on_wait_satisfied({"url": url})


func _on_wait_app_opened(app_id: String, _window: Control) -> void:
	if current_step == null:
		return
	var expected_app: String = str(current_step.wait_for.get("app_id", ""))
	if not expected_app.is_empty() and app_id != expected_app:
		return
	_on_wait_satisfied({"app_id": app_id})


func _on_wait_date_started(session_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	_on_wait_satisfied({"session_id": session_id, "payload": payload})


func _on_wait_date_completed(session_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	_on_wait_satisfied({"session_id": session_id, "payload": payload})


func _complete_story_topic_for_current_step_url(url: String) -> void:
	if current_step == null:
		return

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		return
	if not chat.has_method("get_active_topic"):
		return
	if not ("topic_manager" in chat):
		return

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
			return

		var summary: String = "玩家已打开 %s" % url
		topic_manager.complete_topic(active_topic, {
			"url": url,
			"summary": summary,
		})
		return


func _on_wait_avg_scene_ended(scene_id: String) -> void:
	if current_step == null:
		return
	var expected_scene: String = str(current_step.wait_for.get("scene_id", ""))
	if not expected_scene.is_empty() and scene_id != expected_scene:
		return
	_on_wait_satisfied({"scene_id": scene_id})


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


# =============================================================================
# Chapter Loading
# =============================================================================

func _load_all_chapters() -> void:
	_chapters.clear()
	if not DirAccess.dir_exists_absolute(CHAPTERS_DIR):
		print("[StoryDirector] Chapters dir not found: %s" % CHAPTERS_DIR)
		return

	var dir: DirAccess = DirAccess.open(CHAPTERS_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var chapter: Resource = _load_chapter_from_json(CHAPTERS_DIR + file_name)
			if chapter != null and not chapter.chapter_id.is_empty():
				_chapters[chapter.chapter_id] = chapter
				print("[StoryDirector] Loaded chapter: %s (%s)" % [chapter.chapter_id, chapter.chapter_name])
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_chapter_from_json(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[StoryDirector] Failed to open: %s" % path)
		return null

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		push_warning("[StoryDirector] Invalid JSON in: %s" % path)
		return null

	var data: Dictionary = parsed
	var chapter := StoryChapterClass.new()
	chapter.chapter_id = str(data.get("chapter_id", ""))
	chapter.chapter_name = str(data.get("chapter_name", ""))
	chapter.description = str(data.get("description", ""))
	chapter.next_chapter = str(data.get("next_chapter", ""))

	var steps_data: Array = data.get("steps", [])
	for step_data in steps_data:
		if not step_data is Dictionary:
			continue
		var step := StoryStepClass.new()
		step.step_id = str(step_data.get("step_id", ""))
		step.description = str(step_data.get("description", ""))
		step.next = str(step_data.get("next", ""))

		# actions
		var actions_raw: Array = step_data.get("actions", [])
		for a in actions_raw:
			if a is Dictionary:
				step.actions.append(a)

		# wait_for
		var wait_raw: Variant = step_data.get("wait_for", {})
		if wait_raw is Dictionary:
			step.wait_for = wait_raw

		# capture
		var capture_raw: Variant = step_data.get("capture", {})
		if capture_raw is Dictionary:
			step.capture = capture_raw

		# next_conditions
		var nc_raw: Array = step_data.get("next_conditions", [])
		for nc in nc_raw:
			if nc is Dictionary:
				step.next_conditions.append(nc)

		chapter.steps.append(step)

	return chapter


# =============================================================================
# Utilities
# =============================================================================

## 模板变量替换：{key} → story_variables[key]
func _interpolate(text: String) -> String:
	var result: String = text
	for key in story_variables:
		result = result.replace("{%s}" % key, str(story_variables[key]))
	return result


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
		state["time_phase"] = glm.time_phase

	return state
