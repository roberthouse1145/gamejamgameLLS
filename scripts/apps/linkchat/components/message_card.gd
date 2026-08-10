class_name LinkChatMessageCard extends PanelContainer
## LinkChat 内嵌文件、网页与图片卡片。

const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const DOCUMENT_ICON = preload("res://Assets/images/ui/linkchat/document_file_icon.png")
const WEB_LINK_ICON = preload("res://Assets/images/ui/linkchat/web_link_icon.png")
const LOCATION_ICON = preload("res://Assets/images/app_icons/cityhop.png")

var _card_data: Dictionary = {}
var _enabled: bool = true
var _normal_style: StyleBoxFlat = null


static func create(card_data: Dictionary, _bubble_type: int) -> LinkChatMessageCard:
	var card := LinkChatMessageCard.new()
	card._card_data = card_data.duplicate(true)
	card._enabled = not bool(card_data.get("disabled", false))
	card._build()
	return card


func _ready() -> void:
	if bool(_card_data.get("contract_link", false)):
		add_to_group("linkchat_contract_cards")


func set_enabled(value: bool) -> void:
	_enabled = value
	modulate = Color.WHITE if value else Color(1, 1, 1, 0.55)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW


func _build() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _enabled else Control.CURSOR_ARROW
	_normal_style = LCTheme.rounded_flat(Color("#FFFFFF"), 15, Color("#D9DEE8"), 1, Color(0, 0, 0, 0.05), 3)
	add_theme_stylebox_override("panel", _normal_style)
	if _card_type() == "image":
		_build_image_card()
	else:
		_build_link_card()
	set_enabled(_enabled)


func _build_link_card() -> void:
	custom_minimum_size = Vector2(630, 174)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 21)
	margin.add_theme_constant_override("margin_bottom", 21)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 21)
	margin.add_child(row)

	var icon_rect := TextureRect.new()
	var is_file: bool = _card_type() == "file"
	icon_rect.texture = LOCATION_ICON if _card_type() == "location" else (DOCUMENT_ICON if is_file else WEB_LINK_ICON)
	icon_rect.custom_minimum_size = Vector2(69, 69)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)
	var title := Label.new()
	title.text = str(_card_data.get("title", "未命名文件"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(title)
	var subtitle := Label.new()
	var subtitle_text: String = str(_card_data.get("subtitle", ""))
	var price_text: String = str(_card_data.get("price_text", "")).strip_edges()
	if not price_text.is_empty():
		subtitle_text = "%s  ·  %s" % [subtitle_text, price_text] if not subtitle_text.is_empty() else price_text
	subtitle.text = subtitle_text
	subtitle.add_theme_font_size_override("font_size", 23)
	subtitle.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(subtitle)
	var footer := Label.new()
	footer.text = str(_card_data.get("footer", "点击打开"))
	footer.add_theme_font_size_override("font_size", 23)
	footer.add_theme_color_override("font_color", Color("#6474CB"))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(footer)


func _build_image_card() -> void:
	custom_minimum_size = Vector2(630, 360)
	clip_contents = true

	var image_path := _target_path()
	var image_texture := _load_image_texture(image_path)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 0)
	add_child(content)

	var preview_background := PanelContainer.new()
	preview_background.custom_minimum_size = Vector2(630, _thumbnail_height(image_texture))
	preview_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_background.add_theme_stylebox_override(
		"panel",
		LCTheme.rounded_flat(Color("#EEF3FA"), 15)
	)
	content.add_child(preview_background)

	if image_texture != null:
		var preview := TextureRect.new()
		preview.texture = image_texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_background.add_child(preview)
	else:
		var missing := Label.new()
		missing.text = "图片暂时无法显示"
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		missing.add_theme_font_size_override("font_size", 27)
		missing.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
		missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_background.add_child(missing)

	var caption_margin := MarginContainer.new()
	caption_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_margin.add_theme_constant_override("margin_left", 24)
	caption_margin.add_theme_constant_override("margin_right", 24)
	caption_margin.add_theme_constant_override("margin_top", 18)
	caption_margin.add_theme_constant_override("margin_bottom", 18)
	content.add_child(caption_margin)

	var caption := VBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_constant_override("separation", 5)
	caption_margin.add_child(caption)
	var title := Label.new()
	title.text = str(_card_data.get("title", "图片"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_child(title)

	var description := str(_card_data.get("subtitle", "")).strip_edges()
	if not description.is_empty():
		var subtitle := Label.new()
		subtitle.text = description
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle.add_theme_font_size_override("font_size", 23)
		subtitle.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_child(subtitle)

	var footer := Label.new()
	footer.text = _image_footer(image_texture)
	footer.add_theme_font_size_override("font_size", 23)
	footer.add_theme_color_override("font_color", Color("#6474CB"))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_child(footer)


func _card_type() -> String:
	return str(_card_data.get("type", "")).strip_edges().to_lower()


func _target_path() -> String:
	return str(_card_data.get("source", _card_data.get("url", ""))).strip_edges()


func _load_image_texture(image_path: String) -> Texture2D:
	if image_path.is_empty() or not ResourceLoader.exists(image_path):
		return null
	return ResourceLoader.load(image_path) as Texture2D


func _thumbnail_height(texture: Texture2D) -> float:
	if texture == null or texture.get_width() <= 0:
		return 360.0
	return clampf(630.0 * float(texture.get_height()) / float(texture.get_width()), 300.0, 480.0)


func _image_footer(texture: Texture2D) -> String:
	if texture == null:
		return "点击查看原图"
	return "点击查看原图  ·  %d × %d" % [texture.get_width(), texture.get_height()]


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _card_type() == "image":
			_open_image_viewer()
			accept_event()
			return
		if _card_type() == "location":
			_open_location()
			accept_event()
			return
		var url: String = _target_path()
		var browser_manager: Node = get_node_or_null("/root/BrowserManager")
		if browser_manager != null and not url.is_empty():
			var app_manager: Node = get_node_or_null("/root/AppManager")
			if app_manager != null and app_manager.has_method("focus_app"):
				app_manager.focus_app("browser", true)
			browser_manager.request_open_url.call_deferred(url, "", str(_card_data.get("title", "")))
			accept_event()


func _open_location() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("focus_app"):
		return
	var window: Control = app_manager.call("focus_app", str(_card_data.get("target_app", "cityhop")), true) as Control
	if window == null:
		return
	var app_content: Node = window.get("content") as Node
	if app_content != null and app_content.has_method("open_activity"):
		app_content.call_deferred("open_activity", str(_card_data.get("activity_id", "")))


func _open_image_viewer() -> void:
	var image_path := _target_path()
	if image_path.is_empty() or not ResourceLoader.exists(image_path):
		return
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("focus_app"):
		return
	var window: Control = app_manager.focus_app("image_viewer", true)
	if window == null:
		return
	var viewer := window.get("content") as Node
	if viewer != null and viewer.has_method("open_image"):
		viewer.call_deferred("open_image", image_path, str(_card_data.get("title", "图片")))


func _notification(what: int) -> void:
	if _normal_style == null or not _enabled:
		return
	if what == NOTIFICATION_MOUSE_ENTER:
		_normal_style.border_color = Color("#8C96E8")
	elif what == NOTIFICATION_MOUSE_EXIT:
		_normal_style.border_color = Color("#D9DEE8")
