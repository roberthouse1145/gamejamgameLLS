class_name DslPageParser
extends RefCounted
## 将类 HTML 标签式 DSL 解析为渲染器可用的 Dictionary 节点树。
##
## 语法：
##   <vbox>...</vbox>    <hbox>...</hbox>
##   <panel bg=#色 fill>...</panel>
##   <margin 数字>...</margin>
##   <label size=数字 color=#色>文本</label>
##   <rich size=数字 color=#色>bbcode内容</rich>
##   <spacer 数字/>   <hr/>


## 自闭合标签类型
const VOID_TYPES: Array = ["spacer", "hr", "input", "select"]
## 容器类型（有子节点）
const CONTAINER_TYPES: Array = ["vbox", "hbox", "panel", "panelcontainer", "margin", "margincontainer"]
## 叶子类型（内容在标签内）
const LEAF_TYPES: Array = ["label", "rich", "button", "link", "input", "textarea", "checkbox", "select"]


static func parse(source: String) -> Dictionary:
	var text := _strip_fences(source.strip_edges())
	if text.is_empty():
		return {}
	var pos := 0
	var nodes := _parse_children(text, pos, "")
	if nodes.is_empty():
		return {}
	if nodes.size() == 1:
		return nodes[0]
	return {"type": "vbox", "children": nodes}


# ── 核心递归解析 ─────────────────────────────────────

static func _parse_children(text: String, pos: int, parent_tag: String) -> Array:
	var result: Array = []
	var length := text.length()

	while pos < length:
		# 跳过空白
		while pos < length and _is_whitespace(text[pos]):
			pos += 1
		if pos >= length:
			break

		# 检查是否遇到父标签的关闭标签
		if not parent_tag.is_empty() and _starts_with_close_tag(text, pos, parent_tag):
			break

		# 遇到 < 开始解析标签
		if text[pos] == "<":
			# 跳过 HTML 注释 <!-- ... -->
			if pos + 3 < length and text.substr(pos, 4) == "<!--":
				var end_comment := text.find("-->", pos + 4)
				if end_comment >= 0:
					pos = end_comment + 3
				else:
					pos = length
				continue
			var tag_result := _parse_tag(text, pos, parent_tag)
			if tag_result.is_empty():
				# 解析失败，跳过这个 <
				pos += 1
				continue
			result.append(tag_result["node"])
			pos = int(tag_result["end_pos"])
		else:
			# 在容器标签内遇到非标签文本，当作纯文本 label
			var text_end := text.find("<", pos)
			if text_end == -1:
				text_end = length
			var raw := text.substr(pos, text_end - pos).strip_edges()
			if not raw.is_empty():
				result.append({"type": "label", "text": raw})
			pos = text_end

	return result


static func _parse_tag(text: String, pos: int, _parent_tag: String) -> Dictionary:
	var length := text.length()

	# 跳过 <
	pos += 1

	# 检测是否是关闭标签 </xxx>
	if pos < length and text[pos] == "/":
		return {} # 由 _parse_children 中的 _starts_with_close_tag 处理

	# 读取标签名
	var tag_start := pos
	while pos < length and text[pos] != " " and text[pos] != ">" and text[pos] != "/" and text[pos] != "\n" and text[pos] != "\t":
		pos += 1
	var tag_name := text.substr(tag_start, pos - tag_start).to_lower().strip_edges()
	if tag_name.is_empty():
		return {}

	# 读取属性直到 > 或 />
	var attrs_text := ""
	var is_self_closing := false
	while pos < length:
		if text[pos] == "/" and pos + 1 < length and text[pos + 1] == ">":
			is_self_closing = true
			pos += 2
			break
		elif text[pos] == ">":
			pos += 1
			break
		else:
			attrs_text += text[pos]
			pos += 1

	var attrs := _parse_attrs(attrs_text)

	# ── 自闭合标签（spacer, hr）──
	if is_self_closing or tag_name in VOID_TYPES:
		if tag_name == "hr" or tag_name == "separator":
			return {"node": {"type": "separator"}, "end_pos": pos}
		if tag_name == "spacer":
			var s := 16
			if attrs.has("_positional"):
				s = int(str(attrs["_positional"]))
			elif attrs.has("height"):
				s = int(str(attrs["height"]))
			return {"node": {"type": "spacer", "width": s, "height": s}, "end_pos": pos}
		if tag_name == "input":
			var input_node: Dictionary = {"type": "input"}
			for key in attrs.keys():
				if key == "_positional":
					continue
				input_node[key] = attrs[key]
			if attrs.has("size"):
				input_node["font_size"] = int(str(attrs["size"]))
			return {"node": input_node, "end_pos": pos}
		if tag_name == "select":
			var select_node: Dictionary = {"type": "select"}
			for key in attrs.keys():
				if key == "_positional":
					continue
				select_node[key] = attrs[key]
			if attrs.has("size"):
				select_node["font_size"] = int(str(attrs["size"]))
			return {"node": select_node, "end_pos": pos}
		# 未知自闭合
		return {"node": {"type": "label", "text": "[未知: %s]" % tag_name}, "end_pos": pos}

	# ── 叶子标签（label, rich）──
	if tag_name == "label" or tag_name == "rich" or tag_name == "rich_text":
		var content_start := pos
		var close_pos := _find_close_tag(text, pos, tag_name)
		if close_pos == -1:
			# 没有关闭标签 → 取到末尾
			close_pos = length
		var inner := text.substr(content_start, close_pos - content_start)
		pos = close_pos
		# 跳过关闭标签
		if pos < length and _starts_with_close_tag(text, pos, tag_name):
			pos = _skip_close_tag(text, pos, tag_name)

		if tag_name == "label":
			var node: Dictionary = {"type": "label", "text": _clean_text(inner)}
			if attrs.has("size"):
				node["font_size"] = int(str(attrs["size"]))
			if attrs.has("color"):
				node["color"] = str(attrs["color"])
			if attrs.has("align"):
				node["align"] = str(attrs["align"])
			if attrs.has("wrap"):
				node["wrap"] = true
			if attrs.has("nowrap"):
				node["nowrap"] = true
			return {"node": node, "end_pos": pos}
		else:
			var node: Dictionary = {"type": "rich_text", "bbcode": _clean_rich_content(inner)}
			if attrs.has("size"):
				node["font_size"] = int(str(attrs["size"]))
			if attrs.has("color"):
				node["color"] = str(attrs["color"])
			return {"node": node, "end_pos": pos}

	# ── 交互叶子标签（button, link）──
	if tag_name == "textarea":
		var content_start := pos
		var close_pos := _find_close_tag(text, pos, tag_name)
		if close_pos == -1:
			close_pos = length
		var inner := text.substr(content_start, close_pos - content_start)
		pos = close_pos
		if pos < length and _starts_with_close_tag(text, pos, tag_name):
			pos = _skip_close_tag(text, pos, tag_name)

		var text_area_node: Dictionary = {"type": "textarea", "text": inner.strip_edges()}
		for key in attrs.keys():
			if key == "_positional":
				continue
			text_area_node[key] = attrs[key]
		if attrs.has("size"):
			text_area_node["font_size"] = int(str(attrs["size"]))
		return {"node": text_area_node, "end_pos": pos}

	if tag_name == "button" or tag_name == "link" or tag_name == "checkbox":
		var content_start := pos
		var close_pos := _find_close_tag(text, pos, tag_name)
		if close_pos == -1:
			close_pos = length
		var inner := text.substr(content_start, close_pos - content_start)
		pos = close_pos
		if pos < length and _starts_with_close_tag(text, pos, tag_name):
			pos = _skip_close_tag(text, pos, tag_name)

		var node: Dictionary = {"type": tag_name, "text": _clean_text(inner)}
		if attrs.has("size"):
			node["font_size"] = int(str(attrs["size"]))
		if attrs.has("color"):
			node["color"] = str(attrs["color"])
		if attrs.has("bg_color"):
			node["bg_color"] = str(attrs["bg_color"])
		if attrs.has("action"):
			node["action"] = str(attrs["action"])
		if attrs.has("url"):
			node["url"] = str(attrs["url"])
		if attrs.has("action_id"):
			node["action_id"] = str(attrs["action_id"])
		if attrs.has("keyword"):
			node["keyword"] = str(attrs["keyword"])
		if attrs.has("entry_id"):
			node["entry_id"] = str(attrs["entry_id"])
		if attrs.has("disabled"):
			node["disabled"] = true
		if attrs.has("checked"):
			node["checked"] = true
		if attrs.has("wrap"):
			node["wrap"] = true
		if attrs.has("nowrap"):
			node["nowrap"] = true
		for key in attrs.keys():
			if key in ["size", "color", "bg_color", "action", "url", "action_id", "keyword", "entry_id", "disabled", "checked", "wrap", "nowrap", "_positional"]:
				continue
			node[key] = attrs[key]
		return {"node": node, "end_pos": pos}

	# ── 容器标签（vbox, hbox, panel, margin）──
	if tag_name in CONTAINER_TYPES:
		var children := _parse_children(text, pos, tag_name)
		# 跳过关闭标签
		var close_pos := _find_close_tag(text, pos, tag_name)
		if close_pos >= 0:
			pos = _skip_close_tag(text, close_pos, tag_name)
		else:
			pos = length

		var node: Dictionary = {"type": tag_name}

		match tag_name:
			"vbox", "hbox":
				node["children"] = children
				if attrs.has("sep"):
					node["separation"] = int(str(attrs["sep"]))
				if attrs.has("width"):
					node["width"] = int(str(attrs["width"]))
				if attrs.has("fill"):
					node["fill"] = true
				if attrs.has("bg"):
					node["bg_color"] = str(attrs["bg"])
			"panel", "panelcontainer":
				if attrs.has("bg"):
					node["bg_color"] = str(attrs["bg"])
				if attrs.has("border"):
					node["border_color"] = str(attrs["border"])
				if attrs.has("fill"):
					node["fill"] = true
				if attrs.has("shrink"):
					node["shrink"] = true
				if attrs.has("width"):
					node["width"] = int(str(attrs["width"]))
				if attrs.has("height"):
					node["height"] = int(str(attrs["height"]))
				if attrs.has("corner_radius"):
					node["corner_radius"] = int(str(attrs["corner_radius"]))
				if children.size() == 1:
					node["child"] = children[0]
				elif children.size() > 1:
					node["child"] = {"type": "vbox", "children": children}
			"margin", "margincontainer":
				var m := 0
				if attrs.has("_positional"):
					m = int(str(attrs["_positional"]))
				node["margin"] = m
				if children.size() == 1:
					node["child"] = children[0]
				elif children.size() > 1:
					node["child"] = {"type": "vbox", "children": children}

		return {"node": node, "end_pos": pos}

	# 未知标签 → 当作容器尝试
	var unk_children := _parse_children(text, pos, tag_name)
	var unk_close_pos := _find_close_tag(text, pos, tag_name)
	if unk_close_pos >= 0:
		pos = _skip_close_tag(text, unk_close_pos, tag_name)
	else:
		pos = length
	if unk_children.is_empty():
		return {"node": {"type": "label", "text": "[未知: %s]" % tag_name}, "end_pos": pos}
	if unk_children.size() == 1:
		return {"node": unk_children[0], "end_pos": pos}
	return {"node": {"type": "vbox", "children": unk_children}, "end_pos": pos}


# ── 工具函数 ──────────────────────────────────────────

static func _is_whitespace(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\n" or ch == "\r"


static func _starts_with_close_tag(text: String, pos: int, tag_name: String) -> bool:
	var close := "</" + tag_name + ">"
	if pos + close.length() > text.length():
		return false
	return text.substr(pos, close.length()).to_lower() == close


static func _skip_close_tag(_text: String, pos: int, tag_name: String) -> int:
	return pos + 2 + tag_name.length() + 1  # </tag_name>


static func _find_close_tag(text: String, from: int, tag_name: String) -> int:
	# 查找匹配的关闭标签（处理同名嵌套）
	var open_tag := "<" + tag_name
	var close_tag := "</" + tag_name + ">"
	var depth := 1
	var pos := from
	var length := text.length()

	while pos < length:
		var next_open := _find_ci(text, open_tag, pos)
		var next_close := _find_ci(text, close_tag, pos)

		if next_close == -1:
			return -1  # 没有关闭标签

		if next_open >= 0 and next_open < next_close:
			# 检查是否真的是开标签（后面跟 空格 > / ）
			var after := next_open + open_tag.length()
			if after < length and (text[after] == " " or text[after] == ">" or text[after] == "/" or text[after] == "\n" or text[after] == "\t"):
				depth += 1
			pos = next_open + 1
		else:
			depth -= 1
			if depth == 0:
				return next_close
			pos = next_close + 1

	return -1


static func _find_ci(text: String, pattern: String, from: int) -> int:
	# 大小写不敏感查找
	var lower_text := text.to_lower()
	var lower_pattern := pattern.to_lower()
	return lower_text.find(lower_pattern, from)


static func _strip_fences(source: String) -> String:
	var s := source
	if s.begins_with("```"):
		var first_nl := s.find("\n")
		if first_nl >= 0:
			s = s.substr(first_nl + 1)
		else:
			return ""
	if s.ends_with("```"):
		s = s.substr(0, s.length() - 3)
	return s.strip_edges()


static func _parse_attrs(text: String) -> Dictionary:
	var result := {}
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return result

	var index := 0
	var length := trimmed.length()
	while index < length:
		while index < length and _is_whitespace(trimmed[index]):
			index += 1
		if index >= length:
			break

		var key_start := index
		while index < length and not _is_whitespace(trimmed[index]) and trimmed[index] != "=" and trimmed[index] != ":":
			index += 1
		var raw_key := trimmed.substr(key_start, index - key_start).strip_edges()
		if raw_key.is_empty():
			index += 1
			continue

		while index < length and _is_whitespace(trimmed[index]):
			index += 1

		var lower_key := raw_key.to_lower()
		if index < length and (trimmed[index] == "=" or trimmed[index] == ":"):
			index += 1
			while index < length and _is_whitespace(trimmed[index]):
				index += 1

			var value := ""
			if index < length and (trimmed[index] == "\"" or trimmed[index] == "'"):
				var quote := trimmed[index]
				index += 1
				var value_start := index
				while index < length and trimmed[index] != quote:
					index += 1
				value = trimmed.substr(value_start, index - value_start)
				if index < length and trimmed[index] == quote:
					index += 1
			else:
				var value_start := index
				while index < length and not _is_whitespace(trimmed[index]):
					index += 1
				value = trimmed.substr(value_start, index - value_start)
			result[lower_key] = value
			continue

		if raw_key.is_valid_int():
			result["_positional"] = int(raw_key)
		else:
			result[lower_key] = true
	return result


static func _clean_text(raw: String) -> String:
	# 去掉 HTML 标签
	var text := _strip_html_tags(raw)
	# 去掉首尾空白和换行，合并空白
	var lines := text.split("\n")
	var parts: Array = []
	for line in lines:
		var s := line.strip_edges()
		if not s.is_empty():
			parts.append(s)
	return " ".join(PackedStringArray(parts))


static func _clean_rich_content(raw: String) -> String:
	var text := raw
	# 将 HTML 标题标签转为 BBCode
	text = text.replace("<h1>", "\n[font_size=28][b]").replace("</h1>", "[/b][/font_size]\n")
	text = text.replace("<h2>", "\n[font_size=24][b]").replace("</h2>", "[/b][/font_size]\n")
	text = text.replace("<h3>", "\n[font_size=22][b]").replace("</h3>", "[/b][/font_size]\n")
	text = text.replace("<h4>", "\n[font_size=20][b]").replace("</h4>", "[/b][/font_size]\n")
	# 将 HTML 格式标签转为 BBCode
	text = text.replace("<b>", "[b]").replace("</b>", "[/b]")
	text = text.replace("<i>", "[i]").replace("</i>", "[/i]")
	text = text.replace("<u>", "[u]").replace("</u>", "[/u]")
	# 保留换行但去掉首尾空行和每行首尾多余空白
	var lines := text.split("\n")
	var result: Array = []
	for line in lines:
		result.append(line.strip_edges())
	# 去掉首尾空行
	while result.size() > 0 and str(result[0]) == "":
		result.remove_at(0)
	while result.size() > 0 and str(result[result.size() - 1]) == "":
		result.resize(result.size() - 1)
	return "\n".join(PackedStringArray(result))


static func _strip_html_tags(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("</?[a-zA-Z][^>]*>")
	return regex.sub(text, "", true)
