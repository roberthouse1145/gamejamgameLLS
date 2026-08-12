class_name DesktopNotificationCenter extends Control
## 桌面系统通知视图。Desktop 只负责转发通知请求，不持有 Toast 的构建和生命周期。

const UIIconLibraryClass = preload("res://scripts/ui/ui_icon_library.gd")

@onready var notification_stack: VBoxContainer = %NotificationStack

var _notifications: Dictionary = {}
var _app_manager: Node = null


func _ready() -> void:
	_app_manager = get_node_or_null("/root/AppManager")


func show_notification(
	title: String,
	body: String,
	icon_token: String = "warning",
	duration: float = 5.0
) -> void:
	if notification_stack == null:
		return

	var notification_id: String = "system:%d" % (title + body).hash()
	_remove_notification(notification_id)

	var toast := PanelContainer.new()
	toast.custom_minimum_size = Vector2(0, 190)
	toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	toast.modulate.a = 0.0
	toast.add_theme_stylebox_override("panel", _create_toast_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	toast.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 26)
	margin.add_child(hbox)
	_add_icon(hbox, icon_token)
	_add_text(hbox, title, body)

	toast.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_remove_notification(notification_id)
	)

	notification_stack.add_child(toast)
	notification_stack.move_child(toast, 0)
	_notifications[notification_id] = toast

	var fade_in: Tween = create_tween()
	fade_in.tween_property(toast, "modulate:a", 1.0, 0.18)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(duration, 0.01)
	timer.timeout.connect(_expire_notification.bind(notification_id))
	toast.add_child(timer)
	timer.start()


func _create_toast_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#F7FAFF")
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#D6DFEE")
	style.shadow_size = 16
	style.shadow_color = Color(0, 0, 0, 0.14)
	style.shadow_offset = Vector2(0, 6)
	return style


func _add_icon(hbox: HBoxContainer, icon_token: String) -> void:
	var icon_texture: Texture2D = null
	var is_app_icon: bool = false
	if _app_manager != null and _app_manager.has_method("get_app_definition"):
		var app_definition: Resource = _app_manager.call("get_app_definition", icon_token)
		if app_definition != null and "icon" in app_definition:
			var registered_icon: Variant = app_definition.get("icon")
			if registered_icon is Texture2D:
				icon_texture = registered_icon as Texture2D
				is_app_icon = true
	if icon_texture == null:
		icon_texture = UIIconLibraryClass.get_icon(icon_token)
	if icon_texture == null:
		return

	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(108, 108)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color("#E7EEFC")
	icon_style.corner_radius_top_left = 27
	icon_style.corner_radius_top_right = 27
	icon_style.corner_radius_bottom_left = 27
	icon_style.corner_radius_bottom_right = 27
	icon_panel.add_theme_stylebox_override("panel", icon_style)

	var icon_margin := MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 12)
	icon_margin.add_theme_constant_override("margin_top", 12)
	icon_margin.add_theme_constant_override("margin_right", 12)
	icon_margin.add_theme_constant_override("margin_bottom", 12)
	icon_panel.add_child(icon_margin)

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon_texture
	icon_rect.custom_minimum_size = Vector2(84, 84)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not is_app_icon:
		icon_rect.modulate = _get_icon_color(icon_token)
	icon_margin.add_child(icon_rect)
	hbox.add_child(icon_panel)


func _add_text(hbox: HBoxContainer, title: String, body: String) -> void:
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 10)
	hbox.add_child(text_vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color("#1E2738"))
	text_vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 29)
	body_label.add_theme_color_override("font_color", Color("#56627A"))
	text_vbox.add_child(body_label)


func _expire_notification(notification_id: String) -> void:
	var toast: Control = _notifications.get(notification_id)
	if toast == null or not is_instance_valid(toast):
		_notifications.erase(notification_id)
		return

	var fade_out: Tween = create_tween()
	fade_out.tween_property(toast, "modulate:a", 0.0, 0.18)
	fade_out.tween_callback(_remove_notification.bind(notification_id))


func _remove_notification(notification_id: String) -> void:
	if not _notifications.has(notification_id):
		return
	var toast: Control = _notifications[notification_id]
	_notifications.erase(notification_id)
	if toast != null and is_instance_valid(toast):
		toast.queue_free()


func _get_icon_color(icon_token: String) -> Color:
	match icon_token.strip_edges().to_lower():
		"warning":
			return Color("#C47A00")
		"power":
			return Color("#D64545")
		_:
			return Color("#4569C7")
