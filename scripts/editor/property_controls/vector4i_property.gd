class_name Vector4iProperty extends VBoxContainer
## Vector4i Property Control — 四个 SpinBox (L, T, R, B)
## 用于 margins、padding 等四方向整数值。

signal value_changed(new_value: Vector4i)

@export var property_name: String = ""
@export var label_text: String = ""
@export var min_value: int = -9999
@export var max_value: int = 9999
@export var description: String = ""
## 四个分量的标签
@export var component_labels: PackedStringArray = ["L:", "T:", "R:", "B:"]

var _label: Label
var _spins: Array[SpinBox] = []
var _current_value: Vector4i = Vector4i.ZERO
var _editable: bool = true
var _updating: bool = false


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	if description != "":
		_label.tooltip_text = description
	add_child(_label)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	_spins.clear()
	for i in range(4):
		if i > 0:
			var spacer := Control.new()
			spacer.custom_minimum_size.x = 4
			hbox.add_child(spacer)

		var lbl := Label.new()
		lbl.text = component_labels[i] if i < component_labels.size() else str(i) + ":"
		lbl.custom_minimum_size.x = 18
		hbox.add_child(lbl)

		var spin := SpinBox.new()
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.min_value = min_value
		spin.max_value = max_value
		spin.step = 1.0
		spin.rounded = true
		spin.editable = _editable
		spin.value = _get_component(i)
		spin.value_changed.connect(_on_spin_changed.bind(i))
		hbox.add_child(spin)
		_spins.append(spin)


func _get_component(index: int) -> int:
	match index:
		0: return _current_value.x
		1: return _current_value.y
		2: return _current_value.z
		3: return _current_value.w
		_: return 0


func _set_component(index: int, val: int) -> void:
	match index:
		0: _current_value.x = val
		1: _current_value.y = val
		2: _current_value.z = val
		3: _current_value.w = val


func _on_spin_changed(new_val: float, index: int) -> void:
	if _updating:
		return
	var int_val: int = int(new_val)
	if int_val != _get_component(index):
		_set_component(index, int_val)
		value_changed.emit(_current_value)


func set_value(value: Variant) -> void:
	_updating = true
	if value is Vector4i:
		_current_value = value
	elif value is Vector4:
		_current_value = Vector4i(int(value.x), int(value.y), int(value.z), int(value.w))
	else:
		_current_value = Vector4i.ZERO

	for i in range(_spins.size()):
		_spins[i].value = _get_component(i)
	_updating = false


func get_value() -> Vector4i:
	return _current_value


func set_editable(editable: bool) -> void:
	_editable = editable
	for spin in _spins:
		spin.editable = _editable
