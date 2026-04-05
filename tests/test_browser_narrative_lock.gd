extends Node

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")

var _passed: int = 0
var _failed: int = 0
var _wm: WindowManager = null


func _ready() -> void:
	print("=== Community Narrative Lock Test ===")
	var community: Node = get_node_or_null("/root/CommunityActionManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if community == null or glm == null:
		_fail("autoload", "CommunityActionManager 或 GameLoopManager 缺失")
		_print_summary()
		return
	_ensure_window_manager()

	_reset_runtime(glm)
	_test_community_blacklist_blocks_action(community, glm)

	_reset_runtime(glm)
	_test_community_whitelist_allows_actions(community)

	_reset_runtime(glm)
	_test_specific_action_lock_only_blocks_target(community)

	_reset_runtime(glm)
	await _test_community_ui_buttons_follow_lock()

	await _test_browser_home_no_action_buttons()

	ActivityLockUtilsClass.clear_narrative_lock()
	_print_summary()


func _ensure_window_manager() -> void:
	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		return
	if am.get("window_manager") != null:
		_wm = am.get("window_manager")
		return
	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)
	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_wm.window_container = container
	am.window_manager = _wm


func _reset_runtime(glm: Node) -> void:
	ActivityLockUtilsClass.clear_narrative_lock()
	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()


func _test_community_blacklist_blocks_action(community: Node, glm: Node) -> void:
	ActivityLockUtilsClass.set_narrative_lock("blacklist", ["community"], "先别刷社区")
	var start_ap: int = int(glm.get("current_ap"))
	var result: Dictionary = community.perform_action("browse_forum")
	_assert_true("community blacklist blocked", not bool(result.get("success", false)), "community 黑名单应拦截 browse_forum")
	_assert_equal("community blacklist reason", str(result.get("error", "")), "先别刷社区")
	_assert_equal("community blacklist ap unchanged", int(glm.get("current_ap")), start_ap)
	_assert_true("community blacklist no pending", not community.has_method("has_pending_requests") or not bool(community.has_pending_requests()), "被拦截后不应启动异步请求")


func _test_community_whitelist_allows_actions(community: Node) -> void:
	ActivityLockUtilsClass.set_narrative_lock("whitelist", ["community"], "这里只允许社区行动")
	var actions: Array = community.get_available_actions()
	var browse_action: Dictionary = _find_action(actions, "browse_forum")
	_assert_true("community whitelist action exists", not browse_action.is_empty(), "应能找到 browse_forum")
	_assert_true("community whitelist enabled", bool(browse_action.get("enabled", false)), "whitelist=community 时不应拦截社区行动")


func _test_specific_action_lock_only_blocks_target(community: Node) -> void:
	ActivityLockUtilsClass.set_narrative_lock("blacklist", ["watch_event"], "先别看赛事")
	var actions: Array = community.get_available_actions()
	var browse_action: Dictionary = _find_action(actions, "browse_forum")
	var watch_action: Dictionary = _find_action(actions, "watch_event")
	_assert_true("specific lock browse enabled", bool(browse_action.get("enabled", false)), "具体 action 锁不应误伤其他社区行动")
	_assert_true("specific lock watch disabled", not bool(watch_action.get("enabled", true)), "watch_event 应被单独锁定")
	_assert_equal("specific lock reason", str(watch_action.get("blocked_reason", "")), "先别看赛事")


func _test_community_ui_buttons_follow_lock() -> void:
	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		_fail("community ui", "AppManager 缺失")
		return
	if am.has_method("is_app_running") and bool(am.is_app_running("community")) and am.has_method("close_app"):
		am.close_app("community", true)
	ActivityLockUtilsClass.set_narrative_lock("blacklist", ["watch_event"], "先别看赛事")
	var window: Control = am.launch_app("community")
	if window == null:
		_fail("community ui", "Community app 启动失败")
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var content: Control = window.get("content")
	if content == null:
		_fail("community ui", "Community app content 缺失")
		return

	var browse_button := _find_node_by_name(content, "ActionButton_browse_forum") as Button
	var watch_button := _find_node_by_name(content, "ActionButton_watch_event") as Button
	_assert_true("community ui browse button exists", browse_button != null, "应能找到 browse_forum 按钮")
	_assert_true("community ui watch button exists", watch_button != null, "应能找到 watch_event 按钮")
	if browse_button != null:
		_assert_true("community ui browse enabled", not browse_button.disabled, "未被锁定的按钮不应置灰")
	if watch_button != null:
		_assert_true("community ui watch disabled", watch_button.disabled, "被 narrative lock 的按钮应置灰")

	if am.has_method("is_app_running") and bool(am.is_app_running("community")) and am.has_method("close_app"):
		am.close_app("community", true)


func _test_browser_home_no_action_buttons() -> void:
	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		_fail("browser home", "AppManager 缺失")
		return
	if am.has_method("is_app_running") and bool(am.is_app_running("browser")) and am.has_method("close_app"):
		am.close_app("browser", true)

	var window: Control = am.launch_app("browser", true)
	if window == null:
		_fail("browser home", "Browser app 启动失败")
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var content: Control = window.get("content")
	if content == null:
		_fail("browser home", "Browser app content 缺失")
		return

	var browse_button := _find_button_by_text(content, "进入论坛")
	var watch_button := _find_button_by_text(content, "查看赛事")
	var promo_button := _find_button_by_text(content, "去发布")
	_assert_true("browser home no browse button", browse_button == null, "浏览器主页不应再保留 browse_forum 按钮")
	_assert_true("browser home no watch button", watch_button == null, "浏览器主页不应再保留 watch_event 按钮")
	_assert_true("browser home no promo button", promo_button == null, "浏览器主页不应再保留 post_promo 按钮")

	if am.has_method("is_app_running") and bool(am.is_app_running("browser")) and am.has_method("close_app"):
		am.close_app("browser", true)


func _find_action(actions: Array, action_id: String) -> Dictionary:
	for action in actions:
		if action is Dictionary and str(action.get("action_id", "")) == action_id:
			return action
	return {}


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _find_button_by_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null


func _assert_true(label: String, condition: bool, message: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		push_error("[FAIL] %s: %s" % [label, message])


func _assert_equal(label: String, actual: Variant, expected: Variant) -> void:
	_assert_true(label, actual == expected, "expected=%s actual=%s" % [str(expected), str(actual)])


func _fail(label: String, message: String) -> void:
	_failed += 1
	push_error("[FAIL] %s: %s" % [label, message])


func _print_summary() -> void:
	print("[RESULT] passed=%d failed=%d" % [_passed, _failed])
