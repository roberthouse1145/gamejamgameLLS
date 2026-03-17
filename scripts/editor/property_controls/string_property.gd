class_name StringProperty extends VBoxContainer
## String Property Control
## LineEdit for single line strings, TextEdit for multiline.
## Validates: Task 8.2

# Signals
signal value_changed(new_value: String)

# Configuration
@export var property_name: String = ""
@export var label_text: String = ""
@export var multiline: bool = false
@export var description: String = ""
@export var placeholder: String = ""

# Internal controls
var _label: Label
var _line_edit: LineEdit
var _text_edit: TextEdit
var _current_value: String = ""
var _editable: bool = true


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
	
	# Create appropriate input control
	if multiline:
		_create_text_edit()
	else:
		_create_line_edit()


func _create_line_edit() -> void:
	_line_edit = LineEdit.new()
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.placeholder_text = placeholder
	_line_edit.text = _current_value
	_line_edit.editable = _editable
	_line_edit.text_changed.connect(_on_text_changed)
	_line_edit.text_submitted.connect(_on_text_submitted)
	add_child(_line_edit)


func _create_text_edit() -> void:
	_text_edit = TextEdit.new()
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_edit.custom_minimum_size.y = 80
	_text_edit.placeholder_text = placeholder
	_text_edit.text = _current_value
	_text_edit.editable = _editable
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.text_changed.connect(_on_multiline_text_changed)
	add_child(_text_edit)


func _on_text_changed(new_text: String) -> void:
	if new_text != _current_value:
		_current_value = new_text
		value_changed.emit(_current_value)


func _on_text_submitted(_new_text: String) -> void:
	# Text submitted is handled by text_changed
	pass


func _on_multiline_text_changed() -> void:
	var new_text: String = _text_edit.text
	if new_text != _current_value:
		_current_value = new_text
		value_changed.emit(_current_value)


## Set the current value
func set_value(value: Variant) -> void:
	_current_value = str(value) if value != null else ""
	
	if _line_edit != null:
		_line_edit.text = _current_value
	elif _text_edit != null:
		_text_edit.text = _current_value


## Get the current value
func get_value() -> String:
	return _current_value


## Set whether the control is editable
func set_editable(editable: bool) -> void:
	_editable = editable
	
	if _line_edit != null:
		_line_edit.editable = _editable
	elif _text_edit != null:
		_text_edit.editable = _editable


## Check if the control is editable
func is_editable() -> bool:
	return _editable
