class_name CommandParamEditor extends VBoxContainer
## Command Parameter Editor Component
## Generates UI from ParamSchema to edit command params dictionary.
## Validates: Task 9.6

# Signals
signal params_changed(params: Dictionary)

# Current command being edited
var _current_command: Resource = null  # AVGCommand
# Map of param name to control
var _param_controls: Dictionary = {}

# Preload property control scripts
const StringPropertyControlScript = preload("res://scripts/editor/property_controls/string_property.gd")
const NumericPropertyControlScript = preload("res://scripts/editor/property_controls/numeric_property.gd")
const BoolPropertyControlScript = preload("res://scripts/editor/property_controls/bool_property.gd")
const EnumPropertyControlScript = preload("res://scripts/editor/property_controls/enum_property.gd")

# UI References
@onready var title_label: Label = %TitleLabel
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var params_container: VBoxContainer = %ParamsContainer
@onready var no_params_label: Label = %NoParamsLabel


func _ready() -> void:
	pass


## Set the command to edit
func set_command(command: Resource) -> void:
	_current_command = command
	_rebuild_ui()


## Get the current command
func get_command() -> Resource:
	return _current_command


## Clear the editor
func clear() -> void:
	_current_command = null
	_clear_ui()


## Clear all UI controls
func _clear_ui() -> void:
	_param_controls.clear()
	
	if params_container:
		for child in params_container.get_children():
			child.queue_free()
	
	if no_params_label:
		no_params_label.visible = true
	
	if title_label:
		title_label.text = "命令参数"


## Rebuild UI from command schema
func _rebuild_ui() -> void:
	_clear_ui()
	
	if _current_command == null:
		return
	
	if title_label:
		title_label.text = "参数: " + _current_command.command_type
	
	# Get schema from registry
	var registry = CommandRegistry.get_instance()
	var schema = registry.get_schema(_current_command.command_type)
	
	if schema == null or schema.params.size() == 0:
		if no_params_label:
			no_params_label.text = "此命令无参数"
			no_params_label.visible = true
		return
	
	if no_params_label:
		no_params_label.visible = false
	
	# Create controls for each parameter
	for param_def in schema.params:
		var control: Control = _create_param_control(param_def)
		if control and params_container:
			params_container.add_child(control)
			_param_controls[param_def.name] = control


## Create a control for a parameter definition
func _create_param_control(param_def) -> Control:
	var control: Control = null
	var param_type: String = param_def.type if param_def.type is String else str(param_def.type)
	
	match param_type:
		"string", "String":
			control = _create_string_control(param_def)
		"int", "float", "number":
			control = _create_numeric_control(param_def)
		"bool", "boolean":
			control = _create_bool_control(param_def)
		"choices", "enum":
			control = _create_enum_control(param_def)
		_:
			# Default to string
			control = _create_string_control(param_def)
	
	return control


## Create string parameter control
func _create_string_control(param_def) -> Control:
	var control = StringPropertyControlScript.new()
	control.property_name = param_def.name
	control.label_text = param_def.name.capitalize()
	control.description = param_def.description if param_def.has("description") else ""
	
	# Set current value
	var value = _current_command.params.get(param_def.name, param_def.default_value)
	control.set_value(str(value) if value != null else "")
	
	control.value_changed.connect(_on_string_param_changed.bind(param_def.name))
	return control


## Create numeric parameter control
func _create_numeric_control(param_def) -> Control:
	var control = NumericPropertyControlScript.new()
	control.property_name = param_def.name
	control.label_text = param_def.name.capitalize()
	control.is_integer = param_def.type == "int"
	control.description = param_def.description if param_def.has("description") else ""
	
	# Set current value
	var value = _current_command.params.get(param_def.name, param_def.default_value)
	control.set_value(float(value) if value != null else 0.0)
	
	control.value_changed.connect(_on_numeric_param_changed.bind(param_def.name))
	return control


## Create bool parameter control
func _create_bool_control(param_def) -> Control:
	var control = BoolPropertyControlScript.new()
	control.property_name = param_def.name
	control.label_text = param_def.name.capitalize()
	control.description = param_def.description if param_def.has("description") else ""
	
	# Set current value
	var value = _current_command.params.get(param_def.name, param_def.default_value)
	control.set_value(bool(value) if value != null else false)
	
	control.value_changed.connect(_on_bool_param_changed.bind(param_def.name))
	return control


## Create enum parameter control
func _create_enum_control(param_def) -> Control:
	var control = EnumPropertyControlScript.new()
	control.property_name = param_def.name
	control.label_text = param_def.name.capitalize()
	control.options = param_def.options if param_def.has("options") else []
	control.description = param_def.description if param_def.has("description") else ""
	
	# Set current value
	var value = _current_command.params.get(param_def.name, param_def.default_value)
	control.set_value(str(value) if value != null else "")
	
	control.value_changed.connect(_on_enum_param_changed.bind(param_def.name))
	return control


## Handle string parameter change
func _on_string_param_changed(value: String, param_name: String) -> void:
	_apply_param_change(param_name, value)


## Handle numeric parameter change
func _on_numeric_param_changed(value: float, param_name: String) -> void:
	_apply_param_change(param_name, value)


## Handle bool parameter change
func _on_bool_param_changed(value: bool, param_name: String) -> void:
	_apply_param_change(param_name, value)


## Handle enum parameter change
func _on_enum_param_changed(value: String, param_name: String) -> void:
	_apply_param_change(param_name, value)


## Apply parameter change to command
func _apply_param_change(param_name: String, value: Variant) -> void:
	if _current_command == null:
		return
	
	_current_command.params[param_name] = value
	params_changed.emit(_current_command.params)
