class_name TopicManager extends Node
## ChatTopic 生命周期与 ChatRunner 的统一入口。
## LOCAL 直接执行 local_script；LLM 等待外部生成完整 DSL 后走同一执行链路。

const ChatRunnerScene = preload("res://scenes/chat/chat_runner.tscn")
const AIServiceClass = preload("res://scripts/llm/AIService.gd")
const AIConfigManagerClass = preload("res://scripts/llm/ai_config_manager.gd")

signal topic_generation_requested(topic: ChatTopic, resolved_prompt: String)
signal topic_activated(topic: ChatTopic)
signal topic_message_emitted(topic: ChatTopic, speaker_id: String, text: String, is_player: bool)
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
var _request_channels: Dictionary = {}


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
	if active_topics.has(channel_id):
		push_warning("TopicManager: Channel '%s' already has an active topic" % channel_id)
		return false

	var variable_paths: Array[String] = _collect_leaf_paths(runtime_context)
	active_topics[channel_id] = topic
	_sessions[channel_id] = {
		"context": runtime_context.duplicate(true),
		"speakers": allowed_speakers.duplicate(),
		"variable_paths": variable_paths,
	}

	if topic.mode == ChatTopic.Mode.LOCAL:
		if topic.local_script.strip_edges().is_empty():
			_cancel_topic(topic, "LOCAL topic has no local_script")
			return false
		return _start_runner(topic, topic.local_script)

	if topic.prompt.strip_edges().is_empty():
		_cancel_topic(topic, "LLM topic has no prompt")
		return false
	var resolved_prompt: String = _build_generation_prompt(topic)
	_generation_prompts[channel_id] = resolved_prompt
	topic_generation_requested.emit(topic, resolved_prompt)
	if auto_request_llm and not _request_llm_generation(channel_id, resolved_prompt):
		push_warning("TopicManager: chat_default AI is unavailable; waiting for submit_generated_script()")
	return true


## LLM 调用方收到 topic_generation_requested 后，将模型返回的完整 DSL 交回这里。
func submit_generated_script(channel_id: String, generated_script: String) -> bool:
	var topic: ChatTopic = get_active_topic(channel_id)
	if topic == null or topic.mode != ChatTopic.Mode.LLM:
		return false
	if _runners.has(channel_id):
		return false
	if generated_script.strip_edges().is_empty():
		_cancel_topic(topic, "LLM returned an empty Chat DSL")
		return false
	return _start_runner(topic, generated_script)


## UI 播放完当前消息后调用，执行到下一条消息、选项或 END。
func advance_topic(channel_id: String) -> bool:
	var runner: ChatRunner = _runners.get(channel_id) as ChatRunner
	return runner.advance() if runner != null else false


## UI 提交固定 OPTION 的 id。此 API 不接收自由文本。
func choose_topic_option(channel_id: String, option_id: String) -> bool:
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
	_request_channels.clear()
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
	return runner.start(
		source,
		_dictionary_value(session.get("context", {})),
		_string_array(session.get("speakers", [])),
		_string_array(session.get("variable_paths", []))
	)


func _on_message_emitted(speaker_id: String, text: String, is_player: bool, topic: ChatTopic) -> void:
	topic_message_emitted.emit(topic, speaker_id, text, is_player)


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
	_cleanup_channel(channel_id)
	topic_completed.emit(topic, result)


func _on_runner_failed(errors: Array, topic: ChatTopic) -> void:
	_cancel_topic(topic, "\n".join(_string_array(errors)))


func _request_llm_generation(channel_id: String, resolved_prompt: String) -> bool:
	if not _llm_available or _llm_service == null or resolved_prompt.strip_edges().is_empty():
		return false
	var request_id: String = _llm_service.chat_simple(resolved_prompt)
	if request_id.is_empty():
		return false
	_request_channels[request_id] = channel_id
	return true


func _on_llm_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_channels.has(request_id):
		return
	var channel_id: String = str(_request_channels[request_id])
	_request_channels.erase(request_id)
	var generated_script: String = AIServiceClass.extract_content(response).strip_edges()
	if generated_script.is_empty():
		var topic: ChatTopic = get_active_topic(channel_id)
		if topic != null:
			_cancel_topic(topic, "LLM returned an empty Chat DSL")
		return
	submit_generated_script(channel_id, generated_script)


func _on_llm_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_channels.has(request_id):
		return
	var channel_id: String = str(_request_channels[request_id])
	_request_channels.erase(request_id)
	var topic: ChatTopic = get_active_topic(channel_id)
	if topic != null:
		_cancel_topic(topic, error)


func _cancel_topic(topic: ChatTopic, reason: String) -> void:
	var channel_id: String = topic.channel_id
	topic_history.append({
		"topic_id": topic.topic_id,
		"channel_id": channel_id,
		"cancelled": true,
		"cancel_reason": reason,
		"completed_at": Time.get_unix_time_from_system(),
	})
	_cleanup_channel(channel_id)
	topic_cancelled.emit(topic, reason)


func _cleanup_channel(channel_id: String) -> void:
	var runner: ChatRunner = _runners.get(channel_id) as ChatRunner
	if runner != null:
		runner.queue_free()
	_runners.erase(channel_id)
	_sessions.erase(channel_id)
	_generation_prompts.erase(channel_id)
	active_topics.erase(channel_id)
	for request_id: Variant in _request_channels.keys():
		if str(_request_channels[request_id]) == channel_id:
			_request_channels.erase(request_id)


func _build_generation_prompt(topic: ChatTopic) -> String:
	var session: Dictionary = _sessions.get(topic.channel_id, {})
	var context: Dictionary = _dictionary_value(session.get("context", {}))
	var speakers: Array[String] = _string_array(session.get("speakers", []))
	if "player" not in speakers:
		speakers.append("player")
	var paths: Array[String] = _string_array(session.get("variable_paths", []))
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
