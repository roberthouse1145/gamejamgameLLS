class_name NumericProperty extends HBoxContainer
## Numeric Property Control
## SpinBox for int/float values with min/max range support.
## Validates: Task 8.3

# Signals
signal value_changed(new_value: float)

# Configuration
@export var property_name: String = ""
@export var label_text: String = ""
@export var is_integer: bool = false
@export var min_value: float = -999999
@export var max_value: float = 999999
@export var step: float = 1.0
@export var description: String = ""

# Internal controls
var _label: Label
var _spin_box: SpinBox
var _current_value: float = 0.0
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
	
	# Create spin box
	_spin_box = SpinBox.new()
	_spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_box.min_value = min_value
	_spin_box.max_value = max_value
	_spin_box.step = step if not is_integer else 1.0
	_spin_box.rounded = is_integer
	_spin_box.value = _current_value
	_spin_box.editable = _editable
	_spin_box.value_changed.connect(_on_value_changed)
	add_child(_spin_box)


func _on_value_changed(new_value: float) -> void:
	var final_value: float
	if is_integer:
		final_value = float(int(new_value))
	else:
		final_value = new_value
	if final_value != _current_value:
		_current_value = final_value
		value_changed.emit(_current_value)


## Set the current value
func set_value(value: Variant) -> void:
	if value == null:
		_current_value = 0.0
	elif is_integer:
		_current_value = float(int(value))
	else:
		_current_value = float(value)
	
	if _spin_box != null:
		_spin_box.value = _current_value


## Get the current value
func get_value() -> float:
	return _current_value


## Get the current value as int (if is_integer)
func get_int_value() -> int:
	return int(_current_value)


## Set whether the control is editable
func set_editable(editable: bool) -> void:
	_editable = editable
	if _spin_box != null:
		_spin_box.editable = _editable


## Check if the control is editable
func is_editable() -> bool:
	return _editable
