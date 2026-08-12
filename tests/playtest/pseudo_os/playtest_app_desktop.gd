extends Node
## 独立 APP 验收入口的初始化器。场景根节点直接继承真实 Desktop，不经过 Main Game。

const SOCIAL_POST_SEEDS: Array[Dictionary] = [
	{
		"character_id": "lu_yuanyuan",
		"account_id": "yuanyuan_personal",
		"content_id": "someone_started",
		"age_seconds": 11 * 60 * 60,
		"likes": 48,
		"reposts": 6,
		"replies": 3,
		"reply_items": [
			{"reply_key": "root", "account_id": "yunyou_personal", "content": "看到了。请不要在评论区点名。"},
			{"reply_key": "answer", "parent_key": "root", "account_id": "yuanyuan_personal", "content": "我没有写名字。"},
			{"reply_key": "follow_up", "parent_key": "answer", "account_id": "yunyou_personal", "content": "但所有人都知道你在说谁。"},
		],
	},
	{
		"character_id": "ruan_yunyou",
		"account_id": "yunyou_personal",
		"content_id": "desk_cleanup",
		"age_seconds": 7 * 60 * 60,
		"likes": 21,
		"reposts": 2,
		"replies": 5,
		"reply_items": [
			{"reply_key": "root", "account_id": "yuanyuan_personal", "content": "先把桌面右边那摞收掉。"},
			{"reply_key": "answer", "parent_key": "root", "account_id": "yunyou_personal", "content": "那摞是按使用频率排序的。"},
			{"reply_key": "follow_up", "parent_key": "answer", "account_id": "yuanyuan_personal", "content": "最下面那本落灰了。"},
		],
	},
	{
		"character_id": "lu_yuanyuan",
		"account_id": "yuanyuan_streamer",
		"content_id": "collab_notice",
		"age_seconds": 2 * 60 * 60,
		"likes": 1842,
		"reposts": 216,
		"replies": 97,
		"reply_items": [
			{"reply_key": "root", "display_name": "晚风邮差", "handle": "@evening_post_47", "content": "这次联动几点开始？"},
			{"reply_key": "answer", "parent_key": "root", "account_id": "yuanyuan_streamer", "content": "周六 20:00，开播前会再发一次提醒。"},
			{"reply_key": "follow_up", "parent_key": "answer", "account_id": "yunyou_streamer", "content": "设备和流程今晚会再确认一次。"},
		],
	},
	{
		"character_id": "ruan_yunyou",
		"account_id": "yunyou_streamer",
		"content_id": "first_stream_notice",
		"age_seconds": 18 * 60,
		"likes": 126,
		"reposts": 18,
		"replies": 34,
		"reply_items": [
			{"reply_key": "root", "display_name": "星屑收集员", "handle": "@hoshikuzu_31", "content": "新人首播会留回放吗？"},
			{"reply_key": "answer", "parent_key": "root", "account_id": "yunyou_streamer", "content": "会，结束后整理到主页。"},
			{"reply_key": "follow_up", "parent_key": "answer", "account_id": "yuanyuan_streamer", "content": "先顺利播完，再整理回放。"},
		],
	},
]

const PLAYTEST_INITIAL_MONEY: int = 5000
const PLAYTEST_INITIAL_FANS: int = 1280
const PLAYTEST_INITIAL_STRESS: int = 28
const PLAYTEST_INITIAL_OTAKU_DESIRE: int = 46
const PLAYTEST_INITIAL_LONELINESS: int = 34


func _ready() -> void:
	call_deferred("_initialize_playtest")


func _initialize_playtest() -> void:
	GameState.add_money(PLAYTEST_INITIAL_MONEY - GameState.money)
	GameState.set_fans(PLAYTEST_INITIAL_FANS)
	GameState.set_attribute(GameState.ATTR_STRESS, PLAYTEST_INITIAL_STRESS)
	GameState.set_attribute(GameState.ATTR_OTAKU_DESIRE, PLAYTEST_INITIAL_OTAKU_DESIRE)
	GameState.set_attribute(GameState.ATTR_LONELINESS, PLAYTEST_INITIAL_LONELINESS)
	GameState.day = 1
	GameState.time_slot = GameState.TIME_SLOT_MORNING
	GameState.failed_date_invites.clear()
	var linkchat_manager: Node = get_node_or_null("/root/LinkChatManager")
	if linkchat_manager == null:
		push_error("PlaytestAppDesktop: LinkChatManager is unavailable")
		return

	linkchat_manager.reset_runtime_state(true)
	var mail_manager: Node = get_node_or_null("/root/MailManager")
	if mail_manager == null:
		push_error("PlaytestAppDesktop: MailManager is unavailable")
		return
	mail_manager.reset_runtime_state()
	var older_mail: Dictionary = mail_manager.receive_mail(
		"系统邮件",
		"service@example.test",
		"服务状态通知",
		"这是一封用于检查已读样式、正文行距与长文本换行的中性示例邮件。\n\n邮件阅读区应保持舒适的留白，并允许正文自然向下滚动。",
		"第1天 · 08:30"
	)
	mail_manager.mark_read(str(older_mail.get("mail_id", "")))
	mail_manager.receive_mail(
		"匿名发件人",
		"",
		"留给你的消息",
		"门边的信封里还有一张纸。等四周安静下来，再独自拆开。\n\n不要回复这封邮件。",
		"第1天 · 09:10"
	)
	var social_manager: Node = get_node_or_null("/root/SocialMediaManager")
	if social_manager == null:
		push_error("PlaytestAppDesktop: SocialMediaManager is unavailable")
		return
	social_manager.reset_runtime_state()
	_seed_social_posts(social_manager)
	print("[Playtest] APP desktop initialized; waiting for manual interaction")


func _seed_social_posts(social_manager: Node) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	for social_post_seed: Dictionary in SOCIAL_POST_SEEDS:
		var post: SocialPostRecord = social_manager.publish_character_post(
			str(social_post_seed.get("character_id", "")),
			str(social_post_seed.get("account_id", "")),
			str(social_post_seed.get("content_id", ""))
		) as SocialPostRecord
		if post == null:
			push_error("PlaytestAppDesktop: failed to publish social post %s" % str(social_post_seed.get("content_id", "")))
			continue
		post.published_at = now - int(social_post_seed.get("age_seconds", 0))
		social_manager.set_post_metrics(
			post.post_id,
			int(social_post_seed.get("likes", 0)),
			int(social_post_seed.get("reposts", 0)),
			int(social_post_seed.get("replies", 0))
		)
		var reply_items: Variant = social_post_seed.get("reply_items", [])
		var reply_ids_by_key: Dictionary = {}
		var reply_index: int = 0
		if reply_items is Array:
			for reply_value: Variant in reply_items:
				if not reply_value is Dictionary:
					continue
				var reply: Dictionary = reply_value
				var parent_key: String = str(reply.get("parent_key", ""))
				var parent_reply_id: String = str(reply_ids_by_key.get(parent_key, ""))
				var account_id: String = str(reply.get("account_id", ""))
				var created_reply: SocialPostReplyRecord = null
				if account_id.is_empty():
					created_reply = social_manager.add_ambient_post_reply(
						post.post_id,
						str(reply.get("display_name", "")),
						str(reply.get("handle", "")),
						str(reply.get("content", "")),
						post.published_at + (reply_index + 1) * 5 * 60,
						parent_reply_id
					) as SocialPostReplyRecord
				else:
					created_reply = social_manager.add_post_reply(
						post.post_id,
						account_id,
						str(reply.get("content", "")),
						post.published_at + (reply_index + 1) * 5 * 60,
						parent_reply_id
					) as SocialPostReplyRecord
				if created_reply != null:
					var reply_key: String = str(reply.get("reply_key", ""))
					if not reply_key.is_empty():
						reply_ids_by_key[reply_key] = created_reply.reply_id
				reply_index += 1
