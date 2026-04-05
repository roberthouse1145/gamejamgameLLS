class_name MomentsPanel extends VBoxContainer
## 朋友圈面板
## 展示 NPC 发布的动态，玩家可以点赞

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const HEADER_MARGIN_X := 26
const HEADER_MARGIN_Y := 16
const CARD_MARGIN_X := 26
const CARD_MARGIN_Y := 16
const HEADER_TITLE_FONT_SIZE := 24
const EMPTY_FONT_SIZE := 18
const AVATAR_SIZE := 72.0
const AVATAR_FONT_SIZE := 26
const NAME_FONT_SIZE := 22
const TIME_FONT_SIZE := 17
const BODY_FONT_SIZE := 22
const IMAGE_HINT_HEIGHT := 132.0
const IMAGE_HINT_FONT_SIZE := 18
const ACTION_FONT_SIZE := 18

var _scroll: ScrollContainer
var _post_list: VBoxContainer


func _ready() -> void:
	_build_ui()
	_refresh()
	ChatManager.moment_posted.connect(_on_moment_posted)


func _build_ui() -> void:
	# 头部
	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", HEADER_MARGIN_X)
	header.add_theme_constant_override("margin_top", HEADER_MARGIN_Y)
	header.add_theme_constant_override("margin_right", HEADER_MARGIN_X)
	header.add_theme_constant_override("margin_bottom", HEADER_MARGIN_Y)
	add_child(header)

	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_HEADER, 0))
	header.add_child(header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 22)
	header_margin.add_theme_constant_override("margin_top", 12)
	header_margin.add_theme_constant_override("margin_right", 22)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	header_panel.add_child(header_margin)

	var title := Label.new()
	title.text = "朋友圈"
	title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", HEADER_TITLE_FONT_SIZE)
	header_margin.add_child(title)

	# 滚动区域
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_post_list = VBoxContainer.new()
	_post_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_post_list.add_theme_constant_override("separation", 0)
	_scroll.add_child(_post_list)


func _refresh() -> void:
	for child in _post_list.get_children():
		child.queue_free()

	var moments := ChatManager.get_moments()
	if moments.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无动态"
		empty_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
		empty_label.add_theme_font_size_override("font_size", EMPTY_FONT_SIZE)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty_margin := MarginContainer.new()
		empty_margin.add_theme_constant_override("margin_top", 40)
		empty_margin.add_child(empty_label)
		_post_list.add_child(empty_margin)
		return

	for moment in moments:
		var card := _create_moment_card(moment)
		_post_list.add_child(card)


func _create_moment_card(moment: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", CARD_MARGIN_X)
	card_margin.add_theme_constant_override("margin_right", CARD_MARGIN_X)
	card_margin.add_theme_constant_override("margin_top", CARD_MARGIN_Y)
	card_margin.add_theme_constant_override("margin_bottom", CARD_MARGIN_Y)
	card.add_child(card_margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card_margin.add_child(hbox)

	# 头像
	var avatar := _create_avatar(moment)
	hbox.add_child(avatar)

	# 内容区
	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(content_vbox)

	# 名字 + 时间
	var name_hbox := HBoxContainer.new()
	content_vbox.add_child(name_hbox)

	var name_label := Label.new()
	name_label.text = _resolve_moment_display_name(moment)
	name_label.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(name_label)

	var time_label := Label.new()
	var tm: Node = get_node_or_null("/root/TimeManager")
	if tm:
		time_label.text = tm.get_relative_time(moment.get("timestamp", 0))
	else:
		time_label.text = moment.get("time", "")
	time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	time_label.add_theme_font_size_override("font_size", TIME_FONT_SIZE)
	name_hbox.add_child(time_label)

	# 正文
	var text_label := Label.new()
	text_label.text = moment.get("content", "")
	text_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	text_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(text_label)

	# 图片占位
	var image_hint: String = moment.get("image_hint", "")
	if not image_hint.is_empty():
		var img_panel := PanelContainer.new()
		img_panel.custom_minimum_size = Vector2(0, IMAGE_HINT_HEIGHT)
		img_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(Color("#E8E8EC"), LCTheme.RADIUS_SM))
		content_vbox.add_child(img_panel)

		var img_label := Label.new()
		img_label.text = image_hint
		img_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
		img_label.add_theme_font_size_override("font_size", IMAGE_HINT_FONT_SIZE)
		img_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		img_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		img_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		img_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		img_panel.add_child(img_label)

	# 互动栏：点赞
	var action_hbox := HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 16)
	content_vbox.add_child(action_hbox)

	var like_btn := Button.new()
	var moment_id: String = moment.get("id", "")
	var liked: bool = moment.get("liked_by_player", false)
	var likes: int = moment.get("likes", 0)
	like_btn.text = "❤ %d" % likes if liked else "♡ %d" % likes
	like_btn.flat = true
	like_btn.add_theme_color_override("font_color", LCTheme.COLOR_UNREAD_BADGE if liked else LCTheme.COLOR_TEXT_SECONDARY)
	like_btn.add_theme_color_override("font_hover_color", LCTheme.COLOR_UNREAD_BADGE)
	like_btn.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	like_btn.pressed.connect(_on_like_pressed.bind(moment_id))
	action_hbox.add_child(like_btn)

	# 分隔线
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = LCTheme.COLOR_CONTACT_SEPARATOR
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.add_theme_constant_override("separation", 1)
	content_vbox.add_child(sep)

	return card


func _on_like_pressed(moment_id: String) -> void:
	ChatManager.like_moment(moment_id)
	_refresh()


func _on_moment_posted(_moment: Dictionary) -> void:
	_refresh()


func _create_avatar(moment: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var author := _resolve_moment_author(moment)
	var avatar_seed := str(author.get("avatar_seed", _resolve_moment_display_name(moment))).strip_edges()
	var hue := float(avatar_seed.hash() & 0xFFFF) / 65535.0
	var avatar_color := Color.from_hsv(hue, 0.55, 0.95)
	panel.add_theme_stylebox_override("panel", LCTheme.get_avatar_style(avatar_color))

	var avatar_texture := _resolve_moment_avatar(moment)
	if avatar_texture != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = avatar_texture
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tex_rect)
	else:
		var initial := Label.new()
		var npc_name := _resolve_moment_display_name(moment)
		initial.text = npc_name.substr(0, 1) if not npc_name.is_empty() else "?"
		initial.add_theme_color_override("font_color", Color.WHITE)
		initial.add_theme_font_size_override("font_size", AVATAR_FONT_SIZE)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(initial)

	return panel


func _resolve_moment_display_name(moment: Dictionary) -> String:
	var author := _resolve_moment_author(moment)
	var display_name := str(author.get("display_name", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	var moment_name := str(moment.get("npc_name", "")).strip_edges()
	if not moment_name.is_empty() and not moment_name.begins_with("npc_"):
		return moment_name
	var npc_id := str(moment.get("npc_id", "")).strip_edges()
	if npc_id.is_empty():
		return moment_name if not moment_name.is_empty() else "未知角色"
	return npc_id.trim_prefix("npc_").replace("_", " ")


func _resolve_moment_avatar(moment: Dictionary) -> Texture2D:
	var author := _resolve_moment_author(moment)
	if str(author.get("avatar_mode", "")).strip_edges() != "npc_ref":
		return null
	var npc: Variant = _resolve_moment_npc(moment)
	if npc == null:
		return null
	var avatar = npc.get("avatar")
	return avatar as Texture2D if avatar != null else null


func _resolve_moment_author(moment: Dictionary) -> Dictionary:
	if moment.has("author") and moment["author"] is Dictionary:
		return moment["author"] as Dictionary
	return {
		"id": str(moment.get("npc_id", "")).strip_edges(),
		"display_name": str(moment.get("npc_name", "")).strip_edges(),
		"avatar_mode": "seed",
		"avatar_seed": str(moment.get("npc_id", moment.get("npc_name", ""))).strip_edges(),
	}


func _resolve_moment_npc(moment: Dictionary):
	var author := _resolve_moment_author(moment)
	if str(author.get("avatar_mode", "")).strip_edges() != "npc_ref":
		return null
	var npc_id := str(author.get("avatar_id", moment.get("npc_id", ""))).strip_edges()
	if npc_id.is_empty():
		return null
	var chat_manager := get_node_or_null("/root/ChatManager")
	if chat_manager == null or not chat_manager.has_method("get_npc"):
		return null
	return chat_manager.call("get_npc", npc_id)
