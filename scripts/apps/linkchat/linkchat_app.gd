class_name LinkChatApp extends Control
## 复用原 LinkChat 窗口与消息组件，数据源来自 StoryDirector/TopicManager。

const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const MessageBubbleClass = preload("res://scripts/apps/linkchat/components/message_bubble.gd")
const ContactItemScene = preload("res://scenes/apps/linkchat/contact_item.tscn")
const MomentsPanelScene = preload("res://scenes/apps/linkchat/moments_panel.tscn")

enum NavPage {CHAT, MOMENTS}

## 消息自动推进节奏：短消息至少停留 MIN_ADVANCE_DELAY，长消息按字数加时；玩家点击可立即继续
const MIN_ADVANCE_DELAY: float = 1.2
const ADVANCE_CHAR_SECONDS: float = 0.06
const MAX_ADVANCE_DELAY: float = 6.0

@onready var background: ColorRect = $Background
@onready var nav_strip: PanelContainer = %NavStrip
@onready var nav_avatar: RoundedAvatar = %NavAvatar
@onready var nav_chat_btn: Button = %NavChatBtn
@onready var nav_moments_btn: Button = %NavMomentsBtn
@onready var nav_settings_btn: Button = %NavSettingsBtn
@onready var sidebar: PanelContainer = %Sidebar
@onready var app_title: Label = %AppTitle
@onready var contact_caption: Label = %ContactCaption
@onready var contact_list: VBoxContainer = %ContactList
@onready var sidebar_border: VSeparator = %SidebarBorder
@onready var chat_header: PanelContainer = %ChatHeader
@onready var channel_title: Label = %ChannelTitle
@onready var channel_subtitle: Label = %ChannelSubtitle
@onready var topic_info: Label = %TopicInfo
@onready var message_stage: Control = %MessageStage
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var message_list: VBoxContainer = %MessageList
@onready var input_area: PanelContainer = %InputArea
@onready var input_field: LineEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var recommend_container: VBoxContainer = %RecommendRepliesContainer
@onready var input_hbox: HBoxContainer = %InputHBox
@onready var batch_indicator: Label = %BatchIndicator
@onready var typing_indicator: Label = %TypingIndicator
@onready var moments_container: VBoxContainer = %MomentsContainer

var _topic_manager: Node = null
var _linkchat_manager: Node = null
var _player_character: CharacterProfile = null
var _current_channel_id: String = ""
var _advance_generation: int = 0
var _contact_items: Dictionary = {}
var _moments_panel: LinkChatMomentsPanel = null
var _current_page: NavPage = NavPage.CHAT


func _ready() -> void:
	_connect_linkchat_manager()
	_apply_original_theme()
	_setup_original_layout()
	_render_friend_contacts()
	_setup_navigation()
	_connect_topic_manager()
	_connect_click_to_advance()


func open_topic_channel(channel_id: String) -> void:
	_current_channel_id = channel_id
	_show_page(NavPage.CHAT)
	_render_contact(channel_id)
	_render_thread(channel_id)


func _connect_topic_manager() -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director == null or not story_director.has_method("get_topic_manager"):
		topic_info.text = "聊天服务暂不可用"
		return
	_topic_manager = story_director.get_topic_manager()
	if _topic_manager == null:
		topic_info.text = "聊天服务暂不可用"
		return
	_topic_manager.topic_activated.connect(_on_topic_activated)
	_topic_manager.topic_message_emitted.connect(_on_topic_message_emitted)
	_topic_manager.topic_choices_presented.connect(_on_topic_choices_presented)
	_topic_manager.topic_completed.connect(_on_topic_completed)
	_topic_manager.topic_cancelled.connect(_on_topic_cancelled)


func _connect_linkchat_manager() -> void:
	_linkchat_manager = get_node_or_null("/root/LinkChatManager")
	if _linkchat_manager == null:
		return
	_player_character = _linkchat_manager.call("get_player_character") as CharacterProfile
	if not _linkchat_manager.friendship_changed.is_connected(_on_friendship_changed):
		_linkchat_manager.friendship_changed.connect(_on_friendship_changed)
	if not _linkchat_manager.friends_reloaded.is_connected(_on_friends_reloaded):
		_linkchat_manager.friends_reloaded.connect(_on_friends_reloaded)
	if not _linkchat_manager.moment_published.is_connected(_on_moment_published):
		_linkchat_manager.moment_published.connect(_on_moment_published)
	if not _linkchat_manager.moment_commented.is_connected(_on_moment_commented):
		_linkchat_manager.moment_commented.connect(_on_moment_commented)
	if not _linkchat_manager.moments_reloaded.is_connected(_on_moments_reloaded):
		_linkchat_manager.moments_reloaded.connect(_on_moments_reloaded)
	if not _linkchat_manager.message_appended.is_connected(_on_message_appended):
		_linkchat_manager.message_appended.connect(_on_message_appended)
	if not _linkchat_manager.messages_reloaded.is_connected(_on_messages_reloaded):
		_linkchat_manager.messages_reloaded.connect(_on_messages_reloaded)


func _apply_original_theme() -> void:
	background.color = LCTheme.COLOR_BG_MAIN
	nav_strip.add_theme_stylebox_override("panel", LCTheme.get_nav_strip_style())
	nav_avatar.set_avatar(
		_character_avatar(_player_character),
		_character_name(_player_character, "我")
	)
	for button: Button in [nav_chat_btn, nav_moments_btn, nav_settings_btn]:
		button.flat = false
		button.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
		button.add_theme_color_override("font_hover_color", LCTheme.COLOR_TEXT_PRIMARY)
		button.add_theme_stylebox_override("normal", LCTheme.get_nav_button_style(false))
		button.add_theme_stylebox_override("hover", LCTheme.get_nav_button_style(true))
		button.add_theme_stylebox_override("pressed", LCTheme.get_nav_button_style(true))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	sidebar.add_theme_stylebox_override("panel", LCTheme.get_sidebar_bg_style())
	app_title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	contact_caption.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	chat_header.add_theme_stylebox_override("panel", LCTheme.get_chat_header_style())
	channel_title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	channel_subtitle.add_theme_color_override("font_color", LCTheme.COLOR_ONLINE)
	topic_info.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	input_area.add_theme_stylebox_override("panel", LCTheme.get_input_area_style())
	input_field.add_theme_stylebox_override("normal", LCTheme.get_input_field_style())
	input_field.add_theme_stylebox_override("focus", LCTheme.get_input_field_focus_style())
	input_field.add_theme_stylebox_override("read_only", LCTheme.get_input_field_disabled_style())
	send_button.add_theme_stylebox_override("normal", LCTheme.get_send_button_style())
	send_button.add_theme_stylebox_override("hover", LCTheme.get_send_button_hover_style())
	send_button.add_theme_stylebox_override("pressed", LCTheme.get_send_button_hover_style())
	send_button.add_theme_stylebox_override("disabled", LCTheme.get_send_button_style())
	send_button.add_theme_color_override("font_disabled_color", Color("#8793A6"))
	send_button.add_theme_color_override("font_hover_color", LCTheme.COLOR_TEXT_PRIMARY)
	send_button.add_theme_color_override("font_hover_pressed_color", LCTheme.COLOR_TEXT_PRIMARY)
	send_button.add_theme_color_override("font_pressed_color", LCTheme.COLOR_TEXT_PRIMARY)
	typing_indicator.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT_HOVER)
	batch_indicator.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	var message_v_scroll: VScrollBar = message_scroll.get_v_scroll_bar()
	message_v_scroll.custom_minimum_size.x = 24
	message_v_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_original_layout() -> void:
	nav_moments_btn.visible = true
	nav_settings_btn.visible = false
	_show_page(NavPage.CHAT)
	channel_title.text = "LinkChat"
	channel_subtitle.text = "等待会话"
	topic_info.text = "等待新消息"
	input_field.editable = false
	input_field.placeholder_text = "剧情消息会自动播放"
	send_button.disabled = true
	recommend_container.visible = false
	input_hbox.visible = true
	typing_indicator.visible = false
	batch_indicator.visible = false


func _setup_navigation() -> void:
	if not nav_chat_btn.pressed.is_connected(_on_chat_nav_pressed):
		nav_chat_btn.pressed.connect(_on_chat_nav_pressed)
	if not nav_moments_btn.pressed.is_connected(_on_moments_nav_pressed):
		nav_moments_btn.pressed.connect(_on_moments_nav_pressed)
	_moments_panel = MomentsPanelScene.instantiate() as LinkChatMomentsPanel
	_moments_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moments_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_moments_panel.set_posts(_visible_moment_view_data())
	_moments_panel.post_liked.connect(_on_moment_like_requested)
	_moments_panel.image_open_requested.connect(_on_moment_image_open_requested)
	moments_container.add_child(_moments_panel)
	_update_nav_highlight()


func _on_chat_nav_pressed() -> void:
	_show_page(NavPage.CHAT)


func _on_moments_nav_pressed() -> void:
	_show_page(NavPage.MOMENTS)


func _show_page(page: NavPage) -> void:
	_current_page = page
	var showing_chat: bool = page == NavPage.CHAT
	sidebar.visible = showing_chat
	sidebar_border.visible = showing_chat
	message_stage.visible = showing_chat
	chat_header.visible = showing_chat
	input_area.visible = showing_chat
	moments_container.visible = not showing_chat
	_update_nav_highlight()


func _update_nav_highlight() -> void:
	var chat_active: bool = _current_page == NavPage.CHAT
	nav_chat_btn.add_theme_stylebox_override("normal", LCTheme.get_nav_button_style(chat_active))
	nav_moments_btn.add_theme_stylebox_override("normal", LCTheme.get_nav_button_style(not chat_active))
	nav_chat_btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY if chat_active else LCTheme.COLOR_TEXT_SECONDARY)
	nav_moments_btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY if not chat_active else LCTheme.COLOR_TEXT_SECONDARY)


func _render_empty_contact() -> void:
	for child: Node in contact_list.get_children():
		child.queue_free()
	var empty_margin := MarginContainer.new()
	empty_margin.add_theme_constant_override("margin_left", 33)
	empty_margin.add_theme_constant_override("margin_top", 33)
	contact_list.add_child(empty_margin)
	var empty_label := Label.new()
	empty_label.text = "暂无会话"
	empty_label.add_theme_font_size_override("font_size", 27)
	empty_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	empty_margin.add_child(empty_label)


func _render_contact(channel_id: String) -> void:
	_current_channel_id = channel_id
	_render_friend_contacts()


func _render_friend_contacts() -> void:
	for child: Node in contact_list.get_children():
		child.queue_free()
	_contact_items.clear()
	if _linkchat_manager == null:
		_render_empty_contact()
		return
	var friends_value: Variant = _linkchat_manager.call("get_friend_characters")
	if not friends_value is Array or friends_value.is_empty():
		_render_empty_contact()
		return
	if _current_channel_id.is_empty():
		var first_character: CharacterProfile = friends_value[0] as CharacterProfile
		if first_character != null:
			_current_channel_id = first_character.character_id
	for character_value: Variant in friends_value:
		var character: CharacterProfile = character_value as CharacterProfile
		if character == null:
			continue
		var item: ChatContactItem = ContactItemScene.instantiate() as ChatContactItem
		item.setup(character.character_id, _character_name(character, character.display_name), _character_avatar(character))
		item.selected.connect(_on_contact_selected)
		contact_list.add_child(item)
		item.set_selected(character.character_id == _current_channel_id)
		_contact_items[character.character_id] = item
	if not _current_channel_id.is_empty():
		var current_character: CharacterProfile = _find_channel_character(_current_channel_id)
		channel_title.text = _character_name(current_character, _current_channel_id)
		channel_subtitle.text = "在线"
		_render_thread(_current_channel_id)


func _on_topic_activated(topic: Resource) -> void:
	_current_channel_id = str(topic.channel_id)
	channel_title.text = _character_name(_find_channel_character(_current_channel_id), _current_channel_id)
	channel_subtitle.text = "在线"
	_render_contact(_current_channel_id)
	_render_thread(_current_channel_id)
	topic_info.text = "正在接收消息"
	typing_indicator.text = "正在输入..."
	typing_indicator.visible = true


func _on_topic_message_emitted(topic: Resource, speaker_id: String, text: String, is_player: bool, card: Dictionary) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	typing_indicator.visible = false
	# 消息由 LinkChatManager 持久化后通过 message_appended 渲染。


func _on_topic_choices_presented(topic: Resource, choices: Array) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	_render_choices(choices)


func _render_choices(choices: Array) -> void:
	for child: Node in recommend_container.get_children():
		child.queue_free()
	recommend_container.visible = true
	input_hbox.visible = false
	for choice_value: Variant in choices:
		var choice: Dictionary = choice_value
		var button := Button.new()
		button.text = str(choice.get("text", ""))
		button.custom_minimum_size = Vector2(0, 84)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 30)
		button.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
		button.add_theme_color_override("font_hover_color", LCTheme.COLOR_TEXT_PRIMARY)
		button.add_theme_color_override("font_pressed_color", LCTheme.COLOR_TEXT_PRIMARY)
		button.add_theme_stylebox_override("normal", LCTheme.get_option_panel_style())
		button.add_theme_stylebox_override("hover", LCTheme.get_option_panel_hover_style())
		button.add_theme_stylebox_override("pressed", LCTheme.get_option_panel_pressed_style())
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_choose_option.bind(str(choice.get("id", ""))))
		recommend_container.add_child(button)
	topic_info.text = "请选择回复"


func _on_topic_completed(topic: Resource, _result: Dictionary) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	typing_indicator.visible = false
	recommend_container.visible = false
	input_hbox.visible = true
	topic_info.text = "已读"


func _on_topic_cancelled(topic: Resource, _reason: String) -> void:
	if str(topic.channel_id) == _current_channel_id:
		typing_indicator.visible = false
		recommend_container.visible = false
		input_hbox.visible = true
		topic_info.text = "消息暂未送达"


func _append_message(speaker_id: String, text: String, is_player: bool, card: Dictionary = {}) -> void:
	var character: CharacterProfile = _player_character if is_player else _find_character(speaker_id)
	var message: Dictionary = {
		"sender_id": "player" if is_player else speaker_id,
		"sender_name": _character_name(character, "我" if is_player else speaker_id),
		"avatar": _character_avatar(character),
		"content": text,
		"time": "",
	}
	if not card.is_empty():
		message["card"] = card
	var bubble: ChatMessageBubble = MessageBubbleClass.create(message, message_list.size.x)
	_make_click_through(bubble)
	if not bubble.gui_input.is_connected(_on_bubble_gui_input):
		bubble.gui_input.connect(_on_bubble_gui_input)
	message_list.add_child(bubble)
	var contact_item: ChatContactItem = _contact_items.get(_current_channel_id) as ChatContactItem
	if contact_item != null:
		contact_item.update_preview(str(message["sender_name"]), text, is_player)
	_scroll_to_bottom.call_deferred()


func _render_thread(channel_id: String) -> void:
	for child: Node in message_list.get_children():
		child.queue_free()
	if _linkchat_manager == null:
		return
	var value: Variant = _linkchat_manager.call("get_thread_messages", channel_id)
	if not value is Array:
		return
	var player_id: String = _player_character.character_id if _player_character != null else "player"
	for message_value: Variant in value:
		if not message_value is Dictionary:
			continue
		var message: Dictionary = message_value
		var sender_id: String = str(message.get("sender_id", ""))
		var attachment_value: Variant = message.get("attachment", {})
		var attachment: Dictionary = (attachment_value as Dictionary) if attachment_value is Dictionary else {}
		_append_message(sender_id, str(message.get("content", "")), sender_id == player_id, attachment)


func _on_message_appended(message: Dictionary) -> void:
	var channel_id: String = str(message.get("channel_id", ""))
	if channel_id != _current_channel_id:
		return
	var sender_id: String = str(message.get("sender_id", ""))
	var player_id: String = _player_character.character_id if _player_character != null else "player"
	var attachment_value: Variant = message.get("attachment", {})
	var attachment: Dictionary = (attachment_value as Dictionary) if attachment_value is Dictionary else {}
	_append_message(sender_id, str(message.get("content", "")), sender_id == player_id, attachment)


func _on_messages_reloaded() -> void:
	if not _current_channel_id.is_empty():
		_render_thread(_current_channel_id)


func _on_bubble_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_topic_now()


## 气泡内部子节点（面板/Label 等）默认会吞掉点击，统一设为 IGNORE（保留卡片可点），
## 让点击冒泡到气泡根节点触发推进
func _make_click_through(node: Node) -> void:
	if node is LinkChatMessageCard:
		return
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_make_click_through(child)


func _on_contact_selected(channel_id: String) -> void:
	if channel_id.is_empty():
		return
	_current_channel_id = channel_id
	for item_id_value: Variant in _contact_items:
		var item: ChatContactItem = _contact_items[item_id_value] as ChatContactItem
		if item != null:
			item.set_selected(str(item_id_value) == channel_id)
	var character: CharacterProfile = _find_channel_character(channel_id)
	channel_title.text = _character_name(character, channel_id)
	channel_subtitle.text = "在线"
	_render_thread(channel_id)


func _find_character(character_id: String) -> CharacterProfile:
	if _linkchat_manager == null:
		return null
	return _linkchat_manager.call("get_character", character_id) as CharacterProfile


func _find_channel_character(channel_id: String) -> CharacterProfile:
	return _find_character(channel_id)


func _character_name(character: CharacterProfile, fallback: String) -> String:
	if character == null:
		return fallback
	if character.linkchat_profile != null and not character.linkchat_profile.account_name.is_empty():
		return character.linkchat_profile.account_name
	if not character.display_name.is_empty():
		return character.display_name
	return fallback


func _character_avatar(character: CharacterProfile) -> Texture2D:
	if character == null or character.linkchat_profile == null:
		return null
	return character.linkchat_profile.avatar


func _visible_moment_view_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _linkchat_manager == null:
		return result
	var value: Variant = _linkchat_manager.call("get_visible_moment_view_data")
	if value is Array:
		for post_value: Variant in value:
			if post_value is Dictionary:
				result.append(post_value)
	return result


func _refresh_moments() -> void:
	if _moments_panel != null:
		_moments_panel.set_posts(_visible_moment_view_data())


func _on_friendship_changed(_character_id: String, _is_friend: bool) -> void:
	_render_friend_contacts()
	_refresh_moments()


func _on_friends_reloaded() -> void:
	_render_friend_contacts()


func _on_moment_published(_post: MomentPostRecord) -> void:
	_refresh_moments()


func _on_moment_commented(_post_id: String, _comment: MomentCommentRecord) -> void:
	_refresh_moments()


func _on_moments_reloaded() -> void:
	_refresh_moments()


func _on_moment_like_requested(post_id: String, liked: bool) -> void:
	if _linkchat_manager != null:
		_linkchat_manager.call("set_moment_liked", post_id, liked)


func _on_moment_image_open_requested(texture: Texture2D, image_title: String) -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("focus_app"):
		return
	var window: Control = app_manager.call("focus_app", "image_viewer", true) as Control
	if window == null:
		return
	var viewer: Node = window.get("content") as Node
	if viewer != null and viewer.has_method("open_texture"):
		viewer.call_deferred("open_texture", texture, image_title)


## 等待推进期间，玩家点击消息区域或气泡可立即继续
func _connect_click_to_advance() -> void:
	message_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not message_scroll.gui_input.is_connected(_on_scroll_gui_input):
		message_scroll.gui_input.connect(_on_scroll_gui_input)


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_topic_now()


func _advance_topic_now() -> void:
	if _topic_manager == null or not is_instance_valid(_topic_manager):
		return
	_advance_generation += 1
	_topic_manager.advance_topic(_current_channel_id)


func _choose_option(option_id: String) -> void:
	recommend_container.visible = false
	input_hbox.visible = true
	if is_instance_valid(_topic_manager):
		_topic_manager.choose_topic_option(_current_channel_id, option_id)


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)
