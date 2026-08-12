extends Node
## 叙事邮件的运行时入口。邮件内容不依赖角色、联系人或其它玩法系统。

signal mail_received(mail: Dictionary)
signal mail_read_changed(mail_id: String, is_read: bool)
signal mailbox_reloaded()


func _ready() -> void:
	var game_state: Node = _get_game_state()
	if game_state != null and game_state.has_signal("state_loaded") \
		and not game_state.state_loaded.is_connected(_on_game_state_loaded):
		game_state.state_loaded.connect(_on_game_state_loaded)


func receive_mail(
	sender_name: String,
	sender_address: String,
	subject: String,
	body: String,
	sent_at: String = "",
	source_session_id: String = ""
) -> Dictionary:
	var game_state: Node = _get_game_state()
	var normalized_sender: String = sender_name.strip_edges()
	var normalized_subject: String = subject.strip_edges()
	var normalized_body: String = body.strip_edges()
	if game_state == null or normalized_sender.is_empty() or normalized_subject.is_empty():
		return {}
	game_state.mail_message_serial += 1
	var mail: Dictionary = {
		"mail_id": "mail_%07d" % game_state.mail_message_serial,
		"sender_name": normalized_sender,
		"sender_address": sender_address.strip_edges(),
		"subject": normalized_subject,
		"body": normalized_body,
		"sent_at": sent_at.strip_edges(),
		"source_session_id": source_session_id.strip_edges(),
		"received_game_day": int(game_state.get("day")),
		"received_time_slot": int(game_state.get("time_slot")),
		"received_at": int(Time.get_unix_time_from_system()),
		"is_read": false,
	}
	game_state.mail_messages.append(mail)
	mail_received.emit(mail.duplicate(true))
	return mail.duplicate(true)


func get_messages() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var game_state: Node = _get_game_state()
	if game_state == null:
		return result
	for index: int in range(game_state.mail_messages.size() - 1, -1, -1):
		result.append(game_state.mail_messages[index].duplicate(true))
	return result


func get_mail(mail_id: String) -> Dictionary:
	var game_state: Node = _get_game_state()
	var normalized_id: String = mail_id.strip_edges()
	if game_state == null or normalized_id.is_empty():
		return {}
	for mail: Dictionary in game_state.mail_messages:
		if str(mail.get("mail_id", "")) == normalized_id:
			return mail.duplicate(true)
	return {}


func mark_read(mail_id: String, is_read: bool = true) -> bool:
	var game_state: Node = _get_game_state()
	var normalized_id: String = mail_id.strip_edges()
	if game_state == null or normalized_id.is_empty():
		return false
	for mail: Dictionary in game_state.mail_messages:
		if str(mail.get("mail_id", "")) != normalized_id:
			continue
		if bool(mail.get("is_read", false)) == is_read:
			return true
		mail["is_read"] = is_read
		mail_read_changed.emit(normalized_id, is_read)
		return true
	return false


func get_unread_count() -> int:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return 0
	var count: int = 0
	for mail: Dictionary in game_state.mail_messages:
		if not bool(mail.get("is_read", false)):
			count += 1
	return count


func reset_runtime_state() -> void:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	game_state.mail_messages.clear()
	game_state.mail_message_serial = 0
	mailbox_reloaded.emit()


func _on_game_state_loaded() -> void:
	mailbox_reloaded.emit()


func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")
