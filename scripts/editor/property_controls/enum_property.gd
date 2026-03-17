class_name EnumProperty extends HBoxContainer
## Enum Property Control
## OptionButton with options from property metadata.
## Supports both string and int value modes.

signal value_changed(new_value: Variant)

@export var property_name: String = ""
@export var label_text: String = ""
@export var options: Array = []
@export var description: String = ""

## When true, emit int index instead of string value
var use_int_value: bool = false

var _label: Label
var _option_button: OptionButton
var _current_value: Variant = ""
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

	_option_button = OptionButton.new()
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_button.disabled = not _editable

	for i in range(options.size()):
		var option = options[i]
		if option is String:
			_option_button.add_item(option, i)
		elif option is Dictionary:
			var text: String = option.get("label", option.get("value", str(i)))
			_option_button.add_item(text, i)

	_select_current()
	_option_button.item_selected.connect(_on_item_selected)
	add_child(_option_button)


func _on_item_selected(index: int) -> void:
	var new_value: Variant
	if use_int_value:
		new_value = index
	else:
		new_value = _get_option_value(index)

	if new_value != _current_value:
		_current_value = new_value
		value_changed.emit(_current_value)


func _get_option_value(index: int) -> String:
	if index < 0 or index >= options.size():
		return ""
	var option = options[index]
	if option is String:
		return option
	elif option is Dictionary:
		return option.get("value", option.get("label", ""))
	return ""


func _select_current() -> void:
	if _option_button == null:
		return

	if use_int_value and _current_value is int:
		var idx: int = _current_value as int
		if idx >= 0 and idx < options.size():
			_option_button.select(idx)
			return
	else:
		var val_str: String = str(_current_value) if _current_value != null else ""
		for i in range(options.size()):
			if _get_option_value(i) == val_str:
				_option_button.select(i)
				return

	if options.size() > 0:
		_option_button.select(0)


func set_value(value: Variant) -> void:
	_current_value = value
	_select_current()


func get_value() -> Variant:
	return _current_value


func set_options(new_options: Array) -> void:
	options = new_options
	if _option_button != null:
		_option_button.clear()
		for i in range(options.size()):
			var option = options[i]
			if option is String:
				_option_button.add_item(option, i)
			elif option is Dictionary:
				var text: String = option.get("label", option.get("value", str(i)))
				_option_button.add_item(text, i)
		_select_current()


func set_editable(editable: bool) -> void:
	_editable = editable
	if _option_button != null:
		_option_button.disabled = not _editable


func is_editable() -> bool:
	return _editable
