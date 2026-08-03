class_name Desktop extends Control
## Desktop - 伪操作系统桌面
## Pseudo OS Desktop - manages the virtual desktop environment
## Handles background, desktop icons, and window container

# Preload WindowManager class
const WindowManagerClass = preload("res://scripts/pseudo_os/window_manager.gd")

# Preload DesktopIcon scene and class
const DesktopIconScene = preload("res://scenes/pseudo_os/desktop_icon.tscn")
const DesktopIconClass = preload("res://scripts/pseudo_os/desktop_icon.gd")

# Preload Taskbar class
const TaskbarClass = preload("res://scripts/pseudo_os/taskbar.gd")
const UIIconLibraryClass = preload("res://scripts/ui/ui_icon_library.gd")

# Start menu & system panels
const StartMenuScene = preload("res://scenes/pseudo_os/start_menu.tscn")
const SettingsPanelScene = preload("res://scenes/pseudo_os/settings_panel.tscn")
const QuitConfirmPanelScene = preload("res://scenes/pseudo_os/quit_confirm_panel.tscn")

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

# Desktop icon tracking
var desktop_icons: Dictionary = {} # app_id -> DesktopIcon node
var _selected_desktop_icon_id: String = ""
var _desktop_icon_visibility_overrides: Dictionary = {} # app_id -> bool
var _desktop_notifications: Dictionary = {} # notification_id -> Control
var _notification_stack: VBoxContainer = null

# Start menu
var _start_menu: Control = null
var _settings_window: Control = null
var _quit_confirm_window: Control = null

# Desktop settings
@export var background_color: Color = Color(0.1, 0.3, 0.5)
@export var background_texture: Texture2D = null
@export var icon_spacing: Vector2 = Vector2(156, 184)
@export var icon_margin: Vector2 = Vector2(28, 28)
@export var desktop_app_ids: PackedStringArray = PackedStringArray()

const GROUP_NAME: String = "desktop"


## 获取当前唯一 Desktop 实例（通过 group 查找，与节点路径无关）
static func instance() -> Desktop:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP_NAME) as Desktop


func _ready() -> void:
	add_to_group(GROUP_NAME)
	# Get AppManager autoload reference
	_app_manager = get_node_or_null("/root/AppManager")
	
	# Create WindowManager
	_setup_window_manager()
	
	# Setup AppManager reference
	_setup_app_manager()
	_setup_notification_layer()
	
	# Setup background
	_setup_background()
	
	# Create desktop icons for registered apps
	_create_desktop_icons()
	
	# Setup start menu
	_setup_start_menu()
	
	# Emit ready signal
	desktop_ready.emit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	if _is_pointer_over_desktop_icon(mouse_event.global_position):
		return

	_clear_desktop_icon_selection()

## Setup the WindowManager instance
func _setup_window_manager() -> void:
	window_manager = WindowManagerClass.new()
	add_child(window_manager)
	
	# Set the window container for WindowManager
	window_manager.set_window_container(window_container)
	window_manager.set_taskbar(taskbar)
	_bind_embedded_window_focus()
	
	# Connect window signals for taskbar integration
	window_manager.window_created.connect(_on_window_created)
	window_manager.window_closed.connect(_on_window_closed)
	window_manager.window_focused.connect(_on_window_focused)
	
	# Connect taskbar signal
	if taskbar:
		taskbar.window_button_clicked.connect(_on_taskbar_window_button_clicked)


## Setup the start menu popup
func _setup_start_menu() -> void:
	_start_menu = StartMenuScene.instantiate()
	_start_menu.z_index = 200
	add_child(_start_menu)

	_start_menu.settings_requested.connect(_on_start_menu_settings)
	_start_menu.power_off_requested.connect(_on_start_menu_power_off)

	if taskbar and taskbar.has_signal("start_button_clicked"):
		taskbar.start_button_clicked.connect(_on_start_button_clicked)


func _on_start_button_clicked() -> void:
	if _start_menu == null:
		return
	var anchor_pos: Vector2 = Vector2.ZERO
	if taskbar and taskbar.has_method("get_start_button_global_position"):
		anchor_pos = taskbar.get_start_button_global_position()
	_start_menu.toggle_menu(anchor_pos)


func _on_start_menu_settings() -> void:
	_open_settings_window()


func _on_start_menu_power_off() -> void:
	_open_quit_confirm_window()


func _open_settings_window() -> void:
	# 如果已打开，聚焦已有窗口
	if _settings_window and is_instance_valid(_settings_window):
		window_manager.focus_window(_settings_window)
		return

	var content: Control = SettingsPanelScene.instantiate()
	var constraints := preload("res://scripts/pseudo_os/window_constraints.gd").new()
	constraints.min_size = Vector2(480, 360)
	constraints.default_size = Vector2(520, 420)
	constraints.resizable = true

	_settings_window = window_manager.create_window("设置", content, constraints)
	if _settings_window:
		_settings_window.close_requested.connect(func() -> void:
			window_manager.close_window(_settings_window)
			_settings_window = null
		)


func _open_quit_confirm_window() -> void:
	if _quit_confirm_window and is_instance_valid(_quit_confirm_window):
		window_manager.focus_window(_quit_confirm_window)
		return

	var content: Control = QuitConfirmPanelScene.instantiate()
	var constraints := preload("res://scripts/pseudo_os/window_constraints.gd").new()
	constraints.min_size = Vector2(400, 300)
	constraints.default_size = Vector2(440, 340)
	constraints.resizable = false

	_quit_confirm_window = window_manager.create_window("关闭电源", content, constraints)
	if _quit_confirm_window:
		_quit_confirm_window.close_requested.connect(func() -> void:
			window_manager.close_window(_quit_confirm_window)
			_quit_confirm_window = null
		)
		content.confirmed.connect(func() -> void:
			get_tree().quit()
		)
		content.cancelled.connect(func() -> void:
			window_manager.close_window(_quit_confirm_window)
			_quit_confirm_window = null
		)


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
		if _app_manager.has_signal("app_registered"):
			_app_manager.app_registered.connect(_on_app_registered)
		if _app_manager.has_signal("app_unregistered"):
			_app_manager.app_unregistered.connect(_on_app_unregistered)
		if _app_manager.has_signal("app_desktop_visibility_changed"):
			_app_manager.app_desktop_visibility_changed.connect(_on_app_desktop_visibility_changed)
		if _app_manager.has_signal("app_access_changed"):
			_app_manager.app_access_changed.connect(_on_app_access_changed)
	else:
		push_error("Desktop: AppManager autoload not found")


func _setup_notification_layer() -> void:
	_notification_stack = VBoxContainer.new()
	_notification_stack.name = "NotificationStack"
	_notification_stack.anchor_left = 1.0
	_notification_stack.anchor_top = 1.0
	_notification_stack.anchor_right = 1.0
	_notification_stack.anchor_bottom = 1.0
	# 2560x1440: 右下角更靠内，底部避开 taskbar 与时钟区域
	_notification_stack.offset_left = -496.0
	_notification_stack.offset_top = -340.0
	_notification_stack.offset_right = -28.0
	_notification_stack.offset_bottom = -106.0
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
	
	var registered_apps: Array = _get_desktop_app_definitions()
	for app_def in registered_apps:
		add_desktop_icon(app_def)
	_refresh_icon_access_state()


func _get_desktop_app_definitions() -> Array:
	if _app_manager == null:
		return []

	var app_definitions: Array = []
	for app_definition in _app_manager.get_registered_apps():
		if app_definition == null:
			continue
		var app_id: String = str(app_definition.app_id).strip_edges()
		if app_id.is_empty():
			continue
		if not _should_show_app_icon(app_id, app_definition):
			continue
		app_definitions.append(app_definition)

	return app_definitions


func _is_app_enabled_in_desktop_config(app_id: String) -> bool:
	if _desktop_icon_visibility_overrides.has(app_id):
		return bool(_desktop_icon_visibility_overrides[app_id])
	if desktop_app_ids.is_empty():
		return true
	return app_id in desktop_app_ids


func _should_show_app_icon(app_id: String, app_definition: Resource = null) -> bool:
	if app_id.is_empty():
		return false
	if not _is_app_enabled_in_desktop_config(app_id):
		return false
	if _app_manager != null and _app_manager.has_method("is_app_desktop_visible"):
		return bool(_app_manager.is_app_desktop_visible(app_id))
	if app_definition != null and "show_on_desktop" in app_definition:
		return bool(app_definition.show_on_desktop)
	return true


## Add a desktop icon for an app
## @param app_definition: The AppDefinition resource for the app
func add_desktop_icon(app_definition: Resource) -> void:
	if not app_definition:
		return
	
	var app_id: String = app_definition.app_id
	if not _should_show_app_icon(app_id, app_definition):
		return
	
	# Check if icon already exists
	if desktop_icons.has(app_id):
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
		if icon.has_signal("selected"):
			icon.selected.connect(_on_desktop_icon_selected)
		if icon.has_signal("deselected"):
			icon.deselected.connect(_on_desktop_icon_deselected)
	
	return icon


## Handle desktop icon double-click
func _on_desktop_icon_double_clicked(app_id: String) -> void:
	var icon: Node = desktop_icons.get(app_id, null)
	if icon != null and is_instance_valid(icon) and icon.has_method("play_launch_feedback"):
		icon.play_launch_feedback()
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
	if _selected_desktop_icon_id == app_id:
		_selected_desktop_icon_id = ""
	
	# Reposition remaining icons
	_reposition_all_icons()


func _on_desktop_icon_selected(app_id: String) -> void:
	_selected_desktop_icon_id = app_id
	_clear_desktop_icon_selection(app_id)


func _on_desktop_icon_deselected(app_id: String) -> void:
	if _selected_desktop_icon_id == app_id:
		_selected_desktop_icon_id = ""


func _clear_desktop_icon_selection(except_app_id: String = "") -> void:
	var normalized_except := except_app_id.strip_edges()
	for tracked_app_id in desktop_icons.keys():
		if tracked_app_id == normalized_except:
			continue

		var icon: Node = desktop_icons[tracked_app_id]
		if icon == null or not is_instance_valid(icon):
			continue

		if icon.has_method("deselect"):
			icon.deselect()
		elif icon.has_method("set_selected"):
			icon.set_selected(false)

	if normalized_except.is_empty():
		_selected_desktop_icon_id = ""


func _is_pointer_over_desktop_icon(global_pos: Vector2) -> bool:
	for app_id in desktop_icons.keys():
		var icon: Variant = desktop_icons[app_id]
		if not (icon is Control):
			continue

		var icon_control := icon as Control
		if not is_instance_valid(icon_control):
			continue
		if icon_control.get_global_rect().has_point(global_pos):
			return true

	return false


func set_app_icon_visible(app_id: String, desired_visible: bool) -> void:
	var normalized_app_id := app_id.strip_edges()
	if normalized_app_id.is_empty():
		return

	_desktop_icon_visibility_overrides[normalized_app_id] = desired_visible
	if not desired_visible:
		remove_desktop_icon(normalized_app_id)
		return

	if _app_manager == null:
		return
	var app_definition: Resource = _app_manager.get_app_definition(normalized_app_id)
	if app_definition != null:
		add_desktop_icon(app_definition)


func clear_app_icon_visibility_override(app_id: String) -> void:
	var normalized_app_id := app_id.strip_edges()
	if normalized_app_id.is_empty():
		return
	if not _desktop_icon_visibility_overrides.has(normalized_app_id):
		return

	_desktop_icon_visibility_overrides.erase(normalized_app_id)
	if _app_manager == null:
		return

	var app_definition: Resource = _app_manager.get_app_definition(normalized_app_id)
	if app_definition != null and _should_show_app_icon(normalized_app_id, app_definition):
		add_desktop_icon(app_definition)
	else:
		remove_desktop_icon(normalized_app_id)


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


func _on_app_registered(app_id: String, app_definition: Resource) -> void:
	if desktop_icons.has(app_id):
		remove_desktop_icon(app_id)
	if _should_show_app_icon(app_id, app_definition):
		add_desktop_icon(app_definition)
	_refresh_icon_access_state()


func _on_app_unregistered(app_id: String) -> void:
	_desktop_icon_visibility_overrides.erase(app_id)
	remove_desktop_icon(app_id)


func _on_app_desktop_visibility_changed(app_id: String, desired_visible: bool) -> void:
	set_app_icon_visible(app_id, desired_visible)
	_refresh_icon_access_state()


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


## 显示桌面右下角系统通知（Windows 风格提醒）
func show_system_notification(title: String, body: String, icon_token: String = "warning", duration: float = 5.0) -> void:
	if _notification_stack == null:
		return

	var notification_id := "system:%d" % (title + body).hash()
	_remove_notification(notification_id)

	var toast := PanelContainer.new()
	toast.custom_minimum_size = Vector2(0, 0)
	toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	toast.modulate.a = 0.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#F7FAFF")
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color("#D6DFEE")
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.14)
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

	# 左侧图标（Win11 风格圆底图标）
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(44, 44)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color("#E7EEFC")
	icon_style.corner_radius_top_left = 22
	icon_style.corner_radius_top_right = 22
	icon_style.corner_radius_bottom_left = 22
	icon_style.corner_radius_bottom_right = 22
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	var icon_texture := UIIconLibraryClass.get_icon(icon_token)
	if icon_texture != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(22, 22)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = _get_notification_icon_color(icon_token)
		icon_rect.anchors_preset = Control.PRESET_CENTER
		icon_panel.add_child(icon_rect)
	else:
		var icon_label := Label.new()
		icon_label.text = icon_token
		icon_label.add_theme_font_size_override("font_size", 20)
		icon_label.add_theme_color_override("font_color", Color("#4569C7"))
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_panel.add_child(icon_label)
	hbox.add_child(icon_panel)

	# 右侧文字
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(text_vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color("#1E2738"))
	text_vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 14)
	body_label.add_theme_color_override("font_color", Color("#56627A"))
	text_vbox.add_child(body_label)

	# 点击关闭
	toast.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_remove_notification(notification_id)
	)

	_notification_stack.add_child(toast)
	_notification_stack.move_child(toast, 0)
	_desktop_notifications[notification_id] = toast

	var fade_in := create_tween()
	fade_in.tween_property(toast, "modulate:a", 1.0, 0.18)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(_expire_notification.bind(notification_id))
	toast.add_child(timer)
	timer.start()


func _get_notification_icon_color(icon_token: String) -> Color:
	match icon_token.strip_edges().to_lower():
		"warning", "⚠":
			return Color("#C47A00")
		"power", "⏻":
			return Color("#D64545")
		_:
			return Color("#4569C7")
