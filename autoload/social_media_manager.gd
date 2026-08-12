extends Node
## 公开社交平台的账号、发布记录和动态网页入口。
## 玩家界面不暴露发布操作；剧情与行为系统通过 publish_* 接口触发角色发帖。

signal post_published(post: SocialPostRecord)
signal post_presentation_requested(post: SocialPostRecord)
signal post_presentation_completed(post: SocialPostRecord)
signal post_like_changed(post_id: String, liked: bool, likes: int)
signal post_reply_added(post_id: String, reply: SocialPostReplyRecord)
signal posts_reloaded()
signal recommended_accounts_changed()

const CHARACTER_CATALOG_PATH: String = "res://resources/characters/character_catalog.tres"
const LINKPOSTA_HOME_URL: String = "https://linkposta.net/"
const LINKPOSTA_ICON_PATH: String = "res://Assets/images/app_icons/linkposta.png"
const LINKPOSTA_SCENE_PATH: String = "res://scenes/apps/linkposta/linkposta_page.tscn"
const AMBIENT_AVATAR: Texture2D = preload("res://Assets/images/ui/linkposta/default_user_avatar.svg")
const GENERATED_REACH_MULTIPLIERS: Dictionary = {
	"low": 0.45,
	"normal": 0.85,
	"high": 1.55,
}
const GENERATED_PLAYER_STREAMER_AUDIENCE_FLOOR: int = 36
const GENERATED_NPC_STREAMER_AUDIENCE: int = 2400
const GENERATED_PERSONAL_AUDIENCE: int = 140

var _catalog: CharacterCatalog = null
var _posts: Array[SocialPostRecord] = []
var _pending_post_presentations: Array[String] = []


func _ready() -> void:
	_load_catalog()
	var game_state: Node = _get_game_state()
	if game_state != null and game_state.has_signal("state_loaded") \
		and not game_state.state_loaded.is_connected(_on_game_state_loaded):
		game_state.state_loaded.connect(_on_game_state_loaded)
	if game_state != null and game_state.has_signal("persona_changed") \
		and not game_state.persona_changed.is_connected(_on_persona_changed):
		game_state.persona_changed.connect(_on_persona_changed)
	var linkchat_manager: Node = _get_linkchat_manager()
	if linkchat_manager != null and linkchat_manager.has_signal("friendship_changed") \
		and not linkchat_manager.friendship_changed.is_connected(_on_friendship_changed):
		linkchat_manager.friendship_changed.connect(_on_friendship_changed)
	_reload_posts_from_game_state()
	_register_browser_provider.call_deferred()


func get_account(account_id: String) -> SocialAccountProfile:
	return _catalog.get_social_account(account_id) if _catalog != null else null


func get_character_for_account(account_id: String) -> CharacterProfile:
	return _catalog.get_character_for_social_account(account_id) if _catalog != null else null


func get_active_player_streamer_account() -> SocialAccountProfile:
	var player: CharacterProfile = _catalog.get_player_character() if _catalog != null else null
	return _get_active_player_streamer_account(player)


func get_character_account(character_id: String, identity_type: String) -> SocialAccountProfile:
	var character: CharacterProfile = _catalog.get_character(character_id) if _catalog != null else null
	if character == null:
		return null
	for account: SocialAccountProfile in character.social_accounts:
		if account != null and account.platform_id == "linkposta" and account.identity_type == identity_type:
			return account
	return null


func publish_post(
	account_id: String,
	text_content: String,
	texture_content: Texture2D = null,
	linked_url: String = "",
	source_session_id: String = "",
	present_as_new: bool = false
) -> SocialPostRecord:
	var content := PostContent.new()
	content.text_content = text_content
	content.texture_content = texture_content
	content.linked_url = linked_url
	return publish_post_content(account_id, content, source_session_id, present_as_new)


func publish_generated_post(
	account_id: String,
	text_content: String,
	reach: String,
	comments: Array[Dictionary],
	source_session_id: String = "",
	present_as_new: bool = false
) -> SocialPostRecord:
	var content := PostContent.new()
	content.text_content = text_content
	var record: SocialPostRecord = _create_post_record(account_id, content, source_session_id)
	if record == null:
		return null
	_apply_generated_interactions(record, reach, comments)
	return _commit_post_record(record, present_as_new)


func publish_character_post(
	character_id: String,
	account_id: String,
	content_id: String,
	source_session_id: String = "",
	present_as_new: bool = false
) -> SocialPostRecord:
	var character: CharacterProfile = _catalog.get_character(character_id) if _catalog != null else null
	if character == null:
		return null
	var account: SocialAccountProfile = character.get_social_account(account_id)
	if account == null:
		return null
	return publish_post_content(
		account_id,
		account.get_post_content(content_id),
		source_session_id,
		present_as_new
	)


func publish_post_content(
	account_id: String,
	content: PostContent,
	source_session_id: String = "",
	present_as_new: bool = false
) -> SocialPostRecord:
	var record: SocialPostRecord = _create_post_record(account_id, content, source_session_id)
	return _commit_post_record(record, present_as_new) if record != null else null


func _create_post_record(
	account_id: String,
	content: PostContent,
	source_session_id: String
) -> SocialPostRecord:
	var account: SocialAccountProfile = get_account(account_id)
	var game_state: Node = _get_game_state()
	if account == null or content == null or content.is_empty() or game_state == null:
		return null
	game_state.social_post_serial += 1
	var record := SocialPostRecord.new()
	record.post_id = "social_%06d" % game_state.social_post_serial
	record.author_account_id = account_id
	record.source_session_id = source_session_id.strip_edges()
	record.content = content.duplicate(true) as PostContent
	record.published_at = int(Time.get_unix_time_from_system())
	return record


func _commit_post_record(record: SocialPostRecord, present_as_new: bool) -> SocialPostRecord:
	if record == null:
		return null
	_posts.push_front(record)
	if present_as_new:
		_pending_post_presentations.append(record.post_id)
	_sync_posts_to_game_state()
	post_published.emit(record)
	if present_as_new:
		post_presentation_requested.emit(record)
	return record


func _apply_generated_interactions(
	record: SocialPostRecord,
	reach: String,
	comments: Array[Dictionary]
) -> void:
	var account: SocialAccountProfile = get_account(record.author_account_id)
	if account == null:
		return
	_append_generated_comments(record, comments)
	var metrics: Dictionary = _build_generated_metrics(
		account,
		reach,
		record.source_session_id if not record.source_session_id.is_empty() else record.post_id,
		record.reply_items.size()
	)
	record.likes = maxi(int(metrics.get("likes", 0)), 0)
	record.reposts = maxi(int(metrics.get("reposts", 0)), 0)
	record.replies = maxi(int(metrics.get("replies", 0)), record.reply_items.size())


func _append_generated_comments(record: SocialPostRecord, comments: Array[Dictionary]) -> void:
	var identity_seed: String = record.source_session_id if not record.source_session_id.is_empty() else record.post_id
	for comment: Dictionary in comments:
		var author_ref: String = str(comment.get("author_ref", "")).strip_edges()
		var text_content: String = str(comment.get("text", "")).strip_edges()
		if author_ref.is_empty() or text_content.is_empty():
			continue
		var reply := SocialPostReplyRecord.new()
		reply.reply_id = "%s_reply_%03d" % [record.post_id, record.reply_items.size() + 1]
		var author_account: SocialAccountProfile = get_account(author_ref)
		if author_account != null:
			reply.author_account_id = author_ref
		else:
			reply.author_display_name = author_ref
			reply.author_handle = _generated_ambient_handle(identity_seed, author_ref)
		reply.text_content = text_content
		reply.published_at = record.published_at
		record.reply_items.append(reply)


func _build_generated_metrics(
	account: SocialAccountProfile,
	reach: String,
	seed_key: String,
	visible_comment_count: int
) -> Dictionary:
	var game_state: Node = _get_game_state()
	var audience_size: int = GENERATED_PERSONAL_AUDIENCE
	var like_rate: float = 0.16
	var repost_rate: float = 0.012
	var reply_rate: float = 0.035
	if account.identity_type == SocialAccountProfile.IDENTITY_STREAMER:
		var active_streamer: SocialAccountProfile = get_active_player_streamer_account()
		if active_streamer != null and active_streamer.account_id == account.account_id and game_state != null:
			audience_size = maxi(int(game_state.get("fans")), GENERATED_PLAYER_STREAMER_AUDIENCE_FLOOR)
		else:
			audience_size = GENERATED_NPC_STREAMER_AUDIENCE
		like_rate = 0.11
		repost_rate = 0.026
		reply_rate = 0.018

	var normalized_reach: String = reach.strip_edges().to_lower()
	var reach_multiplier: float = float(GENERATED_REACH_MULTIPLIERS.get(normalized_reach, 0.85))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(("%s|%s" % [seed_key, account.account_id]).hash()) & 0x7fffffff
	var impressions: int = maxi(
		int(round(float(audience_size) * reach_multiplier * rng.randf_range(0.88, 1.14))),
		visible_comment_count
	)
	var likes: int = maxi(
		int(round(float(impressions) * like_rate * rng.randf_range(0.82, 1.18))),
		visible_comment_count * 2
	)
	var reposts: int = maxi(int(round(float(impressions) * repost_rate * rng.randf_range(0.75, 1.25))), 0)
	var replies: int = maxi(
		int(round(float(impressions) * reply_rate * rng.randf_range(0.82, 1.22))),
		visible_comment_count
	)
	return {
		"likes": likes,
		"reposts": reposts,
		"replies": replies,
	}


func _generated_ambient_handle(seed_key: String, display_name: String) -> String:
	var stable_value: int = int(("%s|%s" % [seed_key, display_name]).hash()) & 0x7fffffff
	return "@lp_%06d" % (stable_value % 1000000)


func get_posts() -> Array[SocialPostRecord]:
	return _posts.duplicate()


func get_post(post_id: String) -> SocialPostRecord:
	for post: SocialPostRecord in _posts:
		if post != null and post.post_id == post_id:
			return post
	return null


func has_source_session_post(account_id: String, source_session_id: String) -> bool:
	var normalized_session_id: String = source_session_id.strip_edges()
	if normalized_session_id.is_empty():
		return false
	for post: SocialPostRecord in _posts:
		if post != null and post.author_account_id == account_id \
			and post.source_session_id == normalized_session_id:
			return true
	return false


func is_post_presentation_pending(post_id: String) -> bool:
	return post_id in _pending_post_presentations


func get_pending_post_presentation_ids() -> Array[String]:
	return _pending_post_presentations.duplicate()


func consume_pending_post_presentations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for post_id: String in _pending_post_presentations:
		var view_data: Dictionary = get_post_view_data(post_id)
		if not view_data.is_empty():
			result.append(view_data)
	_pending_post_presentations.clear()
	return result


func consume_post_presentation(post_id: String) -> Dictionary:
	if post_id not in _pending_post_presentations:
		return {}
	_pending_post_presentations.erase(post_id)
	return get_post_view_data(post_id)


func complete_post_presentation(post_id: String) -> bool:
	var post: SocialPostRecord = get_post(post_id)
	if post == null:
		return false
	post_presentation_completed.emit(post)
	return true


func get_feed_view_data(account_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized_account_id: String = account_id.strip_edges()
	for post: SocialPostRecord in _posts:
		if post == null:
			continue
		if not normalized_account_id.is_empty() and post.author_account_id != normalized_account_id:
			continue
		result.append(make_post_view_data(post))
	return result


func get_post_view_data(post_id: String) -> Dictionary:
	return make_post_view_data(get_post(post_id))


func get_recommended_account_view_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen_account_ids: Dictionary = {}
	if _catalog == null:
		return result

	var player: CharacterProfile = _catalog.get_player_character()
	var active_streamer_account: SocialAccountProfile = _get_active_player_streamer_account(player)
	_append_recommended_account(
		result,
		seen_account_ids,
		player,
		active_streamer_account,
		"active_player"
	)

	var linkchat_manager: Node = _get_linkchat_manager()
	if linkchat_manager == null or not linkchat_manager.has_method("get_friend_characters"):
		return result
	var friend_characters: Variant = linkchat_manager.call("get_friend_characters")
	if not friend_characters is Array:
		return result
	for friend_value: Variant in friend_characters:
		if not friend_value is CharacterProfile:
			continue
		var friend: CharacterProfile = friend_value as CharacterProfile
		if friend == null or friend == player:
			continue
		_append_character_accounts_by_identity(
			result,
			seen_account_ids,
			friend,
			SocialAccountProfile.IDENTITY_STREAMER
		)
		_append_character_accounts_by_identity(
			result,
			seen_account_ids,
			friend,
			SocialAccountProfile.IDENTITY_PERSONAL
		)
	return result


func _get_active_player_streamer_account(player: CharacterProfile) -> SocialAccountProfile:
	if player == null:
		return null
	var game_state: Node = _get_game_state()
	var active_persona_id: String = str(game_state.get("active_persona_id")) if game_state != null else ""
	if active_persona_id.is_empty():
		return null
	for account: SocialAccountProfile in player.social_accounts:
		if account == null or account.identity_type != SocialAccountProfile.IDENTITY_STREAMER:
			continue
		if account.streamer_persona != null \
			and String(account.streamer_persona.content_id) == active_persona_id:
			return account
	return null


func _append_character_accounts_by_identity(
	result: Array[Dictionary],
	seen_account_ids: Dictionary,
	character: CharacterProfile,
	identity_type: String
) -> void:
	for account: SocialAccountProfile in character.social_accounts:
		if account != null and account.identity_type == identity_type:
			_append_recommended_account(result, seen_account_ids, character, account, "friend")


func _append_recommended_account(
	result: Array[Dictionary],
	seen_account_ids: Dictionary,
	character: CharacterProfile,
	account: SocialAccountProfile,
	source: String
) -> void:
	if character == null or account == null or account.platform_id != "linkposta":
		return
	var account_id: String = account.account_id.strip_edges()
	if account_id.is_empty() or seen_account_ids.has(account_id):
		return
	seen_account_ids[account_id] = true
	result.append({
		"account_id": account_id,
		"account_url": "%s@%s" % [LINKPOSTA_HOME_URL, account_id],
		"character_id": character.character_id,
		"display_name": account.get_resolved_display_name(),
		"handle": account.handle,
		"avatar": account.get_resolved_avatar(),
		"bio": account.bio,
		"verified": account.verified,
		"identity_type": account.identity_type,
		"identity_label": _identity_label(account),
		"recommendation_source": source,
	})


func add_post_reply(
	post_id: String,
	author_account_id: String,
	text_content: String,
	published_at: int = 0,
	parent_reply_id: String = ""
) -> SocialPostReplyRecord:
	var post: SocialPostRecord = get_post(post_id)
	var account: SocialAccountProfile = get_account(author_account_id)
	if post == null or account == null:
		return null
	return _append_post_reply(
		post,
		author_account_id,
		"",
		"",
		text_content,
		published_at,
		parent_reply_id
	)


func add_ambient_post_reply(
	post_id: String,
	display_name: String,
	handle: String,
	text_content: String,
	published_at: int = 0,
	parent_reply_id: String = ""
) -> SocialPostReplyRecord:
	var post: SocialPostRecord = get_post(post_id)
	var normalized_display_name: String = display_name.strip_edges()
	var normalized_handle: String = _normalize_handle(handle)
	if post == null or normalized_display_name.is_empty() or normalized_handle.is_empty():
		return null
	return _append_post_reply(
		post,
		"",
		normalized_display_name,
		normalized_handle,
		text_content,
		published_at,
		parent_reply_id
	)


func _append_post_reply(
	post: SocialPostRecord,
	author_account_id: String,
	author_display_name: String,
	author_handle: String,
	text_content: String,
	published_at: int,
	parent_reply_id: String
) -> SocialPostReplyRecord:
	var normalized_content: String = text_content.strip_edges()
	if normalized_content.is_empty():
		return null
	var normalized_parent_id: String = parent_reply_id.strip_edges()
	if not normalized_parent_id.is_empty() and _find_reply(post, normalized_parent_id) == null:
		return null
	var reply := SocialPostReplyRecord.new()
	reply.reply_id = "%s_reply_%03d" % [post.post_id, post.reply_items.size() + 1]
	reply.author_account_id = author_account_id
	reply.author_display_name = author_display_name
	reply.author_handle = author_handle
	reply.parent_reply_id = normalized_parent_id
	reply.text_content = normalized_content
	reply.published_at = published_at if published_at > 0 else int(Time.get_unix_time_from_system())
	post.reply_items.append(reply)
	_sync_posts_to_game_state()
	post_reply_added.emit(post.post_id, reply)
	posts_reloaded.emit()
	return reply


func make_post_view_data(post: SocialPostRecord) -> Dictionary:
	if post == null:
		return {}
	var account: SocialAccountProfile = get_account(post.author_account_id)
	var character: CharacterProfile = get_character_for_account(post.author_account_id)
	var reply_items: Array[Dictionary] = []
	for reply: SocialPostReplyRecord in post.reply_items:
		if reply != null:
			reply_items.append(make_reply_view_data(reply, post))
	return {
		"id": post.post_id,
		"post_url": "%spost/%s" % [LINKPOSTA_HOME_URL, post.post_id],
		"account_url": "%s@%s" % [LINKPOSTA_HOME_URL, post.author_account_id],
		"account_id": post.author_account_id,
		"character_id": character.character_id if character != null else "",
		"display_name": account.get_resolved_display_name() if account != null else post.author_account_id,
		"handle": account.handle if account != null else "",
		"avatar": account.get_resolved_avatar() if account != null else null,
		"bio": account.bio if account != null else "",
		"verified": account.verified if account != null else false,
		"identity_type": account.identity_type if account != null else SocialAccountProfile.IDENTITY_PERSONAL,
		"identity_label": _identity_label(account),
		"content": post.content.text_content if post.content != null else "",
		"image": post.content.texture_content if post.content != null else null,
		"linked_url": post.content.linked_url if post.content != null else "",
		"time": _format_post_time(post.published_at),
		"liked": post.liked,
		"likes": post.likes,
		"reposts": post.reposts,
		"replies": post.replies,
		"reply_items": reply_items,
	}


func make_reply_view_data(
	reply: SocialPostReplyRecord,
	post: SocialPostRecord = null
) -> Dictionary:
	if reply == null:
		return {}
	var author: Dictionary = _make_reply_author_view_data(reply)
	var parent: SocialPostReplyRecord = _find_reply(post, reply.parent_reply_id)
	var parent_author: Dictionary = _make_reply_author_view_data(parent)
	return {
		"id": reply.reply_id,
		"parent_reply_id": reply.parent_reply_id,
		"account_id": str(author.get("account_id", "")),
		"account_url": str(author.get("account_url", "")),
		"display_name": str(author.get("display_name", "")),
		"handle": str(author.get("handle", "")),
		"avatar": author.get("avatar"),
		"is_ambient": bool(author.get("is_ambient", false)),
		"content": reply.text_content,
		"time": _format_post_time(reply.published_at),
		"depth": _get_reply_depth(post, reply),
		"reply_to_display_name": str(parent_author.get("display_name", "")),
		"reply_to_handle": str(parent_author.get("handle", "")),
	}


func _make_reply_author_view_data(reply: SocialPostReplyRecord) -> Dictionary:
	if reply == null:
		return {}
	var account: SocialAccountProfile = get_account(reply.author_account_id)
	if account != null:
		return {
			"account_id": reply.author_account_id,
			"account_url": "%s@%s" % [LINKPOSTA_HOME_URL, reply.author_account_id],
			"display_name": account.get_resolved_display_name(),
			"handle": account.handle,
			"avatar": account.get_resolved_avatar(),
			"is_ambient": false,
		}
	return {
		"account_id": "",
		"account_url": "",
		"display_name": reply.author_display_name,
		"handle": reply.author_handle,
		"avatar": AMBIENT_AVATAR,
		"is_ambient": true,
	}


func _normalize_handle(value: String) -> String:
	var normalized: String = value.strip_edges().replace(" ", "")
	if normalized.is_empty() or normalized == "@":
		return ""
	return normalized if normalized.begins_with("@") else "@" + normalized


func _find_reply(post: SocialPostRecord, reply_id: String) -> SocialPostReplyRecord:
	if post == null or reply_id.is_empty():
		return null
	for reply: SocialPostReplyRecord in post.reply_items:
		if reply != null and reply.reply_id == reply_id:
			return reply
	return null


func _get_reply_depth(post: SocialPostRecord, reply: SocialPostReplyRecord) -> int:
	if post == null or reply == null:
		return 0
	var depth: int = 0
	var parent_id: String = reply.parent_reply_id
	var visited: Dictionary = {}
	while not parent_id.is_empty() and depth < 8 and not visited.has(parent_id):
		visited[parent_id] = true
		var parent: SocialPostReplyRecord = _find_reply(post, parent_id)
		if parent == null:
			break
		depth += 1
		parent_id = parent.parent_reply_id
	return depth


func set_post_liked(post_id: String, liked: bool) -> bool:
	var post: SocialPostRecord = get_post(post_id)
	if post == null:
		return false
	if post.liked == liked:
		return true
	post.liked = liked
	post.likes = maxi(post.likes + (1 if liked else -1), 0)
	_sync_posts_to_game_state()
	post_like_changed.emit(post_id, liked, post.likes)
	return true


func set_post_metrics(post_id: String, likes: int, reposts: int, replies: int) -> bool:
	var post: SocialPostRecord = get_post(post_id)
	if post == null:
		return false
	post.likes = maxi(likes, 0)
	post.reposts = maxi(reposts, 0)
	post.replies = maxi(replies, 0)
	_sync_posts_to_game_state()
	posts_reloaded.emit()
	return true


func reset_runtime_state() -> void:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	game_state.social_posts.clear()
	game_state.social_post_serial = 0
	_posts.clear()
	_pending_post_presentations.clear()
	posts_reloaded.emit()


func handles_linkposta_url(url: String) -> bool:
	var normalized: String = url.strip_edges().to_lower()
	normalized = normalized.trim_prefix("https://").trim_prefix("http://")
	return normalized == "linkposta.net" or normalized.begins_with("linkposta.net/")


func build_linkposta_page(url: String) -> Dictionary:
	if not handles_linkposta_url(url):
		return {}
	var title: String = "LinkPosta · 正在发生"
	var normalized: String = url.strip_edges().trim_suffix("/")
	if normalized.contains("/post/"):
		var post_id: String = normalized.get_slice("/post/", 1)
		var post_data: Dictionary = get_post_view_data(post_id)
		if not post_data.is_empty():
			title = "%s 的帖子 · LinkPosta" % str(post_data.get("display_name", ""))
	elif normalized.contains("/@"):
		var account_id: String = normalized.get_slice("/@", 1)
		var account: SocialAccountProfile = get_account(account_id)
		if account != null:
			title = "%s · LinkPosta" % account.get_resolved_display_name()
	return {
		"scene_path": LINKPOSTA_SCENE_PATH,
		"title": title,
		"icon_path": LINKPOSTA_ICON_PATH,
		"site_id": "linkposta",
		"owns_scroll": true,
	}


func _register_browser_provider() -> void:
	var browser_manager: Node = get_node_or_null("/root/BrowserManager")
	if browser_manager != null and browser_manager.has_method("register_page_provider"):
		browser_manager.register_page_provider(
			"linkposta",
			Callable(self, "handles_linkposta_url"),
			Callable(self, "build_linkposta_page")
		)


func _load_catalog() -> void:
	if ResourceLoader.exists(CHARACTER_CATALOG_PATH):
		_catalog = ResourceLoader.load(CHARACTER_CATALOG_PATH) as CharacterCatalog
	if _catalog == null:
		push_error("SocialMediaManager: character catalog is unavailable")


func _reload_posts_from_game_state() -> void:
	_posts.clear()
	_pending_post_presentations.clear()
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	for value: Variant in game_state.social_posts:
		if value is Dictionary:
			_posts.append(SocialPostRecord.from_dict(value))


func _sync_posts_to_game_state() -> void:
	var game_state: Node = _get_game_state()
	if game_state == null:
		return
	game_state.social_posts.clear()
	for post: SocialPostRecord in _posts:
		if post != null:
			game_state.social_posts.append(post.to_dict())


func _on_game_state_loaded() -> void:
	_reload_posts_from_game_state()
	posts_reloaded.emit()
	recommended_accounts_changed.emit()


func _on_persona_changed(_old_persona_id: String, _new_persona_id: String) -> void:
	recommended_accounts_changed.emit()


func _on_friendship_changed(_character_id: String, _is_friend: bool) -> void:
	recommended_accounts_changed.emit()


func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _get_linkchat_manager() -> Node:
	return get_node_or_null("/root/LinkChatManager")


func _identity_label(account: SocialAccountProfile) -> String:
	if account != null and account.identity_type == SocialAccountProfile.IDENTITY_STREAMER:
		return "主播账号"
	return "个人账号"


func _format_post_time(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var value: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d-%02d %02d:%02d" % [
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
	]
