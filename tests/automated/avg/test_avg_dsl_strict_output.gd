extends Node
## AVG DSL 只执行模型显式给出的合法语法，不猜测或改写输出。

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")

var _failures: int = 0


func _ready() -> void:
	_test_valid_dialogue()
	_test_bare_text_is_rejected()
	_test_commented_command_is_not_executed()
	_test_legacy_jump_is_rejected()
	if _failures == 0:
		print("[PASS] avg dsl strict output")
	else:
		push_error("[FAIL] avg dsl strict output: %d checks failed" % _failures)


func _test_valid_dialogue() -> void:
	var result: Dictionary = ParserClass.new().parse("# => TextBlock()\n> 一段合法旁白。")
	_check(bool(result.get("success", false)), "documented TextBlock dialogue remains valid")
	_check((result.get("commands", []) as Array).size() == 1, "valid dialogue produces one command")


func _test_bare_text_is_rejected() -> void:
	var result: Dictionary = ParserClass.new().parse("这行没有使用 AVG DSL。")
	_check(not bool(result.get("success", true)), "bare text is rejected instead of becoming narration")
	_check((result.get("commands", []) as Array).is_empty(), "bare text creates no runtime command")


func _test_commented_command_is_not_executed() -> void:
	var result: Dictionary = ParserClass.new().parse("# => bg.show(\"park_day\")\n# => TextBlock()\n> 注释中的命令不应执行。")
	var commands: Array = result.get("commands", []) as Array
	_check(not bool(result.get("success", true)), "comment marker cannot turn another syntax into an executable command")
	_check(commands.size() == 1, "commented command creates no background command")
	if commands.size() == 1:
		_check(str(commands[0].command_type) == "DIALOGUE", "only the explicit dialogue is executed")


func _test_legacy_jump_is_rejected() -> void:
	var result: Dictionary = ParserClass.new().parse("jump_scene(\"old_scene\")")
	_check(not bool(result.get("success", true)), "undocumented legacy jump syntax is rejected")
	_check((result.get("commands", []) as Array).is_empty(), "legacy jump creates no runtime command")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)
