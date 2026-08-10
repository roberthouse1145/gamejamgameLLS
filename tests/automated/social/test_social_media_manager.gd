extends Node
## 公开社交平台稳定契约：角色多身份、纯内容发布、存档记录与动态网页提供者。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var original_state: Dictionary = GameState.to_dict()
	_test_accounts_and_publish()
	await _test_browser_provider()
	GameState.from_dict(original_state)
	print("[TestSocialMediaManager] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _test_accounts_and_publish() -> void:
	LinkChatManager.reset_runtime_state(true)
	SocialMediaManager.reset_runtime_state()
	var streamer_account: SocialAccountProfile = SocialMediaManager.get_account("yunyou_streamer")
	var personal_account: SocialAccountProfile = SocialMediaManager.get_account("yunyou_personal")
	_check(streamer_account != null and streamer_account.identity_type == "streamer", "角色拥有主播账号")
	_check(streamer_account != null and streamer_account.streamer_persona != null, "主播账号显式引用人设卡")
	_check(personal_account != null and personal_account.identity_type == "personal", "同一角色也可拥有个人账号")
	var recommended_accounts: Array[Dictionary] = SocialMediaManager.get_recommended_account_view_data()
	var recommended_ids: Array[String] = []
	for recommended_account: Dictionary in recommended_accounts:
		recommended_ids.append(str(recommended_account.get("account_id", "")))
	_check(
		recommended_ids == ["yunyou_streamer", "yuanyuan_streamer", "yuanyuan_personal"],
		"推荐账号由当前直播账号和 LinkChat 好友账号生成"
	)
	_check(
		recommended_accounts.size() >= 2 \
		and recommended_accounts[0].get("recommendation_source") == "active_player" \
		and recommended_accounts[1].get("recommendation_source") == "friend",
		"推荐数据保留玩家当前账号与好友账号的来源"
	)
	var recommendation_events: Array[String] = []
	var capture_recommendation_change := func() -> void:
		recommendation_events.append("changed")
	SocialMediaManager.recommended_accounts_changed.connect(capture_recommendation_change)
	LinkChatManager.remove_friend("lu_yuanyuan")
	recommended_accounts = SocialMediaManager.get_recommended_account_view_data()
	_check(
		recommended_accounts.size() == 1 \
		and recommended_accounts[0].get("account_id") == "yunyou_streamer",
		"移除 LinkChat 好友后推荐账号立即更新"
	)
	LinkChatManager.add_friend("lu_yuanyuan")
	GameState.persona_changed.emit(GameState.active_persona_id, GameState.active_persona_id)
	_check(
		recommendation_events.size() == 3,
		"好友变化和当前直播人设变化都会通知推荐列表刷新"
	)
	SocialMediaManager.recommended_accounts_changed.disconnect(capture_recommendation_change)

	var post: SocialPostRecord = SocialMediaManager.publish_character_post(
		"ruan_yunyou",
		"yunyou_streamer",
		"first_stream_notice"
	)
	_check(post != null and post.author_account_id == "yunyou_streamer", "游戏行为可按角色、账号和内容 ID 发帖")
	_check(post != null and post.content != null and post.content.content_id == "first_stream_notice", "纯内容模板不承担作者资料")
	var view_data: Dictionary = SocialMediaManager.get_post_view_data(post.post_id if post != null else "")
	_check(view_data.get("display_name") == "白星眠", "主播身份使用人设卡的频道名")
	_check(
		streamer_account != null and view_data.get("avatar") == streamer_account.streamer_persona.channel_avatar,
		"主播身份使用人设卡的频道头像"
	)
	_check(view_data.get("identity_label") == "主播账号", "帖子明确标识发布身份")
	var reply: SocialPostReplyRecord = SocialMediaManager.add_post_reply(
		post.post_id,
		"yuanyuan_personal",
		"今晚再确认一次流程。"
	)
	var ambient_reply: SocialPostReplyRecord = SocialMediaManager.add_ambient_post_reply(
		post.post_id,
		"星屑收集员",
		"hoshikuzu_31",
		"新人首播会留回放吗？",
		0,
		reply.reply_id if reply != null else ""
	)
	var nested_reply: SocialPostReplyRecord = SocialMediaManager.add_post_reply(
		post.post_id,
		"yunyou_streamer",
		"收到，我会提前上线。",
		0,
		ambient_reply.reply_id if ambient_reply != null else ""
	)
	SocialMediaManager.set_post_metrics(post.post_id, 0, 7, 92)
	view_data = SocialMediaManager.get_post_view_data(post.post_id)
	var reply_items: Variant = view_data.get("reply_items", [])
	_check(reply != null and reply_items is Array and reply_items.size() == 3, "帖子保存并显示真实回复记录")
	var ambient_view: Dictionary = reply_items[1] if reply_items is Array and reply_items.size() > 1 else {}
	_check(
		ambient_reply != null and ambient_reply.author_account_id.is_empty() \
		and ambient_reply.author_display_name == "星屑收集员" \
		and ambient_view.get("is_ambient") == true \
		and ambient_view.get("handle") == "@hoshikuzu_31" \
		and ambient_view.get("avatar") is Texture2D \
		and ambient_view.get("account_url") == "",
		"一次性路人身份以内联快照保存并使用默认头像"
	)
	var nested_view: Dictionary = reply_items[2] if reply_items is Array and reply_items.size() > 2 else {}
	_check(
		ambient_reply != null and nested_reply != null \
		and nested_view.get("parent_reply_id") == ambient_reply.reply_id \
		and nested_view.get("depth") == 2 \
		and nested_view.get("reply_to_handle") == "@hoshikuzu_31",
		"注册账号可以继续回复路人并生成多层对话"
	)
	_check(view_data.get("replies") == 92, "回复指标与实际回复记录数量相互独立")
	_check(SocialMediaManager.set_post_liked(post.post_id, true) and post.likes == 1, "点赞状态写回发布记录")
	var snapshots: Array = GameState.to_dict().get("social_posts", [])
	_check(snapshots.size() == 1 and snapshots[0].get("liked") == true, "发布记录进入 GameState 存档")
	var saved_replies: Array = snapshots[0].get("reply_items", []) if not snapshots.is_empty() else []
	_check(
		saved_replies.size() == 3 and saved_replies[1].get("author_display_name") == "星屑收集员",
		"路人身份快照随回复进入存档"
	)


func _test_browser_provider() -> void:
	_check(BrowserManager.has_page_provider_for("https://linkposta.net/"), "LinkPosta 注册为动态网页提供者")
	var page_scene: PackedScene = load("res://scenes/apps/linkposta/linkposta_page.tscn") as PackedScene
	_check(page_scene != null, "LinkPosta 场景页面可被浏览器加载")
	var app_definition: Resource = AppManager.get_app_definition("linkposta")
	_check(
		app_definition != null and app_definition.launch_url == "https://linkposta.net/",
		"桌面入口是复用 Browser 的 Web 快捷应用"
	)
	var completed: Array[Dictionary] = []
	var capture := func(_request_id: String, url: String, content: Dictionary) -> void:
		if url == "https://linkposta.net/":
			completed.append(content)
	BrowserManager.page_generated.connect(capture)
	BrowserManager.open_page("https://linkposta.net/")
	await get_tree().process_frame
	if BrowserManager.page_generated.is_connected(capture):
		BrowserManager.page_generated.disconnect(capture)
	_check(not completed.is_empty(), "LinkPosta 页面无需 LLM 即可打开")
	_check(
		not completed.is_empty() and completed[0].get("scene_path") == "res://scenes/apps/linkposta/linkposta_page.tscn",
		"动态网页使用 LinkPosta 场景页面"
	)
	_check(
		not completed.is_empty() and completed[0].get("owns_scroll") == true,
		"LinkPosta 场景页拥有独立信息流滚动区"
	)


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("[TestSocialMediaManager] PASS: " + test_name)
	else:
		_failed += 1
		push_error("[TestSocialMediaManager] FAIL: " + test_name)
