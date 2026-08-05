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

## 玩家和联系人资料只负责 LinkChat 的显示身份；ChatTopic 仍只保存剧情脚本。
@export var player_character: StreamerCharacter = null
@export var chat_characters: Array[StreamerCharacter] = []
@export var moment_posts: Array[Dictionary] = []

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
var _current_channel_id: String = ""
var _advance_generation: int = 0
var _contact_item: ChatContactItem = null
var _moments_panel: LinkChatMomentsPanel = null
var _current_page: NavPage = NavPage.CHAT


func _ready() -> void:
	_apply_original_theme()
	_setup_original_layout()
	_render_empty_contact()
	_setup_navigation()
	_connect_topic_manager()
	_connect_click_to_advance()


func open_topic_channel(channel_id: String) -> void:
	_current_channel_id = channel_id
	_show_page(NavPage.CHAT)


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


func _apply_original_theme() -> void:
	background.color = LCTheme.COLOR_BG_MAIN
	nav_strip.add_theme_stylebox_override("panel", LCTheme.get_nav_strip_style())
	nav_avatar.set_avatar(
		player_character.avatar if player_character != null else null,
		_character_name(player_character, "我")
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
	send_button.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	send_button.add_theme_color_override("font_pressed_color", Color("#FFFFFF"))
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
	_moments_panel.set_posts(moment_posts)
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


func set_moment_posts(posts: Array[Dictionary]) -> void:
	moment_posts = posts
	if _moments_panel != null:
		_moments_panel.set_posts(posts)


func add_moment_post(post: Dictionary) -> void:
	moment_posts.push_front(post)
	if _moments_panel != null:
		_moments_panel.add_post(post)


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
	for child: Node in contact_list.get_children():
		child.queue_free()

	var character: StreamerCharacter = _find_channel_character(channel_id)
	_contact_item = ContactItemScene.instantiate() as ChatContactItem
	_contact_item.setup(channel_id, _character_name(character, channel_id), character.avatar if character != null else null)
	_contact_item.selected.connect(_on_contact_selected)
	contact_list.add_child(_contact_item)
	_contact_item.set_selected(true)


func _on_topic_activated(topic: Resource) -> void:
	_current_channel_id = str(topic.channel_id)
	channel_title.text = _current_channel_id
	channel_subtitle.text = "在线"
	_render_contact(_current_channel_id)
	topic_info.text = "正在接收消息"
	typing_indicator.text = "正在输入..."
	typing_indicator.visible = true


func _on_topic_message_emitted(topic: Resource, speaker_id: String, text: String, is_player: bool, card: Dictionary) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	typing_indicator.visible = false
	_append_message(speaker_id, text, is_player, card)
	_schedule_advance(text.length())


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
	var character: StreamerCharacter = player_character if is_player else _find_character(speaker_id)
	var message: Dictionary = {
		"sender_id": "player" if is_player else speaker_id,
		"sender_name": _character_name(character, "我" if is_player else speaker_id),
		"avatar": character.avatar if character != null else null,
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
	if _contact_item != null:
		_contact_item.update_preview(str(message["sender_name"]), text, is_player)
	_scroll_to_bottom.call_deferred()


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
	if channel_id == _current_channel_id and _contact_item != null:
		_contact_item.set_selected(true)


func _find_character(character_key: String) -> StreamerCharacter:
	for character: StreamerCharacter in chat_characters:
		if character != null and character.character_key == character_key:
			return character
	return null


func _find_channel_character(channel_id: String) -> StreamerCharacter:
	for character: StreamerCharacter in chat_characters:
		if character == null:
			continue
		if character.chat_display_name == channel_id:
			return character
		if character.display_name == channel_id:
			return character
	return null


func _character_name(character: StreamerCharacter, fallback: String) -> String:
	if character == null:
		return fallback
	if not character.chat_display_name.is_empty():
		return character.chat_display_name
	if not character.display_name.is_empty():
		return character.display_name
	return fallback


func _schedule_advance(text_length: int) -> void:
	_advance_generation += 1
	var generation: int = _advance_generation
	var delay: float = clampf(
		MIN_ADVANCE_DELAY + ADVANCE_CHAR_SECONDS * text_length,
		MIN_ADVANCE_DELAY,
		MAX_ADVANCE_DELAY
	)
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if generation == _advance_generation and is_instance_valid(_topic_manager):
			_topic_manager.advance_topic(_current_channel_id)
	)


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
