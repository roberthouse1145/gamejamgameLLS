class_name FileManager extends Control
## File Manager Application
## Manages project files: list projects, import resources, export projects.
## Validates: Task 12.1-12.5

# Signals
signal project_opened(project: Resource)
signal project_created(project: Resource)

# Current project being managed
var current_project: Resource = null  # AVGProject

# Node references
@onready var user_project_list: ItemList = %UserProjectList
@onready var template_list: ItemList = %TemplateList
@onready var open_button: Button = %OpenButton
@onready var delete_button: Button = %DeleteButton
@onready var new_from_template_button: Button = %NewFromTemplateButton
@onready var import_button: Button = %ImportButton
@onready var export_button: Button = %ExportButton
@onready var new_project_dialog: ConfirmationDialog = %NewProjectDialog
@onready var new_project_name_edit: LineEdit = %NewProjectNameEdit
@onready var delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog
@onready var import_file_dialog: FileDialog = %ImportFileDialog
@onready var export_folder_dialog: FileDialog = %ExportFolderDialog
@onready var status_label: Label = %StatusLabel

# Currently selected template for copying
var _selected_template: String = ""
# Currently selected user project for deletion
var _selected_user_project: String = ""


func _ready() -> void:
	print("[FileManager] _ready() called")
	_setup_connections()
	_setup_dialogs()
	_refresh_project_lists()
	_update_button_states()
	print("[FileManager] Initialization complete")
	print("[FileManager] user_project_list: ", user_project_list)
	print("[FileManager] template_list: ", template_list)
	print("[FileManager] open_button: ", open_button)
	print("[FileManager] new_from_template_button: ", new_from_template_button)


func _setup_connections() -> void:
	# List selection signals
	if user_project_list:
		user_project_list.item_selected.connect(_on_user_project_selected)
		user_project_list.item_activated.connect(_on_user_project_activated)
	
	if template_list:
		template_list.item_selected.connect(_on_template_selected)
		template_list.item_activated.connect(_on_template_activated)

	# Button signals
	if open_button:
		open_button.pressed.connect(_on_open_pressed)
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if new_from_template_button:
		new_from_template_button.pressed.connect(_on_new_from_template_pressed)
	if import_button:
		import_button.pressed.connect(_on_import_pressed)
	if export_button:
		export_button.pressed.connect(_on_export_pressed)
	
	# Dialog signals
	if new_project_dialog:
		new_project_dialog.confirmed.connect(_on_new_project_confirmed)
	if delete_confirm_dialog:
		delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	if import_file_dialog:
		import_file_dialog.files_selected.connect(_on_import_files_selected)
	if export_folder_dialog:
		export_folder_dialog.dir_selected.connect(_on_export_folder_selected)


func _setup_dialogs() -> void:
	# Setup import file dialog
	if import_file_dialog:
		import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		import_file_dialog.filters = PackedStringArray([
			"*.png, *.jpg, *.jpeg, *.webp ; Images",
			"*.ogg, *.mp3, *.wav ; Audio",
			"*.tres ; Resources"
		])
	
	# Setup export folder dialog
	if export_folder_dialog:
		export_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		export_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM


## Refresh both project lists
func _refresh_project_lists() -> void:
	_refresh_user_projects()
	_refresh_templates()


## Refresh user projects list
func _refresh_user_projects() -> void:
	print("[FileManager] _refresh_user_projects() called")
	if user_project_list == null:
		print("[FileManager] ERROR: user_project_list is null!")
		return
	
	user_project_list.clear()
	var projects: Array[String] = StorageManager.list_user_projects()
	print("[FileManager] Found user projects: ", projects)
	for project_name in projects:
		user_project_list.add_item(project_name)
	
	_update_status("Found %d user projects" % projects.size())


## Refresh templates list
func _refresh_templates() -> void:
	print("[FileManager] _refresh_templates() called")
	if template_list == null:
		print("[FileManager] ERROR: template_list is null!")
		return
	
	template_list.clear()
	var templates: Array[String] = StorageManager.list_template_projects()
	print("[FileManager] Found templates: ", templates)
	for template_name in templates:
		template_list.add_item(template_name)


## Update button enabled states based on selection
func _update_button_states() -> void:
	var user_selected: bool = user_project_list != null and user_project_list.get_selected_items().size() > 0
	var template_selected: bool = template_list != null and template_list.get_selected_items().size() > 0
	var has_project: bool = current_project != null
	
	if open_button:
		open_button.disabled = not user_selected
	if delete_button:
		delete_button.disabled = not user_selected
	if new_from_template_button:
		new_from_template_button.disabled = not template_selected
	if import_button:
		import_button.disabled = not has_project
	if export_button:
		export_button.disabled = not has_project


## Update status label
func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message


## Set the current project
func set_project(project: Resource) -> void:
	current_project = project
	_update_button_states()
	if project:
		_update_status("Current project: %s" % project.project_name)


## Get the current project
func get_project() -> Resource:
	return current_project


## Validate project name
func _is_valid_project_name(project_name_str: String) -> bool:
	if project_name_str.is_empty():
		return false
	var regex: RegEx = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	return regex.search(project_name_str) != null


# ============ User Project List Handlers ============

func _on_user_project_selected(_index: int) -> void:
	# Deselect template list
	if template_list:
		template_list.deselect_all()
	_update_button_states()


func _on_user_project_activated(_index: int) -> void:
	# Double-click to open
	_open_selected_project()


func _open_selected_project() -> void:
	if user_project_list == null:
		return
	
	var selected: PackedInt32Array = user_project_list.get_selected_items()
	if selected.size() == 0:
		return
	
	var project_name: String = user_project_list.get_item_text(selected[0])
	var project_path: String = StorageManager.USER_PROJECTS_PATH + project_name + "/"
	
	var project: Resource = StorageManager.load_project(project_path)
	if project:
		current_project = project
		_update_status("Opened project: %s" % project_name)
		_update_button_states()
		# 设置全局当前项目
		StorageManager.set_current_project(project)
		project_opened.emit(project)
	else:
		_update_status("Failed to open project: %s" % project_name)


# ============ Template List Handlers ============

func _on_template_selected(_index: int) -> void:
	# Deselect user project list
	if user_project_list:
		user_project_list.deselect_all()
	_update_button_states()


func _on_template_activated(_index: int) -> void:
	# Double-click to create from template
	_on_new_from_template_pressed()


# ============ Button Handlers ============

func _on_open_pressed() -> void:
	_open_selected_project()


func _on_delete_pressed() -> void:
	if user_project_list == null:
		return
	
	var selected: PackedInt32Array = user_project_list.get_selected_items()
	if selected.size() == 0:
		return
	
	_selected_user_project = user_project_list.get_item_text(selected[0])
	
	if delete_confirm_dialog:
		delete_confirm_dialog.dialog_text = "Are you sure you want to delete project '%s'?\nThis action cannot be undone." % _selected_user_project
		delete_confirm_dialog.popup_centered()


func _on_new_from_template_pressed() -> void:
	print("[FileManager] _on_new_from_template_pressed() called")
	if template_list == null:
		print("[FileManager] ERROR: template_list is null!")
		return
	
	var selected: PackedInt32Array = template_list.get_selected_items()
	print("[FileManager] Selected items: ", selected)
	if selected.size() == 0:
		print("[FileManager] No template selected")
		return
	
	_selected_template = template_list.get_item_text(selected[0])
	print("[FileManager] Selected template: ", _selected_template)
	
	if new_project_dialog and new_project_name_edit:
		new_project_name_edit.text = _selected_template + "_copy"
		new_project_dialog.popup_centered()
		new_project_name_edit.grab_focus()
		new_project_name_edit.select_all()
	else:
		print("[FileManager] ERROR: new_project_dialog or new_project_name_edit is null!")


func _on_import_pressed() -> void:
	if import_file_dialog:
		import_file_dialog.popup_centered_ratio(0.7)


func _on_export_pressed() -> void:
	if export_folder_dialog:
		export_folder_dialog.popup_centered_ratio(0.7)


# ============ Dialog Handlers ============

func _on_new_project_confirmed() -> void:
	if new_project_name_edit == null or _selected_template.is_empty():
		return
	
	var new_name: String = new_project_name_edit.text.strip_edges()
	if new_name.is_empty():
		_update_status("Project name cannot be empty")
		return
	
	# Validate project name (no special characters)
	if not _is_valid_project_name(new_name):
		_update_status("Invalid project name. Use only letters, numbers, and underscores.")
		return
	
	# Copy template to user projects
	var err: Error = StorageManager.copy_template_to_user(_selected_template, new_name)
	if err == OK:
		_update_status("Created project '%s' from template '%s'" % [new_name, _selected_template])
		_refresh_user_projects()
		
		# Load and emit the new project
		var project_path: String = StorageManager.USER_PROJECTS_PATH + new_name + "/"
		var project: Resource = StorageManager.load_project(project_path)
		if project:
			current_project = project
			_update_button_states()
			# 设置全局当前项目
			StorageManager.set_current_project(project)
			project_created.emit(project)
	elif err == ERR_ALREADY_EXISTS:
		_update_status("Project '%s' already exists" % new_name)
	else:
		_update_status("Failed to create project: error %d" % err)
	
	_selected_template = ""


func _on_delete_confirmed() -> void:
	if _selected_user_project.is_empty():
		return
	
	var project_path: String = StorageManager.USER_PROJECTS_PATH + _selected_user_project
	var err: Error = StorageManager._remove_directory_recursive(project_path + "/")
	
	if err == OK:
		# Also remove the directory itself
		DirAccess.remove_absolute(project_path)
		_update_status("Deleted project: %s" % _selected_user_project)
		_refresh_user_projects()
		
		# Clear current project if it was the deleted one
		if current_project and current_project.project_name == _selected_user_project:
			current_project = null
			_update_button_states()
	else:
		_update_status("Failed to delete project: %s" % _selected_user_project)
	
	_selected_user_project = ""


func _on_import_files_selected(paths: PackedStringArray) -> void:
	if current_project == null:
		_update_status("No project selected for import")
		return
	
	var imported_count: int = 0
	var project_path: String = StorageManager.get_save_path(current_project)
	
	for source_path in paths:
		var file_name: String = source_path.get_file()
		var extension: String = source_path.get_extension().to_lower()
		
		# Determine target folder based on file type
		var target_folder: String = ""
		if extension in ["png", "jpg", "jpeg", "webp"]:
			target_folder = "assets/images/"
		elif extension in ["ogg", "mp3", "wav"]:
			target_folder = "assets/audio/"
		elif extension == "tres":
			target_folder = "resources/"
		else:
			continue  # Skip unsupported files
		
		var target_path: String = project_path + target_folder + file_name
		
		# Ensure target directory exists
		var target_dir: String = project_path + target_folder
		if not DirAccess.dir_exists_absolute(target_dir):
			DirAccess.make_dir_recursive_absolute(target_dir)
		
		# Copy file
		var err: Error = StorageManager._copy_file_binary(source_path, target_path)
		if err == OK:
			imported_count += 1
	
	_update_status("Imported %d files to project" % imported_count)


func _on_export_folder_selected(dir_path: String) -> void:
	if current_project == null:
		_update_status("No project to export")
		return
	
	var export_result: Error = _export_project(dir_path)
	if export_result == OK:
		_update_status("Project exported to: %s" % dir_path)
	else:
		_update_status("Export failed with error: %d" % export_result)


# ============ Export Implementation ============

## Export project to standalone folder
func _export_project(export_path: String) -> Error:
	if current_project == null:
		return ERR_INVALID_DATA
	
	# Ensure export path ends with /
	if not export_path.ends_with("/"):
		export_path += "/"
	
	var project_export_path: String = export_path + current_project.project_name + "/"
	
	# Create export directory
	if not DirAccess.dir_exists_absolute(project_export_path):
		var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(project_export_path)
		if mkdir_err != OK:
			return mkdir_err
	
	# Copy project files
	var source_path: String = StorageManager.get_save_path(current_project)
	var copy_err: Error = StorageManager._copy_directory_recursive(source_path, project_export_path)
	if copy_err != OK:
		return copy_err
	
	# Generate basic project.godot
	var project_godot_err: Error = _generate_project_godot(project_export_path)
	if project_godot_err != OK:
		push_warning("Failed to generate project.godot")
	
	# Copy AVG runtime library files
	var runtime_err: Error = _copy_runtime_files(project_export_path)
	if runtime_err != OK:
		push_warning("Failed to copy runtime files")
	
	return OK


## Generate a basic project.godot file for the exported project
func _generate_project_godot(export_path: String) -> Error:
	var project_name: String = current_project.project_name if current_project else "Exported Project"
	var resolution: Vector2i = current_project.resolution if current_project else Vector2i(2560, 1440)
	
	var content: String = """config_version=5

[application]
config/name="%s"
config/features=PackedStringArray("4.2", "Forward Plus")

[display]
window/size/viewport_width=%d
window/size/viewport_height=%d
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[rendering]
renderer/rendering_method="forward_plus"
""" % [project_name, resolution.x, resolution.y]
	
	var file: FileAccess = FileAccess.open(export_path + "project.godot", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(content)
	file.close()
	
	return OK


## Copy AVG runtime library files to export folder
func _copy_runtime_files(export_path: String) -> Error:
	# Create runtime directory structure
	var runtime_dirs: Array[String] = [
		"scripts/avg/runtime/",
		"scripts/avg/resources/",
		"scripts/avg/commands/",
		"scripts/avg/commands/handlers/",
		"scenes/avg/"
	]
	
	for dir in runtime_dirs:
		var full_path: String = export_path + dir
		if not DirAccess.dir_exists_absolute(full_path):
			var err: Error = DirAccess.make_dir_recursive_absolute(full_path)
			if err != OK:
				return err
	
	# List of runtime files to copy
	var runtime_files: Array[String] = [
		"scripts/avg/runtime/avg_scene_runner.gd",
		"scripts/avg/runtime/avg_audio_manager.gd",
		"scripts/avg/runtime/character_display.gd",
		"scripts/avg/runtime/dialog_box.gd",
		"scripts/avg/runtime/command_context.gd",
		"scripts/avg/runtime/variable_manager.gd",
		"scripts/avg/resources/avg_project.gd",
		"scripts/avg/resources/avg_scene.gd",
		"scripts/avg/resources/avg_character.gd",
		"scripts/avg/resources/avg_variable.gd",
		"scripts/avg/resources/avg_command.gd",
		"scripts/avg/resources/avg_scene_node.gd",
		"scripts/avg/commands/command_handler.gd",
		"scripts/avg/commands/command_registry.gd",
		"scripts/avg/commands/param_definition.gd"
	]
	
	# Copy each runtime file
	for file_path in runtime_files:
		var source: String = "res://" + file_path
		var target: String = export_path + file_path
		
		if FileAccess.file_exists(source):
			var err: Error = StorageManager._copy_file(source, target)
			if err != OK:
				push_warning("Failed to copy runtime file: %s" % file_path)
	
	return OK
