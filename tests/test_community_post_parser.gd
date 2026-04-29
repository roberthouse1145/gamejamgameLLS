extends Node

const Parser = preload("res://scripts/apps/community/community_post_parser.gd")

func _ready() -> void:
	print("=== CommunityPostParser Test ===")
	_test_basic_post()
	_test_multiple_posts()
	_test_post_with_title()
	_test_post_with_quotes_in_content()
	_test_empty_input()
	_test_markdown_fences()
	_test_negative_likes()
	print("=== All tests passed ===")


func _test_basic_post() -> void:
	var dsl := """===post===
author: 兔子做游戏
time: 2小时前
likes: 234
replies: 15

第三天了，终于把对话系统搞定了！
看到角色说出第一句话的时候真的好感动 😭
#GameJam #AVG开发

---reply---
author: 老司机
likes: 12

加油！第一次做AVG的感觉最好了

---reply---
author: 杠精本精
likes: 3

三天才搞定对话系统？我一天就写了战斗系统（
===end==="""

	var posts := Parser.parse(dsl)
	assert(posts.size() == 1, "Should have 1 post, got %d" % posts.size())

	var post: Dictionary = posts[0]
	assert(post["author"] == "兔子做游戏", "Author mismatch: %s" % post["author"])
	assert(post["time"] == "2小时前", "Time mismatch: %s" % post["time"])
	assert(post["likes"] == 234, "Likes mismatch: %d" % post["likes"])
	assert(post["replies"] == 15, "Replies mismatch: %d" % post["replies"])
	assert(post["content"].find("对话系统") >= 0, "Content should contain '对话系统'")
	assert(post["content"].find("#GameJam") >= 0, "Content should contain '#GameJam'")

	var reply_list: Array = post["reply_list"]
	assert(reply_list.size() == 2, "Should have 2 replies, got %d" % reply_list.size())
	assert(reply_list[0]["author"] == "老司机", "Reply 0 author mismatch")
	assert(reply_list[0]["likes"] == 12, "Reply 0 likes mismatch")
	assert(reply_list[1]["author"] == "杠精本精", "Reply 1 author mismatch")
	assert(reply_list[1]["content"].find("战斗系统") >= 0, "Reply 1 content mismatch")

	print("  PASS: _test_basic_post")


func _test_multiple_posts() -> void:
	var dsl := """===post===
author: 用户A
time: 1小时前
likes: 50
replies: 3

第一条帖子内容
===end===

===post===
author: 用户B
time: 30分钟前
likes: 100
replies: 8

第二条帖子内容

---reply---
author: 路人
likes: 5

围观
===end==="""

	var posts := Parser.parse(dsl)
	assert(posts.size() == 2, "Should have 2 posts, got %d" % posts.size())
	assert(posts[0]["author"] == "用户A", "Post 0 author mismatch")
	assert(posts[1]["author"] == "用户B", "Post 1 author mismatch")
	assert(posts[1]["reply_list"].size() == 1, "Post 1 should have 1 reply")

	print("  PASS: _test_multiple_posts")


func _test_post_with_title() -> void:
	var dsl := """===post===
author: 赛事速报Bot
time: 5小时前
likes: 89
replies: 23
title: AI素材在比赛里算不算作弊？

今天看到有队伍用AI生成全部立绘
速度是真快但总觉得哪里不对
===end==="""

	var posts := Parser.parse(dsl)
	assert(posts.size() == 1, "Should have 1 post")
	assert(posts[0].has("title"), "Post should have title")
	assert(posts[0]["title"] == "AI素材在比赛里算不算作弊？", "Title mismatch: %s" % posts[0]["title"])

	print("  PASS: _test_post_with_title")


func _test_post_with_quotes_in_content() -> void:
	var dsl := """===post===
author: 吐槽达人
time: 3小时前
likes: 167
replies: 12

他说"这不可能"，然后就被打脸了。
队友的原话是"我觉得三天够了"，结果现在Day 10还在debug。
===end==="""

	var posts := Parser.parse(dsl)
	assert(posts.size() == 1, "Should have 1 post")
	assert(posts[0]["content"].find('"这不可能"') >= 0, "Content should preserve quotes")
	assert(posts[0]["content"].find('"我觉得三天够了"') >= 0, "Content should preserve quotes 2")

	print("  PASS: _test_post_with_quotes_in_content")


func _test_empty_input() -> void:
	var posts := Parser.parse("")
	assert(posts.size() == 0, "Empty input should return empty array")

	posts = Parser.parse("random text without any markers")
	assert(posts.size() == 0, "No markers should return empty array")

	print("  PASS: _test_empty_input")


func _test_markdown_fences() -> void:
	var dsl := """```
===post===
author: 测试用户
time: 刚刚
likes: 1
replies: 0

被围栏包住的帖子
===end===
```"""

	var posts := Parser.parse(dsl)
	assert(posts.size() == 1, "Should parse through markdown fences")
	assert(posts[0]["author"] == "测试用户", "Author mismatch through fences")

	print("  PASS: _test_markdown_fences")


func _test_negative_likes() -> void:
	var dsl := """===post===
author: 争议发言
time: 1天前
likes: 500
replies: 88

很有争议的观点

---reply---
author: 被踩的人
likes: -12

被踩到地下室的回复
===end==="""

	var posts := Parser.parse(dsl)
	assert(posts.size() == 1, "Should have 1 post")
	assert(posts[0]["reply_list"][0]["likes"] == -12, "Should support negative likes")

	print("  PASS: _test_negative_likes")
