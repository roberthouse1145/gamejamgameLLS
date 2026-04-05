extends Control

const BGM_A: String = "res://Assets/sounds/bgm/Care (loop).ogg"
const BGM_B: String = "res://Assets/sounds/bgm/Sentiments (loop).ogg"

@onready var audio_manager: AVGAudioManager = $AVGAudioManager


func _ready() -> void:
	print("=== AVGAudioManager BGM Race Test ===")
	call_deferred("_run_test")


func _run_test() -> void:
	audio_manager.play_bgm(BGM_A, 0.0, 1.0)
	await get_tree().process_frame
	_assert_true("initial BGM starts", audio_manager.is_bgm_playing())

	audio_manager.play_bgm(BGM_B, 1.0, 1.0)
	await get_tree().create_timer(0.1).timeout
	audio_manager.stop_bgm(0.0)
	await get_tree().create_timer(0.7).timeout

	_assert_true("overlapping play/stop leaves BGM stopped", not audio_manager.is_bgm_playing())
	_assert_eq("current BGM path cleared", audio_manager.get_current_bgm(), "")
	print("=== AVGAudioManager BGM Race Test Done ===")


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s" % label)
		print("  FAIL: %s" % label)


func _assert_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s, got [%s], expected [%s]" % [label, str(actual), str(expected)])
		print("  FAIL: %s, got [%s], expected [%s]" % [label, str(actual), str(expected)])
