extends Node

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")


func _ready() -> void:
	print("=== CG transition defaults test ===")
	var parser: RefCounted = ParserClass.new()
	var result: Dictionary = parser.parse("cg.show(\"cg_event_001\")\ncg.hide()")
	if not bool(result.get("success", false)):
		print("[FAIL] parser should accept cg transition defaults: %s" % str(result.get("errors", [])))
		return

	var commands: Array = result.get("commands", [])
	if commands.size() != 2:
		print("[FAIL] expected 2 commands, got %d" % commands.size())
		return

	var show_cmd = commands[0]
	var hide_cmd = commands[1]
	var show_params: Dictionary = show_cmd.params if show_cmd != null else {}
	var hide_params: Dictionary = hide_cmd.params if hide_cmd != null else {}

	if str(show_params.get("image_id", "")) != "cg":
		print("[FAIL] cg.show should normalize image_id to cg: %s" % str(show_params))
		return
	if str(show_params.get("transition", "")) != "crossfade":
		print("[FAIL] cg.show should default to crossfade transition: %s" % str(show_params))
		return
	if not is_equal_approx(float(show_params.get("fade_duration", 0.0)), 0.25):
		print("[FAIL] cg.show should default to 0.25 fade_duration: %s" % str(show_params))
		return
	if str(hide_params.get("image_id", "")) != "cg":
		print("[FAIL] cg.hide should normalize image_id to cg: %s" % str(hide_params))
		return
	if not is_equal_approx(float(hide_params.get("fade_duration", 0.0)), 0.2):
		print("[FAIL] cg.hide should default to 0.2 fade_duration: %s" % str(hide_params))
		return

	print("[OK] cg.show/cg.hide receive smooth transition defaults")
