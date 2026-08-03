extends Node

const AVGDSLParserV2Class = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var parser = AVGDSLParserV2Class.new()
	var pass_count: int = 0
	var fail_count: int = 0

	# Case 1: 大写底层命令名必须报错，不能降级旁白
	var dsl1 := """JUMP_SCENE(scene_id="roommate_meeting")"""
	var r1 := parser.parse(dsl1) as Dictionary
	var errs1: Array = r1.get("errors", [])
	var cmds1: Array = r1.get("commands", [])
	if errs1.size() > 0 and str(errs1[0].get("message", "")).contains("Forbidden uppercase internal command"):
		print("[PASS] case1: JUMP_SCENE(...) emits error")
		pass_count += 1
	else:
		push_error("[FAIL] case1: expected forbidden-uppercase error, got %s" % str(errs1))
		fail_count += 1
	# 不应当有 DIALOGUE 命令（即不被降级为旁白）
	var has_dialogue1 := false
	for c in cmds1:
		if c != null and str(c.command_type) == "DIALOGUE":
			has_dialogue1 = true
			break
	if not has_dialogue1:
		print("[PASS] case1: not auto-wrapped as DIALOGUE")
		pass_count += 1
	else:
		push_error("[FAIL] case1: still auto-wrapped as DIALOGUE")
		fail_count += 1

	# Case 2: SHOW_CHARACTER / CALL_EVENT 同类大写形式也应被拒绝
	var dsl2 := """SHOW_CHARACTER(character_id="CharacterA")
CALL_EVENT(event_id="ev1")"""
	var r2 := parser.parse(dsl2) as Dictionary
	var errs2: Array = r2.get("errors", [])
	if errs2.size() >= 2:
		print("[PASS] case2: both uppercase commands emit errors (got %d)" % errs2.size())
		pass_count += 1
	else:
		push_error("[FAIL] case2: expected 2 errors, got %d :: %s" % [errs2.size(), str(errs2)])
		fail_count += 1

	# Case 3: 合法语法 scene.jump("x") 必须正常生成 JUMP_SCENE 命令，不被误伤
	var dsl3 := """scene.jump("scene_002")"""
	var r3 := parser.parse(dsl3) as Dictionary
	var cmds3: Array = r3.get("commands", [])
	var errs3: Array = r3.get("errors", [])
	var has_jump3 := false
	for c in cmds3:
		if c != null and str(c.command_type) == "JUMP_SCENE":
			has_jump3 = true
			break
	if has_jump3 and errs3.is_empty():
		print("[PASS] case3: scene.jump(...) produces JUMP_SCENE without errors")
		pass_count += 1
	else:
		push_error("[FAIL] case3: scene.jump(...) broke. cmds=%s errs=%s" % [str(cmds3), str(errs3)])
		fail_count += 1

	# Case 4: 合法 legacy jump_scene("x") 仍可用
	var dsl4 := """jump_scene("scene_003")"""
	var r4 := parser.parse(dsl4) as Dictionary
	var cmds4: Array = r4.get("commands", [])
	var has_jump4 := false
	for c in cmds4:
		if c != null and str(c.command_type) == "JUMP_SCENE":
			has_jump4 = true
			break
	if has_jump4:
		print("[PASS] case4: legacy jump_scene(...) still works")
		pass_count += 1
	else:
		push_error("[FAIL] case4: legacy jump_scene(...) broken")
		fail_count += 1

	# Case 5: 普通对象方法调用 CharacterA.show(...) 不被大写守卫误伤
	var dsl5 := """CharacterA.show(position="center")"""
	var r5 := parser.parse(dsl5) as Dictionary
	var errs5: Array = r5.get("errors", [])
	if errs5.is_empty():
		print("[PASS] case5: CharacterA.show(...) not flagged as uppercase command")
		pass_count += 1
	else:
		push_error("[FAIL] case5: CharacterA.show(...) was flagged: %s" % str(errs5))
		fail_count += 1

	print("\n=== %d passed, %d failed ===" % [pass_count, fail_count])
	print("[TEST] done. waiting (no auto-quit).")
