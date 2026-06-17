extends Node
## 端到端冒烟测试：把 PageMark 解析后通过 WebPageRenderer 渲染，确认新节点类型不崩溃。

const PageMarkParserClass = preload("res://scripts/apps/browser/page_mark_parser.gd")


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("\n=== PageMark + WebPageRenderer smoke tests ===\n")
	_test_render_bbc_header()
	_test_render_bilibili_grid()
	_test_render_tieba_post()
	_test_render_image_placeholder()
	_test_render_quote()
	_test_render_full_article()
	print("\n=== Smoke tests complete ===\n")


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS: %s" % label)
	else:
		print("  FAIL: %s  %s" % [label, detail])


func _render(page_mark_text: String) -> Control:
	var parsed: Dictionary = PageMarkParserClass.parse(page_mark_text)
	var tree: Dictionary = parsed.get("tree", {})
	return WebPageRenderer.render(tree, Callable())


# ── tests ──

func _test_render_bbc_header() -> void:
	print("[Render] BBC header")
	var src := """::: card bg=#BB1919 pad=12
::: row sep=20
[BBC](url:/)
::: col fill :::
[News](action:open url=/news)
[Sport](action:open url=/sport)
[Sign in](action:open url=/signin)
:::
:::"""
	var root := _render(src)
	_assert("non-null root", root != null)
	_assert("root is PanelContainer", root is PanelContainer)
	# Inside PanelContainer there should be a MarginContainer holding an HBoxContainer
	var margin := root.get_child(0) if root.get_child_count() > 0 else null
	_assert("inner is MarginContainer", margin is MarginContainer)
	var hbox: Node = margin.get_child(0) if margin != null and margin.get_child_count() > 0 else null
	_assert("inner content is HBoxContainer", hbox is HBoxContainer)
	# brand link + spacer col + 3 buttons = 5 children
	if hbox is HBoxContainer:
		_assert("hbox has 5 children", hbox.get_child_count() == 5, "got %d" % hbox.get_child_count())


func _test_render_bilibili_grid() -> void:
	print("[Render] Bilibili grid")
	var src := """::: grid cols=4 sep=14
::: col
::: card bg=#3FB4D9 height=140 pad=12 align=bottom
**水印A**
:::
**视频标题A**
UP主-A
:::
::: col
::: card bg=#FF6699 height=140 pad=12 align=bottom
**水印B**
:::
**视频标题B**
:::
:::"""
	var root := _render(src)
	_assert("non-null root", root != null)
	_assert("root is GridContainer", root is GridContainer)
	if root is GridContainer:
		_assert("4 columns", root.columns == 4)
		_assert("2 cards in grid", root.get_child_count() == 2)


func _test_render_tieba_post() -> void:
	print("[Render] Tieba post card")
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
	var root := _render(src)
	_assert("non-null root", root != null)
	_assert("root is PanelContainer", root is PanelContainer)


func _test_render_image_placeholder() -> void:
	print("[Render] image placeholder")
	var src := "![测试](image:src=res://nonexistent.png width=120 height=80)"
	var root := _render(src)
	_assert("non-null root", root != null)
	_assert("falls back to PanelContainer placeholder", root is PanelContainer)


func _test_render_quote() -> void:
	print("[Render] quote block")
	var src := "> 这是引用内容"
	var root := _render(src)
	_assert("non-null root", root != null)
	_assert("quote uses PanelContainer wrapper", root is PanelContainer)


func _test_render_full_article() -> void:
	print("[Render] full article (heading + paragraph + list + quote)")
	var src := """# 标题

这是 **第一** 段。

- 列表一
- 列表二

> 引用块

正文结尾。"""
	var root := _render(src)
	_assert("non-null root", root != null)
	# Five children: heading, paragraph, list, quote, paragraph
	if root is VBoxContainer:
		_assert("multi-child vbox", root.get_child_count() >= 4, "got %d" % root.get_child_count())
	else:
		_assert("root not vbox unexpectedly", false, "type: %s" % str(root.get_class() if root != null else "null"))
