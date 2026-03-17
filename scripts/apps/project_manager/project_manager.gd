class_name ProjectManager extends Control
## Project Manager Application
## Main interface for managing AVG project resources with sidebar navigation.
## Validates: Task 10.1, 14.2, 14.3, 14.4

# Signals
signal project_changed(project: Resource)
signal project_saved()
signal close_requested()

# Current project being managed
var current_project: Resource = null  # AVGProject

# Dirty flag to track unsaved changes (Task 14.4)
var _is_dirty: bool = false

# Auto-save timer (Task 14.2)
var _auto_save_timer: Timer = null
const AUTO_SAVE_INTERVAL: float = 60.0  # seconds

# Panel references
@onready var category_list: ItemList = %CategoryList
@onready var content_container: Control = %ContentContainer
@onready var character_list_panel: Control = %CharacterListPanel
@onready var event_list_panel: Control = %EventListPanel
@onready var variable_list_panel: Control = %VariableListPanel
@onready var resource_library_panel: Control = %ResourceLibraryPanel
@onready var shared_node_panel: Control = %SharedNodePanel
@onready var dialog_settings_panel: Control = %DialogSettingsPanel
@onready var project_settings_panel: Control = %ProjectSettingsPanel
@onready var title_settings_panel: Control = %TitleSettingsPanel
@onready var game_ui_panel: Control = %GameUIPanel
@onready var screen_settings_panel: Control = %ScreenSettingsPanel
@onready var save_button: Button = %SaveButton

# Dialogs
@onready var unsaved_changes_dialog: ConfirmationDialog = %UnsavedChangesDialog

# Category names
const CATEGORIES: Array[String] = [
	"角色",      # Characters
	"事件",      # Events
	"变量",      # Variables
	"资源库",    # Resources
	"公共节点",  # Shared Nodes
	"对话框",    # Dialog Settings
	"标题界面",  # Title Settings
	"游戏UI",    # Game UI Buttons
	"界面设置",  # Screen Settings
	"设置"       # Settings
]

# Map category index to panel
var _category_panels: Array[Control] = []


func _ready() -> void:
	print("[ProjectManager] _ready() called")
	_setup_categories()
	_setup_panels()
	_setup_connections()
	_setup_auto_save_timer()
	_setup_unsaved_changes_dialog()
	_debug_print_node_refs()
	
	# 监听全局项目变化
	StorageManager.current_project_changed.connect(_on_global_project_changed)
	
	# 如果已有当前项目，加载它
	if StorageManager.current_project != null:
		set_project(StorageManager.current_project)
		print("[ProjectManager] Loaded existing project: %s" % StorageManager.current_project.project_name)
	
	# Select first category by default
	if category_list and category_list.item_count > 0:
		category_list.select(0)
		_on_category_selected(0)
		print("[ProjectManager] Selected first category")


func _setup_categories() -> void:
	print("[ProjectManager] _setup_categories() called")
	if category_list == null:
		print("[ProjectManager] WARNING: category_list is null!")
		return
	
	category_list.clear()
	for category in CATEGORIES:
		category_list.add_item(category)
	print("[ProjectManager] Added %d categories" % CATEGORIES.size())


func _setup_panels() -> void:
	print("[ProjectManager] _setup_panels() called")
	_category_panels = [
		character_list_panel,
		event_list_panel,
		variable_list_panel,
		resource_library_panel,
		shared_node_panel,
		dialog_settings_panel,
		title_settings_panel,
		game_ui_panel,
		screen_settings_panel,
		project_settings_panel
	]
	
	# Hide all panels initially
	for i in range(_category_panels.size()):
		var panel = _category_panels[i]
		if panel:
			panel.visible = false
			print("[ProjectManager] Panel %d hidden: %s" % [i, panel.name])
		else:
			print("[ProjectManager] WARNING: Panel %d is null!" % i)


func _setup_connections() -> void:
	print("[ProjectManager] _setup_connections() called")
	if category_list:
		category_list.item_selected.connect(_on_category_selected)
		print("[ProjectManager] category_list connected")
	
	# Connect character panel signals
	if character_list_panel:
		character_list_panel.character_selected.connect(_on_character_selected)
		if character_list_panel.has_signal("character_added"):
			character_list_panel.character_added.connect(_on_content_changed)
		if character_list_panel.has_signal("character_removed"):
			character_list_panel.character_removed.connect(_on_content_changed)
		print("[ProjectManager] character_list_panel connected")
	
	# Connect event panel signals
	if event_list_panel:
		event_list_panel.event_selected.connect(_on_event_selected)
		print("[ProjectManager] event_list_panel connected")
	
	# Connect variable panel signals
	if variable_list_panel:
		variable_list_panel.variable_selected.connect(_on_variable_selected)
		print("[ProjectManager] variable_list_panel connected")
	
	# Connect shared node panel signals
	if shared_node_panel:
		if shared_node_panel.has_signal("content_changed"):
			shared_node_panel.content_changed.connect(_on_content_changed)
		print("[ProjectManager] shared_node_panel connected")

	# Connect dialog settings panel signals
	if dialog_settings_panel:
		if dialog_settings_panel.has_signal("settings_changed"):
			dialog_settings_panel.settings_changed.connect(_on_content_changed)
		print("[ProjectManager] dialog_settings_panel connected")

	# Connect title settings panel signals
	if title_settings_panel:
		if title_settings_panel.has_signal("settings_changed"):
			title_settings_panel.settings_changed.connect(_on_content_changed)
		print("[ProjectManager] title_settings_panel connected")

	# Connect game UI panel signals
	if game_ui_panel:
		if game_ui_panel.has_signal("settings_changed"):
			game_ui_panel.settings_changed.connect(_on_content_changed)
		print("[ProjectManager] game_ui_panel connected")

	# Connect screen settings panel signals
	if screen_settings_panel:
		if screen_settings_panel.has_signal("settings_changed"):
			screen_settings_panel.settings_changed.connect(_on_content_changed)
		print("[ProjectManager] screen_settings_panel connected")

	# Connect save button
	if save_button:
		save_button.pressed.connect(save_project)
		print("[ProjectManager] save_button connected")


## Debug print all node references
func _debug_print_node_refs() -> void:
	print("[ProjectManager] === Node References ===")
	print("[ProjectManager] category_list: ", category_list)
	print("[ProjectManager] content_container: ", content_container)
	print("[ProjectManager] character_list_panel: ", character_list_panel)
	print("[ProjectManager] event_list_panel: ", event_list_panel)
	print("[ProjectManager] variable_list_panel: ", variable_list_panel)
	print("[ProjectManager] resource_library_panel: ", resource_library_panel)
	print("[ProjectManager] shared_node_panel: ", shared_node_panel)
	print("[ProjectManager] dialog_settings_panel: ", dialog_settings_panel)
	print("[ProjectManager] project_settings_panel: ", project_settings_panel)
	print("[ProjectManager] title_settings_panel: ", title_settings_panel)
	print("[ProjectManager] game_ui_panel: ", game_ui_panel)
	print("[ProjectManager] screen_settings_panel: ", screen_settings_panel)
	print("[ProjectManager] === End Node References ===")


## Setup auto-save timer (Task 14.2)
func _setup_auto_save_timer() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.one_shot = false
	_auto_save_timer.timeout.connect(_on_auto_save_timeout)
	add_child(_auto_save_timer)


## Setup unsaved changes dialog (Task 14.4)
func _setup_unsaved_changes_dialog() -> void:
	# Create dialog if it doesn't exist in scene
	if unsaved_changes_dialog == null:
		unsaved_changes_dialog = ConfirmationDialog.new()
		unsaved_changes_dialog.name = "UnsavedChangesDialog"
		unsaved_changes_dialog.title = "Unsaved Changes"
		unsaved_changes_dialog.dialog_text = "You have unsaved changes. Do you want to save before closing?"
		unsaved_changes_dialog.ok_button_text = "Save"
		unsaved_changes_dialog.cancel_button_text = "Don't Save"
		add_child(unsaved_changes_dialog)
	
	if unsaved_changes_dialog:
		unsaved_changes_dialog.confirmed.connect(_on_unsaved_save_confirmed)
		unsaved_changes_dialog.canceled.connect(_on_unsaved_discard_confirmed)


## Set the project to manage
func set_project(project: Resource) -> void:
	# Auto-save previous project if dirty
	if _is_dirty and current_project != null:
		_perform_auto_save()
	
	current_project = project
	_is_dirty = false
	_refresh_all_panels()
	
	# Start auto-save timer when project is loaded
	if project != null and _auto_save_timer:
		_auto_save_timer.start()
	elif _auto_save_timer:
		_auto_save_timer.stop()
	
	project_changed.emit(project)


## Get the current project
func get_project() -> Resource:
	return current_project


## Refresh all panels with current project data
func _refresh_all_panels() -> void:
	if current_project == null:
		return
	
	if character_list_panel:
		character_list_panel.set_project(current_project)
	if event_list_panel:
		event_list_panel.set_project(current_project)
	if variable_list_panel:
		variable_list_panel.set_project(current_project)
	if resource_library_panel:
		resource_library_panel.set_project(current_project)
	if shared_node_panel:
		shared_node_panel.set_project(current_project)
	if dialog_settings_panel:
		if dialog_settings_panel.has_method("set_project_resolution"):
			dialog_settings_panel.set_project_resolution(Vector2(current_project.resolution))
		if dialog_settings_panel.has_method("set_settings"):
			# 确保 dialog_settings 存在
			if current_project.dialog_settings == null:
				var DialogSettingsClass = load("res://scripts/avg/resources/avg_dialog_settings.gd")
				if DialogSettingsClass:
					current_project.dialog_settings = DialogSettingsClass.new()
					var StyleBoxClass = load("res://scripts/avg/resources/avg_style_box.gd")
					if StyleBoxClass:
						current_project.dialog_settings.box_style = StyleBoxClass.new()
			dialog_settings_panel.set_settings(current_project.dialog_settings)
	if project_settings_panel:
		project_settings_panel.set_project(current_project)
	if title_settings_panel:
		title_settings_panel.set_project(current_project)
	if game_ui_panel:
		game_ui_panel.set_project(current_project)
	if screen_settings_panel:
		screen_settings_panel.set_project(current_project)


## Handle category selection
func _on_category_selected(index: int) -> void:
	# Hide all panels
	for panel in _category_panels:
		if panel:
			panel.visible = false
	
	# Show selected panel
	if index >= 0 and index < _category_panels.size():
		var panel: Control = _category_panels[index]
		if panel:
			panel.visible = true


## Handle character selection
func _on_character_selected(_character: Resource) -> void:
	pass  # Character editing is handled within the panel


## Handle event selection
func _on_event_selected(_event: Resource) -> void:
	pass  # Event editing is handled within the panel


## Handle variable selection
func _on_variable_selected(_variable: Resource) -> void:
	pass  # Variable editing is handled within the panel


## Create a new project
func create_new_project() -> Resource:
	var AVGProjectClass = load("res://scripts/avg/resources/avg_project.gd")
	var new_project: Resource = AVGProjectClass.new()
	new_project.project_name = "New Project"
	set_project(new_project)
	return new_project


## Save the current project (Task 14.2)
func save_project() -> void:
	if current_project == null:
		return
	
	# Get StorageManager autoload
	var storage_manager: Node = get_node_or_null("/root/StorageManager")
	if storage_manager == null:
		push_warning("ProjectManager: StorageManager not found")
		return
	
	# Save project
	var err: Error = storage_manager.save_project(current_project)
	if err == OK:
		print("ProjectManager: Project saved successfully")
		_is_dirty = false
		project_saved.emit()
	else:
		push_error("ProjectManager: Failed to save project, error: %d" % err)


## Perform auto-save (Task 14.2)
func _perform_auto_save() -> void:
	if not _is_dirty or current_project == null:
		return
	
	print("ProjectManager: Auto-saving project...")
	save_project()


## Auto-save timer callback
func _on_auto_save_timeout() -> void:
	_perform_auto_save()


## Mark project as dirty (has unsaved changes)
func _mark_dirty() -> void:
	_is_dirty = true


## Check if project has unsaved changes
func is_dirty() -> bool:
	return _is_dirty


## Handle content changed in panels
func _on_content_changed() -> void:
	_mark_dirty()


## Request close with unsaved changes check (Task 14.4)
func request_close() -> void:
	if _is_dirty:
		if unsaved_changes_dialog:
			unsaved_changes_dialog.popup_centered()
	else:
		close_requested.emit()


## Handle save confirmed in unsaved changes dialog
func _on_unsaved_save_confirmed() -> void:
	save_project()
	close_requested.emit()


## Handle discard confirmed in unsaved changes dialog
func _on_unsaved_discard_confirmed() -> void:
	_is_dirty = false
	close_requested.emit()


## Handle keyboard shortcuts (Task 14.3)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			if event.keycode == KEY_S:
				save_project()
				get_viewport().set_input_as_handled()


## Handle global project changed from StorageManager
func _on_global_project_changed(project: Resource) -> void:
	print("[ProjectManager] Global project changed: %s" % (project.project_name if project else "null"))
	set_project(project)

