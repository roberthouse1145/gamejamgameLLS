class_name ChoiceDisplay extends Control
## Displays choice buttons for player selection in AVG games
## Supports conditional choices (condition_commands), greyed-out/hidden modes,
## and sub-command arrays per choice (replaces jump_to).

## Emitted when a choice is selected
signal choice_selected(index: int)

## Container for choice buttons
@onready var button_container: VBoxContainer = %ButtonContainer

## Spacing between buttons
@export var button_spacing: float = 10.0
## Minimum button size
@export var min_button_size: Vector2 = Vector2(200, 40)

## Currently displayed choices
var _choices: Array = []
## Currently created buttons
var _buttons: Array[Button] = []
## Selected index (-1 if none selected)
var _selected_index: int = -1
## Whether currently waiting for selection
var _waiting_for_selection: bool = false
## Dialog settings reference
var _dialog_settings: Resource = null
## Project resolution for scaling
var _project_resolution: Vector2 = Vector2(2560, 1440)
## Variable manager for condition evaluation
var _variable_manager: RefCounted = null
## Scene runner for condition evaluation
var _scene_runner: Variant = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	if button_container == null:
		button_container = VBoxContainer.new()
		button_container.name = "ButtonContainer"
		add_child(button_container)
	
	if button_container != null:
		button_container.add_theme_constant_override("separation", int(button_spacing))


## Set dialog settings for styling
func set_dialog_settings(settings: Resource) -> void:
	_dialog_settings = settings


## Set project resolution
func set_project_resolution(resolution: Vector2) -> void:
	_project_resolution = resolution


## Show choices and wait for selection
## @param choices: Array of choice dictionaries
## @param var_mgr: VariableManager for condition evaluation (optional)
## @param runner: AVGSceneRunner for condition evaluation (optional)
## @return: Selected index
func show_choices(choices: Array, var_mgr: RefCounted = null, runner: Variant = null) -> int:
	_choices = choices
	_selected_index = -1
	_waiting_for_selection = true
	_variable_manager = var_mgr
	_scene_runner = runner
	
	_clear_buttons()

	# Apply spacing from settings
	if button_container != null:
		var spacing: int = int(button_spacing)
		if _dialog_settings != null and "choice_spacing" in _dialog_settings:
			var ref_size: Vector2 = size
			if ref_size.y <= 0:
				ref_size = _project_resolution
			var ref_scale: float = ref_size.y / _project_resolution.y
			spacing = int(_dialog_settings.choice_spacing * ref_scale)
		button_container.add_theme_constant_override("separation", spacing)

	# Create buttons for each choice, evaluating conditions
	for i in range(choices.size()):
		var choice = choices[i]
		var text: String = ""
		var condition_met: bool = true
		var hidden_when_unmet: bool = false
		
		if choice is Dictionary:
			text = choice.get("text", "")
			hidden_when_unmet = choice.get("hidden_when_unmet", false)
			# Evaluate condition_commands
			var cond_cmds: Array = choice.get("condition_commands", [])
			if not cond_cmds.is_empty():
				condition_met = _evaluate_choice_condition(cond_cmds)
		elif choice is String:
			text = choice
		
		# Hidden: skip button creation entirely
		if not condition_met and hidden_when_unmet:
			_buttons.append(null)  # placeholder to keep index alignment
			continue
		
		var button := _create_choice_button(text, i)
		
		# Greyed out: disable button but still show it
		if not condition_met:
			button.disabled = true
			button.modulate = Color(0.5, 0.5, 0.5, 0.7)
		
		_buttons.append(button)
		
		if button_container != null:
			button_container.add_child(button)
	
	visible = true
	_center_container()
	return _selected_index


## Hide the choice display
func hide_choices() -> void:
	visible = false
	_waiting_for_selection = false
	_clear_buttons()


## Get the selected index
func get_selected_index() -> int:
	return _selected_index


## Check if waiting for selection
func is_waiting_for_selection() -> bool:
	return _waiting_for_selection


## Get the selected choice data
func get_selected_choice() -> Variant:
	if _selected_index >= 0 and _selected_index < _choices.size():
		return _choices[_selected_index]
	return null


## Evaluate condition_commands for a choice
## Uses the same system as command_tabs condition evaluation
func _evaluate_choice_condition(condition_commands: Array) -> bool:
	if _scene_runner != null and _scene_runner.has_method("_evaluate_condition_commands"):
		return _scene_runner._evaluate_condition_commands(condition_commands)
	
	# Fallback: if no scene_runner, try basic CHECK_VAR evaluation
	if _variable_manager == null:
		return true
	
	for cmd in condition_commands:
		if cmd == null:
			continue
		var cmd_type: String = ""
		var params: Dictionary = {}
		if cmd is Resource and "command_type" in cmd:
			cmd_type = cmd.command_type
			params = cmd.params if cmd.params != null else {}
		elif cmd is Dictionary:
			cmd_type = cmd.get("command_type", "")
			params = cmd.get("params", {})
		
		if cmd_type == "CHECK_VAR":
			var var_id: String = params.get("variable_id", "")
			var var_name: String = params.get("variable_name", "")
			var op: String = params.get("operator", ">=")
			var actual: Variant = null
			if not var_id.is_empty():
				actual = _variable_manager.get_value_by_id(var_id)
			elif not var_name.is_empty():
				actual = _variable_manager.get_value(var_name)
			if actual == null:
				return false
			var expected = _parse_value(params.get("value", "0"))
			if not _compare(actual, op, expected):
				return false
	return true


## Parse a value string to appropriate type
func _parse_value(value) -> Variant:
	if value is int or value is float or value is bool:
		return value
	var s: String = str(value)
	if s.is_valid_int():
		return s.to_int()
	elif s.is_valid_float():
		return s.to_float()
	elif s == "true":
		return true
	elif s == "false":
		return false
	return s


## Compare two values
func _compare(actual: Variant, op: String, expected: Variant) -> bool:
	match op:
		"==": return actual == expected
		"!=": return actual != expected
		">": return actual > expected
		">=": return actual >= expected
		"<": return actual < expected
		"<=": return actual <= expected
	return false


## Create a choice button
func _create_choice_button(text: String, index: int) -> Button:
	var button := Button.new()
	button.name = "Choice_%d" % index
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var ref_size: Vector2 = size
	if ref_size.x <= 0 or ref_size.y <= 0:
		ref_size = _project_resolution

	if _dialog_settings != null:
		if "choice_min_norm_size" in _dialog_settings:
			var norm: Vector2 = _dialog_settings.choice_min_norm_size
			button.custom_minimum_size = norm * ref_size
		else:
			button.custom_minimum_size = min_button_size

		if _dialog_settings.has_method("get_choice_stylebox"):
			var sb: StyleBox = _dialog_settings.get_choice_stylebox()
			button.add_theme_stylebox_override("normal", sb)
			var hover_sb: StyleBox = _dialog_settings.get_choice_stylebox()
			if hover_sb is StyleBoxFlat:
				hover_sb.bg_color = hover_sb.bg_color.lightened(0.15)
			button.add_theme_stylebox_override("hover", hover_sb)

		if "choice_font_size" in _dialog_settings and _dialog_settings.choice_font_size > 0:
			var ref_scale: float = ref_size.y / _project_resolution.y
			var scaled_fs: int = maxi(int(_dialog_settings.choice_font_size * ref_scale), 8)
			button.add_theme_font_size_override("font_size", scaled_fs)

		if "choice_font_color" in _dialog_settings:
			button.add_theme_color_override("font_color", _dialog_settings.choice_font_color)
			button.add_theme_color_override("font_hover_color", _dialog_settings.choice_font_color)
	else:
		button.custom_minimum_size = min_button_size

	button.pressed.connect(_on_choice_pressed.bind(index))
	return button


## Handle choice button press
func _on_choice_pressed(index: int) -> void:
	if not _waiting_for_selection:
		return
	
	_selected_index = index
	_waiting_for_selection = false
	choice_selected.emit(index)
	hide_choices()


## Clear all choice buttons
func _clear_buttons() -> void:
	for button in _buttons:
		if button != null and is_instance_valid(button):
			button.queue_free()
	_buttons.clear()


## Center the button container
func _center_container() -> void:
	if button_container == null:
		return
	
	await get_tree().process_frame
	
	var container_size: Vector2 = button_container.size
	var parent_size: Vector2 = size
	button_container.position = (parent_size - container_size) / 2.0


## Async method to wait for choice selection
func show_choices_async(choices: Array, var_mgr: RefCounted = null, runner: Variant = null) -> int:
	show_choices(choices, var_mgr, runner)
	var selected: int = await choice_selected
	return selected
