extends Node

var _passed: int = 0
var _failed: int = 0
var _last_completed_payload: Dictionary = {}


func _ready() -> void:
	print("=== Home Activity Manager Test ===")
	await _test_rest_flow()
	await _test_rest_early_flow()
	await _test_old_home_activities_removed()
	print("=== Home Activity Manager Test Complete ===")
	print("[RESULT] passed=%d failed=%d" % [_passed, _failed])


func _test_chat_casual_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("chat_casual", "autoload 缺失")
		return

	var activities: Array[Dictionary] = home.get_available_activities("MORNING")
	var chat_activity: Dictionary = _find_activity(activities, "chat_casual")
	_assert_true("chat_casual enabled", bool(chat_activity.get("enabled", false)), "早上应可闲聊")

	var start_affection: int = int(gm.get("affection"))
	var start_stress: int = int(gm.get("stress"))
	var result: Dictionary = home.begin_activity("chat_casual")
	_assert_true("chat_casual begin", bool(result.get("success", false)), "闲聊应能成功开始")

	await get_tree().process_frame
	await get_tree().process_frame

	_assert_equal("chat_casual phase", glm.get_phase_name(glm.time_phase), "AFTERNOON")
	_assert_equal("chat_casual affection", int(gm.get("affection")), start_affection + 1)
	_assert_equal("chat_casual stress", int(gm.get("stress")), start_stress - 1)
	_assert_true("chat_casual cleared", not home.has_any_pending_sessions(), "闲聊结束后不应残留 session")


func _test_chat_deep_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("chat_deep", "autoload 缺失")
		return

	# chat_deep 需要 affection >= 20，默认 30 应该满足
	# chat_deep 只在 AFTERNOON/NIGHT 可用，先推进到下午
	glm.consume_ap(1, "test", "advance_to_afternoon")
	await get_tree().process_frame

	var activities: Array[Dictionary] = home.get_available_activities("AFTERNOON")
	var deep_activity: Dictionary = _find_activity(activities, "chat_deep")
	_assert_true("chat_deep enabled", bool(deep_activity.get("enabled", false)), "下午应可谈心")

	# 早上不应可用
	var morning_activities: Array[Dictionary] = home.get_available_activities("MORNING")
	var deep_morning: Dictionary = _find_activity(morning_activities, "chat_deep")
	_assert_true("chat_deep morning disabled", not bool(deep_morning.get("enabled", true)), "早上不应可谈心")

	var start_affection: int = int(gm.get("affection"))
	var start_stress: int = int(gm.get("stress"))
	var result: Dictionary = home.begin_activity("chat_deep")
	_assert_true("chat_deep begin", bool(result.get("success", false)), "谈心应能成功开始")

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_equal("chat_deep phase", glm.get_phase_name(glm.time_phase), "NIGHT")
	_assert_equal("chat_deep affection", int(gm.get("affection")), start_affection + 2)
	_assert_equal("chat_deep stress", int(gm.get("stress")), start_stress - 1)
	_assert_true("chat_deep cleared", not home.has_any_pending_sessions(), "谈心结束后不应残留 session")


func _test_personal_overuse_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("personal", "autoload 缺失")
		return

	for _i in range(3):
		var result: Dictionary = home.begin_activity("personal")
		_assert_true("personal begin", bool(result.get("success", false)), "personal 应能成功开始")
		await get_tree().process_frame
		await get_tree().process_frame

	# 3 次 personal 消耗 3 AP → 进入第 2 天
	_assert_equal("personal next day", int(glm.get("current_day")), 2)
	_assert_equal("personal phase reset", glm.get_phase_name(glm.time_phase), "MORNING")
	# 初始 affection=30, 3次 personal stress -2 each = -6, 第3次触发 overuse penalty affection -1
	_assert_equal("personal affection penalty", int(gm.get("affection")), 29)
	# 初始 stress=20, 3次 -2 each = 14, 然后 advance_to_next_day → on_new_day stress -2 = 12
	_assert_equal("personal stress settle", int(gm.get("stress")), 12)


func _test_watch_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("watch", "autoload 缺失")
		return

	# watch 只在 AFTERNOON/NIGHT 可用
	glm.consume_ap(1, "test", "advance_to_afternoon")
	await get_tree().process_frame

	var activities: Array[Dictionary] = home.get_available_activities("AFTERNOON")
	var watch_activity: Dictionary = _find_activity(activities, "watch")
	_assert_true("watch enabled", bool(watch_activity.get("enabled", false)), "下午应可一起看点东西")

	var options: Array[Dictionary] = home.get_activity_options("watch", "AFTERNOON")
	var option: Dictionary = _find_first_enabled(options)
	_assert_true("watch options", not option.is_empty(), "应该有可看的内容")

	var start_affection: int = int(gm.get("affection"))
	var start_stress: int = int(gm.get("stress"))
	var result: Dictionary = home.begin_activity("watch", {"content_id": str(option.get("content_id", ""))})
	_assert_true("watch begin", bool(result.get("success", false)), "watch 应能成功开始")

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_equal("watch phase", glm.get_phase_name(glm.time_phase), "NIGHT")
	_assert_equal("watch affection", int(gm.get("affection")), start_affection + 1)
	_assert_equal("watch stress", int(gm.get("stress")), start_stress - 2)
	_assert_true("watch cleared", not home.has_any_pending_sessions(), "watch 结束后不应残留 session")


func _test_review_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("review", "autoload 缺失")
		return

	# review 需要 completion >= 10，先检查默认值
	var completion: int = int(gm.get("completion"))
	if completion < 10:
		# 手动设置 completion 以满足前置条件
		if gm.has_method("modify_stats"):
			gm.modify_stats({"completion": 10 - completion})
		await get_tree().process_frame

	var activities: Array[Dictionary] = home.get_available_activities("MORNING")
	var review_activity: Dictionary = _find_activity(activities, "review")
	_assert_true("review enabled", bool(review_activity.get("enabled", false)), "有进度时应可审视作品")

	var start_passion: int = int(gm.get("passion"))
	var result: Dictionary = home.begin_activity("review")
	_assert_true("review begin", bool(result.get("success", false)), "review 应能成功开始")

	await get_tree().process_frame
	await get_tree().process_frame

	_assert_equal("review phase", glm.get_phase_name(glm.time_phase), "AFTERNOON")
	_assert_equal("review passion", int(gm.get("passion")), start_passion + 1)
	_assert_true("review cleared", not home.has_any_pending_sessions(), "review 结束后不应残留 session")


func _test_rest_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("rest", "autoload 缺失")
		return

	# 先推进到晚上
	glm.consume_ap(1, "test", "advance_to_afternoon")
	await get_tree().process_frame
	glm.consume_ap(1, "test", "advance_to_night")
	await get_tree().process_frame

	_assert_equal("rest pre phase", glm.get_phase_name(glm.time_phase), "NIGHT")

	var activities: Array[Dictionary] = home.get_available_activities("NIGHT")
	var rest_activity: Dictionary = _find_activity(activities, "rest")
	_assert_true("rest enabled", bool(rest_activity.get("enabled", false)), "晚上应可休息")
	_assert_equal("rest ap_cost", int(rest_activity.get("ap_cost", 0)), 1)

	var result: Dictionary = home.begin_rest()
	_assert_true("rest begin", bool(result.get("success", false)), "休息应能成功开始")
	if bool(result.get("success", false)):
		home._finish_session(str(result.get("session_id", "")))

	await get_tree().create_timer(1.2).timeout

	_assert_equal("rest next day", int(glm.get("current_day")), 2)
	_assert_equal("rest next phase", glm.get_phase_name(glm.time_phase), "MORNING")
	_assert_equal("rest stress", int(gm.get("stress")), 0)
	_assert_equal("rest payload reward stress", int((_last_completed_payload.get("rewards", {}) as Dictionary).get("stress", 0)), -25)
	_assert_true("rest cleared", not home.has_any_pending_sessions(), "休息结束后不应残留 session")


func _test_rest_early_flow() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if home == null or glm == null or gm == null:
		_fail("rest_early", "autoload 缺失")
		return

	# 在早上就选择休息：rest 与其它行动一致，只消耗当前 1 个时段，
	# 不会跳过整天（设计已修正：只有晚上 rest 自然进入下一天）
	_assert_equal("rest_early pre phase", glm.get_phase_name(glm.time_phase), "MORNING")

	var activities: Array[Dictionary] = home.get_available_activities("MORNING")
	var rest_activity: Dictionary = _find_activity(activities, "rest")
	_assert_true("rest_early enabled", bool(rest_activity.get("enabled", false)), "早上也应可休息")

	var result: Dictionary = home.begin_rest()
	_assert_true("rest_early begin", bool(result.get("success", false)), "早上休息应能成功开始")
	if bool(result.get("success", false)):
		home._finish_session(str(result.get("session_id", "")))

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# 早上 rest 只推进到下午，仍是同一天
	_assert_equal("rest_early same day", int(glm.get("current_day")), 1)
	_assert_equal("rest_early next phase", glm.get_phase_name(glm.time_phase), "AFTERNOON")
	_assert_true("rest_early payload has rewards", (_last_completed_payload.get("rewards", {}) as Dictionary).has("stress"), "提前休息结果应包含 stress")
	_assert_true("rest_early cleared", not home.has_any_pending_sessions(), "休息结束后不应残留 session")


func _test_old_home_activities_removed() -> void:
	_reset_managers()
	await get_tree().process_frame

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	if home == null:
		_fail("old_home_removed", "autoload 缺失")
		return

	for old_id in ["chat_casual", "chat_deep", "personal", "watch", "review"]:
		var result: Dictionary = home.begin_activity(old_id)
		_assert_true("%s removed" % old_id, not bool(result.get("success", false)), "旧居家活动不应再能启动")


# === 工具函数 ===

func _reset_managers() -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var home: Node = get_node_or_null("/root/HomeActivityManager")

	if chat != null and chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(true)
	if gm != null and gm.has_method("reset_runtime_state"):
		gm.reset_runtime_state()
	if glm != null and glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()
	if home != null and home.has_method("reset_runtime_state"):
		home.reset_runtime_state()
	_last_completed_payload.clear()
	if home != null and home.has_signal("activity_completed"):
		var callback := Callable(self, "_on_activity_completed")
		if not home.activity_completed.is_connected(callback):
			home.activity_completed.connect(callback)


func _find_activity(activities: Array[Dictionary], activity_id: String) -> Dictionary:
	for activity in activities:
		if str(activity.get("activity_id", "")) == activity_id:
			return activity
	return {}


func _find_first_enabled(options: Array[Dictionary]) -> Dictionary:
	for option in options:
		if bool(option.get("enabled", true)):
			return option
	return {}


func _assert_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_pass(label)
	else:
		_fail(label, "expected=%s actual=%s" % [str(expected), str(actual)])


func _assert_true(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass(label)
	else:
		_fail(label, detail)


func _pass(label: String) -> void:
	_passed += 1
	print("[OK] %s" % label)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	if detail.is_empty():
		print("[FAIL] %s" % label)
	else:
		print("[FAIL] %s :: %s" % [label, detail])


func _on_activity_completed(_activity_id: String, payload: Dictionary) -> void:
	_last_completed_payload = payload.duplicate(true)
