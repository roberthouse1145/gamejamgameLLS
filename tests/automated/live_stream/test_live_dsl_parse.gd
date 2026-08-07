extends Node
## 直播 DSL 的解析、动态表情校验与消息池抽取契约。

const ParserScript = preload("res://scripts/game/live_stream/live_dsl_parser.gd")
const PlayerScript = preload("res://scripts/apps/obs_live/components/live_show_player.gd")

const VALID_DSL: String = """say strained: 大家晚上好，今天来打这个。
chat: 来了来了 | 前排 | 围观
say: 这个 BOSS 有点难。
sc 4: 加油 | 稳住 | 冲冲冲
wait：0.2
say smile: 今天先这样，下次见。
"""

const EXPRESSIONS: Array[StringName] = [&"default", &"smile", &"strained"]


func _ready() -> void:
	_test_parse_valid()
	_test_reject_unknown_expression()
	_test_reject_unknown_statement_with_line()
	_test_fullwidth_separator()
	_test_reject_invalid_wait()
	_test_draw_without_replacement()
	print("TEST_LIVE_DSL_PARSE_DONE")


func _test_parse_valid() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse(VALID_DSL, EXPRESSIONS)
	assert(bool(parsed.get("success", false)), "valid live DSL should parse: %s" % [parsed.get("errors", [])])
	var ops: Array = parsed.get("ops", [])
	assert(ops.size() == 6, "expected six live ops")
	assert(ops[0].get("op") == "say", "first op should be say")
	assert(ops[0].get("expression") == &"strained", "explicit expression should parse")
	assert(ops[1].get("op") == "chat", "second op should be chat")
	assert(int(ops[1].get("count", 0)) == 3, "chat without count sends each pool item")
	assert(ops[2].get("expression") == &"strained", "say without expression should keep current expression")
	assert(ops[3].get("op") == "sc", "fourth op should be sc")
	assert(int(ops[3].get("count", 0)) == 4, "SC count should parse")
	assert(is_equal_approx(float(ops[4].get("seconds", 0.0)), 0.2), "wait should parse")
	assert(ops[5].get("expression") == &"smile", "later expression should replace current expression")
	print("TEST_PARSE_VALID ok")


func _test_reject_unknown_expression() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse("say missing: 不存在的表情。", EXPRESSIONS)
	assert(not bool(parsed.get("success", true)), "expression absent from streamer resource should fail")
	assert("不存在表情" in str(parsed.get("errors", [])), "error should explain missing expression")
	print("TEST_REJECT_UNKNOWN_EXPRESSION ok")


func _test_reject_unknown_statement_with_line() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse("say: 第一行。\nunknown: 第二行。", EXPRESSIONS)
	assert(not bool(parsed.get("success", true)), "unknown statement should fail")
	assert("第 2 行" in str(parsed.get("errors", [])), "error should include source line")
	print("TEST_REJECT_UNKNOWN_STATEMENT ok")


func _test_fullwidth_separator() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse("chat 25：刷屏 | 哈哈哈 | 稳住", EXPRESSIONS)
	assert(bool(parsed.get("success", false)), "fullwidth separator should parse")
	var ops: Array = parsed.get("ops", [])
	var op: Dictionary = ops[0]
	assert(int(op.get("count", 0)) == 25, "chat flood count should parse")
	assert(op.get("messages", []).size() == 3, "chat pool should preserve messages")
	print("TEST_FULLWIDTH_SEPARATOR ok")


func _test_reject_invalid_wait() -> void:
	var parser = ParserScript.new()
	var parsed: Dictionary = parser.parse("wait: 0", EXPRESSIONS)
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
	assert(drawn[3] in pool and drawn[4] in pool, "refill should draw from full pool")
	print("TEST_DRAW_WITHOUT_REPLACEMENT ok")
