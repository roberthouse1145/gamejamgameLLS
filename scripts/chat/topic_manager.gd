class_name TopicManager extends Node
## ChatTopic 生命周期与 ChatRunner 的统一入口。
## LOCAL 直接执行 local_script；LLM 等待外部生成完整 DSL 后走同一执行链路。

const ChatRunnerScene = preload("res://scenes/chat/chat_runner.tscn")
const AIServiceClass = preload("res://scripts/llm/AIService.gd")
const AIConfigManagerClass = preload("res://scripts/llm/ai_config_manager.gd")
const GENERATION_IDLE: String = "idle"
const GENERATION_RUNNING: String = "running"
const GENERATION_WAITING_EXTERNAL: String = "waiting_external"
const GENERATION_READY: String = "ready"
const GENERATION_FAILED: String = "failed"

signal topic_generation_requested(topic: ChatTopic, resolved_prompt: String)
signal topic_activated(topic: ChatTopic)
signal topic_message_emitted(topic: ChatTopic, speaker_id: String, text: String, is_player: bool, card: Dictionary)
signal topic_choices_presented(topic: ChatTopic, choices: Array)
signal topic_completed(topic: ChatTopic, result: Dictionary)
signal topic_cancelled(topic: ChatTopic, reason: String)

## channel_id -> ChatTopic。LLM 生成期间也属于活跃状态。
var active_topics: Dictionary = {}
var topic_history: Array[Dictionary] = []

## 自动使用现有 chat_default AI 配置生成 LLM Topic。测试或外部接管生成时可关闭。
var auto_request_llm: bool = true

var _sessions: Dictionary = {}
var _runners: Dictionary = {}
var _generation_prompts: Dictionary = {}
var _llm_service: AIService = null
var _llm_available: bool = false
## request_id -> {channel_id, activation_id}。LLM 返回绑定到具体 Topic 激活任务，而不是频道。
var _request_entries: Dictionary = {}
var _active_entries: Dictionary = {}
var _activation_counter: int = 0
## channel_id -> Array[entry]。生成可并行，ChatRunner 播放严格按激活顺序进行。
var _pending_topics: Dictionary = {}
## 完成/取消信号派发期间也视为占用，避免回调中的新 Topic 抢到队列前面。
var _closing_channels: Dictionary = {}
var _auto_advance_tokens: Dictionary = {}


func _ready() -> void:
	_llm_service = AIServiceClass.new()
	_llm_service.name = "ChatDslWriter"
	add_child(_llm_service)
	_llm_service.request_completed.connect(_on_llm_request_completed)
	_llm_service.request_failed.connect(_on_llm_request_failed)
	var config_manager: AIConfigManager = AIConfigManagerClass.get_instance()
	_llm_available = config_manager.apply_to_service(_llm_service, "chat_default")


func activate_topic(
	topic: ChatTopic,
	runtime_context: Dictionary = {},
	allowed_speakers: Array[String] = []
) -> bool:
	if topic == null:
		push_warning("TopicManager: Cannot activate null topic")
		return false
	var topic_id: String = topic.topic_id.strip_edges()
	var channel_id: String = topic.channel_id.strip_edges()
	if topic_id.is_empty() or channel_id.is_empty():
		push_warning("TopicManager: topic_id and channel_id are required")
		return false
	var entry: Dictionary = _make_topic_entry(topic, runtime_context, allowed_speakers)
	if active_topics.has(channel_id) or _closing_channels.has(channel_id):
		_queue_topic(channel_id, entry)
		if topic.mode == ChatTopic.Mode.LLM:
			_begin_llm_generation(entry)
		return true
	return _activate_topic_entry(entry)


func _make_topic_entry(
	topic: ChatTopic,
	runtime_context: Dictionary,
	allowed_speakers: Array[String]
) -> Dictionary:
	_activation_counter += 1
	return {
		"activation_id": _activation_counter,
		"topic": topic,
		"context": runtime_context.duplicate(true),
		"speakers": allowed_speakers.duplicate(),
		"variable_paths": _collect_leaf_paths(runtime_context),
		"generation_state": GENERATION_IDLE,
		"generation_prompt": "",
		"generated_script": "",
		"generation_error": "",
	}


func _activate_topic_entry(entry: Dictionary) -> bool:
	var topic: ChatTopic = entry.get("topic") as ChatTopic
	if topic == null:
		return false
	var channel_id: String = topic.channel_id.strip_edges()
	active_topics[channel_id] = topic
	_active_entries[channel_id] = entry
	_sessions[channel_id] = {
		"context": _dictionary_value(entry.get("context", {})),
		"speakers": _string_array(entry.get("speakers", [])),
		"variable_paths": _string_array(entry.get("variable_paths", [])),
	}

	if topic.mode == ChatTopic.Mode.LOCAL:
		if topic.local_script.strip_edges().is_empty():
			_cancel_topic(topic, "LOCAL topic has no local_script")
			return false
		return _start_runner(topic, topic.local_script)

	if topic.prompt.strip_edges().is_empty():
		_cancel_topic(topic, "LLM topic has no prompt")
		return false
	var generation_state: String = str(entry.get("generation_state", GENERATION_IDLE))
	match generation_state:
		GENERATION_READY:
			return _start_runner(topic, str(entry.get("generated_script", "")))
		GENERATION_FAILED:
			_cancel_topic(topic, str(entry.get("generation_error", "LLM generation failed")))
			return false
		GENERATION_RUNNING, GENERATION_WAITING_EXTERNAL:
			_generation_prompts[channel_id] = str(entry.get("generation_prompt", ""))
			return true
		_:
			return _begin_llm_generation(entry)


func _queue_topic(
	channel_id: String,
	entry: Dictionary
) -> void:
	var pending: Array = _pending_topics.get(channel_id, [])
	pending.append(entry)
	_pending_topics[channel_id] = pending


func _start_next_queued_topic(channel_id: String) -> void:
	var pending: Array = _pending_topics.get(channel_id, [])
	if pending.is_empty():
		_pending_topics.erase(channel_id)
		return
	var entry: Dictionary = pending.pop_front()
	if pending.is_empty():
		_pending_topics.erase(channel_id)
	else:
		_pending_topics[channel_id] = pending
	var topic: ChatTopic = entry.get("topic") as ChatTopic
	if topic == null:
		_start_next_queued_topic(channel_id)
		return
	_activate_topic_entry(entry)


## LLM 调用方收到 topic_generation_requested 后，将模型返回的完整 DSL 交回这里。
func submit_generated_script(channel_id: String, generated_script: String) -> bool:
	var topic: ChatTopic = get_active_topic(channel_id)
	if topic == null or topic.mode != ChatTopic.Mode.LLM:
		print("[TopicManager] submit_generated_script rejected: channel=%s topic=%s mode_ok=%s" % [channel_id, str(topic != null), str(topic != null and topic.mode == ChatTopic.Mode.LLM)])
		return false
	if _runners.has(channel_id):
		print("[TopicManager] submit_generated_script rejected: channel=%s already has a runner" % channel_id)
		return false
	var entry: Dictionary = _active_entries.get(channel_id, {})
	return _store_generated_script(entry, generated_script)


## 将模型返回值绑定到具体 ChatTopic。排队中的 LLM Topic 应使用此入口，避免同频道误投。
func submit_generated_topic_script(topic: ChatTopic, generated_script: String) -> bool:
	var entry: Dictionary = _find_entry_for_topic(topic)
	if entry.is_empty():
		print("[TopicManager] submit_generated_topic_script rejected: topic is not active or queued")
		return false
	return _store_generated_script(entry, generated_script)


## UI 播放完当前消息后调用，执行到下一条消息、选项或 END。
func advance_topic(channel_id: String) -> bool:
	_auto_advance_tokens[channel_id] = int(_auto_advance_tokens.get(channel_id, 0)) + 1
	var runner: ChatRunner = _runners.get(channel_id) as ChatRunner
	return runner.advance() if runner != null else false


## UI 提交固定 OPTION 的 id。此 API 不接收自由文本。
func choose_topic_option(channel_id: String, option_id: String) -> bool:
	_auto_advance_tokens[channel_id] = int(_auto_advance_tokens.get(channel_id, 0)) + 1
	var runner: ChatRunner = _runners.get(channel_id) as ChatRunner
	return runner.choose(option_id) if runner != null else false


func cancel_topic(channel_id: String, reason: String = "cancelled") -> void:
	var topic: ChatTopic = get_active_topic(channel_id)
	if topic != null:
		_cancel_topic(topic, reason)


func get_active_topic(channel_id: String) -> ChatTopic:
	return active_topics.get(channel_id) as ChatTopic


func has_active_topic(channel_id: String) -> bool:
	return active_topics.has(channel_id)


func get_generation_prompt(channel_id: String) -> String:
	return str(_generation_prompts.get(channel_id, ""))


func get_topic_runner(channel_id: String) -> ChatRunner:
	return _runners.get(channel_id) as ChatRunner


func can_auto_generate_llm() -> bool:
	return auto_request_llm and _llm_available and _llm_service != null


func reset_runtime_state(clear_history: bool = false) -> void:
	for runner_value: Variant in _runners.values():
		var runner: ChatRunner = runner_value as ChatRunner
		if runner != null:
			runner.queue_free()
	_runners.clear()
	_sessions.clear()
	_generation_prompts.clear()
	_request_entries.clear()
	_active_entries.clear()
	_activation_counter = 0
	_pending_topics.clear()
	_closing_channels.clear()
	_auto_advance_tokens.clear()
	active_topics.clear()
	if clear_history:
		topic_history.clear()


func _start_runner(topic: ChatTopic, source: String) -> bool:
	var channel_id: String = topic.channel_id
	var session: Dictionary = _sessions.get(channel_id, {})
	var runner: ChatRunner = ChatRunnerScene.instantiate() as ChatRunner
	if runner == null:
		_cancel_topic(topic, "ChatRunner scene could not be instantiated")
		return false
	runner.name = "ChatRunner_%s" % topic.topic_id
	add_child(runner)
	_runners[channel_id] = runner
	runner.message_emitted.connect(_on_message_emitted.bind(topic))
	runner.choices_presented.connect(_on_choices_presented.bind(topic))
	runner.completed.connect(_on_runner_completed.bind(topic))
	runner.failed.connect(_on_runner_failed.bind(topic))
	topic_activated.emit(topic)
	var started: bool = runner.start(
		source,
		_dictionary_value(session.get("context", {})),
		_string_array(session.get("speakers", [])),
		_string_array(session.get("variable_paths", []))
	)
	print("[TopicManager] runner start: channel=%s topic=%s started=%s" % [channel_id, topic.topic_id, str(started)])
	return started


func _on_message_emitted(speaker_id: String, text: String, is_player: bool, card: Dictionary, topic: ChatTopic) -> void:
	topic_message_emitted.emit(topic, speaker_id, text, is_player, card)
	if topic.auto_advance:
		_schedule_auto_advance(topic, text.length())


func _schedule_auto_advance(topic: ChatTopic, text_length: int) -> void:
	var channel_id: String = topic.channel_id
	var token: int = int(_auto_advance_tokens.get(channel_id, 0)) + 1
	_auto_advance_tokens[channel_id] = token
	var delay: float = clampf(
		topic.min_advance_delay + topic.advance_char_seconds * float(text_length),
		topic.min_advance_delay,
		topic.max_advance_delay
	)
	_auto_advance_after(channel_id, token, delay)


func _auto_advance_after(channel_id: String, token: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if int(_auto_advance_tokens.get(channel_id, -1)) != token:
		return
	advance_topic(channel_id)


func _on_choices_presented(choices: Array, topic: ChatTopic) -> void:
	topic_choices_presented.emit(topic, choices)


func _on_runner_completed(result: Dictionary, topic: ChatTopic) -> void:
	var channel_id: String = topic.channel_id
	topic_history.append({
		"topic_id": topic.topic_id,
		"channel_id": channel_id,
		"result": result.duplicate(true),
		"completed_at": Time.get_unix_time_from_system(),
	})
	_closing_channels[channel_id] = true
	_cleanup_channel(channel_id)
	topic_completed.emit(topic, result)
	_closing_channels.erase(channel_id)
	_start_next_queued_topic(channel_id)


func _on_runner_failed(errors: Array, topic: ChatTopic) -> void:
	print("[TopicManager] runner failed: topic=%s channel=%s errors=%s" % [topic.topic_id, topic.channel_id, str(errors)])
	_cancel_topic(topic, "\n".join(_string_array(errors)))


func _begin_llm_generation(entry: Dictionary) -> bool:
	var topic: ChatTopic = entry.get("topic") as ChatTopic
	if topic == null:
		return false
	if topic.prompt.strip_edges().is_empty():
		return _store_generation_failure(entry, "LLM topic has no prompt")
	var generation_state: String = str(entry.get("generation_state", GENERATION_IDLE))
	if generation_state != GENERATION_IDLE:
		return generation_state != GENERATION_FAILED

	var resolved_prompt: String = _build_generation_prompt(
		topic,
		_dictionary_value(entry.get("context", {})),
		_string_array(entry.get("speakers", [])),
		_string_array(entry.get("variable_paths", []))
	)
	if resolved_prompt.strip_edges().is_empty():
		return _store_generation_failure(entry, "LLM generation prompt is empty")

	entry["generation_prompt"] = resolved_prompt
	entry["generation_state"] = GENERATION_RUNNING
	_generation_prompts[topic.channel_id] = resolved_prompt
	topic_generation_requested.emit(topic, resolved_prompt)
	if str(entry.get("generation_state", GENERATION_IDLE)) == GENERATION_READY:
		return true
	if auto_request_llm and _request_llm_generation(entry, resolved_prompt):
		return true
	entry["generation_state"] = GENERATION_WAITING_EXTERNAL
	return true


func _request_llm_generation(entry: Dictionary, resolved_prompt: String) -> bool:
	var topic: ChatTopic = entry.get("topic") as ChatTopic
	if topic == null:
		return false
	if not _llm_available or _llm_service == null or resolved_prompt.strip_edges().is_empty():
		print("[TopicManager] LLM generation skipped: available=%s prompt_len=%d" % [str(_llm_available), resolved_prompt.length()])
		return false
	var request_id: String = _llm_service.chat_simple(
		resolved_prompt,
		_build_llm_system_prompt(),
		{"max_tokens": 2048}
	)
	if request_id.is_empty():
		print("[TopicManager] LLM generation failed to create request for channel '%s'" % topic.channel_id)
		return false
	_request_entries[request_id] = {
		"channel_id": topic.channel_id,
		"activation_id": int(entry.get("activation_id", 0)),
	}
	print("[TopicManager] LLM request sent: request_id=%s channel=%s prompt_len=%d" % [request_id, topic.channel_id, resolved_prompt.length()])
	return true


func _build_llm_system_prompt() -> String:
	return "You are a Chat DSL writer. Reasoning consists of exactly four physical lines, one for each label in the single Chat Reasoning decision record at the end of the user prompt. Keep every label on one compact line. End reasoning immediately after the acceptance line, then generate the final answer. The final answer contains only complete Chat DSL with no markdown fences or explanations."


func _on_llm_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_entries.has(request_id):
		print("[TopicManager] LLM response ignored: request_id=%s not tracked (active=%s)" % [request_id, str(_request_entries.keys())])
		return
	var request_entry: Dictionary = _dictionary_value(_request_entries[request_id])
	_request_entries.erase(request_id)
	var channel_id: String = str(request_entry.get("channel_id", ""))
	var entry: Dictionary = _find_entry(channel_id, int(request_entry.get("activation_id", 0)))
	if entry.is_empty():
		return
	var generated_script: String = AIServiceClass.extract_content(response).strip_edges()
	var reasoning_text: String = AIServiceClass.extract_reasoning_content(response).strip_edges()
	if not reasoning_text.is_empty():
		print("[TopicManager] LLM reasoning metrics: request_id=%s channel=%s lines=%d chars=%d" % [
			request_id,
			channel_id,
			reasoning_text.split("\n").size(),
			reasoning_text.length(),
		])
	print("[TopicManager] LLM response received: request_id=%s channel=%s script_len=%d" % [request_id, channel_id, generated_script.length()])
	_store_generated_script(entry, generated_script)


func _on_llm_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_entries.has(request_id):
		return
	var request_entry: Dictionary = _dictionary_value(_request_entries[request_id])
	_request_entries.erase(request_id)
	var entry: Dictionary = _find_entry(
		str(request_entry.get("channel_id", "")),
		int(request_entry.get("activation_id", 0))
	)
	if not entry.is_empty():
		_store_generation_failure(entry, error)


func _store_generated_script(entry: Dictionary, generated_script: String) -> bool:
	var topic: ChatTopic = entry.get("topic") as ChatTopic
	if topic == null or topic.mode != ChatTopic.Mode.LLM:
		return false
	if _is_entry_active(entry) and _runners.has(topic.channel_id):
		return false
	if generated_script.strip_edges().is_empty():
		return _store_generation_failure(entry, "LLM returned an empty Chat DSL")
	entry["generated_script"] = generated_script.strip_edges()
	entry["generation_state"] = GENERATION_READY
	_erase_requests_for_activation(int(entry.get("activation_id", 0)))
	if not _is_entry_active(entry):
		return true
	var started: bool = _start_runner(topic, str(entry.get("generated_script", "")))
	print("[TopicManager] generated DSL ready: channel=%s runner_started=%s" % [topic.channel_id, str(started)])
	return started


func _store_generation_failure(entry: Dictionary, error: String) -> bool:
	entry["generation_state"] = GENERATION_FAILED
	entry["generation_error"] = error
	_erase_requests_for_activation(int(entry.get("activation_id", 0)))
	if _is_entry_active(entry):
		var topic: ChatTopic = entry.get("topic") as ChatTopic
		if topic != null:
			_cancel_topic(topic, error)
	return false


func _cancel_topic(topic: ChatTopic, reason: String) -> void:
	print("[TopicManager] topic cancelled: topic=%s channel=%s reason=%s" % [topic.topic_id, topic.channel_id, reason])
	var channel_id: String = topic.channel_id
	topic_history.append({
		"topic_id": topic.topic_id,
		"channel_id": channel_id,
		"cancelled": true,
		"cancel_reason": reason,
		"completed_at": Time.get_unix_time_from_system(),
	})
	_closing_channels[channel_id] = true
	_cleanup_channel(channel_id)
	topic_cancelled.emit(topic, reason)
	_closing_channels.erase(channel_id)
	_start_next_queued_topic(channel_id)


func _cleanup_channel(channel_id: String) -> void:
	var active_entry: Dictionary = _active_entries.get(channel_id, {})
	_erase_requests_for_activation(int(active_entry.get("activation_id", 0)))
	var runner: ChatRunner = _runners.get(channel_id) as ChatRunner
	if runner != null:
		runner.queue_free()
	_runners.erase(channel_id)
	_sessions.erase(channel_id)
	_generation_prompts.erase(channel_id)
	_active_entries.erase(channel_id)
	active_topics.erase(channel_id)
	_auto_advance_tokens.erase(channel_id)


func _find_entry(channel_id: String, activation_id: int) -> Dictionary:
	var active_entry: Dictionary = _active_entries.get(channel_id, {})
	if int(active_entry.get("activation_id", 0)) == activation_id:
		return active_entry
	var pending: Array = _pending_topics.get(channel_id, [])
	for value: Variant in pending:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if int(entry.get("activation_id", 0)) == activation_id:
			return entry
	return {}


func _find_entry_for_topic(topic: ChatTopic) -> Dictionary:
	if topic == null:
		return {}
	var channel_id: String = topic.channel_id.strip_edges()
	var active_entry: Dictionary = _active_entries.get(channel_id, {})
	if active_entry.get("topic") == topic:
		return active_entry
	var pending: Array = _pending_topics.get(channel_id, [])
	for value: Variant in pending:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if entry.get("topic") == topic:
			return entry
	return {}


func _is_entry_active(entry: Dictionary) -> bool:
	var topic: ChatTopic = entry.get("topic") as ChatTopic
	if topic == null:
		return false
	var active_entry: Dictionary = _active_entries.get(topic.channel_id, {})
	return int(active_entry.get("activation_id", 0)) == int(entry.get("activation_id", -1))


func _erase_requests_for_activation(activation_id: int) -> void:
	if activation_id <= 0:
		return
	for request_id: Variant in _request_entries.keys():
		var request_entry: Dictionary = _dictionary_value(_request_entries[request_id])
		if int(request_entry.get("activation_id", 0)) == activation_id:
			_request_entries.erase(request_id)


func _build_generation_prompt(
	topic: ChatTopic,
	context: Dictionary,
	allowed_speakers: Array[String],
	paths: Array[String]
) -> String:
	var speakers: Array[String] = allowed_speakers.duplicate()
	if "player" not in speakers:
		speakers.append("player")
	var base_vars: Dictionary = {
		"topic_id": topic.topic_id,
		"channel_id": topic.channel_id,
		"runtime_context": JSON.stringify(context, "  "),
		"allowed_speakers": "\n".join(speakers),
		"allowed_variable_paths": "\n".join(paths),
	}
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	var topic_prompt: String = topic.prompt
	if prompt_manager != null and prompt_manager.has_method("resolve_template_with_vars"):
		topic_prompt = str(prompt_manager.call("resolve_template_with_vars", topic.prompt, base_vars))
	base_vars["topic_prompt"] = topic_prompt
	if prompt_manager != null and prompt_manager.has_method("has_prompt") \
		and bool(prompt_manager.call("has_prompt", "chat_dsl_generator")):
		return str(prompt_manager.call("resolve_with_vars", "chat_dsl_generator", base_vars))
	return topic_prompt


func _collect_leaf_paths(value: Variant, prefix: String = "") -> Array[String]:
	var result: Array[String] = []
	if value is Dictionary:
		for key_value: Variant in value:
			var key: String = str(key_value)
			var path: String = key if prefix.is_empty() else "%s.%s" % [prefix, key]
			var child: Variant = value[key_value]
			if child is Dictionary:
				result.append_array(_collect_leaf_paths(child, path))
			else:
				result.append(path)
	elif not prefix.is_empty():
		result.append(prefix)
	result.sort()
	return result


func _dictionary_value(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for item: Variant in value:
			result.append(str(item))
	return result
