class_name ScenePreviewPanel extends Control
## Scene Preview Panel Component
## SubViewport for real-time preview of AVG scenes with node selection highlighting.
## Maintains project aspect ratio with letterboxing.
## Supports drag to move non-root nodes.
##
## 原理：SubViewportContainer stretch=true 让 SubViewport.size 自动跟随 container 像素大小。
## NodesContainer 固定 size = 项目分辨率，通过 scale 缩放到 SubViewport 实际大小。
## 节点坐标始终在项目分辨率空间内操作。

const AVGCanvasLayerNodeClass = preload("res://scripts/avg/resources/nodes/avg_canvas_layer_node.gd")

# Signals
signal node_clicked(node: Resource)
signal node_moved(node: Resource, new_position: Vector2)

# Current scene reference
var _scene: Resource = null  # AVGScene
# Currently highlighted node
var _highlighted_node: Resource = null
# Map of AVGNode to preview Control
var _node_to_control: Dictionary = {}
# Project resolution (from project settings or default)
var _project_resolution: Vector2 = Vector2(2560, 1440)

# Drag state
var _dragging: bool = false
var _drag_node: Resource = null
var _drag_offset: Vector2 = Vector2.ZERO

# UI References
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var background_rect: TextureRect = %BackgroundRect
@onready var nodes_container: Control = %NodesContainer
@onready var highlight_rect: Control = %HighlightRect


func _ready() -> void:
	_setup_viewport()
	_setup_highlight()
	resized.connect(_on_resized)
	call_deferred("_update_viewport_size")


func _setup_viewport() -> void:
	if viewport_container:
		viewport_container.stretch = true
		viewport_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		viewport_container.anchor_right = 0.0
		viewport_container.anchor_bottom = 0.0
	# NodesContainer 不用 anchor 铺满，固定为项目分辨率
	if nodes_container:
		nodes_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		nodes_container.anchor_right = 0.0
		nodes_container.anchor_bottom = 0.0
		nodes_container.position = Vector2.ZERO
		nodes_container.size = _project_resolution


func _setup_highlight() -> void:
	if highlight_rect:
		highlight_rect.visible = false
		highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(0.2, 0.6, 1.0, 0.8)
		style.set_border_width_all(2)
		highlight_rect.add_theme_stylebox_override("panel", style)


## 更新 viewport container 大小（保持宽高比居中）+ 同步 NodesContainer scale
func _update_viewport_size() -> void:
	if viewport_container == null or sub_viewport == null:
		return

	var available_size: Vector2 = size
	if available_size.x <= 0 or available_size.y <= 0:
		return

	var aspect_ratio: float = _project_resolution.x / _project_resolution.y
	var container_aspect: float = available_size.x / available_size.y

	var new_size: Vector2
	if container_aspect > aspect_ratio:
		new_size.y = available_size.y
		new_size.x = available_size.y * aspect_ratio
	else:
		new_size.x = available_size.x
		new_size.y = available_size.x / aspect_ratio

	viewport_container.size = new_size
	viewport_container.position = (available_size - new_size) / 2

	# stretch=true 时 SubViewport.size 自动 = container 像素大小
	# 等一帧让 SubViewport.size 更新后再算 scale
	call_deferred("_sync_nodes_container_scale")


## 同步 NodesContainer 的 scale，使其内部坐标空间 = 项目分辨率
func _sync_nodes_container_scale() -> void:
	if nodes_container == null or sub_viewport == null:
		return
	var vp_size: Vector2 = Vector2(sub_viewport.size)
	if vp_size.x <= 0 or vp_size.y <= 0 or _project_resolution.x <= 0:
		return
	# NodesContainer.size 固定为项目分辨率，通过 scale 缩放到 viewport 实际大小
	nodes_container.size = _project_resolution
	var s: float = vp_size.x / _project_resolution.x
	nodes_container.scale = Vector2(s, s)
	# BackgroundRect 和 HighlightRect 都是 NodesContainer 的子节点，自动继承 scale
	if background_rect:
		background_rect.size = _project_resolution
	_update_highlight()


func _on_resized() -> void:
	_update_viewport_size()
	_rebuild_preview()


## Set project resolution
func set_project_resolution(resolution: Vector2) -> void:
	_project_resolution = resolution
	if nodes_container:
		nodes_container.size = resolution
	_update_viewport_size()


## Set the scene to preview
func set_scene(scene: Resource) -> void:
	_scene = scene
	_highlighted_node = null
	var project = StorageManager.current_project
	if project and "resolution" in project:
		set_project_resolution(Vector2(project.resolution))
	_rebuild_preview()


## Highlight a specific node
func highlight_node(node: Resource) -> void:
	_highlighted_node = node
	_update_highlight()


## Clear the highlight
func clear_highlight() -> void:
	_highlighted_node = null
	if highlight_rect:
		highlight_rect.visible = false


## Rebuild the entire preview
func _rebuild_preview() -> void:
	_clear_preview()
	if _scene == null:
		return

	var root_node: Resource = _find_root_node()
	if root_node and root_node is AVGRootNode:
		if background_rect and root_node.background:
			background_rect.texture = root_node.background
			background_rect.visible = true
		elif background_rect:
			background_rect.visible = false
	elif background_rect:
		background_rect.visible = false

	for node in _scene.nodes:
		_create_node_preview(node)


func _find_root_node() -> Resource:
	if _scene == null:
		return null
	for node in _scene.nodes:
		if node is AVGRootNode:
			return node
	return null


func _clear_preview() -> void:
	_node_to_control.clear()
	if nodes_container:
		for child in nodes_container.get_children():
			if child == background_rect or child == highlight_rect:
				continue
			child.queue_free()


## Create a preview control for a node
## owner_shared_ref: 如果正在渲染非唯一 SharedNodeRef 的模板内容，传入该 SharedNodeRef
func _create_node_preview(node: Resource, parent: Control = null, owner_shared_ref: Resource = null) -> Control:
	var target_parent: Control = parent if parent else nodes_container
	if target_parent == null:
		return null

	# Root 节点不需要额外渲染，但仍需渲染其子节点
	if node is AVGRootNode:
		for child_node in node.children:
			_create_node_preview(child_node, target_parent, owner_shared_ref)
		return null

	# AVGCanvasLayerNode — 逻辑容器，预览中不渲染自身，直接渲染子节点
	# （预览面板没有 Camera2D，不需要 CanvasLayer 隔离）
	if node is AVGCanvasLayerNodeClass:
		for child_node in node.children:
			_create_node_preview(child_node, target_parent, owner_shared_ref)
		return null

	# SharedNodeRef — 创建容器，渲染解析后的节点树
	if node is AVGSharedNodeRef:
		var resolved: Resource = null
		if node.is_unique and node.unique_data != null:
			resolved = node.unique_data
		else:
			var project = StorageManager.current_project
			if project:
				resolved = node.get_resolved_node(project)
		if resolved != null:
			var ref_container := Control.new()
			ref_container.name = node.node_name
			ref_container.position = node.calc_pixel_position(_project_resolution)
			ref_container.size = node.calc_pixel_size(_project_resolution)
			ref_container.visible = node.visible
			ref_container.mouse_filter = Control.MOUSE_FILTER_STOP
			ref_container.set_meta("avg_node", node)
			ref_container.gui_input.connect(_on_node_gui_input.bind(node))
			target_parent.add_child(ref_container)
			_node_to_control[node] = ref_container
			# 非唯一时，模板内部节点的点击应该选中 SharedNodeRef 本体
			var inner_owner: Resource = node if not node.is_unique else null
			_create_node_preview(resolved, ref_container, inner_owner)
		# 渲染 SharedNodeRef 自己的 children（场景内添加的子节点）
		for child_node in node.children:
			_create_node_preview(child_node, target_parent, owner_shared_ref)
		return null

	var control: Control = _create_control_for_type(node)
	if control == null:
		return null

	control.position = node.calc_pixel_position(_project_resolution)
	control.size = node.calc_pixel_size(_project_resolution)
	control.visible = node.visible
	control.set_meta("avg_node", node)
	
	# 如果在渲染非唯一 SharedNodeRef 的模板内容，点击应该选中 SharedNodeRef 本体
	if owner_shared_ref != null:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.gui_input.connect(_on_node_gui_input.bind(node))

	target_parent.add_child(control)
	_node_to_control[node] = control

	for child_node in node.children:
		_create_node_preview(child_node, control, owner_shared_ref)

	return control


## Create appropriate control based on node type
func _create_control_for_type(node: Resource) -> Control:
	if node is AVGCharacterNode:
		return _create_character_preview(node)
	else:
		return _create_unified_preview(node)


## 统一渲染：style_box 背景 → texture 图片 → text 文本
func _create_unified_preview(node: Resource) -> Control:
	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.clip_contents = node.clip_contents

	# 1. style_box 背景
	if node.style_box != null and node.style_box.has_method("to_stylebox"):
		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_theme_stylebox_override("panel", node.style_box.to_stylebox())
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(panel)
	
	# 2. texture 图片
	if node.texture != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = node.texture
		tex_rect.modulate = node.modulate
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(tex_rect)
	
	# 3. text 文本
	if not node.text.is_empty():
		var label := Label.new()
		label.text = node.text
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = node.h_alignment
		label.vertical_alignment = node.v_alignment
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if node.font_size > 0:
			label.add_theme_font_size_override("font_size", node.font_size)
		label.add_theme_color_override("font_color", node.font_color)
		if node.outline_size > 0:
			label.add_theme_constant_override("outline_size", node.outline_size)
			label.add_theme_color_override("font_outline_color", node.outline_color)
		container.add_child(label)

	return container


func _create_character_preview(node: Resource) -> Control:
	var texture_rect := TextureRect.new()
	if node.character_ref and "sprites" in node.character_ref:
		var emotion: String = node.emotion if node.emotion else "default"
		var sprites: Dictionary = node.character_ref.sprites
		if sprites.has(emotion):
			texture_rect.texture = sprites[emotion]
		elif sprites.has("default"):
			texture_rect.texture = sprites["default"]
	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.flip_h = node.flip_h
	texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return texture_rect


## Update highlight position and visibility
func _update_highlight() -> void:
	if highlight_rect == null:
		return
	if _highlighted_node == null or not _node_to_control.has(_highlighted_node):
		highlight_rect.visible = false
		return
	var control: Control = _node_to_control[_highlighted_node]
	if not is_instance_valid(control):
		highlight_rect.visible = false
		return
	highlight_rect.visible = true
	# 坐标在 NodesContainer 的项目分辨率空间内（highlight_rect 也在同一 scale 下）
	var global_pos: Vector2 = _get_control_global_position_in_container(control)
	var actual_size: Vector2 = control.size
	var border_margin: Vector2 = Vector2(2, 2)
	highlight_rect.position = global_pos - border_margin
	highlight_rect.size = actual_size + border_margin * 2


func _get_control_global_position_in_container(control: Control) -> Vector2:
	var pos: Vector2 = Vector2.ZERO
	var current: Control = control
	while current != null and current != nodes_container:
		pos += current.position
		current = current.get_parent() as Control
	return pos


## Handle node input (click and drag)
func _on_node_gui_input(event: InputEvent, node: Resource) -> void:
	var is_root: bool = node is AVGRootNode
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				node_clicked.emit(node)
				if not is_root:
					_dragging = true
					_drag_node = node
					var control: Control = _node_to_control.get(node)
					if control:
						_drag_offset = control.get_local_mouse_position()
			else:
				if _dragging and _drag_node != null:
					node_moved.emit(_drag_node, _drag_node.position)
				_dragging = false
				_drag_node = null
	elif event is InputEventMouseMotion and _dragging and _drag_node != null:
		var control: Control = _node_to_control.get(_drag_node)
		if control:
			var parent_control: Control = control.get_parent() as Control
			if parent_control:
				var mouse_pos: Vector2 = parent_control.get_local_mouse_position()
				var new_pos: Vector2 = mouse_pos - _drag_offset
				control.position = new_pos
				_drag_node.set_position_from_pixels(new_pos, _project_resolution)
				_update_highlight()


## Refresh a specific node's preview (rebuild it)
func refresh_node(node: Resource) -> void:
	if not _node_to_control.has(node):
		return
	var control: Control = _node_to_control[node]
	control.position = node.calc_pixel_position(_project_resolution)
	control.size = node.calc_pixel_size(_project_resolution)
	control.visible = node.visible
	# 完整重建比逐属性更新更可靠
	_rebuild_preview()
	_update_highlight()


## Refresh entire preview
func refresh() -> void:
	_rebuild_preview()
	_update_highlight()
