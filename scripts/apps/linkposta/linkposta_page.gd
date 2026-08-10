class_name LinkPostaPage extends Control
## LinkPosta 网站控制器。页面骨架在 TSCN 中，脚本只处理路由、数据绑定和交互。

const PostCardScene := preload("res://scenes/apps/linkposta/linkposta_post_card.tscn")
const HOME_URL: String = "https://linkposta.net/"
const COLOR_TEXT := Color("#1E2126")
const COLOR_MUTED := Color("#707882")
const COLOR_BRAND := Color("#C73550")

@onready var site_shell: HBoxContainer = %SiteShell
@onready var left_rail: PanelContainer = %LeftRail
@onready var center_column: PanelContainer = %CenterColumn
@onready var right_rail: VBoxContainer = %RightRail
@onready var home_button: Button = %HomeButton
@onready var hot_button: Button = %HotButton
@onready var streamer_button: Button = %StreamerButton
@onready var personal_button: Button = %PersonalButton
@onready var page_title: Label = %PageTitle
@onready var feed_mode_label: Label = %FeedModeLabel
@onready var feed_scroll: ScrollContainer = %FeedScroll
@onready var account_header: PanelContainer = %AccountHeader
@onready var account_name: Label = %AccountName
@onready var account_meta: Label = %AccountMeta
@onready var account_bio: Label = %AccountBio
@onready var posts_container: VBoxContainer = %PostsContainer
@onready var empty_state: PanelContainer = %EmptyState
@onready var search_field: LineEdit = %SearchField
@onready var suggested_accounts: VBoxContainer = %SuggestedAccounts

var _browser_app: Control = null
var _page_url: String = HOME_URL
var _feed_mode: String = "home"


func _ready() -> void:
	home_button.pressed.connect(_select_feed_mode.bind("home"))
	hot_button.pressed.connect(_select_feed_mode.bind("hot"))
	streamer_button.pressed.connect(_select_feed_mode.bind("streamer"))
	personal_button.pressed.connect(_select_feed_mode.bind("personal"))
	search_field.text_changed.connect(_on_search_changed)
	resized.connect(_apply_responsive_layout)
	var manager: Node = _social_manager()
	if manager != null:
		if not manager.posts_reloaded.is_connected(_refresh):
			manager.posts_reloaded.connect(_refresh)
		if not manager.post_published.is_connected(_on_post_published):
			manager.post_published.connect(_on_post_published)
		if not manager.post_like_changed.is_connected(_on_post_like_changed):
			manager.post_like_changed.connect(_on_post_like_changed)
		if not manager.recommended_accounts_changed.is_connected(_refresh_suggested_accounts):
			manager.recommended_accounts_changed.connect(_refresh_suggested_accounts)
	_refresh_suggested_accounts()
	_refresh()
	_apply_responsive_layout.call_deferred()


func configure_browser_page(browser_app: Control, page_context: Dictionary) -> void:
	_browser_app = browser_app
	_page_url = str(page_context.get("page_url", HOME_URL)).strip_edges()
	if _page_url.is_empty():
		_page_url = HOME_URL
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var previous_scroll: int = feed_scroll.scroll_vertical
	_clear_posts()
	var route: Dictionary = _parse_route()
	var posts: Array[Dictionary] = _posts_for_route(route)
	posts = _filter_posts(posts)
	_update_header(route, posts.size())
	_update_account_header(route)
	_update_nav_states(route)

	for post: Dictionary in posts:
		var card := PostCardScene.instantiate() as LinkPostaPostCard
		card.configure(post)
		card.url_open_requested.connect(_open_url)
		card.image_open_requested.connect(_open_image)
		card.like_requested.connect(_set_post_liked)
		posts_container.add_child(card)
	empty_state.visible = posts.is_empty()
	feed_scroll.set_deferred("scroll_vertical", previous_scroll)


func _posts_for_route(route: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var manager: Node = _social_manager()
	if manager == null:
		return result
	match str(route.get("type", "home")):
		"post":
			var post: Dictionary = manager.get_post_view_data(str(route.get("id", "")))
			if not post.is_empty():
				result.append(post)
		"account":
			result.assign(manager.get_feed_view_data(str(route.get("id", ""))))
		_:
			result.assign(manager.get_feed_view_data())
	return result


func _filter_posts(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = source.duplicate(true)
	match _feed_mode:
		"hot":
			result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _engagement_score(a) > _engagement_score(b)
			)
		"streamer":
			result = result.filter(func(post: Dictionary) -> bool:
				return str(post.get("identity_type", "")) == SocialAccountProfile.IDENTITY_STREAMER
			)
		"personal":
			result = result.filter(func(post: Dictionary) -> bool:
				return str(post.get("identity_type", "")) == SocialAccountProfile.IDENTITY_PERSONAL
			)

	var keyword: String = search_field.text.strip_edges().to_lower()
	if not keyword.is_empty():
		result = result.filter(func(post: Dictionary) -> bool:
			var searchable: String = "%s %s %s" % [
				str(post.get("display_name", "")),
				str(post.get("handle", "")),
				str(post.get("content", "")),
			]
			return searchable.to_lower().contains(keyword)
		)
	return result


func _update_header(route: Dictionary, result_count: int) -> void:
	match str(route.get("type", "home")):
		"post":
			page_title.text = "帖子"
			feed_mode_label.text = "详情"
		"account":
			var manager: Node = _social_manager()
			var account: SocialAccountProfile = manager.get_account(str(route.get("id", ""))) if manager != null else null
			page_title.text = account.get_resolved_display_name() if account != null else "账号"
			feed_mode_label.text = "%d 条动态" % result_count
		_:
			var titles: Dictionary = {
				"home": ["首页", "最新动态"],
				"hot": ["热门", "按互动排序"],
				"streamer": ["主播动态", "主播账号"],
				"personal": ["个人动态", "个人账号"],
			}
			var value: Array = titles.get(_feed_mode, titles["home"])
			page_title.text = str(value[0])
			feed_mode_label.text = str(value[1])


func _update_account_header(route: Dictionary) -> void:
	account_header.visible = str(route.get("type", "home")) == "account"
	if not account_header.visible:
		return
	var manager: Node = _social_manager()
	var account: SocialAccountProfile = manager.get_account(str(route.get("id", ""))) if manager != null else null
	if account == null:
		account_header.visible = false
		return
	account_name.text = account.get_resolved_display_name()
	account_meta.text = "%s  ·  %s" % [account.handle, _identity_label(account.identity_type)]
	account_bio.text = account.bio


func _update_nav_states(route: Dictionary) -> void:
	var is_home_route: bool = str(route.get("type", "home")) == "home"
	home_button.button_pressed = is_home_route and _feed_mode == "home"
	hot_button.button_pressed = is_home_route and _feed_mode == "hot"
	streamer_button.button_pressed = is_home_route and _feed_mode == "streamer"
	personal_button.button_pressed = is_home_route and _feed_mode == "personal"


func _refresh_suggested_accounts() -> void:
	for child: Node in suggested_accounts.get_children():
		suggested_accounts.remove_child(child)
		child.queue_free()
	var manager: Node = _social_manager()
	if manager == null:
		return
	for account: Dictionary in manager.get_recommended_account_view_data():
		var button := Button.new()
		button.custom_minimum_size.y = 78.0
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.text = "%s\n%s" % [str(account.get("display_name", "")), str(account.get("handle", ""))]
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", COLOR_BRAND)
		button.pressed.connect(_open_url.bind(str(account.get("account_url", ""))))
		suggested_accounts.add_child(button)


func _select_feed_mode(mode: String) -> void:
	_feed_mode = mode
	if str(_parse_route().get("type", "home")) != "home":
		_open_url(HOME_URL)
		return
	feed_scroll.scroll_vertical = 0
	_refresh()


func _on_search_changed(_value: String) -> void:
	feed_scroll.scroll_vertical = 0
	_refresh()


func _set_post_liked(post_id: String, liked: bool) -> void:
	var manager: Node = _social_manager()
	if manager != null:
		manager.set_post_liked(post_id, liked)


func _open_url(url: String) -> void:
	var normalized: String = url.strip_edges()
	if normalized.is_empty():
		return
	if _browser_app != null and _browser_app.has_method("navigate_to"):
		_browser_app.call("navigate_to", normalized)
		return
	var browser_manager: Node = get_node_or_null("/root/BrowserManager")
	if browser_manager != null:
		browser_manager.request_open_url(normalized)


func _open_image(texture: Texture2D, title: String) -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return
	var window: Control = app_manager.focus_app("image_viewer", true) as Control
	var viewer: Control = window.get("content") as Control if window != null else null
	if viewer != null and viewer.has_method("open_texture"):
		viewer.call_deferred("open_texture", texture, title)


func _apply_responsive_layout() -> void:
	var available_width: float = size.x
	if available_width >= 2800.0:
		left_rail.visible = true
		right_rail.visible = true
		left_rail.custom_minimum_size.x = 520.0
		center_column.custom_minimum_size.x = 1900.0
		right_rail.custom_minimum_size.x = 550.0
	elif available_width >= 2200.0:
		left_rail.visible = true
		right_rail.visible = true
		left_rail.custom_minimum_size.x = 340.0
		center_column.custom_minimum_size.x = 1250.0
		right_rail.custom_minimum_size.x = 480.0
	else:
		right_rail.visible = false
		left_rail.visible = available_width >= 1450.0
		left_rail.custom_minimum_size.x = 340.0
		center_column.custom_minimum_size.x = maxf(
			available_width - (358.0 if left_rail.visible else 0.0),
			980.0
		)


func _parse_route() -> Dictionary:
	var normalized: String = _page_url.trim_suffix("/")
	if normalized.contains("/post/"):
		return {"type": "post", "id": normalized.get_slice("/post/", 1)}
	if normalized.contains("/@"):
		return {"type": "account", "id": normalized.get_slice("/@", 1)}
	return {"type": "home", "id": ""}


func _clear_posts() -> void:
	for child: Node in posts_container.get_children():
		posts_container.remove_child(child)
		child.queue_free()


func _engagement_score(post: Dictionary) -> int:
	return int(post.get("likes", 0)) + int(post.get("reposts", 0)) * 2 + int(post.get("replies", 0))


func _identity_label(identity_type: String) -> String:
	return "主播账号" if identity_type == SocialAccountProfile.IDENTITY_STREAMER else "个人账号"


func _social_manager() -> Node:
	return get_node_or_null("/root/SocialMediaManager")


func _on_post_published(_post: SocialPostRecord) -> void:
	_refresh()


func _on_post_like_changed(_post_id: String, _liked: bool, _likes: int) -> void:
	_refresh()
