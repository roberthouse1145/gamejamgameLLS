class_name Desktop extends Control
## Desktop - 伪操作系统桌面
## Pseudo OS Desktop - manages the virtual desktop environment
## Handles background, desktop icons, and window container
##
## =============================================================================
## AVG Engine Workflow Documentation (Task 14.6)
## =============================================================================
##
## Complete Workflow Test Checklist:
##
## 1. PROJECT CREATION
##    [ ] Launch Project Manager from desktop icon
##    [ ] Create new project (File > New Project)
##    [ ] Set project name and basic settings
##    [ ] Verify project appears in project list
##
## 2. SCENE EDITING
##    [ ] Open Scene Editor from desktop or Project Manager
##    [ ] Create new scene in project
##    [ ] Add nodes to scene (Label, Sprite, Character, etc.)
##    [ ] Edit node properties (position, size, text, etc.)
##    [ ] Add auto commands (dialogue, narration, etc.)
##    [ ] Add parallel commands (background music, etc.)
##    [ ] Save scene (Ctrl+S)
##    [ ] Verify auto-save works (wait 60 seconds)
##
## 3. CHARACTER MANAGEMENT
##    [ ] Open Project Manager > Characters tab
##    [ ] Create new character
##    [ ] Set character name and display name
##    [ ] Add character expressions/sprites
##    [ ] Save character data
##
## 4. GAME PREVIEW
##    [ ] Launch Game Previewer from desktop
##    [ ] Load project in previewer
##    [ ] Select scene to preview
##    [ ] Click Play to start preview
##    [ ] Test keyboard shortcuts:
##        - Space: Play/Pause
##        - Escape: Stop
##    [ ] Enable debug mode to view variables
##    [ ] Verify error handling displays correctly
##
## 5. FILE MANAGEMENT
##    [ ] Launch File Manager from desktop
##    [ ] Browse project files
##    [ ] Import assets (images, audio)
##    [ ] Organize resources
##
## 6. KEYBOARD SHORTCUTS
##    Scene Editor:
##    - Ctrl+S: Save scene
##    - Ctrl+N: Add new node
##    - Delete: Delete selected node
##
##    Project Manager:
##    - Ctrl+S: Save project
##
##    Game Previewer:
##    - Space: Play/Pause
##    - Escape: Stop preview
##
## 7. AUTO-SAVE VERIFICATION
##    [ ] Make changes in Scene Editor
##    [ ] Wait 60 seconds without manual save
##    [ ] Verify auto-save occurs (check console)
##    [ ] Make changes in Project Manager
##    [ ] Verify project auto-saves
##
## 8. UNSAVED CHANGES WARNING
##    [ ] Make changes without saving
##    [ ] Try to close the app window
##    [ ] Verify unsaved changes dialog appears
##    [ ] Test "Save" option
##    [ ] Test "Don't Save" option
##
## =============================================================================

# Preload WindowManager class
const WindowManagerClass = preload("res://scripts/pseudo_os/window_manager.gd")

# Preload DesktopIcon scene and class
const DesktopIconScene = preload("res://scenes/pseudo_os/desktop_icon.tscn")
const DesktopIconClass = preload("res://scripts/pseudo_os/desktop_icon.gd")

# Preload Taskbar class
const TaskbarClass = preload("res://scripts/pseudo_os/taskbar.gd")
const NPCResponseHandlerClass = preload("res://scripts/chat/npc_response_handler.gd")

# Signals
signal desktop_ready
signal icon_double_clicked(app_id: String)

# Desktop components (set via unique names in scene)
@onready var background: Control = %Background
@onready var icon_grid: Control = %IconGrid
@onready var window_container: Control = %WindowContainer
@onready var taskbar: Control = %Taskbar

# WindowManager instance
var window_manager: Node = null

# Reference to AppManager autoload (accessed via scene tree)
var _app_manager: Node = null
var _chat_manager: Node = null

# Desktop icon tracking
var desktop_icons: Dictionary = {} # app_id -> DesktopIcon node
var _desktop_notifications: Dictionary = {} # notification_id -> Control
var _notification_stack: VBoxContainer = null
var _notification_message_queues: Dictionary = {} # channel_id -> Array[Dictionary]
var _notification_delivery_tokens: Dictionary = {} # channel_id -> int
var _active_notification_deliveries: Dictionary = {} # channel_id -> bool

# Desktop settings
@export var background_color: Color = Color(0.1, 0.3, 0.5)
@export var background_texture: Texture2D = null
@export var icon_spacing: Vector2 = Vector2(110, 116)
@export var icon_margin: Vector2 = Vector2(24, 24)

const CHAT_NOTIFICATION_DURATION: float = 6.0
const CHAT_NOTIFICATION_PAUSE_MIN: float = 0.5
const CHAT_NOTIFICATION_PAUSE_MAX: float = 1.5


func _ready() -> void:
	# Get AppManager autoload reference
	_app_manager = get_node_or_null("/root/AppManager")
	_chat_manager = get_node_or_null("/root/ChatManager")
	
	# Create WindowManager
	_setup_window_manager()
	
	# Setup AppManager reference
	_setup_app_manager()
	_setup_chat_notifications()
	_setup_notification_layer()
	
	# Setup background
	_setup_background()
	
	# Create desktop icons for registered apps
	_create_desktop_icons()
	
	# Emit ready signal
	desktop_ready.emit()
	return
	await get_tree().create_timer(1).timeout
	var run_manager: Node = get_node_or_null("/root/CampaignRunManager")
	if run_manager != null and run_manager.has_method("ensure_campaign_started"):
		run_manager.ensure_campaign_started("day1")
	elif StoryDirector != null:
		StoryDirector.start_chapter("day1")

## Setup the WindowManager instance
func _setup_window_manager() -> void:
	window_manager = WindowManagerClass.new()
	add_child(window_manager)
	
	# Set the window container for WindowManager
	window_manager.set_window_container(window_container)
	_bind_embedded_window_focus()
	
	# Connect window signals for taskbar integration
	window_manager.window_created.connect(_on_window_created)
	window_manager.window_closed.connect(_on_window_closed)
	window_manager.window_focused.connect(_on_window_focused)
	
	# Connect taskbar signal
	if taskbar:
		taskbar.window_button_clicked.connect(_on_taskbar_window_button_clicked)


func _bind_embedded_window_focus() -> void:
	if window_container == null or window_manager == null:
		return

	for child in window_container.get_children():
		if not (child is Control):
			continue
		var window := child as Control
		if not window.has_signal("focus_requested"):
			continue
		var callback := _on_embedded_window_focus_requested.bind(window)
		if not window.focus_requested.is_connected(callback):
			window.focus_requested.connect(callback)


func _on_embedded_window_focus_requested(window: Control) -> void:
	if window_manager != null:
		window_manager.focus_window(window)


## Setup AppManager with WindowManager reference
func _setup_app_manager() -> void:
	# AppManager is an autoload, access it via scene tree
	if _app_manager:
		_app_manager.set_window_manager(window_manager)
		# Connect app signals
		_app_manager.app_launched.connect(_on_app_launched)
		_app_manager.app_closed.connect(_on_app_closed)
		if _app_manager.has_signal("app_access_changed"):
			_app_manager.app_access_changed.connect(_on_app_access_changed)
	else:
		push_error("Desktop: AppManager autoload not found")


func _setup_chat_notifications() -> void:
	if _chat_manager == null:
		return
	if _chat_manager.has_signal("message_added"):
		_chat_manager.message_added.connect(_on_chat_message_added)
	if _chat_manager.has_signal("topic_activated"):
		_chat_manager.topic_activated.connect(_on_chat_topic_activated)


func _setup_notification_layer() -> void:
	_notification_stack = VBoxContainer.new()
	_notification_stack.name = "NotificationStack"
	_notification_stack.anchor_left = 1.0
	_notification_stack.anchor_top = 1.0
	_notification_stack.anchor_right = 1.0
	_notification_stack.anchor_bottom = 1.0
	# 2560x1440: 宽 420px，底部避开 taskbar(56px) + 间距 16px
	_notification_stack.offset_left = -436.0
	_notification_stack.offset_top = -360.0
	_notification_stack.offset_right = -16.0
	_notification_stack.offset_bottom = -72.0
	_notification_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notification_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notification_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_stack.alignment = BoxContainer.ALIGNMENT_END
	_notification_stack.add_theme_constant_override("separation", 12)
	_notification_stack.z_index = 100
	add_child(_notification_stack)


## Setup the desktop background
func _setup_background() -> void:
	if not background:
		push_warning("Desktop: Background node not found")
		return
	
	# If background is a ColorRect, set the color
	if background is ColorRect:
		background.color = background_color
	
	# If background is a TextureRect and we have a texture, set it
	if background is TextureRect and background_texture:
		background.texture = background_texture


## Create desktop icons for all registered apps
func _create_desktop_icons() -> void:
	if not _app_manager:
		return
	
	var registered_apps: Array = _app_manager.get_registered_apps()
	for app_def in registered_apps:
		add_desktop_icon(app_def)
	_refresh_icon_access_state()


## Add a desktop icon for an app
## @param app_definition: The AppDefinition resource for the app
func add_desktop_icon(app_definition: Resource) -> void:
	if not app_definition:
		return
	
	var app_id: String = app_definition.app_id
	
	# Check if icon already exists
	if desktop_icons.has(app_id):
		push_warning("Desktop: Icon for app '%s' already exists" % app_id)
		return
	
	# Create icon node (will be implemented in Task 5.2)
	# For now, create a placeholder that can be replaced later
	var icon := _create_icon_placeholder(app_definition)
	
	if icon and icon_grid:
		icon_grid.add_child(icon)
		desktop_icons[app_id] = icon
		
		# Position the icon in grid
		_position_icon(icon, desktop_icons.size() - 1)


## Create a placeholder icon (will be replaced with DesktopIcon scene in Task 5.2)
func _create_icon_placeholder(app_definition: Resource) -> Control:
	# Use the DesktopIcon scene
	var icon: Control = DesktopIconScene.instantiate()
	
	if icon:
		# Setup from app definition
		icon.setup_from_definition(app_definition)
		
		# Connect double-click signal
		icon.double_clicked.connect(_on_desktop_icon_double_clicked)
	
	return icon


## Handle desktop icon double-click
func _on_desktop_icon_double_clicked(app_id: String) -> void:
	icon_double_clicked.emit(app_id)
	_launch_app(app_id)


## Position an icon in the grid
func _position_icon(icon: Control, index: int) -> void:
	if not icon_grid:
		return
	
	# Calculate grid position
	var grid_size := icon_grid.size
	var icons_per_column := int((grid_size.y - icon_margin.y * 2) / icon_spacing.y)
	if icons_per_column <= 0:
		icons_per_column = 1
	
	@warning_ignore("integer_division")
	var col := index / icons_per_column
	var row := index % icons_per_column
	
	icon.position = Vector2(
		icon_margin.x + col * icon_spacing.x,
		icon_margin.y + row * icon_spacing.y
	)


## Remove a desktop icon
## @param app_id: The ID of the app whose icon to remove
func remove_desktop_icon(app_id: String) -> void:
	if not desktop_icons.has(app_id):
		return
	
	var icon: Control = desktop_icons[app_id]
	if is_instance_valid(icon):
		icon.queue_free()
	desktop_icons.erase(app_id)
	
	# Reposition remaining icons
	_reposition_all_icons()


## Reposition all icons after removal
func _reposition_all_icons() -> void:
	var index := 0
	for app_id in desktop_icons:
		var icon: Control = desktop_icons[app_id]
		if is_instance_valid(icon):
			_position_icon(icon, index)
			index += 1


## Set the desktop background color
## @param color: The new background color
func set_background_color(color: Color) -> void:
	background_color = color
	if background is ColorRect:
		background.color = color


## Set the desktop background texture
## @param texture: The new background texture
func set_background_texture(texture: Texture2D) -> void:
	background_texture = texture
	if background is TextureRect:
		background.texture = texture


## Get the WindowManager instance
## @return: The WindowManager
func get_window_manager() -> Node:
	return window_manager


## Get the window container
## @return: The Control node used as window container
func get_window_container() -> Control:
	return window_container


# Signal handlers

func _launch_app(app_id: String) -> void:
	if _app_manager:
		_app_manager.launch_app(app_id)


func _on_window_created(window: Control) -> void:
	# Add taskbar button for the new window
	if taskbar and window:
		var title: String = window.window_title if "window_title" in window else "Window"
		taskbar.add_window_button(window, title)


func _on_window_closed(window: Control) -> void:
	# Remove taskbar button for the closed window
	if taskbar:
		taskbar.remove_window_button(window)


func _on_window_focused(window: Control) -> void:
	# Update taskbar button states
	if taskbar:
		# Clear focused state on all buttons
		for tracked_window in taskbar.get_tracked_windows():
			taskbar.set_window_button_focused(tracked_window, false)
		# Set focused state on the focused window's button
		taskbar.set_window_button_focused(window, true)


func _on_taskbar_window_button_clicked(window: Control) -> void:
	# Handle taskbar button click - focus or restore the window
	if not window or not is_instance_valid(window):
		return
	
	if window.is_minimized:
		# Restore minimized window
		window_manager.restore_window(window)
	else:
		# Focus the window
		window_manager.focus_window(window)


func _on_app_launched(_app_id: String, _window: Control) -> void:
	# Could update icon state to show app is running
	pass


func _on_app_closed(_app_id: String) -> void:
	# Could update icon state to show app is closed
	pass


func _on_app_access_changed(_mode: String, _apps: Array[String]) -> void:
	_refresh_icon_access_state()


func _refresh_icon_access_state() -> void:
	if _app_manager == null:
		return

	for app_id in desktop_icons.keys():
		var icon: Node = desktop_icons[app_id]
		if icon == null or not is_instance_valid(icon):
			continue
		var accessible: bool = _app_manager.is_app_accessible(app_id)
		if icon.has_method("set_accessible"):
			icon.set_accessible(accessible)


func _on_chat_message_added(channel_id: String, msg: Dictionary) -> void:
	var sender: String = str(msg.get("sender_id", ""))
	# 只通知 NPC 消息，忽略玩家自己发的和系统消息
	if sender == "player" or sender == "system" or sender.is_empty():
		return

	# 如果 linkchat 已打开且玩家正在看这个频道，不弹通知
	if _is_linkchat_viewing_channel(channel_id):
		return

	var sender_name: String = str(msg.get("sender_name", sender))
	if _chat_manager != null and _chat_manager.has_method("resolve_sender_name"):
		var resolved: String = str(_chat_manager.resolve_sender_name(sender)).strip_edges()
		if not resolved.is_empty():
			sender_name = resolved

	var content_preview: String = str(msg.get("content", "")).strip_edges()
	if content_preview.length() > 40:
		content_preview = content_preview.left(40) + "…"
	if content_preview.is_empty():
		content_preview = "[新消息]"

	_queue_linkchat_notification(channel_id, msg)


func _on_chat_topic_activated(topic: ChatTopic) -> void:
	# topic_activated 只处理 force 模式（剧情事件强制打开 linkchat）
	# 普通消息通知由 _on_chat_message_added 处理
	var open_mode: String = _resolve_linkchat_open_mode(topic)
	if open_mode == "force":
		_open_linkchat_channel(topic.channel_id, true)


func _is_linkchat_viewing_channel(channel_id: String) -> bool:
	if _app_manager == null or not _app_manager.is_app_running("linkchat"):
		return false
	var window: Control = _app_manager.get_app_window("linkchat")
	if window == null or not is_instance_valid(window):
		return false
	# 检查窗口是否被最小化
	if "is_minimized" in window and window.is_minimized:
		return false
	if not ("content" in window):
		return false
	var app: Node = window.content as Node
	if app == null:
		return false
	if "current_channel_id" in app and app.current_channel_id == channel_id:
		return true
	return false


func _resolve_linkchat_open_mode(topic: ChatTopic) -> String:
	var explicit_mode: String = str(topic.context_data.get("linkchat_open_mode", "")).strip_edges().to_lower()
	if explicit_mode in ["force", "notify", "silent"]:
		return explicit_mode
	if topic.topic_type == "story_event":
		return "force"
	return "notify"


func _open_linkchat_channel(channel_id: String, force_launch: bool = false) -> void:
	if _app_manager == null:
		return

	_clear_channel_notifications(channel_id)

	var window: Control = null
	if _app_manager.has_method("focus_app"):
		window = _app_manager.focus_app("linkchat", force_launch)
	elif _app_manager.has_method("launch_app"):
		window = _app_manager.launch_app("linkchat", force_launch)

	_focus_linkchat_channel(window, channel_id)


func _focus_linkchat_channel(window: Control, channel_id: String) -> void:
	if window == null or not is_instance_valid(window):
		return
	if not ("content" in window):
		return

	var content: Variant = window.content
	if not (content is Node):
		return

	var app: Node = content as Node
	if app.has_method("open_topic_channel"):
		app.call_deferred("open_topic_channel", channel_id)
	elif app.has_method("select_channel"):
		app.call_deferred("select_channel", channel_id)


func _show_linkchat_notification(channel_id: String, sender_name: String, preview: String) -> void:
	if _notification_stack == null:
		return

	# 同一频道只保留最新一条通知
	var notification_id := "linkchat:%s" % channel_id
	_remove_notification(notification_id)

	# TODO: 播放通知音效（音频系统尚未实现）

	var toast := PanelContainer.new()
	toast.custom_minimum_size = Vector2(0, 0)
	toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toast.modulate.a = 0.0

	# 亮色风格：白底 + 浅灰边框 + 微阴影，与 LinkChat UI 一致
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#FFFFFF")
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color("#E0E0E0")
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.10)
	panel_style.shadow_offset = Vector2(0, 2)
	toast.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	toast.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	margin.add_child(hbox)

	# 左侧头像占位（圆形色块 + 首字母）
	var avatar_panel := PanelContainer.new()
	avatar_panel.custom_minimum_size = Vector2(48, 48)
	avatar_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = Color("#95EC69")
	avatar_style.corner_radius_top_left = 24
	avatar_style.corner_radius_top_right = 24
	avatar_style.corner_radius_bottom_left = 24
	avatar_style.corner_radius_bottom_right = 24
	avatar_panel.add_theme_stylebox_override("panel", avatar_style)
	var avatar_label := Label.new()
	avatar_label.text = sender_name.left(1) if not sender_name.is_empty() else "?"
	avatar_label.add_theme_font_size_override("font_size", 22)
	avatar_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_panel.add_child(avatar_label)
	hbox.add_child(avatar_panel)

	# 右侧文字区
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(text_vbox)

	# 第一行：应用名 + 发送者
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 8)
	text_vbox.add_child(header_hbox)

	var app_label := Label.new()
	app_label.text = "LinkChat"
	app_label.add_theme_font_size_override("font_size", 14)
	app_label.add_theme_color_override("font_color", Color("#B0B0B0"))
	header_hbox.add_child(app_label)

	var dot_label := Label.new()
	dot_label.text = "·"
	dot_label.add_theme_font_size_override("font_size", 14)
	dot_label.add_theme_color_override("font_color", Color("#B0B0B0"))
	header_hbox.add_child(dot_label)

	var name_label := Label.new()
	name_label.text = sender_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color("#1F1F1F"))
	header_hbox.add_child(name_label)

	# 第二行：消息预览
	var body_label := Label.new()
	body_label.text = preview
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 16)
	body_label.add_theme_color_override("font_color", Color("#555555"))
	text_vbox.add_child(body_label)

	toast.gui_input.connect(_on_notification_gui_input.bind(notification_id, channel_id))
	_notification_stack.add_child(toast)
	_notification_stack.move_child(toast, 0)
	_desktop_notifications[notification_id] = toast

	var fade_in := create_tween()
	fade_in.tween_property(toast, "modulate:a", 1.0, 0.18)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = CHAT_NOTIFICATION_DURATION
	timer.timeout.connect(_expire_notification.bind(notification_id))
	toast.add_child(timer)
	timer.start()


func _queue_linkchat_notification(channel_id: String, msg: Dictionary) -> void:
	var normalized_channel_id := channel_id.strip_edges()
	if normalized_channel_id.is_empty():
		return

	var queue: Array = _notification_message_queues.get(normalized_channel_id, [])
	queue.append(msg.duplicate(true))
	_notification_message_queues[normalized_channel_id] = queue

	if bool(_active_notification_deliveries.get(normalized_channel_id, false)):
		return

	var token := int(_notification_delivery_tokens.get(normalized_channel_id, 0)) + 1
	_notification_delivery_tokens[normalized_channel_id] = token
	_active_notification_deliveries[normalized_channel_id] = true
	_deliver_linkchat_notifications(normalized_channel_id, token)


func _deliver_linkchat_notifications(channel_id: String, token: int) -> void:
	while true:
		if token != int(_notification_delivery_tokens.get(channel_id, 0)):
			return
		if _is_linkchat_viewing_channel(channel_id):
			_clear_channel_notifications(channel_id, false)
			return

		var queue: Array = _notification_message_queues.get(channel_id, [])
		if queue.is_empty():
			break

		var raw_message: Variant = queue[0]
		queue.remove_at(0)
		if queue.is_empty():
			_notification_message_queues.erase(channel_id)
		else:
			_notification_message_queues[channel_id] = queue

		if not raw_message is Dictionary:
			continue

		var msg: Dictionary = (raw_message as Dictionary).duplicate(true)
		var typing_delay := _calculate_notification_delay(msg)
		if typing_delay > 0.0:
			await get_tree().create_timer(typing_delay).timeout

		if token != int(_notification_delivery_tokens.get(channel_id, 0)):
			return
		if _is_linkchat_viewing_channel(channel_id):
			_clear_channel_notifications(channel_id, false)
			return

		var sender_name := _resolve_notification_sender_name(msg)
		var preview := _build_notification_preview(msg)
		_show_linkchat_notification(channel_id, sender_name, preview)

		if _notification_message_queues.has(channel_id):
			var pause := randf_range(CHAT_NOTIFICATION_PAUSE_MIN, CHAT_NOTIFICATION_PAUSE_MAX)
			await get_tree().create_timer(pause).timeout

	if token == int(_notification_delivery_tokens.get(channel_id, 0)):
		_active_notification_deliveries.erase(channel_id)


func _clear_channel_notifications(channel_id: String, bump_token: bool = true) -> void:
	var normalized_channel_id := channel_id.strip_edges()
	if normalized_channel_id.is_empty():
		return

	_notification_message_queues.erase(normalized_channel_id)
	_active_notification_deliveries.erase(normalized_channel_id)
	if bump_token:
		_notification_delivery_tokens[normalized_channel_id] = int(_notification_delivery_tokens.get(normalized_channel_id, 0)) + 1

	var notification_id := "linkchat:%s" % normalized_channel_id
	_remove_notification(notification_id)


func _resolve_notification_sender_name(msg: Dictionary) -> String:
	var sender: String = str(msg.get("sender_id", "")).strip_edges()
	var sender_name: String = str(msg.get("sender_name", sender)).strip_edges()
	if _chat_manager != null and _chat_manager.has_method("resolve_sender_name"):
		var resolved: String = str(_chat_manager.resolve_sender_name(sender)).strip_edges()
		if not resolved.is_empty():
			sender_name = resolved
	if sender_name.is_empty():
		sender_name = sender if not sender.is_empty() else "LinkChat"
	return sender_name


func _build_notification_preview(msg: Dictionary) -> String:
	var content_preview: String = str(msg.get("content", "")).strip_edges()
	if content_preview.is_empty() and msg.has("card") and msg["card"] is Dictionary:
		content_preview = _build_card_notification_preview(msg["card"] as Dictionary)
	if content_preview.length() > 40:
		content_preview = content_preview.left(40) + "..."
	if content_preview.is_empty():
		content_preview = "[新消息]"
	return content_preview


func _build_card_notification_preview(card: Dictionary) -> String:
	var card_type := str(card.get("type", "")).strip_edges().to_lower()
	match card_type:
		"image":
			var caption := str(card.get("caption", "")).strip_edges()
			return "[图片] %s" % caption if not caption.is_empty() else "[图片]"
		"link":
			var title := str(card.get("title", "")).strip_edges()
			return "[链接] %s" % title if not title.is_empty() else "[链接]"
		_:
			var title := str(card.get("title", "")).strip_edges()
			return "[卡片] %s" % title if not title.is_empty() else "[卡片消息]"


func _calculate_notification_delay(msg: Dictionary) -> float:
	var content := str(msg.get("content", "")).strip_edges()
	if content.is_empty() and msg.has("card") and msg["card"] is Dictionary:
		content = _build_card_notification_preview(msg["card"] as Dictionary)
	content = NPCResponseHandlerClass.clean_message(content)
	return NPCResponseHandlerClass.calculate_typing_delay(content)


func _on_notification_gui_input(event: InputEvent, notification_id: String, channel_id: String) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	# 先 kill 可能正在播放的 fade_out tween，防止 freed object 警告
	var toast: Control = _desktop_notifications.get(notification_id)
	if toast != null and is_instance_valid(toast) and toast.has_meta("_fade_tween"):
		var tw: Tween = toast.get_meta("_fade_tween") as Tween
		if tw != null and tw.is_valid():
			tw.kill()

	_remove_notification(notification_id)
	_open_linkchat_channel(channel_id, true)


func _expire_notification(notification_id: String) -> void:
	var toast: Control = _desktop_notifications.get(notification_id)
	if toast == null or not is_instance_valid(toast):
		_desktop_notifications.erase(notification_id)
		return

	var fade_out := create_tween()
	toast.set_meta("_fade_tween", fade_out)
	fade_out.tween_property(toast, "modulate:a", 0.0, 0.18)
	fade_out.tween_callback(func() -> void: _remove_notification(notification_id))


func _remove_notification(notification_id: String) -> void:
	if not _desktop_notifications.has(notification_id):
		return

	var toast: Control = _desktop_notifications[notification_id]
	_desktop_notifications.erase(notification_id)
	if toast != null and is_instance_valid(toast):
		toast.queue_free()
