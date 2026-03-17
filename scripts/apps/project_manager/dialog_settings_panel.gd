class_name DialogSettingsPanel extends Control
## 对话框设置面板 — SubViewport 预览 + 属性编辑
## 左侧：SubViewport 预览（使用实际 DialogBox 场景实例，与运行时渲染一致）
## 右侧：PropertyEditor 编辑 AVGDialogSettings 属性
## 名字框可拖拽调整位置

signal settings_changed()

# =============================================================================
# 子节点引用
# =============================================================================

@onready var preview_area: Control = %PreviewArea
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var preview_root: Control = %PreviewRoot
@onready var dialog_box_preview: Control = %DialogBoxPreview
@onready var choice_container: VBoxContainer = %ChoiceContainer
@onready var property_editor: Control = %SettingsPropertyEditor

# =============================================================================
# State
# =============================================================================

var _settings: Resource = null  # AVGDialogSettings
var _project_resolution: Vector2 = Vector2(2560, 1440)

## 名字框拖拽状态
var _dragging_name: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _name_panel_ref: Control = null


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	if preview_area:
		preview_area.resized.connect(_on_preview_resized)
	if property_editor and property_editor.has_signal("property_changed"):
		property_editor.property_changed.connect(_on_property_changed)
	
	# 设置背景样式
	_setup_background()
	
	call_deferred("_on_preview_resized")


# =============================================================================
# Public API
# =============================================================================

func set_settings(settings: Resource) -> void:
	_settings = settings
	_refresh_property_editor()
	# 延迟调用，确保 DialogBox 子节点已初始化
	call_deferred("_update_preview")


func set_project_resolution(resolution: Vector2) -> void:
	_project_resolution = resolution
	_update_viewport_size()
	_update_preview()


# =============================================================================
# Property Editor
# =============================================================================

func _refresh_property_editor() -> void:
	if property_editor == null or _settings == null:
		return
	if property_editor.has_method("set_target"):
		property_editor.set_target(_settings)


func _on_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	_update_preview()
	settings_changed.emit()


# =============================================================================
# Background
# =============================================================================

func _setup_background() -> void:
	var bg: Panel = preview_root.get_node_or_null("Background") as Panel
	if bg:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
		style.border_color = Color(0.4, 0.4, 0.4, 0.8)
		style.set_border_width_all(1)
		bg.add_theme_stylebox_override("panel", style)


# =============================================================================
# Viewport Layout
# =============================================================================

func _on_preview_resized() -> void:
	_update_viewport_layout()


func _update_viewport_size() -> void:
	if preview_root:
		preview_root.size = _project_resolution
	_update_viewport_layout()


func _update_viewport_layout() -> void:
	if preview_area == null or viewport_container == null:
		return
	
	var available_size: Vector2 = preview_area.size
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
	
	call_deferred("_sync_preview_root_scale")


func _sync_preview_root_scale() -> void:
	if sub_viewport == null or preview_root == null:
		return
	var vp_size: Vector2 = Vector2(sub_viewport.size)
	if vp_size.x <= 0 or vp_size.y <= 0 or _project_resolution.x <= 0:
		return
	
	preview_root.size = _project_resolution
	var s: float = vp_size.x / _project_resolution.x
	preview_root.scale = Vector2(s, s)


# =============================================================================
# Preview — Update
# =============================================================================

func _update_preview() -> void:
	if _settings == null:
		return
	_update_dialog_box()
	_update_choice_preview()
	_setup_name_drag()


func _update_dialog_box() -> void:
	if dialog_box_preview == null or _settings == null:
		return
	
	# DialogBox 尺寸 = 项目分辨率（它内部自己布局）
	dialog_box_preview.size = _project_resolution
	
	if dialog_box_preview.has_method("set_dialog_settings"):
		dialog_box_preview.set_dialog_settings(_settings)
	if dialog_box_preview.has_method("set_project_resolution"):
		dialog_box_preview.set_project_resolution(_project_resolution)
	
	# 显示示例对话（极大 text_speed 实现瞬间显示）
	if dialog_box_preview.has_method("show_dialogue"):
		dialog_box_preview.show_dialogue({
			"text": "这是一段示例对话文本，用于预览对话框的显示效果。\n支持 [color=yellow]BBCode[/color] 格式。",
			"speaker": "角色名",
			"text_speed": 99999.0,
		})
	if dialog_box_preview.has_method("_skip_typewriter"):
		dialog_box_preview.call("_skip_typewriter")


func _update_choice_preview() -> void:
	if choice_container == null or _settings == null:
		return
	
	# 清除旧选项
	for child in choice_container.get_children():
		child.queue_free()
	
	var spacing: int = _settings.choice_spacing
	choice_container.add_theme_constant_override("separation", spacing)
	
	var choice_sb: StyleBox = _settings.get_choice_stylebox()
	var min_norm: Vector2 = _settings.choice_min_norm_size
	var min_pixel: Vector2 = min_norm * _project_resolution
	var font_size: int = _settings.choice_font_size
	var font_color: Color = _settings.choice_font_color
	
	var sample_texts: Array[String] = ["选项 A", "选项 B"]
	for text in sample_texts:
		var btn := Button.new()
		btn.text = text
		btn.custom_minimum_size = min_pixel
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_stylebox_override("normal", choice_sb)
		btn.add_theme_font_size_override("font_size", font_size)
		btn.add_theme_color_override("font_color", font_color)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		choice_container.add_child(btn)
	
	# 选项居中放置
	await get_tree().process_frame
	if is_instance_valid(choice_container):
		var container_size: Vector2 = choice_container.size
		choice_container.position = Vector2(
			(_project_resolution.x - container_size.x) / 2.0,
			(_project_resolution.y - container_size.y) / 2.0
		)


# =============================================================================
# Name Panel Drag
# =============================================================================

func _setup_name_drag() -> void:
	if dialog_box_preview == null:
		return
	# 获取 DialogBox 内部的 NamePanel 节点
	var name_panel: Control = dialog_box_preview.get_node_or_null("%NamePanel")
	if name_panel == null:
		return
	_name_panel_ref = name_panel
	# 允许名字框接收输入
	name_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# 避免重复连接
	if not name_panel.gui_input.is_connected(_on_name_panel_gui_input):
		name_panel.gui_input.connect(_on_name_panel_gui_input)


func _on_name_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging_name = true
				_drag_offset = _name_panel_ref.get_local_mouse_position()
			else:
				_dragging_name = false
				_save_name_offset()

	elif event is InputEventMouseMotion and _dragging_name:
		if _name_panel_ref == null:
			return
		var mouse_pos: Vector2 = _name_panel_ref.get_parent().get_local_mouse_position()
		_name_panel_ref.position = mouse_pos - _drag_offset


func _save_name_offset() -> void:
	if _settings == null or _name_panel_ref == null or dialog_box_preview == null:
		return
	
	# 获取 BoxPanel 位置来计算相对偏移
	var box_panel: Control = dialog_box_preview.get_node_or_null("%BoxPanel")
	if box_panel == null:
		return
	
	var relative_pos: Vector2 = _name_panel_ref.position - box_panel.position
	var box_pixel_size: Vector2 = _settings.box_norm_size * _project_resolution
	if box_pixel_size.x <= 0 or box_pixel_size.y <= 0:
		return
	
	var new_norm_offset: Vector2 = Vector2(
		relative_pos.x / box_pixel_size.x,
		relative_pos.y / box_pixel_size.y
	)
	
	_settings.name_norm_offset = new_norm_offset
	_refresh_property_editor()
	settings_changed.emit()
