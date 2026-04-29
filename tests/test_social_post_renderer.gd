extends Node

const SocialPostRendererClass = preload("res://scripts/apps/community/social_post_renderer.gd")


func _ready() -> void:
	print("=== SocialPostRenderer Test ===")
	_test_render_entry()
	print("=== SocialPostRenderer Test Passed ===")


func _test_render_entry() -> void:
	var entry := {
		"action_id": "browse_forum",
		"action_title": "刷帖子",
		"title": "测试热帖",
		"summary": "测试摘要",
		"day": 7,
		"phase": "冲刺阶段",
		"posts": [
			{
				"author": "测试用户",
				"time": "刚刚",
				"likes": 42,
				"replies": 2,
				"content": "第一条帖子内容",
				"reply_list": [
					{
						"author": "路人甲",
						"time": "1分钟前",
						"likes": 3,
						"content": "这是 1 楼内容",
						"sub_reply_list": [
							{
								"author": "楼中楼甲",
								"time": "刚刚",
								"likes": 1,
								"content": "这是针对 1 楼的楼中楼"
							}
						]
					},
					{
						"author": "路人乙",
						"time": "2分钟前",
						"likes": 2,
						"content": "这是 2 楼内容",
						"sub_reply_list": []
					}
				]
			},
			{
				"author": "第二个用户",
				"time": "5分钟前",
				"likes": 11,
				"replies": 0,
				"title": "标题帖",
				"content": "第二条帖子内容",
				"reply_list": []
			}
		]
	}

	var control: Control = SocialPostRendererClass.create_feed_entry(entry)
	assert(control != null, "Renderer should return a control")
	assert(control.get_child_count() == 3, "Expected header + 2 post cards")

	var header: Control = control.get_child(0)
	assert(header is PanelContainer, "Header should be a panel container")

	var first_post: Control = control.get_child(1)
	assert(first_post is PanelContainer, "First post should be a panel container")
	assert((entry["posts"][0]["reply_list"] as Array).size() == 2, "Expected 2 floor replies in fixture")

	print("  PASS: _test_render_entry")