class_name DesktopIcon extends Control
## DesktopIcon - Desktop application icon component
## Displays an app icon and name, handles double-click to launch

# Signals
signal double_clicked(app_id: String)
signal selected(app_id: String)
signal deselected(app_id: String)

# Exported properties
@export var app_id: String = ""
@export var app_name: String = "Application"
@export var icon_texture: Texture2D = null

# Node references (set via unique names in scene)
@onready var icon_rect: TextureRect = %IconTexture
@onready var name_label: Label = %NameLabel

# Selection state
var is_selected: bool = false

# Visual settings
@export var normal_color: Color = Color.WHITE
@export var selected_color: Color = Color(0.29, 0.49, 1.0, 0.3)  # #4A7CFF at 30%
@export var hover_color: Color = Color(1.0, 1.0, 1.0, 0.15)

# Internal state
var _is_hovered: bool = false
var _is_accessible: bool = true
var _launch_tween: Tween = null


func _ready() -> void:
	# Apply initial values
	_update_display()
	_update_visual_state()
	
	# Setup mouse filter
	mouse_filter = Control.MOUSE_FILTER_STOP


## Setup the icon with app definition data
## @param definition: The AppDefinition resource
func setup_from_definition(definition: Resource) -> void:
	if not definition:
		return
	
	# AppDefinition has these properties directly
	app_id = definition.app_id
	app_name = definition.app_name
	icon_texture = definition.icon
	
	_update_display()


## Set the app ID
## @param id: The application ID
func set_app_id(id: String) -> void:
	app_id = id


## Set the app name
## @param p_name: The application display name
func set_app_name(p_name: String) -> void:
	app_name = p_name
	_update_display()


## Set the icon texture
## @param texture: The icon texture to display
func set_icon_texture(texture: Texture2D) -> void:
	icon_texture = texture
	_update_display()


## Update the display with current values
func _update_display() -> void:
	if icon_rect:
		icon_rect.texture = icon_texture

	if name_label:
		name_label.text = app_name
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", Color.WHITE)


## Handle GUI input events
func _gui_input(event: InputEvent) -> void:
	if not _is_accessible:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.double_click:
				# Double-click to launch
				play_launch_feedback()
				double_clicked.emit(app_id)
				accept_event()
			elif mouse_event.pressed:
				# Single click to select
				set_selected(true)
				_play_press_feedback()
				accept_event()


## Handle mouse enter
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_is_hovered = true
			_update_visual_state()
		NOTIFICATION_MOUSE_EXIT:
			_is_hovered = false
			_update_visual_state()


## Set the selection state
## @param value: Whether the icon is selected
func set_selected(value: bool) -> void:
	if not _is_accessible and value:
		return
	if is_selected == value:
		return
	
	is_selected = value
	_update_visual_state()
	
	if is_selected:
		selected.emit(app_id)
	else:
		deselected.emit(app_id)


## Update visual state based on selection and hover
func _update_visual_state() -> void:
	# Get or create the background panel
	var bg := get_node_or_null("SelectionBackground") as Panel
	
	if not bg:
		# Create selection background if it doesn't exist
		bg = Panel.new()
		bg.name = "SelectionBackground"
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		move_child(bg, 0)  # Move to back
		
		# Create a StyleBoxFlat for the background
		var new_style := StyleBoxFlat.new()
		new_style.bg_color = Color.TRANSPARENT
		new_style.corner_radius_top_left = 6
		new_style.corner_radius_top_right = 6
		new_style.corner_radius_bottom_left = 6
		new_style.corner_radius_bottom_right = 6
		bg.add_theme_stylebox_override("panel", new_style)
	
	# Get the stylebox
	var current_style: StyleBoxFlat = bg.get_theme_stylebox("panel") as StyleBoxFlat
	if current_style:
		if not _is_accessible:
			current_style.bg_color = Color(0.08, 0.1, 0.14, 0.28)
		elif is_selected:
			current_style.bg_color = selected_color
		elif _is_hovered:
			current_style.bg_color = hover_color
		else:
			current_style.bg_color = Color.TRANSPARENT

	modulate = Color(1, 1, 1, 1.0 if _is_accessible else 0.42)


## Deselect this icon
func deselect() -> void:
	set_selected(false)


func set_accessible(value: bool) -> void:
	_is_accessible = value
	if not value:
		is_selected = false
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_visual_state()


func play_launch_feedback() -> void:
	if not _is_accessible:
		return
	_play_scale_feedback(Vector2(0.94, 0.94), 0.08, 0.12)


func _play_press_feedback() -> void:
	_play_scale_feedback(Vector2(0.97, 0.97), 0.05, 0.09)


func _play_scale_feedback(target_scale: Vector2, shrink_duration: float, restore_duration: float) -> void:
	if _launch_tween != null and is_instance_valid(_launch_tween):
		_launch_tween.kill()
	pivot_offset = size * 0.5
	_launch_tween = create_tween()
	_launch_tween.set_trans(Tween.TRANS_CUBIC)
	_launch_tween.set_ease(Tween.EASE_OUT)
	_launch_tween.tween_property(self, "scale", target_scale, shrink_duration)
	_launch_tween.tween_property(self, "scale", Vector2.ONE, restore_duration)
