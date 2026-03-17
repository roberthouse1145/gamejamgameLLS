class_name SceneListPanel extends VBoxContainer
## Scene List Panel Component
## Displays all scenes in project using ItemList with add/delete/open functionality.
## Validates: Task 10.2

# Signals
signal scene_open_requested(scene: Resource)
signal scene_selected(scene: Resource)

# Current project reference
var _project: Resource = null  # AVGProject
# Currently selected scene index
var _selected_index: int = -1

# Preload AVGScene
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")

# UI References
@onready var toolbar: HBoxContainer = %Toolbar
@onready var add_button: Button = %AddButton
@onready var delete_button: Button = %DeleteButton
@onready var open_button: Button = %OpenButton
@onready var scene_list: ItemList = %SceneList
@onready var scene_name_input: LineEdit = %SceneNameInput


func _ready() -> void:
	_setup_toolbar()
	_setup_list()


func _setup_toolbar() -> void:
	if add_button:
		add_button.pressed.connect(_on_add_pressed)
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if open_button:
		open_button.pressed.connect(_on_open_pressed)


func _setup_list() -> void:
	if scene_list:
		scene_list.item_selected.connect(_on_item_selected)
		scene_list.item_activated.connect(_on_item_activated)


## Set the project to display scenes from
func set_project(project: Resource) -> void:
	_project = project
	_selected_index = -1
	_refresh_list()


## Get the current project
func get_project() -> Resource:
	return _project


## Get the selected scene
func get_selected_scene() -> Resource:
	if _project == null or _selected_index < 0:
		return null
	if _selected_index >= _project.scenes.size():
		return null
	return _project.scenes[_selected_index]


## Refresh the scene list display
func _refresh_list() -> void:
	if scene_list == null:
		return
	
	scene_list.clear()
	
	if _project == null:
		_update_button_states()
		return
	
	for scene in _project.scenes:
		var display_text: String = scene.scene_name
		if scene.scene_id != "":
			display_text = "%s (%s)" % [scene.scene_name, scene.scene_id]
		scene_list.add_item(display_text)
	
	# Restore selection
	if _selected_index >= 0 and _selected_index < _project.scenes.size():
		scene_list.select(_selected_index)
	
	_update_button_states()


## Update button enabled states
func _update_button_states() -> void:
	var has_selection: bool = _selected_index >= 0
	var has_project: bool = _project != null
	
	if add_button:
		add_button.disabled = not has_project
	if delete_button:
		delete_button.disabled = not has_selection
	if open_button:
		open_button.disabled = not has_selection


## Handle item selection
func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_button_states()
	
	var scene: Resource = get_selected_scene()
	if scene:
		scene_selected.emit(scene)


## Handle item double-click (activate)
func _on_item_activated(index: int) -> void:
	_selected_index = index
	var scene: Resource = get_selected_scene()
	if scene:
		scene_open_requested.emit(scene)


## Handle add button
func _on_add_pressed() -> void:
	if _project == null:
		return
	
	var scene_name: String = "New Scene"
	if scene_name_input and scene_name_input.text != "":
		scene_name = scene_name_input.text
	
	var new_scene: Resource = AVGSceneClass.new()
	new_scene.scene_id = AVGSceneClass.next_available_id(_project.scenes)
	new_scene.scene_name = scene_name
	
	_project.scenes.append(new_scene)
	_refresh_list()
	
	# Select the new scene
	_selected_index = _project.scenes.size() - 1
	if scene_list:
		scene_list.select(_selected_index)
	
	scene_selected.emit(new_scene)
	
	# Clear input
	if scene_name_input:
		scene_name_input.text = ""


## Handle delete button
func _on_delete_pressed() -> void:
	if _project == null or _selected_index < 0:
		return
	if _selected_index >= _project.scenes.size():
		return
	
	_project.scenes.remove_at(_selected_index)
	
	# Adjust selection
	if _selected_index >= _project.scenes.size():
		_selected_index = _project.scenes.size() - 1
	
	_refresh_list()


## Handle open button
func _on_open_pressed() -> void:
	var scene: Resource = get_selected_scene()
	if scene:
		scene_open_requested.emit(scene)

