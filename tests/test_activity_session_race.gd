extends Node

const ActivitySessionManagerBase = preload("res://autoload/activity_session_manager.gd")
const DateManagerScript = preload("res://autoload/date_manager.gd")
const PartTimeManagerScript = preload("res://autoload/part_time_job_manager.gd")
const SbeamManagerScript = preload("res://autoload/sbeam_manager.gd")


class TestActivityManager extends ActivitySessionManagerBase:
	func _get_activity_type() -> String:
		return "test_activity"


	func _find_entry(_entry_id: String) -> Dictionary:
		return {}


	func make_scene_ready_session(session_id: String) -> void:
		var session: Dictionary = _build_base_session(
			session_id,
			"entry_01",
			{"title": "Test Entry"},
			false,
			0.05
		)
		session["scene_requested"] = true
		session["scene_ready"] = true
		session["scene_result"] = {"choice_text": "already_available"}
		session["scene_package"] = {"title": "ready"}
		_pending_sessions[session_id] = session


	func start_progress(session_id: String) -> void:
		_emit_progress_started(session_id)


	func get_session_data(session_id: String) -> Dictionary:
		return get_session_snapshot(session_id)


	func _start_followup_phase(session_id: String) -> void:
		if not _pending_sessions.has(session_id):
			return
		var session: Dictionary = (_pending_sessions[session_id] as Dictionary).duplicate(true)
		session["followup_done"] = true
		session["moment_done"] = true
		_pending_sessions[session_id] = session


func _ready() -> void:
	print("=== Activity Session Race Test ===")
	await _test_progress_completes_when_scene_ready_arrives_early()
	_test_departure_prompt_is_not_polluted()
	print("=== Activity Session Race Test Complete ===")


func _test_progress_completes_when_scene_ready_arrives_early() -> void:
	var manager := TestActivityManager.new()
	add_child(manager)
	await get_tree().process_frame

	var session_id := "test_activity_early_scene"
	manager.make_scene_ready_session(session_id)
	manager.start_progress(session_id)
	await get_tree().create_timer(0.25).timeout

	var session: Dictionary = manager.get_session_data(session_id)
	var completed: bool = bool(session.get("progress_phase_complete", false))
	if completed:
		print("[OK] scene_ready early completion works")
	else:
		print("[FAIL] scene_ready early completion stuck")

	manager.queue_free()
	await get_tree().process_frame


func _test_departure_prompt_is_not_polluted() -> void:
	var date_manager = DateManagerScript.new()
	var part_time_manager = PartTimeManagerScript.new()
	var sbeam_manager = SbeamManagerScript.new()

	var date_session: Dictionary = {
		"location": {"title": "Seaside"},
		"detail_prompt": "Night wind",
		"important_event_result": {"choice_text": "IMPORTANT_CHOICE", "summary": "IMPORTANT_SUMMARY"},
		"important_event_outline": "IMPORTANT_OUTLINE",
		"scene_result": {"choice_text": "DATE_CHOICE"},
		"scene_outline": "DATE_OUTLINE",
	}
	_assert_departure_context_clean(
		"DateManager",
		date_manager._build_topic_prompt(date_session, "departure"),
		date_manager._build_topic_prompt(date_session, "followup"),
		["IMPORTANT_CHOICE", "IMPORTANT_SUMMARY", "IMPORTANT_OUTLINE", "DATE_CHOICE", "DATE_OUTLINE"]
	)

	var part_time_session: Dictionary = {
		"job": {"job_title": "Bookstore Shift"},
		"detail_prompt": "Night restock",
		"scene_result": {"choice_text": "PART_TIME_CHOICE"},
		"scene_outline": "PART_TIME_OUTLINE",
	}
	_assert_departure_context_clean(
		"PartTimeJobManager",
		part_time_manager._build_topic_prompt(part_time_session, "departure"),
		part_time_manager._build_topic_prompt(part_time_session, "followup"),
		["PART_TIME_CHOICE", "PART_TIME_OUTLINE"]
	)

	var sbeam_session: Dictionary = {
		"game": {"title": "Co-op Puzzle"},
		"pitch": "Solve together",
		"reaction_summary": "Light vibe",
		"scene_result": {"choice_text": "SBEAM_CHOICE"},
		"scene_outline": "SBEAM_OUTLINE",
	}
	_assert_departure_context_clean(
		"SbeamManager",
		sbeam_manager._build_topic_prompt(sbeam_session, "departure"),
		sbeam_manager._build_topic_prompt(sbeam_session, "followup"),
		["SBEAM_CHOICE", "SBEAM_OUTLINE"]
	)


func _assert_departure_context_clean(
	manager_name: String,
	departure_prompt: String,
	followup_prompt: String,
	sentinels: Array[String]
) -> void:
	var polluted: bool = false
	var followup_missing: Array[String] = []
	for sentinel in sentinels:
		if departure_prompt.contains(sentinel):
			polluted = true
		if not followup_prompt.contains(sentinel):
			followup_missing.append(sentinel)

	if polluted:
		print("[FAIL] %s departure prompt polluted" % manager_name)
	else:
		print("[OK] %s departure prompt clean" % manager_name)

	if followup_missing.is_empty():
		print("[OK] %s followup prompt keeps scene context" % manager_name)
	else:
		print("[FAIL] %s followup prompt missing: %s" % [manager_name, ", ".join(followup_missing)])
