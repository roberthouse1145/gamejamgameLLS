class_name ProjectSettingsPanel extends VBoxContainer
## Project Settings Panel — 编辑项目基本设置（名称、分辨率等）

signal settings_changed()

var _project: Resource = null  # AVGProject

@onready var property_editor: Control = %PropertyEditor
@onready var save_button: Button = %SaveButton
@onready var project_name_label: Label = %ProjectNameLabel


func _ready() -> void:
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if property_editor and property_editor.has_signal("property_changed"):
		property_editor.property_changed.connect(_on_property_changed)


func set_project(project: Resource) -> void:
	_project = project
	_refresh_ui()


func get_project() -> Resource:
	return _project


func _refresh_ui() -> void:
	if _project == null:
		if project_name_label:
			project_name_label.text = "未加载项目"
		if property_editor and property_editor.has_method("set_target"):
			property_editor.set_target(null)
		return

	if project_name_label:
		project_name_label.text = "项目: " + _project.project_name
	if property_editor and property_editor.has_method("set_target"):
		property_editor.set_target(_project)


func _on_property_changed(property_name: String, _old_value: Variant, _new_value: Variant) -> void:
	if property_name == "project_name" and project_name_label and _project:
		project_name_label.text = "项目: " + _project.project_name
	settings_changed.emit()


func _on_save_pressed() -> void:
	if _project == null:
		return
	settings_changed.emit()
