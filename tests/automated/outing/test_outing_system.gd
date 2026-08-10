extends Node
## 外出系统稳定契约：目录、可约角色、剧情锁和延迟提交事务。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_catalog_contract()
	_test_invitation_prompt_contract()
	_test_datable_contract()
	_test_story_lock_contract()
	_test_transaction_contract()
	print("[TestOutingSystem] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("[TestOutingSystem] PASS: " + test_name)
	else:
		_failed += 1
		push_error("[TestOutingSystem] FAIL: " + test_name)


func _test_catalog_contract() -> void:
	var catalog: OutingCatalog = OutingManager.get_catalog()
	var park: MapPlace = catalog.get_place("riverside_park")
	var concert: OutingActivity = catalog.get_activity("weekend_concert")
	_check(park != null and park.is_valid(), "地点目录提供稳定地点资料")
	_check(concert != null and concert.listing_kind == OutingActivity.KIND_EVENT, "地点与限时事件共用活动契约")
	_check(concert.narrative_mode == OutingActivity.NARRATIVE_LLM, "外出剧情明确由 LLM AVG 生成")


func _test_invitation_prompt_contract() -> void:
	var activity: OutingActivity = OutingManager.get_activity("park_walk")
	var place: MapPlace = OutingManager.get_place("riverside_park")
	var card_message: String = OutingManager._build_invitation_location_card_message(activity, place)
	_check(
		card_message == "player: [card:location|park_walk|riverside_park|沿河散步|汐见河滨公园|约会合计 ¥600]",
		"邀约 prompt 获得完整、可直接输出的地点卡片 DSL"
	)
	var empty_context: String = OutingManager._build_invitation_conversation_context("test_empty_invitation_channel")
	_check(empty_context.contains("没有历史消息") and empty_context.contains("会话的开场"), "空私聊会明确告诉邀约 prompt 当前没有历史")
	var accepted_structure: String = OutingManager._build_invitation_conversation_structure(true, "test_friend")
	var rejected_structure: String = OutingManager._build_invitation_conversation_structure(false, "test_friend")
	_check(
		accepted_structure.contains("`player` 发送唯一一轮邀约") \
			and accepted_structure.contains("直接、正面地接受邀请") \
			and accepted_structure.contains("立即输出 `END accepted`") \
			and not accepted_structure.contains("`player` 发送 1 个简短气泡回应"),
		"接受分支只包含玩家邀约轮和对方接受轮"
	)
	_check(
		rejected_structure.contains("明确拒绝邀请") \
			and rejected_structure.contains("`player` 发送 1 个简短气泡回应") \
			and rejected_structure.contains("立即输出 `END rejected`"),
		"拒绝分支只额外保留玩家的一次简短回应"
	)
	var resolved_prompt: String = OutingManager._resolve_outing_prompt("outing/invitation", {
		"player_profile": "测试玩家",
		"invited_display_name": "测试角色",
		"invited_persona": "测试设定",
		"activity_title": activity.title,
		"place_name": place.display_name,
		"conversation_context": empty_context,
		"conversation_structure": accepted_structure,
		"location_card_message": card_message,
		"authoritative_result": "接受邀约",
		"invited_speaker_id": "test_friend",
		"expected_result": "accepted",
	})
	_check(
		resolved_prompt.contains("聊天结束后将立即衔接这次外出") \
			and resolved_prompt.contains("本次行为事实只有一项") \
			and resolved_prompt.contains("不产生新的剧情前提") \
			and resolved_prompt.contains("严格按照以下顺序输出") \
			and resolved_prompt.contains(accepted_structure) \
			and resolved_prompt.contains(empty_context),
		"邀约 prompt 使用判定结果对应的固定短链路和真实私聊上下文"
	)


func _test_datable_contract() -> void:
	var datable: CharacterProfile = LinkChatManager.get_character("lu_yuanyuan")
	var blocked: CharacterProfile = LinkChatManager.get_character("su_he")
	_check(datable != null and datable.datable, "角色资源显式声明可约会")
	_check(blocked != null and not blocked.datable, "未声明的角色不会进入约会选择")


func _test_story_lock_contract() -> void:
	StoryLockManager.reset_runtime_state()
	_check(StoryLockManager.acquire_lock("test_outing", {
		"block_time_actions": true,
		"restrict_apps": true,
		"allowed_apps": ["cityhop", "linkchat", "avg_player"],
		"protected_apps": ["linkchat"],
		"reason": "测试中的外出剧情",
	}), "可创建通用剧情锁")
	_check(not StoryLockManager.can_consume_time("another_action"), "剧情锁阻止其它时段消费行为")
	_check(StoryLockManager.can_consume_time("test_outing"), "锁拥有者可继续同一事务")
	_check(not StoryLockManager.can_launch_app("browser"), "剧情锁限制无关 APP")
	_check(StoryLockManager.can_launch_app("cityhop"), "剧情链路需要的 APP 保持可用")
	_check(not StoryLockManager.can_close_app("linkchat"), "当前剧情 APP 无法被关闭")
	StoryLockManager.release_lock("test_outing")


func _test_transaction_contract() -> void:
	var original_money: int = GameState.money
	var original_day: int = GameState.day
	var original_slot: int = GameState.time_slot
	var original_completed: Array[String] = GameState.completed_action_transactions.duplicate()
	var original_history: Array[Dictionary] = GameState.action_transaction_history.duplicate(true)
	var transaction_id: String = "test_outing_transaction"
	GameState.money = 500
	GameState.day = 3
	GameState.time_slot = GameState.TIME_SLOT_MORNING
	GameState.completed_action_transactions.erase(transaction_id)
	_check(ActionTransactionManager.reserve(transaction_id, "test_outing", 120, 1), "活动可先预留时段与费用")
	_check(GameState.money == 500 and GameState.time_slot == GameState.TIME_SLOT_MORNING, "预留阶段不会扣款或推进时段")
	_check(ActionTransactionManager.commit(transaction_id), "有效内容准备完成后可原子提交")
	_check(GameState.money == 380 and GameState.time_slot == GameState.TIME_SLOT_AFTERNOON, "提交阶段才扣款并推进时段")
	_check(ActionTransactionManager.commit(transaction_id) and GameState.money == 380, "重复提交保持幂等")
	GameState.money = original_money
	GameState.day = original_day
	GameState.time_slot = original_slot
	GameState.completed_action_transactions = original_completed
	GameState.action_transaction_history = original_history
