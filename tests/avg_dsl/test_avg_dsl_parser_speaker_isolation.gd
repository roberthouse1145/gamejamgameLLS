extends Node
## 验证 parser 的 TextBlock 行归属行为：
## 连续、同缩进的 > 行会合并进同一个 TextBlock；
## 要切换到旁白或其他 speaker，必须显式写新的 # => TextBlock(...)。

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")

var _parser: RefCounted
var _all_passed: bool = true


func _ready() -> void:
	_parser = ParserClass.new()
	print("========== AVG DSL Parser Speaker Isolation Tests ==========")
	_test_single_dialogue_keeps_speaker()
	_test_explicit_narration_block()
	_test_multiple_dialogue_blocks_each_keep_own_speaker()
	_test_consecutive_dialogue_lines_share_text_block()
	_test_dialogue_then_narration_explicit()
	print("========== Tests Complete ==========")
	if _all_passed:
		print("PASS")
	else:
		print("FAIL")


## Case 1: 单组 # => TextBlock(speaker="A") + 一行 > → speaker="A"
func _test_single_dialogue_keeps_speaker() -> void:
	var dsl: String = "# => TextBlock(speaker=\"CharacterA\", expression=\"happy\")\n> 你好"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "case1 parse success")
	var cmds: Array = result.get("commands", [])
	_assert_eq(cmds.size(), 1, "case1 command count")
	if cmds.is_empty():
		return
	var cmd: AVGCommand = cmds[0]
	_assert_eq(cmd.params.get("speaker", ""), "CharacterA", "case1 speaker preserved")
	_assert_eq(cmd.params.get("text", ""), "你好", "case1 text preserved")


## Case 2: # => TextBlock() + 一行 > → speaker=""（旁白）
func _test_explicit_narration_block() -> void:
	var dsl: String = "# => TextBlock()\n> 风从窗外吹进来。"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "case2 parse success")
	var cmds: Array = result.get("commands", [])
	_assert_eq(cmds.size(), 1, "case2 command count")
	if cmds.is_empty():
		return
	var cmd: AVGCommand = cmds[0]
	_assert_eq(cmd.params.get("speaker", ""), "", "case2 speaker empty for narration")
	_assert_eq(cmd.params.get("text", ""), "风从窗外吹进来。", "case2 text preserved")


## Case 3: 两组独立配对，各自保留自己的 speaker
func _test_multiple_dialogue_blocks_each_keep_own_speaker() -> void:
	var dsl: String = "# => TextBlock(speaker=\"CharacterA\")\n> 我也不想告诉你。\n# => TextBlock(speaker=\"洛恩\")\n> 我没问。"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "case3 parse success")
	var cmds: Array = result.get("commands", [])
	_assert_eq(cmds.size(), 2, "case3 command count")
	if cmds.size() < 2:
		return
	_assert_eq((cmds[0] as AVGCommand).params.get("speaker", ""), "CharacterA", "case3 first speaker")
	_assert_eq((cmds[0] as AVGCommand).params.get("text", ""), "我也不想告诉你。", "case3 first text")
	_assert_eq((cmds[1] as AVGCommand).params.get("speaker", ""), "洛恩", "case3 second speaker")
	_assert_eq((cmds[1] as AVGCommand).params.get("text", ""), "我没问。", "case3 second text")


## Case 4: # => TextBlock(speaker="A") + 多行 > → 同一个 speaker / 同一个 DIALOGUE
func _test_consecutive_dialogue_lines_share_text_block() -> void:
	var dsl: String = "# => TextBlock(speaker=\"赛琳\")\n> 我也不想告诉你。\n> 他没有告诉赛琳。\n> 他想知道她为什么这么在意。"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "case4 parse success")
	var cmds: Array = result.get("commands", [])
	_assert_eq(cmds.size(), 1, "case4 command count")
	if cmds.is_empty():
		return
	_assert_eq((cmds[0] as AVGCommand).params.get("speaker", ""), "赛琳", "case4 line1 speaker")
	_assert_eq((cmds[0] as AVGCommand).params.get("text", ""), "我也不想告诉你。\n他没有告诉赛琳。\n他想知道她为什么这么在意。", "case4 multiline text")


## Case 5: 角色台词后接显式旁白块，行为正常
func _test_dialogue_then_narration_explicit() -> void:
	var dsl: String = "# => TextBlock(speaker=\"CharacterA\")\n> 我也不想告诉你。\n# => TextBlock()\n> 他没有告诉对方。"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "case5 parse success")
	var cmds: Array = result.get("commands", [])
	_assert_eq(cmds.size(), 2, "case5 command count")
	if cmds.size() < 2:
		return
	_assert_eq((cmds[0] as AVGCommand).params.get("speaker", ""), "CharacterA", "case5 dialogue speaker")
	_assert_eq((cmds[1] as AVGCommand).params.get("speaker", ""), "", "case5 narration speaker empty")


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("  PASS " + label)
		return
	_all_passed = false
	push_error("FAIL " + label)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("  PASS " + label)
		return
	_all_passed = false
	push_error("FAIL %s actual=%s expected=%s" % [label, str(actual), str(expected)])
