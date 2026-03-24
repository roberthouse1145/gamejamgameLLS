class_name LinkChatMessageCard
extends VBoxContainer

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")

const CARD_WIDTH: float = 380.0
const MEDIA_WIDTH: float = 352.0
const MEDIA_HEIGHT: float = 228.0

var _card_data: Dictionary = {}
var _bubble_type: int = 0


static func create(card_data: Dictionary, bubble_type: int) -> LinkChatMessageCard:
	var card := LinkChatMessageCard.new()
	card._card_data = card_data.duplicate(true)
	card._bubble_type = bubble_type
	card._build()
	return card


func _build() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var card_type := str(_card_data.get("type", "")).strip_edges().to_lower()
	match card_type:
		"image":
			_build_image_card()
		"mock_image":
			_build_mock_image_card()
		"location":
			_build_location_card()
		"game":
			_build_game_card()
		"web_page":
			_build_web_page_card()
		"product":
			_build_product_card()
		_:
			_build_unknown_card()


func _build_image_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]
	var media: Control = _create_image_media(
		str(_card_data.get("image_path", _card_data.get("texture_path", ""))).strip_edges(),
		float(_card_data.get("preview_width", MEDIA_WIDTH)),
		float(_card_data.get("preview_height", MEDIA_HEIGHT))
	)
	body.add_child(media)


func _build_mock_image_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]
	var poster := PanelContainer.new()
	poster.custom_minimum_size = Vector2(MEDIA_WIDTH, MEDIA_HEIGHT)
	poster.add_theme_stylebox_override("panel", _get_mock_card_style())
	body.add_child(poster)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	poster.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var badge := str(_card_data.get("badge", _default_mock_badge())).strip_edges()
	if not badge.is_empty():
		content.add_child(_create_badge_label(badge))

	var title := str(_card_data.get("title", "未命名卡片")).strip_edges()
	content.add_child(_create_title_label(title, Color("#342B21")))

	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		content.add_child(_create_subtitle_label(subtitle, Color("#6F6251")))

	var separator := HSeparator.new()
	content.add_child(separator)

	var body_text := str(_card_data.get("body", _card_data.get("hint", ""))).strip_edges()
	if not body_text.is_empty():
		content.add_child(_create_body_label(body_text, Color("#4B4033")))

	var footer := str(_card_data.get("footer", "")).strip_edges()
	if not footer.is_empty():
		content.add_child(_create_footer_label(footer, Color("#8C7D69")))


func _build_game_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]

	# Sbeam 风格深色面板
	var sbeam_panel := PanelContainer.new()
	sbeam_panel.custom_minimum_size = Vector2(MEDIA_WIDTH, 176)
	var bg_style := LCTheme.rounded_flat(Color("#171D25"), LCTheme.RADIUS_SM)
	sbeam_panel.add_theme_stylebox_override("panel", bg_style)
	body.add_child(sbeam_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	sbeam_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	# 顶部标签栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	content.add_child(header)
	
	var badge_label := _create_badge_label(str(_card_data.get("badge", "SBEAM GAME")))
	badge_label.add_theme_color_override("font_color", Color("#66c0f4"))
	header.add_child(badge_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var brand_icon := Label.new()
	brand_icon.text = "✦"
	brand_icon.add_theme_color_override("font_color", Color("#2F89CE"))
	brand_icon.add_theme_font_size_override("font_size", 15)
	header.add_child(brand_icon)

	# 游戏标题
	var title_lbl := _create_title_label(str(_card_data.get("title", "未命名游戏")), Color("#E1E8ED"))
	title_lbl.add_theme_font_size_override("font_size", 20)
	content.add_child(title_lbl)

	# 游戏类型副标题
	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		content.add_child(_create_subtitle_label(subtitle, Color("#8F98A0")))

	# 推荐语 / Pitch
	var pitch_text := str(_card_data.get("body", "")).strip_edges()
	if not pitch_text.is_empty():
		var pitch_lbl := _create_body_label(pitch_text, Color("#B8B6B4"))
		pitch_lbl.add_theme_font_size_override("font_size", 15)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 4)
		m.add_theme_constant_override("margin_bottom", 6)
		m.add_child(pitch_lbl)
		content.add_child(m)

	# 底部按钮区 (购买 / 一起玩)
	var footer_hbox := HBoxContainer.new()
	content.add_child(footer_hbox)

	var footer_text := str(_card_data.get("footer", ""))
	var price_lbl := _create_footer_label(footer_text, Color("#A1BA89"))
	price_lbl.add_theme_font_size_override("font_size", 14)
	price_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	price_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	footer_hbox.add_child(price_lbl)


func _build_location_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]

	var map_panel := PanelContainer.new()
	map_panel.custom_minimum_size = Vector2(MEDIA_WIDTH, 168)
	var base_bg := Color("#FFFFFF")
	map_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(base_bg, LCTheme.RADIUS_SM, Color("#E5E5E5"), 1))
	body.add_child(map_panel)

	# 高德 / Google Maps 风布局: 左侧图标，右侧文字
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	map_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	# 左侧圆形地图图标
	var icon_bg := PanelContainer.new()
	icon_bg.custom_minimum_size = Vector2(54, 54)
	icon_bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color("#F0F4F8")
	icon_style.corner_radius_top_left = 20
	icon_style.corner_radius_top_right = 20
	icon_style.corner_radius_bottom_left = 20
	icon_style.corner_radius_bottom_right = 20
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	hbox.add_child(icon_bg)

	var pin_icon := Label.new()
	pin_icon.text = "📍"
	pin_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pin_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pin_icon.add_theme_font_size_override("font_size", 22)
	icon_bg.add_child(pin_icon)

	# 右侧内容区
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	hbox.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	content.add_child(header)

	var badge_text := str(_card_data.get("badge", "位置共享"))
	var badge := _create_badge_label(badge_text)
	badge.add_theme_color_override("font_color", Color("#2D85EA")) # 导航蓝
	header.add_child(badge)

	# 标题
	var title_lbl := _create_title_label(str(_card_data.get("title", "未命名地点")), Color("#1D1D1F"))
	title_lbl.add_theme_font_size_override("font_size", 19)
	content.add_child(title_lbl)

	# 副标题 (英文名或子区域)
	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		content.add_child(_create_subtitle_label(subtitle, Color("#86868B")))

	# 描述 (商圈信息等)
	var body_text := str(_card_data.get("body", "")).strip_edges()
	if not body_text.is_empty():
		content.add_child(_create_body_label(body_text, Color("#515154")))

	# 底部行程信息
	var footer := str(_card_data.get("footer", "")).strip_edges()
	if not footer.is_empty():
		var footer_lbl := _create_footer_label(footer, Color("#34C759")) # 行程绿
		footer_lbl.add_theme_font_size_override("font_size", 14)
		
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 4)
		m.add_child(footer_lbl)
		content.add_child(m)


func _build_web_page_card() -> void:
	var shell_info := _create_shell(true)
	var body: VBoxContainer = shell_info["body"]
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	body.add_child(header)

	var badge := _create_badge_label("网页卡片")
	header.add_child(badge)

	var icon := Label.new()
	icon.text = "↗"
	icon.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	icon.add_theme_font_size_override("font_size", 18)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(icon)

	var title := str(_card_data.get("title", "未命名网页")).strip_edges()
	body.add_child(_create_title_label(title))

	var hint := str(_card_data.get("hint", "")).strip_edges()
	if not hint.is_empty():
		body.add_child(_create_hint_label(hint))

	var url := str(_card_data.get("url", "")).strip_edges()
	if not url.is_empty():
		body.add_child(_create_footer_label(url, LCTheme.COLOR_TEXT_SECONDARY))


func _build_product_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]

	# 电商风格：橙色顶部条
	var accent_bar := PanelContainer.new()
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.add_theme_stylebox_override("panel", LCTheme.rounded_flat(Color("#FF6A00"), 0))
	body.add_child(accent_bar)

	# 分类标签 + 购物袋图标
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	body.add_child(header)

	var icon := Label.new()
	icon.text = "🛍"
	icon.add_theme_font_size_override("font_size", 14)
	header.add_child(icon)

	var badge_text := str(_card_data.get("badge", "商品"))
	var badge := _create_badge_label(badge_text)
	badge.add_theme_color_override("font_color", Color("#FF6A00"))
	header.add_child(badge)

	# 商品标题
	var title_text := str(_card_data.get("title", "未命名商品")).strip_edges()
	var title_lbl := _create_title_label(title_text, Color("#1D1D1F"))
	title_lbl.add_theme_font_size_override("font_size", 18)
	body.add_child(title_lbl)

	# 简介
	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		body.add_child(_create_body_label(subtitle, Color("#666666")))

	# 底部：价格 + 标签
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 8)
	body.add_child(footer_hbox)

	var price_text := str(_card_data.get("price", "")).strip_edges()
	if not price_text.is_empty():
		var price_lbl := Label.new()
		price_lbl.text = price_text
		price_lbl.add_theme_font_size_override("font_size", 18)
		price_lbl.add_theme_color_override("font_color", Color("#FF4400"))
		footer_hbox.add_child(price_lbl)

	var tags_text := str(_card_data.get("footer", "")).strip_edges()
	if not tags_text.is_empty():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer_hbox.add_child(spacer)
		var tags_lbl := _create_footer_label(tags_text, Color("#999999"))
		tags_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tags_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		footer_hbox.add_child(tags_lbl)


func _build_unknown_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]
	body.add_child(_create_badge_label("未知卡片"))
	body.add_child(_create_title_label(str(_card_data.get("title", "无法识别的卡片"))))


func _create_shell(clickable: bool) -> Dictionary:
	var style := _get_shell_style()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	if clickable:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(_on_shell_gui_input.bind(panel, style))

	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	return {
		"shell": panel,
		"body": body,
	}


func _on_shell_gui_input(event: InputEvent, panel: PanelContainer, _normal_style: StyleBoxFlat) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		panel.add_theme_stylebox_override("panel", _get_shell_hover_style())
		_on_web_card_pressed()
	elif event is InputEventMouseMotion:
		# 简易 hover 效果
		pass


func _create_image_media(image_path: String, preview_width: float, preview_height: float) -> Control:
	var target_size := Vector2(maxf(preview_width, 96.0), maxf(preview_height, 96.0))
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		var tex_res := load(image_path)
		if tex_res is Texture2D:
			var texture_rect := TextureRect.new()
			texture_rect.texture = tex_res
			texture_rect.custom_minimum_size = target_size
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return texture_rect

	var placeholder := PanelContainer.new()
	placeholder.custom_minimum_size = target_size
	placeholder.add_theme_stylebox_override("panel", LCTheme.rounded_flat(Color("#ECEDEF"), LCTheme.RADIUS_SM))

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	placeholder.add_child(inner)

	var icon := Label.new()
	icon.text = "🖼"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 32)
	inner.add_child(icon)
	return placeholder


func _create_badge_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	return label


func _create_title_label(text: String, color: Color = LCTheme.COLOR_TEXT_PRIMARY) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	return label


func _create_subtitle_label(text: String, color: Color = LCTheme.COLOR_TEXT_SECONDARY) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	return label


func _create_hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	return label


func _create_body_label(text: String, color: Color = LCTheme.COLOR_TEXT_PRIMARY) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	return label


func _create_footer_label(text: String, color: Color = LCTheme.COLOR_TEXT_MUTED) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label


func _get_shell_style() -> StyleBoxFlat:
	var bg := Color("#FFFFFF")
	if _bubble_type == 1:
		bg = Color("#F3FFE9")
	elif _bubble_type == 2:
		bg = Color("#F6F6F6")
	var style := LCTheme.rounded_flat(bg, LCTheme.RADIUS_MD, Color("#E5E5E5"), 1)
	style.shadow_color = Color(0, 0, 0, 0.04)
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, 1)
	return style


func _get_shell_hover_style() -> StyleBoxFlat:
	var style := _get_shell_style()
	style.border_color = LCTheme.COLOR_ACCENT
	return style


func _get_mock_card_style() -> StyleBoxFlat:
	var theme_name := str(_card_data.get("theme", "document")).strip_edges().to_lower()
	match theme_name:
		"contract", "document":
			return LCTheme.rounded_flat(Color("#F7F1E3"), LCTheme.RADIUS_SM, Color("#D9C8A9"), 1)
		"poster":
			return LCTheme.rounded_flat(Color("#FFF4E2"), LCTheme.RADIUS_SM, Color("#F0BF7A"), 1)
		_:
			return LCTheme.rounded_flat(Color("#EEF1F4"), LCTheme.RADIUS_SM, Color("#D3D9DF"), 1)


func _default_mock_badge() -> String:
	var theme_name := str(_card_data.get("theme", "document")).strip_edges().to_lower()
	match theme_name:
		"contract":
			return "合同快照"
		"poster":
			return "海报卡片"
		_:
			return "伪图片卡片"


func _on_web_card_pressed() -> void:
	var url := str(_card_data.get("url", "")).strip_edges()
	if url.is_empty():
		return
	call_deferred("_request_browser_open")


func _request_browser_open() -> void:
	var browser_manager := get_node_or_null("/root/BrowserManager")
	if browser_manager == null or not browser_manager.has_method("request_open_url"):
		return
	browser_manager.request_open_url(
		str(_card_data.get("url", "")).strip_edges(),
		str(_card_data.get("design_prompt", "")).strip_edges(),
		str(_card_data.get("hint", "")).strip_edges()
	)
