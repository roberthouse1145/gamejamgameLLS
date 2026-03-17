class_name ColorProperty extends HBoxContainer
## Color Property Control — ColorPickerButton with label

signal value_changed(new_value: Color)

@export var property_name: String = ""
@export var label_text: String = ""
@export var description: String = ""

var _label: Label
var _picker: ColorPickerButton
var _current_value: Color = Color.WHITE
var _editable: bool = true


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size.x = 100
	if description != "":
		_label.tooltip_text = description
	add_child(_label)

	_picker = ColorPickerButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.color = _current_value
	_picker.edit_alpha = true
	_picker.disabled = not _editable
	_picker.color_changed.connect(_on_color_changed)
	add_child(_picker)


func _on_color_changed(new_color: Color) -> void:
	if new_color != _current_value:
		_current_value = new_color
		value_changed.emit(_current_value)


func set_value(value: Variant) -> void:
	if value is Color:
		_current_value = value
	else:
		_current_value = Color.WHITE
	if _picker != null:
		_picker.color = _current_value


func get_value() -> Color:
	return _current_value


func set_editable(editable: bool) -> void:
	_editable = editable
	if _picker != null:
		_picker.disabled = not _editable


func is_editable() -> bool:
	return _editable
