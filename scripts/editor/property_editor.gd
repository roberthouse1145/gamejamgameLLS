class_name PropertyEditor extends VBoxContainer
## Property Editor Base Component
## Generates UI controls from object properties using get_avg_properties() metadata.
## Supports: string, int, float, bool, Vector2, Vector2i, Vector4i, Color,
##           enum (string & int), Texture2D, AudioStream, inline sub-resource.

const StringPropertyControlScript = preload("res://scripts/editor/property_controls/string_property.gd")
const NumericPropertyControlScript = preload("res://scripts/editor/property_controls/numeric_property.gd")
const BoolPropertyControlScript = preload("res://scripts/editor/property_controls/bool_property.gd")
const Vector2PropertyControlScript = preload("res://scripts/editor/property_controls/vector2_property.gd")
const Vector4iPropertyControlScript = preload("res://scripts/editor/property_controls/vector4i_property.gd")
const EnumPropertyControlScript = preload("res://scripts/editor/property_controls/enum_property.gd")
const ResourcePropertyControlScript = preload("res://scripts/editor/property_controls/resource_property.gd")
const ColorPropertyControlScript = preload("res://scripts/editor/property_controls/color_property.gd")
const PropertyCategoryControlScript = preload("res://scripts/editor/property_controls/property_category.gd")

signal property_changed(property_name: String, old_value: Variant, new_value: Variant)

var _target: Resource = null
var _categories: Dictionary = {}
var _property_controls: Dictionary = {}
var _custom_properties: Array = []


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_target(obj: Resource) -> void:
	_target = obj
	_custom_properties = []
	_clear_ui()
	if _target != null:
		_generate_ui()


## 使用自定义属性定义设置目标（覆盖 get_avg_properties）
func set_target_with_properties(obj: Resource, properties: Array) -> void:
	_target = obj
	_custom_properties = properties
	_clear_ui()
	if _target != null:
		_generate_ui()


func get_target() -> Resource:
	return _target


func _clear_ui() -> void:
	for child in get_children():
		child.queue_free()
	_categories.clear()
	_property_controls.clear()


func _generate_ui() -> void:
	if _target == null:
		return

	var properties: Array = []
	if not _custom_properties.is_empty():
		properties = _custom_properties
	elif _target.has_method("get_avg_properties"):
		properties = _target.get_avg_properties()
	else:
		var script = _target.get_script()
		if script != null and script.has_method("get_avg_properties"):
			properties = script.get_avg_properties()

	if properties.is_empty():
		var label := Label.new()
		label.text = "No editable properties"
		add_child(label)
		return

	var categorized: Dictionary = {}
	for prop in properties:
		var category: String = prop.get("category", "General")
		if not categorized.has(category):
			categorized[category] = []
		categorized[category].append(prop)

	for category_name in categorized.keys():
		var category_control: Control = PropertyCategoryControlScript.new()
		category_control.category_name = category_name
		add_child(category_control)
		_categories[category_name] = category_control

		for prop in categorized[category_name]:
			var prop_control: Control = _create_property_control(prop)
			if prop_control != null:
				category_control.add_property(prop_control)
				_property_controls[prop["name"]] = prop_control


## Determine the control type for a property
func _create_property_control(prop: Dictionary) -> Control:
	var prop_name: String = prop.get("name", "")
	var prop_type = prop.get("type", TYPE_STRING)
	var editable: bool = prop.get("editable", true)
	var visible_prop: bool = prop.get("visible", true)

	if not visible_prop:
		return null

	var control: Control = null
	var type_str: String = _normalize_type(prop_type)

	# Check for enum hint first — int with choices → enum dropdown
	var hint: String = prop.get("hint", "")
	if hint == "choices" or prop.has("options") or prop.has("enum"):
		control = _create_enum_control(prop)
	else:
		match type_str:
			"string":
				control = _create_string_control(prop)
			"packed_string_array":
				control = _create_packed_string_array_control(prop)
			"int", "float":
				control = _create_numeric_control(prop)
			"bool":
				control = _create_bool_control(prop)
			"vector2":
				control = _create_vector2_control(prop)
			"vector4i":
				control = _create_vector4i_control(prop)
			"color":
				control = _create_color_control(prop)
			"sub_resource":
				control = _create_sub_resource_control(prop)
			"object", "texture", "audio":
				control = _create_resource_control(prop)
			_:
				control = _create_string_control(prop)

	if control != null:
		control.set_meta("property_name", prop_name)
		control.set_meta("editable", editable)
		if not editable and control.has_method("set_editable"):
			control.set_editable(false)

	return control


func _normalize_type(prop_type) -> String:
	if prop_type is String:
		return prop_type
	match prop_type:
		TYPE_STRING:
			return "string"
		TYPE_PACKED_STRING_ARRAY:
			return "packed_string_array"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_BOOL:
			return "bool"
		TYPE_VECTOR2:
			return "vector2"
		TYPE_VECTOR2I:
			return "vector2"
		TYPE_VECTOR4I:
			return "vector4i"
		TYPE_OBJECT:
			return "object"
		TYPE_COLOR:
			return "color"
		_:
			return "string"


# =============================================================================
# Control Creators
# =============================================================================

func _create_string_control(prop: Dictionary) -> Control:
	var control: Control = StringPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.multiline = prop.get("multiline", false) or prop.get("hint", "") == "multiline"
	control.description = prop.get("description", "")

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", ""))

	control.value_changed.connect(_on_string_value_changed.bind(prop["name"]))
	return control


func _create_packed_string_array_control(prop: Dictionary) -> Control:
	var control: Control = StringPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.multiline = true
	control.description = prop.get("description", "每行一个文本项")

	var target_value = _target.get(prop["name"])
	control.set_value(_packed_string_array_to_text(target_value))
	control.value_changed.connect(_on_packed_string_array_value_changed.bind(prop["name"]))
	return control


func _create_numeric_control(prop: Dictionary) -> Control:
	var control: Control = NumericPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.is_integer = prop.get("type", TYPE_FLOAT) in [TYPE_INT, "int"]
	control.min_value = prop.get("min", -999999.0)
	control.max_value = prop.get("max", 999999.0)
	if control.is_integer:
		control.step = prop.get("step", 1.0)
	else:
		control.step = prop.get("step", 0.1)
	control.description = prop.get("description", "")

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", 0))

	control.value_changed.connect(_on_numeric_value_changed.bind(prop["name"]))
	return control


func _create_bool_control(prop: Dictionary) -> Control:
	var control: Control = BoolPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.description = prop.get("description", "")

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", false))

	control.value_changed.connect(_on_bool_value_changed.bind(prop["name"]))
	return control


func _create_vector2_control(prop: Dictionary) -> Control:
	var control: Control = Vector2PropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.is_integer = prop.get("type", TYPE_VECTOR2) == TYPE_VECTOR2I
	if control.is_integer:
		control.step = prop.get("step", 1.0)
	else:
		control.step = prop.get("step", 0.01)
	control.description = prop.get("description", "")

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", Vector2.ZERO))

	control.value_changed.connect(_on_vector2_value_changed.bind(prop["name"]))
	return control


func _create_vector4i_control(prop: Dictionary) -> Control:
	var control: Control = Vector4iPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.description = prop.get("description", "")

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", Vector4i.ZERO))

	control.value_changed.connect(_on_vector4i_value_changed.bind(prop["name"]))
	return control


func _create_color_control(prop: Dictionary) -> Control:
	var control: Control = ColorPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.description = prop.get("description", "")

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", Color.WHITE))

	control.value_changed.connect(_on_color_value_changed.bind(prop["name"]))
	return control


func _create_enum_control(prop: Dictionary) -> Control:
	var control: Control = EnumPropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.options = prop.get("options", prop.get("enum", []))
	control.description = prop.get("description", "")

	# Determine if this is an int-backed enum
	var prop_type = prop.get("type", TYPE_STRING)
	if prop_type is int and prop_type == TYPE_INT:
		control.use_int_value = true
	elif prop_type is String and prop_type == "int":
		control.use_int_value = true

	var target_value = _target.get(prop["name"])
	if target_value != null:
		control.set_value(target_value)
	else:
		control.set_value(prop.get("default", ""))

	control.value_changed.connect(_on_enum_value_changed.bind(prop["name"]))
	return control


func _create_resource_control(prop: Dictionary) -> Control:
	var control: Control = ResourcePropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.description = prop.get("description", "")

	var class_hint: String = prop.get("class_hint", "")
	var type_str: String = _normalize_type(prop.get("type", TYPE_OBJECT))

	if class_hint == "Texture2D" or type_str == "texture":
		control.resource_type = 1  # TEXTURE
	elif class_hint == "AudioStream" or type_str == "audio":
		control.resource_type = 2  # AUDIO
	else:
		control.resource_type = 0  # GENERIC

	var value = _target.get(prop["name"])
	control.set_value(value)

	control.value_changed.connect(_on_resource_value_changed.bind(prop["name"]))
	return control


func _create_sub_resource_control(prop: Dictionary) -> Control:
	var control: Control = ResourcePropertyControlScript.new()
	control.property_name = prop.get("name", "")
	control.label_text = prop.get("name", "").capitalize()
	control.description = prop.get("description", "")
	control.resource_type = 3  # SUB_RESOURCE

	# Set the script class for "New" button
	var res_script_path: String = prop.get("resource_script", "")
	if res_script_path != "":
		control.sub_resource_script = load(res_script_path)

	var value = _target.get(prop["name"])
	control.set_value(value)

	control.value_changed.connect(_on_resource_value_changed.bind(prop["name"]))
	return control


# =============================================================================
# Value change callbacks
# =============================================================================

func _on_string_value_changed(new_value: String, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _on_packed_string_array_value_changed(new_value: String, prop_name: String) -> void:
	_apply_property_change(prop_name, _text_to_packed_string_array(new_value))


func _on_numeric_value_changed(new_value: float, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _on_bool_value_changed(new_value: bool, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _on_vector2_value_changed(new_value: Vector2, prop_name: String) -> void:
	# Convert to Vector2i if the original property is Vector2i
	var current = _target.get(prop_name)
	if current is Vector2i:
		_apply_property_change(prop_name, Vector2i(int(new_value.x), int(new_value.y)))
	else:
		_apply_property_change(prop_name, new_value)


func _on_vector4i_value_changed(new_value: Vector4i, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _on_enum_value_changed(new_value: Variant, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _on_resource_value_changed(new_value: Resource, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _on_color_value_changed(new_value: Color, prop_name: String) -> void:
	_apply_property_change(prop_name, new_value)


func _packed_string_array_to_text(value: Variant) -> String:
	if value is PackedStringArray:
		var packed: PackedStringArray = value
		return "\n".join(packed)
	if value is Array:
		var lines := PackedStringArray()
		for item in value:
			lines.append(str(item))
		return "\n".join(lines)
	return str(value) if value != null else ""


func _text_to_packed_string_array(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	var normalized: String = value.replace("\r\n", "\n").replace("\r", "\n")
	for line in normalized.split("\n", false):
		var item: String = str(line).strip_edges()
		if not item.is_empty():
			result.append(item)
	return result


func _apply_property_change(prop_name: String, new_value: Variant) -> void:
	if _target == null:
		return
	var old_value = _target.get(prop_name)
	_target.set(prop_name, new_value)
	property_changed.emit(prop_name, old_value, new_value)


func refresh_property(prop_name: String) -> void:
	if not _property_controls.has(prop_name) or _target == null:
		return
	var control = _property_controls[prop_name]
	var value = _target.get(prop_name)
	if control.has_method("set_value"):
		control.set_value(value)


func refresh_all() -> void:
	for prop_name in _property_controls.keys():
		refresh_property(prop_name)
