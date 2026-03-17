class_name CommandListEditor extends VBoxContainer
## Command List Editor Component
## List of commands with add/remove/reorder buttons.
## Validates: Task 9.5

# Signals
signal command_selected(command: Resource, index: int)
signal commands_changed(commands: Array)

# Current commands array reference
var _commands: Array = []
# Currently selected index
var _selected_index: int = -1

# Preload AVGCommand
const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")

# UI References
@onready var toolbar: HBoxContainer = %Toolbar
@onready var add_button: Button = %AddButton
@onready var remove_button: Button = %RemoveButton
@onready var move_up_button: Button = %MoveUpButton
@onready var move_down_button: Button = %MoveDownButton
@onready var command_list: ItemList = %CommandList
@onready var type_selector: OptionButton = %TypeSelector


func _ready() -> void:
	_setup_toolbar()
	_setup_list()
	_setup_type_selector()


func _setup_toolbar() -> void:
	if add_button:
		add_button.pressed.connect(_on_add_pressed)
	if remove_button:
		remove_button.pressed.connect(_on_remove_pressed)
	if move_up_button:
		move_up_button.pressed.connect(_on_move_up_pressed)
	if move_down_button:
		move_down_button.pressed.connect(_on_move_down_pressed)


func _setup_list() -> void:
	if command_list:
		command_list.item_selected.connect(_on_item_selected)


func _setup_type_selector() -> void:
	if type_selector:
		type_selector.clear()
		# Get command types from registry
		var registry = CommandRegistry.get_instance()
		var types: Array = registry.get_all_command_types()
		for cmd_type in types:
			type_selector.add_item(cmd_type)
		
		if types.size() > 0:
			type_selector.select(0)


## Set the commands array to edit
func set_commands(commands: Array) -> void:
	_commands = commands
	_selected_index = -1
	_refresh_list()


## Get the commands array
func get_commands() -> Array:
	return _commands


## Get the selected command
func get_selected_command() -> Resource:
	if _selected_index >= 0 and _selected_index < _commands.size():
		return _commands[_selected_index]
	return null


## Refresh the command list display
func _refresh_list() -> void:
	if command_list == null:
		return
	
	command_list.clear()
	
	for i in range(_commands.size()):
		var cmd = _commands[i]
		var display_text: String = "%d. %s" % [i + 1, cmd.command_type]
		command_list.add_item(display_text)
	
	# Restore selection
	if _selected_index >= 0 and _selected_index < _commands.size():
		command_list.select(_selected_index)
	
	_update_button_states()


## Update button enabled states
func _update_button_states() -> void:
	var has_selection: bool = _selected_index >= 0
	
	if remove_button:
		remove_button.disabled = not has_selection
	if move_up_button:
		move_up_button.disabled = not has_selection or _selected_index <= 0
	if move_down_button:
		move_down_button.disabled = not has_selection or _selected_index >= _commands.size() - 1


## Handle item selection
func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_button_states()
	
	if index >= 0 and index < _commands.size():
		command_selected.emit(_commands[index], index)


## Handle add button
func _on_add_pressed() -> void:
	var cmd_type: String = "DIALOGUE"  # Default
	if type_selector and type_selector.selected >= 0:
		cmd_type = type_selector.get_item_text(type_selector.selected)
	
	var new_command = AVGCommandClass.new(cmd_type, {})
	_commands.append(new_command)
	_refresh_list()
	
	# Select the new command
	_selected_index = _commands.size() - 1
	if command_list:
		command_list.select(_selected_index)
	
	commands_changed.emit(_commands)
	command_selected.emit(new_command, _selected_index)


## Handle remove button
func _on_remove_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _commands.size():
		return
	
	_commands.remove_at(_selected_index)
	
	# Adjust selection
	if _selected_index >= _commands.size():
		_selected_index = _commands.size() - 1
	
	_refresh_list()
	commands_changed.emit(_commands)
	
	# Emit selection for new index
	if _selected_index >= 0:
		command_selected.emit(_commands[_selected_index], _selected_index)


## Handle move up button
func _on_move_up_pressed() -> void:
	if _selected_index <= 0 or _selected_index >= _commands.size():
		return
	
	var cmd = _commands[_selected_index]
	_commands.remove_at(_selected_index)
	_commands.insert(_selected_index - 1, cmd)
	_selected_index -= 1
	
	_refresh_list()
	commands_changed.emit(_commands)


## Handle move down button
func _on_move_down_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _commands.size() - 1:
		return
	
	var cmd = _commands[_selected_index]
	_commands.remove_at(_selected_index)
	_commands.insert(_selected_index + 1, cmd)
	_selected_index += 1
	
	_refresh_list()
	commands_changed.emit(_commands)
