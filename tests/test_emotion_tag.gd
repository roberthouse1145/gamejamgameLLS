extends Control

const EmotionTagScene = preload("res://scenes/minigames/emotion_tag.tscn")


func _ready() -> void:
	print("[TestEmotionTag] Starting emotion_tag minigame test...")

	var instance: Node = EmotionTagScene.instantiate()
	if instance == null:
		print("[TestEmotionTag] ERROR: Failed to instantiate scene")
		return

	add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	instance.minigame_finished.connect(_on_finished)
	instance.minigame_cancelled.connect(_on_cancelled)
	instance.setup({
		"task_data": {
			"task_id": "test_emotion_tag",
			"title": "校准钟塔露台争执戏的情绪",
			"description": "看几句争执戏台词，判断它们各自更接近什么情绪。",
			"minigame_type": "emotion_tag",
			"kb_sources": ["characters", "story", "notes"],
		},
		"minigame_type": "emotion_tag",
		"generated_content": {
			"scene_brief": "这是一组来自钟塔露台争执戏的候选台词，先判断它们的情绪基调。",
			"items": [
				{
					"speaker": "赛琳",
					"line": "你为什么每次都这样？",
					"correct_emotion": "委屈",
					"options": ["愤怒", "委屈", "担忧", "冷淡", "期待"],
				},
				{
					"speaker": "阿尔诺",
					"line": "我不是想躲着你，我只是没想好怎么说。",
					"correct_emotion": "犹豫",
					"options": ["欣喜", "犹豫", "骄傲", "释然", "冷淡"],
				},
				{
					"speaker": "旁白",
					"line": "风从露台边刮过去，谁都没有先把视线挪开。",
					"correct_emotion": "焦虑",
					"options": ["欣喜", "焦虑", "安心", "冷淡", "骄傲"],
				},
				{
					"speaker": "赛琳",
					"line": "……算了，你至少先回来就好。",
					"correct_emotion": "安心",
					"options": ["绝望", "安心", "愤怒", "骄傲", "欣喜"],
				},
				{
					"speaker": "阿尔诺",
					"line": "你别总把所有事都揽到自己身上。",
					"correct_emotion": "担忧",
					"options": ["担忧", "冷淡", "期待", "欣喜", "释然"],
				},
			],
		},
	})
	print("[TestEmotionTag] Minigame started successfully!")


func _on_finished(result: Dictionary) -> void:
	print("[TestEmotionTag] Minigame FINISHED!")
	print("[TestEmotionTag]   score: %.2f" % float(result.get("score", 0.0)))
	print("[TestEmotionTag]   correct_count: %d" % int(result.get("correct_count", 0)))
	print("[TestEmotionTag]   max_combo: %d" % int(result.get("max_combo", 0)))


func _on_cancelled() -> void:
	print("[TestEmotionTag] Minigame CANCELLED")