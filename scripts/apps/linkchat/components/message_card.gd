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
		"job_posting":
			_build_job_posting_card()
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

	var theme_name := str(_card_data.get("theme", "document")).strip_edges().to_lower()
	var poster := PanelContainer.new()
	poster.custom_minimum_size = Vector2(MEDIA_WIDTH, 0)
	poster.add_theme_stylebox_override("panel", _get_mock_card_style())
	body.add_child(poster)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	poster.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	# ── 顶部装饰线（双线） ──
	var top_deco := VBoxContainer.new()
	top_deco.add_theme_constant_override("separation", 2)
	content.add_child(top_deco)
	for i in range(2):
		var line := ColorRect.new()
		line.color = _mock_accent_color(theme_name, 0.3 if i == 0 else 0.15)
		line.custom_minimum_size = Vector2(0, 2 if i == 0 else 1)
		top_deco.add_child(line)

	# 标签
	var badge := str(_card_data.get("badge", _default_mock_badge())).strip_edges()
	if not badge.is_empty():
		var badge_row := HBoxContainer.new()
		badge_row.add_theme_constant_override("separation", 6)
		content.add_child(badge_row)

		var badge_icon := Label.new()
		badge_icon.text = _mock_badge_icon(theme_name)
		badge_icon.add_theme_font_size_override("font_size", 12)
		badge_icon.add_theme_color_override("font_color", _mock_accent_color(theme_name, 0.7))
		badge_row.add_child(badge_icon)

		var badge_lbl := _create_badge_label(badge)
		badge_lbl.add_theme_color_override("font_color", _mock_accent_color(theme_name, 0.6))
		badge_row.add_child(badge_lbl)

	# 标题
	var title := str(_card_data.get("title", "未命名卡片")).strip_edges()
	var title_lbl := _create_title_label(title, _mock_text_color(theme_name, "title"))
	title_lbl.add_theme_font_size_override("font_size", 20)
	content.add_child(title_lbl)

	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		content.add_child(_create_subtitle_label(subtitle, _mock_text_color(theme_name, "subtitle")))

	# 分隔装饰 —— 细线 + 间距
	var sep_line := ColorRect.new()
	sep_line.color = _mock_accent_color(theme_name, 0.15)
	sep_line.custom_minimum_size = Vector2(0, 1)
	content.add_child(sep_line)

	# 正文
	var body_text := str(_card_data.get("body", _card_data.get("hint", ""))).strip_edges()
	if not body_text.is_empty():
		content.add_child(_create_body_label(body_text, _mock_text_color(theme_name, "body")))

	# 底部
	var footer := str(_card_data.get("footer", "")).strip_edges()
	if not footer.is_empty():
		content.add_child(_create_footer_label(footer, _mock_text_color(theme_name, "footer")))

	# ── 右下角印章 (仅 contract/document) ──
	if theme_name in ["contract", "document"]:
		var seal_container := Control.new()
		seal_container.custom_minimum_size = Vector2(0, 52)
		content.add_child(seal_container)

		var seal := PanelContainer.new()
		seal.custom_minimum_size = Vector2(52, 52)
		seal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		seal.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		seal.grow_vertical = Control.GROW_DIRECTION_BEGIN
		var seal_style := StyleBoxFlat.new()
		seal_style.bg_color = Color(0, 0, 0, 0)
		seal_style.border_color = Color("#C0392B", 0.35)
		seal_style.border_width_left = 2
		seal_style.border_width_top = 2
		seal_style.border_width_right = 2
		seal_style.border_width_bottom = 2
		seal_style.corner_radius_top_left = 26
		seal_style.corner_radius_top_right = 26
		seal_style.corner_radius_bottom_left = 26
		seal_style.corner_radius_bottom_right = 26
		seal.add_theme_stylebox_override("panel", seal_style)
		seal_container.add_child(seal)

		var seal_text := Label.new()
		seal_text.text = "确认"
		seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seal_text.add_theme_font_size_override("font_size", 14)
		seal_text.add_theme_color_override("font_color", Color("#C0392B", 0.4))
		seal.add_child(seal_text)

	# ── 底部装饰线 ──
	var bot_line := ColorRect.new()
	bot_line.color = _mock_accent_color(theme_name, 0.2)
	bot_line.custom_minimum_size = Vector2(0, 2)
	content.add_child(bot_line)


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

	# 整体容器 —— 仿地图应用的位置分享卡片
	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(MEDIA_WIDTH, 0)
	card_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(
		Color("#F8FAFB"), LCTheme.RADIUS_SM, Color("#E2E8ED"), 1))
	body.add_child(card_panel)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 0)
	card_panel.add_child(card_vbox)

	# ── 上半部分：仿地图网格区域 ──
	var map_area := PanelContainer.new()
	map_area.custom_minimum_size = Vector2(0, 96)
	var map_bg := LCTheme.rounded_flat(Color("#EDF2F7"), 0)
	map_bg.corner_radius_top_left = LCTheme.RADIUS_SM
	map_bg.corner_radius_top_right = LCTheme.RADIUS_SM
	map_area.add_theme_stylebox_override("panel", map_bg)
	card_vbox.add_child(map_area)

	# 地图网格线（水平+垂直装饰线）
	var grid_container := Control.new()
	grid_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_area.add_child(grid_container)

	for i in range(5):
		var h_line := ColorRect.new()
		h_line.color = Color("#DAE2EA")
		h_line.set_anchors_preset(Control.PRESET_FULL_RECT)
		h_line.offset_top = 18.0 * (i + 1)
		h_line.offset_bottom = 18.0 * (i + 1) + 1
		h_line.offset_left = 0
		h_line.offset_right = 0
		grid_container.add_child(h_line)

	for j in range(8):
		var v_line := ColorRect.new()
		v_line.color = Color("#DAE2EA")
		v_line.set_anchors_preset(Control.PRESET_TOP_LEFT)
		v_line.offset_left = 44.0 * (j + 1)
		v_line.offset_right = 44.0 * (j + 1) + 1
		v_line.offset_top = 0
		v_line.offset_bottom = 96
		grid_container.add_child(v_line)

	# 模拟道路（两条交叉粗线）
	var road_h := ColorRect.new()
	road_h.color = Color("#FFFFFF", 0.8)
	road_h.set_anchors_preset(Control.PRESET_FULL_RECT)
	road_h.offset_top = 40
	road_h.offset_bottom = 56
	road_h.offset_left = 0
	road_h.offset_right = 0
	grid_container.add_child(road_h)

	var road_v := ColorRect.new()
	road_v.color = Color("#FFFFFF", 0.7)
	road_v.set_anchors_preset(Control.PRESET_TOP_LEFT)
	road_v.offset_left = 140
	road_v.offset_right = 156
	road_v.offset_top = 0
	road_v.offset_bottom = 96
	grid_container.add_child(road_v)

	# Pin 图标 —— 中心红色标记
	var pin_center := VBoxContainer.new()
	pin_center.set_anchors_preset(Control.PRESET_CENTER)
	pin_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pin_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	pin_center.alignment = BoxContainer.ALIGNMENT_CENTER
	pin_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	map_area.add_child(pin_center)

	# Pin 阴影圈
	var pin_shadow := PanelContainer.new()
	pin_shadow.custom_minimum_size = Vector2(20, 8)
	pin_shadow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pin_shadow.add_theme_stylebox_override("panel", LCTheme.rounded_flat(
		Color(0, 0, 0, 0.1), 4))
	pin_center.add_child(pin_shadow)

	var pin_label := Label.new()
	pin_label.text = "📍"
	pin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pin_label.add_theme_font_size_override("font_size", 28)
	pin_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pin_center.add_child(pin_label)
	pin_center.move_child(pin_label, 0) # pin 在阴影上方

	# ── 下半部分：文字信息区 ──
	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 14)
	info_margin.add_theme_constant_override("margin_top", 12)
	info_margin.add_theme_constant_override("margin_right", 14)
	info_margin.add_theme_constant_override("margin_bottom", 14)
	card_vbox.add_child(info_margin)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info_margin.add_child(info)

	# 标签行
	var accent_color := Color(str(_card_data.get("accent_color", "#2D85EA")))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	info.add_child(header)

	var nav_dot := Label.new()
	nav_dot.text = "●"
	nav_dot.add_theme_font_size_override("font_size", 10)
	nav_dot.add_theme_color_override("font_color", accent_color)
	nav_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(nav_dot)

	var badge_text := str(_card_data.get("badge", "位置共享"))
	var badge := _create_badge_label(badge_text)
	badge.add_theme_color_override("font_color", accent_color)
	header.add_child(badge)

	# 地点名称
	var title_lbl := _create_title_label(str(_card_data.get("title", "未命名地点")), Color("#1D1D1F"))
	title_lbl.add_theme_font_size_override("font_size", 19)
	info.add_child(title_lbl)

	# 副标题
	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		info.add_child(_create_subtitle_label(subtitle, Color("#86868B")))

	# 描述
	var body_text := str(_card_data.get("body", "")).strip_edges()
	if not body_text.is_empty():
		info.add_child(_create_body_label(body_text, Color("#515154")))

	# 底部行程
	var footer := str(_card_data.get("footer", "")).strip_edges()
	if not footer.is_empty():
		var footer_row := HBoxContainer.new()
		footer_row.add_theme_constant_override("separation", 4)
		info.add_child(footer_row)

		var route_icon := Label.new()
		route_icon.text = "→"
		route_icon.add_theme_font_size_override("font_size", 13)
		route_icon.add_theme_color_override("font_color", Color("#34C759"))
		footer_row.add_child(route_icon)

		var footer_lbl := _create_footer_label(footer, Color("#34C759"))
		footer_lbl.add_theme_font_size_override("font_size", 14)
		footer_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer_row.add_child(footer_lbl)


func _build_job_posting_card() -> void:
	var shell_info := _create_shell(false)
	var body: VBoxContainer = shell_info["body"]

	# Boss直聘 / 领英风格招聘卡片
	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(MEDIA_WIDTH, 0)
	card_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(
		Color("#FFFFFF"), LCTheme.RADIUS_SM, Color("#E8ECF0"), 1))
	body.add_child(card_panel)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 0)
	card_panel.add_child(card_vbox)

	# ── 顶部强调色条 ──
	var accent_color := Color(str(_card_data.get("accent_color", "#00BFA5")))
	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 3)
	var bar_style := LCTheme.rounded_flat(accent_color, 0)
	bar_style.corner_radius_top_left = LCTheme.RADIUS_SM
	bar_style.corner_radius_top_right = LCTheme.RADIUS_SM
	top_bar.add_theme_stylebox_override("panel", bar_style)
	card_vbox.add_child(top_bar)

	# ── 内容区 ──
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_bottom", 14)
	card_vbox.add_child(content_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content_margin.add_child(content)

	# ── 标签行：图标 + 兼职邀约 ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	content.add_child(header)

	var badge_icon := Label.new()
	badge_icon.text = "💼"
	badge_icon.add_theme_font_size_override("font_size", 13)
	header.add_child(badge_icon)

	var badge_text := str(_card_data.get("badge", "招聘"))
	var badge := _create_badge_label(badge_text)
	badge.add_theme_color_override("font_color", accent_color)
	header.add_child(badge)

	# ── 职位名称 + 薪资 (同行) ──
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	content.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = str(_card_data.get("title", "未命名职位"))
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color("#1D1D1F"))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var salary := str(_card_data.get("salary", "")).strip_edges()
	if not salary.is_empty():
		var salary_lbl := Label.new()
		salary_lbl.text = salary
		salary_lbl.add_theme_font_size_override("font_size", 16)
		salary_lbl.add_theme_color_override("font_color", Color("#FF6633"))
		salary_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		salary_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		salary_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		salary_lbl.custom_minimum_size.x = 80
		title_row.add_child(salary_lbl)

	# ── 公司名 · 地区 ──
	var subtitle := str(_card_data.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		var sub_row := HBoxContainer.new()
		sub_row.add_theme_constant_override("separation", 6)
		content.add_child(sub_row)

		# 公司首字母圆形头像
		var company_initial := subtitle.left(1).to_upper()
		var avatar := PanelContainer.new()
		avatar.custom_minimum_size = Vector2(22, 22)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		avatar.add_theme_stylebox_override("panel", LCTheme.rounded_flat(accent_color, 11))
		sub_row.add_child(avatar)

		var avatar_lbl := Label.new()
		avatar_lbl.text = company_initial
		avatar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar_lbl.add_theme_font_size_override("font_size", 11)
		avatar_lbl.add_theme_color_override("font_color", Color.WHITE)
		avatar.add_child(avatar_lbl)

		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.add_theme_font_size_override("font_size", 15)
		sub_lbl.add_theme_color_override("font_color", Color("#86868B"))
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sub_lbl.clip_text = true
		sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sub_row.add_child(sub_lbl)

	# ── 分割线 ──
	var sep := ColorRect.new()
	sep.color = Color("#F0F0F0")
	sep.custom_minimum_size = Vector2(0, 1)
	content.add_child(sep)

	# ── 职位描述 ──
	var body_text := str(_card_data.get("body", "")).strip_edges()
	if not body_text.is_empty():
		var body_lbl := _create_body_label(body_text, Color("#515154"))
		body_lbl.add_theme_font_size_override("font_size", 14)
		content.add_child(body_lbl)

	# ── 底部：交通/附加信息 ──
	var footer := str(_card_data.get("footer", "")).strip_edges()
	if not footer.is_empty():
		var footer_lbl := _create_footer_label(footer, Color("#999999"))
		footer_lbl.add_theme_font_size_override("font_size", 13)
		content.add_child(footer_lbl)


func _build_web_page_card() -> void:
	var shell_info := _create_shell(true)
	var body: VBoxContainer = shell_info["body"]

	# 整体仿浏览器 OG 预览卡片
	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(MEDIA_WIDTH, 0)
	card_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(
		Color("#FFFFFF"), LCTheme.RADIUS_SM, Color("#E0E4E8"), 1))
	body.add_child(card_panel)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 0)
	card_panel.add_child(card_vbox)

	# ── 迷你浏览器标题栏 ──
	var chrome := PanelContainer.new()
	chrome.custom_minimum_size = Vector2(0, 32)
	var chrome_bg := LCTheme.rounded_flat(Color("#F0F2F4"), 0)
	chrome_bg.corner_radius_top_left = LCTheme.RADIUS_SM
	chrome_bg.corner_radius_top_right = LCTheme.RADIUS_SM
	chrome_bg.border_color = Color("#E0E4E8")
	chrome_bg.border_width_bottom = 1
	chrome.add_theme_stylebox_override("panel", chrome_bg)
	card_vbox.add_child(chrome)

	var chrome_margin := MarginContainer.new()
	chrome_margin.add_theme_constant_override("margin_left", 10)
	chrome_margin.add_theme_constant_override("margin_right", 10)
	chrome.add_child(chrome_margin)

	var chrome_hbox := HBoxContainer.new()
	chrome_hbox.add_theme_constant_override("separation", 6)
	chrome_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	chrome_margin.add_child(chrome_hbox)

	# 三个小圆点（红黄绿）
	for dot_color in [Color("#FF5F57"), Color("#FEBC2E"), Color("#28C840")]:
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", LCTheme.rounded_flat(dot_color, 5))
		chrome_hbox.add_child(dot)

	# 地址栏
	var url_text := str(_card_data.get("url", "")).strip_edges()
	var display_domain := _extract_domain(url_text)
	if not display_domain.is_empty():
		var url_bar := PanelContainer.new()
		url_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		url_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		url_bar.add_theme_stylebox_override("panel", LCTheme.rounded_flat(
			Color("#E8EAED"), 4))
		chrome_hbox.add_child(url_bar)

		var url_margin := MarginContainer.new()
		url_margin.add_theme_constant_override("margin_left", 8)
		url_margin.add_theme_constant_override("margin_right", 8)
		url_margin.add_theme_constant_override("margin_top", 2)
		url_margin.add_theme_constant_override("margin_bottom", 2)
		url_bar.add_child(url_margin)

		var url_label := Label.new()
		url_label.text = "🔒 " + display_domain
		url_label.add_theme_font_size_override("font_size", 11)
		url_label.add_theme_color_override("font_color", Color("#5F6368"))
		url_label.clip_text = true
		url_margin.add_child(url_label)

	# ── 内容区 ──
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_bottom", 14)
	card_vbox.add_child(content_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content_margin.add_child(content)

	# Favicon + 站点名
	var site_row := HBoxContainer.new()
	site_row.add_theme_constant_override("separation", 8)
	content.add_child(site_row)

	# 仿 Favicon 圆角方块
	var site_name := str(_card_data.get("site_name", display_domain)).strip_edges()
	var first_char := site_name.left(1).to_upper() if not site_name.is_empty() else "W"
	var favicon := PanelContainer.new()
	favicon.custom_minimum_size = Vector2(24, 24)
	favicon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	favicon.add_theme_stylebox_override("panel", LCTheme.rounded_flat(
		Color("#4285F4"), 4))
	site_row.add_child(favicon)

	var fav_letter := Label.new()
	fav_letter.text = first_char
	fav_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fav_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fav_letter.add_theme_font_size_override("font_size", 13)
	fav_letter.add_theme_color_override("font_color", Color.WHITE)
	favicon.add_child(fav_letter)

	if not site_name.is_empty():
		var site_lbl := Label.new()
		site_lbl.text = site_name
		site_lbl.add_theme_font_size_override("font_size", 13)
		site_lbl.add_theme_color_override("font_color", Color("#5F6368"))
		site_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		site_row.add_child(site_lbl)

	# 标题
	var title := str(_card_data.get("title", "未命名网页")).strip_edges()
	var title_lbl := _create_title_label(title, Color("#1A0DAB"))
	title_lbl.add_theme_font_size_override("font_size", 17)
	content.add_child(title_lbl)

	# 描述
	var hint := str(_card_data.get("hint", "")).strip_edges()
	if not hint.is_empty():
		var hint_lbl := _create_body_label(hint, Color("#4D5156"))
		hint_lbl.add_theme_font_size_override("font_size", 14)
		content.add_child(hint_lbl)

	# URL 全文
	if not url_text.is_empty():
		var full_url := _create_footer_label(url_text, Color("#70757A"))
		full_url.add_theme_font_size_override("font_size", 12)
		content.add_child(full_url)


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
		call_deferred("_finalize_clickable_shell", panel)

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


func _finalize_clickable_shell(panel: PanelContainer) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_set_children_mouse_filter(panel)


func _set_children_mouse_filter(root: Node) -> void:
	for child in root.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_filter(child)


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


# ============ Mock-image helpers ============

func _mock_accent_color(theme_name: String, alpha: float = 1.0) -> Color:
	match theme_name:
		"contract", "document":
			return Color("#8B6914", alpha)
		"poster":
			return Color("#C47F17", alpha)
		_:
			return Color("#6B7B8D", alpha)


func _mock_text_color(theme_name: String, role: String) -> Color:
	match role:
		"title":
			return Color("#342B21") if theme_name in ["contract", "document", "poster"] else Color("#1F2937")
		"subtitle":
			return Color("#6F6251") if theme_name in ["contract", "document", "poster"] else Color("#6B7280")
		"body":
			return Color("#4B4033") if theme_name in ["contract", "document", "poster"] else Color("#374151")
		"footer":
			return Color("#8C7D69") if theme_name in ["contract", "document", "poster"] else Color("#9CA3AF")
		_:
			return Color("#1F1F1F")


func _mock_badge_icon(theme_name: String) -> String:
	match theme_name:
		"contract":
			return "📜"
		"poster":
			return "🎨"
		_:
			return "📄"


# ============ Web-page helpers ============

func _extract_domain(url: String) -> String:
	if url.is_empty():
		return ""
	var stripped := url
	if stripped.begins_with("https://"):
		stripped = stripped.substr(8)
	elif stripped.begins_with("http://"):
		stripped = stripped.substr(7)
	var slash_pos := stripped.find("/")
	if slash_pos > 0:
		stripped = stripped.left(slash_pos)
	return stripped
