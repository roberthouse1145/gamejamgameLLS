class_name LiveDSLParser extends RefCounted
## 直播 DSL 解析器。处理 3D 主播动作、字幕、弹幕、SC 与停顿。

var _message_pattern := RegEx.new()


func _init() -> void:
	_message_pattern.compile("^(chat|sc)(?:\\s+(\\d+))?$")


func parse(
	dsl_text: String,
	allowed_expressions: Array,
	allowed_postures: Array = [],
	allowed_gestures: Array = [],
	allowed_costumes: Array = [],
	allowed_arm_poses: Array = [],
	allowed_head_poses: Array = []
) -> Dictionary:
	var ops: Array[Dictionary] = []
	var errors: Array[String] = []
	var lines: PackedStringArray = dsl_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

	for index: int in range(lines.size()):
		var line: String = lines[index].strip_edges()
		if line.is_empty():
			continue
		var separator_index: int = _find_separator(line)
		if separator_index < 0:
			errors.append(_line_error(index, "缺少冒号"))
			continue
		var head: String = line.substr(0, separator_index).strip_edges()
		var body: String = line.substr(separator_index + 1).strip_edges()
		if body.is_empty():
			errors.append(_line_error(index, "冒号后缺少内容"))
			continue

		if head == "say":
			ops.append({"op": "say", "text": body})
			continue

		if head in ["expression", "posture", "gesture", "costume", "arm_pose", "head_pose"]:
			var value := StringName(body)
			var allowed_values: Array
			var value_label: String
			match head:
				"expression":
					allowed_values = allowed_expressions
					value_label = "表情"
				"posture":
					allowed_values = allowed_postures
					value_label = "姿态"
				"gesture":
					allowed_values = allowed_gestures
					value_label = "手势"
				"arm_pose":
					allowed_values = allowed_arm_poses
					value_label = "手臂姿势"
				"head_pose":
					allowed_values = allowed_head_poses
					value_label = "头部姿势"
				_:
					allowed_values = allowed_costumes
					value_label = "服装"
			if not _has_value(allowed_values, value):
				errors.append(_line_error(index, "主播模型不支持%s“%s”" % [value_label, body]))
				continue
			ops.append({"op": head, "value": value})
			continue

		var message_match: RegExMatch = _message_pattern.search(head)
		if message_match != null:
			var messages: Array[String] = _parse_message_pool(body)
			if messages.is_empty():
				errors.append(_line_error(index, "%s 至少需要一条有效消息" % message_match.get_string(1)))
				continue
			var count_text: String = message_match.get_string(2)
			var count: int = messages.size() if count_text.is_empty() else int(count_text)
			if count < 1:
				errors.append(_line_error(index, "发送数量必须大于 0"))
				continue
			ops.append({
				"op": message_match.get_string(1),
				"messages": messages,
				"count": count,
			})
			continue

		if head == "wait":
			if not body.is_valid_float():
				errors.append(_line_error(index, "wait 秒数必须是数字"))
				continue
			var seconds: float = float(body)
			if seconds <= 0.0:
				errors.append(_line_error(index, "wait 秒数必须大于 0"))
				continue
			ops.append({"op": "wait", "seconds": seconds})
			continue

		errors.append(_line_error(index, "未知语句“%s”" % head))

	return {
		"success": errors.is_empty() and not ops.is_empty(),
		"ops": ops,
		"errors": errors if not ops.is_empty() or not errors.is_empty() else ["直播 DSL 不能为空"],
	}


func _find_separator(line: String) -> int:
	var ascii_index: int = line.find(":")
	var fullwidth_index: int = line.find("：")
	if ascii_index < 0:
		return fullwidth_index
	if fullwidth_index < 0:
		return ascii_index
	return mini(ascii_index, fullwidth_index)


func _parse_message_pool(body: String) -> Array[String]:
	var messages: Array[String] = []
	for raw_message: String in body.split("|"):
		var message: String = raw_message.strip_edges()
		if not message.is_empty():
			messages.append(message)
	return messages


func _has_value(allowed_values: Array, value: StringName) -> bool:
	for allowed: Variant in allowed_values:
		if StringName(str(allowed)) == value:
			return true
	return false


func _line_error(zero_based_line: int, message: String) -> String:
	return "第 %d 行：%s" % [zero_based_line + 1, message]
