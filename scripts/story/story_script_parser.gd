class_name StoryScriptParser
## .story 文本格式解析器
## 将人类友好的章节脚本纯文本转换为与 JSON 完全等价的 Dictionary
##
## 格式规则:
##   chapter: <id>             — 章节 ID
##   name: <显示名>            — 章节名称
##   desc: <描述>              — 章节描述
##   next_chapter: <id>        — 后续章节
##   === step_id ===           — 步骤分隔符
##   # 注释                    — 步骤描述
##   [action_type]             — 动作块起始
##   key: value                — 动作/等待/捕获的键值对
##   wait: <type>              — 等待条件
##     key: value              — 等待条件参数（缩进）
##   capture:                  — 捕获块
##     key: jsonpath           — 捕获映射（缩进）
##   next_conditions:          — 条件分支块
##     expr -> step_id         — 条件命中后跳转
##     default -> step_id      — 默认分支
##   -> step_id                — 下一步
##
## 值会自动类型推断:
##   true/false → bool, 纯数字 → int/float, 含逗号 → Array


static func parse(text: String) -> Dictionary:
	var result: Dictionary = {
		"chapter_id": "",
		"chapter_name": "",
		"description": "",
		"priority": 0,
		"trigger": {},
		"next_chapter": "",
		"steps": []
	}

	var lines: PackedStringArray = text.split("\n")
	var i: int = 0
	var current_step: Dictionary = {}
	var in_header: bool = true
	var header_mode: String = ""
	var parse_mode: String = ""  # "", "action", "wait", "capture", "next_conditions"
	var current_action: Dictionary = {}

	while i < lines.size():
		var raw_line: String = lines[i].rstrip("\r")
		var stripped: String = raw_line.strip_edges()
		var is_indented: bool = raw_line.begins_with("  ") or raw_line.begins_with("\t")

		# 跳过空行
		if stripped.is_empty():
			i += 1
			continue

		# ── 章节头部字段 ──
		if in_header:
			if header_mode == "trigger":
				if is_indented and ":" in stripped:
					var trigger_kv: Array = _parse_kv(stripped)
					if trigger_kv.size() == 2:
						result["trigger"][trigger_kv[0]] = _coerce_header_value(trigger_kv[0], trigger_kv[1], header_mode)
					i += 1
					continue
				header_mode = ""

			if stripped.begins_with("chapter:"):
				result["chapter_id"] = stripped.substr(8).strip_edges()
				i += 1
				continue
			elif stripped.begins_with("name:"):
				result["chapter_name"] = stripped.substr(5).strip_edges()
				i += 1
				continue
			elif stripped.begins_with("desc:"):
				result["description"] = stripped.substr(5).strip_edges()
				i += 1
				continue
			elif stripped.begins_with("priority:"):
				result["priority"] = int(_auto_type(stripped.substr(9).strip_edges()))
				i += 1
				continue
			elif stripped == "trigger:":
				header_mode = "trigger"
				if not result.has("trigger"):
					result["trigger"] = {}
				i += 1
				continue
			elif stripped.begins_with("next_chapter:"):
				result["next_chapter"] = stripped.substr(13).strip_edges()
				i += 1
				continue
			elif stripped.begins_with("==="):
				in_header = false
				# 不递增 i，让下面的步骤分隔符逻辑处理
			else:
				i += 1
				continue

		# ── 步骤分隔符 === step_id === ──
		if stripped.begins_with("===") and stripped.ends_with("==="):
			# 保存前一个步骤
			if not current_step.is_empty():
				_finalize_action(current_step, current_action)
				result["steps"].append(current_step)

			var step_id: String = stripped.trim_prefix("===").trim_suffix("===").strip_edges()
			current_step = {
				"step_id": step_id,
				"description": "",
				"actions": [],
				"wait_for": {"type": "immediate"},
				"next": ""
			}
			current_action = {}
			parse_mode = ""
			i += 1
			continue

		# ── 步骤描述 ──
		if stripped.begins_with("#") and parse_mode == "":
			var desc_text: String = stripped.substr(1).strip_edges()
			if current_step.get("description", "") == "":
				current_step["description"] = desc_text
			else:
				current_step["description"] += "\n" + desc_text
			i += 1
			continue

		# ── 动作块起始 [type] ──
		if stripped.begins_with("[") and stripped.ends_with("]"):
			_finalize_action(current_step, current_action)
			var action_type: String = stripped.substr(1, stripped.length() - 2)
			current_action = {"type": action_type}
			parse_mode = "action"
			i += 1
			continue

		# ── 等待条件 ──
		if stripped.begins_with("wait:"):
			_finalize_action(current_step, current_action)
			current_action = {}
			var wait_type: String = stripped.substr(5).strip_edges()
			current_step["wait_for"] = {"type": wait_type}
			parse_mode = "wait"
			i += 1
			continue

		# ── 下一步 ──
		if stripped.begins_with("->"):
			_finalize_action(current_step, current_action)
			current_action = {}
			parse_mode = ""
			current_step["next"] = stripped.substr(2).strip_edges()
			i += 1
			continue

		# ── 捕获块 ──
		if stripped == "capture:":
			_finalize_action(current_step, current_action)
			current_action = {}
			parse_mode = "capture"
			if not current_step.has("capture"):
				current_step["capture"] = {}
			i += 1
			continue

		# ── 条件分支块 ──
		if stripped == "next_conditions:":
			_finalize_action(current_step, current_action)
			current_action = {}
			parse_mode = "next_conditions"
			if not current_step.has("next_conditions"):
				current_step["next_conditions"] = []
			i += 1
			continue

		# ── 条件分支项（缩进行 expr -> step_id） ──
		if parse_mode == "next_conditions" and is_indented and "->" in stripped:
			var arrow_pos: int = stripped.find("->")
			if arrow_pos >= 0:
				var left: String = stripped.substr(0, arrow_pos).strip_edges()
				var next_step: String = stripped.substr(arrow_pos + 2).strip_edges()
				if not next_step.is_empty():
					var condition: Dictionary = {"next": next_step}
					if left == "default" or left == "else":
						condition["default"] = true
					elif left.begins_with("if:"):
						condition["if"] = left.substr(3).strip_edges()
					elif left.begins_with("if "):
						condition["if"] = left.substr(2).strip_edges()
					else:
						condition["if"] = left
					current_step["next_conditions"].append(condition)
			i += 1
			continue

		# ── 缩进行：属于当前块的 key: value ──
		if is_indented and ":" in stripped:
			var kv: Array = _parse_kv(stripped)
			if kv.size() == 2:
				match parse_mode:
					"wait":
						current_step["wait_for"][kv[0]] = _coerce_value(kv[1])
					"capture":
						if not current_step.has("capture"):
							current_step["capture"] = {}
						# capture 值保持字符串（JSONPath 表达式）
						current_step["capture"][kv[0]] = kv[1]
					"action":
						current_action[kv[0]] = _coerce_value(kv[1])
			i += 1
			continue

		# ── 非缩进 key: value（动作模式下） ──
		if parse_mode == "action" and ":" in stripped:
			var kv: Array = _parse_kv(stripped)
			if kv.size() == 2:
				current_action[kv[0]] = _coerce_value(kv[1])
			i += 1
			continue

		# 未识别的行，跳过
		i += 1

	# 保存最后一个步骤
	if not current_step.is_empty():
		_finalize_action(current_step, current_action)
		result["steps"].append(current_step)

	return result


## 从文件路径加载并解析
static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[StoryScriptParser] File not found: %s" % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[StoryScriptParser] Failed to open: %s" % path)
		return {}

	var text: String = file.get_as_text()
	file.close()
	return parse(text)


# =============================================================================
# Internal helpers
# =============================================================================

## 将未提交的 action 追加到 step.actions
static func _finalize_action(step: Dictionary, action: Dictionary) -> void:
	if action.has("type") and not str(action["type"]).is_empty():
		step["actions"].append(action.duplicate(true))
	action.clear()


## 按第一个冒号拆分 key: value
static func _parse_kv(line: String) -> Array:
	var colon_pos: int = line.find(":")
	if colon_pos < 0:
		return []
	var key: String = line.substr(0, colon_pos).strip_edges()
	var value: String = line.substr(colon_pos + 1).strip_edges()
	return [key, value]


static func _coerce_value(value: String) -> Variant:
	return _auto_type(value)


static func _coerce_header_value(key: String, value: String, header_mode: String) -> Variant:
	if header_mode == "trigger" and key in ["conditions", "required_chapters", "excluded_chapters"]:
		return _parse_array_value(value)
	if header_mode == "trigger" and key == "phase":
		return value.strip_edges().to_upper()
	return _auto_type(value)


static func _parse_array_value(value: String) -> Array:
	if value.is_empty():
		return []

	var parts: Array = []
	for part in value.split(","):
		var stripped_part: String = part.strip_edges()
		if stripped_part.is_empty():
			continue
		parts.append(_auto_type(stripped_part))
	return parts


## 自动类型推断
static func _auto_type(value: String) -> Variant:
	if value == "true":
		return true
	if value == "false":
		return false
	if value.is_empty():
		return ""
	# 逗号分隔 → 数组
	if "," in value:
		var parts: Array = []
		for part in value.split(","):
			parts.append(_auto_type(part.strip_edges()))
		return parts
	# 整数
	if value.is_valid_int():
		return value.to_int()
	# 浮点数
	if value.is_valid_float():
		return value.to_float()
	return value
