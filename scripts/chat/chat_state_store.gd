class_name ChatStateStore extends RefCounted
## LinkChat 状态存储层
## 持有频道、消息、朋友圈与运行态序列化逻辑

const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")
const ChatRunStateCodecClass = preload("res://scripts/chat/chat_run_state_codec.gd")

signal channel_added(channel_id: String)
signal message_added(channel_id: String, msg_data: Dictionary)
signal moment_posted(moment: Dictionary)
signal state_changed()

var _channels: Dictionary = {}
var _channel_order: Array[String] = []
var _moments: Array[Dictionary] = []
var _moments_unread: int = 0
var _run_state_codec = null


func setup(build_moment_author_callback: Callable) -> ChatStateStore:
	_run_state_codec = ChatRunStateCodecClass.new()
	_run_state_codec.setup(
		Callable(self, "add_channel"),
		Callable(self, "get_channel"),
		build_moment_author_callback
	)
	return self


func register_channel(channel: ChatChannel) -> void:
	if channel == null:
		return
	var channel_id := str(channel.channel_id).strip_edges()
	if channel_id.is_empty():
		return
	channel.channel_id = channel_id
	if not _channels.has(channel_id):
		_channel_order.append(channel_id)
	_channels[channel_id] = channel
	channel_added.emit(channel_id)
	_emit_state_changed()


func add_channel(channel_id: String, display_name: String, channel_type: int, members_list: Array) -> void:
	var channel := ChatChannelClass.new()
	channel.channel_id = channel_id
	channel.display_name = display_name
	channel.channel_type = channel_type as ChatChannelClass.ChannelType
	channel.members.assign(members_list)
	register_channel(channel)


func get_channel(channel_id: String) -> Resource:
	return _channels.get(channel_id)


func get_channel_order() -> Array[String]:
	return _channel_order


func get_channels() -> Dictionary:
	return _channels


func store_message_data(
	channel_id: String,
	sender_id: String,
	sender_name: String,
	message_data: Dictionary
) -> Dictionary:
	var channel := get_channel(channel_id) as ChatChannel
	if channel == null:
		return {}

	var content := str(message_data.get("content", ""))
	var card: Variant = message_data.get("card", {})
	var has_card: bool = card is Dictionary and not (card as Dictionary).is_empty()
	if content.strip_edges().is_empty() and not has_card:
		return {}

	var extras := message_data.duplicate(true)
	extras.erase("speaker")
	extras.erase("content")
	var msg: Dictionary = channel.add_message(sender_id, sender_name, content, extras)
	message_added.emit(channel_id, msg)
	_emit_state_changed()
	return msg


func get_channel_messages_copy(channel_id: String) -> Array[Dictionary]:
	var channel := get_channel(channel_id) as ChatChannel
	if channel == null:
		return []

	var messages: Array[Dictionary] = []
	for msg in channel.messages:
		if msg is Dictionary:
			messages.append((msg as Dictionary).duplicate(true))
	return messages


func clear_all_channel_messages() -> int:
	var cleared_count: int = 0
	for channel_value in _channels.values():
		var channel := channel_value as ChatChannel
		if channel == null:
			continue
		if channel.messages.is_empty() and channel.unread_count <= 0:
			continue
		channel.messages.clear()
		channel.unread_count = 0
		cleared_count += 1
	if cleared_count > 0:
		_emit_state_changed()
	return cleared_count


func store_moment(moment_data: Dictionary, count_as_unread: bool = true) -> Dictionary:
	var moment := moment_data.duplicate(true)
	_moments.insert(0, moment)
	if count_as_unread:
		_moments_unread += 1
	moment_posted.emit(moment)
	_emit_state_changed()
	return moment


func like_moment(moment_id: String) -> bool:
	for i in range(_moments.size()):
		var moment := _moments[i]
		if str(moment.get("id", "")).strip_edges() != moment_id:
			continue
		if bool(moment.get("liked_by_player", false)):
			return false
		moment["liked_by_player"] = true
		moment["likes"] = int(moment.get("likes", 0)) + 1
		_moments[i] = moment
		_emit_state_changed()
		return true
	return false


func get_moments() -> Array[Dictionary]:
	return _moments


func get_moments_unread() -> int:
	return _moments_unread


func clear_moments_unread() -> void:
	if _moments_unread <= 0:
		return
	_moments_unread = 0
	_emit_state_changed()


func set_moments_unread(value: int) -> void:
	_moments_unread = max(0, value)
	_emit_state_changed()


func build_run_state(
	last_activated_topic_channel_id: String,
	topic_manager: Node,
	debug_mode: bool
) -> Dictionary:
	if _run_state_codec == null:
		return {}
	return _run_state_codec.build_run_state(
		_channels,
		_channel_order,
		_moments,
		_moments_unread,
		last_activated_topic_channel_id,
		topic_manager,
		debug_mode
	)


func load_run_state(data: Dictionary, default_debug_mode: bool, topic_manager: Node = null) -> Dictionary:
	if data.is_empty():
		return {
			"moments": [] as Array[Dictionary],
			"moments_unread": 0,
			"last_activated_topic_channel_id": "",
			"debug_mode": default_debug_mode,
		}
	if _run_state_codec == null:
		return {
			"moments": [] as Array[Dictionary],
			"moments_unread": 0,
			"last_activated_topic_channel_id": "",
			"debug_mode": default_debug_mode,
		}

	reset_runtime_state(false)
	var restored: Dictionary = _run_state_codec.load_run_state(data, default_debug_mode, topic_manager)
	var restored_moments: Variant = restored.get("moments", [])
	if restored_moments is Array:
		for moment in restored_moments:
			if moment is Dictionary:
				_moments.append((moment as Dictionary).duplicate(true))
	_moments_unread = max(0, int(restored.get("moments_unread", 0)))
	_emit_state_changed()
	return restored


func serialize_channels() -> Array[Dictionary]:
	if _run_state_codec == null:
		return []
	var state: Dictionary = build_run_state("", null, true)
	var channels_state: Variant = state.get("channels", [])
	if channels_state is Array:
		return channels_state
	return []


func restore_channels(channels_state: Variant, default_debug_mode: bool = true) -> void:
	if _run_state_codec == null:
		return
	reset_runtime_state(false, true, false)
	_run_state_codec.load_run_state({
		"channels": channels_state,
		"moments": [],
		"moments_unread": 0,
		"last_activated_topic_channel_id": "",
		"topic_history": [],
		"debug_mode": default_debug_mode,
	}, default_debug_mode, null)
	_emit_state_changed()


func restore_moments(moments_state: Variant, default_debug_mode: bool = true) -> void:
	if _run_state_codec == null:
		return
	reset_runtime_state(false, false, true)
	var restored: Dictionary = _run_state_codec.load_run_state({
		"channels": [],
		"moments": moments_state,
		"moments_unread": 0,
		"last_activated_topic_channel_id": "",
		"topic_history": [],
		"debug_mode": default_debug_mode,
	}, default_debug_mode, null)
	var restored_moments: Variant = restored.get("moments", [])
	if restored_moments is Array:
		for moment in restored_moments:
			if moment is Dictionary:
				_moments.append((moment as Dictionary).duplicate(true))
	_emit_state_changed()


func reset_runtime_state(
	emit_change: bool = true,
	clear_channels: bool = true,
	clear_moments: bool = true
) -> void:
	if clear_channels:
		_channels.clear()
		_channel_order.clear()
	if clear_moments:
		_moments.clear()
		_moments_unread = 0
	if emit_change:
		_emit_state_changed()


func _emit_state_changed() -> void:
	state_changed.emit()
