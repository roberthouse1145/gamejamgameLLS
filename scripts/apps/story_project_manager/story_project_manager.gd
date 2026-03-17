class_name StoryProjectManager extends Control

signal project_changed(project: Resource)
signal project_saved()
signal close_requested()

const CATEGORIES: Array[String] = [
	"场景",
	"角色",
	"资源",
	"对话框",
	"标题界面",
	"界面设置",
	"项目设置",
]

const AUTO_SAVE_INTERVAL: float = 60.0

var current_project: Resource = null
var _is_dirty: bool = false
var _auto_save_timer: Timer = null
var _category_panels: Array[Control] = []

@onready var title_label: Label = %TitleLabel
@onready var category_list: ItemList = %CategoryList
@onready var save_button: Button = %SaveButton
@onready var scene_list_panel: Control = %SceneListPanel
@onready var character_list_panel: Control = %CharacterListPanel
@onready var resource_library_panel: Control = %ResourceLibraryPanel
@onready var dialog_settings_panel: Control = %DialogSettingsPanel
@onready var title_settings_panel: Control = %TitleSettingsPanel
@onready var screen_settings_panel: Control = %ScreenSettingsPanel
@onready var project_settings_panel: Control = %ProjectSettingsPanel
@onready var unsaved_changes_dialog: ConfirmationDialog = %UnsavedChangesDialog


func _ready() -> void:
	_setup_categories()
	_setup_panels()
	_setup_connections()
	_setup_auto_save_timer()
	_setup_unsaved_changes_dialog()

	if title_label != null:
		title_label.text = "剧情工程管理器"

	if not NarrativeProjectManager.current_project_changed.is_connected(_on_global_project_changed):
		NarrativeProjectManager.current_project_changed.connect(_on_global_project_changed)

	if NarrativeProjectManager.current_project != null:
		set_project(NarrativeProjectManager.current_project)

	if category_list != null and category_list.item_count > 0:
		category_list.select(0)
		_on_category_selected(0)


func _setup_categories() -> void:
	if category_list == null:
		return
	category_list.clear()
	for category in CATEGORIES:
		category_list.add_item(category)


func _setup_panels() -> void:
	_category_panels = [
		scene_list_panel,
		character_list_panel,
		resource_library_panel,
		dialog_settings_panel,
		title_settings_panel,
		screen_settings_panel,
		project_settings_panel,
	]
	for panel in _category_panels:
		if panel != null:
			panel.visible = false


func _setup_connections() -> void:
	if category_list != null:
		category_list.item_selected.connect(_on_category_selected)
	if save_button != null:
		save_button.pressed.connect(save_project)
	if scene_list_panel != null and scene_list_panel.has_signal("scene_selected"):
		scene_list_panel.scene_selected.connect(func(_scene: Resource) -> void: _mark_dirty())
	if character_list_panel != null and character_list_panel.has_signal("character_selected"):
		character_list_panel.character_selected.connect(func(_character: Resource) -> void: _mark_dirty())
	if dialog_settings_panel != null and dialog_settings_panel.has_signal("settings_changed"):
		dialog_settings_panel.settings_changed.connect(_on_content_changed)
	if title_settings_panel != null and title_settings_panel.has_signal("settings_changed"):
		title_settings_panel.settings_changed.connect(_on_content_changed)
	if screen_settings_panel != null and screen_settings_panel.has_signal("settings_changed"):
		screen_settings_panel.settings_changed.connect(_on_content_changed)
	if project_settings_panel != null and project_settings_panel.has_signal("settings_changed"):
		project_settings_panel.settings_changed.connect(_on_content_changed)


func _setup_auto_save_timer() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.one_shot = false
	_auto_save_timer.timeout.connect(_on_auto_save_timeout)
	add_child(_auto_save_timer)


func _setup_unsaved_changes_dialog() -> void:
	if unsaved_changes_dialog == null:
		return
	unsaved_changes_dialog.confirmed.connect(_on_unsaved_save_confirmed)
	unsaved_changes_dialog.canceled.connect(_on_unsaved_discard_confirmed)


func set_project(project: Resource) -> void:
	current_project = project
	_is_dirty = false
	_refresh_all_panels()
	if current_project != null:
		_auto_save_timer.start()
	elif _auto_save_timer != null:
		_auto_save_timer.stop()
	project_changed.emit(project)


func save_project() -> void:
	if current_project == null:
		return
	var err: Error = NarrativeProjectManager.save_project(current_project)
	if err == OK:
		_is_dirty = false
		project_saved.emit()
		print("[StoryProjectManager] Narrative project saved")
	else:
		push_error("[StoryProjectManager] Failed to save narrative project, error: %d" % err)


func request_close() -> void:
	if _is_dirty and unsaved_changes_dialog != null:
		unsaved_changes_dialog.popup_centered()
		return
	close_requested.emit()


func _refresh_all_panels() -> void:
	if current_project == null:
		return
	var project_root: String = ""
	if "project_root_path" in current_project:
		project_root = str(current_project.get("project_root_path"))

	if scene_list_panel != null:
		scene_list_panel.set_project(current_project)
	if character_list_panel != null:
		character_list_panel.set_project(current_project)
		if character_list_panel.has_method("set_project_root"):
			character_list_panel.set_project_root(project_root)
	if resource_library_panel != null:
		resource_library_panel.set_project(current_project)
		if resource_library_panel.has_method("set_project_root"):
			resource_library_panel.set_project_root(project_root)
	if dialog_settings_panel != null:
		if dialog_settings_panel.has_method("set_project_resolution"):
			dialog_settings_panel.set_project_resolution(Vector2(current_project.resolution))
		if dialog_settings_panel.has_method("set_settings"):
			dialog_settings_panel.set_settings(current_project.dialog_settings)
	if title_settings_panel != null:
		title_settings_panel.set_project(current_project)
	if screen_settings_panel != null:
		screen_settings_panel.set_project(current_project)
	if project_settings_panel != null:
		project_settings_panel.set_project(current_project)


func _on_category_selected(index: int) -> void:
	for panel in _category_panels:
		if panel != null:
			panel.visible = false
	if index >= 0 and index < _category_panels.size():
		var panel: Control = _category_panels[index]
		if panel != null:
			panel.visible = true


func _mark_dirty() -> void:
	_is_dirty = true


func _on_content_changed() -> void:
	_mark_dirty()


func _on_auto_save_timeout() -> void:
	if _is_dirty:
		save_project()


func _on_unsaved_save_confirmed() -> void:
	save_project()
	close_requested.emit()


func _on_unsaved_discard_confirmed() -> void:
	_is_dirty = false
	close_requested.emit()


func _on_global_project_changed(project: Resource) -> void:
	set_project(project)
