class_name CharacterListPanel extends VBoxContainer
## Character List Panel
## 三栏布局: 左=角色槽位列表, 中=属性+表情列表, 右=立绘预览
## 表情图片从资源库选择，存储为相对路径字符串

signal character_selected(character: Resource)

const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")
const DEFAULT_MAX_SLOTS: int = 100

var _project: Resource = null
var _project_root_override: String = ""
var _selected_slot: int = -1
var _max_slots: int = DEFAULT_MAX_SLOTS
## 当前选中的表情名称
var _selected_expression: String = ""

# UI — _ready 中通过 %UniqueNode 获取
@onready var clear_button: Button = %DeleteButton
@onready var character_list: ItemList = %CharacterList
@onready var property_editor: Control = %PropertyEditor
@onready var expression_list: ItemList = %ExpressionList
@onready var add_expression_button: Button = %AddExpressionButton
@onready var remove_expression_button: Button = %RemoveExpressionButton
@onready var expression_name_input: LineEdit = %ExpressionNameInput
@onready var select_image_button: Button = %SelectImageButton
@onready var preview_texture: TextureRect = %PreviewTexture
@onready var preview_info_label: Label = %PreviewInfoLabel
# 显示调整控件
@onready var scale_slider: HSlider = %ScaleSlider
@onready var scale_value_label: Label = %ScaleValue
@onready var offset_x_slider: HSlider = %OffsetXSlider
@onready var offset_x_value_label: Label = %OffsetXValue
@onready var offset_y_slider: HSlider = %OffsetYSlider
@onready var offset_y_value_label: Label = %OffsetYValue
@onready var reset_display_button: Button = %ResetDisplayButton
# 资源选择器弹窗
@onready var resource_picker_dialog: Window = %ResourcePickerDialog
var _resource_picker_panel: Control = null


func _ready() -> void:
	_setup_connections()
	_setup_resource_picker()


func _setup_connections() -> void:
	if clear_button:
		clear_button.text = "清空"
		clear_button.pressed.connect(_on_clear_pressed)
	if character_list:
		character_list.item_selected.connect(_on_item_selected)
	if add_expression_button:
		add_expression_button.pressed.connect(_on_add_expression_pressed)
	if remove_expression_button:
		remove_expression_button.pressed.connect(_on_remove_expression_pressed)
	if expression_list:
		expression_list.item_selected.connect(_on_expression_selected)
	if select_image_button:
		select_image_button.pressed.connect(_on_select_image_pressed)
	if scale_slider:
		scale_slider.value_changed.connect(_on_scale_changed)
	if offset_x_slider:
		offset_x_slider.value_changed.connect(_on_offset_x_changed)
	if offset_y_slider:
		offset_y_slider.value_changed.connect(_on_offset_y_changed)
	if reset_display_button:
		reset_display_button.pressed.connect(_on_reset_display_pressed)


func _setup_resource_picker() -> void:
	if resource_picker_dialog == null:
		return
	# 从场景实例化 ResourceLibraryPanel（包含完整 UI 节点树）
	var scene: PackedScene = load("res://scenes/apps/project_manager/resource_library_panel.tscn")
	if scene == null:
		push_warning("CharacterListPanel: Failed to load resource_library_panel.tscn")
		return
	_resource_picker_panel = scene.instantiate()
	_resource_picker_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_picker_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 弹窗内容布局
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	resource_picker_dialog.add_child(vbox)

	vbox.add_child(_resource_picker_panel)

	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.pressed.connect(_on_resource_picker_ok)
	btn_bar.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_on_resource_picker_cancel)
	btn_bar.add_child(cancel_btn)
	vbox.add_child(btn_bar)

	resource_picker_dialog.close_requested.connect(_on_resource_picker_cancel)


# =============================================================================
# Public API
# =============================================================================

func set_project(project: Resource) -> void:
	_project = project
	_project_root_override = _resolve_project_root(project)
	_selected_slot = -1
	_selected_expression = ""
	_refresh_list()
	_clear_property_editor()
	_clear_expression_list()
	_clear_preview()


func get_project() -> Resource:
	return _project


func set_project_root(project_root: String) -> void:
	_project_root_override = project_root.strip_edges()


func get_character_by_slot(slot: int) -> Resource:
	if _project == null:
		return null
	var char_id: String = AVGCharacterClass.make_id(slot)
	for c in _project.characters:
		if c.character_id == char_id:
			return c
	return null


func get_selected_character() -> Resource:
	if _selected_slot < 1:
		return null
	return get_character_by_slot(_selected_slot)


# =============================================================================
# Character Slot List (Left Column)
# =============================================================================

func _refresh_list() -> void:
	if character_list == null:
		return
	character_list.clear()
	if _project == null:
		_update_buttons()
		return

	for slot in range(1, _max_slots + 1):
		var char_id: String = AVGCharacterClass.make_id(slot)
		var character: Resource = get_character_by_slot(slot)
		var display_text: String
		if character != null:
			var name_part: String = character.character_name
			if character.display_name != "" and character.display_name != character.character_name:
				name_part = "%s(%s)" % [character.character_name, character.display_name]
			display_text = "%s: %s" % [char_id, name_part]
		else:
			display_text = "%s: (空)" % char_id
		character_list.add_item(display_text)
		if character == null:
			character_list.set_item_custom_fg_color(slot - 1, Color(0.5, 0.5, 0.5))

	if _selected_slot >= 1 and _selected_slot <= _max_slots:
		character_list.select(_selected_slot - 1)
	_update_buttons()


func _on_item_selected(index: int) -> void:
	_selected_slot = index + 1
	_selected_expression = ""
	var character: Resource = get_selected_character()
	if character == null:
		_create_character_at_slot(_selected_slot)
		character = get_selected_character()
	if character:
		if property_editor and property_editor.has_method("set_target"):
			property_editor.set_target(character)
		_refresh_expression_list()
		_update_preview_for_expression()
		_update_display_tuning_sliders()
		character_selected.emit(character)
	_update_buttons()


func _create_character_at_slot(slot: int) -> void:
	if _project == null:
		return
	var new_char: Resource = AVGCharacterClass.new()
	new_char.character_id = AVGCharacterClass.make_id(slot)
	new_char.character_name = "角色%03d" % slot
	new_char.display_name = ""
	new_char.sprites = {"default": ""}
	_project.characters.append(new_char)
	_refresh_list()
	if character_list and slot >= 1 and slot <= _max_slots:
		character_list.select(slot - 1)


func _on_clear_pressed() -> void:
	if _project == null or _selected_slot < 1:
		return
	var character: Resource = get_selected_character()
	if character == null:
		return
	var idx: int = _project.characters.find(character)
	if idx >= 0:
		_project.characters.remove_at(idx)
	_selected_expression = ""
	_refresh_list()
	_clear_property_editor()
	_clear_expression_list()
	_clear_preview()
	_update_buttons()
	StorageManager.notify_content_changed()


# =============================================================================
# Expression List (Middle Column)
# =============================================================================

func _refresh_expression_list() -> void:
	if expression_list == null:
		return
	expression_list.clear()
	var character: Resource = get_selected_character()
	if character == null:
		return

	for expr_name in character.sprites.keys():
		var sprite_path: String = character.sprites[expr_name]
		# 尝试加载缩略图
		var icon: Texture2D = null
		if sprite_path is String and not sprite_path.is_empty():
			icon = StorageManager.load_texture_from_path(sprite_path, _project, _project_root_override)
		if icon:
			expression_list.add_item(expr_name, icon)
		else:
			expression_list.add_item(expr_name)

	# 恢复选中
	if not _selected_expression.is_empty():
		var keys: Array = character.sprites.keys()
		var idx: int = keys.find(_selected_expression)
		if idx >= 0:
			expression_list.select(idx)
	_update_buttons()


func _on_expression_selected(index: int) -> void:
	var character: Resource = get_selected_character()
	if character == null:
		return
	var keys: Array = character.sprites.keys()
	if index >= 0 and index < keys.size():
		_selected_expression = keys[index]
	else:
		_selected_expression = ""
	_update_preview_for_expression()
	_update_buttons()


func _on_add_expression_pressed() -> void:
	var character: Resource = get_selected_character()
	if character == null:
		return
	var expr_name: String = ""
	if expression_name_input:
		expr_name = expression_name_input.text.strip_edges()
		expression_name_input.text = ""
	if expr_name.is_empty():
		expr_name = "expression_%d" % character.sprites.size()
	# 避免重名
	if character.sprites.has(expr_name):
		var counter: int = 2
		while character.sprites.has("%s_%d" % [expr_name, counter]):
			counter += 1
		expr_name = "%s_%d" % [expr_name, counter]
	character.sprites[expr_name] = ""
	_selected_expression = expr_name
	_refresh_expression_list()
	_update_preview_for_expression()
	StorageManager.notify_content_changed()


func _on_remove_expression_pressed() -> void:
	var character: Resource = get_selected_character()
	if character == null or _selected_expression.is_empty():
		return
	if character.sprites.size() <= 1:
		return  # 至少保留一个表情
	character.sprites.erase(_selected_expression)
	_selected_expression = ""
	_refresh_expression_list()
	_clear_preview()
	_update_buttons()
	StorageManager.notify_content_changed()


# =============================================================================
# Image Selection (Resource Picker)
# =============================================================================

func _on_select_image_pressed() -> void:
	var character: Resource = get_selected_character()
	if character == null or _selected_expression.is_empty():
		return
	if resource_picker_dialog == null:
		return
	# 初始化资源库面板
	if _resource_picker_panel and _resource_picker_panel.has_method("set_project"):
		_resource_picker_panel.set_project(_project)
	if _resource_picker_panel and _resource_picker_panel.has_method("set_project_root"):
		_resource_picker_panel.set_project_root(_project_root_override)
	resource_picker_dialog.popup_centered(Vector2i(700, 500))


func _on_resource_picker_ok() -> void:
	if _resource_picker_panel == null:
		_on_resource_picker_cancel()
		return
	var selected_path: String = ""
	if _resource_picker_panel.has_method("get_selected_path"):
		selected_path = _resource_picker_panel.get_selected_path()
	if selected_path.is_empty():
		_on_resource_picker_cancel()
		return
	# 检查是否是图片
	var ext: String = selected_path.get_extension().to_lower()
	if StorageManager.get_file_category(ext) != "image":
		push_warning("CharacterListPanel: Selected file is not an image")
		return
	# 设置到当前表情
	var character: Resource = get_selected_character()
	if character and not _selected_expression.is_empty():
		character.sprites[_selected_expression] = selected_path
		_refresh_expression_list()
		_update_preview_for_expression()
		StorageManager.notify_content_changed()
	if resource_picker_dialog:
		resource_picker_dialog.hide()


func _on_resource_picker_cancel() -> void:
	if resource_picker_dialog:
		resource_picker_dialog.hide()


# =============================================================================
# Preview (Right Column)
# =============================================================================

func _clear_preview() -> void:
	if preview_texture:
		preview_texture.texture = null
		preview_texture.pivot_offset = Vector2.ZERO
		preview_texture.scale = Vector2.ONE
		preview_texture.position = Vector2.ZERO
	if preview_info_label:
		preview_info_label.text = ""
	_reset_display_sliders_ui()


func _update_preview_for_expression() -> void:
	var character: Resource = get_selected_character()
	if character == null or _selected_expression.is_empty():
		_clear_preview()
		return

	var sprite_path: String = character.sprites.get(_selected_expression, "")
	if preview_info_label:
		var char_name: String = character.display_name if character.display_name != "" else character.character_name
		preview_info_label.text = "%s\n表情: %s" % [char_name, _selected_expression]

	if sprite_path is String and not sprite_path.is_empty():
		var tex: Texture2D = StorageManager.load_texture_from_path(sprite_path, _project, _project_root_override)
		if preview_texture:
			preview_texture.texture = tex
	else:
		if preview_texture:
			preview_texture.texture = null


# =============================================================================
# Helpers
# =============================================================================

func _clear_property_editor() -> void:
	if property_editor and property_editor.has_method("set_target"):
		property_editor.set_target(null)


func _clear_expression_list() -> void:
	if expression_list:
		expression_list.clear()
	_selected_expression = ""


func _update_buttons() -> void:
	var has_char: bool = get_selected_character() != null
	var has_expr: bool = not _selected_expression.is_empty()
	if clear_button:
		clear_button.disabled = not has_char
	if add_expression_button:
		add_expression_button.disabled = not has_char
	if remove_expression_button:
		remove_expression_button.disabled = not has_expr
	if select_image_button:
		select_image_button.disabled = not has_expr
	if reset_display_button:
		reset_display_button.disabled = not has_char


# =============================================================================
# Display Tuning (Offset / Scale)
# =============================================================================

## 更新显示调整滑块为当前角色的值
func _update_display_tuning_sliders() -> void:
	var character: Resource = get_selected_character()
	if character == null:
		_reset_display_sliders_ui()
		return
	var ds: float = character.display_scale if "display_scale" in character else 1.0
	var do_vec: Vector2 = character.display_offset if "display_offset" in character else Vector2.ZERO
	if scale_slider:
		scale_slider.set_value_no_signal(ds)
	if scale_value_label:
		scale_value_label.text = "%.2f" % ds
	if offset_x_slider:
		offset_x_slider.set_value_no_signal(do_vec.x)
	if offset_x_value_label:
		offset_x_value_label.text = "%.2f" % do_vec.x
	if offset_y_slider:
		offset_y_slider.set_value_no_signal(do_vec.y)
	if offset_y_value_label:
		offset_y_value_label.text = "%.2f" % do_vec.y
	_apply_display_tuning_preview(ds, do_vec)


func _reset_display_sliders_ui() -> void:
	if scale_slider:
		scale_slider.set_value_no_signal(1.0)
	if scale_value_label:
		scale_value_label.text = "1.00"
	if offset_x_slider:
		offset_x_slider.set_value_no_signal(0.0)
	if offset_x_value_label:
		offset_x_value_label.text = "0.00"
	if offset_y_slider:
		offset_y_slider.set_value_no_signal(0.0)
	if offset_y_value_label:
		offset_y_value_label.text = "0.00"
	if preview_texture:
		preview_texture.pivot_offset = Vector2.ZERO
		preview_texture.scale = Vector2.ONE
		preview_texture.position = Vector2.ZERO


func _on_scale_changed(value: float) -> void:
	var character: Resource = get_selected_character()
	if character == null:
		return
	character.display_scale = value
	if scale_value_label:
		scale_value_label.text = "%.2f" % value
	var offset: Vector2 = character.display_offset if "display_offset" in character else Vector2.ZERO
	_apply_display_tuning_preview(value, offset)
	StorageManager.notify_content_changed()


func _on_offset_x_changed(value: float) -> void:
	var character: Resource = get_selected_character()
	if character == null:
		return
	character.display_offset.x = value
	if offset_x_value_label:
		offset_x_value_label.text = "%.2f" % value
	var ds: float = character.display_scale if "display_scale" in character else 1.0
	_apply_display_tuning_preview(ds, character.display_offset)
	StorageManager.notify_content_changed()


func _on_offset_y_changed(value: float) -> void:
	var character: Resource = get_selected_character()
	if character == null:
		return
	character.display_offset.y = value
	if offset_y_value_label:
		offset_y_value_label.text = "%.2f" % value
	var ds: float = character.display_scale if "display_scale" in character else 1.0
	_apply_display_tuning_preview(ds, character.display_offset)
	StorageManager.notify_content_changed()


func _on_reset_display_pressed() -> void:
	var character: Resource = get_selected_character()
	if character == null:
		return
	character.display_scale = 1.0
	character.display_offset = Vector2.ZERO
	_update_display_tuning_sliders()
	StorageManager.notify_content_changed()


## 在预览区域近似展示 offset/scale 效果
func _apply_display_tuning_preview(ds: float, offset: Vector2) -> void:
	if preview_texture == null:
		return
	# 使用缩放和位移近似展示效果
	preview_texture.pivot_offset = preview_texture.size / 2.0
	preview_texture.scale = Vector2(ds, ds)
	# offset 映射到预览区域的像素偏移（预览区域宽度的比例）
	var parent_size: Vector2 = preview_texture.get_parent_area_size()
	preview_texture.position = Vector2(offset.x * parent_size.x, offset.y * parent_size.y)


func _resolve_project_root(project: Resource) -> String:
	if project != null and "project_root_path" in project:
		return str(project.get("project_root_path")).strip_edges()
	return ""
