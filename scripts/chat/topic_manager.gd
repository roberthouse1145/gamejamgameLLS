class_name TopicManager extends Node
## Topic管理器
## 管理ChatTopic的激活、完成、超时生命周期
## 只有激活Topic时玩家才能在对应频道输入

## Topic激活
signal topic_activated(topic: ChatTopic)

## Topic完成（携带结果）
signal topic_completed(topic: ChatTopic, result: Dictionary)

## Topic超时
signal topic_timeout(topic: ChatTopic)

## 活跃的Topic：channel_id -> ChatTopic
var active_topics: Dictionary = {}

## Topic历史记录
var topic_history: Array[Dictionary] = []


## 激活一个Topic
func activate_topic(topic: ChatTopic) -> bool:
	if topic == null:
		push_warning("TopicManager: Cannot activate null topic")
		return false

	# 检查频道是否已有活跃Topic
	if active_topics.has(topic.channel_id):
		push_warning("TopicManager: Channel '%s' already has active topic" % topic.channel_id)
		return false

	topic.is_active = true
	topic.turn_count = 0
	topic.start_time = int(Time.get_unix_time_from_system())

	active_topics[topic.channel_id] = topic

	# 启动超时计时器
	if topic.timeout_seconds > 0:
		_start_timeout_timer(topic)

	topic_activated.emit(topic)
	return true


## 完成一个Topic
func complete_topic(topic: ChatTopic, result: Dictionary = {}) -> void:
	if topic == null or not topic.is_active:
		return

	topic.is_active = false
	topic.result_variables = result
	active_topics.erase(topic.channel_id)

	_stop_timeout_timer(topic)

	# 保存到历史
	topic_history.append({
		"topic_id": topic.topic_id,
		"topic_type": topic.topic_type,
		"npc_id": topic.npc_id,
		"result": result,
		"completed_at": Time.get_unix_time_from_system(),
	})

	topic_completed.emit(topic, result)


## 超时一个Topic
func timeout_topic(topic: ChatTopic) -> void:
	if topic == null or not topic.is_active:
		return

	topic.is_active = false
	active_topics.erase(topic.channel_id)
	_stop_timeout_timer(topic)

	topic_history.append({
		"topic_id": topic.topic_id,
		"topic_type": topic.topic_type,
		"npc_id": topic.npc_id,
		"result": {},
		"timed_out": true,
		"completed_at": Time.get_unix_time_from_system(),
	})

	topic_timeout.emit(topic)


## 增加轮数，返回是否超过最大轮数
func increment_turn(topic: ChatTopic) -> bool:
	topic.turn_count += 1
	if topic.max_turns > 0 and topic.turn_count >= topic.max_turns:
		return true
	return false


## 获取频道的活跃Topic
func get_active_topic(channel_id: String) -> ChatTopic:
	return active_topics.get(channel_id)


## 频道是否有活跃Topic
func has_active_topic(channel_id: String) -> bool:
	return active_topics.has(channel_id)


# --- 超时计时器管理 ---

var _timeout_timers: Dictionary = {}  # topic_id -> Timer


func reset_runtime_state(clear_history: bool = false) -> void:
	for timer in _timeout_timers.values():
		if timer is Timer:
			timer.stop()
			timer.queue_free()
	_timeout_timers.clear()
	active_topics.clear()
	if clear_history:
		topic_history.clear()


func _start_timeout_timer(topic: ChatTopic) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = topic.timeout_seconds
	timer.timeout.connect(_on_topic_timeout.bind(topic))
	add_child(timer)
	timer.start()
	_timeout_timers[topic.topic_id] = timer


func _stop_timeout_timer(topic: ChatTopic) -> void:
	if _timeout_timers.has(topic.topic_id):
		var timer: Timer = _timeout_timers[topic.topic_id]
		timer.stop()
		timer.queue_free()
		_timeout_timers.erase(topic.topic_id)


func _on_topic_timeout(topic: ChatTopic) -> void:
	_stop_timeout_timer(topic)
	timeout_topic(topic)
