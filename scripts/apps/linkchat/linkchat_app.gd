class_name LinkChatApp extends Control
## LinkChat 聊天应用 — 纯 UI 层
## 所有数据（频道、消息、NPC、Topic）由 ChatManager autoload 持有
## 本类只负责渲染和用户交互

const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")
const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const MessageBubbleClass = preload("res://scripts/apps/linkchat/components/message_bubble.gd")
const ContactItemClass = preload("res://scripts/apps/linkchat/components/contact_item.gd")
const MomentsPanelClass = preload("res://scripts/apps/linkchat/components/moments_panel.gd")

## 导航页面枚举
enum NavPage {CHAT, MOMENTS, SETTINGS}

# --- 节点引用 ---
@onready var background: ColorRect = $Background
@onready var nav_strip: PanelContainer = %NavStrip
@onready var nav_avatar: PanelContainer = %NavAvatar
@onready var nav_chat_btn: Button = %NavChatBtn
@onready var nav_moments_btn: Button = %NavMomentsBtn
@onready var nav_settings_btn: Button = %NavSettingsBtn
@onready var sidebar: PanelContainer = %Sidebar
@onready var app_title: Label = %AppTitle
@onready var contact_scroll: ScrollContainer = %ContactScroll
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
@onready var sidebar_border: VSeparator = %SidebarBorder

# --- UI 子系统 ---
var response_handler: NPCResponseHandler

# --- UI 状态 ---
var current_channel_id: String = ""
var _playing_typing_animation: bool = false
var _typing_animation_token: int = 0
var _active_typing_channel_id: String = ""
## 玩家消息 InputGuard 审核进行中（保留输入框内容，避免「先清空后拦截」的观感）
var _auditing_send: bool = false
## channel_id -> ContactItemClass
var _contact_items: Dictionary = {}
## 当前导航页面
var _current_page: NavPage = NavPage.CHAT
## 朋友圈面板实例
var _moments_panel: Control = null
## 每个频道缓存的推荐回复 { channel_id: Array[String] }
var _channel_replies: Dictionary = {}
## 当前频道里已存储但等待 UI 动画显示的 NPC 消息 { channel_id: Array[Dictionary] }
var _deferred_npc_messages: Dictionary = {}
var _offscreen_npc_message_queues: Dictionary = {}
var _offscreen_delivery_tokens: Dictionary = {}
var _active_offscreen_deliveries: Dictionary = {}
## 过渡动画时长
const TRANSITION_DURATION: float = 0.18
## 侧边栏目标宽度
const SIDEBAR_WIDTH: float = 500.0
const NAV_STRIP_WIDTH: float = 108.0
const NAV_AVATAR_SIZE: float = 72.0
const NAV_BUTTON_SIZE: float = 84.0
const SEND_BUTTON_MIN_WIDTH: float = 132.0
const OFFSCREEN_MESSAGE_PAUSE_MIN: float = 0.5
const OFFSCREEN_MESSAGE_PAUSE_MAX: float = 1.5
## 页面切换动画 tween
var _page_tween: Tween = null
## 输入区内嵌提示条
var _toast_wrapper: Control = null
var _toast_label: Label = null
var _toast_tween: Tween = null


func _play_chat_sfx(key: String) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx_key"):
		audio.play_sfx_key(key)


func _append_message_bubble(msg: Dictionary, play_sound: bool = false) -> void:
	var bubble := MessageBubbleClass.create(msg)
	message_list.add_child(bubble)
	if play_sound:
		var sender_id := str(msg.get("sender_id", "")).strip_edges()
		if sender_id == "player":
			_play_chat_sfx("chat_send")
		elif sender_id != "system" and not sender_id.is_empty():
			_play_chat_sfx("chat_receive")


func _ready() -> void:
	response_handler = NPCResponseHandler.new()
	add_child(response_handler)

	_create_toast_label()
	_apply_theme()
	_setup_ui_connections()
	_setup_data_connections()
	_render_contacts()
	_setup_initial_page()
	open_topic_channel(_resolve_initial_channel_id())


func _exit_tree() -> void:
	if _playing_typing_animation or not _active_typing_channel_id.is_empty():
		_cancel_typing_animation()


func _apply_theme() -> void:
	# 全局背景
	if background:
		background.color = LCTheme.COLOR_BG_MAIN

	# 导航条
	nav_strip.custom_minimum_size.x = NAV_STRIP_WIDTH
	var nav_bg := LCTheme.rounded_flat(LCTheme.COLOR_BG_NAV, 0)
	nav_strip.add_theme_stylebox_override("panel", nav_bg)
	_apply_nav_button_theme(nav_chat_btn)
	_apply_nav_button_theme(nav_moments_btn)
	_apply_nav_button_theme(nav_settings_btn)
	nav_avatar.custom_minimum_size = Vector2(NAV_AVATAR_SIZE, NAV_AVATAR_SIZE)
	nav_chat_btn.custom_minimum_size = Vector2(NAV_BUTTON_SIZE, NAV_BUTTON_SIZE)
	nav_moments_btn.custom_minimum_size = Vector2(NAV_BUTTON_SIZE, NAV_BUTTON_SIZE)
	nav_settings_btn.custom_minimum_size = Vector2(NAV_BUTTON_SIZE, NAV_BUTTON_SIZE)
	nav_settings_btn.visible = false
	nav_settings_btn.disabled = true
	nav_settings_btn.focus_mode = Control.FOCUS_NONE

	# 导航头像
	var avatar_style := LCTheme.rounded_flat(LCTheme.COLOR_ACCENT, LCTheme.RADIUS_AVATAR)
	nav_avatar.add_theme_stylebox_override("panel", avatar_style)
	var avatar_label: Label = nav_avatar.get_child(0)
	if avatar_label:
		avatar_label.add_theme_color_override("font_color", Color.WHITE)
		avatar_label.add_theme_font_size_override("font_size", 26)

	# 侧边栏
	sidebar.custom_minimum_size.x = SIDEBAR_WIDTH
	sidebar.add_theme_stylebox_override("panel", LCTheme.get_sidebar_bg_style())
	app_title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	app_title.add_theme_font_size_override("font_size", 30)

	# 聊天头部
	chat_header.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_HEADER, 0))
	channel_title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	channel_title.add_theme_font_size_override("font_size", 28)
	channel_subtitle.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	channel_subtitle.add_theme_font_size_override("font_size", 19)
	topic_info.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	topic_info.add_theme_font_size_override("font_size", 19)

	# 输入区域
	input_area.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_INPUT_AREA, 0))
	input_field.add_theme_stylebox_override("normal", LCTheme.get_input_field_style())
	input_field.add_theme_stylebox_override("focus", LCTheme.get_input_field_focus_style())
	input_field.add_theme_stylebox_override("read_only", LCTheme.get_input_field_disabled_style())
	input_field.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	input_field.add_theme_color_override("font_placeholder_color", LCTheme.COLOR_TEXT_MUTED)
	input_field.add_theme_color_override("caret_color", LCTheme.COLOR_ACCENT)
	input_field.add_theme_font_size_override("font_size", 22)

	send_button.add_theme_stylebox_override("normal", LCTheme.get_send_button_style())
	send_button.add_theme_stylebox_override("hover", LCTheme.get_send_button_hover_style())
	send_button.add_theme_stylebox_override("pressed", LCTheme.get_send_button_hover_style())
	send_button.add_theme_stylebox_override("disabled", LCTheme.get_send_button_style())
	send_button.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	send_button.add_theme_color_override("font_hover_color", Color.WHITE)
	send_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	send_button.add_theme_color_override("font_disabled_color", LCTheme.COLOR_TEXT_MUTED)
	send_button.add_theme_font_size_override("font_size", 20)
	send_button.custom_minimum_size.x = SEND_BUTTON_MIN_WIDTH

	# 提示文字
	typing_indicator.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	typing_indicator.add_theme_font_size_override("font_size", 18)
	batch_indicator.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	batch_indicator.add_theme_font_size_override("font_size", 18)

	# 初始导航高亮
	_update_nav_highlight()


func _apply_nav_button_theme(btn: Button) -> void:
	btn.flat = true
	var normal := LCTheme.rounded_flat(Color.TRANSPARENT, LCTheme.RADIUS_SM)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := LCTheme.rounded_flat(Color("#DCDCE0"), LCTheme.RADIUS_SM)
	hover.content_margin_left = 8
	hover.content_margin_right = 8
	hover.content_margin_top = 10
	hover.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", LCTheme.COLOR_TEXT_PRIMARY)


func _set_nav_button_active(btn: Button, active: bool) -> void:
	if active:
		# 选中态：浅灰背景 + 深色文字（和联系人选中一致）
		var active_style := LCTheme.rounded_flat(LCTheme.COLOR_CONTACT_SELECTED, LCTheme.RADIUS_SM)
		active_style.content_margin_left = 8
		active_style.content_margin_right = 8
		active_style.content_margin_top = 10
		active_style.content_margin_bottom = 10
		btn.add_theme_stylebox_override("normal", active_style)
		btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	else:
		# 非选中态：透明背景 + 灰色文字
		var normal := LCTheme.rounded_flat(Color.TRANSPARENT, LCTheme.RADIUS_SM)
		normal.content_margin_left = 8
		normal.content_margin_right = 8
		normal.content_margin_top = 10
		normal.content_margin_bottom = 10
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)


func _update_nav_highlight() -> void:
	_set_nav_button_active(nav_chat_btn, _current_page == NavPage.CHAT)
	_set_nav_button_active(nav_moments_btn, _current_page == NavPage.MOMENTS)
	_set_nav_button_active(nav_settings_btn, _current_page == NavPage.SETTINGS)

	# 朋友圈未读提示
	var unread := ChatManager.get_moments_unread()
	if unread > 0 and _current_page != NavPage.MOMENTS:
		nav_moments_btn.text = "动态 *"
	else:
		nav_moments_btn.text = "动态"


func _setup_ui_connections() -> void:
	input_field.text_submitted.connect(_on_text_submitted)
	send_button.pressed.connect(_on_send_pressed)
	nav_chat_btn.pressed.connect(func() -> void: _navigate_to(NavPage.CHAT))
	nav_moments_btn.pressed.connect(func() -> void: _navigate_to(NavPage.MOMENTS))
	nav_settings_btn.pressed.connect(func() -> void: _navigate_to(NavPage.SETTINGS))
	response_handler.typing_started.connect(_on_typing_started)
	response_handler.typing_ended.connect(_on_typing_ended)


func _setup_data_connections() -> void:
	ChatManager.message_added.connect(_on_message_added)
	ChatManager.npc_messages_received.connect(_on_npc_messages_received)
	ChatManager.topic_activated.connect(_on_topic_changed)
	ChatManager.topic_completed.connect(func(_t: ChatTopic, _r: Dictionary) -> void: _on_topic_changed(_t))
	ChatManager.topic_timeout.connect(_on_topic_changed)
	if ChatManager.has_signal("topic_cancelled"):
		ChatManager.topic_cancelled.connect(func(_t: ChatTopic, _reason: String) -> void: _on_topic_changed(_t))
	ChatManager.batch_state_changed.connect(_on_batch_state_changed)
	ChatManager.waiting_for_ai_changed.connect(_on_waiting_for_ai_changed)
	ChatManager.channel_added.connect(_on_channel_added_to_data)
	ChatManager.moment_posted.connect(_on_moment_posted)
	ChatManager.message_blocked.connect(_on_message_blocked)


# --- 导航 ---

## 初始化页面状态（无动画）
func _setup_initial_page() -> void:
	_current_page = NavPage.CHAT
	_update_nav_highlight()
	sidebar.visible = true
	sidebar_border.visible = true
	moments_container.visible = false
	message_scroll.visible = true
	input_area.visible = true
	chat_header.visible = true


func _navigate_to(page: NavPage) -> void:
	var old_page := _current_page
	if old_page == NavPage.CHAT and page != NavPage.CHAT and _playing_typing_animation:
		_cancel_typing_animation()
	_current_page = page
	_update_nav_highlight()

	# 同页点击不做动画
	if old_page == page:
		return

	# 取消正在进行的动画
	if _page_tween and _page_tween.is_valid():
		_page_tween.kill()

	var show_sidebar: bool = (page == NavPage.CHAT)
	var old_show_sidebar: bool = (old_page == NavPage.CHAT)

	# 确定要显示的内容节点
	var content_nodes_to_show: Array[Control] = []
	var content_nodes_to_hide: Array[Control] = []

	# 所有内容区节点
	var all_content: Array[Control] = [message_scroll, input_area, moments_container, chat_header]

	match page:
		NavPage.CHAT:
			content_nodes_to_show = [message_scroll, input_area, chat_header]
			if not current_channel_id.is_empty():
				var channel: Resource = ChatManager.get_channel(current_channel_id)
				if channel:
					_update_chat_header(channel)
				_refresh_message_display()
			_update_input_state()
			_update_topic_info()
		NavPage.MOMENTS:
			content_nodes_to_show = [moments_container]
			ChatManager.clear_moments_unread()
			_update_nav_highlight()
			if _moments_panel == null:
				_moments_panel = MomentsPanelClass.new()
				_moments_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_moments_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
				moments_container.add_child(_moments_panel)
		NavPage.SETTINGS:
			content_nodes_to_show = [chat_header]
			channel_title.text = "设置"
			channel_subtitle.text = "开发中..."
			channel_subtitle.visible = true
			topic_info.text = ""

	# 计算要隐藏的节点
	for node in all_content:
		if not content_nodes_to_show.has(node):
			content_nodes_to_hide.append(node)

	_page_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var sidebar_changing := (show_sidebar != old_show_sidebar)

	# === Phase 1: 收起侧边栏（仅隐藏时）+ 淡出旧内容 ===
	if sidebar_changing and not show_sidebar:
		_page_tween.tween_property(sidebar, "custom_minimum_size:x", 0.0, TRANSITION_DURATION)
		_page_tween.parallel().tween_property(sidebar, "modulate:a", 0.0, TRANSITION_DURATION)
		_page_tween.parallel().tween_property(sidebar_border, "modulate:a", 0.0, TRANSITION_DURATION)

	for node in content_nodes_to_hide:
		if node.visible:
			_page_tween.parallel().tween_property(node, "modulate:a", 0.0, TRANSITION_DURATION * 0.6)

	# === Phase 2: 交换节点 ===
	_page_tween.tween_callback(func() -> void:
		for node in content_nodes_to_hide:
			node.visible = false
			node.modulate.a = 1.0
		if sidebar_changing:
			if show_sidebar:
				sidebar.custom_minimum_size.x = SIDEBAR_WIDTH
				sidebar.modulate.a = 0.0
				sidebar_border.modulate.a = 0.0
				sidebar.visible = true
				sidebar_border.visible = true
			else:
				sidebar.visible = false
				sidebar_border.visible = false
		for node in content_nodes_to_show:
			node.visible = true
			node.modulate.a = 0.0
	)

	# === Phase 3: 淡入侧边栏（仅展开时）+ 淡入新内容 ===
	var _first_fadein := true
	if sidebar_changing and show_sidebar:
		_page_tween.tween_property(sidebar, "modulate:a", 1.0, TRANSITION_DURATION * 0.6)
		_page_tween.parallel().tween_property(sidebar_border, "modulate:a", 1.0, TRANSITION_DURATION * 0.6)
		_first_fadein = false

	for node in content_nodes_to_show:
		if _first_fadein:
			_page_tween.tween_property(node, "modulate:a", 1.0, TRANSITION_DURATION * 0.6)
			_first_fadein = false
		else:
			_page_tween.parallel().tween_property(node, "modulate:a", 1.0, TRANSITION_DURATION * 0.6)


# --- 联系人列表渲染 ---

func _render_contacts() -> void:
	for child in contact_list.get_children():
		child.queue_free()
	_contact_items.clear()

	for cid in ChatManager.get_channel_order():
		_add_contact_item(cid)


func _add_contact_item(channel_id: String) -> void:
	var channel: Resource = ChatManager.get_channel(channel_id)
	if channel == null:
		return

	var npc: Resource = null
	if channel.channel_type == ChatChannelClass.ChannelType.DM:
		for member_id in channel.members:
			if member_id != "player":
				npc = ChatManager.get_npc(member_id)
				break

	var item := ContactItemClass.create(channel, npc)
	item.selected.connect(_on_contact_selected)
	contact_list.add_child(item)
	_contact_items[channel_id] = item


func open_topic_channel(channel_id: String) -> void:
	var target_channel_id := channel_id.strip_edges()
	if target_channel_id.is_empty():
		target_channel_id = "dm_lin_xia"
	select_channel(target_channel_id)


func _resolve_initial_channel_id() -> String:
	if ChatManager.has_method("get_last_activated_topic_channel_id"):
		var last_channel_id := str(ChatManager.get_last_activated_topic_channel_id()).strip_edges()
		if not last_channel_id.is_empty() and ChatManager.has_active_topic(last_channel_id):
			return last_channel_id

	for channel_id in ChatManager.get_channel_order():
		if ChatManager.has_active_topic(channel_id):
			return channel_id

	return "dm_lin_xia"


func select_channel(channel_id: String) -> void:
	var channel: Resource = ChatManager.get_channel(channel_id)
	if channel == null:
		return
	if _playing_typing_animation and _active_typing_channel_id != channel_id:
		_cancel_typing_animation()
	_cancel_offscreen_delivery(channel_id)

	# 如果在非聊天页，切回聊天
	if _current_page != NavPage.CHAT:
		_navigate_to(NavPage.CHAT)

	current_channel_id = channel_id

	# 更新联系人选中状态
	for cid in _contact_items:
		_contact_items[cid].set_selected(cid == channel_id)

	# 清除未读
	channel.unread_count = 0
	var selected_item = _contact_items.get(channel_id)
	if selected_item:
		selected_item.update_from_channel(channel)

	# 更新头部
	_update_chat_header(channel)
	_refresh_message_display()
	_update_input_state()
	_update_topic_info()
	
	# 恢复该频道的推荐回复
	var cached_replies: Array[String] = []
	if _channel_replies.has(channel_id):
		cached_replies.assign(_channel_replies[channel_id])
	_render_recommended_replies(cached_replies)


func _update_chat_header(channel: Resource) -> void:
	channel_title.text = channel.display_name

	if channel.channel_type == ChatChannelClass.ChannelType.DM:
		for member_id in channel.members:
			if member_id != "player":
				var npc := ChatManager.get_npc(member_id)
				if npc:
					channel_subtitle.text = "在线"
					channel_subtitle.visible = true
					return

	channel_subtitle.visible = false


# --- 消息渲染 ---

func _refresh_message_display() -> void:
	for child in message_list.get_children():
		child.queue_free()

	var channel: Resource = ChatManager.get_channel(current_channel_id)
	if channel:
		for msg in channel.messages:
			if msg.get("ai_only", false):
				continue
			var bubble := MessageBubbleClass.create(msg)
			message_list.add_child(bubble)

	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	# 等待两帧：第一帧气泡加入布局，第二帧 ScrollContainer 的 max_value 完成传播
	await get_tree().process_frame
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)


# --- 输入状态 ---

func _update_input_state() -> void:
	if _auditing_send:
		input_field.editable = false
		input_field.placeholder_text = "发送校验中..."
		send_button.disabled = true
		recommend_container.visible = false
		return

	var topic := ChatManager.get_active_topic(current_channel_id)
	var waiting := ChatManager.is_waiting_for_ai()
	var can_input: bool = (topic != null or ChatManager.debug_mode) and not waiting and not _playing_typing_animation

	if can_input:
		input_field.editable = true
		input_field.placeholder_text = "输入消息..."
		send_button.disabled = false
	else:
		input_field.editable = false
		if waiting or _playing_typing_animation:
			input_field.placeholder_text = "等待回复中..."
		else:
			input_field.placeholder_text = "当前没有进行中的对话"
		input_field.text = ""
		send_button.disabled = true

		# 禁用输入时，也隐藏推荐回复，避免状态不一致
		recommend_container.visible = false


func _update_topic_info() -> void:
	# Topic 名称与轮数是 debug 信息，仅在编辑器中显示，导出后隐藏
	if not OS.has_feature("editor"):
		topic_info.text = ""
		topic_info.visible = false
		return

	var topic := ChatManager.get_active_topic(current_channel_id)
	if topic:
		var info := "%s  轮数：%d" % [topic.display_title, topic.turn_count]
		topic_info.text = info
	else:
		topic_info.text = ""


# --- 用户交互回调 ---

func _on_text_submitted(text: String) -> void:
	if text.strip_edges().is_empty() or _auditing_send:
		return
	_auditing_send = true
	_update_input_state()
	var passed: bool = await ChatManager.add_player_message(current_channel_id, text)
	_auditing_send = false
	if passed:
		input_field.text = ""
		_channel_replies.erase(current_channel_id)
		_render_recommended_replies([])
	_update_input_state()
	if not passed:
		input_field.caret_column = text.length()


func _on_send_pressed() -> void:
	if not input_field.text.strip_edges().is_empty():
		_on_text_submitted(input_field.text)
	else:
		ChatManager.force_send_batch()


func _on_contact_selected(channel_id: String) -> void:
	select_channel(channel_id)


func _on_message_blocked(_channel_id: String, _text: String) -> void:
	_show_toast("消息发送失败，请检查内容")


# --- Toast 提示 ---

func _create_toast_label() -> void:
	# 外层 wrapper 用 clip_contents 裁剪，高度动画实现滑入滑出
	_toast_wrapper = Control.new()
	_toast_wrapper.clip_contents = true
	_toast_wrapper.custom_minimum_size.y = 0
	_toast_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 内部 label
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast_label.add_theme_font_size_override("font_size", 17)
	_toast_label.add_theme_color_override("font_color", Color("#B85450"))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#FDF2F2")
	bg.corner_radius_top_left = LCTheme.RADIUS_SM
	bg.corner_radius_top_right = LCTheme.RADIUS_SM
	bg.corner_radius_bottom_left = LCTheme.RADIUS_SM
	bg.corner_radius_bottom_right = LCTheme.RADIUS_SM
	bg.content_margin_left = 16
	bg.content_margin_right = 16
	bg.content_margin_top = 9
	bg.content_margin_bottom = 9
	_toast_label.add_theme_stylebox_override("normal", bg)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_wrapper.add_child(_toast_label)
	# 插入到 InputVBox 中，在 RecommendRepliesContainer 之后、InputHBox 之前
	var input_vbox: VBoxContainer = input_field.get_parent().get_parent()
	var input_hbox: HBoxContainer = input_field.get_parent()
	var idx := input_hbox.get_index()
	input_vbox.add_child(_toast_wrapper)
	input_vbox.move_child(_toast_wrapper, idx)


func _show_toast(text: String, duration: float = 2.5) -> void:
	if _toast_label == null or _toast_wrapper == null:
		return
	_toast_label.text = text
	# 先测量 label 自然高度
	await get_tree().process_frame
	var target_h: float = _toast_label.get_combined_minimum_size().y
	# 取消之前的动画
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	# 初始状态：高度 0，透明
	_toast_wrapper.custom_minimum_size.y = 0
	_toast_wrapper.modulate.a = 0.0
	_toast_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 滑入：高度展开 + 淡入
	_toast_tween.tween_property(_toast_wrapper, "custom_minimum_size:y", target_h, 0.25)
	_toast_tween.parallel().tween_property(_toast_wrapper, "modulate:a", 1.0, 0.2)
	# 停留
	_toast_tween.tween_interval(duration)
	# 滑出：淡出 + 高度收缩
	_toast_tween.tween_property(_toast_wrapper, "modulate:a", 0.0, 0.2)
	_toast_tween.tween_property(_toast_wrapper, "custom_minimum_size:y", 0.0, 0.2)


# --- ChatManager 信号回调 ---

func _on_message_added(channel_id: String, msg: Dictionary) -> void:
	if msg.get("ai_only", false):
		return
	if _should_defer_npc_message(channel_id, msg):
		_enqueue_deferred_npc_message(channel_id, msg)
		return
	elif _should_queue_offscreen_npc_message(channel_id, msg):
		_enqueue_offscreen_npc_message(channel_id, msg)
		return
	elif channel_id == current_channel_id and _current_page == NavPage.CHAT:
		_append_message_bubble(msg, true)
		_scroll_to_bottom()
	else:
		var channel: Resource = ChatManager.get_channel(channel_id)
		if channel:
			channel.unread_count += 1
			var item = _contact_items.get(channel_id)
			if item:
				item.update_from_channel(channel)

	# 更新联系人预览
	var ch: Resource = ChatManager.get_channel(channel_id)
	if ch:
		var ci = _contact_items.get(channel_id)
		if ci:
			ci.update_from_channel(ch)


func _update_contact_preview_for_message(channel_id: String, msg: Dictionary) -> void:
	var item = _contact_items.get(channel_id)
	if item == null:
		return

	var channel: Resource = ChatManager.get_channel(channel_id)
	if channel == null:
		return

	item.update_from_message(msg, int(channel.unread_count))


func _on_npc_messages_received(channel_id: String, messages: Array, recommended_replies: Array[String] = []) -> void:
	_cache_recommended_replies(channel_id, recommended_replies)

	if not _is_current_chat_channel(channel_id):
		return

	if _playing_typing_animation and _active_typing_channel_id != channel_id:
		_cancel_typing_animation(false)

	var animation_messages := _resolve_animation_messages(channel_id, messages)
	if animation_messages.is_empty():
		_refresh_message_display()
		_render_recommended_replies(recommended_replies)
		_update_input_state()
		_update_topic_info()
		return

	_typing_animation_token += 1
	var token := _typing_animation_token
	_active_typing_channel_id = channel_id
	_playing_typing_animation = true
	ChatManager.begin_npc_message_presentation(channel_id)
	_update_input_state()
	await _play_typing_animation(animation_messages, channel_id, token)

	if token != _typing_animation_token or _active_typing_channel_id != channel_id:
		return

	_active_typing_channel_id = ""
	_playing_typing_animation = false
	typing_indicator.visible = false
	ChatManager.finish_npc_message_presentation(channel_id)
	_update_input_state()
	_update_topic_info()
	_render_recommended_replies(recommended_replies)


func _render_recommended_replies(replies: Array[String]) -> void:
	# 先清空现有的按钮
	for child in recommend_container.get_children():
		child.queue_free()
		
	if replies.is_empty():
		recommend_container.visible = false
		return
		
	for reply in replies:
		var btn := Button.new()
		btn.text = reply
		btn.add_theme_font_size_override("font_size", 17)
		btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
		btn.add_theme_color_override("font_hover_color", LCTheme.COLOR_ACCENT_HOVER)
		btn.add_theme_stylebox_override("normal", LCTheme.get_chip_style())
		btn.add_theme_stylebox_override("hover", LCTheme.get_chip_hover_style())
		btn.add_theme_stylebox_override("pressed", LCTheme.get_chip_hover_style())
		btn.add_theme_stylebox_override("focus", LCTheme.get_chip_hover_style())
		btn.add_theme_stylebox_override("disabled", LCTheme.get_chip_disabled_style())
		btn.add_theme_stylebox_override("disabled_mirrored", LCTheme.get_chip_disabled_style())
		btn.add_theme_color_override("font_disabled_color", LCTheme.COLOR_TEXT_MUTED)
		
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(func(): _on_recommended_reply_clicked(reply))
		recommend_container.add_child(btn)
		
	recommend_container.visible = true


func _on_recommended_reply_clicked(reply_text: String) -> void:
	if input_field.editable:
		input_field.text = reply_text
		input_field.grab_focus()
		input_field.caret_column = reply_text.length()


func _on_topic_changed(_topic: ChatTopic) -> void:
	# Topic 激活时清理该频道的推荐回复
	_channel_replies.erase(_topic.channel_id)
	if _topic.channel_id == current_channel_id:
		_render_recommended_replies([])
		_update_input_state()
		_update_topic_info()


func _on_batch_state_changed(is_batching: bool) -> void:
	batch_indicator.visible = is_batching


func _on_waiting_for_ai_changed(_is_waiting: bool) -> void:
	if not _is_waiting and not _playing_typing_animation:
		_flush_deferred_messages(current_channel_id)
	_update_input_state()


func _on_channel_added_to_data(channel_id: String) -> void:
	if _contact_items.has(channel_id):
		return
	_add_contact_item(channel_id)


func _on_moment_posted(_moment: Dictionary) -> void:
	_update_nav_highlight()


# --- 打字机动画 ---

func _play_typing_animation(messages: Array, channel_id: String, token: int) -> void:
	typing_indicator.visible = true

	for i in messages.size():
		var msg_data: Dictionary = messages[i] if messages[i] is Dictionary else {"sender_name": "unknown", "content": str(messages[i])}
		var sender_id := str(msg_data.get("sender_id", msg_data.get("speaker", ""))).strip_edges()
		var sender_name := str(msg_data.get("sender_name", "")).strip_edges()
		var content: String = msg_data.get("content", "")

		var npc := ChatManager.get_npc(sender_id)
		var npc_name: String = sender_name
		if npc_name.is_empty():
			npc_name = npc.display_name if npc else sender_id
		if npc_name.is_empty():
			npc_name = "unknown"
		typing_indicator.text = "%s 正在输入..." % npc_name

		var clean_content := NPCResponseHandler.clean_message(content)
		if clean_content.is_empty() and msg_data.has("card") and msg_data["card"] is Dictionary:
			clean_content = _build_card_typing_preview(msg_data["card"])
		var delay := NPCResponseHandler.calculate_typing_delay(clean_content)
		await get_tree().create_timer(delay).timeout
		if token != _typing_animation_token or not _is_current_chat_channel(channel_id):
			return

		_append_message_bubble(msg_data, true)
		_update_contact_preview_for_message(channel_id, msg_data)
		_scroll_to_bottom()

		if i < messages.size() - 1:
			var pause := randf_range(0.5, 1.5)
			await get_tree().create_timer(pause).timeout
			if token != _typing_animation_token or not _is_current_chat_channel(channel_id):
				return

	typing_indicator.visible = false


func _should_defer_npc_message(channel_id: String, msg: Dictionary) -> bool:
	if not _is_current_chat_channel(channel_id):
		return false
	if not ChatManager.is_waiting_for_ai():
		return false
	var sender_id := str(msg.get("sender_id", "")).strip_edges()
	return sender_id != "player" and sender_id != "system"


func _should_queue_offscreen_npc_message(channel_id: String, msg: Dictionary) -> bool:
	if _is_current_chat_channel(channel_id):
		return false
	var sender_id := str(msg.get("sender_id", "")).strip_edges()
	return sender_id != "player" and sender_id != "system"


func _is_current_chat_channel(channel_id: String) -> bool:
	return _current_page == NavPage.CHAT and channel_id == current_channel_id


func _enqueue_deferred_npc_message(channel_id: String, msg: Dictionary) -> void:
	var queue: Array = _deferred_npc_messages.get(channel_id, [])
	queue.append(msg.duplicate(true))
	_deferred_npc_messages[channel_id] = queue


func _enqueue_offscreen_npc_message(channel_id: String, msg: Dictionary) -> void:
	var queue: Array = _offscreen_npc_message_queues.get(channel_id, [])
	queue.append(msg.duplicate(true))
	_offscreen_npc_message_queues[channel_id] = queue

	if bool(_active_offscreen_deliveries.get(channel_id, false)):
		return

	var token := int(_offscreen_delivery_tokens.get(channel_id, 0)) + 1
	_offscreen_delivery_tokens[channel_id] = token
	_active_offscreen_deliveries[channel_id] = true
	_deliver_offscreen_npc_messages(channel_id, token)


func _consume_deferred_npc_messages(channel_id: String, count: int) -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	if count <= 0 or not _deferred_npc_messages.has(channel_id):
		return consumed

	var queue: Array = _deferred_npc_messages[channel_id]
	var consume_count := mini(count, queue.size())
	for i in consume_count:
		if queue[i] is Dictionary:
			consumed.append((queue[i] as Dictionary).duplicate(true))

	if consume_count >= queue.size():
		_deferred_npc_messages.erase(channel_id)
	else:
		_deferred_npc_messages[channel_id] = queue.slice(consume_count)

	return consumed


func _resolve_animation_messages(channel_id: String, raw_messages: Array) -> Array[Dictionary]:
	var expected_count := raw_messages.size()
	var deferred := _consume_deferred_npc_messages(channel_id, expected_count)
	if deferred.size() == expected_count:
		return deferred

	var channel: Resource = ChatManager.get_channel(channel_id)
	if channel == null:
		return deferred

	var resolved: Array[Dictionary] = []
	var start_index := maxi(channel.messages.size() - expected_count, 0)
	for i in range(start_index, channel.messages.size()):
		if channel.messages[i] is Dictionary:
			resolved.append((channel.messages[i] as Dictionary).duplicate(true))
	return resolved


func _flush_deferred_messages(channel_id: String) -> void:
	if not _is_current_chat_channel(channel_id):
		return
	if not _deferred_npc_messages.has(channel_id):
		return

	var queue: Array = _deferred_npc_messages[channel_id]
	_deferred_npc_messages.erase(channel_id)
	for msg in queue:
		if msg is Dictionary:
			_append_message_bubble(msg, true)
			_update_contact_preview_for_message(channel_id, msg)
	_scroll_to_bottom()


func _deliver_offscreen_npc_messages(channel_id: String, token: int) -> void:
	while true:
		if token != int(_offscreen_delivery_tokens.get(channel_id, 0)):
			return
		if _is_current_chat_channel(channel_id):
			_cancel_offscreen_delivery(channel_id, false)
			return

		var queue: Array = _offscreen_npc_message_queues.get(channel_id, [])
		if queue.is_empty():
			break

		var raw_message: Variant = queue[0]
		queue.remove_at(0)
		if queue.is_empty():
			_offscreen_npc_message_queues.erase(channel_id)
		else:
			_offscreen_npc_message_queues[channel_id] = queue

		if not raw_message is Dictionary:
			continue

		var msg: Dictionary = (raw_message as Dictionary).duplicate(true)
		var content := NPCResponseHandler.clean_message(_build_typing_delay_source(msg))
		var delay := NPCResponseHandler.calculate_typing_delay(content)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout

		if token != int(_offscreen_delivery_tokens.get(channel_id, 0)):
			return
		if _is_current_chat_channel(channel_id):
			_cancel_offscreen_delivery(channel_id, false)
			return

		var channel: Resource = ChatManager.get_channel(channel_id)
		if channel != null:
			channel.unread_count += 1
			var item = _contact_items.get(channel_id)
			if item and item.has_method("update_from_message"):
				item.update_from_message(msg, channel.unread_count)
			elif item:
				item.update_from_channel(channel)

		if _offscreen_npc_message_queues.has(channel_id):
			var pause := randf_range(OFFSCREEN_MESSAGE_PAUSE_MIN, OFFSCREEN_MESSAGE_PAUSE_MAX)
			await get_tree().create_timer(pause).timeout

	if token == int(_offscreen_delivery_tokens.get(channel_id, 0)):
		_active_offscreen_deliveries.erase(channel_id)


func _cancel_offscreen_delivery(channel_id: String, bump_token: bool = true) -> void:
	_offscreen_npc_message_queues.erase(channel_id)
	_active_offscreen_deliveries.erase(channel_id)
	if bump_token:
		_offscreen_delivery_tokens[channel_id] = int(_offscreen_delivery_tokens.get(channel_id, 0)) + 1


func _build_typing_delay_source(msg: Dictionary) -> String:
	var content := str(msg.get("content", "")).strip_edges()
	if content.is_empty() and msg.has("card") and msg["card"] is Dictionary:
		content = _build_card_typing_preview(msg["card"] as Dictionary)
	return content


func _cancel_typing_animation(clear_deferred: bool = true) -> void:
	var animated_channel := _active_typing_channel_id
	_typing_animation_token += 1
	_playing_typing_animation = false
	_active_typing_channel_id = ""
	typing_indicator.visible = false
	if not animated_channel.is_empty():
		ChatManager.finish_npc_message_presentation(animated_channel)
	if clear_deferred and not animated_channel.is_empty():
		_deferred_npc_messages.erase(animated_channel)
	_update_input_state()


func _cache_recommended_replies(channel_id: String, recommended_replies: Array[String]) -> void:
	if not recommended_replies.is_empty():
		_channel_replies[channel_id] = recommended_replies
	else:
		_channel_replies.erase(channel_id)


func _on_typing_started(npc_id: String) -> void:
	var npc := ChatManager.get_npc(npc_id)
	var npc_name: String = npc.display_name if npc else npc_id
	typing_indicator.text = "%s 正在输入..." % npc_name
	typing_indicator.visible = true


func _on_typing_ended(_npc_id: String) -> void:
	typing_indicator.visible = false


func _build_card_typing_preview(card: Dictionary) -> String:
	var card_type := str(card.get("type", "")).strip_edges().to_lower()
	match card_type:
		"image":
			return str(card.get("title", card.get("alt", "发来一张图片")))
		"mock_image":
			return str(card.get("title", card.get("hint", "发来一张卡片")))
		"web_page":
			return str(card.get("title", card.get("url", "发来一个网页卡片")))
		_:
			return "发来一张卡片"


# --- 外部 API ---

func activate_test_topic(npc_id: String, channel_id: String, title: String, prompt: String) -> bool:
	return ChatManager.activate_test_topic(npc_id, channel_id, title, prompt)
