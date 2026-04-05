extends Control

const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")


func _ready() -> void:
	print("=== Activity Preview Hint Test ===")

	var host := Control.new()
	host.name = "Host"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.custom_minimum_size = Vector2(640, 360)
	add_child(host)

	var button := Button.new()
	button.text = "Hover Me"
	button.position = Vector2(120, 80)
	button.size = Vector2(180, 48)
	host.add_child(button)

	var hint := ActivityPreviewHintClass.new()
	button.add_child(hint)
	hint.set_preview_payload({
		"title": "兼职预览",
		"rewards": {
			"money": 120,
			"stress": -2,
		},
		"conditions": ["下午可用"],
	})

	await get_tree().process_frame
	hint._on_target_mouse_entered()
	await get_tree().process_frame

	var layer := get_node_or_null("ActivityPreviewLayer")
	_assert_true("layer created", layer != null, "should create preview layer")
	_assert_true("layer visible on hover", layer != null and layer.visible, "layer should be visible")
	if layer != null:
		_assert_eq("preview title", layer.get_current_title(), "兼职预览")
		_assert_contains("preview rewards", layer.get_current_body(), "预计结果：金钱 +120，压力 -2")
		_assert_contains("preview conditions", layer.get_current_body(), "条件：下午可用")

	hint._on_target_mouse_exited()
	await get_tree().process_frame
	_assert_true("layer hidden after exit", layer != null and not layer.visible, "layer should hide after exit")
	print("=== Activity Preview Hint Test Done ===")


func _assert_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s, got [%s], expected [%s]" % [label, str(actual), str(expected)])


func _assert_true(label: String, condition: bool, detail: String) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s, %s" % [label, detail])


func _assert_contains(label: String, text: String, expected_fragment: String) -> void:
	if text.contains(expected_fragment):
		print("  OK: %s" % label)
	else:
		push_error("FAIL: %s, text [%s] missing [%s]" % [label, text, expected_fragment])
