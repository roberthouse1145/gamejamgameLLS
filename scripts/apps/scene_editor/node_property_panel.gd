class_name NodePropertyPanel extends VBoxContainer
## Node Property Panel Component
## Uses PropertyEditor for selected node properties.
## 命令编辑已移至右侧命令标签页面板

# Signals
signal property_changed(node: Resource, property_name: String, value: Variant)

# Current node being edited
var _current_node: Resource = null  # AVGNode

# Preload PropertyEditor
const PropertyEditorScript = preload("res://scripts/editor/property_editor.gd")

# UI References
@onready var title_label: Label = %TitleLabel
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var property_container: VBoxContainer = %PropertyContainer

# Dynamic components
var _property_editor: Control = null


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# Create property editor
	_property_editor = PropertyEditorScript.new()
	_property_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_editor.property_changed.connect(_on_property_editor_changed)

	if property_container:
		property_container.add_child(_property_editor)


## Set the node to edit
func set_node(node: Resource) -> void:
	_current_node = node
	_update_ui()


## Get the current AVG node being edited
func get_avg_node() -> Resource:
	return _current_node


## Update UI with current node data
func _update_ui() -> void:
	if title_label:
		if _current_node:
			title_label.text = "属性: " + _current_node.node_name
		else:
			title_label.text = "属性"
	
	# Update property editor
	if _property_editor:
		_property_editor.set_target(_current_node)


## Handle property editor changes
func _on_property_editor_changed(property_name: String, _old_value: Variant, new_value: Variant) -> void:
	if _current_node:
		property_changed.emit(_current_node, property_name, new_value)


## Refresh the panel
func refresh() -> void:
	_update_ui()
