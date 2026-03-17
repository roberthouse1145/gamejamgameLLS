extends Control
## LinkChat LLM聊天测试
## 直接实例化LinkChat场景，使用 ChatManager autoload 管理数据

var app: Control = null


func _ready() -> void:
	print("[Test] LinkChat LLM测试开始")

	# 直接实例化LinkChat场景
	var scene := preload("res://scenes/apps/linkchat/linkchat_app.tscn")
	app = scene.instantiate()
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(app)

	# 等待 LinkChat _ready() 完成
	await get_tree().process_frame
	await get_tree().process_frame

	print("[Test] LinkChat instantiated, activating test topic...")

	# 读取林夏的personality prompt
	var personality_prompt := ""
	var file := FileAccess.open("res://prompts/npc/lin_xia.md", FileAccess.READ)
	if file:
		personality_prompt = file.get_as_text()
		file.close()

	# 通过 ChatManager 激活测试 Topic
	var topic_prompt := personality_prompt + """

## 当前场景
比赛刚刚开始，你和男朋友刚拿到 Lumina Engine 和素材包。
主题「再会」刚刚揭晓，你们需要讨论创意方向。

## 对话目标
- 和玩家讨论对主题「再会」的理解
- 分享你的初步创意想法
- 了解玩家的思路
"""

	var success: bool = ChatManager.activate_test_topic(
		"npc_lin_xia",
		"dm_lin_xia",
		"开赛讨论",
		topic_prompt
	)

	if success:
		print("[Test] Topic activated! You can now chat with 林夏")
		print("[Test] Type in the input field and press Enter")
	else:
		push_error("[Test] Failed to activate topic")
