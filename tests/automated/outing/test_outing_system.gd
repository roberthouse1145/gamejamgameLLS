extends Node
## 外出系统稳定契约：剧情锁、原子事务和新帖展示完成后的提交边界。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_story_lock_contract()
	_test_transaction_contract()
	_test_outing_completion_transaction_contract()
	print("[TestOutingSystem] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("[TestOutingSystem] PASS: " + test_name)
	else:
		_failed += 1
		push_error("[TestOutingSystem] FAIL: " + test_name)


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
	_check(ActionTransactionManager.commit(transaction_id), "调用方确认动作链完成后可原子提交")
	_check(GameState.money == 380 and GameState.time_slot == GameState.TIME_SLOT_AFTERNOON, "提交阶段才扣款并推进时段")
	_check(ActionTransactionManager.commit(transaction_id) and GameState.money == 380, "重复提交保持幂等")
	GameState.money = original_money
	GameState.day = original_day
	GameState.time_slot = original_slot
	GameState.completed_action_transactions = original_completed
	GameState.action_transaction_history = original_history


func _test_outing_completion_transaction_contract() -> void:
	var original_money: int = GameState.money
	var original_day: int = GameState.day
	var original_slot: int = GameState.time_slot
	var original_completed: Array[String] = GameState.completed_action_transactions.duplicate()
	var original_transaction_history: Array[Dictionary] = GameState.action_transaction_history.duplicate(true)
	var original_outing_history: Array[Dictionary] = GameState.outing_history.duplicate(true)
	var original_session: Dictionary = GameState.active_outing_session.duplicate(true)
	var original_stress: int = GameState.stress
	var original_loneliness: int = GameState.loneliness
	var transaction_id: String = "test_outing_completion_transaction"
	var session_id: String = "test_outing_completion"

	GameState.money = 500
	GameState.day = 3
	GameState.time_slot = GameState.TIME_SLOT_MORNING
	GameState.completed_action_transactions.erase(transaction_id)
	GameState.active_outing_session = {
		"session_id": session_id,
		"transaction_id": transaction_id,
		"activity_id": "riverside_walk_01",
		"mode": OutingManager.MODE_SOLO,
		"status": "generating",
	}
	StoryLockManager.reset_runtime_state()
	StoryLockManager.acquire_lock("outing_session", {"block_time_actions": true})
	_check(
		ActionTransactionManager.reserve(transaction_id, "outing_session", 120, 1),
		"外出链路开始时只预留时段与费用"
	)

	OutingManager._on_scene_generated(session_id, {"title": "测试场景"})
	_check(
		GameState.money == 500 \
			and GameState.time_slot == GameState.TIME_SLOT_MORNING \
			and not ActionTransactionManager.get_reservation(transaction_id).is_empty(),
		"AVG DSL 返回后仍不扣费或推进时段"
	)

	_check(
		OutingManager._prepare_post_stage_after_avg(session_id, {
			"success": true,
			"narrative_text": "测试剧情已经播放完成。",
		}),
		"AVG 播放成功后进入动态发布阶段"
	)
	_check(
		GameState.money == 500 \
			and GameState.time_slot == GameState.TIME_SLOT_MORNING \
			and GameState.active_outing_session.get("status") == "publishing_posts",
		"AVG 播放结束后仍不扣费或推进时段"
	)
	_check(
		StoryLockManager.can_launch_app("linkposta") and StoryLockManager.can_launch_app("browser"),
		"动态发布阶段允许 LinkPosta 快捷入口及其 Browser 宿主"
	)
	_check(not StoryLockManager.can_close_app("browser"), "动态展示完成前 Browser 保持受保护")
	_check(OutingManager._settle_completed_post_chain(session_id), "新帖展示完成后可以提交外出事务")
	_check(
		GameState.money == 380 \
			and GameState.time_slot == GameState.TIME_SLOT_AFTERNOON \
			and ActionTransactionManager.is_committed(transaction_id) \
			and GameState.active_outing_session.is_empty(),
		"新帖展示链完成后才扣费、推进时段并清理会话"
	)

	ActionTransactionManager.cancel(transaction_id)
	StoryLockManager.reset_runtime_state()
	GameState.money = original_money
	GameState.day = original_day
	GameState.time_slot = original_slot
	GameState.completed_action_transactions = original_completed
	GameState.action_transaction_history = original_transaction_history
	GameState.outing_history = original_outing_history
	GameState.active_outing_session = original_session
	GameState.stress = original_stress
	GameState.loneliness = original_loneliness
