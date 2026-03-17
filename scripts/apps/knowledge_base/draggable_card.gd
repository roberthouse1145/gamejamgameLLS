class_name KnowledgeBaseDraggableCard extends PanelContainer

signal card_moved(card: KnowledgeBaseDraggableCard, new_pos: Vector2)

@onready var content_vbox: VBoxContainer = %ContentVBox

var item_id: String = ""
var author: String = "player"

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

var player_style: StyleBoxFlat
var lin_xia_style: StyleBoxFlat

func _ready() -> void:
	# Keep input processing inside this control to allow dragging
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Create styles dynamically or load from resources
	player_style = get_theme_stylebox("panel", "PanelContainer").duplicate()
	player_style.bg_color = Color(0.18, 0.18, 0.22, 1) # Dark gray
	player_style.border_width_top = 4
	player_style.border_color = Color(0.25, 0.6, 0.9, 1) # Blue header for player
	
	lin_xia_style = player_style.duplicate()
	lin_xia_style.bg_color = Color(0.2, 0.18, 0.22, 1) # Slightly warmer gray
	lin_xia_style.border_color = Color(0.9, 0.4, 0.6, 1) # Pink header for Lin Xia
	
	_apply_style()

func setup(id: String, _author: String, pos_x: float, pos_y: float) -> void:
	item_id = id
	author = _author
	position = Vector2(pos_x, pos_y)
	
	# Clamping to avoid cards spawning completely off-screen in extreme cases
	if position.x < 0: position.x = 20
	if position.y < 0: position.y = 20
	
	_apply_style()

func _apply_style() -> void:
	if author == "lin_xia":
		add_theme_stylebox_override("panel", lin_xia_style)
		# Optional: Could add a custom handwritten font here for Lin Xia's notes
	else:
		add_theme_stylebox_override("panel", player_style)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				# Move this card to the front of the drawing order
				get_parent().move_child(self , -1)
				accept_event()
			else:
				if _dragging:
					_dragging = false
					card_moved.emit(self , position)
					accept_event()
					
	elif event is InputEventMouseMotion and _dragging:
		position = get_parent().get_local_mouse_position() - _drag_offset
		# Prevent dragging out of bounds (negative)
		if position.x < 0: position.x = 0
		if position.y < 0: position.y = 0
		accept_event()
