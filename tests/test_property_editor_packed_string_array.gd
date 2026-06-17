extends Node

const PropertyEditorClass = preload("res://scripts/editor/property_editor.gd")


func _ready() -> void:
	var editor: Control = PropertyEditorClass.new()
	var text: String = editor._packed_string_array_to_text(PackedStringArray(["继续游戏", "历史记录", "设置"]))
	var parsed: PackedStringArray = editor._text_to_packed_string_array("继续游戏\n历史记录\n设置\n")

	var pass_count: int = 0
	if text == "继续游戏\n历史记录\n设置":
		pass_count += 1
		print("PASS  packed string array displays one item per line")
	else:
		print("FAIL  packed string array display text mismatch: %s" % text)

	if parsed == PackedStringArray(["继续游戏", "历史记录", "设置"]):
		pass_count += 1
		print("PASS  multiline text converts back to PackedStringArray")
	else:
		print("FAIL  packed string array parse mismatch: %s" % str(parsed))

	print("SUMMARY  pass=%d fail=%d" % [pass_count, 2 - pass_count])
