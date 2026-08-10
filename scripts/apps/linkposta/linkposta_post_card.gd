class_name LinkPostaPostCard extends PanelContainer
## LinkPosta 信息流中的单条帖子。节点结构由 TSCN 固定，脚本只绑定数据和交互。

signal url_open_requested(url: String)
signal image_open_requested(texture: Texture2D, title: String)
signal like_requested(post_id: String, liked: bool)

const LIKE_OUTLINE_ICON := preload("res://Assets/images/ui/linkchat/like_outline.png")
const LIKE_FILLED_ICON := preload("res://Assets/images/ui/linkchat/like_filled.png")
const ReplyItemScene := preload("res://scenes/apps/linkposta/linkposta_reply_item.tscn")
const MAX_REPLY_PREVIEWS: int = 3
const COLOR_BRAND := Color("#E94B64")
const COLOR_BRAND_DARK := Color("#C73550")
const COLOR_MUTED := Color("#6F7782")
const COLOR_STREAMER := Color("#7656D8")
const COLOR_PERSONAL := Color("#527086")

@onready var avatar: RoundedAvatar = %Avatar
@onready var name_button: Button = %NameButton
@onready var verified_badge: Label = %VerifiedBadge
@onready var meta_label: Label = %MetaLabel
@onready var identity_badge: Label = %IdentityBadge
@onready var time_label: Label = %TimeLabel
@onready var post_body: Label = %PostBody
@onready var linked_button: Button = %LinkedButton
@onready var image_surface: PanelContainer = %ImageSurface
@onready var image_texture: TextureRect = %ImageTexture
@onready var reply_layer: PanelContainer = %ReplyLayer
@onready var reply_list: VBoxContainer = %ReplyList
@onready var reply_button: Button = %ReplyButton
@onready var repost_button: Button = %RepostButton
@onready var like_button: Button = %LikeButton
@onready var detail_button: Button = %DetailButton

var _post: Dictionary = {}


func _ready() -> void:
	name_button.pressed.connect(_open_account)
	linked_button.pressed.connect(_open_linked_url)
	reply_button.pressed.connect(_open_post)
	detail_button.pressed.connect(_open_post)
	like_button.pressed.connect(_toggle_like)
	image_texture.gui_input.connect(_on_image_input)
	image_texture.resized.connect(_update_image_height)
	_apply_post()


func configure(post: Dictionary) -> void:
	_post = post.duplicate(true)
	if is_node_ready():
		_apply_post()


func _apply_post() -> void:
	if _post.is_empty():
		return
	var display_name: String = str(_post.get("display_name", "未知账号"))
	var avatar_value: Variant = _post.get("avatar")
	avatar.set_avatar(avatar_value as Texture2D if avatar_value is Texture2D else null, display_name)
	name_button.text = display_name
	verified_badge.visible = bool(_post.get("verified", false))
	meta_label.text = str(_post.get("handle", ""))
	time_label.text = str(_post.get("time", ""))
	post_body.text = str(_post.get("content", ""))
	_set_identity_badge(str(_post.get("identity_type", SocialAccountProfile.IDENTITY_PERSONAL)))

	var linked_url: String = str(_post.get("linked_url", "")).strip_edges()
	linked_button.visible = not linked_url.is_empty()
	linked_button.text = "打开链接  %s" % linked_url

	var image_value: Variant = _post.get("image")
	image_surface.visible = image_value is Texture2D
	image_texture.texture = image_value as Texture2D if image_value is Texture2D else null
	if image_surface.visible:
		_update_image_height.call_deferred()
	_apply_reply_previews()

	reply_button.text = "回复  %s" % _format_count(int(_post.get("replies", 0)))
	repost_button.text = "转发  %s" % _format_count(int(_post.get("reposts", 0)))
	var liked: bool = bool(_post.get("liked", false))
	like_button.text = "%s  %s" % ["已赞" if liked else "点赞", _format_count(int(_post.get("likes", 0)))]
	like_button.icon = LIKE_FILLED_ICON if liked else LIKE_OUTLINE_ICON
	var like_color: Color = COLOR_BRAND if liked else COLOR_MUTED
	like_button.add_theme_color_override("font_color", like_color)
	like_button.add_theme_color_override("icon_normal_color", like_color)
	like_button.add_theme_color_override("font_hover_color", COLOR_BRAND_DARK)
	like_button.add_theme_color_override("icon_hover_color", COLOR_BRAND_DARK)


func _apply_reply_previews() -> void:
	for child: Node in reply_list.get_children():
		reply_list.remove_child(child)
		child.queue_free()
	var reply_values: Variant = _post.get("reply_items", [])
	if not reply_values is Array:
		reply_layer.visible = false
		return
	var displayed_count: int = 0
	for value: Variant in reply_values:
		if displayed_count >= MAX_REPLY_PREVIEWS:
			break
		if not value is Dictionary:
			continue
		var reply_data: Dictionary = value
		var item := ReplyItemScene.instantiate() as LinkPostaReplyItem
		item.configure(reply_data)
		reply_list.add_child(item)
		displayed_count += 1
	reply_layer.visible = displayed_count > 0


func _set_identity_badge(identity_type: String) -> void:
	var is_streamer: bool = identity_type == SocialAccountProfile.IDENTITY_STREAMER
	var badge_color: Color = COLOR_STREAMER if is_streamer else COLOR_PERSONAL
	identity_badge.text = "主播" if is_streamer else "个人"
	identity_badge.add_theme_color_override("font_color", badge_color)
	var style := StyleBoxFlat.new()
	style.bg_color = badge_color.lightened(0.88)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	identity_badge.add_theme_stylebox_override("normal", style)


func _update_image_height() -> void:
	var texture: Texture2D = image_texture.texture
	if texture == null:
		return
	var source: Vector2 = texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var available_width: float = image_texture.size.x
	if available_width <= 1.0:
		available_width = 1450.0
	image_texture.custom_minimum_size.y = clampf(
		available_width * source.y / source.x,
		360.0,
		1000.0
	)


func _open_account() -> void:
	url_open_requested.emit(str(_post.get("account_url", "")))


func _open_linked_url() -> void:
	url_open_requested.emit(str(_post.get("linked_url", "")))


func _open_post() -> void:
	url_open_requested.emit(str(_post.get("post_url", "")))


func _toggle_like() -> void:
	like_requested.emit(str(_post.get("id", "")), not bool(_post.get("liked", false)))


func _on_image_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var texture: Texture2D = image_texture.texture
		if texture != null:
			image_open_requested.emit(texture, "%s · LinkPosta" % str(_post.get("display_name", "")))


func _format_count(value: int) -> String:
	if value >= 10000:
		return "%.1f万" % (float(value) / 10000.0)
	return str(maxi(value, 0))
