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

# Desktop settings
@export var background_color: Color = Color(0.1, 0.3, 0.5)
@export var background_texture: Texture2D = null
@export var icon_spacing: Vector2 = Vector2(110, 116)
@export var icon_margin: Vector2 = Vector2(24, 24)

const CHAT_NOTIFICATION_DURATION: float = 6.0


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
	
	# Connect window signals for taskbar integration
	window_manager.window_created.connect(_on_window_created)
	window_manager.window_closed.connect(_on_window_closed)
	window_manager.window_focused.connect(_on_window_focused)
	
	# Connect taskbar signal
	if taskbar:
		taskbar.window_button_clicked.connect(_on_taskbar_window_button_clicked)


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
	if _chat_manager.has_signal("topic_activated"):
		_chat_manager.topic_activated.connect(_on_chat_topic_activated)


func _setup_notification_layer() -> void:
	_notification_stack = VBoxContainer.new()
	_notification_stack.name = "NotificationStack"
	_notification_stack.anchor_left = 1.0
	_notification_stack.anchor_top = 1.0
	_notification_stack.anchor_right = 1.0
	_notification_stack.anchor_bottom = 1.0
	_notification_stack.offset_left = -320.0
	_notification_stack.offset_top = -220.0
	_notification_stack.offset_right = -16.0
	_notification_stack.offset_bottom = -72.0
	_notification_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notification_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notification_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_stack.alignment = BoxContainer.ALIGNMENT_END
	_notification_stack.add_theme_constant_override("separation", 10)
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


func _on_chat_topic_activated(topic: ChatTopic) -> void:
	var open_mode: String = _resolve_linkchat_open_mode(topic)
	match open_mode:
		"force":
			_open_linkchat_channel(topic.channel_id, true)
		"notify":
			_show_linkchat_notification(topic)


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


func _show_linkchat_notification(topic: ChatTopic) -> void:
	if _notification_stack == null:
		return

	var notification_id := "linkchat:%s" % topic.topic_id
	_remove_notification(notification_id)

	var toast := PanelContainer.new()
	toast.custom_minimum_size = Vector2(0, 84)
	toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toast.modulate.a = 0.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.13, 0.18, 0.96)
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.34, 0.44, 0.60, 0.95)
	panel_style.shadow_size = 6
	panel_style.shadow_color = Color(0, 0, 0, 0.22)
	toast.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	toast.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	margin.add_child(content)

	var app_label := Label.new()
	app_label.text = "LinkChat"
	app_label.add_theme_font_size_override("font_size", 12)
	app_label.add_theme_color_override("font_color", Color(0.68, 0.80, 1.0, 0.95))
	content.add_child(app_label)

	var sender_name := topic.npc_id
	if _chat_manager != null and _chat_manager.has_method("resolve_sender_name"):
		sender_name = str(_chat_manager.resolve_sender_name(topic.npc_id))

	var title_label := Label.new()
	title_label.text = "%s 发来新话题" % sender_name
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	content.add_child(title_label)

	var body_label := Label.new()
	body_label.text = topic.display_title
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 12)
	body_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96, 0.92))
	content.add_child(body_label)

	toast.gui_input.connect(_on_notification_gui_input.bind(notification_id, topic.channel_id))
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


func _on_notification_gui_input(event: InputEvent, notification_id: String, channel_id: String) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	_remove_notification(notification_id)
	_open_linkchat_channel(channel_id, true)


func _expire_notification(notification_id: String) -> void:
	var toast: Control = _desktop_notifications.get(notification_id)
	if toast == null or not is_instance_valid(toast):
		_desktop_notifications.erase(notification_id)
		return

	var fade_out := create_tween()
	fade_out.tween_property(toast, "modulate:a", 0.0, 0.18)
	fade_out.tween_callback(func() -> void: _remove_notification(notification_id))


func _remove_notification(notification_id: String) -> void:
	if not _desktop_notifications.has(notification_id):
		return

	var toast: Control = _desktop_notifications[notification_id]
	_desktop_notifications.erase(notification_id)
	if toast != null and is_instance_valid(toast):
		toast.queue_free()
