class_name ScreenSettingsPanel extends Control
## 通用子界面设置面板
## 支持菜单、存档、读档、历史记录、设置等界面的预览和属性编辑
## 顶部：界面类型选择器
## 左侧：SubViewport 预览（与运行时渲染一致）
## 右侧：PropertyEditor

const AVGScreenConfigClass = preload("res://scripts/avg/resources/avg_screen_config.gd")

signal settings_changed()

# =============================================================================
# 子节点引用
# =============================================================================

@onready var type_option: OptionButton = %TypeOption
@onready var preview_area: Control = %PreviewArea
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var preview_root: Control = %PreviewRoot
@onready var background_panel: Panel = %Background
@onready var background_image: TextureRect = %BackgroundImage
@onready var content_panel: Panel = %ContentPanel
@onready var title_label: Label = %TitleLabel
@onready var mock_content: Control = %MockContent
@onready var close_button: Button = %CloseButton
@onready var property_editor: Control = %ScreenPropertyEditor

# =============================================================================
# State
# =============================================================================

var _project: Resource = null
var _project_resolution: Vector2 = Vector2(2560, 1440)
var _current_type: int = 0  # AVGScreenConfig.ScreenType
var _current_config: Resource = null  # AVGScreenConfig

## 拖拽
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
	if type_option:
		_setup_type_options()
		type_option.item_selected.connect(_on_type_selected)
	
	# 拖拽
	if title_label:
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP
		title_label.gui_input.connect(_on_title_gui_input)
	if close_button:
		close_button.mouse_filter = Control.MOUSE_FILTER_STOP
		close_button.gui_input.connect(_on_close_btn_gui_input)
	
	call_deferred("_on_preview_resized")


func _setup_type_options() -> void:
	type_option.clear()
	for key in AVGScreenConfigClass.SCREEN_TYPE_NAMES:
		type_option.add_item(AVGScreenConfigClass.SCREEN_TYPE_NAMES[key], key)


# =============================================================================
# Public API
# =============================================================================

func set_project(project: Resource) -> void:
	_project = project
	if project != null and "resolution" in project:
		_project_resolution = Vector2(project.resolution)
	_update_viewport_size()
	_load_current_config()
	call_deferred("_update_preview")


# =============================================================================
# Type Selection
# =============================================================================

func _on_type_selected(index: int) -> void:
	_current_type = type_option.get_item_id(index)
	_load_current_config()
	_update_preview()


func _load_current_config() -> void:
	if _project == null:
		_current_config = null
		return
	
	var type_key: String = _type_to_key(_current_type)
	if not _project.screen_configs.has(type_key):
		# 自动创建默认配置
		var config: Resource = AVGScreenConfigClass.new()
		config.init_defaults_for_type(_current_type as AVGScreenConfigClass.ScreenType)
		_project.screen_configs[type_key] = config
	
	_current_config = _project.screen_configs[type_key]
	_refresh_property_editor()


func _type_to_key(type: int) -> String:
	match type:
		0: return "menu"
		1: return "save"
		2: return "load"
		3: return "history"
		4: return "settings"
		_: return "menu"


# =============================================================================
# Property Editor
# =============================================================================

func _refresh_property_editor() -> void:
	if property_editor == null or _current_config == null:
		return
	if property_editor.has_method("set_target"):
		property_editor.set_target(_current_config)


func _on_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	_update_preview()
	settings_changed.emit()


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
	if _current_config == null:
		return
	_update_background()
	_update_title()
	_update_content_panel()
	_update_close_button()
	_update_mock_content()


func _update_background() -> void:
	if background_panel:
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = _current_config.background_color
		background_panel.add_theme_stylebox_override("panel", bg_style)
	
	if background_image:
		if not _current_config.background_image.is_empty():
			var tex: Texture2D = StorageManager.load_texture_from_path(_current_config.background_image, _project)
			background_image.texture = tex
			background_image.visible = tex != null
		else:
			background_image.texture = null
			background_image.visible = false


func _update_title() -> void:
	if title_label == null or _current_config == null:
		return
	title_label.text = _current_config.get_display_title()
	title_label.add_theme_font_size_override("font_size", _current_config.title_font_size)
	title_label.add_theme_color_override("font_color", _current_config.title_color)
	
	var label_size := Vector2(_project_resolution.x * 0.5, 80)
	title_label.size = label_size
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var norm_pos: Vector2 = _current_config.title_norm_position
	title_label.position = Vector2(
		norm_pos.x * _project_resolution.x - label_size.x / 2.0,
		norm_pos.y * _project_resolution.y - label_size.y / 2.0
	)


func _update_content_panel() -> void:
	if content_panel == null or _current_config == null:
		return
	
	var panel_size: Vector2 = _current_config.panel_norm_size * _project_resolution
	var panel_pos: Vector2 = Vector2(
		_current_config.panel_norm_position.x * _project_resolution.x - panel_size.x / 2.0,
		_current_config.panel_norm_position.y * _project_resolution.y - panel_size.y / 2.0
	)
	content_panel.position = panel_pos
	content_panel.size = panel_size
	
	if _current_config.panel_style != null and _current_config.panel_style.has_method("to_stylebox"):
		content_panel.add_theme_stylebox_override("panel", _current_config.panel_style.to_stylebox())
	else:
		var default_style := StyleBoxFlat.new()
		default_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		default_style.set_corner_radius_all(8)
		content_panel.add_theme_stylebox_override("panel", default_style)


func _update_close_button() -> void:
	if close_button == null or _current_config == null:
		return
	close_button.text = _current_config.close_button_text
	close_button.custom_minimum_size = _current_config.close_button_size
	close_button.size = _current_config.close_button_size
	close_button.add_theme_font_size_override("font_size", _current_config.close_button_font_size)
	var btn_size: Vector2 = _current_config.close_button_size
	var norm_pos: Vector2 = _current_config.close_button_norm_position
	close_button.position = Vector2(
		norm_pos.x * _project_resolution.x - btn_size.x / 2.0,
		norm_pos.y * _project_resolution.y - btn_size.y / 2.0
	)


# =============================================================================
# Mock Content — 根据界面类型渲染占位内容
# =============================================================================

func _update_mock_content() -> void:
	if mock_content == null or _current_config == null:
		return
	# 清除旧内容
	for child in mock_content.get_children():
		child.queue_free()
	
	# mock_content 与 content_panel 同位置同大小
	mock_content.position = content_panel.position
	mock_content.size = content_panel.size
	mock_content.clip_contents = true
	
	match _current_config.screen_type:
		AVGScreenConfigClass.ScreenType.MENU:
			_build_mock_menu()
		AVGScreenConfigClass.ScreenType.SAVE, AVGScreenConfigClass.ScreenType.LOAD:
			_build_mock_slots()
		AVGScreenConfigClass.ScreenType.HISTORY:
			_build_mock_history()
		AVGScreenConfigClass.ScreenType.SETTINGS:
			_build_mock_settings()


func _build_mock_menu() -> void:
	var container := VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", _current_config.menu_button_spacing)
	
	for text in _current_config.menu_button_texts:
		var btn := Button.new()
		btn.text = text
		btn.custom_minimum_size = _current_config.menu_button_size
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", _current_config.menu_button_font_size)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(btn)
	
	mock_content.add_child(container)


func _build_mock_slots() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	
	var grid := GridContainer.new()
	grid.columns = _current_config.grid_columns
	grid.add_theme_constant_override("h_separation", _current_config.slot_spacing)
	grid.add_theme_constant_override("v_separation", _current_config.slot_spacing)
	
	var visible_slots: int = mini(_current_config.slot_count, 9)
	for i in range(visible_slots):
		var slot := Panel.new()
		slot.custom_minimum_size = _current_config.slot_size
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.2, 0.2, 0.25, 0.8)
		slot_style.set_corner_radius_all(4)
		slot_style.border_color = Color(0.4, 0.4, 0.5, 0.6)
		slot_style.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", slot_style)
		
		var label := Label.new()
		label.text = "槽位 %d" % (i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(slot)
	
	margin.add_child(grid)
	mock_content.add_child(margin)


func _build_mock_history() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 20)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _current_config.history_entry_spacing)
	
	var sample_entries: Array[Dictionary] = [
		{"speaker": "角色A", "text": "这是第一条历史对话记录。"},
		{"speaker": "", "text": "（这是一段旁白文本。）"},
		{"speaker": "角色B", "text": "这是第二条历史对话记录，内容稍长一些。"},
		{"speaker": "角色A", "text": "好的，我明白了。"},
	]
	
	for entry in sample_entries:
		var entry_vbox := VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 2)
		
		if not entry["speaker"].is_empty():
			var speaker_label := Label.new()
			speaker_label.text = entry["speaker"]
			speaker_label.add_theme_font_size_override("font_size", _current_config.history_entry_font_size)
			speaker_label.add_theme_color_override("font_color", _current_config.history_speaker_color)
			speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry_vbox.add_child(speaker_label)
		
		var text_label := Label.new()
		text_label.text = entry["text"]
		text_label.add_theme_font_size_override("font_size", _current_config.history_entry_font_size)
		text_label.add_theme_color_override("font_color", Color.WHITE)
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(text_label)
		
		# 分隔线
		var sep := HSeparator.new()
		sep.modulate = Color(1, 1, 1, 0.2)
		entry_vbox.add_child(sep)
		
		entry_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(entry_vbox)
	
	margin.add_child(vbox)
	mock_content.add_child(margin)


func _build_mock_settings() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	
	var settings_items: Array[Dictionary] = [
		{"label": "BGM 音量", "type": "slider"},
		{"label": "SE 音量", "type": "slider"},
		{"label": "文字速度", "type": "slider"},
		{"label": "自动播放速度", "type": "slider"},
		{"label": "全屏模式", "type": "toggle"},
	]
	
	for item in settings_items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		
		var label := Label.new()
		label.text = item["label"]
		label.custom_minimum_size.x = 200
		label.add_theme_color_override("font_color", Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		
		if item["type"] == "slider":
			var slider := HSlider.new()
			slider.min_value = 0
			slider.max_value = 100
			slider.value = 70
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(slider)
		else:
			var toggle := CheckButton.new()
			toggle.button_pressed = true
			toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(toggle)
		
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)
	
	margin.add_child(vbox)
	mock_content.add_child(margin)


# =============================================================================
# Drag — 标题和关闭按钮可拖拽
# =============================================================================

func _on_title_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event, title_label, "title_norm_position", title_label.size if title_label else Vector2.ZERO)


func _on_close_btn_gui_input(event: InputEvent) -> void:
	_handle_drag_input(event, close_button, "close_button_norm_position", _current_config.close_button_size if _current_config else Vector2.ZERO)


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
	if _current_config == null:
		return
	var center_pos: Vector2 = target.position + element_size / 2.0
	var norm_pos: Vector2 = center_pos / _project_resolution
	norm_pos = norm_pos.clamp(Vector2.ZERO, Vector2.ONE)
	_current_config.set(config_prop, norm_pos)
	_refresh_property_editor()
	settings_changed.emit()
