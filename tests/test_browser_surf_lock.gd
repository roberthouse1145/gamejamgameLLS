extends Node

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("\n=== Browser Surf Lock Test ===")
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_fail("browser manager", "BrowserManager autoload missing")
		_print_summary()
		return

	ActivityLockUtilsClass.clear_narrative_lock()
	_test_browser_surf_lock_alias(bm)
	await _test_browser_surf_fast_disabled(bm)
	await _test_unknown_page_fast_disabled(bm)
	ActivityLockUtilsClass.clear_narrative_lock()
	_print_summary()


func _test_browser_surf_lock_alias(bm: Node) -> void:
	var reason := "先看完这个剧情网页。"
	ActivityLockUtilsClass.set_narrative_lock("blacklist", ["browser_surf"], reason)

	_assert_true(
		"browser_surf locked",
		ActivityLockUtilsClass.get_narrative_blocking_reason_for_any(["browser_surf"]) == reason,
		"browser_surf should be blocked by narrative lock"
	)
	_assert_true(
		"browser alias not locked",
		ActivityLockUtilsClass.get_narrative_blocking_reason_for_any(["browser"]).is_empty(),
		"browser aggregate alias should remain available for story pages"
	)

	var surf_reason := str(bm.call("get_surf_blocking_reason")).strip_edges()
	_assert_true("surf blocking reason", not surf_reason.is_empty(), "surf should be unavailable while browser_surf is locked")

	var page_request_id := str(bm.call("open_page", "gamejam://news")).strip_edges()
	_assert_true("premade open_page available", not page_request_id.is_empty(), "premade browser pages should still open")

	ActivityLockUtilsClass.clear_narrative_lock()
	_assert_true(
		"browser_surf unlocked",
		ActivityLockUtilsClass.get_narrative_blocking_reason_for_any(["browser_surf"]).is_empty(),
		"clear_narrative_lock should remove browser_surf lock"
	)


func _test_browser_surf_fast_disabled(bm: Node) -> void:
	var events: Array = []
	var on_failed := func(failed_request_id: String, keyword: String, error: String) -> void:
		events.append({
			"request_id": failed_request_id,
			"keyword": keyword,
			"error": error,
		})
	bm.surf_failed.connect(on_failed)

	var request_id := str(bm.call("surf", "红烧肉")).strip_edges()
	await get_tree().process_frame
	if bm.surf_failed.is_connected(on_failed):
		bm.surf_failed.disconnect(on_failed)

	_assert_true("surf disabled request id", not request_id.is_empty(), "disabled surf should still return a request id")
	_assert_true("surf disabled emits failure", events.size() == 1, "disabled surf should emit one failure event")
	if not events.is_empty():
		var event: Dictionary = events[0]
		_assert_true("surf disabled keyword", str(event.get("keyword", "")) == "红烧肉", "surf failure should keep keyword")
		_assert_true("surf disabled message", str(event.get("error", "")).find("暂时关闭") >= 0, "surf failure should explain feature is disabled")


func _test_unknown_page_fast_disabled(bm: Node) -> void:
	var events: Array = []
	var on_failed := func(failed_request_id: String, url: String, error: String) -> void:
		events.append({
			"request_id": failed_request_id,
			"url": url,
			"error": error,
		})
	bm.page_failed.connect(on_failed)

	var request_id := str(bm.call("open_page", "framestory://unknown-disabled-test")).strip_edges()
	await get_tree().process_frame
	if bm.page_failed.is_connected(on_failed):
		bm.page_failed.disconnect(on_failed)

	_assert_true("unknown page request id", not request_id.is_empty(), "disabled page generation should still return a local request id")
	_assert_true("unknown page emits failure", events.size() == 1, "unknown page should emit one failure event")
	if not events.is_empty():
		var event: Dictionary = events[0]
		_assert_true("unknown page url", str(event.get("url", "")) == "framestory://unknown-disabled-test", "page failure should keep url")
		_assert_true("unknown page disabled message", str(event.get("error", "")).find("网页生成暂时关闭") >= 0, "page failure should explain dynamic generation is disabled")


func _assert_true(label: String, condition: bool, message: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		push_error("[FAIL] %s: %s" % [label, message])


func _fail(label: String, message: String) -> void:
	_failed += 1
	push_error("[FAIL] %s: %s" % [label, message])


func _print_summary() -> void:
	print("[RESULT] passed=%d failed=%d" % [_passed, _failed])
