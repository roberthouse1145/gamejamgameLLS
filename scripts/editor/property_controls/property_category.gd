class_name PropertyCategory extends VBoxContainer
## Property Category Control
## Collapsible sections by category with toggle visibility.
## Validates: Task 8.8

# Signals
signal toggled(expanded: bool)

# Configuration
@export var category_name: String = "Category"
@export var expanded: bool = true
@export var header_color: Color = Color(0.2, 0.2, 0.2, 1.0)

# Internal controls
var _header_button: Button
var _content_container: VBoxContainer
var _arrow_label: Label


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create header button
	_header_button = Button.new()
	_header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header_button.flat = false
	
	# Create header content with arrow and text
	var header_hbox := HBoxContainer.new()
	_header_button.add_child(header_hbox)
	
	_arrow_label = Label.new()
	_arrow_label.text = "▼" if expanded else "▶"
	_arrow_label.custom_minimum_size.x = 20
	header_hbox.add_child(_arrow_label)
	
	var title_label := Label.new()
	title_label.text = category_name
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_label)
	
	_header_button.pressed.connect(_on_header_pressed)
	add_child(_header_button)
	
	# Create content container
	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.visible = expanded
	
	# Add some left margin for indentation
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_child(_content_container)
	add_child(margin)
	
	# Add separator
	var separator := HSeparator.new()
	add_child(separator)


func _on_header_pressed() -> void:
	expanded = not expanded
	_content_container.visible = expanded
	_arrow_label.text = "▼" if expanded else "▶"
	toggled.emit(expanded)


## Add a property control to this category
func add_property(control: Control) -> void:
	if _content_container != null:
		_content_container.add_child(control)


## Remove a property control from this category
func remove_property(control: Control) -> void:
	if _content_container != null and control.get_parent() == _content_container:
		_content_container.remove_child(control)


## Get all property controls in this category
func get_properties() -> Array[Control]:
	var controls: Array[Control] = []
	if _content_container != null:
		for child in _content_container.get_children():
			controls.append(child)
	return controls


## Clear all property controls
func clear_properties() -> void:
	if _content_container != null:
		for child in _content_container.get_children():
			child.queue_free()


## Set the category name
func set_category_name(new_name: String) -> void:
	category_name = new_name
	# Update title label if it exists
	if _header_button != null:
		var header_hbox = _header_button.get_child(0)
		if header_hbox != null and header_hbox.get_child_count() > 1:
			var title_label = header_hbox.get_child(1)
			if title_label is Label:
				title_label.text = category_name


## Set expanded state
func set_expanded(value: bool) -> void:
	expanded = value
	if _content_container != null:
		_content_container.visible = expanded
	if _arrow_label != null:
		_arrow_label.text = "▼" if expanded else "▶"


## Check if category is expanded
func is_expanded() -> bool:
	return expanded


## Get the number of properties in this category
func get_property_count() -> int:
	if _content_container != null:
		return _content_container.get_child_count()
	return 0
