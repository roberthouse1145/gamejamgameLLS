extends Node

const PageMarkParserClass = preload("res://scripts/apps/browser/page_mark_parser.gd")


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("\n=== PageMarkParser tests ===\n")
	_test_heading()
	_test_paragraph_inline()
	_test_unordered_list()
	_test_ordered_list()
	_test_quote()
	_test_separator()
	_test_image_standalone()
	_test_block_link()
	_test_block_button_action()
	_test_inline_link_in_paragraph()
	_test_inline_empty_fence()
	_test_nested_row_col()
	_test_card_with_bg()
	_test_grid()
	_test_form_with_fields()
	_test_unclosed_fence_warning()
	_test_literal_special_chars()
	_test_strip_code_fences()
	_test_bbc_header_sample()
	_test_bilibili_sample()
	_test_tieba_sample()
	print("\n=== Parser tests complete ===")


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS: %s" % label)
	else:
		print("  FAIL: %s  %s" % [label, detail])


func _parse(src: String) -> Dictionary:
	return PageMarkParserClass.parse(src)


func _tree(src: String) -> Dictionary:
	return _parse(src).get("tree", {})


# ── Tests ──

func _test_heading() -> void:
	print("[Test] heading")
	var t := _tree("# Hello World")
	_assert("type=rich_text", t.get("type") == "rich_text")
	_assert("bbcode contains text", str(t.get("bbcode", "")).find("Hello World") >= 0)
	_assert("no bold wrap (size hierarchy only)", str(t.get("bbcode", "")).find("[b]") < 0)
	_assert("font_size=40", t.get("font_size") == 40)

	var t3 := _tree("### Section")
	_assert("h3 size=22", t3.get("font_size") == 22)


func _test_paragraph_inline() -> void:
	print("[Test] paragraph inline")
	var t := _tree("This is **bold** and *italic* and ~~strike~~.")
	_assert("type=rich_text", t.get("type") == "rich_text")
	var bb: String = t.get("bbcode", "")
	_assert("[b]bold[/b]", bb.find("[b]bold[/b]") >= 0)
	_assert("[i]italic[/i]", bb.find("[i]italic[/i]") >= 0)
	_assert("[s]strike[/s]", bb.find("[s]strike[/s]") >= 0)

	var t2 := _tree("Visit [our site](color:#0066CC) for more.")
	var bb2: String = t2.get("bbcode", "")
	_assert("color bbcode", bb2.find("[color=#0066CC]our site[/color]") >= 0)


func _test_unordered_list() -> void:
	print("[Test] ul")
	var src := "- 项目一\n- 项目二\n- 项目三"
	var t := _tree(src)
	_assert("type=rich_text", t.get("type") == "rich_text")
	var bb: String = t.get("bbcode", "")
	_assert("contains 项目一", bb.find("项目一") >= 0)
	_assert("bullet present", bb.find("•") >= 0)


func _test_ordered_list() -> void:
	print("[Test] ol")
	var src := "1. 第一\n2. 第二\n3. 第三"
	var t := _tree(src)
	var bb: String = t.get("bbcode", "")
	_assert("ordered numbered", bb.find("1. 第一") >= 0 and bb.find("2. 第二") >= 0)


func _test_quote() -> void:
	print("[Test] quote")
	var t := _tree("> 这是引用")
	_assert("type=quote", t.get("type") == "quote")
	var child: Dictionary = t.get("child", {})
	_assert("child rich_text", child.get("type") == "rich_text")
	_assert("child text", str(child.get("bbcode", "")).find("这是引用") >= 0)


func _test_separator() -> void:
	print("[Test] separator")
	var t := _tree("---")
	_assert("type=separator", t.get("type") == "separator")


func _test_image_standalone() -> void:
	print("[Test] image")
	var t := _tree("![logo](image:src=res://logo.png width=64 height=64)")
	_assert("type=image", t.get("type") == "image")
	_assert("src", t.get("src") == "res://logo.png")
	_assert("alt", t.get("alt") == "logo")
	_assert("width=64", t.get("width") == 64)
	_assert("height=64", t.get("height") == 64)


func _test_block_link() -> void:
	print("[Test] block link")
	var t := _tree("[News](url:/news)")
	_assert("type=link", t.get("type") == "link")
	_assert("text=News", t.get("text") == "News")
	_assert("url=/news", t.get("url") == "/news")


func _test_block_button_action() -> void:
	print("[Test] block button (action)")
	var t := _tree("[Submit](action:submit validate=true)")
	_assert("type=button", t.get("type") == "button")
	_assert("text=Submit", t.get("text") == "Submit")
	_assert("action=submit", t.get("action") == "submit")
	_assert("validate=true", str(t.get("validate", "")) == "true")


func _test_inline_link_in_paragraph() -> void:
	print("[Test] inline link in paragraph")
	var src := "Read more at [our blog](url:/blog) today."
	var t := _tree(src)
	_assert("type=rich_text", t.get("type") == "rich_text")
	var bb: String = t.get("bbcode", "")
	_assert("inline url bbcode", bb.find("[url=/blog]our blog[/url]") >= 0)


func _test_inline_empty_fence() -> void:
	print("[Test] inline empty fence")
	var src := "::: row\n[A](url:/a)\n::: col fill :::\n[B](url:/b)\n:::"
	var t := _tree(src)
	_assert("type=hbox", t.get("type") == "hbox")
	var children: Array = t.get("children", [])
	_assert("3 children", children.size() == 3)
	_assert("middle is empty col", children[1].get("type") == "vbox" and children[1].get("fill") == true)
	var middle_children: Array = children[1].get("children", [])
	_assert("middle has no children", middle_children.is_empty())


func _test_nested_row_col() -> void:
	print("[Test] nested row > col")
	var src := """::: row sep=20
::: col fill
# 主区
正文
:::
::: col width=200 bg=#f5f5f5
## 侧栏
- 项目
:::
:::"""
	var t := _tree(src)
	_assert("root hbox", t.get("type") == "hbox")
	_assert("sep=20", t.get("separation") == 20)
	var children: Array = t.get("children", [])
	_assert("2 cols", children.size() == 2)
	_assert("col0 vbox fill", children[0].get("type") == "vbox" and children[0].get("fill") == true)
	_assert("col1 width=200", children[1].get("width") == 200)
	_assert("col1 bg", children[1].get("bg_color") == "#f5f5f5")


func _test_card_with_bg() -> void:
	print("[Test] card with bg")
	var src := """::: card bg=#BB1919 pad=12
**logo**
:::"""
	var t := _tree(src)
	_assert("type=panelcontainer", t.get("type") == "panelcontainer")
	_assert("bg=#BB1919", t.get("bg_color") == "#BB1919")
	_assert("padding=12", t.get("padding") == 12)
	var child: Dictionary = t.get("child", {})
	_assert("child rich_text", child.get("type") == "rich_text")


func _test_grid() -> void:
	print("[Test] grid")
	var src := """::: grid cols=4 sep=14
::: col
A
:::
::: col
B
:::
:::"""
	var t := _tree(src)
	_assert("type=grid", t.get("type") == "grid")
	_assert("columns=4", t.get("columns") == 4)
	_assert("separation=14", t.get("separation") == 14)
	var children: Array = t.get("children", [])
	_assert("2 children", children.size() == 2)


func _test_form_with_fields() -> void:
	print("[Test] form with fields")
	var src := """::: form action=submit
input field=username placeholder=用户名 required
input field=password secret=true
[Login](action:submit)
:::"""
	var t := _tree(src)
	_assert("type=vbox (form)", t.get("type") == "vbox")
	_assert("is_form", t.get("is_form") == true)
	_assert("form_action=submit", t.get("form_action") == "submit")
	var children: Array = t.get("children", [])
	_assert("3 children", children.size() == 3, "got %d" % children.size())
	_assert("c0 input", children[0].get("type") == "input")
	_assert("c0 field=username", children[0].get("field") == "username")
	_assert("c1 input secret", children[1].get("type") == "input" and str(children[1].get("secret", "")) == "true")
	_assert("c2 button", children[2].get("type") == "button")


func _test_unclosed_fence_warning() -> void:
	print("[Test] unclosed fence warning")
	var src := "::: row\n[A](url:/a)\n[B](url:/b)"
	var result: Dictionary = _parse(src)
	var warnings: Array = result.get("warnings", [])
	_assert("has unclosed warning", warnings.size() > 0 and str(warnings[0]).find("unclosed") >= 0)


func _test_literal_special_chars() -> void:
	print("[Test] literal special chars (regression)")
	# This is the key regression: arbitrary characters in text must not break parser.
	var src := """这是一段正文，包含 "引号"、<尖括号>、{大括号} 和 'em quotes'。 还有 'apostrophe' s."""
	var t := _tree(src)
	_assert("type=rich_text", t.get("type") == "rich_text")
	var bb: String = t.get("bbcode", "")
	_assert("contains quote", bb.find("\"引号\"") >= 0)
	_assert("contains <>", bb.find("<尖括号>") >= 0)
	_assert("contains {}", bb.find("{大括号}") >= 0)


func _test_strip_code_fences() -> void:
	print("[Test] strip ``` fences")
	var src := "```\n# 标题\n正文\n```"
	var t := _tree(src)
	_assert("strip works (top is vbox)", t.get("type") == "vbox" or t.get("type") == "label")


func _test_bbc_header_sample() -> void:
	print("[Test] BBC header sample")
	var src := """::: card bg=#BB1919 pad=12
::: row sep=20
[BBC](url:/)
::: col fill :::
[News](action:open url=/news)
[Sport](action:open url=/sport)
[Sign in](action:open url=/signin)
:::
:::"""
	var result: Dictionary = _parse(src)
	var t: Dictionary = result.get("tree", {})
	var warnings: Array = result.get("warnings", [])
	_assert("no warnings", warnings.is_empty(), "warnings: %s" % str(warnings))
	_assert("root panelcontainer", t.get("type") == "panelcontainer")
	_assert("root bg red", t.get("bg_color") == "#BB1919")
	var child: Dictionary = t.get("child", {})
	_assert("child hbox", child.get("type") == "hbox")
	var row_children: Array = child.get("children", [])
	_assert("row has 5 children (1 brand + 1 spacer + 3 buttons)", row_children.size() == 5, "got %d" % row_children.size())
	_assert("c0 link BBC", row_children[0].get("type") == "link" and row_children[0].get("text") == "BBC")
	_assert("c1 empty fill col", row_children[1].get("type") == "vbox" and row_children[1].get("fill") == true)
	_assert("c2 button News", row_children[2].get("type") == "button" and row_children[2].get("text") == "News")
	_assert("c4 button Sign in", row_children[4].get("type") == "button" and row_children[4].get("text") == "Sign in")


func _test_bilibili_sample() -> void:
	print("[Test] Bilibili grid sample")
	var src := """::: grid cols=4 sep=14
::: col
::: card bg=#3FB4D9 height=140 pad=12
**水印A**
:::
**视频标题A**
UP主-A
:::
::: col
::: card bg=#FF6699 height=140 pad=12
**水印B**
:::
**视频标题B**
UP主-B
:::
:::"""
	var result: Dictionary = _parse(src)
	var t: Dictionary = result.get("tree", {})
	var warnings: Array = result.get("warnings", [])
	_assert("no warnings", warnings.is_empty(), "warnings: %s" % str(warnings))
	_assert("grid root", t.get("type") == "grid")
	_assert("4 cols", t.get("columns") == 4)
	var children: Array = t.get("children", [])
	_assert("2 cards in grid", children.size() == 2)


func _test_tieba_sample() -> void:
	print("[Test] Tieba forum post sample")
	var src := """::: card bg=#fff
::: row sep=12
::: col width=80
**用户A**
:::
::: col fill
::: row
::: col fill :::
1L · 14:30
:::
正文段落。
:::
:::
:::"""
	var result: Dictionary = _parse(src)
	var t: Dictionary = result.get("tree", {})
	var warnings: Array = result.get("warnings", [])
	_assert("no warnings", warnings.is_empty(), "warnings: %s" % str(warnings))
	_assert("root card", t.get("type") == "panelcontainer")
	var inner: Dictionary = t.get("child", {})
	_assert("inner row", inner.get("type") == "hbox")
	var inner_children: Array = inner.get("children", [])
	_assert("2 cols (avatar + body)", inner_children.size() == 2)
	_assert("col0 width=80", inner_children[0].get("width") == 80)
	_assert("col1 fill", inner_children[1].get("fill") == true)
