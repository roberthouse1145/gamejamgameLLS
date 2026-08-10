extends Node
## LinkChatManager 稳定契约：角色资料、好友可见性、纯内容发布和存档快照。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_character_catalog()
	_test_friend_visibility_and_publish()
	_test_serialized_post_state()
	print("[TestLinkChatManager] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("[TestLinkChatManager] PASS: " + test_name)
	else:
		_failed += 1
		push_error("[TestLinkChatManager] FAIL: " + test_name)


func _test_character_catalog() -> void:
	var player: CharacterProfile = LinkChatManager.get_player_character()
	var friend: CharacterProfile = LinkChatManager.get_character("lu_yuanyuan")
	_check(player != null and player.character_id == "ruan_yunyou", "角色目录提供玩家资料")
	_check(friend != null and friend.linkchat_profile.account_name == "鸢鸢", "角色拥有 LinkChat 账号资料")


func _test_friend_visibility_and_publish() -> void:
	LinkChatManager.reset_runtime_state(false)
	var post: MomentPostRecord = LinkChatManager.publish_moment("su_he", "下班路上。", null)
	_check(post != null and post.character_id == "su_he", "角色可发布纯内容动态")
	_check(post.content != null and post.content.text_content == "下班路上。", "MomentContent 不包含作者显示资料")
	_check(LinkChatManager.get_visible_moments().is_empty(), "非好友动态默认不可见")
	_check(LinkChatManager.add_friend("su_he"), "可按角色 ID 添加好友")
	var visible: Array[MomentPostRecord] = LinkChatManager.get_visible_moments()
	_check(visible.size() == 1 and visible[0] == post, "添加好友后可看到既有动态")
	var view_data: Dictionary = LinkChatManager.make_moment_view_data(post)
	_check(view_data.get("author_name") == "苏禾" and view_data.get("content") == "下班路上。", "显示资料由角色账号补充")
	_check(LinkChatManager.set_moment_liked(post.post_id, true) and post.likes == 1, "点赞状态写回发布记录")
	var comment: MomentCommentRecord = LinkChatManager.add_moment_comment(
		post.post_id,
		"ruan_yunyou",
		"记得带伞。"
	)
	_check(comment != null and comment.text_content == "记得带伞。", "角色可评论已发布动态")
	view_data = LinkChatManager.make_moment_view_data(post)
	var comments: Array = view_data.get("comments", [])
	_check(
		comments.size() == 1 and comments[0].get("author_name") == "柚柚",
		"评论显示资料由评论角色账号补充"
	)


func _test_serialized_post_state() -> void:
	var snapshot: Dictionary = GameState.to_dict()
	var posts: Array = snapshot.get("linkchat_moment_posts", [])
	_check(posts.size() == 1 and posts[0].get("character_id") == "su_he", "发布记录进入 GameState 存档")
	_check(JSON.stringify(snapshot).contains("下班路上。"), "朋友圈状态可序列化为 JSON")
	_check(JSON.stringify(snapshot).contains("记得带伞。"), "评论随发布记录进入 GameState 存档")
