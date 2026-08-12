extends Node
## 公开社交平台稳定契约：角色多身份、纯内容发布、存档记录与动态网页提供者。

const PostDSLParserClass = preload("res://scripts/social/post_dsl_parser.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var original_state: Dictionary = GameState.to_dict()
	_test_post_dsl()
	_test_accounts_and_publish()
	_test_generated_post_package()
	await _test_browser_provider()
	GameState.from_dict(original_state)
	print("[TestSocialMediaManager] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _test_post_dsl() -> void:
	var parser: RefCounted = PostDSLParserClass.new()
	var result: Dictionary = parser.call("parse", """```text
POST account_a
TEXT
她写道：\"今天很好。\"
JSON 样式符号也会原样保留：{\"key\": \"value\"}
END_TEXT
MEDIA NONE
REACH NORMAL
COMMENT yuanyuan_personal
她今天看起来确实很开心。
END_COMMENT
COMMENT 星屑收集员
下次也想去看看。
END_COMMENT
END_POST
```

```text
POST account_b
TEXT
配图描述也使用独立块。
END_TEXT
MEDIA GENERATE
IMAGE_PROMPT
河岸晨光，两个人的背影，写实摄影风格。
END_IMAGE_PROMPT
REACH HIGH
COMMENT 河岸摄影部
这个光线一定很好看。
END_COMMENT
END_POST
```

```postdsl
POST account_c
TEXT
已有素材使用明确引用。
END_TEXT
MEDIA ASSET res://provided/outing_photo.png
REACH LOW
COMMENT account_a
照片收到了。
END_COMMENT
END_POST
```""") as Dictionary
	var posts: Array[Dictionary] = []
	posts.assign(result.get("posts", []))
	_check(bool(result.get("success", false)) and posts.size() == 3, "Post DSL 可解析多账号发布块")
	_check(
		posts.size() >= 1 and str(posts[0].get("text", "")).contains("{\"key\": \"value\"}"),
		"正文中的引号与类 JSON 符号无需转义即可保留"
	)
	_check(
		posts.size() >= 2 \
			and posts[1].get("media_mode") == PostDSLParserClass.MEDIA_GENERATE \
			and not str(posts[1].get("image_prompt", "")).is_empty(),
		"Post DSL 为美术生成提示词保留独立媒体块"
	)
	_check(
		posts.size() >= 3 \
			and posts[2].get("media_mode") == PostDSLParserClass.MEDIA_ASSET \
			and posts[2].get("asset_ref") == "res://provided/outing_photo.png",
		"Post DSL 可携带已提供素材的明确引用"
	)
	var first_comments: Array[Dictionary] = []
	if not posts.is_empty():
		first_comments.assign(posts[0].get("comments", []))
	_check(
		posts.size() >= 1 and posts[0].get("reach") == PostDSLParserClass.REACH_NORMAL,
		"Post DSL 保留模型选择的传播档位"
	)
	_check(
		first_comments.size() == 2 \
			and first_comments[0].get("author_ref") == "yuanyuan_personal" \
			and first_comments[1].get("author_ref") == "星屑收集员",
		"COMMENT 统一保留注册账号 ID 或粉丝显示名称"
	)


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
		"first_stream_notice",
		"test_outing_session",
		true
	)
	_check(post != null and post.author_account_id == "yunyou_streamer", "游戏行为可按角色、账号和内容 ID 发帖")
	_check(post != null and post.source_session_id == "test_outing_session", "帖子保留来源会话用于发布幂等")
	var pending_presentations: Array[Dictionary] = SocialMediaManager.consume_pending_post_presentations()
	_check(pending_presentations.size() == 1, "新帖发布可交给页面消费展示动画")
	var completed_presentations: Array[String] = []
	var capture_presentation_complete := func(completed_post: SocialPostRecord) -> void:
		completed_presentations.append(completed_post.post_id)
	SocialMediaManager.post_presentation_completed.connect(capture_presentation_complete)
	SocialMediaManager.complete_post_presentation(post.post_id)
	SocialMediaManager.post_presentation_completed.disconnect(capture_presentation_complete)
	_check(completed_presentations == [post.post_id], "页面可在新帖淡入后确认展示完成")
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


func _test_generated_post_package() -> void:
	SocialMediaManager.reset_runtime_state()
	GameState.set_fans(1200)
	var published_records: Array[SocialPostRecord] = []
	var capture_generated_post := func(value: SocialPostRecord) -> void:
		published_records.append(value)
	SocialMediaManager.post_published.connect(capture_generated_post)
	var comments: Array[Dictionary] = [
		{
			"author_ref": "yuanyuan_personal",
			"text": "今晚记得早点休息。",
		},
		{
			"author_ref": "星屑收集员",
			"text": "明晚直播间见！",
		},
	]
	var post: SocialPostRecord = SocialMediaManager.publish_generated_post(
		"yunyou_streamer",
		"今天休息得很好，明晚直播间见。",
		PostDSLParserClass.REACH_NORMAL,
		comments,
		"generated_post_contract",
		true
	)
	SocialMediaManager.post_published.disconnect(capture_generated_post)
	_check(
		post != null and published_records.size() == 1 \
			and published_records[0].reply_items.size() == 2 \
			and published_records[0].replies >= published_records[0].reply_items.size(),
		"生成帖子在发布信号发出前已原子写入互动指标与展示评论"
	)
	var registered_reply: SocialPostReplyRecord = post.reply_items[0] if post != null and post.reply_items.size() >= 1 else null
	var ambient_reply: SocialPostReplyRecord = post.reply_items[1] if post != null and post.reply_items.size() >= 2 else null
	_check(
		registered_reply != null and registered_reply.author_account_id == "yuanyuan_personal",
		"COMMENT 命中账号 ID 时使用正式社交账号回复"
	)
	_check(
		ambient_reply != null and ambient_reply.author_account_id.is_empty() \
			and ambient_reply.author_display_name == "星屑收集员" \
			and ambient_reply.author_handle.begins_with("@"),
		"COMMENT 未命中账号 ID 时以原文作为粉丝名称并生成稳定 handle"
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
