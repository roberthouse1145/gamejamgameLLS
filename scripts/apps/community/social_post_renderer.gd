class_name SocialPostRenderer
extends RefCounted

const C_SECTION_BG := Color("#F9FAFB")
const C_SECTION_BORDER := Color("#E5E7EB")
const C_CARD_BG := Color("#FFFFFF")
const C_CARD_BORDER := Color("#E5E7EB")
const C_REPLY_BG := Color("#F3F4F6")
const C_REPLY_BORDER := Color("#E5E7EB")
const C_SUB_REPLY_BG := Color("#FFFFFF")
const C_SUB_REPLY_BORDER := Color("#DDE3EE")
const C_TITLE := Color("#111827")
const C_BODY := Color("#374151")
const C_META := Color("#9CA3AF")
const C_AUTHOR := Color("#111827")   # 用户名用深色（推特风）
const C_LINK := Color("#6366F1")
const C_DIVIDER := Color("#EEF0F4")
const C_LIKE := Color("#EF4444")
const C_BTN_ICON := Color("#6B7280")

static var _avatar_colors: Array[Color] = [
	Color("#6366F1"), Color("#3B82F6"), Color("#10B981"),
	Color("#F59E0B"), Color("#EF4444"), Color("#8B5CF6"),
	Color("#EC4899"), Color("#14B8A6"),
]


static func create_feed_entry(entry: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)
	root.add_child(_build_section_header(entry))
	var floor_index := 1
	for raw_post in entry.get("posts", []):
		if raw_post is Dictionary:
			floor_index = _append_thread_floors(root, entry, raw_post, floor_index)
	return root


static func _append_thread_floors(container: VBoxContainer, entry: Dictionary, raw_post: Dictionary, floor_index: int) -> int:
	var post: Dictionary = raw_post.duplicate(true)
	container.add_child(_build_divider())
	container.add_child(_build_floor_card(entry, post, floor_index, true))
	floor_index += 1
	for raw_reply in post.get("reply_list", []):
		if raw_reply is Dictionary:
			container.add_child(_build_divider())
			container.add_child(_build_floor_card(entry, raw_reply, floor_index, false))
			floor_index += 1
	return floor_index


## 历史列表 — Twitter/贴吧 手机版风：头像 + 名字/时间列 + 正文 + 底部 3 按钮
static func create_history_card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 无边框、无圆角 —— 靠容器的分隔线分层
	var bg := StyleBoxFlat.new()
	bg.bg_color = C_CARD_BG
	panel.add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	# 左：头像
	var first_post := _get_first_post(entry)
	var author_name: String = str(first_post.get("author", "匿名用户"))
	var avatar := _build_avatar(author_name, 52)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(avatar)

	# 右：内容列
	var content_col := VBoxContainer.new()
	content_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_col.add_theme_constant_override("separation", 4)
	row.add_child(content_col)

	# 第一行：用户名 + 时间 + tag chip + 右侧 day
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	content_col.add_child(head)

	var name_lbl := Label.new()
	name_lbl.text = author_name
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color", C_AUTHOR)
	head.add_child(name_lbl)

	var time_lbl := Label.new()
	time_lbl.text = "· %s" % str(first_post.get("time", "刚刚"))
	time_lbl.add_theme_font_size_override("font_size", 17)
	time_lbl.add_theme_color_override("font_color", C_META)
	head.add_child(time_lbl)

	var action_id: String = str(entry.get("action_id", ""))
	var tag_text: String = _tag_for_action(action_id)
	if not tag_text.is_empty():
		head.add_child(_build_tag_chip(tag_text, _get_action_color(action_id)))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var day_lbl := Label.new()
	day_lbl.text = "第%s天" % str(entry.get("day", "?"))
	day_lbl.add_theme_font_size_override("font_size", 15)
	day_lbl.add_theme_color_override("font_color", C_META)
	head.add_child(day_lbl)

	# 标题（可选）
	var post_title: String = str(first_post.get("title", "")).strip_edges()
	var entry_title: String = str(entry.get("title", "")).strip_edges()
	var shown_title := post_title if not post_title.is_empty() else entry_title
	if not shown_title.is_empty():
		var t := Label.new()
		t.text = shown_title
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.add_theme_font_size_override("font_size", 22)
		t.add_theme_color_override("font_color", C_TITLE)
		content_col.add_child(t)

	# 正文预览
	var preview := Label.new()
	preview.text = str(first_post.get("content", "")).strip_edges().replace("\n", " ")
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_theme_font_size_override("font_size", 20)
	preview.add_theme_color_override("font_color", C_BODY)
	content_col.add_child(preview)

	# 底部 3 按钮
	var replies: int = (first_post.get("reply_list", []) as Array).size()
	if replies == 0:
		replies = int(first_post.get("replies", 0))
	var likes: int = int(first_post.get("likes", 0))
	content_col.add_child(_build_action_row(replies, likes, false))

	return panel


static func _build_section_header(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(C_SECTION_BG, C_SECTION_BORDER, 10))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var accent := PanelContainer.new()
	accent.custom_minimum_size = Vector2(4, 0)
	accent.add_theme_stylebox_override("panel", _make_plain_style(_get_action_color(str(entry.get("action_id", ""))), 4))
	row.add_child(accent)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)
	row.add_child(text_box)

	var title := Label.new()
	title.text = str(entry.get("title", "社区动态"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", C_TITLE)
	text_box.add_child(title)

	var meta := Label.new()
	meta.text = _build_entry_meta(entry)
	meta.add_theme_font_size_override("font_size", 17)
	meta.add_theme_color_override("font_color", C_META)
	text_box.add_child(meta)

	return panel


## 单层楼 — 与 history_card 同一套社交风视觉
static func _build_floor_card(entry: Dictionary, raw_floor: Dictionary, floor_index: int, is_thread_owner: bool) -> Control:
	var floor_data: Dictionary = raw_floor.duplicate(true)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = C_CARD_BG
	panel.add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	# 左：头像
	var author_name: String = str(floor_data.get("author", "匿名用户"))
	var avatar := _build_avatar(author_name, 48)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(avatar)

	# 右：内容列
	var content_col := VBoxContainer.new()
	content_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_col.add_theme_constant_override("separation", 4)
	row.add_child(content_col)

	# 头行：名字 + 楼主tag + 时间 + spacer + 楼号
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	content_col.add_child(head)

	var name_lbl := Label.new()
	name_lbl.text = author_name
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", C_AUTHOR)
	head.add_child(name_lbl)

	if is_thread_owner:
		head.add_child(_build_tag_chip("楼主", _get_action_color(str(entry.get("action_id", "")))))

	var time_lbl := Label.new()
	time_lbl.text = "· %s" % str(floor_data.get("time", "刚刚"))
	time_lbl.add_theme_font_size_override("font_size", 16)
	time_lbl.add_theme_color_override("font_color", C_META)
	head.add_child(time_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var floor_lbl := Label.new()
	floor_lbl.text = "%d楼" % floor_index
	floor_lbl.add_theme_font_size_override("font_size", 15)
	floor_lbl.add_theme_color_override("font_color", C_META)
	head.add_child(floor_lbl)

	# 标题（可选）
	var title_text: String = str(floor_data.get("title", "")).strip_edges()
	if not title_text.is_empty():
		var title := Label.new()
		title.text = title_text
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", C_TITLE)
		content_col.add_child(title)

	# 正文
	var content := Label.new()
	content.text = str(floor_data.get("content", ""))
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_size_override("font_size", 20)
	content.add_theme_color_override("font_color", C_BODY)
	content_col.add_child(content)

	# 底部 3 按钮
	var reply_count: int = _get_floor_reply_count(floor_data)
	var likes: int = int(floor_data.get("likes", 0))
	content_col.add_child(_build_action_row(reply_count, likes, likes > 0))

	# 楼中楼
	var sub_replies: Array = floor_data.get("sub_reply_list", [])
	if sub_replies.is_empty() and floor_data.has("reply_list"):
		sub_replies = floor_data.get("reply_list", [])
	if not sub_replies.is_empty():
		var sub_list := VBoxContainer.new()
		sub_list.add_theme_constant_override("separation", 6)
		content_col.add_child(sub_list)
		for raw_sub_reply in sub_replies:
			if raw_sub_reply is Dictionary:
				sub_list.add_child(_build_sub_reply_card(raw_sub_reply))

	return panel


## 1px 细分隔线（用于 feed 列表之间）
static func build_feed_divider() -> Control:
	return _build_divider()


static func _build_divider() -> Control:
	# 透明细带 —— 让 FeedPage 背景透出，视觉上相当于 6px 灰缝隙
	var r := Control.new()
	r.custom_minimum_size = Vector2(0, 6)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 彩色 tag chip（"楼主"、"#讨论"）
static func _build_tag_chip(text: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	panel.add_child(lbl)
	return panel


## 底部 3 按钮行：💬回复 · ↗转发 · ♥点赞
static func _build_action_row(reply_count: int, like_count: int, liked: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.custom_minimum_size = Vector2(0, 30)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(_build_action_btn("💬", "%d" % reply_count, C_BTN_ICON))
	row.add_child(_build_action_btn("↗", "转发", C_BTN_ICON))
	row.add_child(_build_action_btn("♥", "%d" % like_count, C_LIKE if liked else C_BTN_ICON))

	# 右侧占位让按钮靠左排 ~3 等分
	var tail := Control.new()
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tail)
	return row


static func _build_action_btn(icon: String, label_text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.text = "%s  %s" % [icon, label_text]
	btn.custom_minimum_size = Vector2(92, 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 1.0
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", Color("#1F2937"))
	btn.add_theme_color_override("font_pressed_color", color)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn


## 从 action_id 派生话题 tag 文案
static func _tag_for_action(action_id: String) -> String:
	match action_id:
		"chill_browse":
			return "#讨论"
		"learn_dev":
			return "#学习"
		"follow_contest":
			return "#宣传"
		_:
			return ""


static func _build_sub_reply_card(raw_sub_reply: Dictionary) -> Control:
	var reply: Dictionary = raw_sub_reply.duplicate(true)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(C_SUB_REPLY_BG, C_SUB_REPLY_BORDER, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	body.add_child(top)

	var author := Label.new()
	author.text = str(reply.get("author", "匿名用户"))
	author.add_theme_font_size_override("font_size", 17)
	author.add_theme_color_override("font_color", C_AUTHOR)
	top.add_child(author)

	var time_text: String = str(reply.get("time", "")).strip_edges()
	if not time_text.is_empty():
		var time_label := Label.new()
		time_label.text = "· %s" % time_text
		time_label.add_theme_font_size_override("font_size", 15)
		time_label.add_theme_color_override("font_color", C_META)
		top.add_child(time_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var likes := Label.new()
	likes.text = "♥ %d" % int(reply.get("likes", 0))
	likes.add_theme_font_size_override("font_size", 15)
	likes.add_theme_color_override("font_color", C_LIKE if int(reply.get("likes", 0)) > 0 else C_META)
	top.add_child(likes)

	var content := Label.new()
	content.text = str(reply.get("content", ""))
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_size_override("font_size", 18)
	content.add_theme_color_override("font_color", C_BODY)
	body.add_child(content)

	return panel


static func _build_avatar(author_name: String, diameter: int) -> Control:
	var color_index: int = abs(author_name.hash()) % _avatar_colors.size()
	var bg_color: Color = _avatar_colors[color_index]

	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(diameter, diameter)
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_theme_stylebox_override("panel", _make_plain_style(bg_color, int(diameter / 2.0)))

	var initial := Label.new()
	initial.text = author_name.substr(0, 1) if not author_name.is_empty() else "?"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", int(diameter * 0.45))
	initial.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(initial)

	return container


static func _build_entry_meta(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("第%s天" % str(entry.get("day", "?")))
	var phase: String = str(entry.get("phase", "")).strip_edges()
	if not phase.is_empty():
		parts.append(phase)
	var action_title: String = str(entry.get("action_title", "")).strip_edges()
	if not action_title.is_empty():
		parts.append(action_title)
	if str(entry.get("source_type", "llm")).strip_edges() == "fallback":
		parts.append("本地备用")
	return " · ".join(parts)


static func _build_history_meta(entry: Dictionary) -> String:
	var first_post: Dictionary = _get_first_post(entry)
	var author: String = str(first_post.get("author", "匿名用户")).strip_edges()
	var time_text: String = str(first_post.get("time", "刚刚")).strip_edges()
	var parts: PackedStringArray = []
	if not author.is_empty():
		parts.append(author)
	if not time_text.is_empty():
		parts.append(time_text)
	parts.append("第%s天" % str(entry.get("day", "?")))
	if str(entry.get("source_type", "llm")).strip_edges() == "fallback":
		parts.append("本地备用")
	return " · ".join(parts)


static func _build_history_preview(entry: Dictionary) -> String:
	var first_post: Dictionary = _get_first_post(entry)
	var post_title: String = str(first_post.get("title", "")).strip_edges()
	var content: String = str(first_post.get("content", "")).strip_edges().replace("\n", " ")
	if not post_title.is_empty() and not content.is_empty():
		return "%s  %s" % [post_title, content]
	if not post_title.is_empty():
		return post_title
	return content


static func _build_history_footer(entry: Dictionary) -> String:
	var first_post: Dictionary = _get_first_post(entry)
	var floor_count: int = (first_post.get("reply_list", []) as Array).size()
	if floor_count == 0:
		floor_count = int(first_post.get("replies", 0))
	var source_note: String = " · 本地备用" if str(entry.get("source_type", "llm")).strip_edges() == "fallback" else ""
	return "%s · ♥ %d · %d楼%s" % [
		str(entry.get("action_title", "社区")),
		int(first_post.get("likes", 0)),
		floor_count,
		source_note,
	]


static func _get_first_post(entry: Dictionary) -> Dictionary:
	var posts: Array = entry.get("posts", [])
	if posts.is_empty() or not posts[0] is Dictionary:
		return {}
	return (posts[0] as Dictionary).duplicate(true)


static func _build_post_footer(post: Dictionary) -> String:
	var reply_count: int = post.get("reply_list", []).size()
	if reply_count == 0:
		reply_count = int(post.get("replies", 0))
	return "♥ %d · ↩ %d" % [int(post.get("likes", 0)), reply_count]


static func _get_floor_reply_count(floor_data: Dictionary) -> int:
	var reply_count: int = 0
	if floor_data.has("sub_reply_list"):
		reply_count = (floor_data.get("sub_reply_list", []) as Array).size()
	elif floor_data.has("reply_list"):
		reply_count = (floor_data.get("reply_list", []) as Array).size()
	if reply_count == 0:
		reply_count = int(floor_data.get("replies", 0))
	return reply_count


static func _get_action_color(action_id: String) -> Color:
	match action_id:
		"chill_browse":
			return Color("#3B82F6")
		"learn_dev":
			return Color("#F59E0B")
		"follow_contest":
			return Color("#10B981")
		_:
			return Color("#3B82F6")


static func _make_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


static func _make_plain_style(bg_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
