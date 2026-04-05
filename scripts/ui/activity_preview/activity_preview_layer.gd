class_name ActivityPreviewLayer
extends Control

const ActivityPreviewFormatterClass = preload("res://scripts/ui/activity_preview/activity_preview_formatter.gd")
const LAYER_SCENE: PackedScene = preload("res://scenes/ui/activity_preview/activity_preview_layer.tscn")
const PSEUDO_OS_LIGHT_THEME: Theme = preload("res://resources/themes/pseudo_os_light.tres")
const CURSOR_OFFSET := Vector2(18, 18)
const SCREEN_MARGIN := 12.0

var _panel: PanelContainer = null
var _panel_style: StyleBoxFlat = null
var _title_label: Label = null
var _body_label: Label = null
var _current_source: Control = null


static func ensure_for(host: Control) -> Control:
	if host == null:
		return null

	var existing := host.get_node_or_null("ActivityPreviewLayer")
	if existing != null:
		return existing

	var layer := LAYER_SCENE.instantiate() as Control
	if layer == null:
		return null

	host.add_child(layer)
	host.move_child(layer, host.get_child_count() - 1)
	return layer


func _ready() -> void:
	name = "ActivityPreviewLayer"
	theme = PSEUDO_OS_LIGHT_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 4096
	_build_ui()
	hide_preview()


func _process(_delta: float) -> void:
	if _current_source == null or not is_instance_valid(_current_source) or not _current_source.is_visible_in_tree():
		hide_preview()
		return
	_position_panel()


func show_preview(source: Control, payload: Dictionary) -> void:
	if source == null:
		return

	var lines: Array[String] = ActivityPreviewFormatterClass.build_lines(payload)
	var title: String = str(payload.get("title", "")).strip_edges()
	if title.is_empty() and lines.is_empty():
		hide_preview()
		return

	_current_source = source
	_title_label.text = title
	_title_label.visible = not title.is_empty()
	_body_label.text = "\n".join(lines)
	_apply_accent(payload)

	visible = true
	_panel.visible = true
	set_process(true)
	_panel.reset_size()
	_position_panel()


func hide_preview(source: Control = null) -> void:
	if source != null and source != _current_source:
		return

	_current_source = null
	visible = false
	_panel.visible = false
	set_process(false)


func get_current_title() -> String:
	return _title_label.text if _title_label != null else ""


func get_current_body() -> String:
	return _body_label.text if _body_label != null else ""


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.982, 0.986, 0.993, 0.98)
	_panel_style.border_color = Color(0.886, 0.894, 0.918, 1.0)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(10)
	_panel_style.content_margin_left = 12
	_panel_style.content_margin_top = 10
	_panel_style.content_margin_right = 12
	_panel_style.content_margin_bottom = 10
	_panel_style.shadow_color = Color(0, 0, 0, 0.12)
	_panel_style.shadow_size = 6
	_panel_style.shadow_offset = Vector2(0, 2)
	_panel.add_theme_stylebox_override("panel", _panel_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.102, 0.114, 0.153, 1.0))
	box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(220, 0)
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", Color(0.42, 0.439, 0.525, 1.0))
	box.add_child(_body_label)


func _apply_accent(payload: Dictionary) -> void:
	var accent: Variant = payload.get("accent_color", Color(0, 0, 0, 0))
	if accent is Color and (accent as Color).a > 0.0:
		var border_color: Color = accent as Color
		border_color.a = 0.75
		_panel_style.border_color = border_color
	else:
		_panel_style.border_color = Color(0.886, 0.894, 0.918, 1.0)
	_panel.add_theme_stylebox_override("panel", _panel_style)


func _position_panel() -> void:
	var panel_size: Vector2 = _panel.size
	if panel_size == Vector2.ZERO:
		panel_size = _panel.get_combined_minimum_size()

	var local_mouse: Vector2 = get_local_mouse_position()
	var target_pos: Vector2 = local_mouse + CURSOR_OFFSET

	if target_pos.x + panel_size.x > size.x - SCREEN_MARGIN:
		target_pos.x = local_mouse.x - panel_size.x - CURSOR_OFFSET.x
	if target_pos.y + panel_size.y > size.y - SCREEN_MARGIN:
		target_pos.y = local_mouse.y - panel_size.y - CURSOR_OFFSET.y

	target_pos.x = clampf(target_pos.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, size.x - panel_size.x - SCREEN_MARGIN))
	target_pos.y = clampf(target_pos.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, size.y - panel_size.y - SCREEN_MARGIN))
	_panel.position = target_pos
