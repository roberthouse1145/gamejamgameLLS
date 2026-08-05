class_name LinkChatMomentsPanel extends VBoxContainer
## LinkChat 朋友圈视图。数据由游戏内容层传入，不依赖旧 ChatManager。

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const RoundedAvatarScene := preload("res://scenes/ui/rounded_avatar.tscn")
const AVATAR_SIZE: float = 126.0

signal post_liked(post_id: String, liked: bool)

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
		var image_rect := TextureRect.new()
		image_rect.texture = image_value as Texture2D
		image_rect.custom_minimum_size = Vector2(720, 360)
		image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		content.add_child(image_rect)

	var liked: bool = bool(post.get("liked", false))
	var like_count: int = int(post.get("likes", 0))
	var like_button := Button.new()
	like_button.text = "%s · %d" % ["已赞" if liked else "点赞", like_count]
	like_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	like_button.add_theme_font_size_override("font_size", 27)
	like_button.add_theme_stylebox_override("normal", LCTheme.get_name_tag_style(liked))
	like_button.add_theme_stylebox_override("hover", LCTheme.get_name_tag_style(true))
	like_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	like_button.pressed.connect(_on_like_pressed.bind(index))
	content.add_child(like_button)

	return card


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
