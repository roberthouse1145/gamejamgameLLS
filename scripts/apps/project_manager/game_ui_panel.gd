class_name GameUIPanel extends Control
## 游戏内 UI 按钮配置面板
## 左侧：SubViewport 预览区域（与运行时渲染一致）
## 右侧：预览选项 + 按钮列表 + 属性编辑器

const AVGGameUIConfigClass = preload("res://scripts/avg/resources/avg_game_ui_config.gd")
const AVGUIButtonClass = preload("res://scripts/avg/resources/avg_ui_button.gd")

signal settings_changed()

# =============================================================================
# 子节点引用
# =============================================================================

@onready var preview_area: Control = %PreviewArea
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var preview_root: Control = %PreviewRoot
@onready var background_image: TextureRect = %BackgroundImage
@onready var dialog_box_preview: Control = %DialogBoxPreview
@onready var buttons_container: Control = %ButtonsContainer
@onready var show_dialog_check: CheckBox = %ShowDialogCheck
@onready var bg_select_button: Button = %BgSelectButton
@onready var bg_clear_button: Button = %BgClearButton
@onready var button_list_container: VBoxContainer = %ButtonListContainer
@onready var property_editor: Control = %GameUIPropertyEditor
@onready var global_property_editor: Control = %GlobalPropertyEditor

# =============================================================================
# State
# =============================================================================

var _config: Resource = null  # AVGGameUIConfig
var _project: Resource = null  # AVGProject
var _project_resolution: Vector2 = Vector2(2560, 1440)
var _selected_index: int = -1
var _preview_bg_path: String = ""

## 预览区域内的动态按钮节点
var _preview_buttons: Array[Button] = []

## 拖拽状态
var _dragging_node: Control = null
var _drag_offset: Vector2 = Vector2.ZERO


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	if preview_area:
		preview_area.resized.connect(_on_preview_resized)
	if property_editor and property_editor.has_signal("property_changed"):
		property_editor.property_changed.connect(_on_property_changed)
	if global_property_editor and global_property_editor.has_signal("property_changed"):
		global_property_editor.property_changed.connect(_on_global_property_changed)
	
	# 预览选项
	if show_dialog_check:
		show_dialog_check.toggled.connect(_on_show_dialog_toggled)
	if bg_select_button:
		bg_select_button.pressed.connect(_on_bg_select_pressed)
	if bg_clear_button:
		bg_clear_button.pressed.connect(_on_bg_clear_pressed)
	
	# 设置背景样式
	_setup_background_styles()
	
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
	_refresh_button_list()
	_refresh_global_editor()
	_rebuild_preview_buttons()
	# 延迟调用，确保 DialogBox 子节点已初始化
	call_deferred("_update_dialog_box_preview")


# =============================================================================
# Internal — Config
# =============================================================================

func _load_config() -> void:
	if _project == null:
		_config = null
		return
	if _project.game_ui_config == null:
		_project.game_ui_config = AVGGameUIConfigClass.new()
		_project.game_ui_config.init_defaults()
	_config = _project.game_ui_config


func _get_buttons() -> Array:
	if _config == null:
		return []
	return _config.buttons


# =============================================================================
# Preview Options
# =============================================================================

func _on_show_dialog_toggled(toggled_on: bool) -> void:
	if dialog_box_preview:
		dialog_box_preview.visible = toggled_on


func _on_bg_select_pressed() -> void:
	if _project == null:
		return
	var file_dialog := FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png", "*.jpg", "*.jpeg", "*.webp"])
	file_dialog.title = "选择预览背景图"
	
	var project_path: String = StorageManager.get_save_path(_project) if _project else ""
	if not project_path.is_empty():
		file_dialog.current_dir = project_path + "assets/images"
	
	file_dialog.file_selected.connect(_on_bg_file_selected)
	file_dialog.canceled.connect(func(): file_dialog.queue_free())
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(800, 600))


func _on_bg_file_selected(path: String) -> void:
	_preview_bg_path = path
	_update_background_image()
	for child in get_children():
		if child is FileDialog:
			child.queue_free()


func _on_bg_clear_pressed() -> void:
	_preview_bg_path = ""
	_update_background_image()


func _update_background_image() -> void:
	if background_image == null:
		return
	if _preview_bg_path.is_empty():
		background_image.texture = null
		background_image.visible = false
	else:
		var tex: Texture2D = StorageManager.load_texture_from_path(_preview_bg_path)
		background_image.texture = tex
		background_image.visible = tex != null


func _update_dialog_box_preview() -> void:
	if dialog_box_preview == null or _project == null:
		return
	
	# DialogBox 尺寸 = 项目分辨率（它内部自己布局）
	dialog_box_preview.size = _project_resolution
	
	if dialog_box_preview.has_method("set_project_resolution"):
		dialog_box_preview.set_project_resolution(_project_resolution)
	
	# 应用项目的 dialog_settings（如果有）
	if "dialog_settings" in _project and _project.dialog_settings != null:
		if dialog_box_preview.has_method("set_dialog_settings"):
			dialog_box_preview.set_dialog_settings(_project.dialog_settings)
	
	# 显示示例对话
	if dialog_box_preview.has_method("show_dialogue"):
		dialog_box_preview.show_dialogue({
			"text": "这是对话框预览文本...",
			"speaker": "角色名",
			"text_speed": 99999.0,
		})
	if dialog_box_preview.has_method("_skip_typewriter"):
		dialog_box_preview.call("_skip_typewriter")


# =============================================================================
# Viewport Layout
# =============================================================================

func _setup_background_styles() -> void:
	# 背景面板样式
	var bg_panel: Panel = preview_root.get_node_or_null("Background") as Panel
	if bg_panel:
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
		bg_panel.add_theme_stylebox_override("panel", bg_style)


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
# Button List
# =============================================================================

func _refresh_button_list() -> void:
	if button_list_container == null:
		return
	for child in button_list_container.get_children():
		child.queue_free()
	var buttons: Array = _get_buttons()
	for i in range(buttons.size()):
		var btn_data: Resource = buttons[i]
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 30

		var select_btn := Button.new()
		select_btn.text = "%s (%s)" % [btn_data.display_text, btn_data.action]
		select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_btn.toggle_mode = true
		select_btn.button_pressed = (i == _selected_index)
		select_btn.pressed.connect(_on_list_item_pressed.bind(i))
		if not btn_data.visible_default:
			select_btn.modulate = Color(1, 1, 1, 0.5)
		row.add_child(select_btn)

		var vis_btn := Button.new()
		vis_btn.text = "👁" if btn_data.visible_default else "🚫"
		vis_btn.tooltip_text = "隐藏" if btn_data.visible_default else "显示"
		vis_btn.custom_minimum_size = Vector2(32, 0)
		vis_btn.pressed.connect(_on_toggle_visibility.bind(i))
		row.add_child(vis_btn)

		button_list_container.add_child(row)
	_refresh_property_editor()


func _on_list_item_pressed(index: int) -> void:
	_selected_index = index
	for i in range(button_list_container.get_child_count()):
		var row: HBoxContainer = button_list_container.get_child(i) as HBoxContainer
		if row and row.get_child_count() > 0:
			var select_btn: Button = row.get_child(0) as Button
			if select_btn:
				select_btn.button_pressed = (i == _selected_index)
	_refresh_property_editor()
	_update_button_highlight()


func _on_toggle_visibility(index: int) -> void:
	var buttons: Array = _get_buttons()
	if index < 0 or index >= buttons.size():
		return
	buttons[index].visible_default = not buttons[index].visible_default
	_refresh_button_list()
	_rebuild_preview_buttons()
	settings_changed.emit()


func _refresh_property_editor() -> void:
	if property_editor == null:
		return
	var buttons: Array = _get_buttons()
	if _selected_index >= 0 and _selected_index < buttons.size():
		if property_editor.has_method("set_target"):
			property_editor.set_target(buttons[_selected_index])
	else:
		if property_editor.has_method("set_target"):
			property_editor.set_target(null)


func _refresh_global_editor() -> void:
	if global_property_editor == null or _config == null:
		return
	if global_property_editor.has_method("set_target"):
		global_property_editor.set_target(_config)


func _on_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	_refresh_button_list()
	_rebuild_preview_buttons()
	settings_changed.emit()


func _on_global_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	_rebuild_preview_buttons()
	settings_changed.emit()


# =============================================================================
# Preview Buttons
# =============================================================================

func _rebuild_preview_buttons() -> void:
	_clear_preview_buttons()
	if buttons_container == null or _config == null:
		return
	
	var buttons: Array = _get_buttons()
	for i in range(buttons.size()):
		var btn_data: Resource = buttons[i]
		var btn := Button.new()
		btn.name = "PreviewBtn_%d" % i
		btn.text = btn_data.display_text
		btn.custom_minimum_size = btn_data.size
		btn.size = btn_data.size
		btn.add_theme_font_size_override("font_size", btn_data.font_size)
		
		btn.position = Vector2(
			btn_data.norm_position.x * _project_resolution.x - btn_data.size.x / 2.0,
			btn_data.norm_position.y * _project_resolution.y - btn_data.size.y / 2.0
		)
		
		# 应用按钮样式四状态
		if _config != null and "button_style" in _config and _config.button_style != null and _config.button_style.has_method("apply_to_button"):
			_config.button_style.apply_to_button(btn)
		
		if not btn_data.visible_default:
			btn.modulate = Color(1, 1, 1, 0.35)
		
		if i == _selected_index:
			btn.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.gui_input.connect(_make_drag_handler(btn, i))
		buttons_container.add_child(btn)
		_preview_buttons.append(btn)


func _clear_preview_buttons() -> void:
	for btn in _preview_buttons:
		if btn != null and is_instance_valid(btn):
			btn.queue_free()
	_preview_buttons.clear()


func _update_button_highlight() -> void:
	for i in range(_preview_buttons.size()):
		var btn: Button = _preview_buttons[i]
		if btn == null or not is_instance_valid(btn):
			continue
		btn.remove_theme_color_override("font_color")
		if i == _selected_index:
			btn.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))


# =============================================================================
# Drag
# =============================================================================

func _make_drag_handler(target: Control, btn_index: int) -> Callable:
	return func(event: InputEvent) -> void:
		_on_button_gui_input(event, target, btn_index)


func _on_button_gui_input(event: InputEvent, target: Control, btn_index: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging_node = target
				_drag_offset = target.get_local_mouse_position()
				_selected_index = btn_index
				_on_list_item_pressed(btn_index)
			else:
				if _dragging_node == target:
					_save_drag_position(target, btn_index)
					_dragging_node = null

	elif event is InputEventMouseMotion and _dragging_node == target:
		var mouse_pos: Vector2 = buttons_container.get_local_mouse_position()
		target.position = mouse_pos - _drag_offset


func _save_drag_position(target: Control, btn_index: int) -> void:
	if _config == null:
		return
	var buttons: Array = _get_buttons()
	if btn_index < 0 or btn_index >= buttons.size():
		return
	var btn_data: Resource = buttons[btn_index]
	
	var center_pos: Vector2 = target.position + btn_data.size / 2.0
	var norm_pos: Vector2 = center_pos / _project_resolution
	norm_pos = norm_pos.clamp(Vector2.ZERO, Vector2.ONE)
	btn_data.norm_position = norm_pos
	
	_refresh_property_editor()
	settings_changed.emit()
