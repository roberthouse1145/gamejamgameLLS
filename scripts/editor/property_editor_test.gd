extends Control
## Property Editor Test Scene
## Tests the PropertyEditor component with AVGNode resource.

const PropertyEditorScript = preload("res://scripts/editor/property_editor.gd")

var _property_editor: Control
var _test_resource: Resource


func _ready() -> void:
	_setup_test()


func _setup_test() -> void:
	# Create a test AVGNode resource
	_test_resource = _create_test_resource()
	
	# Create property editor
	_property_editor = PropertyEditorScript.new()
	
	# Add to container
	var container = $MarginContainer/VBoxContainer/ScrollContainer/PropertyEditorContainer
	container.add_child(_property_editor)
	
	# Set target
	_property_editor.set_target(_test_resource)
	
	# Connect to property changed signal
	_property_editor.property_changed.connect(_on_property_changed)
	
	print("Property Editor Test initialized")
	print("Test resource: ", _test_resource)


func _create_test_resource() -> Resource:
	# Try to use AVGNode if available
	var avg_node_script = load("res://scripts/avg/resources/avg_node.gd")
	if avg_node_script != null:
		var node = avg_node_script.new()
		node.node_id = "test_node_001"
		node.node_name = "Test Node"
		node.position = Vector2(100, 200)
		node.size = Vector2(300, 400)
		node.visible = true
		return node
	
	# Fallback: create a simple test resource
	return _create_simple_test_resource()


func _create_simple_test_resource() -> Resource:
	var res = Resource.new()
	return res


func _on_property_changed(property_name: String, old_value: Variant, new_value: Variant) -> void:
	print("Property changed: ", property_name)
	print("  Old value: ", old_value)
	print("  New value: ", new_value)
