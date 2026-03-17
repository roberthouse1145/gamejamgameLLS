extends Node


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("\n=== DslPageParser tests ===\n")
	_test_simple_label()
	_test_nested_vbox()
	_test_rich_multiline()
	_test_self_closing()
	_test_panel_with_fill()
	_test_panelcontainer_defaults()
	_test_hbox_layout()
	_test_full_page()
	_test_markdown_fence()
	_test_vbox_width_fill_bg()
	_test_spacer_width_height()
	_test_label_align()
	_test_label_nowrap()
	_test_link_nowrap()
	_test_panel_width()
	_test_margincontainer_alias()
	_test_html_in_label()
	_test_html_in_rich()
	_test_color_colon_syntax()
	print("\n=== Parser tests complete ===")


func _assert(assert_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS: %s" % assert_name)
	else:
		print("  FAIL: %s  %s" % [assert_name, detail])


func _test_simple_label() -> void:
	print("[Test] simple label")
	var result := DslPageParser.parse("<label size=24>Hello World</label>")
	_assert("type=label", result.get("type") == "label")
	_assert("text=Hello World", result.get("text") == "Hello World")
	_assert("font_size=24", result.get("font_size") == 24)


func _test_nested_vbox() -> void:
	print("[Test] nested vbox")
	var dsl := """
<vbox>
  <label size=28>Title</label>
  <label>Body</label>
</vbox>"""
	var result := DslPageParser.parse(dsl)
	_assert("type=vbox", result.get("type") == "vbox")
	var children: Array = result.get("children", [])
	_assert("children=2", children.size() == 2)
	_assert("child0 text=Title", children[0].get("text") == "Title")
	_assert("child1 text=Body", children[1].get("text") == "Body")


func _test_rich_multiline() -> void:
	print("[Test] rich multiline")
	var dsl := """
<rich>
First paragraph.

Second paragraph with [color=#0066CC]link[/color].
</rich>"""
	var result := DslPageParser.parse(dsl)
	_assert("type=rich_text", result.get("type") == "rich_text")
	var bbcode: String = result.get("bbcode", "")
	_assert("contains first paragraph", bbcode.find("First paragraph.") >= 0)
	_assert("contains second paragraph", bbcode.find("Second paragraph") >= 0)
	_assert("preserve blank line", bbcode.find("\n\n") >= 0)
	_assert("preserve bbcode", bbcode.find("[color=#0066CC]") >= 0)


func _test_self_closing() -> void:
	print("[Test] self closing tags")
	var dsl := """
<vbox>
  <spacer 20/>
  <hr/>
  <spacer 10/>
</vbox>"""
	var result := DslPageParser.parse(dsl)
	var children: Array = result.get("children", [])
	_assert("children=3", children.size() == 3)
	_assert("spacer height=20", children[0].get("height") == 20)
	_assert("separator", children[1].get("type") == "separator")
	_assert("spacer height=10", children[2].get("height") == 10)


func _test_panel_with_fill() -> void:
	print("[Test] panel fill")
	var dsl := """<panel bg=#f0f0f0 fill><label>Content</label></panel>"""
	var result := DslPageParser.parse(dsl)
	_assert("type=panel", result.get("type") == "panel")
	_assert("bg_color=#f0f0f0", result.get("bg_color") == "#f0f0f0")
	_assert("fill=true", result.get("fill") == true)
	_assert("child type=label", result.get("child", {}).get("type") == "label")


func _test_panelcontainer_defaults() -> void:
	print("[Test] panelcontainer default")
	var dsl := """<panelcontainer bg=#f0f0f0><label>Content</label></panelcontainer>"""
	var result := DslPageParser.parse(dsl)
	_assert("type=panelcontainer", result.get("type") == "panelcontainer")
	_assert("bg_color=#f0f0f0", result.get("bg_color") == "#f0f0f0")
	_assert("child type=label", result.get("child", {}).get("type") == "label")


func _test_hbox_layout() -> void:
	print("[Test] hbox layout")
	var dsl := """
<hbox>
  <label>Left</label>
  <label>Right</label>
</hbox>"""
	var result := DslPageParser.parse(dsl)
	_assert("type=hbox", result.get("type") == "hbox")
	var children: Array = result.get("children", [])
	_assert("children=2", children.size() == 2)


func _test_full_page() -> void:
	print("[Test] full page")
	var dsl := """
<vbox>
  <panel bg=#f8f8f8>
    <hbox>
      <label size=18 color=#2e69cc>Header</label>
      <spacer 20/>
      <label size=12 color=#666>Home Explore</label>
    </hbox>
  </panel>
  <hr/>
  <label size=30>Love</label>
  <rich>
Main text paragraph one.

## Section
More content here.
  </rich>
  <spacer 15/>
  <panel bg=#f5f5f5>
    <label size=14>Quote</label>
  </panel>
</vbox>"""
	var result := DslPageParser.parse(dsl)
	_assert("type=vbox", result.get("type") == "vbox")
	var children: Array = result.get("children", [])
	_assert("children>=5", children.size() >= 5)
	_assert("child0=panel", children[0].get("type") == "panel")
	_assert("panel bg", children[0].get("bg_color") == "#f8f8f8")
	_assert("child1=separator", children[1].get("type") == "separator")
	_assert("child2=label Love", children[2].get("text") == "Love")
	_assert("child3=rich_text", children[3].get("type") == "rich_text")
	var bbcode: String = children[3].get("bbcode", "")
	_assert("rich contains content", bbcode.find("Main text paragraph one.") >= 0)


func _test_markdown_fence() -> void:
	print("[Test] markdown fence")
	var dsl := "```html\n<label>Test</label>\n```"
	var result := DslPageParser.parse(dsl)
	_assert("type=label", result.get("type") == "label")
	_assert("text=Test", result.get("text") == "Test")


func _test_vbox_width_fill_bg() -> void:
	print("[Test] vbox width/fill/bg")
	var dsl := '<vbox width=200 bg=#f8f9fa fill><label>Sidebar</label></vbox>'
	var result := DslPageParser.parse(dsl)
	_assert("type=vbox", result.get("type") == "vbox")
	_assert("width=200", result.get("width") == 200)
	_assert("fill=true", result.get("fill") == true)
	_assert("bg_color=#f8f9fa", result.get("bg_color") == "#f8f9fa")

	var dsl2 := '<vbox width=300><label>Fixed Width</label></vbox>'
	var r2 := DslPageParser.parse(dsl2)
	_assert("width=300", r2.get("width") == 300)
	_assert("no fill", not r2.has("fill"))


func _test_spacer_width_height() -> void:
	print("[Test] spacer width and height")
	var dsl := "<vbox><spacer 25/></vbox>"
	var result := DslPageParser.parse(dsl)
	var children: Array = result.get("children", [])
	_assert("spacer width=25", children[0].get("width") == 25)
	_assert("spacer height=25", children[0].get("height") == 25)


func _test_label_align() -> void:
	print("[Test] label align")
	var dsl := '<label size=16 align=center>Centered</label>'
	var result := DslPageParser.parse(dsl)
	_assert("align=center", result.get("align") == "center")


func _test_label_nowrap() -> void:
	print("[Test] label nowrap")
	var dsl := '<label size=10 nowrap>ANNOUNCEMENT</label>'
	var result := DslPageParser.parse(dsl)
	_assert("nowrap=true", result.get("nowrap") == true)


func _test_link_nowrap() -> void:
	print("[Test] link nowrap")
	var dsl := '<link size=11 nowrap action=open_url url=gamejam://signup>立即报名</link>'
	var result := DslPageParser.parse(dsl)
	_assert("type=link", result.get("type") == "link")
	_assert("nowrap=true", result.get("nowrap") == true)
	_assert("url=gamejam://signup", result.get("url") == "gamejam://signup")


func _test_panel_width() -> void:
	print("[Test] panel width")
	var dsl := '<panel bg=#f8f9fa width=260><label>Info Card</label></panel>'
	var result := DslPageParser.parse(dsl)
	_assert("type=panel", result.get("type") == "panel")
	_assert("width=260", result.get("width") == 260)


func _test_margincontainer_alias() -> void:
	print("[Test] margincontainer alias")
	var dsl := '<margincontainer 18><label>Content</label></margincontainer>'
	var result := DslPageParser.parse(dsl)
	_assert("type=margincontainer", result.get("type") == "margincontainer")
	_assert("margin=18", result.get("margin") == 18)
	_assert("child type=label", result.get("child", {}).get("type") == "label")


func _test_html_in_label() -> void:
	print("[Test] html stripped in label")
	var dsl := "<label size=14><b>Name</b>: Love</label>"
	var result := DslPageParser.parse(dsl)
	_assert("no html tag", result.get("text", "").find("<b>") == -1)
	_assert("keep text", result.get("text", "").find("Name") >= 0)
	_assert("keep content", result.get("text", "").find("Love") >= 0)


func _test_html_in_rich() -> void:
	print("[Test] html converted in rich")
	var dsl := "<rich><h3>Title</h3>Body<b>Bold</b></rich>"
	var result := DslPageParser.parse(dsl)
	var bbcode: String = result.get("bbcode", "")
	_assert("h3 converted", bbcode.find("[font_size=22]") >= 0)
	_assert("b converted", bbcode.find("[b]Bold[/b]") >= 0)
	_assert("no raw h3", bbcode.find("<h3>") == -1)


func _test_color_colon_syntax() -> void:
	print("[Test] color colon syntax")
	var dsl := '<label size=14 color:#666666>Gray text</label>'
	var result := DslPageParser.parse(dsl)
	_assert("color=#666666", result.get("color") == "#666666")
