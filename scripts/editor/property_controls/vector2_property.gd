class_name Vector2Property extends VBoxContainer
## Vector2 Property Control
## HBoxContainer with X and Y SpinBox controls.
## Validates: Task 8.5

# Signals
signal value_changed(new_value: Vector2)

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
var _x_spin: SpinBox
var _y_spin: SpinBox
var _current_value: Vector2 = Vector2.ZERO
var _editable: bool = true
var _updating: bool = false


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create label
	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	if description != "":
		_label.tooltip_text = description
	add_child(_label)
	
	# Create horizontal container for X and Y
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hbox)
	
	# X label and spin box
	var x_label := Label.new()
	x_label.text = "X:"
	x_label.custom_minimum_size.x = 20
	hbox.add_child(x_label)
	
	_x_spin = SpinBox.new()
	_x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_x_spin.min_value = min_value
	_x_spin.max_value = max_value
	_x_spin.step = step if not is_integer else 1.0
	_x_spin.rounded = is_integer
	_x_spin.value = _current_value.x
	_x_spin.editable = _editable
	_x_spin.value_changed.connect(_on_x_changed)
	hbox.add_child(_x_spin)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 10
	hbox.add_child(spacer)
	
	# Y label and spin box
	var y_label := Label.new()
	y_label.text = "Y:"
	y_label.custom_minimum_size.x = 20
	hbox.add_child(y_label)
	
	_y_spin = SpinBox.new()
	_y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_y_spin.min_value = min_value
	_y_spin.max_value = max_value
	_y_spin.step = step if not is_integer else 1.0
	_y_spin.rounded = is_integer
	_y_spin.value = _current_value.y
	_y_spin.editable = _editable
	_y_spin.value_changed.connect(_on_y_changed)
	hbox.add_child(_y_spin)


func _on_x_changed(new_value: float) -> void:
	if _updating:
		return

	var x: float
	if is_integer:
		x = float(int(new_value))
	else:
		x = new_value
	if x != _current_value.x:
		_current_value.x = x
		value_changed.emit(_current_value)


func _on_y_changed(new_value: float) -> void:
	if _updating:
		return

	var y: float
	if is_integer:
		y = float(int(new_value))
	else:
		y = new_value
	if y != _current_value.y:
		_current_value.y = y
		value_changed.emit(_current_value)


## Set the current value
func set_value(value: Variant) -> void:
	_updating = true

	if value == null:
		_current_value = Vector2.ZERO
	elif value is Vector2:
		_current_value = value
	elif value is Vector2i:
		_current_value = Vector2(value)
	else:
		_current_value = Vector2.ZERO

	if _x_spin != null:
		_x_spin.value = _current_value.x
	if _y_spin != null:
		_y_spin.value = _current_value.y

	_updating = false


## Get the current value
func get_value() -> Vector2:
	return _current_value


## Get the current value as Vector2i (if is_integer)
func get_int_value() -> Vector2i:
	return Vector2i(_current_value)


## Set whether the control is editable
func set_editable(editable: bool) -> void:
	_editable = editable
	if _x_spin != null:
		_x_spin.editable = _editable
	if _y_spin != null:
		_y_spin.editable = _editable


## Check if the control is editable
func is_editable() -> bool:
	return _editable
