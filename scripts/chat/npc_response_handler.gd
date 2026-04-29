class_name NPCResponseHandler extends Node
## NPC回复处理器
## 解析AI结构化输出，逐条显示消息（打字机效果）

## 单条消息显示完成
signal message_displayed(npc_id: String, content: String)

## 所有消息显示完成
signal all_messages_displayed(npc_id: String)

## 开始输入提示
signal typing_started(npc_id: String)

## 结束输入提示
signal typing_ended(npc_id: String)


## 处理AI回复的JSON，逐条延迟显示
func handle_response(response_json: Dictionary, npc_id: String) -> Array[String]:
	var messages: Array[String] = []

	if response_json.has("messages") and response_json.messages is Array:
		for msg in response_json.messages:
			if msg is String:
				messages.append(msg)

	if messages.is_empty():
		return messages

	typing_started.emit(npc_id)

	for i in messages.size():
		var msg: String = messages[i]

		# 根据消息长度计算延迟
		var delay := calculate_typing_delay(msg)
		await get_tree().create_timer(delay).timeout

		message_displayed.emit(npc_id, msg)

		# 消息之间的随机间隔（模拟思考）
		if i < messages.size() - 1:
			var pause := randf_range(0.5, 1.5)
			await get_tree().create_timer(pause).timeout

	typing_ended.emit(npc_id)
	all_messages_displayed.emit(npc_id)

	return messages


## 根据消息长度动态计算延迟
static func calculate_typing_delay(message: String) -> float:
	var chars_per_second: float = 20.0

	# 计算字符数（非ASCII算2个字符）
	var char_count: int = 0
	for i in message.length():
		if message.unicode_at(i) > 127:
			char_count += 2
		else:
			char_count += 1

	var base_delay := float(char_count) / chars_per_second
	var random_factor := randf_range(0.8, 1.2)

	return clampf(base_delay * random_factor, 0.5, 5.0)


## 从AI回复中检查是否包含Topic完成标记
static func check_topic_complete(response_json: Dictionary) -> bool:
	if not response_json.has("messages"):
		return false

	var messages: Array = response_json.messages
	if messages.is_empty():
		return false

	var last_msg: String = str(messages[-1])
	return "[TOPIC_COMPLETE]" in last_msg or "[TOPIC_FAILED]" in last_msg


## 清理消息中的标记
static func clean_message(message: String) -> String:
	return message.replace("[TOPIC_COMPLETE]", "").replace("[TOPIC_FAILED]", "").strip_edges()
