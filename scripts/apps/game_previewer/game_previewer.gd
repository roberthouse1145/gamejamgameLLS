class_name GamePreviewer extends Control
## Game Previewer Application
## Allows users to test and preview their AVG games with debug capabilities.
## Validates: Task 11.1, 11.2, 11.3, 11.4

const AVGTitleConfigClass = preload("res://scripts/avg/resources/avg_title_config.gd")

# =============================================================================
# Signals
# =============================================================================

## Emitted when preview starts
signal preview_started()
## Emitted when preview stops
signal preview_stopped()
## Emitted when an error occurs during preview
signal error_occurred(error_message: String)

# =============================================================================
# Node References
# =============================================================================

## Reference to the AVGSceneRunner
@onready var scene_runner: Control = %AVGSceneRunner
## Reference to the control bar
@onready var control_bar: HBoxContainer = %ControlBar
## Reference to the play button
@onready var play_button: Button = %PlayButton
## Reference to the stop button
@onready var stop_button: Button = %StopButton
## Reference to the scene selector dropdown
@onready var scene_selector: OptionButton = %SceneSelector
## Reference to the debug toggle button
@onready var debug_toggle: Button = %DebugToggle
## Reference to the debug panel
@onready var debug_panel: PanelContainer = %DebugPanel
## Reference to the variable display container
@onready var variable_display: VBoxContainer = %VariableDisplay
## Reference to the error panel
@onready var error_panel: PanelContainer = %ErrorPanel
## Reference to the error label
@onready var error_label: RichTextLabel = %ErrorLabel
## Reference to the retry button
@onready var retry_button: Button = %RetryButton
## Reference to the dismiss button
@onready var dismiss_button: Button = %DismissButton
## Viewport scaling references
@onready var content_container: Control = %ContentContainer
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var preview_viewport: SubViewport = %PreviewViewport

# =============================================================================
# Properties
# =============================================================================

## Current AVGProject being previewed
var current_project: Resource = null  # AVGProject

## Whether the preview is currently playing
var is_playing: bool = false

## Currently selected scene index
var _selected_scene_index: int = 0

## Variable manager reference for debug display
var _variable_manager: RefCounted = null

## Dictionary to track variable labels in debug panel
var _variable_labels: Dictionary = {}

## List of error messages
var _error_messages: Array[String] = []

## Project resolution for viewport scaling
var _project_resolution: Vector2 = Vector2(2560, 1440)


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	print("[GamePreviewer] _ready() called")
	_setup_connections()
	_update_ui_state()
	_hide_error_panel()
	_hide_debug_panel()
	_debug_print_node_refs()
	
	# Setup viewport scaling
	if content_container:
		content_container.resized.connect(_on_content_resized)
	if preview_container:
		# Reset anchors so manual size/position works
		preview_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		preview_container.anchor_right = 0.0
		preview_container.anchor_bottom = 0.0
	
	# 监听全局项目变化
	StorageManager.current_project_changed.connect(_on_global_project_changed)
	
	# 如果已有当前项目，加载它
	if StorageManager.current_project != null:
		set_project(StorageManager.current_project)
		print("[GamePreviewer] Loaded existing project: %s" % StorageManager.current_project.project_name)
	
	# Deferred initial layout
	call_deferred("_on_content_resized")


## Handle keyboard shortcuts (Task 14.3)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				# Space to play/pause
				if is_playing:
					# Toggle pause (if scene_runner supports it)
					if scene_runner and scene_runner.has_method("toggle_pause"):
						scene_runner.toggle_pause()
				else:
					start_preview()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				# Escape to stop
				if is_playing:
					stop_preview()
				get_viewport().set_input_as_handled()


func _setup_connections() -> void:
	print("[GamePreviewer] _setup_connections() called")
	# Control bar buttons
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
		print("[GamePreviewer] play_button connected")
	else:
		print("[GamePreviewer] WARNING: play_button is null!")
	if stop_button:
		stop_button.pressed.connect(_on_stop_pressed)
		print("[GamePreviewer] stop_button connected")
	else:
		print("[GamePreviewer] WARNING: stop_button is null!")
	if scene_selector:
		scene_selector.item_selected.connect(_on_scene_selected)
		print("[GamePreviewer] scene_selector connected")
	else:
		print("[GamePreviewer] WARNING: scene_selector is null!")
	if debug_toggle:
		debug_toggle.toggled.connect(_on_debug_toggled)
		print("[GamePreviewer] debug_toggle connected")
	else:
		print("[GamePreviewer] WARNING: debug_toggle is null!")
	
	# Error panel buttons
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)
	if dismiss_button:
		dismiss_button.pressed.connect(_on_dismiss_pressed)
	
	# Scene runner signals
	if scene_runner:
		scene_runner.scene_started.connect(_on_scene_started)
		scene_runner.scene_ended.connect(_on_scene_ended)
		scene_runner.command_executed.connect(_on_command_executed)
		scene_runner.title_start_requested.connect(_on_title_start_requested)
		print("[GamePreviewer] scene_runner connected")
	else:
		print("[GamePreviewer] WARNING: scene_runner is null!")


## Debug print all node references
func _debug_print_node_refs() -> void:
	print("[GamePreviewer] === Node References ===")
	print("[GamePreviewer] scene_runner: ", scene_runner)
	print("[GamePreviewer] control_bar: ", control_bar)
	print("[GamePreviewer] play_button: ", play_button)
	print("[GamePreviewer] stop_button: ", stop_button)
	print("[GamePreviewer] scene_selector: ", scene_selector)
	print("[GamePreviewer] debug_toggle: ", debug_toggle)
	print("[GamePreviewer] debug_panel: ", debug_panel)
	print("[GamePreviewer] error_panel: ", error_panel)
	print("[GamePreviewer] === End Node References ===")


# =============================================================================
# Viewport Scaling
# =============================================================================

## Resize PreviewContainer to maintain aspect ratio within ContentContainer
func _on_content_resized() -> void:
	if content_container == null or preview_container == null:
		return
	
	var available_size: Vector2 = content_container.size
	if available_size.x <= 0 or available_size.y <= 0:
		return
	
	var aspect_ratio: float = _project_resolution.x / _project_resolution.y
	var container_aspect: float = available_size.x / available_size.y
	
	var new_size: Vector2
	if container_aspect > aspect_ratio:
		# Wider than project — fit height, pillarbox
		new_size.y = available_size.y
		new_size.x = available_size.y * aspect_ratio
	else:
		# Taller than project — fit width, letterbox
		new_size.x = available_size.x
		new_size.y = available_size.x / aspect_ratio
	
	preview_container.size = new_size
	preview_container.position = (available_size - new_size) / 2


# =============================================================================
# Task 11.2: Project and Scene Selection
# =============================================================================

## Set the project to preview
## @param project: The AVGProject resource to preview
func set_project(project: Resource) -> void:
	# Stop any current preview
	if is_playing:
		stop_preview()
	
	current_project = project
	_selected_scene_index = 0
	
	# Read project resolution and update viewport
	if project and "resolution" in project:
		_project_resolution = Vector2(project.resolution)
	else:
		_project_resolution = Vector2(2560, 1440)
	
	# stretch=true 时不能手动设 SubViewport.size（Godot 会忽略并警告）
	# SubViewport.size 由 SubViewportContainer 自动控制
	# SceneRunner 内部通过归一化坐标 + SubViewport 实际 size 来定位
	
	# Recalculate aspect-ratio layout
	_on_content_resized()
	
	# Update scene selector
	_populate_scene_selector()
	
	# Load project into scene runner
	if scene_runner and project:
		scene_runner.load_project(project)
	
	# Connect to variable manager for debug display
	_connect_variable_manager()
	
	_update_ui_state()


## 标题界面在场景选择器中的特殊索引
const TITLE_SCREEN_INDEX: int = -1


## Populate the scene selector dropdown with project scenes
func _populate_scene_selector() -> void:
	if scene_selector == null:
		return
	
	scene_selector.clear()
	
	if current_project == null:
		scene_selector.add_item("No Project Loaded", 0)
		scene_selector.disabled = true
		return
	
	scene_selector.disabled = false
	
	var scenes: Array = current_project.scenes
	if scenes.is_empty():
		scene_selector.add_item("No Scenes Available", 0)
		scene_selector.disabled = true
		return
	
	# 如果标题界面已启用，在最前面加一个"标题界面"选项
	var has_title: bool = false
	if current_project.title_config != null and current_project.title_config is AVGTitleConfigClass:
		has_title = current_project.title_config.enabled
	
	if has_title:
		scene_selector.add_item("标题界面", TITLE_SCREEN_INDEX)
	
	for i in range(scenes.size()):
		var scene = scenes[i]
		if scene == null:
			continue
		
		var scene_name: String = scene.scene_name if "scene_name" in scene else "Unnamed Scene"
		var scene_id: String = scene.scene_id if "scene_id" in scene else ""
		var display_text: String = scene_name
		if not scene_id.is_empty():
			display_text = "%s (%s)" % [scene_name, scene_id]
		
		scene_selector.add_item(display_text, i)
	
	scene_selector.select(0)


## Handle scene selection change
func _on_scene_selected(index: int) -> void:
	_selected_scene_index = scene_selector.get_item_id(index) if scene_selector else index
	
	# If currently playing, restart with selected target
	if is_playing:
		if scene_runner:
			scene_runner.hide_title_screen()
			scene_runner.stop()
			scene_runner.reset()
			scene_runner.load_project(current_project)
			_connect_variable_manager()
		if _selected_scene_index == TITLE_SCREEN_INDEX:
			if scene_runner:
				scene_runner.show_title_screen()
		else:
			_start_from_scene_index(_selected_scene_index)


# =============================================================================
# Task 11.1: Preview Control
# =============================================================================

## Start the preview
func start_preview() -> void:
	if current_project == null:
		_show_error("No project loaded")
		return
	
	var scenes: Array = current_project.scenes
	if scenes.is_empty():
		_show_error("No scenes in project")
		return
	
	# Clear previous errors
	_clear_errors()
	
	is_playing = true
	_update_ui_state()
	preview_started.emit()
	
	# 根据场景选择器当前选中项决定行为
	var selected_id: int = 0
	if scene_selector and scene_selector.get_selected() >= 0:
		selected_id = scene_selector.get_item_id(scene_selector.get_selected())
	_selected_scene_index = selected_id
	
	if selected_id == TITLE_SCREEN_INDEX:
		# 选中了"标题界面" → 显示标题
		if scene_runner:
			scene_runner.show_title_screen()
	else:
		# 选中了具体场景 → 直接进入
		_start_from_scene_index(selected_id)


## 从指定场景索引开始游戏
func _start_from_scene_index(scene_index: int) -> void:
	if current_project == null:
		return
	var scenes: Array = current_project.scenes
	if scene_index < 0 or scene_index >= scenes.size():
		_show_error("Invalid scene index: %d" % scene_index)
		return
	var target_scene = scenes[scene_index]
	if target_scene == null:
		_show_error("Scene at index %d is null" % scene_index)
		return
	
	# 更新场景选择器 — 需要找到 item id == scene_index 对应的视觉索引
	if scene_selector:
		for i in range(scene_selector.get_item_count()):
			if scene_selector.get_item_id(i) == scene_index:
				scene_selector.select(i)
				break
		_selected_scene_index = scene_index
	
	if scene_runner:
		scene_runner.load_scene(target_scene)
		scene_runner.start()


## 获取有效的初始场景索引（从 title_config.first_scene_id 解析）
func _get_effective_start_index() -> int:
	if current_project == null:
		return 0
	if current_project.title_config != null and current_project.title_config is AVGTitleConfigClass:
		if current_project.title_config.has_method("resolve_first_scene_index"):
			return current_project.title_config.resolve_first_scene_index(current_project)
	return 0


## 标题界面"开始游戏"回调
func _on_title_start_requested(first_scene_index: int) -> void:
	_start_from_scene_index(first_scene_index)


## Stop the preview
func stop_preview() -> void:
	if scene_runner:
		scene_runner.hide_title_screen()
		scene_runner.stop()
		scene_runner.reset()
	
	is_playing = false
	_update_ui_state()
	preview_stopped.emit()


## Handle play button press
func _on_play_pressed() -> void:
	if is_playing:
		return
	start_preview()


## Handle stop button press
func _on_stop_pressed() -> void:
	if not is_playing:
		return
	stop_preview()


## Handle scene started signal
func _on_scene_started(scene_id: String) -> void:
	print("GamePreviewer: Scene started - %s" % scene_id)


## Handle scene ended signal
func _on_scene_ended(scene_id: String) -> void:
	print("GamePreviewer: Scene ended - %s" % scene_id)
	is_playing = false
	_update_ui_state()


## Handle command executed signal
func _on_command_executed(_command_type: String, _command_index: int) -> void:
	# Update debug display if visible
	if debug_panel and debug_panel.visible:
		_update_variable_display()


# =============================================================================
# Task 11.3: Debug Mode
# =============================================================================

## Connect to variable manager for debug display
func _connect_variable_manager() -> void:
	# Disconnect from previous variable manager
	if _variable_manager != null:
		if _variable_manager.is_connected("variable_changed", _on_variable_changed):
			_variable_manager.variable_changed.disconnect(_on_variable_changed)
	
	_variable_manager = null
	
	# Get variable manager from scene runner
	if scene_runner and scene_runner.has_method("get_variable_manager"):
		_variable_manager = scene_runner.get_variable_manager()
		if _variable_manager != null:
			_variable_manager.variable_changed.connect(_on_variable_changed)


## Handle debug toggle
func _on_debug_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_show_debug_panel()
	else:
		_hide_debug_panel()


## Show the debug panel
func _show_debug_panel() -> void:
	if debug_panel:
		debug_panel.visible = true
		_update_variable_display()


## Hide the debug panel
func _hide_debug_panel() -> void:
	if debug_panel:
		debug_panel.visible = false


## Handle variable changed signal
func _on_variable_changed(variable_name: String, _old_value: Variant, new_value: Variant) -> void:
	if not debug_panel or not debug_panel.visible:
		return
	
	_update_single_variable(variable_name, new_value)


## Update the entire variable display
func _update_variable_display() -> void:
	if variable_display == null or _variable_manager == null:
		return
	
	# Clear existing labels
	for child in variable_display.get_children():
		child.queue_free()
	_variable_labels.clear()
	
	# Get all variables
	var var_names: Array = _variable_manager.get_all_variable_names()
	
	if var_names.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No variables defined"
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		variable_display.add_child(empty_label)
		return
	
	# Create labels for each variable
	for var_name in var_names:
		var value: Variant = _variable_manager.get_value(var_name)
		_create_variable_label(var_name, value)


## Create a label for a variable
func _create_variable_label(var_name: String, value: Variant) -> void:
	var label: Label = Label.new()
	label.text = "%s: %s" % [var_name, str(value)]
	label.add_theme_font_size_override("font_size", 12)
	variable_display.add_child(label)
	_variable_labels[var_name] = label


## Update a single variable in the display
func _update_single_variable(var_name: String, value: Variant) -> void:
	if _variable_labels.has(var_name):
		var label: Label = _variable_labels[var_name]
		if is_instance_valid(label):
			label.text = "%s: %s" % [var_name, str(value)]
			# Flash effect to indicate change
			var tween: Tween = create_tween()
			label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
			tween.tween_callback(func(): 
				if is_instance_valid(label):
					label.remove_theme_color_override("font_color")
			).set_delay(0.5)
	else:
		# Variable doesn't exist in display, refresh all
		_update_variable_display()


# =============================================================================
# Task 11.4: Error Handling Display
# =============================================================================

## Show an error message
func _show_error(message: String) -> void:
	_error_messages.append(message)
	_update_error_display()
	
	if error_panel:
		error_panel.visible = true
	
	error_occurred.emit(message)
	push_error("GamePreviewer: %s" % message)


## Clear all errors
func _clear_errors() -> void:
	_error_messages.clear()
	_hide_error_panel()


## Hide the error panel
func _hide_error_panel() -> void:
	if error_panel:
		error_panel.visible = false


## Update the error display
func _update_error_display() -> void:
	if error_label == null:
		return
	
	if _error_messages.is_empty():
		error_label.text = ""
		return
	
	var error_text: String = "[color=red][b]Errors:[/b][/color]\n"
	for i in range(_error_messages.size()):
		error_text += "[color=white]%d. %s[/color]\n" % [i + 1, _error_messages[i]]
	
	error_label.text = error_text


## Handle retry button press - restart from current scene
func _on_retry_pressed() -> void:
	_clear_errors()
	
	if is_playing:
		stop_preview()
	
	start_preview()


## Handle dismiss button press
func _on_dismiss_pressed() -> void:
	_hide_error_panel()


# =============================================================================
# UI State Management
# =============================================================================

## Update UI state based on current state
func _update_ui_state() -> void:
	var has_project: bool = current_project != null
	var has_scenes: bool = has_project and current_project.scenes.size() > 0
	
	if play_button:
		play_button.disabled = not has_scenes or is_playing
	
	if stop_button:
		stop_button.disabled = not is_playing
	
	if scene_selector:
		scene_selector.disabled = not has_scenes or is_playing
	
	if debug_toggle:
		debug_toggle.disabled = not has_project


# =============================================================================
# Public API
# =============================================================================

## Get the current project
func get_project() -> Resource:
	return current_project


## Check if preview is currently playing
func get_is_playing() -> bool:
	return is_playing


## Get the scene runner instance
func get_scene_runner() -> Control:
	return scene_runner


## Handle global project changed from StorageManager
func _on_global_project_changed(project: Resource) -> void:
	print("[GamePreviewer] Global project changed: %s" % (project.project_name if project else "null"))
	set_project(project)
