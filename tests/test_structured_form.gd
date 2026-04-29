extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Structured Form Minigame Test ===")
	var scene: PackedScene = load("res://scenes/minigames/structured_form.tscn")
	if scene == null:
		print("[FAIL] structured_form scene loads")
		return
	var form: Control = scene.instantiate()
	add_child(form)
	form.setup({
		"minigame_type": "structured_form",
		"task_data": _build_task_data(),
	})
	await get_tree().process_frame

	form.call("_set_field_value", "game_title", "月塔密约")
	form.call("_set_field_value", "game_genre", "悬疑推理")
	form.call("_set_field_value", "game_tags", ["暧昧", "黑暗"])
	form.call("_set_field_value", "game_outline", "新生卷入学院禁书库的秘密，并在调查中逐渐靠近一位立场暧昧的少女。")

	var values: Dictionary = form.call("_collect_values")
	_assert_eq("title value", values.get("game_title", ""), "月塔密约")
	_assert_eq("genre value", values.get("game_genre", ""), "悬疑推理")
	_assert_true("tag value is array", values.get("game_tags", []) is Array)
	_assert_eq("tag count", values.get("game_tags", []).size(), 2)

	var validation: Dictionary = form.call("_validate_form")
	_assert_true("valid form passes", bool(validation.get("ok", false)))

	var value_dsl: String = form.call("_parse_value_dsl", "value:\n  第一行\n  第二行")
	_assert_eq("value DSL multiline", value_dsl, "第一行\n第二行")

	var review: Dictionary = form.call("_parse_review_dsl", "approved: false\nreason: 跑题")
	_assert_true("review DSL rejects", not bool(review.get("approved", true)))
	_assert_eq("review DSL reason", review.get("reason", ""), "跑题")

	var creative_prompt: String = form.call("_build_creative_prompt", values)
	_assert_true("creative prompt includes title", creative_prompt.contains("月塔密约"))
	_assert_true("creative prompt includes tags", creative_prompt.contains("暧昧"))
	print("=== Structured Form Minigame Test Done ===")


func _build_task_data() -> Dictionary:
	return {
		"task_id": "test_structured_form",
		"title": "填写测试企划卡",
		"description": "测试结构化表单。",
		"form_config": {
			"form_id": "test_form",
			"title": "测试表单",
			"fields": [
				{"id": "game_title", "type": "text", "label": "作品名称", "required": true, "max_length": 20},
				{"id": "game_genre", "type": "single_select", "label": "类型", "required": true, "allow_custom": true, "options": ["恋爱 Gal", "悬疑推理"]},
				{"id": "game_tags", "type": "multi_select", "label": "标签", "required": true, "min_selected": 1, "max_selected": 3, "options": ["暧昧", "黑暗", "治愈"]},
				{"id": "game_outline", "type": "textarea", "label": "大纲", "required": true, "max_length": 200},
			],
			"review": {"mode": "none"},
		},
	}


func _assert_eq(label: String, got: Variant, expected: Variant) -> void:
	if str(got) == str(expected):
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s — got [%s] expected [%s]" % [label, str(got), str(expected)])


func _assert_true(label: String, condition: bool) -> void:
	if condition:
		print("  OK: %s" % label)
	else:
		print("  FAIL: %s" % label)
