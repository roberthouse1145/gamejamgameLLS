extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== GameLoop stale phase advance test ===")

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		print("[FAIL] GameLoopManager missing")
		return

	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()

	glm.current_day = 1
	glm.time_phase = 2 # NIGHT
	glm.current_ap = 1

	var consumed: bool = glm.consume_ap(1, "date", "story_day1_final_date")
	if not consumed:
		print("[FAIL] failed to consume AP")
		return

	# Simulate StoryDirector immediately entering day2 before the delayed
	# end-of-night advance from day1 resumes.
	if glm.has_method("set_day"):
		glm.set_day(2)
	else:
		glm.current_day = 2
	glm.time_phase = 0 # MORNING

	await get_tree().create_timer(1.2).timeout

	if int(glm.current_day) != 2:
		print("[FAIL] stale day1 night advance should not push day2 to day %d" % int(glm.current_day))
		return
	if int(glm.time_phase) != 0:
		print("[FAIL] expected MORNING after story set_phase, got phase %d" % int(glm.time_phase))
		return
	if int(glm.current_ap) <= 0:
		print("[FAIL] set_day should restore AP for the new story day")
		return

	print("[OK] stale day1 night advance is ignored after story enters day2")
