class_name CommandContext extends RefCounted
## Provides runtime context for AVG command execution
## Contains references to all runtime components and utility methods.
## Validates: Requirement 7.2

# Preload VariableManager to ensure type is available
const VariableManagerClass = preload("res://scripts/avg/runtime/variable_manager.gd")

## Emitted when waiting for a click
signal click_requested
## Emitted when click is received
signal click_received
## Emitted when a label jump is requested
signal label_jump_requested(label_name: String)
## Emitted when a scene jump is requested
signal scene_jump_requested(scene_id: String)
## Emitted when an event call is requested
signal event_call_requested(event_id: String)
## Emitted when background change is requested
signal background_change_requested(texture: Texture2D, fade_duration: float)

## Reference to the AVGSceneRunner
var scene_runner: Node = null

## Reference to the VariableManager
var variable_manager: RefCounted = null  # VariableManager type

## Reference to the DialogBox
var dialog_box: Control = null

## Reference to the CharacterDisplay
var character_display: Node = null

## Reference to the ChoiceDisplay
var choice_display: Control = null

## Reference to the AVGAudioManager
var audio_manager: Node = null

## Reference to the background display node
var background_display: TextureRect = null

## Flag indicating if currently waiting for click
var _waiting_for_click: bool = false

## Flag indicating if currently waiting for time
var _waiting_for_time: bool = false


## Initialize the context with component references
## @param components: Dictionary with component references
func initialize(components: Dictionary) -> void:
	if components.has("scene_runner"):
		scene_runner = components["scene_runner"]
	if components.has("variable_manager"):
		variable_manager = components["variable_manager"]
	if components.has("dialog_box"):
		dialog_box = components["dialog_box"]
	if components.has("character_display"):
		character_display = components["character_display"]
	if components.has("choice_display"):
		choice_display = components["choice_display"]
	if components.has("audio_manager"):
		audio_manager = components["audio_manager"]
	if components.has("background_display"):
		background_display = components["background_display"]


## Wait for player click to continue
## This is an async operation - the scene runner should await this
func wait_for_click() -> void:
	_waiting_for_click = true
	click_requested.emit()
	
	# Wait until click_received is emitted
	await click_received


## Called when a click is received (from dialog_box or external)
func _on_click_received() -> void:
	if _waiting_for_click:
		_waiting_for_click = false
		click_received.emit()


## Notify the context that a click was received (called externally)
func notify_click() -> void:
	_on_click_received()


## Check if currently waiting for click
func is_waiting_for_click() -> bool:
	return _waiting_for_click


## Wait for a specified duration
## @param duration: Time to wait in seconds
func wait_for_time(duration: float) -> void:
	_waiting_for_time = true
	
	if scene_runner != null and scene_runner.is_inside_tree():
		var timer := scene_runner.get_tree().create_timer(duration)
		await timer.timeout
	
	_waiting_for_time = false


## Check if currently waiting for time
func is_waiting_for_time() -> bool:
	return _waiting_for_time


## Request a jump to a label
## @param label_name: Name of the label to jump to
func jump_to_label(label_name: String) -> void:
	label_jump_requested.emit(label_name)


## Request a jump to another scene
## @param scene_id: ID of the scene to jump to
func jump_to_scene(scene_id: String) -> void:
	scene_jump_requested.emit(scene_id)


## Request to call an event
## @param event_id: ID of the event to call
func call_event(event_id: String) -> void:
	event_call_requested.emit(event_id)


## Change the background with optional fade
## @param texture: The new background texture
## @param fade_duration: Duration of the fade transition
func change_background(texture: Texture2D, fade_duration: float = 0.0) -> void:
	if background_display != null:
		if fade_duration > 0.0 and background_display.is_inside_tree():
			# Fade out current background
			var tween := background_display.create_tween()
			tween.tween_property(background_display, "modulate:a", 0.0, fade_duration / 2.0)
			await tween.finished
			
			# Change texture
			background_display.texture = texture
			
			# Fade in new background
			tween = background_display.create_tween()
			tween.tween_property(background_display, "modulate:a", 1.0, fade_duration / 2.0)
			await tween.finished
		else:
			background_display.texture = texture
	
	background_change_requested.emit(texture, fade_duration)


## Get a variable value from the variable manager
## @param variable_key: Key of the variable
## @return: The variable value or null
func get_variable(variable_key: String) -> Variant:
	if variable_manager != null:
		return variable_manager.get_value(variable_key)
	return null


## Set a variable value in the variable manager
## @param variable_key: Key of the variable
## @param value: Value to set
## @param operation: Operation to perform
func set_variable(variable_key: String, value: Variant, operation: String = "set") -> void:
	if variable_manager != null:
		variable_manager.set_value(variable_key, value, operation)
