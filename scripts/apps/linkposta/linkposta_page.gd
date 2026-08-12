class_name LinkPostaPage extends Control
## LinkPosta 网站控制器。页面骨架在 TSCN 中，脚本只处理路由、数据绑定和交互。

const PostCardScene := preload("res://scenes/apps/linkposta/linkposta_post_card.tscn")
const PostLoaderScene := preload("res://scenes/apps/linkposta/linkposta_post_loader.tscn")
const HOME_URL: String = "https://linkposta.net/"
const COLOR_TEXT := Color("#1E2126")
const COLOR_MUTED := Color("#707882")
const COLOR_BRAND := Color("#C73550")
const POST_REVEAL_HEIGHT: float = 280.0
const SLOT_EXPAND_SECONDS: float = 0.28
const LOADER_SECONDS: float = 1.0
const POST_FADE_SECONDS: float = 0.24

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
var _post_reveal_queue: Array[Dictionary] = []
var _revealing_post_ids: Dictionary = {}
var _post_reveal_running: bool = false


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
		if not manager.post_presentation_requested.is_connected(_on_post_presentation_requested):
			manager.post_presentation_requested.connect(_on_post_presentation_requested)
		if not manager.post_like_changed.is_connected(_on_post_like_changed):
			manager.post_like_changed.connect(_on_post_like_changed)
		if not manager.recommended_accounts_changed.is_connected(_refresh_suggested_accounts):
			manager.recommended_accounts_changed.connect(_refresh_suggested_accounts)
	_refresh_suggested_accounts()
	_refresh()
	_consume_pending_post_presentations.call_deferred()
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
	var result: Array[Dictionary] = []
	var manager: Node = _social_manager()
	for post: Dictionary in source:
		var post_id: String = str(post.get("id", ""))
		if _revealing_post_ids.has(post_id):
			continue
		if manager != null and manager.is_post_presentation_pending(post_id):
			continue
		result.append(post)
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


func _on_post_published(post: SocialPostRecord) -> void:
	var manager: Node = _social_manager()
	if manager != null and post != null and manager.is_post_presentation_pending(post.post_id):
		return
	_request_refresh()


func _on_post_presentation_requested(post: SocialPostRecord) -> void:
	if post == null:
		return
	var manager: Node = _social_manager()
	if manager == null:
		return
	var candidate: Dictionary = manager.get_post_view_data(post.post_id)
	if not _post_matches_current_view(candidate):
		return
	var view_data: Dictionary = manager.consume_post_presentation(post.post_id)
	_queue_post_reveal(view_data)


func _consume_pending_post_presentations() -> void:
	var manager: Node = _social_manager()
	if manager == null:
		return
	for post_id: String in manager.get_pending_post_presentation_ids():
		var candidate: Dictionary = manager.get_post_view_data(post_id)
		if not _post_matches_current_view(candidate):
			continue
		_queue_post_reveal(manager.consume_post_presentation(post_id))


func _queue_post_reveal(view_data: Dictionary) -> void:
	if view_data.is_empty() or not _post_matches_current_view(view_data):
		_request_refresh()
		return
	var post_id: String = str(view_data.get("id", ""))
	if post_id.is_empty() or _revealing_post_ids.has(post_id):
		return
	_revealing_post_ids[post_id] = true
	_post_reveal_queue.append(view_data.duplicate(true))
	empty_state.visible = false
	if not _post_reveal_running:
		_run_next_post_reveal.call_deferred()


func _post_matches_current_view(view_data: Dictionary) -> bool:
	var route: Dictionary = _parse_route()
	var route_type: String = str(route.get("type", "home"))
	if route_type == "post":
		return str(route.get("id", "")) == str(view_data.get("id", ""))
	if route_type == "account" and str(route.get("id", "")) != str(view_data.get("account_id", "")):
		return false
	match _feed_mode:
		"streamer":
			if str(view_data.get("identity_type", "")) != SocialAccountProfile.IDENTITY_STREAMER:
				return false
		"personal":
			if str(view_data.get("identity_type", "")) != SocialAccountProfile.IDENTITY_PERSONAL:
				return false
	var keyword: String = search_field.text.strip_edges().to_lower()
	if keyword.is_empty():
		return true
	var searchable: String = "%s %s %s" % [
		str(view_data.get("display_name", "")),
		str(view_data.get("handle", "")),
		str(view_data.get("content", "")),
	]
	return searchable.to_lower().contains(keyword)


func _run_next_post_reveal() -> void:
	if _post_reveal_running or _post_reveal_queue.is_empty() or not is_inside_tree():
		return
	_post_reveal_running = true
	var view_data: Dictionary = _post_reveal_queue.pop_front()
	var slot := PanelContainer.new()
	slot.name = "IncomingPostSlot"
	slot.custom_minimum_size = Vector2(0.0, 0.0)
	slot.clip_contents = true
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color("#FFFFFF")
	slot_style.border_width_bottom = 1
	slot_style.border_color = Color("#E0E3E8")
	slot.add_theme_stylebox_override("panel", slot_style)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var loader := PostLoaderScene.instantiate() as LinkPostaPostLoader
	center.add_child(loader)
	slot.add_child(center)
	posts_container.add_child(slot)
	posts_container.move_child(slot, 0)
	var expand_tween: Tween = create_tween()
	expand_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	expand_tween.tween_property(slot, "custom_minimum_size:y", POST_REVEAL_HEIGHT, SLOT_EXPAND_SECONDS)
	await expand_tween.finished
	await get_tree().create_timer(LOADER_SECONDS).timeout
	if not is_instance_valid(slot):
		_post_reveal_running = false
		return
	var card := PostCardScene.instantiate() as LinkPostaPostCard
	card.configure(view_data)
	card.url_open_requested.connect(_open_url)
	card.image_open_requested.connect(_open_image)
	card.like_requested.connect(_set_post_liked)
	card.modulate.a = 0.0
	var slot_index: int = slot.get_index()
	posts_container.remove_child(slot)
	slot.queue_free()
	posts_container.add_child(card)
	posts_container.move_child(card, slot_index)
	var fade_tween: Tween = create_tween()
	fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(card, "modulate:a", 1.0, POST_FADE_SECONDS)
	await fade_tween.finished
	var revealed_post_id: String = str(view_data.get("id", ""))
	_revealing_post_ids.erase(revealed_post_id)
	var manager: Node = _social_manager()
	if manager != null:
		manager.complete_post_presentation(revealed_post_id)
	_post_reveal_running = false
	if not _post_reveal_queue.is_empty():
		_run_next_post_reveal.call_deferred()
	else:
		_refresh()


func _request_refresh() -> void:
	if _post_reveal_running or not _post_reveal_queue.is_empty():
		return
	_refresh()


func _on_post_like_changed(_post_id: String, _liked: bool, _likes: int) -> void:
	_request_refresh()
