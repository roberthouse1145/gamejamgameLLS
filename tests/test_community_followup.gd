extends Node

const COMMUNITY_APP_SCENE: PackedScene = preload("res://scenes/apps/community/community_app.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("=== Community Followup Test ===")

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null:
		_fail("autoload", "CommunityActionManager 缺失")
		_print_summary()
		return

	_test_followup_card(manager)
	_test_local_followup_reply(manager)
	_test_scene_instantiation()
	_print_summary()


func _test_followup_card(manager: Node) -> void:
	var action_meta := {
		"action_id": "browse_forum",
		"site": {"display_name": "AGJ Community"},
		"topic": {"mood": "mixed"},
		"action": {"title": "刷论坛"},
	}
	var entry := {
		"title": "赛题讨论串",
		"url": "community://discussion/day-4/1",
		"summary": "评论区开始发酵",
		"site": {"display_name": "AGJ Community"},
	}
	var card: Dictionary = manager.call("_build_followup_card", entry, action_meta)
	_assert_true("followup card type", str(card.get("type", "")) == "web_page", "卡片类型应该是 web_page")
	_assert_true("followup card url", not str(card.get("url", "")).strip_edges().is_empty(), "卡片必须带 url")
	_assert_true("followup card title", not str(card.get("title", "")).strip_edges().is_empty(), "卡片必须带标题")


func _test_local_followup_reply(manager: Node) -> void:
	var action_meta := {
		"action_id": "post_promo",
	}
	var entry := {
		"title": "宣传页",
		"summary": "有人开始记住你们",
	}
	var reply: String = str(manager.call("_build_local_followup_reply", entry, action_meta)).strip_edges()
	_assert_true("local followup reply", not reply.is_empty(), "本地后备回复不应该为空")


func _test_scene_instantiation() -> void:
	var instance := COMMUNITY_APP_SCENE.instantiate() as Control
	if instance == null:
		_fail("scene instantiate", "CommunityApp 场景实例化失败")
		return
	add_child(instance)
	await get_tree().process_frame
	_assert_true("loading view exists", instance.get_node_or_null("RootMargin/RootVBox/ContentStack/LoadingView") != null, "应当存在加载视图")
	_assert_true("feed scroll exists", instance.get_node_or_null("RootMargin/RootVBox/ContentStack/FeedScroll") != null, "应当存在内容流滚动区")
	instance.queue_free()


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
