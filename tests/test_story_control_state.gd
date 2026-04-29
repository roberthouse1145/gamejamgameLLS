extends Node

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Story Control State Test ===")

	var story: Node = get_node_or_null("/root/StoryDirector")
	var chat: Node = get_node_or_null("/root/ChatManager")
	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var npc_initiative: Node = get_node_or_null("/root/NpcInitiativeManager")
	if story == null or chat == null or home == null or glm == null or npc_initiative == null:
		print("[FAIL] missing required autoload")
		return

	if npc_initiative.has_method("reset_runtime_state"):
		npc_initiative.reset_runtime_state()
	if npc_initiative.has_method("load_run_state"):
		npc_initiative.load_run_state({
			"initiatives_today": 1,
			"last_initiative_day": 1,
			"cooldown_phases": 99,
		})
	if story.has_method("reset_runtime_state"):
		story.reset_runtime_state()
	if chat.has_method("reset_runtime_state"):
		chat.reset_runtime_state(false)
	if home.has_method("reset_runtime_state"):
		home.reset_runtime_state()
	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()
	await get_tree().process_frame

	if not story.has_method("is_taking_control"):
		print("[FAIL] StoryDirector.is_taking_control missing")
		return
	if bool(story.is_taking_control()):
		print("[FAIL] clean runtime should not be taking control")
		return
	if not ActivityLockUtilsClass.is_free_period():
		print("[FAIL] clean runtime should be free period")
		return
	print("[OK] clean runtime is free period")

	var chapter := StoryChapterClass.new()
	chapter.chapter_id = "test_manual_control_release"
	chapter.chapter_name = "测试剧情控制释放"

	var step := StoryStepClass.new()
	step.step_id = "test_manual_control_release_step"
	chapter.steps = [step]

	story.current_chapter = chapter
	story.current_step = step
	if not bool(story.is_taking_control()):
		print("[FAIL] active chapter should take control")
		return
	if ActivityLockUtilsClass.is_free_period():
		print("[FAIL] active chapter should block free period")
		return
	print("[OK] active chapter takes control")

	story.call("_complete_chapter")
	await get_tree().process_frame

	if bool(story.is_taking_control()):
		print("[FAIL] completed chapter should release control")
		return
	if not ActivityLockUtilsClass.is_free_period():
		print("[FAIL] completed chapter should return to free period")
		return
	print("[OK] completed chapter releases control and returns to free period")
