class_name TitleSettingsPanel extends Control
## 标题界面设置面板 — SubViewport 预览 + 属性编辑 + 拖拽定位
## 左侧：SubViewport 预览（与运行时渲染一致）
## 右侧：PropertyEditor 编辑 AVGTitleConfig 属性

const SceneSelectorDialogClass = preload("res://scripts/editor/scene_selector_dialog.gd")

signal settings_changed()

# =============================================================================
# 子节点引用
# =============================================================================

@onready var preview_area: Control = %PreviewArea
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var preview_root: Control = %PreviewRoot
@onready var background_panel: Panel = %Background
@onready var background_image: TextureRect = %BackgroundImage
@onready var title_label: Label = %TitleLabel
@onready var start_button: Button = %StartButton
@onready var load_button: Button = %LoadButton
@onready var settings_button: Button = %SettingsButton
@onready var property_editor: Control = %TitlePropertyEditor
@onready var scene_select_button: Button = %SceneSelectButton
@onready var scene_select_label: Label = %SceneSelectLabel

# =============================================================================
# State
# =============================================================================

var _config: Resource = null  # AVGTitleConfig
var _project: Resource = null  # AVGProject
var _project_resolution: Vector2 = Vector2(2560, 1440)

## 拖拽状态
var _dragging_node: Control = null
var _drag_offset: Vector2 = Vector2.ZERO
## 拖拽目标 -> config 属性名映射
var _drag_map: Dictionary = {}


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	if preview_area:
		preview_area.resized.connect(_on_preview_resized)
	if property_editor and property_editor.has_signal("property_changed"):
		property_editor.property_changed.connect(_on_property_changed)
	if scene_select_button:
		scene_select_button.pressed.connect(_on_scene_select_pressed)
	
	# 设置拖拽处理
	_setup_drag_handlers()
	
	# 延迟初始化布局
	call_deferred("_on_preview_resized")


# =============================================================================
# Public API
# =============================================================================

func set_project(project: Resource) -> void:
	_project = project
	if project != null and "resolution" in project:
		_project_resolution = Vector2(project.resolution)
	_load_config()
	_update_viewport_size()
	_refresh_property_editor()
	_refresh_scene_select_label()
	_update_preview()


func set_config(config: Resource) -> void:
	_config = config
	_refresh_property_editor()
	_update_preview()


# =============================================================================
# Internal — Config
# =============================================================================

func _load_config() -> void:
	if _project == null:
		_config = null
		return
	if _project.title_config == null:
		var TitleConfigClass = load("res://scripts/avg/resources/avg_title_config.gd")
		if TitleConfigClass:
			_project.title_config = TitleConfigClass.new()
	_config = _project.title_config


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
# Property Editor
# =============================================================================

func _refresh_property_editor() -> void:
	if property_editor == null or _config == null:
		return
	if property_editor.has_method("set_target"):
		property_editor.set_target(_config)


func _on_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	_update_preview()
	settings_changed.emit()


# =============================================================================
# Scene Selector
# =============================================================================

func _on_scene_select_pressed() -> void:
	if _project == null:
		return
	var preselect_id: String = ""
	if _config != null:
		preselect_id = _config.first_scene_id
	var dialog: Window = SceneSelectorDialogClass.new()
	add_child(dialog)
	dialog.scene_confirmed.connect(_on_scene_selected)
	dialog.open(_project, preselect_id)


func _on_scene_selected(scene_id: String) -> void:
	if _config == null:
		return
	_config.first_scene_id = scene_id
	_refresh_property_editor()
	_refresh_scene_select_label()
	settings_changed.emit()


func _refresh_scene_select_label() -> void:
	if scene_select_label == null:
		return
	if _config == null or _project == null:
		scene_select_label.text = "未选择"
		return
	var scene_id: String = _config.first_scene_id
	if scene_id.is_empty():
		scene_select_label.text = "未选择"
		return
	for i in range(_project.scenes.size()):
		var scene = _project.scenes[i]
		if scene != null and "scene_id" in scene and scene.scene_id == scene_id:
			var scene_name: String = scene.scene_name if "scene_name" in scene else ""
			scene_select_label.text = "%d. %s (%s)" % [i, scene_name, scene_id]
			return
	scene_select_label.text = "未找到: %s" % scene_id


# =============================================================================
# Preview — Update
# =============================================================================

func _update_preview() -> void:
	if _config == null:
		return
	
	_update_background()
	_update_title()
	_update_buttons()


func _update_background() -> void:
	if background_panel:
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = _config.background_color
		background_panel.add_theme_stylebox_override("panel", bg_style)
	
	if background_image:
		if not _config.background_image.is_empty():
			var tex: Texture2D = StorageManager.load_texture_from_path(_config.background_image, _project)
			background_image.texture = tex
			background_image.visible = tex != null
		else:
			background_image.texture = null
			background_image.visible = false


func _update_title() -> void:
	if title_label == null or _config == null:
		return
	
	var title_text: String = _config.title_text
	if title_text.is_empty() and _project != null:
		title_text = _project.project_name
	
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", _config.title_font_size)
	title_label.add_theme_color_override("font_color", _config.title_color)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	
	# 标题尺寸和位置
	var label_size := Vector2(_project_resolution.x * 0.6, 120)
	title_label.size = label_size
	var norm_pos: Vector2 = _config.title_norm_position
	title_label.position = Vector2(
		norm_pos.x * _project_resolution.x - _project_resolution.x * 0.3,
		norm_pos.y * _project_resolution.y - 60
	)


func _update_buttons() -> void:
	if _config == null:
		return
	
	var btn_size: Vector2 = _config.button_size
	var btn_font: int = _config.button_font_size
	
	# 开始游戏按钮
	if start_button:
		start_button.text = _config.start_button_text
		start_button.custom_minimum_size = btn_size
		start_button.size = btn_size
		start_button.add_theme_font_size_override("font_size", btn_font)
		start_button.position = Vector2(
			_config.start_button_norm_position.x * _project_resolution.x - btn_size.x / 2.0,
			_config.start_button_norm_position.y * _project_resolution.y - btn_size.y / 2.0
		)
	
	# 读档按钮
	if load_button:
		load_button.text = _config.load_button_text
		load_button.custom_minimum_size = btn_size
		load_button.size = btn_size
		load_button.add_theme_font_size_override("font_size", btn_font)
		load_button.disabled = not _config.load_button_enabled
		load_button.position = Vector2(
			_config.load_button_norm_position.x * _project_resolution.x - btn_size.x / 2.0,
			_config.load_button_norm_position.y * _project_resolution.y - btn_size.y / 2.0
		)
	
	# 设置按钮
	if settings_button:
		settings_button.text = _config.settings_button_text
		settings_button.custom_minimum_size = btn_size
		settings_button.size = btn_size
		settings_button.add_theme_font_size_override("font_size", btn_font)
		settings_button.disabled = not _config.settings_button_enabled
		settings_button.position = Vector2(
			_config.settings_button_norm_position.x * _project_resolution.x - btn_size.x / 2.0,
			_config.settings_button_norm_position.y * _project_resolution.y - btn_size.y / 2.0
		)


# =============================================================================
# Drag Handlers
# =============================================================================

func _setup_drag_handlers() -> void:
	_drag_map.clear()
	
	if title_label:
		title_label.gui_input.connect(_on_title_gui_input)
		_drag_map[title_label] = "title_norm_position"
	
	if start_button:
		start_button.gui_input.connect(_on_start_btn_gui_input)
		_drag_map[start_button] = "start_button_norm_position"
	
	if load_button:
		load_button.gui_input.connect(_on_load_btn_gui_input)
		_drag_map[load_button] = "load_button_norm_position"
	
	if settings_button:
		settings_button.gui_input.connect(_on_settings_btn_gui_input)
		_drag_map[settings_button] = "settings_button_norm_position"


func _on_title_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event, title_label, "title_norm_position", title_label.size if title_label else Vector2.ZERO)


func _on_start_btn_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event, start_button, "start_button_norm_position", _config.button_size if _config else Vector2.ZERO)


func _on_load_btn_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event, load_button, "load_button_norm_position", _config.button_size if _config else Vector2.ZERO)


func _on_settings_btn_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event, settings_button, "settings_button_norm_position", _config.button_size if _config else Vector2.ZERO)


func _handle_drag_input(event: InputEvent, target: Control, config_prop: String, element_size: Vector2) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging_node = target
				_drag_offset = target.get_local_mouse_position()
			else:
				if _dragging_node == target:
					_save_drag_position(target, config_prop, element_size)
					_dragging_node = null

	elif event is InputEventMouseMotion and _dragging_node == target:
		var mouse_pos: Vector2 = preview_root.get_local_mouse_position()
		target.position = mouse_pos - _drag_offset


func _save_drag_position(target: Control, config_prop: String, element_size: Vector2) -> void:
	if _config == null:
		return
	
	# 直接从项目分辨率坐标计算归一化位置
	var center_pos: Vector2 = target.position + element_size / 2.0
	var norm_pos: Vector2 = center_pos / _project_resolution
	norm_pos = norm_pos.clamp(Vector2.ZERO, Vector2.ONE)
	
	_config.set(config_prop, norm_pos)
	_refresh_property_editor()
	settings_changed.emit()
