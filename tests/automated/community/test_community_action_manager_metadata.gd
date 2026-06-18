extends Node

const CommunityActionManagerClass = preload("res://autoload/community_action_manager.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")


class BusyBlocker extends Node:
	var busy: bool = true

	func is_busy() -> bool:
		return busy


func _ready() -> void:
	print("=== CommunityActionManager Metadata Test ===")
	_test_entry_title_prefers_post_title()
	_test_entry_summary_prefers_post_content()
	_test_entry_marks_llm_source_type()
	_test_fallback_entry_marks_fallback_source_type()
	_test_topic_seeds_avoid_recent_history()
	_test_feed_prompt_requests_single_thread()
	_test_search_actions_are_hidden_and_prompted()
	_test_extract_content_supports_structured_ai_response()
	_test_free_period_blocking_disables_community_actions()
	print("=== All tests passed ===")


func _test_entry_title_prefers_post_title() -> void:
	var manager := CommunityActionManagerClass.new()
	var action_meta := {
		"action_id": "browse_forum",
		"action": {"title": "刷帖子"},
		"selected_seeds": ["神队友居然是个大一新生"],
		"day": 7,
		"phase": "下午",
		"url": "community://feed/test",
	}
	var posts := [{
		"author": "通宵做UI的人",
		"time": "刚刚",
		"likes": 86,
		"title": "昨晚复盘后，我感觉最该砍的是开场演出",
		"content": "主楼正文应该优先成为列表标题，而不是继续显示 seed。",
		"reply_list": [],
	}]

	var entry: Dictionary = manager._build_feed_entry(action_meta, posts)
	assert(entry.get("title", "") == "昨晚复盘后，我感觉最该砍的是开场演出")

	print("  PASS: _test_entry_title_prefers_post_title")


func _test_entry_summary_prefers_post_content() -> void:
	var manager := CommunityActionManagerClass.new()
	var action_meta := {
		"action_id": "browse_forum",
		"action": {"title": "刷帖子"},
		"selected_seeds": ["神队友居然是个大一新生"],
		"day": 7,
		"phase": "下午",
		"url": "community://feed/test",
	}
	var posts := [{
		"author": "通宵做UI的人",
		"time": "刚刚",
		"likes": 86,
		"title": "",
		"content": "这里是一段真正的主楼正文，用来验证 summary 不再直接显示 seed 拼接。",
		"reply_list": [],
	}]

	var entry: Dictionary = manager._build_feed_entry(action_meta, posts)
	var summary_text: String = str(entry.get("summary", ""))
	assert(summary_text.find("真正的主楼正文") >= 0)
	assert(summary_text.find("神队友居然是个大一新生") == -1)

	print("  PASS: _test_entry_summary_prefers_post_content")


func _test_entry_marks_llm_source_type() -> void:
	var manager := CommunityActionManagerClass.new()
	var action_meta := {
		"action_id": "browse_forum",
		"action": {"title": "刷帖子"},
		"selected_seeds": ["AI素材算不算作弊"],
		"day": 7,
		"phase": "下午",
		"url": "community://feed/test",
	}
	var posts := [{
		"author": "通宵做UI的人",
		"time": "刚刚",
		"likes": 86,
		"title": "这楼已经开始吵起来了",
		"content": "这里是一段主楼正文。",
		"reply_list": [],
	}]

	var entry: Dictionary = manager._build_feed_entry(action_meta, posts)
	assert(entry.get("source_type", "") == "llm")

	print("  PASS: _test_entry_marks_llm_source_type")


func _test_fallback_entry_marks_fallback_source_type() -> void:
	var manager := CommunityActionManagerClass.new()
	var action_meta := {
		"action_id": "follow_contest",
		"action": {"title": "发帖宣传"},
		"selected_seeds": ["评论区两极分化说明什么"],
		"day": 7,
		"phase": "下午",
		"url": "community://feed/test",
	}

	var entry: Dictionary = manager._build_fallback_entry(action_meta)
	assert(entry.get("source_type", "") == "fallback")

	print("  PASS: _test_fallback_entry_marks_fallback_source_type")


func _test_topic_seeds_avoid_recent_history() -> void:
	var manager := CommunityActionManagerClass.new()
	manager._community_content = {
		"topic_seeds": {
			"learn_dev": ["A", "B", "C", "D", "E", "F"],
		}
	}
	manager._recent_topic_seeds = ["A", "B", "C"]

	var picks: Array = manager._pick_topic_seeds("learn_dev", 8, 1)
	assert(picks.size() == 1)
	assert(not picks.has("A"))
	assert(not picks.has("B"))
	assert(not picks.has("C"))

	print("  PASS: _test_topic_seeds_avoid_recent_history")


func _test_feed_prompt_requests_single_thread() -> void:
	var manager := CommunityActionManagerClass.new()
	var action_meta := {
		"action_id": "browse_forum",
		"action": {"title": "刷帖子"},
		"selected_seeds": ["AI素材算不算作弊"],
		"day": 9,
	}

	var user_prompt: String = manager._build_action_feed_user_prompt(action_meta)
	assert(user_prompt.find("1 条完整帖子串") >= 0)
	assert(user_prompt.find("几条热门帖子") == -1)
	assert(user_prompt.find("只围绕这一个主题展开") >= 0)

	print("  PASS: _test_feed_prompt_requests_single_thread")


func _test_search_actions_are_hidden_and_prompted() -> void:
	var manager := CommunityActionManagerClass.new()
	manager._load_default_actions()

	assert(manager._action_definitions.has("free_search"))
	assert(manager._action_definitions.has("random_search"))
	assert(bool(manager._action_definitions["free_search"].get("ui_hidden", false)))
	assert(bool(manager._action_definitions["random_search"].get("ui_hidden", false)))

	var root_manager := get_node_or_null("/root/CommunityActionManager")
	assert(root_manager != null)
	var board_actions: Array = root_manager.get_available_actions()
	assert(_find_action(board_actions, "free_search").is_empty())
	assert(_find_action(board_actions, "random_search").is_empty())

	var free_prompt: String = manager._build_action_feed_user_prompt({
		"action_id": "free_search",
		"action": manager._action_definitions["free_search"],
		"selected_seeds": ["猫娘算猫还是娘"],
		"day": 3,
	})
	assert(free_prompt.find("玩家主动搜索") >= 0)
	assert(free_prompt.find("1 条完整帖子串") >= 0)

	var random_prompt: String = manager._build_action_feed_user_prompt({
		"action_id": "random_search",
		"action": manager._action_definitions["random_search"],
		"selected_seeds": ["今天社区都在聊什么"],
		"day": 3,
	})
	assert(random_prompt.find("随手刷到") >= 0)
	assert(random_prompt.find("只围绕这一个主题展开") >= 0)

	print("  PASS: _test_search_actions_are_hidden_and_prompted")


func _test_extract_content_supports_structured_ai_response() -> void:
	var manager := CommunityActionManagerClass.new()
	var response := {
		"choices": [{
			"message": {
				"content": [
					{
						"type": "text",
						"text": "===post===\nauthor: 测试用户\n\ntime: 刚刚\nlikes: 1\nreplies: 0\n\n结构化响应里的帖子正文\n===end===",
					}
				]
			}
		}]
	}

	var content: String = manager._extract_content(response)
	assert(content.find("===post===") >= 0)
	assert(content.find("结构化响应里的帖子正文") >= 0)

	print("  PASS: _test_extract_content_supports_structured_ai_response")


func _test_free_period_blocking_disables_community_actions() -> void:
	var manager := get_node_or_null("/root/CommunityActionManager")
	assert(manager != null)
	var blocker := BusyBlocker.new()
	add_child(blocker)
	ActivityLockUtilsClass.register_free_period_blocker("community_test_blocker", blocker, "is_busy", "测试占用中")

	var actions: Array = manager.get_available_actions()
	var target := _find_action(actions, "chill_browse")
	assert(not target.is_empty())
	assert(not bool(target.get("enabled", true)))
	assert(str(target.get("blocked_reason", "")) == "测试占用中")

	var result: Dictionary = manager.perform_action("chill_browse")
	assert(not bool(result.get("success", false)))
	assert(str(result.get("error", "")) == "测试占用中")

	ActivityLockUtilsClass.unregister_free_period_blocker("community_test_blocker")
	blocker.queue_free()

	print("  PASS: _test_free_period_blocking_disables_community_actions")


func _find_action(actions: Array, action_id: String) -> Dictionary:
	for action in actions:
		if not action is Dictionary:
			continue
		var action_dict: Dictionary = action
		if str(action_dict.get("action_id", "")) == action_id:
			return action_dict
	return {}
