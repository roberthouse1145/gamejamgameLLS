class_name BoolProperty extends HBoxContainer
## Bool Property Control
## CheckBox for boolean values.
## Validates: Task 8.4

# Signals
signal value_changed(new_value: bool)

# Configuration
@export var property_name: String = ""
@export var label_text: String = ""
@export var description: String = ""

# Internal controls
var _label: Label
var _check_box: CheckBox
var _current_value: bool = false
var _editable: bool = true


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create label
	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size.x = 100
	if description != "":
		_label.tooltip_text = description
	add_child(_label)
	
	# Create check box
	_check_box = CheckBox.new()
	_check_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check_box.button_pressed = _current_value
	_check_box.disabled = not _editable
	_check_box.toggled.connect(_on_toggled)
	add_child(_check_box)


func _on_toggled(pressed: bool) -> void:
	if pressed != _current_value:
		_current_value = pressed
		value_changed.emit(_current_value)


## Set the current value
func set_value(value: Variant) -> void:
	_current_value = bool(value) if value != null else false
	
	if _check_box != null:
		_check_box.button_pressed = _current_value


## Get the current value
func get_value() -> bool:
	return _current_value


## Set whether the control is editable
func set_editable(editable: bool) -> void:
	_editable = editable
	if _check_box != null:
		_check_box.disabled = not _editable


## Check if the control is editable
func is_editable() -> bool:
	return _editable
