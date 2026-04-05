extends Node
## 测试 typing_code 小游戏的独立启动
## 直接实例化小游戏场景，不依赖 DevWorkApp

func _ready() -> void:
	print("[TestTypingCode] Starting typing_code minigame test...")

	var scene: PackedScene = load("res://scenes/minigames/typing_code.tscn")
	if scene == null:
		print("[TestTypingCode] ERROR: Failed to load typing_code.tscn")
		return

	var instance: Node = scene.instantiate()
	if instance == null:
		print("[TestTypingCode] ERROR: Failed to instantiate scene")
		return

	add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 模拟 MinigameManager 的 setup 调用
	var config: Dictionary = {
		"task_data": {
			"task_id": "rush_progress",
			"title": "赶进度",
			"minigame_type": "typing_code",
			"stat_changes": {"completion": 10},
			"stress_cost": 5,
		},
		"minigame_type": "typing_code",
		"day": 3,
		"heroine_mood": {"affection": 80, "stress": 20, "passion": 60},
	}

	instance.minigame_finished.connect(_on_finished)
	instance.minigame_cancelled.connect(_on_cancelled)
	instance.setup(config)
	print("[TestTypingCode] Minigame started successfully!")


func _on_finished(result: Dictionary) -> void:
	print("[TestTypingCode] Minigame FINISHED!")
	print("[TestTypingCode]   score: %.2f" % float(result.get("score", 0.0)))
	print("[TestTypingCode]   accuracy: %.2f" % float(result.get("accuracy", 0.0)))
	print("[TestTypingCode]   max_combo: %d" % int(result.get("max_combo", 0)))
	print("[TestTypingCode]   elapsed: %.1fs" % float(result.get("elapsed", 0.0)))
	print("[TestTypingCode]   snippet: %s" % str(result.get("snippet_title", "")))


func _on_cancelled() -> void:
	print("[TestTypingCode] Minigame CANCELLED")
