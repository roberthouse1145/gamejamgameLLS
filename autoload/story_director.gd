extends Node
## 通用剧情流程调度器。
## 负责章节、步骤、变量、等待条件与存档状态；具体游戏动作由注册的处理器接入。

const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const StoryChapterIndexClass = preload("res://scripts/story/resources/story_chapter_index.gd")
const StoryCompilerClass = preload("res://scripts/story/story_compiler.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const TopicManagerClass = preload("res://scripts/chat/topic_manager.gd")

signal step_entered(chapter_id: String, step_id: String)
signal step_completed(chapter_id: String, step_id: String)
signal chapter_started(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal all_chapters_completed()
signal story_variable_changed(key: String, value: Variant)
signal action_requested(action: Dictionary)
signal action_failed(action: Dictionary, reason: String)
signal wait_started(wait_condition: Dictionary)

var current_chapter: Resource = null
var current_step: Resource = null
var story_variables: Dictionary = {}
var completed_steps: Dictionary = {}
var completed_chapters: Dictionary = {}

var _chapters: Dictionary = {}
var _action_handlers: Dictionary = {}
var _topic_manager: Node = null
var _waiting: bool = false
var _wait_generation: int = 0
var _current_wait: Dictionary = {}


func _ready() -> void:
	var topic_manager: Node = TopicManagerClass.new()
	topic_manager.name = "TopicManager"
	add_child(topic_manager)
	set_topic_manager(topic_manager)
	_load_compiled_chapters()


func register_chapter(chapter: Resource) -> bool:
	if chapter == null or not chapter is StoryChapterClass:
		return false
	var chapter_id: String = str(chapter.chapter_id).strip_edges()
	if chapter_id.is_empty():
		return false
	_chapters[chapter_id] = chapter
	return true


func register_action_handler(action_type: String, handler: Callable) -> bool:
	var normalized_type: String = action_type.strip_edges()
	if normalized_type.is_empty() or not handler.is_valid():
		return false
	_action_handlers[normalized_type] = handler
	return true


func unregister_action_handler(action_type: String) -> void:
	_action_handlers.erase(action_type.strip_edges())


func set_topic_manager(topic_manager: Node) -> void:
	if _topic_manager != null and is_instance_valid(_topic_manager):
		var old_callback := Callable(self, "_on_topic_completed")
		if _topic_manager.has_signal("topic_completed") and _topic_manager.is_connected("topic_completed", old_callback):
			_topic_manager.disconnect("topic_completed", old_callback)

	_topic_manager = topic_manager
	if _topic_manager == null:
		return

	var callback := Callable(self, "_on_topic_completed")
	if _topic_manager.has_signal("topic_completed") and not _topic_manager.is_connected("topic_completed", callback):
		_topic_manager.connect("topic_completed", callback)


func get_topic_manager() -> Node:
	return _topic_manager


func start_chapter(chapter_id: String) -> bool:
	var normalized_id: String = chapter_id.strip_edges()
	var chapter: Resource = _chapters.get(normalized_id)
	if chapter == null:
		push_warning("StoryDirector: Unknown chapter '%s'" % normalized_id)
		return false

	_cancel_wait()
	current_chapter = chapter
	current_step = null
	chapter_started.emit(normalized_id)

	var first_step: Resource = chapter.get_first_step()
	if first_step == null:
		_complete_chapter()
		return true

	_enter_step(first_step)
	return true


func set_variable(key: String, value: Variant) -> void:
	var normalized_key: String = key.strip_edges()
	if normalized_key.is_empty():
		return
	story_variables[normalized_key] = value
	story_variable_changed.emit(normalized_key, value)

	if _waiting and str(_current_wait.get("type", "")) == "variable_equals":
		var expected_key: String = str(_current_wait.get("key", ""))
		if expected_key == normalized_key and _values_equal(value, _current_wait.get("value")):
			_satisfy_wait.call_deferred(_wait_generation, {"key": normalized_key, "value": value})


func get_variable(key: String, default: Variant = null) -> Variant:
	return story_variables.get(key, default)


func notify_condition_met(condition_type: String, data: Dictionary = {}) -> void:
	if not _waiting:
		return
	if str(_current_wait.get("type", "")) != condition_type.strip_edges():
		return
	if not _matches_wait_data(_current_wait, data):
		return
	_satisfy_wait(_wait_generation, data)


func submit_story_event(condition_type: String, data: Dictionary = {}, variables: Dictionary = {}) -> void:
	for key: Variant in variables:
		set_variable(str(key), variables[key])
	notify_condition_met(condition_type, data)


func has_active_story() -> bool:
	return current_chapter != null


func is_waiting() -> bool:
	return _waiting


func get_chapter(chapter_id: String) -> Resource:
	return _chapters.get(chapter_id.strip_edges())


func get_chapter_ids() -> Array[String]:
	var result: Array[String] = []
	for chapter_id: Variant in _chapters:
		result.append(str(chapter_id))
	result.sort()
	return result


func evaluate_triggers() -> bool:
	if has_active_story():
		return false

	var candidates: Array[Resource] = []
	for chapter_value: Variant in _chapters.values():
		var chapter: Resource = chapter_value as Resource
		if chapter == null or completed_chapters.has(str(chapter.chapter_id)) or not chapter.has_trigger():
			continue
		if _matches_chapter_trigger(chapter.trigger):
			candidates.append(chapter)

	if candidates.is_empty():
		return false

	candidates.sort_custom(func(a: Resource, b: Resource) -> bool: return int(a.priority) > int(b.priority))
	return start_chapter(str(candidates[0].chapter_id))


func get_save_data() -> Dictionary:
	return {
		"current_chapter_id": str(current_chapter.chapter_id) if current_chapter != null else "",
		"current_step_id": str(current_step.step_id) if current_step != null else "",
		"story_variables": story_variables.duplicate(true),
		"completed_steps": completed_steps.duplicate(true),
		"completed_chapters": completed_chapters.duplicate(true),
	}


func load_save_data(data: Dictionary) -> bool:
	_cancel_wait()
	story_variables = _dictionary_value(data.get("story_variables", {}))
	completed_steps = _dictionary_value(data.get("completed_steps", {}))
	completed_chapters = _dictionary_value(data.get("completed_chapters", {}))
	current_chapter = null
	current_step = null

	var chapter_id: String = str(data.get("current_chapter_id", ""))
	var step_id: String = str(data.get("current_step_id", ""))
	if chapter_id.is_empty():
		return true

	var chapter: Resource = _chapters.get(chapter_id)
	if chapter == null:
		return false
	current_chapter = chapter

	if step_id.is_empty():
		return true
	var step: Resource = chapter.get_step(step_id)
	if step == null:
		current_chapter = null
		return false
	current_step = step
	_setup_wait(step.wait_for)
	return true


func get_run_state() -> Dictionary:
	return get_save_data()


func load_run_state(data: Dictionary) -> bool:
	return load_save_data(data)


func reset_runtime_state() -> void:
	_cancel_wait()
	current_chapter = null
	current_step = null
	story_variables.clear()
	completed_steps.clear()
	completed_chapters.clear()


func rebuild_story_cache() -> bool:
	if not OS.has_feature("editor"):
		push_warning("StoryDirector: Story cache can only be rebuilt from an editor build")
		return false
	var index: Resource = StoryCompilerClass.compile_all()
	if index == null:
		return false
	_load_chapter_index(index)
	return true


func _enter_step(step: Resource) -> void:
	if current_chapter == null or step == null or not step is StoryStepClass:
		return

	_cancel_wait()
	current_step = step
	step_entered.emit(str(current_chapter.chapter_id), str(step.step_id))

	for action: Dictionary in step.actions:
		_execute_action(action)
	_setup_wait(step.wait_for)


func _execute_action(action: Dictionary) -> void:
	var action_type: String = str(action.get("type", "")).strip_edges()
	if action_type.is_empty():
		action_failed.emit(action, "missing action type")
		return

	match action_type:
		"set_variable":
			set_variable(str(action.get("key", "")), action.get("value"))
		"activate_topic":
			_activate_topic(action)
		_:
			var handler: Callable = _action_handlers.get(action_type, Callable())
			if handler.is_valid():
				var result: Variant = handler.call(action)
				if result is bool and not result:
					action_failed.emit(action, "registered handler rejected action")
			else:
				action_requested.emit(action)


func _activate_topic(action: Dictionary) -> void:
	if _topic_manager == null or not is_instance_valid(_topic_manager) or not _topic_manager.has_method("activate_topic"):
		action_failed.emit(action, "topic manager is not configured")
		return

	var topic: Resource = null
	var topic_value: Variant = action.get("topic")
	if topic_value is ChatTopicClass:
		topic = topic_value
	else:
		var topic_path: String = str(action.get("topic_path", "")).strip_edges()
		if not topic_path.is_empty() and ResourceLoader.exists(topic_path):
			var loaded: Resource = ResourceLoader.load(topic_path)
			if loaded is ChatTopicClass:
				topic = loaded

	if topic == null:
		topic = ChatTopicClass.new()
		topic.topic_id = str(action.get("topic_id", ""))
		topic.channel_id = str(action.get("channel_id", ""))
		var mode_value: Variant = action.get("mode", ChatTopicClass.Mode.LOCAL)
		if mode_value is String:
			topic.mode = ChatTopicClass.Mode.LLM if str(mode_value).to_upper() == "LLM" else ChatTopicClass.Mode.LOCAL
		else:
			topic.mode = ChatTopicClass.Mode.LLM if int(mode_value) == ChatTopicClass.Mode.LLM else ChatTopicClass.Mode.LOCAL
		topic.local_script = str(action.get("local_script", ""))
		topic.prompt = str(action.get("prompt", ""))

	if str(topic.topic_id).is_empty() or str(topic.channel_id).is_empty():
		action_failed.emit(action, "topic_id and channel_id are required")
		return
	var runtime_context: Dictionary = _collect_chat_context()
	var context_value: Variant = action.get("runtime_context", {})
	if context_value is Dictionary:
		runtime_context.merge(context_value, true)
	var allowed_speakers: Array[String] = []
	var speaker_value: Variant = action.get("allowed_speakers", [])
	if speaker_value is Array or speaker_value is PackedStringArray:
		for speaker: Variant in speaker_value:
			allowed_speakers.append(str(speaker))
	if not bool(_topic_manager.call("activate_topic", topic, runtime_context, allowed_speakers)):
		action_failed.emit(action, "topic activation failed")


func _setup_wait(wait_condition: Dictionary) -> void:
	_cancel_wait()
	_current_wait = wait_condition.duplicate(true)
	var wait_type: String = str(_current_wait.get("type", "immediate")).strip_edges()
	if wait_type.is_empty():
		wait_type = "immediate"
		_current_wait["type"] = wait_type

	_waiting = true
	_wait_generation += 1
	var generation: int = _wait_generation
	wait_started.emit(_current_wait.duplicate(true))

	match wait_type:
		"immediate":
			_satisfy_wait.call_deferred(generation, {})
		"delay":
			var seconds: float = maxf(0.0, float(_current_wait.get("seconds", 0.0)))
			get_tree().create_timer(seconds).timeout.connect(_on_delay_finished.bind(generation), CONNECT_ONE_SHOT)
		"variable_equals":
			var key: String = str(_current_wait.get("key", ""))
			if story_variables.has(key) and _values_equal(story_variables[key], _current_wait.get("value")):
				_satisfy_wait.call_deferred(generation, {"key": key, "value": story_variables[key]})
		_:
			pass


func _on_delay_finished(generation: int) -> void:
	_satisfy_wait(generation, {})


func _on_topic_completed(topic: Resource, result: Dictionary) -> void:
	if not _waiting or str(_current_wait.get("type", "")) != "topic_completed":
		return
	var topic_id: String = str(topic.topic_id) if topic != null and "topic_id" in topic else ""
	var data: Dictionary = {"topic_id": topic_id, "topic": topic, "result": result}
	if _matches_wait_data(_current_wait, data):
		_satisfy_wait(_wait_generation, data)


func _satisfy_wait(generation: int, data: Dictionary) -> void:
	if not _waiting or generation != _wait_generation:
		return
	_waiting = false
	_current_wait.clear()
	_complete_current_step(data)


func _complete_current_step(data: Dictionary) -> void:
	if current_chapter == null or current_step == null:
		return

	_capture_step_data(current_step.capture, data)
	var chapter_id: String = str(current_chapter.chapter_id)
	var step_id: String = str(current_step.step_id)
	completed_steps["%s/%s" % [chapter_id, step_id]] = true
	step_completed.emit(chapter_id, step_id)

	var next_step_id: String = current_step.resolve_next(story_variables, _collect_game_state())
	if next_step_id.is_empty():
		_complete_chapter()
		return

	var next_step: Resource = current_chapter.get_step(next_step_id)
	if next_step == null:
		push_warning("StoryDirector: Step '%s' points to unknown step '%s'" % [step_id, next_step_id])
		_complete_chapter()
		return
	_enter_step(next_step)


func _complete_chapter() -> void:
	if current_chapter == null:
		return
	var finished_chapter: Resource = current_chapter
	var chapter_id: String = str(finished_chapter.chapter_id)
	var next_chapter_id: String = str(finished_chapter.next_chapter).strip_edges()
	completed_chapters[chapter_id] = true
	current_chapter = null
	current_step = null
	_cancel_wait()
	chapter_completed.emit(chapter_id)

	if not next_chapter_id.is_empty() and _chapters.has(next_chapter_id):
		start_chapter.call_deferred(next_chapter_id)
	else:
		all_chapters_completed.emit()


func _cancel_wait() -> void:
	_waiting = false
	_current_wait.clear()
	_wait_generation += 1


func _capture_step_data(capture: Dictionary, data: Dictionary) -> void:
	for variable_key: Variant in capture:
		var path: String = str(capture[variable_key])
		set_variable(str(variable_key), _extract_from_data(data, path))


func _extract_from_data(data: Dictionary, path: String) -> Variant:
	if path.is_empty():
		return null
	var current: Variant = data
	for segment: String in path.split(".", false):
		if current is Dictionary and current.has(segment):
			current = current[segment]
		else:
			return null
	return current


func _matches_wait_data(wait_condition: Dictionary, data: Dictionary) -> bool:
	for key: Variant in wait_condition:
		var key_name: String = str(key)
		if key_name in ["type", "seconds", "key", "value"]:
			continue
		if not data.has(key_name) or not _values_equal(data[key_name], wait_condition[key]):
			return false
	return true


func _matches_chapter_trigger(trigger: Dictionary) -> bool:
	var required_value: Variant = trigger.get("required_chapters", [])
	if required_value is Array:
		for chapter_id: Variant in required_value:
			if not completed_chapters.has(str(chapter_id)):
				return false

	var excluded_value: Variant = trigger.get("excluded_chapters", [])
	if excluded_value is Array:
		for chapter_id: Variant in excluded_value:
			if completed_chapters.has(str(chapter_id)):
				return false

	var state: Dictionary = _collect_game_state()
	var conditions_value: Variant = trigger.get("conditions", [])
	if conditions_value is Array:
		for condition: Variant in conditions_value:
			if not _evaluate_condition(str(condition), state):
				return false

	for key: Variant in trigger:
		var key_name: String = str(key)
		if key_name in ["required_chapters", "excluded_chapters", "conditions"]:
			continue
		if not state.has(key_name) or not _values_equal(state[key_name], trigger[key]):
			return false
	return true


func _evaluate_condition(expression: String, game_state: Dictionary) -> bool:
	var parts: PackedStringArray = expression.strip_edges().split(" ", false)
	if parts.size() < 3:
		return false
	var key: String = parts[0]
	var operator: String = parts[1]
	var expected: Variant = _parse_literal(" ".join(parts.slice(2)))
	var actual: Variant = story_variables.get(key, game_state.get(key))
	if actual == null:
		return false

	match operator:
		"==":
			return _values_equal(actual, expected)
		"!=":
			return not _values_equal(actual, expected)
		">", ">=", "<", "<=":
			if not _is_numeric(actual) or not _is_numeric(expected):
				return false
			var actual_number: float = float(actual)
			var expected_number: float = float(expected)
			match operator:
				">": return actual_number > expected_number
				">=": return actual_number >= expected_number
				"<": return actual_number < expected_number
				"<=": return actual_number <= expected_number
	return false


func _parse_literal(raw_value: String) -> Variant:
	var value: String = raw_value.strip_edges()
	if value == "true":
		return true
	if value == "false":
		return false
	if value == "null":
		return null
	if value.is_valid_int():
		return value.to_int()
	if value.is_valid_float():
		return value.to_float()
	return value.trim_prefix("\"").trim_suffix("\"")


func _values_equal(left: Variant, right: Variant) -> bool:
	if _is_numeric(left) and _is_numeric(right):
		return is_equal_approx(float(left), float(right))
	return left == right


func _is_numeric(value: Variant) -> bool:
	return value is int or value is float


func _collect_game_state() -> Dictionary:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("to_dict"):
		var value: Variant = game_state.call("to_dict")
		if value is Dictionary:
			return value
	return {}


func _collect_chat_context() -> Dictionary:
	var state: Dictionary = _collect_game_state()
	var context: Dictionary = {
		"state": state,
		"story": story_variables.duplicate(true),
	}
	var relationship_value: Variant = state.get("relationship", state.get("relationships", {}))
	if relationship_value is Dictionary:
		context["relationship"] = relationship_value.duplicate(true)
	return context


func _load_compiled_chapters() -> void:
	var index: Resource = StoryCompilerClass.load_index_resource()
	if index != null:
		_load_chapter_index(index)


func _load_chapter_index(index: Resource) -> void:
	if index == null or not index is StoryChapterIndexClass:
		return
	_chapters.clear()
	for chapter: Resource in index.chapters:
		register_chapter(chapter)


func _dictionary_value(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}
