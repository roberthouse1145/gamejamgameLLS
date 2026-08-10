class_name LinkChatMomentsPanel extends VBoxContainer
## LinkChat 朋友圈视图。数据由游戏内容层传入，不依赖旧 ChatManager。

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const RoundedAvatarScene := preload("res://scenes/ui/rounded_avatar.tscn")
const LIKE_OUTLINE_ICON := preload("res://Assets/images/ui/linkchat/like_outline.png")
const LIKE_FILLED_ICON := preload("res://Assets/images/ui/linkchat/like_filled.png")
const AVATAR_SIZE: float = 126.0
const LIKE_ICON_SIZE: float = 30.0
const MOMENT_IMAGE_MAX_SIZE := Vector2(1200.0, 840.0)

signal post_liked(post_id: String, liked: bool)
signal image_open_requested(texture: Texture2D, title: String)

@onready var post_list: VBoxContainer = %PostList

var _posts: Array[Dictionary] = []


func _ready() -> void:
	_refresh()


func set_posts(posts: Array[Dictionary]) -> void:
	_posts.clear()
	for post: Dictionary in posts:
		_posts.append(post.duplicate(true))
	if is_node_ready():
		_refresh()


func add_post(post: Dictionary) -> void:
	_posts.push_front(post.duplicate(true))
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	for child: Node in post_list.get_children():
		child.queue_free()
	if _posts.is_empty():
		post_list.add_child(_create_empty_state())
		return
	for index: int in range(_posts.size()):
		post_list.add_child(_create_post_card(_posts[index], index))


func _create_empty_state() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = 300.0
	card.add_theme_stylebox_override("panel", LCTheme.get_moment_card_style())

	var label := Label.new()
	label.text = "暂时还没有新动态"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	label.add_theme_font_size_override("font_size", 30)
	card.add_child(label)
	return card


func _create_post_card(post: Dictionary, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", LCTheme.get_moment_card_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 30)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 27)
	margin.add_child(row)

	var display_name := str(post.get("author_name", post.get("display_name", "未知角色"))).strip_edges()
	var avatar := RoundedAvatarScene.instantiate() as RoundedAvatar
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var avatar_value: Variant = post.get("avatar")
	avatar.set_avatar(avatar_value as Texture2D if avatar_value is Texture2D else null, display_name)
	row.add_child(avatar)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 15)
	row.add_child(content)

	var heading := HBoxContainer.new()
	content.add_child(heading)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SENDER_PLAYER)
	name_label.add_theme_font_size_override("font_size", 33)
	heading.add_child(name_label)

	var time_label := Label.new()
	time_label.text = str(post.get("time", ""))
	time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_TIME)
	time_label.add_theme_font_size_override("font_size", 24)
	heading.add_child(time_label)

	var body := Label.new()
	body.text = str(post.get("content", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	body.add_theme_font_size_override("font_size", 32)
	content.add_child(body)

	var image_value: Variant = post.get("image")
	if image_value is Texture2D:
		content.add_child(_create_image_block(image_value as Texture2D, display_name))

	var liked: bool = bool(post.get("liked", false))
	var like_count: int = int(post.get("likes", 0))
	content.add_child(_create_like_button(index, liked, like_count))

	var comments_value: Variant = post.get("comments", [])
	if comments_value is Array and not comments_value.is_empty():
		content.add_child(_create_comments_panel(comments_value))

	return card


func _create_image_block(texture: Texture2D, display_name: String) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	block.add_theme_constant_override("separation", 9)

	var image_rect := TextureRect.new()
	image_rect.texture = texture
	image_rect.custom_minimum_size = _moment_image_display_size(texture)
	image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	image_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	image_rect.tooltip_text = "查看原图"
	image_rect.gui_input.connect(
		_on_image_gui_input.bind(texture, "%s的朋友圈图片" % display_name)
	)
	block.add_child(image_rect)

	var hint := Label.new()
	hint.text = "查看原图  ·  %d × %d" % [texture.get_width(), texture.get_height()]
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	block.add_child(hint)
	image_rect.mouse_entered.connect(_set_image_hint_hovered.bind(hint, true))
	image_rect.mouse_exited.connect(_set_image_hint_hovered.bind(hint, false))
	return block


func _moment_image_display_size(texture: Texture2D) -> Vector2:
	var source_size: Vector2 = texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return MOMENT_IMAGE_MAX_SIZE
	var fit_scale: float = minf(
		MOMENT_IMAGE_MAX_SIZE.x / source_size.x,
		MOMENT_IMAGE_MAX_SIZE.y / source_size.y
	)
	return (source_size * fit_scale).round()


func _on_image_gui_input(event: InputEvent, texture: Texture2D, title: String) -> void:
	if event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT:
		image_open_requested.emit(texture, title)


func _set_image_hint_hovered(hint: Label, hovered: bool) -> void:
	var color: Color = LCTheme.COLOR_ACCENT_HOVER if hovered else LCTheme.COLOR_TEXT_SECONDARY
	hint.add_theme_color_override("font_color", color)


func _create_like_button(index: int, liked: bool, like_count: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(210, 60)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", LCTheme.get_name_tag_style(liked))
	button.add_theme_stylebox_override("hover", LCTheme.get_name_tag_style(true))
	button.add_theme_stylebox_override("pressed", LCTheme.get_name_tag_style(true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var visual_margin := MarginContainer.new()
	visual_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_margin.add_theme_constant_override("margin_left", 20)
	visual_margin.add_theme_constant_override("margin_right", 20)
	visual_margin.add_theme_constant_override("margin_top", 10)
	visual_margin.add_theme_constant_override("margin_bottom", 10)
	button.add_child(visual_margin)

	var visual := HBoxContainer.new()
	visual.alignment = BoxContainer.ALIGNMENT_CENTER
	visual.add_theme_constant_override("separation", 12)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_margin.add_child(visual)

	var icon_rect := TextureRect.new()
	icon_rect.texture = LIKE_FILLED_ICON if liked else LIKE_OUTLINE_ICON
	icon_rect.custom_minimum_size = Vector2(LIKE_ICON_SIZE, LIKE_ICON_SIZE)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(icon_rect)

	var label := Label.new()
	label.text = "%s · %d" % ["已赞" if liked else "点赞", like_count]
	label.add_theme_font_size_override("font_size", 27)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(label)

	var normal_color: Color = LCTheme.COLOR_ACCENT_HOVER if liked else LCTheme.COLOR_TEXT_SECONDARY
	_set_like_visual_color(icon_rect, label, normal_color)
	button.mouse_entered.connect(
		_set_like_visual_color.bind(icon_rect, label, LCTheme.COLOR_ACCENT_HOVER)
	)
	button.mouse_exited.connect(_set_like_visual_color.bind(icon_rect, label, normal_color))
	button.pressed.connect(_on_like_pressed.bind(index))
	return button


func _set_like_visual_color(icon_rect: TextureRect, label: Label, color: Color) -> void:
	icon_rect.modulate = color
	label.add_theme_color_override("font_color", color)


func _create_comments_panel(comment_values: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", LCTheme.get_moment_comment_panel_style())

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 9)
	panel.add_child(list)

	var heading := Label.new()
	heading.text = "%d 条评论" % comment_values.size()
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	list.add_child(heading)

	for comment_value: Variant in comment_values:
		if not comment_value is Dictionary:
			continue
		var comment: Dictionary = comment_value
		var comment_row := HBoxContainer.new()
		comment_row.add_theme_constant_override("separation", 9)
		list.add_child(comment_row)

		var author := Label.new()
		author.text = "%s：" % str(comment.get("author_name", "未知角色"))
		author.add_theme_font_size_override("font_size", 25)
		author.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SENDER_PLAYER)
		comment_row.add_child(author)

		var comment_body := Label.new()
		comment_body.text = str(comment.get("content", ""))
		comment_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		comment_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		comment_body.add_theme_font_size_override("font_size", 25)
		comment_body.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
		comment_row.add_child(comment_body)
	return panel


func _on_like_pressed(index: int) -> void:
	if index < 0 or index >= _posts.size():
		return
	var post: Dictionary = _posts[index]
	var liked: bool = not bool(post.get("liked", false))
	var likes: int = int(post.get("likes", 0)) + (1 if liked else -1)
	post["liked"] = liked
	post["likes"] = maxi(likes, 0)
	_posts[index] = post
	post_liked.emit(str(post.get("id", "")), liked)
	_refresh()
