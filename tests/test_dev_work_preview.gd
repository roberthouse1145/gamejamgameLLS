extends Control

const DevWorkAppScene = preload("res://scenes/apps/dev_work/dev_work_app.tscn")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := DevWorkAppScene.instantiate()
	add_child(app)
	await get_tree().process_frame

	var task := {
		"task_id": "preview_test_task",
		"title": "测试开发任务",
		"description": "用于测试开发任务预览。",
		"task_type": "chat_topic",
		"stat_changes": {"quality": 5, "completion": 2},
		"stress_cost": 1,
	}

	var rewards: Dictionary = app.call("_get_task_reward_preview", task)
	if int(rewards.get("stress", 0)) <= 0:
		print("[FAIL] Dev work preview should include positive stress")
		return
	if int(rewards.get("passion", 0)) >= 0:
		print("[FAIL] Dev work preview should include negative passion")
		return
	print("[OK] Dev work preview includes stress and passion changes")

	var effect_text: String = str(app.call("_format_stat_changes", task))
	if not effect_text.contains("压力+") or not effect_text.contains("激情-"):
		print("[FAIL] Dev work effect text should mention stress and passion")
		return
	print("[OK] Dev work effect text mentions stress and passion")

	var payload: Dictionary = app.call("_build_task_preview_payload", task, true)
	var rewards_payload: Dictionary = payload.get("rewards", {})
	if int(rewards_payload.get("stress", 0)) <= 0 or int(rewards_payload.get("passion", 0)) >= 0:
		print("[FAIL] Dev work hint payload should expose stress and passion changes")
		return
	print("[OK] Dev work hint payload exposes stress and passion changes")
	print("[OK] Dev work preview test passed")
