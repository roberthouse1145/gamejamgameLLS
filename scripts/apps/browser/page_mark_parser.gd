class_name PageMarkParser
extends RefCounted
## Markdown-first page DSL parser. Produces a Dictionary tree for WebPageRenderer.
##
## Block fence syntax:
##   ::: row [attrs]      ... :::
##   ::: col [attrs]      ... :::
##   ::: card [attrs]     ... :::
##   ::: grid cols=N      ... :::
##   ::: form [attrs]     ... :::
##   ::: pdf [attrs]      ... :::
##   ::: document [attrs] ... :::
##   ::: table cols=N     ... :::
##   ::: cell [attrs]     ... :::
##   ::: section [attrs]  ... :::
##
## Line-level markdown:
##   # ## ### ####        headings -> label
##   - / 1.               list -> rich_text
##   >                    quote
##   ---                  separator
##   ![alt](image:src=..) image
##   [txt](url:..) standalone -> link node
##   [txt](action:..) standalone -> button node
##   blank line           paragraph break
##
## Inline markdown:
##   **emphasis**         -> plain text（网站统一使用常规字重）
##   *i*  ~~s~~           -> BBCode
##   [txt](color:#xx)     -> [color=#xx]txt[/color]
##   [txt](url:..)        -> [url=..]txt[/url]


const FENCE_TAGS: Array = [
	"row", "col", "card", "grid", "form",
	"pdf", "document", "table", "cell", "section",
]
const HEADING_SIZES: Dictionary = {1: 54, 2: 42, 3: 34, 4: 30}


static func parse(source: String) -> Dictionary:
	var stripped := _strip_fences(source.strip_edges())
	if stripped.is_empty():
		return {"tree": {}, "warnings": []}

	var lines: PackedStringArray = stripped.split("\n")
	var ctx: Dictionary = {
		"lines": lines,
		"pos": 0,
		"warnings": [],
	}
	var children: Array = _parse_block(ctx, "", 0)

	var tree: Dictionary
	if children.is_empty():
		tree = {}
	elif children.size() == 1:
		tree = children[0]
	else:
		tree = {"type": "vbox", "children": children}

	return {"tree": tree, "warnings": ctx["warnings"]}


# ── 主递归 ─────────────────────────────────────────────

static func _parse_block(ctx: Dictionary, expected_close: String, open_line: int) -> Array:
	var children: Array = []
	var paragraph_buf: Array = []
	var list_buf: Array = []
	var list_kind: String = ""
	var lines: PackedStringArray = ctx["lines"]

	while int(ctx["pos"]) < lines.size():
		var raw_line: String = lines[int(ctx["pos"])]
		var line_no: int = int(ctx["pos"]) + 1
		var line: String = raw_line.rstrip(" \t\r")
		var stripped: String = line.strip_edges()

		# anonymous fence close
		if stripped == ":::":
			_flush_list(children, list_buf, list_kind)
			list_buf = []
			list_kind = ""
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			ctx["pos"] = int(ctx["pos"]) + 1
			if expected_close.is_empty():
				continue
			return children

		# fence open (or inline self-closed)
		if stripped.begins_with(":::") and stripped != ":::":
			var fence: Dictionary = _parse_fence_open(stripped)
			if not fence.is_empty():
				_flush_list(children, list_buf, list_kind)
				list_buf = []
				list_kind = ""
				_flush_paragraph(children, paragraph_buf)
				paragraph_buf = []
				ctx["pos"] = int(ctx["pos"]) + 1
				if bool(fence.get("inline_close", false)):
					children.append(_make_container_node(fence["tag"], fence["attrs"], []))
				else:
					var sub: Array = _parse_block(ctx, fence["tag"], line_no)
					children.append(_make_container_node(fence["tag"], fence["attrs"], sub))
				continue
			# fall through: malformed fence treated as paragraph

		# blank line: paragraph break
		if stripped.is_empty():
			_flush_list(children, list_buf, list_kind)
			list_buf = []
			list_kind = ""
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# list item
		var list_match: Dictionary = _match_list_item(stripped)
		if not list_match.is_empty():
			var item_kind: String = list_match["kind"]
			if list_kind != "" and list_kind != item_kind:
				_flush_list(children, list_buf, list_kind)
				list_buf = []
			list_kind = item_kind
			list_buf.append(list_match["text"])
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# any non-list line: flush list buffer
		if not list_buf.is_empty():
			_flush_list(children, list_buf, list_kind)
			list_buf = []
			list_kind = ""

		# heading
		var heading: Dictionary = _match_heading(stripped)
		if not heading.is_empty():
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			children.append(heading)
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# separator
		if stripped == "---":
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			children.append({"type": "separator"})
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# quote
		if stripped.begins_with("> "):
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			children.append(_make_quote_node(stripped.substr(2).strip_edges()))
			ctx["pos"] = int(ctx["pos"]) + 1
			continue
		if stripped == ">":
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			children.append(_make_quote_node(""))
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# image (standalone)
		var image_node: Dictionary = _match_image(stripped)
		if not image_node.is_empty():
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			children.append(image_node)
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# block-level link/button (standalone)
		var block_link: Dictionary = _match_block_link(stripped)
		if not block_link.is_empty():
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []
			children.append(block_link)
			ctx["pos"] = int(ctx["pos"]) + 1
			continue

		# input/select shorthand inside form
		if expected_close == "form":
			var field_node: Dictionary = _match_form_field(stripped)
			if not field_node.is_empty():
				_flush_paragraph(children, paragraph_buf)
				paragraph_buf = []
				children.append(field_node)
				ctx["pos"] = int(ctx["pos"]) + 1
				continue

		# regular paragraph line
		paragraph_buf.append(_apply_inline(stripped))
		ctx["pos"] = int(ctx["pos"]) + 1
		if expected_close == "row":
			_flush_paragraph(children, paragraph_buf)
			paragraph_buf = []

	# EOF
	_flush_list(children, list_buf, list_kind)
	_flush_paragraph(children, paragraph_buf)
	if not expected_close.is_empty():
		ctx["warnings"].append("unclosed ::: %s opened at line %d" % [expected_close, open_line])
	return children


# ── 行级匹配 ──────────────────────────────────────────

static func _match_heading(line: String) -> Dictionary:
	var level := 0
	while level < line.length() and level < 4 and line[level] == "#":
		level += 1
	if level == 0 or level >= line.length() or line[level] != " ":
		return {}
	var text: String = line.substr(level + 1).strip_edges()
	if text.is_empty():
		return {}
	var size: int = HEADING_SIZES.get(level, 20)
	# Headings rely on font size hierarchy alone (no [b] wrap). Godot's bold font
	# variant for CJK looks visibly worse than plain weight at large sizes.
	return {
		"type": "rich_text",
		"bbcode": _apply_inline(text),
		"font_size": size,
	}


static func _match_list_item(line: String) -> Dictionary:
	if line.begins_with("- ") or line.begins_with("• "):
		return {"kind": "ul", "text": line.substr(2).strip_edges()}
	# ordered: "1. ", "2. ", ...
	var dot := line.find(". ")
	if dot > 0 and dot <= 3:
		var prefix: String = line.substr(0, dot)
		if prefix.is_valid_int():
			return {"kind": "ol", "text": line.substr(dot + 2).strip_edges()}
	return {}


static func _match_image(line: String) -> Dictionary:
	# ![alt](image:src=URL height=120 width=200)
	if not line.begins_with("!["):
		return {}
	var close_bracket := line.find("](")
	if close_bracket < 0:
		return {}
	var paren_open := close_bracket + 2
	if not line.substr(paren_open).begins_with("image:"):
		return {}
	if not line.ends_with(")"):
		return {}
	var alt: String = line.substr(2, close_bracket - 2)
	var attrs_text: String = line.substr(paren_open + 6, line.length() - paren_open - 6 - 1)
	var attrs: Dictionary = _parse_attrs(attrs_text)
	var node: Dictionary = {"type": "image", "alt": alt}
	if attrs.has("src"):
		node["src"] = str(attrs["src"])
	if attrs.has("width"):
		node["width"] = int(str(attrs["width"]))
	if attrs.has("height"):
		node["height"] = int(str(attrs["height"]))
	return node


static func _match_block_link(line: String) -> Dictionary:
	# Whole line is exactly one [txt](url:..) or [txt](action:..) link
	if not line.begins_with("["):
		return {}
	if not line.ends_with(")"):
		return {}
	var close_bracket := line.find("](")
	if close_bracket < 0:
		return {}
	var paren_open := close_bracket + 2
	var inner: String = line.substr(paren_open, line.length() - paren_open - 1)
	var text: String = line.substr(1, close_bracket - 1)
	if inner.begins_with("url:"):
		var rest: String = inner.substr(4).strip_edges()
		# First whitespace splits URL value from optional attributes
		var space_idx: int = -1
		for i in range(rest.length()):
			var ch: String = rest[i]
			if ch == " " or ch == "\t":
				space_idx = i
				break
		var url_value: String
		var url_attrs: Dictionary = {}
		if space_idx < 0:
			url_value = rest
		else:
			url_value = rest.substr(0, space_idx)
			url_attrs = _parse_attrs(rest.substr(space_idx + 1))
		var node: Dictionary = {
			"type": "link",
			"text": _strip_inline_markup(text),
			"url": url_value,
			"action": "open_url",
		}
		for key in url_attrs.keys():
			node[key] = url_attrs[key]
		if url_attrs.has("size"):
			node["font_size"] = int(str(url_attrs["size"]))
		return node
	if inner.begins_with("action:"):
		var rest: String = inner.substr(7).strip_edges()
		var action_attrs: Dictionary = _parse_attrs_with_first_positional(rest)
		var node: Dictionary = {
			"type": "button",
			"text": _strip_inline_markup(text),
			"action": str(action_attrs.get("_action", "")),
		}
		for key in action_attrs.keys():
			if key == "_action":
				continue
			node[key] = action_attrs[key]
		return node
	return {}


static func _match_form_field(line: String) -> Dictionary:
	# input field=username placeholder=用户名 required
	# select field=gender options=A|B|C
	# textarea field=note height=120
	var first_space := line.find(" ")
	var head: String
	var tail: String
	if first_space < 0:
		head = line
		tail = ""
	else:
		head = line.substr(0, first_space)
		tail = line.substr(first_space + 1)
	if not (head == "input" or head == "select" or head == "textarea" or head == "checkbox"):
		return {}
	var attrs: Dictionary = _parse_attrs(tail)
	var node: Dictionary = {"type": head}
	for key in attrs.keys():
		if key == "_positional":
			continue
		node[key] = attrs[key]
	if attrs.has("size"):
		node["font_size"] = int(str(attrs["size"]))
	return node


# ── Fence ─────────────────────────────────────────────

static func _parse_fence_open(line: String) -> Dictionary:
	# Line starts with ::: and is not equal to :::
	# Format: ::: tag [attrs] [:::]
	var rest: String = line.substr(3).strip_edges()
	var inline_close: bool = false
	if rest.ends_with(":::"):
		inline_close = true
		rest = rest.substr(0, rest.length() - 3).strip_edges()
	if rest.is_empty():
		return {}
	var first_space := rest.find(" ")
	var tag: String
	var attrs_text: String
	if first_space < 0:
		tag = rest
		attrs_text = ""
	else:
		tag = rest.substr(0, first_space)
		attrs_text = rest.substr(first_space + 1).strip_edges()
	tag = tag.to_lower()
	if not (tag in FENCE_TAGS):
		return {}
	var attrs: Dictionary = _parse_attrs(attrs_text)
	return {
		"tag": tag,
		"attrs": attrs,
		"inline_close": inline_close,
	}


static func _make_container_node(tag: String, attrs: Dictionary, children: Array) -> Dictionary:
	match tag:
		"row":
			var row_node: Dictionary = {"type": "hbox", "children": children}
			_apply_box_attrs(row_node, attrs)
			return row_node
		"col":
			var col_node: Dictionary = {"type": "vbox", "children": children}
			_apply_box_attrs(col_node, attrs)
			return col_node
		"card":
			var card_node: Dictionary = {"type": "panelcontainer"}
			_apply_card_attrs(card_node, attrs)
			if children.size() == 1:
				card_node["child"] = children[0]
			elif children.size() > 1:
				var card_body: Dictionary = {"type": "vbox", "children": children}
				if attrs.has("sep"):
					card_body["separation"] = int(str(attrs["sep"]))
				card_node["child"] = card_body
			else:
				card_node["child"] = {}
			if attrs.has("pad"):
				card_node["padding"] = int(str(attrs["pad"]))
			return card_node
		"grid":
			var grid_node: Dictionary = {"type": "grid", "children": children}
			if attrs.has("cols"):
				grid_node["columns"] = int(str(attrs["cols"]))
			else:
				grid_node["columns"] = 2
			if attrs.has("sep"):
				grid_node["separation"] = int(str(attrs["sep"]))
			if attrs.has("fill"):
				grid_node["fill"] = true
			if attrs.has("width"):
				grid_node["width"] = int(str(attrs["width"]))
			return grid_node
		"form":
			var form_node: Dictionary = {"type": "vbox", "children": children, "is_form": true}
			if attrs.has("action"):
				form_node["form_action"] = str(attrs["action"])
			if attrs.has("sep"):
				form_node["separation"] = int(str(attrs["sep"]))
			else:
				form_node["separation"] = 12
			form_node["fill"] = true
			return form_node
		"pdf":
			var pdf_node: Dictionary = {"type": "pdf_viewer", "children": children}
			for key: Variant in attrs.keys():
				pdf_node[str(key)] = attrs[key]
			return pdf_node
		"document":
			var document_node: Dictionary = {"type": "pdf_document"}
			if children.size() == 1:
				document_node["child"] = children[0]
			else:
				document_node["child"] = {"type": "vbox", "children": children, "separation": int(str(attrs.get("sep", 22)))}
			for key: Variant in attrs.keys():
				document_node[str(key)] = attrs[key]
			return document_node
		"table":
			var table_node: Dictionary = {
				"type": "table",
				"children": children,
				"columns": int(str(attrs.get("cols", 2))),
			}
			if attrs.has("width"):
				table_node["width"] = int(str(attrs["width"]))
			return table_node
		"cell":
			var cell_node: Dictionary = {"type": "table_cell"}
			if children.size() == 1:
				cell_node["child"] = children[0]
			else:
				cell_node["child"] = {"type": "vbox", "children": children, "separation": int(str(attrs.get("sep", 6)))}
			for key: Variant in attrs.keys():
				cell_node[str(key)] = attrs[key]
			return cell_node
		"section":
			var section_node: Dictionary = {"type": "web_section"}
			if children.size() == 1:
				section_node["child"] = children[0]
			else:
				section_node["child"] = {"type": "vbox", "children": children, "separation": int(str(attrs.get("sep", 18)))}
			for key: Variant in attrs.keys():
				section_node[str(key)] = attrs[key]
			return section_node
	return {"type": "vbox", "children": children}


static func _apply_box_attrs(node: Dictionary, attrs: Dictionary) -> void:
	if attrs.has("sep"):
		node["separation"] = int(str(attrs["sep"]))
	if attrs.has("fill"):
		node["fill"] = true
	if attrs.has("width"):
		node["width"] = int(str(attrs["width"]))
	if attrs.has("height"):
		node["height"] = int(str(attrs["height"]))
	if attrs.has("bg"):
		node["bg_color"] = str(attrs["bg"])
	if attrs.has("pad"):
		node["padding"] = int(str(attrs["pad"]))
	if attrs.has("align"):
		node["alignment"] = str(attrs["align"])


static func _apply_card_attrs(node: Dictionary, attrs: Dictionary) -> void:
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
	if attrs.has("align"):
		node["alignment"] = str(attrs["align"])
	if attrs.has("shadow"):
		node["shadow"] = str(attrs["shadow"])
	if attrs.has("border_width"):
		node["border_width"] = int(str(attrs["border_width"]))


# ── 缓冲区 flush ───────────────────────────────────────

static func _flush_paragraph(children: Array, buf: Array) -> void:
	if buf.is_empty():
		return
	var bbcode: String = "\n".join(PackedStringArray(buf))
	children.append({
		"type": "rich_text",
		"bbcode": bbcode,
		"font_size": 30,
	})


static func _flush_list(children: Array, buf: Array, kind: String) -> void:
	if buf.is_empty():
		return
	var lines: Array = []
	if kind == "ol":
		for i in range(buf.size()):
			lines.append("%d. %s" % [i + 1, _apply_inline(str(buf[i]))])
	else:
		for item in buf:
			lines.append("• %s" % _apply_inline(str(item)))
	children.append({
		"type": "rich_text",
		"bbcode": "\n".join(PackedStringArray(lines)),
		"font_size": 30,
	})


static func _make_quote_node(text: String) -> Dictionary:
	return {
		"type": "quote",
		"child": {
			"type": "rich_text",
			"bbcode": _apply_inline(text),
			"font_size": 27,
		},
	}


# ── inline markup ──────────────────────────────────────

static func _apply_inline(text: String) -> String:
	var out: String = text
	out = _replace_color_links(out)
	out = _replace_action_links(out)
	out = _replace_url_links(out)
	out = _replace_bold(out)
	out = _replace_italic(out)
	out = _replace_strike(out)
	return out


static func _replace_color_links(text: String) -> String:
	# Skip [/closing] tags: ensure first char inside [] is not '/'
	var regex := RegEx.new()
	regex.compile("\\[([^/\\]][^\\]]*)\\]\\(color:(#[0-9A-Fa-f]+)\\)")
	return regex.sub(text, "[color=$2]$1[/color]", true)


static func _replace_url_links(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[([^/\\]][^\\]]*)\\]\\(url:([^\\)]+)\\)")
	return regex.sub(text, "[url=$2]$1[/url]", true)


static func _replace_action_links(text: String) -> String:
	# inline action links inside paragraph: degrade to plain text + [url=action:..] BBCode
	var regex := RegEx.new()
	regex.compile("\\[([^/\\]][^\\]]*)\\]\\(action:([^\\)]+)\\)")
	return regex.sub(text, "[url=action:$2]$1[/url]", true)


static func _replace_bold(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\*\\*([^\\*]+)\\*\\*")
	return regex.sub(text, "$1", true)


static func _replace_italic(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?<!\\*)\\*([^\\*\\s][^\\*]*[^\\*\\s]|[^\\*\\s])\\*(?!\\*)")
	return regex.sub(text, "[i]$1[/i]", true)


static func _replace_strike(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("~~([^~]+)~~")
	return regex.sub(text, "[s]$1[/s]", true)


static func _strip_inline_markup(text: String) -> String:
	# For headings/labels: keep visible text, drop markdown wrapping
	var out: String = text
	var color_re := RegEx.new()
	color_re.compile("\\[([^\\]]+)\\]\\(color:#[0-9A-Fa-f]+\\)")
	out = color_re.sub(out, "$1", true)
	var url_re := RegEx.new()
	url_re.compile("\\[([^\\]]+)\\]\\([^\\)]+\\)")
	out = url_re.sub(out, "$1", true)
	out = out.replace("**", "").replace("~~", "")
	return out


# ── 通用工具 ───────────────────────────────────────────

static func _parse_attrs(text: String) -> Dictionary:
	var result: Dictionary = {}
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return result
	var index: int = 0
	var length: int = trimmed.length()
	while index < length:
		while index < length and _is_whitespace(trimmed[index]):
			index += 1
		if index >= length:
			break
		var key_start: int = index
		while index < length and not _is_whitespace(trimmed[index]) and trimmed[index] != "=":
			index += 1
		var raw_key: String = trimmed.substr(key_start, index - key_start).strip_edges()
		if raw_key.is_empty():
			index += 1
			continue
		var lower_key: String = raw_key.to_lower()
		if index < length and trimmed[index] == "=":
			index += 1
			var value: String = ""
			if index < length and (trimmed[index] == "\"" or trimmed[index] == "'"):
				var quote: String = trimmed[index]
				index += 1
				var v_start: int = index
				while index < length and trimmed[index] != quote:
					index += 1
				value = trimmed.substr(v_start, index - v_start)
				if index < length and trimmed[index] == quote:
					index += 1
			else:
				var v_start: int = index
				while index < length and not _is_whitespace(trimmed[index]):
					index += 1
				value = trimmed.substr(v_start, index - v_start)
			result[lower_key] = value
		else:
			result[lower_key] = true
	return result


static func _parse_attrs_with_first_positional(text: String) -> Dictionary:
	# For "[btn](action:open url=/x id=42)" — first token is the action verb
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return {"_action": ""}
	var first_space: int = trimmed.find(" ")
	if first_space < 0:
		return {"_action": trimmed}
	var verb: String = trimmed.substr(0, first_space)
	var rest: String = trimmed.substr(first_space + 1)
	var attrs: Dictionary = _parse_attrs(rest)
	attrs["_action"] = verb
	return attrs


static func _is_whitespace(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\n" or ch == "\r"


static func _strip_fences(source: String) -> String:
	var s: String = source
	if s.begins_with("```"):
		var first_nl: int = s.find("\n")
		if first_nl >= 0:
			s = s.substr(first_nl + 1)
		else:
			return ""
	if s.ends_with("```"):
		s = s.substr(0, s.length() - 3)
	return s.strip_edges()
