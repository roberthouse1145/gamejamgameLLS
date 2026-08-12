extends Node
## LinkChatManager 稳定契约：角色目录、好友关系、私聊消息和存档快照。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_character_catalog()
	_test_friendship_and_message_storage()
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


func _test_friendship_and_message_storage() -> void:
	LinkChatManager.reset_runtime_state(false)
	_check(LinkChatManager.add_friend("su_he"), "可按角色 ID 添加好友")
	_check(LinkChatManager.is_friend("su_he"), "好友关系写入运行时状态")
	var message: Dictionary = LinkChatManager.append_message(
		"su_he",
		"ruan_yunyou",
		"测试消息",
		{},
		"test_session"
	)
	_check(not message.is_empty(), "有效私聊消息可写入")
	var messages: Array[Dictionary] = LinkChatManager.get_thread_messages("su_he")
	_check(messages.size() == 1 and messages[0].get("source_session_id") == "test_session", "会话按频道读取并保留来源")
	var snapshot: Dictionary = GameState.to_dict()
	var stored_messages: Array = snapshot.get("linkchat_messages", [])
	_check(stored_messages.size() == 1, "私聊消息进入 GameState 存档")
