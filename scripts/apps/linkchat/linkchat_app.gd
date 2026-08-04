class_name LinkChatApp extends Control
## 复用原 LinkChat 窗口与消息组件，数据源来自 StoryDirector/TopicManager。

const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const MessageBubbleClass = preload("res://scripts/apps/linkchat/components/message_bubble.gd")

const AUTO_ADVANCE_DELAY: float = 0.55

@onready var background: ColorRect = $Background
@onready var nav_strip: PanelContainer = %NavStrip
@onready var nav_avatar: PanelContainer = %NavAvatar
@onready var nav_chat_btn: Button = %NavChatBtn
@onready var nav_moments_btn: Button = %NavMomentsBtn
@onready var nav_settings_btn: Button = %NavSettingsBtn
@onready var sidebar: PanelContainer = %Sidebar
@onready var app_title: Label = %AppTitle
@onready var contact_list: VBoxContainer = %ContactList
@onready var chat_header: PanelContainer = %ChatHeader
@onready var channel_title: Label = %ChannelTitle
@onready var channel_subtitle: Label = %ChannelSubtitle
@onready var topic_info: Label = %TopicInfo
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var message_list: VBoxContainer = %MessageList
@onready var input_area: PanelContainer = %InputArea
@onready var input_field: LineEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var recommend_container: HFlowContainer = %RecommendRepliesContainer
@onready var batch_indicator: Label = %BatchIndicator
@onready var typing_indicator: Label = %TypingIndicator
@onready var moments_container: VBoxContainer = %MomentsContainer

var _topic_manager: Node = null
var _current_channel_id: String = ""
var _advance_generation: int = 0


func _ready() -> void:
	_apply_original_theme()
	_setup_original_layout()
	_render_contact()
	_connect_topic_manager()


func open_topic_channel(channel_id: String) -> void:
	_current_channel_id = channel_id
	message_scroll.visible = true
	chat_header.visible = true
	input_area.visible = true
	moments_container.visible = false


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
	nav_strip.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_NAV, 0))
	nav_strip.custom_minimum_size.x = 108.0
	nav_avatar.custom_minimum_size = Vector2(72, 72)
	nav_avatar.add_theme_stylebox_override("panel", LCTheme.get_avatar_style(LCTheme.COLOR_ACCENT))
	var avatar_label: Label = nav_avatar.get_child(0) as Label
	if avatar_label != null:
		avatar_label.add_theme_color_override("font_color", Color.WHITE)
		avatar_label.add_theme_font_size_override("font_size", 26)
	for button: Button in [nav_chat_btn, nav_moments_btn, nav_settings_btn]:
		button.flat = true
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.custom_minimum_size = Vector2(84, 84)
	var active_style := LCTheme.rounded_flat(LCTheme.COLOR_CONTACT_SELECTED, LCTheme.RADIUS_SM)
	nav_chat_btn.add_theme_stylebox_override("normal", active_style)
	nav_chat_btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)

	sidebar.custom_minimum_size.x = 500.0
	sidebar.add_theme_stylebox_override("panel", LCTheme.get_sidebar_bg_style())
	app_title.add_theme_font_size_override("font_size", 30)
	app_title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	chat_header.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_HEADER, 0))
	channel_title.add_theme_font_size_override("font_size", 28)
	channel_title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	channel_subtitle.add_theme_font_size_override("font_size", 19)
	channel_subtitle.add_theme_color_override("font_color", LCTheme.COLOR_ONLINE)
	topic_info.add_theme_font_size_override("font_size", 18)
	topic_info.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	input_area.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_INPUT_AREA, 0))
	input_field.add_theme_stylebox_override("read_only", LCTheme.get_input_field_disabled_style())
	input_field.add_theme_font_size_override("font_size", 21)
	send_button.add_theme_stylebox_override("disabled", LCTheme.get_send_button_style())
	send_button.add_theme_color_override("font_disabled_color", LCTheme.COLOR_TEXT_MUTED)
	send_button.add_theme_font_size_override("font_size", 20)
	typing_indicator.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT_HOVER)
	batch_indicator.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)


func _setup_original_layout() -> void:
	nav_moments_btn.visible = false
	nav_settings_btn.visible = false
	moments_container.visible = false
	message_scroll.visible = true
	chat_header.visible = true
	input_area.visible = true
	channel_title.text = "LinkChat"
	channel_subtitle.text = "等待会话"
	topic_info.text = "等待新消息"
	input_field.editable = false
	input_field.placeholder_text = "剧情消息会自动播放"
	send_button.disabled = true
	recommend_container.visible = false
	typing_indicator.visible = false
	batch_indicator.visible = false


func _render_contact() -> void:
	for child: Node in contact_list.get_children():
		child.queue_free()
	var contact := Button.new()
	contact.text = "暂无会话"
	contact.alignment = HORIZONTAL_ALIGNMENT_LEFT
	contact.custom_minimum_size.y = 112
	contact.add_theme_font_size_override("font_size", 22)
	contact.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	contact.add_theme_stylebox_override("normal", LCTheme.get_contact_selected_style())
	contact.add_theme_stylebox_override("hover", LCTheme.get_contact_selected_style())
	contact.add_theme_stylebox_override("pressed", LCTheme.get_contact_selected_style())
	contact.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	contact_list.add_child(contact)


func _on_topic_activated(topic: Resource) -> void:
	_current_channel_id = str(topic.channel_id)
	channel_title.text = _current_channel_id
	channel_subtitle.text = "在线"
	var contact: Button = contact_list.get_child(0) as Button
	if contact != null:
		contact.text = _current_channel_id
	topic_info.text = "正在接收消息"
	typing_indicator.text = "正在输入..."
	typing_indicator.visible = true


func _on_topic_message_emitted(topic: Resource, speaker_id: String, text: String, is_player: bool) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	typing_indicator.visible = false
	_append_message(speaker_id, text, is_player)
	_schedule_advance()


func _on_topic_choices_presented(topic: Resource, choices: Array) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	for child: Node in recommend_container.get_children():
		child.queue_free()
	recommend_container.visible = true
	for choice_value: Variant in choices:
		var choice: Dictionary = choice_value
		var button := Button.new()
		button.text = str(choice.get("text", ""))
		button.add_theme_stylebox_override("normal", LCTheme.get_chip_style())
		button.add_theme_stylebox_override("hover", LCTheme.get_chip_hover_style())
		button.pressed.connect(_choose_option.bind(str(choice.get("id", ""))))
		recommend_container.add_child(button)
	topic_info.text = "请选择回复"


func _on_topic_completed(topic: Resource, _result: Dictionary) -> void:
	if str(topic.channel_id) != _current_channel_id:
		return
	typing_indicator.visible = false
	recommend_container.visible = false
	topic_info.text = "已读"


func _on_topic_cancelled(topic: Resource, _reason: String) -> void:
	if str(topic.channel_id) == _current_channel_id:
		typing_indicator.visible = false
		topic_info.text = "消息暂未送达"


func _append_message(speaker_id: String, text: String, is_player: bool) -> void:
	var message: Dictionary = {
		"sender_id": "player" if is_player else speaker_id,
		"sender_name": "player" if is_player else speaker_id,
		"content": text,
		"time": "",
	}
	message_list.add_child(MessageBubbleClass.create(message))
	_scroll_to_bottom.call_deferred()


func _schedule_advance() -> void:
	_advance_generation += 1
	var generation: int = _advance_generation
	var timer := get_tree().create_timer(AUTO_ADVANCE_DELAY)
	timer.timeout.connect(func() -> void:
		if generation == _advance_generation and is_instance_valid(_topic_manager):
			_topic_manager.advance_topic(_current_channel_id)
	)


func _choose_option(option_id: String) -> void:
	if is_instance_valid(_topic_manager):
		_topic_manager.choose_topic_option(_current_channel_id, option_id)


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)
