extends Node
## LinkChat 账号、好友关系与朋友圈发布记录的运行时入口。
## 角色资料和纯内容来自 Resource，好友与发布状态由 GameState 持久化。

signal friendship_changed(character_id: String, is_friend: bool)
signal friends_reloaded()
signal moment_published(post: MomentPostRecord)
signal moment_like_changed(post_id: String, liked: bool, likes: int)
signal moment_commented(post_id: String, comment: MomentCommentRecord)
signal moments_reloaded()
signal message_appended(message: Dictionary)
signal messages_reloaded()

const CHARACTER_CATALOG_PATH: String = "res://resources/characters/character_catalog.tres"

var _catalog: CharacterCatalog = null
var _posts: Array[MomentPostRecord] = []


func _ready() -> void:
	_load_catalog()
	var game_state: Node = _get_game_state()
	if game_state != null and game_state.has_signal("state_loaded") \
		and not game_state.state_loaded.is_connected(_on_game_state_loaded):
		game_state.state_loaded.connect(_on_game_state_loaded)
	_reload_posts_from_game_state()
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


func publish_moment(
	character_id: String,
	text_content: String,
	texture_content: Texture2D = null
) -> MomentPostRecord:
	var content := MomentContent.new()
	content.text_content = text_content
	content.texture_content = texture_content
	return publish_moment_content(character_id, content)


func publish_character_moment(character_id: String, moment_id: String) -> MomentPostRecord:
	var character: CharacterProfile = get_character(character_id)
	if character == null or character.linkchat_profile == null:
		return null
	var content: MomentContent = character.linkchat_profile.get_moment_content(moment_id)
	return publish_moment_content(character_id, content)


func publish_moment_content(
	character_id: String,
	content: MomentContent
) -> MomentPostRecord:
	var character: CharacterProfile = get_character(character_id)
	var game_state: Node = _get_game_state()
	if character == null or character.linkchat_profile == null or content == null \
		or content.is_empty() or game_state == null:
		return null

	game_state.linkchat_moment_serial += 1
	var record := MomentPostRecord.new()
	record.post_id = "moment_%06d" % game_state.linkchat_moment_serial
	record.character_id = character_id
	record.content = content.duplicate(true) as MomentContent
	record.published_at = int(Time.get_unix_time_from_system())
	_posts.push_front(record)
	_sync_posts_to_game_state()
	moment_published.emit(record)
	return record


func get_visible_moments() -> Array[MomentPostRecord]:
	var result: Array[MomentPostRecord] = []
	var player: CharacterProfile = get_player_character()
	var player_id: String = player.character_id if player != null else ""
	for post: MomentPostRecord in _posts:
		if post != null and (post.character_id == player_id or is_friend(post.character_id)):
			result.append(post)
	return result


func get_visible_moment_view_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for post: MomentPostRecord in get_visible_moments():
		result.append(make_moment_view_data(post))
	return result


func make_moment_view_data(post: MomentPostRecord) -> Dictionary:
	if post == null:
		return {}
	var character: CharacterProfile = get_character(post.character_id)
	var profile: LinkChatProfile = character.linkchat_profile if character != null else null
	return {
		"id": post.post_id,
		"character_id": post.character_id,
		"author_name": profile.account_name if profile != null else post.character_id,
		"avatar": profile.avatar if profile != null else null,
		"content": post.content.text_content if post.content != null else "",
		"image": post.content.texture_content if post.content != null else null,
		"time": _format_post_time(post.published_at),
		"liked": post.liked,
		"likes": post.likes,
		"comments": _make_comment_view_data(post.comments),
	}


func set_moment_liked(post_id: String, liked: bool) -> bool:
	for post: MomentPostRecord in _posts:
		if post == null or post.post_id != post_id:
			continue
		if post.liked == liked:
			return true
		post.liked = liked
		post.likes = maxi(post.likes + (1 if liked else -1), 0)
		_sync_posts_to_game_state()
		moment_like_changed.emit(post_id, liked, post.likes)
		return true
	return false


func add_moment_comment(
	post_id: String,
	character_id: String,
	text_content: String
) -> MomentCommentRecord:
	var character: CharacterProfile = get_character(character_id)
	var normalized_text: String = text_content.strip_edges()
	if character == null or character.linkchat_profile == null or normalized_text.is_empty():
		return null
	for post: MomentPostRecord in _posts:
		if post == null or post.post_id != post_id:
			continue
		var comment := MomentCommentRecord.new()
		comment.comment_id = "%s_comment_%03d" % [post_id, post.comments.size() + 1]
		comment.character_id = character_id
		comment.text_content = normalized_text
		comment.published_at = int(Time.get_unix_time_from_system())
		post.comments.append(comment)
		_sync_posts_to_game_state()
		moment_commented.emit(post_id, comment)
		return comment
	return null


func _make_comment_view_data(comments: Array[MomentCommentRecord]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for comment: MomentCommentRecord in comments:
		if comment == null:
			continue
		var character: CharacterProfile = get_character(comment.character_id)
		var profile: LinkChatProfile = character.linkchat_profile if character != null else null
		result.append({
			"id": comment.comment_id,
			"character_id": comment.character_id,
			"author_name": profile.account_name if profile != null else comment.character_id,
			"content": comment.text_content,
			"time": _format_post_time(comment.published_at),
		})
	return result


func reset_runtime_state(seed_initial_friends: bool = true) -> void:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	game_state.linkchat_initialized = not seed_initial_friends
	game_state.linkchat_friend_ids.clear()
	game_state.linkchat_moment_posts.clear()
	game_state.linkchat_moment_serial = 0
	game_state.linkchat_messages.clear()
	game_state.linkchat_message_serial = 0
	_posts.clear()
	if seed_initial_friends:
		_ensure_initial_state()
	friends_reloaded.emit()
	moments_reloaded.emit()
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


func _reload_posts_from_game_state() -> void:
	_posts.clear()
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	for value: Variant in game_state.linkchat_moment_posts:
		if value is Dictionary:
			_posts.append(MomentPostRecord.from_dict(value))


func _sync_posts_to_game_state() -> void:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	game_state.linkchat_moment_posts.clear()
	for post: MomentPostRecord in _posts:
		if post != null:
			game_state.linkchat_moment_posts.append(post.to_dict())


func _on_game_state_loaded() -> void:
	_reload_posts_from_game_state()
	_ensure_initial_state()
	friends_reloaded.emit()
	moments_reloaded.emit()
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
	append_message(str(topic.channel_id), sender_id, text, card.duplicate(true), str(topic.topic_id))


func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _format_post_time(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var value: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d-%02d %02d:%02d" % [
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
	]
