class_name LinkChatMessageCard extends PanelContainer
## LinkChat 内嵌文件/网页卡片。沿用原卡片组件入口，使用当前 BrowserManager 打开网页。

const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const UIIconLibraryClass = preload("res://scripts/ui/ui_icon_library.gd")

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
	custom_minimum_size = Vector2(420, 116)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _enabled else Control.CURSOR_ARROW
	_normal_style = LCTheme.rounded_flat(Color("#FFFFFF"), 10, Color("#D9DEE8"), 1, Color(0, 0, 0, 0.05), 2)
	add_theme_stylebox_override("panel", _normal_style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var icon_rect := TextureRect.new()
	var icon_token: String = "document" if str(_card_data.get("type", "")) == "file" else "browser"
	icon_rect.texture = UIIconLibraryClass.get_icon(icon_token)
	icon_rect.custom_minimum_size = Vector2(46, 46)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.modulate = Color("#6474CB")
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)
	var title := Label.new()
	title.text = str(_card_data.get("title", "未命名文件"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = str(_card_data.get("subtitle", ""))
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(subtitle)
	var footer := Label.new()
	footer.text = str(_card_data.get("footer", "点击打开"))
	footer.add_theme_font_size_override("font_size", 15)
	footer.add_theme_color_override("font_color", Color("#6474CB"))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(footer)
	set_enabled(_enabled)


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var url: String = str(_card_data.get("url", "")).strip_edges()
		var browser_manager: Node = get_node_or_null("/root/BrowserManager")
		if browser_manager != null and not url.is_empty():
			browser_manager.request_open_url(url, "", str(_card_data.get("title", "")))
		accept_event()


func _notification(what: int) -> void:
	if _normal_style == null or not _enabled:
		return
	if what == NOTIFICATION_MOUSE_ENTER:
		_normal_style.border_color = Color("#8C96E8")
	elif what == NOTIFICATION_MOUSE_EXIT:
		_normal_style.border_color = Color("#D9DEE8")
