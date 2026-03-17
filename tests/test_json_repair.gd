extends Node
## 测试 BrowserManager._repair_json_quotes 和 _parse_json_payload

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		print("ERROR: BrowserManager not found")
		return

	print("\n=== JSON 修复测试 ===\n")

	# Case 1: 正常 JSON，不应被修改
	var c1 := '{"type":"label","text":"正常文本"}'
	_test(bm, "Case1-正常JSON", c1, true)

	# Case 2: 值内含未转义引号 - 典型 LLM 错误
	var c2 := '{"type":"label","text":"他说"你好"然后走了"}'
	_test(bm, "Case2-值内野引号", c2, true)

	# Case 3: 嵌套结构 + 值内引号
	var c3 := '{"type":"vbox","children":[{"type":"label","text":"标题"副标题"结尾"}]}'
	_test(bm, "Case3-嵌套+野引号", c3, true)

	# Case 4: 多个字段都有野引号
	var c4 := '{"title":"[新闻] "重要"通告","hint":"这是"测试"内容"}'
	_test(bm, "Case4-多字段野引号", c4, true)

	# Case 5: 已经正确转义的不应被破坏
	var c5 := '{"type":"label","text":"他说\\"你好\\"然后走了"}'
	_test(bm, "Case5-已转义引号", c5, true)

	# Case 6: 空字符串值
	var c6 := '{"type":"label","text":""}'
	_test(bm, "Case6-空字符串值", c6, true)

	# Case 7: 数组根节点 + 野引号
	var c7 := '[{"title":"[通告] "配给"调整","url":"ark://test"}]'
	_test(bm, "Case7-数组+野引号", c7, true)

	# Case 8: markdown包裹
	var c8 := "```json\n{\"type\":\"label\",\"text\":\"测试\"内容\"\"}\n```"
	_test(bm, "Case8-markdown包裹+野引号", c8, true)

	# Case 9: 缺失开引号（LLM 实际故障）
	var c9 := '{"hint": 技术安全部门提醒，属违规操作。","title":"test"}'
	_test(bm, "Case9-缺失开引号", c9, true)

	# Case 10: 多个字段缺失开引号
	var c10 := '[{"hint": 一段描述内容。","title":"标题","dp": 另一段。"}]'
	_test(bm, "Case10-多字段缺失开引号", c10, true)

	# Case 11: 缺失开引号 + 值内野引号组合
	var c11 := '{"hint": 他说"好的"然后走了。","url":"ark://x"}'
	_test(bm, "Case11-缺失开引号+野引号", c11, true)

	# Case 12: 数值/布尔/null 值不应被误加引号
	var c12 := '{"count":6,"flag":true,"data":null,"neg":-1}'
	_test(bm, "Case12-非字符串值不变", c12, true)

	print("\n=== 测试完成 ===")


func _test(bm: Node, name: String, input: String, expect_success: bool) -> void:
	var result: Variant = bm._parse_json_payload(input)
	if expect_success:
		if result != null:
			print("PASS  %s  result=%s" % [name, str(result).substr(0, 100)])
		else:
			print("FAIL  %s  -> null, input: %s" % [name, input])
	else:
		if result == null:
			print("PASS  %s  -> expected null" % name)
		else:
			print("FAIL  %s  -> expected null but got: %s" % [name, str(result).substr(0, 100)])
