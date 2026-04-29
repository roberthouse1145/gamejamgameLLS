extends Node
## 测试 code_puzzle 小游戏的独立启动

func _ready() -> void:
	print("[TestCodePuzzle] Starting code_puzzle minigame test...")

	var scene: PackedScene = load("res://scenes/minigames/code_puzzle.tscn")
	if scene == null:
		print("[TestCodePuzzle] ERROR: Failed to load code_puzzle.tscn")
		return

	var instance: Node = scene.instantiate()
	if instance == null:
		print("[TestCodePuzzle] ERROR: Failed to instantiate scene")
		return

	add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var config: Dictionary = {
		"task_data": {
			"task_id": "test_code_puzzle",
			"title": "整理执行顺序",
			"minigame_type": "code_puzzle",
			"stat_changes": {"completion": 8},
			"stress_cost": 4,
		},
		"minigame_type": "code_puzzle",
		"day": 6,
		"heroine_mood": {"affection": 70, "stress": 25, "passion": 66},
	}

	instance.minigame_finished.connect(_on_finished)
	instance.minigame_cancelled.connect(_on_cancelled)
	instance.setup(config)
	print("[TestCodePuzzle] Minigame started successfully!")


func _on_finished(result: Dictionary) -> void:
	print("[TestCodePuzzle] Minigame FINISHED!")
	print("[TestCodePuzzle]   score: %.2f" % float(result.get("score", 0.0)))
	print("[TestCodePuzzle]   moves: %d" % int(result.get("moves", 0)))
	print("[TestCodePuzzle]   elapsed: %.1fs" % float(result.get("elapsed", 0.0)))
	print("[TestCodePuzzle]   puzzle: %s" % str(result.get("puzzle_title", "")))


func _on_cancelled() -> void:
	print("[TestCodePuzzle] Minigame CANCELLED")