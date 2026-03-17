class_name MomentsPanel extends VBoxContainer
## 朋友圈面板
## 展示 NPC 发布的动态，玩家可以点赞

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")

var _scroll: ScrollContainer
var _post_list: VBoxContainer


func _ready() -> void:
	_build_ui()
	_refresh()
	ChatManager.moment_posted.connect(_on_moment_posted)


func _build_ui() -> void:
	# 头部
	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 18)
	header.add_theme_constant_override("margin_top", 12)
	header.add_theme_constant_override("margin_right", 18)
	header.add_theme_constant_override("margin_bottom", 12)
	add_child(header)

	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_HEADER, 0))
	header.add_child(header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header_panel.add_child(header_margin)

	var title := Label.new()
	title.text = "朋友圈"
	title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", 20)
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
		empty_label.add_theme_font_size_override("font_size", 16)
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
	card_margin.add_theme_constant_override("margin_left", 18)
	card_margin.add_theme_constant_override("margin_right", 18)
	card_margin.add_theme_constant_override("margin_top", 12)
	card_margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(card_margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card_margin.add_child(hbox)

	# 头像
	var avatar := _create_avatar(moment.get("npc_name", "?"))
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
	name_label.text = moment.get("npc_name", "")
	name_label.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(name_label)

	var time_label := Label.new()
	var tm: Node = get_node_or_null("/root/TimeManager")
	if tm:
		time_label.text = tm.get_relative_time(moment.get("timestamp", 0))
	else:
		time_label.text = moment.get("time", "")
	time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	time_label.add_theme_font_size_override("font_size", 13)
	name_hbox.add_child(time_label)

	# 正文
	var text_label := Label.new()
	text_label.text = moment.get("content", "")
	text_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(text_label)

	# 图片占位
	var image_hint: String = moment.get("image_hint", "")
	if not image_hint.is_empty():
		var img_panel := PanelContainer.new()
		img_panel.custom_minimum_size = Vector2(0, 110)
		img_panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(Color("#E8E8EC"), LCTheme.RADIUS_SM))
		content_vbox.add_child(img_panel)

		var img_label := Label.new()
		img_label.text = image_hint
		img_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
		img_label.add_theme_font_size_override("font_size", 14)
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
	like_btn.add_theme_font_size_override("font_size", 14)
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


func _create_avatar(npc_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(48, 48)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var hue := float(npc_name.hash() & 0xFFFF) / 65535.0
	var avatar_color := Color.from_hsv(hue, 0.55, 0.95)
	panel.add_theme_stylebox_override("panel", LCTheme.get_avatar_style(avatar_color))

	var initial := Label.new()
	initial.text = npc_name.substr(0, 1) if not npc_name.is_empty() else "?"
	initial.add_theme_color_override("font_color", Color.WHITE)
	initial.add_theme_font_size_override("font_size", 18)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(initial)

	return panel
