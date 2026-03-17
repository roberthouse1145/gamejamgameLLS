extends SceneTree

func _init():
	var parser = load("res://scripts/avg/dsl/avg_dsl_parser_v2.gd").new()
	var dict = parser.parse("char_001.show(position=\"center\", outfit=\"loungewear\", emotion=\"happy\")")
	if dict.success:
		for cmd in dict.commands:
			print("Command Type: ", cmd.command_type)
			print("Params: ", cmd.params)
	else:
		print("Parse error: ", dict.errors)
	quit()
