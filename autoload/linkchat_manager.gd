extends Node
## LinkChat 账号、好友关系与私聊消息的运行时入口。
## 角色资料来自 Resource，好友与消息状态由 GameState 持久化。

signal friendship_changed(character_id: String, is_friend: bool)
signal friends_reloaded()
signal message_appended(message: Dictionary)
signal messages_reloaded()

const CHARACTER_CATALOG_PATH: String = "res://resources/characters/character_catalog.tres"

var _catalog: CharacterCatalog = null


func _ready() -> void:
	_load_catalog()
	var game_state: Node = _get_game_state()
	if game_state != null and game_state.has_signal("state_loaded") \
		and not game_state.state_loaded.is_connected(_on_game_state_loaded):
		game_state.state_loaded.connect(_on_game_state_loaded)
	_ensure_initial_state()
	call_deferred("_connect_topic_manager")


func get_character(character_id: String) -> CharacterProfile:
	return _catalog.get_character(character_id) if _catalog != null else null


func get_player_character() -> CharacterProfile:
	return _catalog.get_player_character() if _catalog != null else null


func get_friend_characters() -> Array[CharacterProfile]:
	var result: Array[CharacterProfile] = []
	var game_state: Node = _get_game_state()
	if game_state == null:
		return result
	for character_id: String in game_state.linkchat_friend_ids:
		var character: CharacterProfile = get_character(character_id)
		if character != null and character.linkchat_profile != null:
			result.append(character)
	return result


func is_friend(character_id: String) -> bool:
	var game_state: Node = _get_game_state()
	return game_state != null and character_id in game_state.linkchat_friend_ids


func add_friend(character_id: String) -> bool:
	var character: CharacterProfile = get_character(character_id)
	var game_state: Node = _get_game_state()
	if character == null or character.linkchat_profile == null or game_state == null:
		return false
	if character_id in game_state.linkchat_friend_ids:
		return true
	game_state.linkchat_friend_ids.append(character_id)
	friendship_changed.emit(character_id, true)
	return true


func remove_friend(character_id: String) -> bool:
	var game_state: Node = _get_game_state()
	if game_state == null or character_id not in game_state.linkchat_friend_ids:
		return false
	game_state.linkchat_friend_ids.erase(character_id)
	friendship_changed.emit(character_id, false)
	return true


func append_message(
	channel_id: String,
	sender_id: String,
	content: String,
	attachment: Dictionary = {},
	source_session_id: String = ""
) -> Dictionary:
	var game_state: Node = _get_game_state()
	var normalized_channel: String = channel_id.strip_edges()
	var normalized_sender: String = sender_id.strip_edges()
	var normalized_content: String = content.strip_edges()
	if game_state == null or normalized_channel.is_empty() or normalized_sender.is_empty():
		return {}
	if normalized_content.is_empty() and attachment.is_empty():
		return {}
	game_state.linkchat_message_serial += 1
	var message: Dictionary = {
		"message_id": "linkchat_message_%07d" % game_state.linkchat_message_serial,
		"channel_id": normalized_channel,
		"sender_id": normalized_sender,
		"content": normalized_content,
		"attachment": attachment.duplicate(true),
		"source_session_id": source_session_id.strip_edges(),
		"game_day": int(game_state.get("day")),
		"time_slot": int(game_state.get("time_slot")),
		"created_at": int(Time.get_unix_time_from_system()),
	}
	game_state.linkchat_messages.append(message)
	message_appended.emit(message.duplicate(true))
	return message


func make_location_card(
	activity_id: String,
	place_id: String,
	title: String,
	subtitle: String,
	price_text: String,
	cover_path: String
) -> Dictionary:
	return {
		"type": "location",
		"activity_id": activity_id,
		"place_id": place_id,
		"title": title,
		"subtitle": subtitle,
		"price_text": price_text,
		"source": cover_path,
		"target_app": "cityhop",
		"footer": "在 CityHop 中查看",
	}


func get_thread_messages(channel_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var game_state: Node = _get_game_state()
	if game_state == null:
		return result
	var normalized_channel: String = channel_id.strip_edges()
	for message_value: Variant in game_state.linkchat_messages:
		if not message_value is Dictionary:
			continue
		var message: Dictionary = message_value
		if str(message.get("channel_id", "")) == normalized_channel:
			result.append(message.duplicate(true))
	return result


func get_topic_transcript(topic_id: String) -> String:
	var normalized_topic_id: String = topic_id.strip_edges()
	if normalized_topic_id.is_empty():
		return ""
	var game_state: Node = _get_game_state()
	if game_state == null:
		return ""
	var lines: Array[String] = []
	for message_value: Variant in game_state.linkchat_messages:
		if not message_value is Dictionary:
			continue
		var message: Dictionary = message_value as Dictionary
		if str(message.get("source_session_id", "")) != normalized_topic_id:
			continue
		var sender_id: String = str(message.get("sender_id", ""))
		var sender: CharacterProfile = get_character(sender_id)
		var sender_name: String = sender.display_name if sender != null else sender_id
		var content: String = str(message.get("content", "")).strip_edges()
		if not content.is_empty():
			lines.append("%s：%s" % [sender_name, content])
		var attachment_value: Variant = message.get("attachment", {})
		if attachment_value is Dictionary:
			var attachment: Dictionary = attachment_value as Dictionary
			if str(attachment.get("type", "")) == "location":
				var card_parts: Array[String] = []
				for field: String in ["title", "subtitle", "price_text"]:
					var field_text: String = str(attachment.get(field, "")).strip_edges()
					if not field_text.is_empty():
						card_parts.append(field_text)
				if not card_parts.is_empty():
					lines.append("%s发送了地点卡：%s" % [sender_name, "｜".join(card_parts)])
	return "\n".join(lines)


func get_thread_channel_ids() -> Array[String]:
	var result: Array[String] = []
	var game_state: Node = _get_game_state()
	if game_state == null:
		return result
	for message_value: Variant in game_state.linkchat_messages:
		if not message_value is Dictionary:
			continue
		var channel_id: String = str((message_value as Dictionary).get("channel_id", "")).strip_edges()
		if not channel_id.is_empty() and channel_id not in result:
			result.append(channel_id)
	return result


func reset_runtime_state(seed_initial_friends: bool = true) -> void:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	game_state.linkchat_initialized = not seed_initial_friends
	game_state.linkchat_friend_ids.clear()
	game_state.linkchat_messages.clear()
	game_state.linkchat_message_serial = 0
	if seed_initial_friends:
		_ensure_initial_state()
	friends_reloaded.emit()
	messages_reloaded.emit()


func _load_catalog() -> void:
	if not ResourceLoader.exists(CHARACTER_CATALOG_PATH):
		push_error("LinkChatManager: character catalog not found")
		return
	_catalog = ResourceLoader.load(CHARACTER_CATALOG_PATH) as CharacterCatalog
	if _catalog == null:
		push_error("LinkChatManager: character catalog is invalid")


func _ensure_initial_state() -> void:
	var game_state: Node = _get_game_state()
	if game_state == null or game_state.linkchat_initialized:
		return
	game_state.linkchat_friend_ids.clear()
	if _catalog != null:
		for character: CharacterProfile in _catalog.get_linkchat_characters():
			if character.linkchat_profile.initially_friend:
				game_state.linkchat_friend_ids.append(character.character_id)
	game_state.linkchat_initialized = true


func _on_game_state_loaded() -> void:
	_ensure_initial_state()
	friends_reloaded.emit()
	messages_reloaded.emit()


func _connect_topic_manager() -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director == null or not story_director.has_method("get_topic_manager"):
		return
	var topic_manager: Node = story_director.call("get_topic_manager") as Node
	if topic_manager == null or not topic_manager.has_signal("topic_message_emitted"):
		return
	var callback := Callable(self, "_on_topic_message_emitted")
	if not topic_manager.is_connected("topic_message_emitted", callback):
		topic_manager.connect("topic_message_emitted", callback)


func _on_topic_message_emitted(
	topic: Resource,
	speaker_id: String,
	text: String,
	is_player: bool,
	card: Dictionary
) -> void:
	if topic == null or not "channel_id" in topic:
		return
	var sender_id: String = speaker_id
	if is_player:
		var player: CharacterProfile = get_player_character()
		sender_id = player.character_id if player != null else "player"
	append_message(str(topic.channel_id), sender_id, text, _resolve_card(card), str(topic.topic_id))


## 运行时补全卡片展示数据：location 卡只携带 activity_id，展示字段由资源目录填充。
func _resolve_card(card: Dictionary) -> Dictionary:
	if str(card.get("type", "")) != "location":
		return card.duplicate(true)
	var outing_manager: Node = get_node_or_null("/root/OutingManager")
	if outing_manager == null or not outing_manager.has_method("get_catalog"):
		return card.duplicate(true)
	var activity_id: String = str(card.get("activity_id", "")).strip_edges()
	var catalog: Resource = outing_manager.call("get_catalog")
	if catalog == null or not catalog.has_method("get_activity"):
		return card.duplicate(true)
	var activity: Resource = catalog.call("get_activity", activity_id)
	if activity == null:
		return card.duplicate(true)
	var place_id: String = str(activity.get("place_id")).strip_edges()
	var place: Resource = null
	if catalog.has_method("get_place"):
		place = catalog.call("get_place", place_id)
	var date_cost: int = int(activity.get("date_cost"))
	var cost_text: String = "免费"
	if date_cost > 0:
		cost_text = "约会合计 ¥%d" % date_cost
	return {
		"type": "location",
		"activity_id": activity_id,
		"place_id": place_id,
		"title": str(activity.get("title")),
		"subtitle": str(place.get("display_name") if place != null else place_id),
		"price_text": cost_text,
		"target_app": "cityhop",
		"footer": "在 CityHop 中查看",
	}


func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")
