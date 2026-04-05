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
	_pending_activity_guidance.clear()
	_waiting = false
	_started = false


func rebuild_story_cache() -> bool:
	if OS.has_feature("template"):
		push_warning("[StoryDirector] rebuild_story_cache is unavailable in exported builds")
		return false

	var index_resource: Resource = StoryCompilerClass.compile_all()
	return _load_compiled_chapters(index_resource)


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
		"open_browser":
			_action_open_browser(action)
		"post_moment":
			_action_post_moment(action)
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
		"close_app":
			_action_close_app(action)
		"focus_app":
			_action_focus_app(action)
		"lock_app_window":
			_action_lock_app_window(action)
		"unlock_app_window":
			_action_unlock_app_window(action)
		"set_activity_lock":
			_action_set_activity_lock(action)
		"clear_activity_lock":
			_action_clear_activity_lock(action)
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


## set_activity_lock — 叙事活动锁，按活动类型选择性禁用
## { "type": "set_activity_lock", "mode": "blacklist", "activities": ["date", "part_time", "gift"], "reason": "先把报名搞定" }
## { "type": "set_activity_lock", "mode": "whitelist", "activities": ["chat_casual", "rest"], "reason": "今天只能待在家里" }
## { "type": "set_activity_lock", "mode": "blacklist", "activities": ["browser", "watch_event"], "reason": "先别分心刷网页" }
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


## dispatch_work_order — 直接创建并派发工单
## { "type": "dispatch_work_order", "title": "...", "description": "...",
##   "assignee": "npc_lin_xia", "priority": 2, "save_order_id": "var_name" }
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
	order.assignee_npc_id = str(action.get("assignee", "npc_lin_xia"))
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
##   "assignee": "npc_lin_xia", "priority": 2, "role": "work_order",
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

	var system_prompt: String = """你是一个游戏开发项目的任务拆解助手。
根据用户的指令，生成一个详细的工单。

你必须严格使用以下 JSON 格式回复，不要输出任何其他内容：
{"title": "工单标题（简洁描述任务）", "description": "工单详细描述（包含背景、目标、具体要求）"}

当前项目知识库摘要：
%s""" % kb_context

	# 创建一次性 AIService
	var ai: AIService = AIService.new()
	ai.name = "StoryDirectorGenWO"
	var role_name: String = str(action.get("role", "work_order"))
	add_child(ai)
	AIConfigManager.get_instance().apply_to_service(ai, role_name)

	var assignee: String = str(action.get("assignee", "npc_lin_xia"))
	var priority: int = int(action.get("priority", 2))
	var save_var: String = str(action.get("save_order_id", ""))

	# 异步回调
	ai.request_completed.connect(
		func(_request_id: String, response: Dictionary) -> void:
			_on_generate_work_order_completed(response, wom, assignee, priority, save_var)
			ai.queue_free()
	)
	ai.request_failed.connect(
		func(_request_id: String, error: String, _error_code: int) -> void:
			push_warning("[StoryDirector] generate_work_order LLM failed: %s" % error)
			ai.queue_free()
	)

	ai.chat_simple(user_prompt, system_prompt)


func _on_generate_work_order_completed(response: Dictionary, wom: Node, assignee: String, priority: int, save_var: String) -> void:
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
	order.assignee_npc_id = assignee
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
			_wait_on_signal_dynamic("scene_ended", _on_wait_avg_scene_ended)
		"sbeam_completed":
			_wait_on_signal("/root/SbeamManager", "play_session_completed", _on_wait_sbeam_completed)
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


func _on_wait_home_activity_started(activity_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	var expected_activity: String = str(current_step.wait_for.get("activity_id", "")).strip_edges()
	if not expected_activity.is_empty() and activity_id != expected_activity:
		return
	_on_wait_satisfied({"activity_id": activity_id, "payload": payload})


func _on_wait_home_activity_completed(activity_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	var expected_activity: String = str(current_step.wait_for.get("activity_id", "")).strip_edges()
	if not expected_activity.is_empty() and activity_id != expected_activity:
		return
	_on_wait_satisfied({"activity_id": activity_id, "payload": payload})


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


func _on_wait_sbeam_completed(session_id: String, payload: Dictionary) -> void:
	if current_step == null:
		return
	_on_wait_satisfied({"session_id": session_id, "payload": payload})


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


func _on_wait_work_order_dispatched(order_id: String, assignee_npc_id: String) -> void:
	if current_step == null:
		return
	var expected_id: String = _interpolate(str(current_step.wait_for.get("order_id", "")))
	if not expected_id.is_empty() and order_id != expected_id:
		return
	_on_wait_satisfied({"order_id": order_id, "assignee_npc_id": assignee_npc_id})


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
# Utilities
# =============================================================================

## 模板变量替换：{key} → story_variables[key]
func _interpolate(text: String) -> String:
	var result: String = text
	for key in story_variables:
		result = result.replace("{%s}" % key, str(story_variables[key]))
	return result


func _resolve_activity_guidance_prompt(action: Dictionary) -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	var vars := story_variables.duplicate(true)

	var prompt_key := _interpolate(str(action.get("prompt_key", ""))).strip_edges()
	if not prompt_key.is_empty():
		if prompt_manager != null and prompt_manager.has_method("resolve_with_vars") and prompt_manager.has_method("has_prompt"):
			if prompt_manager.has_prompt(prompt_key):
				return str(prompt_manager.resolve_with_vars(prompt_key, vars)).strip_edges()
			push_warning("[StoryDirector] set_activity_guidance: prompt_key not found: %s" % prompt_key)
		else:
			push_warning("[StoryDirector] set_activity_guidance: PromptManager unavailable for prompt_key '%s'" % prompt_key)

	var prompt_text := _interpolate(str(action.get("prompt", ""))).strip_edges()
	if prompt_text.is_empty():
		return ""
	if prompt_manager != null and prompt_manager.has_method("resolve_template_with_vars"):
		return str(prompt_manager.resolve_template_with_vars(prompt_text, vars)).strip_edges()
	return prompt_text


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
