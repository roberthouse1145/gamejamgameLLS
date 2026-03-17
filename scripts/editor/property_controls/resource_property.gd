class_name ResourceProperty extends VBoxContainer
## Resource Property Control
## Supports three modes:
## 1. TEXTURE — Texture2D picker with preview
## 2. AUDIO — AudioStream picker with play button
## 3. GENERIC — Load/Clear for generic resources
## 4. SUB_RESOURCE — Inline expandable sub-resource with PropertyEditor

signal value_changed(new_value: Resource)

enum ResourceType {
	GENERIC,
	TEXTURE,
	AUDIO,
	SUB_RESOURCE
}

@export var property_name: String = ""
@export var label_text: String = ""
@export var resource_type: ResourceType = ResourceType.GENERIC
@export var description: String = ""

## For SUB_RESOURCE mode: the script class to instantiate when creating new
var sub_resource_script: Script = null

var _label: Label
var _preview_rect: TextureRect
var _path_label: Label
var _load_button: Button
var _clear_button: Button
var _play_button: Button
var _audio_player: AudioStreamPlayer
var _current_value: Resource = null
var _editable: bool = true

# Resource picker dialog (shared by TEXTURE and AUDIO)
var _picker_dialog: Window = null
var _picker_panel: Control = null  # ResourceLibraryPanel instance

# Sub-resource inline editing
var _header_container: HBoxContainer
var _toggle_button: Button
var _create_button: Button
var _clear_sub_button: Button
var _sub_editor_container: VBoxContainer
var _sub_editor: Control  # PropertyEditor instance
var _expanded: bool = true


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	match resource_type:
		ResourceType.TEXTURE:
			_setup_texture_ui()
		ResourceType.AUDIO:
			_setup_audio_ui()
		ResourceType.SUB_RESOURCE:
			_setup_sub_resource_ui()
		_:
			_setup_generic_ui()


# =============================================================================
# SUB_RESOURCE mode
# =============================================================================

func _setup_sub_resource_ui() -> void:
	# Header row: label + toggle + create/clear
	_header_container = HBoxContainer.new()
	_header_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_header_container)

	_toggle_button = Button.new()
	_toggle_button.text = "v " if _expanded else "> "
	_toggle_button.custom_minimum_size.x = 24
	_toggle_button.flat = true
	_toggle_button.pressed.connect(_on_toggle_expand)
	_header_container.add_child(_toggle_button)

	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if description != "":
		_label.tooltip_text = description
	_header_container.add_child(_label)

	_create_button = Button.new()
	_create_button.text = "新建"
	_create_button.pressed.connect(_on_create_sub_resource)
	_header_container.add_child(_create_button)

	_clear_sub_button = Button.new()
	_clear_sub_button.text = "清除"
	_clear_sub_button.pressed.connect(_on_clear_sub_resource)
	_header_container.add_child(_clear_sub_button)

	# Container for inline PropertyEditor
	_sub_editor_container = VBoxContainer.new()
	_sub_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Indent the sub-editor
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	add_child(margin)
	margin.add_child(_sub_editor_container)

	_refresh_sub_resource_ui()


func _on_toggle_expand() -> void:
	_expanded = not _expanded
	if _toggle_button:
		_toggle_button.text = "v " if _expanded else "> "
	if _sub_editor_container:
		_sub_editor_container.visible = _expanded


func _on_create_sub_resource() -> void:
	if sub_resource_script != null:
		var new_res: Resource = sub_resource_script.new()
		set_value(new_res)
		value_changed.emit(_current_value)
	else:
		set_value(Resource.new())
		value_changed.emit(_current_value)


func _on_clear_sub_resource() -> void:
	set_value(null)
	value_changed.emit(_current_value)


func _refresh_sub_resource_ui() -> void:
	if _sub_editor_container == null:
		return

	# Clear old editor
	for child in _sub_editor_container.get_children():
		child.queue_free()
	_sub_editor = null
	_stylebox_preview = null

	if _current_value == null:
		var hint_label := Label.new()
		hint_label.text = "(null)"
		hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_sub_editor_container.add_child(hint_label)
		if _create_button:
			_create_button.visible = true
		if _clear_sub_button:
			_clear_sub_button.visible = false
		return

	if _create_button:
		_create_button.visible = false
	if _clear_sub_button:
		_clear_sub_button.visible = true

	# Check if resource has get_avg_properties
	var has_props: bool = false
	if _current_value.has_method("get_avg_properties"):
		has_props = true
	else:
		var script = _current_value.get_script()
		if script != null and script.has_method("get_avg_properties"):
			has_props = true

	if has_props:
		# Create inline PropertyEditor
		var PropertyEditorScript = load("res://scripts/editor/property_editor.gd")
		_sub_editor = PropertyEditorScript.new()
		_sub_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sub_editor_container.add_child(_sub_editor)
		_sub_editor.set_target(_current_value)
		_sub_editor.property_changed.connect(_on_sub_property_changed)

		# AVGStyleBox preview: show a small PanelContainer with the generated stylebox
		if _current_value.has_method("to_stylebox"):
			_create_stylebox_preview()
	else:
		var info_label := Label.new()
		info_label.text = _current_value.get_class()
		_sub_editor_container.add_child(info_label)

	_sub_editor_container.visible = _expanded


func _on_sub_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	# Bubble up — the sub-resource was modified in place
	value_changed.emit(_current_value)
	# Update stylebox preview if present
	_update_stylebox_preview()


## StyleBox preview panel (for AVGStyleBox sub-resources)
var _stylebox_preview: PanelContainer = null


## Create a small preview showing the generated StyleBox
func _create_stylebox_preview() -> void:
	if _sub_editor_container == null or _current_value == null:
		return
	_stylebox_preview = PanelContainer.new()
	_stylebox_preview.custom_minimum_size = Vector2(0, 48)
	_stylebox_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBox = _current_value.to_stylebox()
	_stylebox_preview.add_theme_stylebox_override("panel", sb)
	# Add a hint label inside
	var hint := Label.new()
	hint.text = "StyleBox Preview"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 12)
	_stylebox_preview.add_child(hint)
	# Insert preview before the sub-editor
	_sub_editor_container.add_child(_stylebox_preview)
	_sub_editor_container.move_child(_stylebox_preview, 0)


## Update the stylebox preview after property changes
func _update_stylebox_preview() -> void:
	if _stylebox_preview == null or _current_value == null:
		return
	if not _current_value.has_method("to_stylebox"):
		return
	var sb: StyleBox = _current_value.to_stylebox()
	_stylebox_preview.add_theme_stylebox_override("panel", sb)


# =============================================================================
# TEXTURE mode
# =============================================================================

func _setup_texture_ui() -> void:
	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	if description != "":
		_label.tooltip_text = description
	add_child(_label)

	var preview_container := HBoxContainer.new()
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(preview_container)

	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(64, 64)
	_preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_container.add_child(_preview_rect)

	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container.add_child(buttons)

	_path_label = Label.new()
	_path_label.text = "No texture"
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	buttons.add_child(_path_label)

	var button_row := HBoxContainer.new()
	buttons.add_child(button_row)

	_load_button = Button.new()
	_load_button.text = "选择"
	_load_button.pressed.connect(_on_load_pressed)
	button_row.add_child(_load_button)

	_clear_button = Button.new()
	_clear_button.text = "清除"
	_clear_button.pressed.connect(_on_clear_pressed)
	button_row.add_child(_clear_button)

	_update_texture_preview()


# =============================================================================
# AUDIO mode
# =============================================================================

func _setup_audio_ui() -> void:
	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	if description != "":
		_label.tooltip_text = description
	add_child(_label)

	var audio_container := HBoxContainer.new()
	audio_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(audio_container)

	_path_label = Label.new()
	_path_label.text = "No audio"
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	audio_container.add_child(_path_label)

	_play_button = Button.new()
	_play_button.text = "播放"
	_play_button.custom_minimum_size.x = 40
	_play_button.pressed.connect(_on_play_pressed)
	audio_container.add_child(_play_button)

	_load_button = Button.new()
	_load_button.text = "选择"
	_load_button.pressed.connect(_on_load_pressed)
	audio_container.add_child(_load_button)

	_clear_button = Button.new()
	_clear_button.text = "清除"
	_clear_button.pressed.connect(_on_clear_pressed)
	audio_container.add_child(_clear_button)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	_update_audio_preview()


# =============================================================================
# GENERIC mode
# =============================================================================

func _setup_generic_ui() -> void:
	_label = Label.new()
	_label.text = label_text if label_text != "" else property_name.capitalize()
	if description != "":
		_label.tooltip_text = description
	add_child(_label)

	var container := HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(container)

	_path_label = Label.new()
	_path_label.text = "No resource"
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	container.add_child(_path_label)

	_load_button = Button.new()
	_load_button.text = "选择"
	_load_button.pressed.connect(_on_load_pressed)
	container.add_child(_load_button)

	_clear_button = Button.new()
	_clear_button.text = "清除"
	_clear_button.pressed.connect(_on_clear_pressed)
	container.add_child(_clear_button)


# =============================================================================
# Resource Picker Dialog (TEXTURE / AUDIO — uses ResourceLibraryPanel)
# =============================================================================

func _ensure_picker_dialog() -> void:
	if _picker_dialog != null:
		return
	_picker_dialog = Window.new()
	_picker_dialog.title = "选择资源"
	_picker_dialog.size = Vector2i(700, 500)
	_picker_dialog.exclusive = true
	_picker_dialog.unresizable = false
	_picker_dialog.min_size = Vector2i(500, 350)

	var scene: PackedScene = load("res://scenes/apps/project_manager/resource_library_panel.tscn")
	if scene == null:
		push_warning("ResourceProperty: Failed to load resource_library_panel.tscn")
		return
	_picker_panel = scene.instantiate()
	_picker_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	_picker_dialog.add_child(vbox)
	vbox.add_child(_picker_panel)

	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.pressed.connect(_on_picker_ok)
	btn_bar.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_on_picker_cancel)
	btn_bar.add_child(cancel_btn)
	vbox.add_child(btn_bar)

	_picker_dialog.close_requested.connect(_on_picker_cancel)
	add_child(_picker_dialog)


func _on_load_pressed() -> void:
	_ensure_picker_dialog()
	if _picker_panel and _picker_panel.has_method("set_project"):
		var project: Resource = StorageManager.current_project
		# 设置文件类型过滤
		match resource_type:
			ResourceType.TEXTURE:
				_picker_panel.filter_category = "image"
			ResourceType.AUDIO:
				_picker_panel.filter_category = "audio"
			_:
				_picker_panel.filter_category = ""
		_picker_panel.set_project(project)
	if _picker_dialog:
		_picker_dialog.popup_centered(Vector2i(700, 500))


func _on_picker_ok() -> void:
	if _picker_panel == null:
		_on_picker_cancel()
		return
	var selected_path: String = ""
	if _picker_panel.has_method("get_selected_path"):
		selected_path = _picker_panel.get_selected_path()
	if selected_path.is_empty():
		_on_picker_cancel()
		return

	var ext: String = selected_path.get_extension().to_lower()
	var category: String = StorageManager.get_file_category(ext)

	# 验证文件类型匹配
	match resource_type:
		ResourceType.TEXTURE:
			if category != "image":
				push_warning("ResourceProperty: Selected file is not an image")
				return
			var tex: Texture2D = StorageManager.load_texture_from_path(selected_path)
			if tex != null:
				set_value(tex)
				value_changed.emit(_current_value)
		ResourceType.AUDIO:
			if category != "audio":
				push_warning("ResourceProperty: Selected file is not audio")
				return
			var audio: AudioStream = StorageManager.load_audio_from_path(selected_path)
			if audio != null:
				set_value(audio)
				value_changed.emit(_current_value)
		_:
			var res: Resource = load(selected_path)
			if res != null:
				set_value(res)
				value_changed.emit(_current_value)

	if _picker_dialog:
		_picker_dialog.hide()


func _on_picker_cancel() -> void:
	if _picker_dialog:
		_picker_dialog.hide()


func _on_clear_pressed() -> void:
	set_value(null)
	value_changed.emit(_current_value)


func _on_play_pressed() -> void:
	if _audio_player == null or _current_value == null:
		return
	if _audio_player.playing:
		_audio_player.stop()
		_play_button.text = "播放"
	else:
		_audio_player.stream = _current_value as AudioStream
		_audio_player.play()
		_play_button.text = "停止"
		_audio_player.finished.connect(_on_audio_finished, CONNECT_ONE_SHOT)


func _on_audio_finished() -> void:
	if _play_button != null:
		_play_button.text = "播放"


# =============================================================================
# Preview updates
# =============================================================================

func _update_texture_preview() -> void:
	if _preview_rect == null:
		return
	if _current_value != null and _current_value is Texture2D:
		_preview_rect.texture = _current_value
		_path_label.text = _current_value.resource_path.get_file()
	else:
		_preview_rect.texture = null
		_path_label.text = "No texture"


func _update_audio_preview() -> void:
	if _path_label == null:
		return
	if _current_value != null and _current_value is AudioStream:
		_path_label.text = _current_value.resource_path.get_file()
		if _play_button != null:
			_play_button.disabled = false
	else:
		_path_label.text = "No audio"
		if _play_button != null:
			_play_button.disabled = true


func _update_generic_preview() -> void:
	if _path_label == null:
		return
	if _current_value != null:
		_path_label.text = _current_value.resource_path.get_file()
	else:
		_path_label.text = "No resource"


# =============================================================================
# Public API
# =============================================================================

func set_value(value: Variant) -> void:
	_current_value = value as Resource
	match resource_type:
		ResourceType.TEXTURE:
			_update_texture_preview()
		ResourceType.AUDIO:
			_update_audio_preview()
		ResourceType.SUB_RESOURCE:
			_refresh_sub_resource_ui()
		_:
			_update_generic_preview()


func get_value() -> Resource:
	return _current_value


func set_editable(editable: bool) -> void:
	_editable = editable
	if _load_button != null:
		_load_button.disabled = not _editable
	if _clear_button != null:
		_clear_button.disabled = not _editable


func is_editable() -> bool:
	return _editable
