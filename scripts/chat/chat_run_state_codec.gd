class_name ChatRunStateCodec extends RefCounted
## LinkChat 运行态序列化/恢复辅助

const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")
const TopicManagerClass = preload("res://scripts/chat/topic_manager.gd")

var _add_channel_callback: Callable = Callable()
var _get_channel_callback: Callable = Callable()
var _build_moment_author_callback: Callable = Callable()


func setup(
	add_channel_callback: Callable,
	get_channel_callback: Callable,
	build_moment_author_callback: Callable
) -> ChatRunStateCodec:
	_add_channel_callback = add_channel_callback
	_get_channel_callback = get_channel_callback
	_build_moment_author_callback = build_moment_author_callback
	return self


func build_run_state(
	channels: Dictionary,
	channel_order: Array[String],
	moments: Array[Dictionary],
	moments_unread: int,
	last_activated_topic_channel_id: String,
	topic_manager: Node,
	debug_mode: bool
) -> Dictionary:
	var topic_history: Array[Dictionary] = []
	var typed_topic_manager := topic_manager as TopicManagerClass
	if typed_topic_manager != null:
		topic_history = typed_topic_manager.topic_history.duplicate(true)
	return {
		"channels": _serialize_channels(channels, channel_order),
		"moments": moments.duplicate(true),
		"moments_unread": moments_unread,
		"last_activated_topic_channel_id": last_activated_topic_channel_id,
		"topic_history": topic_history,
		"debug_mode": debug_mode,
	}


func load_run_state(data: Dictionary, default_debug_mode: bool, topic_manager: Node = null) -> Dictionary:
	if data.is_empty():
		return {
			"moments": [] as Array[Dictionary],
			"moments_unread": 0,
			"last_activated_topic_channel_id": "",
			"debug_mode": default_debug_mode,
		}

	_restore_channels(data.get("channels", []))
	var restored_moments := _restore_moments(data.get("moments", []))

	var typed_topic_manager := topic_manager as TopicManagerClass
	if typed_topic_manager != null:
		if typed_topic_manager.has_method("reset_runtime_state"):
			typed_topic_manager.reset_runtime_state(true)
		typed_topic_manager.topic_history.clear()
		for item in data.get("topic_history", []):
			if item is Dictionary:
				typed_topic_manager.topic_history.append((item as Dictionary).duplicate(true))

	return {
		"moments": restored_moments,
		"moments_unread": max(0, int(data.get("moments_unread", 0))),
		"last_activated_topic_channel_id": str(data.get("last_activated_topic_channel_id", "")).strip_edges(),
		"debug_mode": bool(data.get("debug_mode", default_debug_mode)),
	}


func _serialize_channels(channels: Dictionary, channel_order: Array[String]) -> Array[Dictionary]:
	var channels_state: Array[Dictionary] = []
	for channel_id in channel_order:
		var channel = channels.get(channel_id)
		if channel == null:
			continue
		channels_state.append({
			"channel_id": channel.channel_id,
			"display_name": channel.display_name,
			"channel_prompt": channel.channel_prompt,
			"channel_type": int(channel.channel_type),
			"members": channel.members.duplicate(),
			"pinned": channel.pinned,
			"unread_count": channel.unread_count,
			"messages": channel.messages.duplicate(true),
		})
	return channels_state


func _restore_channels(channels_state: Variant) -> void:
	if not (channels_state is Array):
		return
	if _add_channel_callback.is_null() or _get_channel_callback.is_null():
		return

	for item in channels_state:
		if not item is Dictionary:
			continue
		var channel_data: Dictionary = item
		var channel_id: String = str(channel_data.get("channel_id", "")).strip_edges()
		if channel_id.is_empty():
			continue

		_add_channel_callback.call(
			channel_id,
			str(channel_data.get("display_name", channel_id)),
			int(channel_data.get("channel_type", ChatChannelClass.ChannelType.SOCIAL)),
			channel_data.get("members", [])
		)

		var channel := _get_channel_callback.call(channel_id) as ChatChannelClass
		if channel == null:
			continue
		channel.channel_prompt = str(channel_data.get("channel_prompt", ""))
		channel.pinned = bool(channel_data.get("pinned", false))
		channel.unread_count = max(0, int(channel_data.get("unread_count", 0)))
		var restored_messages: Array[Dictionary] = []
		for msg in channel_data.get("messages", []):
			if msg is Dictionary:
				restored_messages.append((msg as Dictionary).duplicate(true))
		channel.messages = restored_messages


func _restore_moments(moments_state: Variant) -> Array[Dictionary]:
	var restored: Array[Dictionary] = []
	if not (moments_state is Array):
		return restored

	for item in moments_state:
		if not item is Dictionary:
			continue
		var moment := (item as Dictionary).duplicate(true)
		if not moment.has("author") and not _build_moment_author_callback.is_null():
			moment["author"] = _build_moment_author_callback.call(str(moment.get("npc_id", "")).strip_edges())
		restored.append(moment)
	return restored
