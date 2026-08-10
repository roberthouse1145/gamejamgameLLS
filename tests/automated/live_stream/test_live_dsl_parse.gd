extends Node
## 3D 直播 DSL 的动作解析、模型能力校验与消息池抽取契约。

const ParserScript = preload("res://scripts/game/live_stream/live_dsl_parser.gd")
const PlayerScript = preload("res://scripts/apps/obs_live/components/live_show_player.gd")
const PlayerScene = preload("res://scenes/apps/obs_live/components/live_show_player.tscn")

const VALID_DSL: String = """posture: idle
expression: strained
gesture: wave
say: 大家晚上好，今天来打这个。
chat: 来了来了 | 前排 | 围观
say: 这个 BOSS 有点难。
sc 4: 加油 | 稳住 | 冲冲冲
wait：0.2
expression: smile
say: 今天先这样，下次见。
"""

const EXPRESSIONS: Array[StringName] = [&"default", &"smile", &"strained"]
const POSTURES: Array[StringName] = [&"idle", &"thinking"]
const GESTURES: Array[StringName] = [&"wave"]
const COSTUMES: Array[StringName] = []
const ARM_POSES: Array[StringName] = [&"idle", &"arms_crossed"]
const HEAD_POSES: Array[StringName] = [&"idle", &"head_down"]


func _ready() -> void:
	_test_parse_valid()
	_test_reject_unknown_expression()
	_test_reject_unknown_posture()
	_test_reject_unknown_gesture()
	_test_reject_unknown_costume()
	_test_parse_arm_and_head_pose()
	_test_reject_unknown_arm_and_head_pose()
	_test_reject_expression_inside_say()
	_test_reject_unknown_statement_with_line()
	_test_fullwidth_separator()
	_test_reject_invalid_wait()
	_test_draw_without_replacement()
	await _test_message_pools_are_consumed_in_order()
	print("TEST_LIVE_DSL_PARSE_DONE")


func _test_parse_valid() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse(VALID_DSL, EXPRESSIONS, POSTURES, GESTURES)
	assert(bool(parsed.get("success", false)), "valid live DSL should parse: %s" % [parsed.get("errors", [])])
	var ops: Array = parsed.get("ops", [])
	assert(ops.size() == 10, "expected ten live ops")
	assert(ops[0] == {"op": "posture", "value": &"idle"})
	assert(ops[1] == {"op": "expression", "value": &"strained"})
	assert(ops[2] == {"op": "gesture", "value": &"wave"})
	assert(ops[3].get("op") == "say", "fourth op should be say")
	assert(ops[4].get("op") == "chat", "fifth op should be chat")
	assert(int(ops[4].get("count", 0)) == 3, "chat without count sends each pool item")
	assert(ops[5].get("op") == "say", "say should not carry visual state")
	assert(int(ops[6].get("count", 0)) == 4, "SC count should parse")
	assert(is_equal_approx(float(ops[7].get("seconds", 0.0)), 0.2), "wait should parse")
	assert(ops[8] == {"op": "expression", "value": &"smile"})
	print("TEST_PARSE_VALID ok")


func _test_reject_unknown_costume() -> void:
	var parsed: Dictionary = ParserScript.new().parse(
		"costume: uniform",
		EXPRESSIONS,
		POSTURES,
		GESTURES,
		COSTUMES
	)
	assert(not bool(parsed.get("success", true)))
	assert("不支持服装" in str(parsed.get("errors", [])))
	print("TEST_REJECT_UNKNOWN_COSTUME ok")


func _test_reject_unknown_expression() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse(
		"expression: missing",
		EXPRESSIONS,
		POSTURES,
		GESTURES
	)
	assert(not bool(parsed.get("success", true)), "expression absent from streamer resource should fail")
	assert("不支持表情" in str(parsed.get("errors", [])), "error should explain missing expression")
	print("TEST_REJECT_UNKNOWN_EXPRESSION ok")


func _test_reject_unknown_posture() -> void:
	var parsed: Dictionary = ParserScript.new().parse(
		"posture: missing",
		EXPRESSIONS,
		POSTURES,
		GESTURES
	)
	assert(not bool(parsed.get("success", true)))
	assert("不支持姿态" in str(parsed.get("errors", [])))
	print("TEST_REJECT_UNKNOWN_POSTURE ok")


func _test_reject_unknown_gesture() -> void:
	var parsed: Dictionary = ParserScript.new().parse(
		"gesture: missing",
		EXPRESSIONS,
		POSTURES,
		GESTURES
	)
	assert(not bool(parsed.get("success", true)))
	assert("不支持手势" in str(parsed.get("errors", [])))
	print("TEST_REJECT_UNKNOWN_GESTURE ok")


func _test_parse_arm_and_head_pose() -> void:
	var parsed: Dictionary = ParserScript.new().parse(
		"arm_pose: arms_crossed\nhead_pose: head_down",
		EXPRESSIONS,
		POSTURES,
		GESTURES,
		COSTUMES,
		ARM_POSES,
		HEAD_POSES
	)
	assert(bool(parsed.get("success", false)), "arm/head pose should parse: %s" % [parsed.get("errors", [])])
	var ops: Array = parsed.get("ops", [])
	assert(ops[0] == {"op": "arm_pose", "value": &"arms_crossed"})
	assert(ops[1] == {"op": "head_pose", "value": &"head_down"})
	print("TEST_PARSE_ARM_AND_HEAD_POSE ok")


func _test_reject_unknown_arm_and_head_pose() -> void:
	var bad_arm: Dictionary = ParserScript.new().parse(
		"arm_pose: missing", EXPRESSIONS, POSTURES, GESTURES, COSTUMES, ARM_POSES, HEAD_POSES
	)
	assert(not bool(bad_arm.get("success", true)))
	assert("不支持手臂姿势" in str(bad_arm.get("errors", [])))
	var bad_head: Dictionary = ParserScript.new().parse(
		"head_pose: missing", EXPRESSIONS, POSTURES, GESTURES, COSTUMES, ARM_POSES, HEAD_POSES
	)
	assert(not bool(bad_head.get("success", true)))
	assert("不支持头部姿势" in str(bad_head.get("errors", [])))
	print("TEST_REJECT_UNKNOWN_ARM_AND_HEAD_POSE ok")


func _test_reject_expression_inside_say() -> void:
	var parsed: Dictionary = ParserScript.new().parse(
		"say smile: 旧写法。",
		EXPRESSIONS,
		POSTURES,
		GESTURES
	)
	assert(not bool(parsed.get("success", true)))
	print("TEST_REJECT_EXPRESSION_INSIDE_SAY ok")


func _test_reject_unknown_statement_with_line() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse(
		"say: 第一行。\nunknown: 第二行。",
		EXPRESSIONS,
		POSTURES,
		GESTURES
	)
	assert(not bool(parsed.get("success", true)), "unknown statement should fail")
	assert("第 2 行" in str(parsed.get("errors", [])), "error should include source line")
	print("TEST_REJECT_UNKNOWN_STATEMENT ok")


func _test_fullwidth_separator() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse(
		"chat 25：刷屏 | 哈哈哈 | 稳住",
		EXPRESSIONS,
		POSTURES,
		GESTURES
	)
	assert(bool(parsed.get("success", false)), "fullwidth separator should parse")
	var ops: Array = parsed.get("ops", [])
	var op: Dictionary = ops[0]
	assert(int(op.get("count", 0)) == 25, "chat flood count should parse")
	assert(op.get("messages", []).size() == 3, "chat pool should preserve messages")
	print("TEST_FULLWIDTH_SEPARATOR ok")


func _test_reject_invalid_wait() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse("wait: 0", EXPRESSIONS, POSTURES, GESTURES)
	assert(not bool(parsed.get("success", true)), "zero wait should fail")
	print("TEST_REJECT_INVALID_WAIT ok")


func _test_draw_without_replacement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pool: Array = ["a", "b", "c"]
	var drawn: Array[String] = PlayerScript.draw_without_replacement(pool, 5, rng)
	assert(drawn.size() == 5, "drawn size")
	var first_three: Array[String] = [drawn[0], drawn[1], drawn[2]]
	first_three.sort()
	assert(first_three == ["a", "b", "c"], "first bag should contain each pool item once")
	assert(drawn[3] in pool and drawn[4] in pool, "refill should draw from the current pool")
	print("TEST_DRAW_WITHOUT_REPLACEMENT ok")


func _test_message_pools_are_consumed_in_order() -> void:
	var player: LiveShowPlayer = PlayerScene.instantiate() as LiveShowPlayer
	add_child(player)
	var display := StreamSceneDisplay.new()
	var subtitle_panel := Control.new()
	var subtitle_label := Label.new()
	add_child(subtitle_panel)
	add_child(subtitle_label)
	player.setup(display, subtitle_panel, subtitle_label)

	var received: Array[String] = []
	player.chat_event.connect(func(event: Dictionary) -> void:
		var entries: Array = event.get("entries", [])
		if not entries.is_empty():
			received.append(str(entries[0].get("text", "")))
	)
	var ops: Array = [
		{"op": "chat", "messages": ["前池甲", "前池乙"], "count": 4},
		{"op": "chat", "messages": ["后池甲", "后池乙"], "count": 4},
	]
	assert(player.play(ops, 42))
	player.set_fast_forward(true)
	await player.finished

	assert(received.size() == 8, "both chat counts should be fully emitted")
	for index: int in range(4):
		assert(received[index] in ["前池甲", "前池乙"], "the first pool should finish before the next pool starts")
	for index: int in range(4, 8):
		assert(received[index] in ["后池甲", "后池乙"], "the next pool should only use its own messages")
	player.queue_free()
	subtitle_panel.queue_free()
	subtitle_label.queue_free()
	print("TEST_MESSAGE_POOLS_CONSUMED_IN_ORDER ok")
