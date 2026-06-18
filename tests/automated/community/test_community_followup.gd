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
	await _test_scene_instantiation()
	_test_app_manager_launch()
	_print_summary()


func _test_followup_card(manager: Node) -> void:
	var action_meta := {
		"action_id": "learn_dev",
		"action": {"title": "学习开发"},
	}
	var entry := {
		"title": "赛题讨论串",
		"url": "community://discussion/day-4/1",
		"summary": "评论区开始发酵",
		"source_type": "llm",
		"posts": [{"author": "路过的楼主", "content": "主楼正文"}],
	}
	var card: Dictionary = manager.call("_build_followup_card", entry, action_meta)
	_assert_true("followup card type", str(card.get("type", "")) == "web_page", "卡片类型应该是 web_page")
	_assert_true("followup card url", not str(card.get("url", "")).strip_edges().is_empty(), "卡片必须带 url")
	_assert_true("followup card title", not str(card.get("title", "")).strip_edges().is_empty(), "卡片必须带标题")
	_assert_true("followup card source kind", str(card.get("source_kind", "")) == "community_thread", "社区卡片必须标记为帖子转发")
	_assert_true("followup card source author", str(card.get("source_author", "")) == "路过的楼主", "卡片应保留社区原作者")

	var prompt: String = str(manager.call("_build_followup_prompt", entry, action_meta))
	_assert_true("followup prompt shared thread", prompt.find("分享给你看") >= 0, "prompt 应明确这是分享给林夏看的帖子")
	_assert_true("followup prompt not player-authored", prompt.find("不是玩家自己写") >= 0, "prompt 应明确帖子不是玩家自己写的")
	_assert_true("followup prompt marks original post", prompt.find("社区用户原文，不是玩家发言") >= 0, "prompt 应区分社区原文和玩家发言")


func _test_local_followup_reply(manager: Node) -> void:
	var action_meta := {
		"action_id": "follow_contest",
		"action": {"title": "发帖宣传"},
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
	_assert_true("loading view exists", instance.get_node_or_null("LoadingView") != null, "应当存在加载视图")
	_assert_true("feed scroll exists", instance.get_node_or_null("MainVBox/PagesContainer/FeedPage/FeedScroll") != null, "应当存在内容流滚动区")
	instance.queue_free()


func _test_app_manager_launch() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		_fail("app manager launch", "AppManager 缺失")
		return

	var previous_window_manager: Node = app_manager.get("window_manager")
	var window_manager := WindowManager.new()
	window_manager.name = "CommunityTestWindowManager"
	add_child(window_manager)

	var container := Control.new()
	container.name = "CommunityTestWindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	window_manager.window_container = container
	app_manager.set("window_manager", window_manager)

	var window: Control = app_manager.call("launch_app", "community", true)
	_assert_true("app manager launches community", window != null, "AppManager 应能启动 community")
	if window != null:
		window.queue_free()
	if app_manager.get("running_apps") is Dictionary:
		(app_manager.get("running_apps") as Dictionary).erase("community")
	app_manager.set("window_manager", previous_window_manager)
	window_manager.queue_free()
	container.queue_free()


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
