extends Node

var _captured_payload: Dictionary = {}


func _ready() -> void:
	print("=== Home Rest Rewards Payload Test ===")

	var home: Node = get_node_or_null("/root/HomeActivityManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if home == null or gm == null or glm == null:
		push_error("missing autoload")
		return

	if gm.has_method("reset_runtime_state"):
		gm.reset_runtime_state()
	if glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()
	if home.has_method("reset_runtime_state"):
		home.reset_runtime_state()

	var callback := Callable(self, "_on_activity_completed")
	if not home.activity_completed.is_connected(callback):
		home.activity_completed.connect(callback)

	gm.stress = 20
	gm.affection = 30

	var session_id: String = "home_rest_payload_test"
	home._pending_sessions[session_id] = {
		"session_id": session_id,
		"activity_id": "rest",
		"activity_type": "life",
		"activity": {
			"activity_id": "rest",
			"ap_cost": 0,
			"stat_effects": {"stress": -25},
		},
		"context": {},
		"extra_stat_effects": {},
		"start_day": 1,
		"start_phase": "NIGHT",
		"reply_text": "",
		"moment": {},
		"settlement_done": false,
	}

	home._finish_session(session_id)
	await get_tree().process_frame

	_assert_eq("payload reward stress", int((_captured_payload.get("rewards", {}) as Dictionary).get("stress", 0)), -25)
	_assert_eq("game manager stress applied", int(gm.stress), 0)
	print("=== Home Rest Rewards Payload Test Done ===")


func _on_activity_completed(activity_id: String, payload: Dictionary) -> void:
	if activity_id == "rest":
		_captured_payload = payload.duplicate(true)


func _assert_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s, got [%s], expected [%s]" % [label, str(actual), str(expected)])
		print("  FAIL: %s, got [%s], expected [%s]" % [label, str(actual), str(expected)])
