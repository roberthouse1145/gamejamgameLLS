class_name BrowserApp
extends Control

const BrowserTabDataClass = preload("res://scripts/apps/browser/browser_tab_data.gd")
const BrowserThemeClass = preload("res://scripts/apps/browser/browser_theme.gd")
const WebPageRendererClass = preload("res://scripts/apps/browser/web_page_renderer.gd")
const HOMEPAGE_RES_PATH: String = "res://resources/data/browser_pages/homepage.tres"

@onready var toolbar: PanelContainer = %ToolBar
@onready var address_display: LineEdit = %AddressDisplay
@onready var search_input: LineEdit = %SearchInput
@onready var search_button: Button = %SearchButton
@onready var tab_buttons: HBoxContainer = %TabButtons
@onready var new_tab_button: Button = %NewTabButton
@onready var content_scroll: ScrollContainer = %ContentScroll
@onready var content_root: VBoxContainer = %ContentRoot
@onready var status_label: Label = %StatusLabel

var _home_button: Button = null
var _history_button: Button = null

var _tabs: Array = []
var _tab_widgets: Dictionary = {}
var _request_to_tab: Dictionary = {}
var _current_tab_id: String = ""
var _tab_counter: int = 0


func _ready() -> void:
	_apply_theme()
	_connect_ui()
	_connect_browser_manager()
	_create_blank_tab()


func _apply_theme() -> void:
	# toolbar panel、nav buttons、address/search input、new_tab_button、status_bar —
	# 由 browser_light.tres Theme 提供，无需 override

	# Background ColorRect — Theme 管不到 ColorRect，保留
	if self.has_node("Background"):
		var bg: ColorRect = $Background
		bg.color = BrowserThemeClass.COLOR_BG

	# status_label font_color — Theme Label 已定义，无需 override
	# status_label font_size=20 与 Theme Label font_size=22 不同，保留
	if status_label:
		status_label.add_theme_font_size_override("font_size", 20)


func _make_flat_btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = border
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## 为所有动态创建的内容按钮统一设置字体颜色（防止 Godot 默认白色 hover/pressed/focus）
func _style_content_button(btn: Button) -> void:
	var T := BrowserThemeClass
	var ns := _make_flat_btn_style(T.COLOR_ACCENT, T.COLOR_ACCENT, 6)
	var hs := _make_flat_btn_style(Color("#3560D4"), Color("#3560D4"), 6)
	btn.add_theme_stylebox_override("normal", ns)
	btn.add_theme_stylebox_override("hover", hs)
	btn.add_theme_stylebox_override("pressed", hs)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 22)


func _connect_ui() -> void:
	if search_button:
		search_button.pressed.connect(_on_search_pressed)
		search_button.visible = false
	if search_input:
		search_input.text_submitted.connect(_on_search_submitted)
		search_input.visible = false
	if new_tab_button:
		new_tab_button.pressed.connect(_on_new_tab_pressed)

	# 在 NavRow 中添加主页和历史记录按钮
	var nav_row: HBoxContainer = address_display.get_parent() if address_display else null
	if nav_row:
		_home_button = Button.new()
		_home_button.text = "主页"
		_home_button.pressed.connect(_on_home_button_pressed)
		nav_row.add_child(_home_button)
		nav_row.move_child(_home_button, 0)

		_history_button = Button.new()
		_history_button.text = "历史"
		_history_button.pressed.connect(_on_history_button_pressed)
		nav_row.add_child(_history_button)


func _connect_browser_manager() -> void:
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		push_error("BrowserApp: BrowserManager autoload not found")
		return

	var on_search_completed := Callable(self, "_on_search_completed")
	if not bm.is_connected("search_completed", on_search_completed):
		bm.connect("search_completed", on_search_completed)

	var on_search_failed := Callable(self, "_on_search_failed")
	if not bm.is_connected("search_failed", on_search_failed):
		bm.connect("search_failed", on_search_failed)

	var on_page_generated := Callable(self, "_on_page_generated")
	if not bm.is_connected("page_generated", on_page_generated):
		bm.connect("page_generated", on_page_generated)

	var on_page_failed := Callable(self, "_on_page_failed")
	if not bm.is_connected("page_failed", on_page_failed):
		bm.connect("page_failed", on_page_failed)

	var on_url_open := Callable(self, "_on_url_open_requested")
	if not bm.is_connected("url_open_requested", on_url_open):
		bm.connect("url_open_requested", on_url_open)

	var on_history_updated := Callable(self, "_on_browser_history_updated")
	if not bm.is_connected("browser_history_updated", on_history_updated):
		bm.connect("browser_history_updated", on_history_updated)

func _create_blank_tab() -> void:
	var tab = BrowserTabDataClass.new()
	_tab_counter += 1
	tab.tab_id = "tab_%d" % _tab_counter
	tab.title = "新标签页"
	tab.state = BrowserTabDataClass.TabState.IDLE
	tab.title = "Browser"
	tab.display_url = "browser://home"
	_tabs.append(tab)
	_create_tab_widget(tab)
	_switch_tab(tab.tab_id)
	_render_tab(tab)


func _start_search(keyword: String, reuse_tab_id: String = "") -> void:
	var query: String = keyword.strip_edges()
	if query.is_empty():
		return

	var tab = null
	if not reuse_tab_id.is_empty():
		tab = _find_tab_by_id(reuse_tab_id)

	if tab == null:
		tab = BrowserTabDataClass.new()
		_tab_counter += 1
		tab.tab_id = "tab_%d" % _tab_counter
		_tabs.append(tab)
		_create_tab_widget(tab)

	tab.keyword = query
	tab.display_url = query
	tab.is_search_result = true
	tab.state = BrowserTabDataClass.TabState.LOADING
	tab.title = "[搜索] %s" % query
	tab.search_results = []
	tab.page_content = {}
	tab.error_message = ""
	_update_tab_title(tab)
	_switch_tab(tab.tab_id)
	_set_status("搜索中...")
	_render_loading(tab, "正在生成搜索结果...")

	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_set_tab_error(tab, "BrowserManager 不存在")
		return

	var request_id: String = bm.search(query)
	if request_id.is_empty():
		_set_tab_error(tab, "搜索请求创建失败")
		return
	_request_to_tab[request_id] = tab.tab_id
	tab.request_id = request_id


func _open_page(url: String, design_prompt: String = "", reuse_tab_id: String = "", page_context: String = "") -> void:
	var target_url: String = url.strip_edges()
	if target_url.is_empty():
		return

	var existing_tab = _find_page_tab_by_url(target_url)
	if existing_tab != null and existing_tab.tab_id != reuse_tab_id:
		_switch_tab(existing_tab.tab_id)
		match existing_tab.state:
			BrowserTabDataClass.TabState.LOADING:
				_set_status("该网页已在其他标签页加载中")
			BrowserTabDataClass.TabState.ERROR:
				_set_status("已切换到已有标签页（上次加载失败）")
			_:
				_set_status("已切换到已有标签页")
		return

	var tab = null
	if not reuse_tab_id.is_empty():
		tab = _find_tab_by_id(reuse_tab_id)

	if tab == null:
		tab = BrowserTabDataClass.new()
		_tab_counter += 1
		tab.tab_id = "tab_%d" % _tab_counter
		_tabs.append(tab)
		_create_tab_widget(tab)

	tab.display_url = target_url
	tab.design_prompt = design_prompt
	tab.is_search_result = false
	tab.state = BrowserTabDataClass.TabState.LOADING
	tab.title = target_url
	tab.search_results = []
	tab.page_content = {}
	tab.error_message = ""
	_update_tab_title(tab)
	_switch_tab(tab.tab_id)
	_set_status("网页生成中...")
	_render_loading(tab, "正在生成网页内容...")

	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_set_tab_error(tab, "BrowserManager 不存在")
		return

	var request_id: String = bm.open_page(target_url, design_prompt, page_context)
	if request_id.is_empty():
		_set_tab_error(tab, "网页请求创建失败")
		return
	_request_to_tab[request_id] = tab.tab_id
	tab.request_id = request_id


func _create_tab_widget(tab) -> void:
	if tab_buttons == null:
		return

	var T := BrowserThemeClass

	# 外层 PanelContainer 作为统一的标签背景
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(180, 0)
	var holder_style := StyleBoxFlat.new()
	holder_style.bg_color = T.COLOR_SURFACE
	holder_style.corner_radius_top_left = 6
	holder_style.corner_radius_top_right = 6
	holder_style.corner_radius_bottom_left = 0
	holder_style.corner_radius_bottom_right = 0
	holder_style.border_width_left = 1
	holder_style.border_width_top = 1
	holder_style.border_width_right = 1
	holder_style.border_width_bottom = 0
	holder_style.border_color = T.COLOR_BORDER
	holder.add_theme_stylebox_override("panel", holder_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	holder.add_child(row)

	var tab_btn := Button.new()
	tab_btn.text = tab.title
	tab_btn.clip_text = true
	tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_btn.pressed.connect(_on_tab_button_pressed.bind(tab.tab_id))
	# 按钮本身透明，背景由 holder 提供
	tab_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tab_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	tab_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	tab_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tab_btn.add_theme_color_override("font_color", T.COLOR_TEXT)
	tab_btn.add_theme_color_override("font_hover_color", T.COLOR_TEXT)
	tab_btn.add_theme_color_override("font_pressed_color", T.COLOR_TEXT)
	tab_btn.add_theme_color_override("font_focus_color", T.COLOR_TEXT)
	tab_btn.add_theme_color_override("font_hover_pressed_color", T.COLOR_TEXT)
	tab_btn.add_theme_font_size_override("font_size", 22)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(_on_tab_close_pressed.bind(tab.tab_id))
	close_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	close_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	close_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.add_theme_color_override("font_color", T.COLOR_TEXT_MUTED)
	close_btn.add_theme_color_override("font_hover_color", Color("#FF5F57"))
	close_btn.add_theme_color_override("font_pressed_color", Color("#FF5F57"))
	close_btn.add_theme_color_override("font_focus_color", T.COLOR_TEXT_MUTED)
	close_btn.add_theme_color_override("font_hover_pressed_color", Color("#FF5F57"))
	close_btn.add_theme_font_size_override("font_size", 22)

	row.add_child(tab_btn)
	row.add_child(close_btn)
	tab_buttons.add_child(holder)
	_tab_widgets[tab.tab_id] = {
		"holder": holder,
		"button": tab_btn,
	}


func _switch_tab(tab_id: String) -> void:
	_current_tab_id = tab_id
	for tab in _tabs:
		if tab.tab_id == tab_id:
			if address_display:
				address_display.text = tab.display_url
			_render_tab(tab)
			break
	_update_tab_focus_style()


func _update_tab_focus_style() -> void:
	var T := BrowserThemeClass
	for tab_id in _tab_widgets.keys():
		var widget: Dictionary = _tab_widgets[tab_id]
		var holder: PanelContainer = widget.get("holder")
		if holder == null:
			continue
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 0
		style.border_color = T.COLOR_BORDER
		if tab_id == _current_tab_id:
			style.bg_color = T.COLOR_SURFACE
		else:
			style.bg_color = T.COLOR_SURFACE_ALT
		holder.add_theme_stylebox_override("panel", style)


func _render_tab(tab: BrowserTabData) -> void:
	_clear_content_root()

	match tab.state:
		BrowserTabDataClass.TabState.LOADING:
			_render_loading(tab, "加载中...")
		BrowserTabDataClass.TabState.ERROR:
			_render_error(tab.error_message)
		BrowserTabDataClass.TabState.READY:
			if tab.is_search_result:
				_render_search_results(tab.search_results)
			else:
				_render_page(tab.page_content)
		_:
			_render_idle_placeholder()


func _render_loading(_tab, text: String) -> void:
	_clear_content_root()
	var loading := Label.new()
	loading.text = text
	loading.add_theme_color_override("font_color", BrowserThemeClass.COLOR_TEXT_DIM)
	loading.add_theme_font_size_override("font_size", 24)
	content_root.add_child(loading)


func _render_error(text: String) -> void:
	_clear_content_root()
	var label := Label.new()
	label.text = "加载失败: %s" % text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", BrowserThemeClass.COLOR_ERROR)
	label.add_theme_font_size_override("font_size", 24)
	content_root.add_child(label)


func _render_idle_placeholder() -> void:
	_render_home_page()
	var label := Label.new()
	label.text = "在顶部输入关键词开始搜索"


func _render_home_page() -> void:
	_clear_content_root()
	var res: WebPageResource = load(HOMEPAGE_RES_PATH) as WebPageResource
	if res == null or res.content.strip_edges().is_empty():
		_render_error("主页资源加载失败")
		return

	var page: Dictionary = DslPageParser.parse(res.content)
	if page.is_empty():
		_render_error("主页 DSL 解析失败")
		return
	var on_action := Callable(self, "_on_page_action")
	var rendered: Control = WebPageRendererClass.render(page, on_action, {"page_url": "browser://home"})
	content_root.add_child(rendered)


func _render_search_results(results: Array) -> void:
	_clear_content_root()
	if results.is_empty():
		var empty := Label.new()
		empty.text = "没有结果"
		empty.add_theme_color_override("font_color", BrowserThemeClass.COLOR_TEXT_DIM)
		content_root.add_child(empty)
		return

	for item in results:
		if not item is Dictionary:
			continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = BrowserThemeClass.COLOR_SURFACE
		card_style.corner_radius_top_left = 8
		card_style.corner_radius_top_right = 8
		card_style.corner_radius_bottom_left = 8
		card_style.corner_radius_bottom_right = 8
		card_style.border_width_left = 1
		card_style.border_width_top = 1
		card_style.border_width_right = 1
		card_style.border_width_bottom = 1
		card_style.border_color = BrowserThemeClass.COLOR_BORDER
		card.add_theme_stylebox_override("panel", card_style)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		card.add_child(margin)

		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		margin.add_child(body)

		# 标题作为超链接
		var item_url: String = str(item.get("url", "")).strip_edges()
		var item_design: String = str(item.get("design_prompt", "")).strip_edges()
		var item_title: String = str(item.get("title", "")).strip_edges()
		var item_hint: String = str(item.get("hint", "")).strip_edges()
		var page_context: String = item_title
		if not item_hint.is_empty():
			page_context += ("\n" if not page_context.is_empty() else "") + item_hint

		var title_link := RichTextLabel.new()
		title_link.bbcode_enabled = true
		title_link.fit_content = true
		title_link.scroll_active = false
		title_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_link.add_theme_font_size_override("normal_font_size", 24)
		var title_text: String = str(item.get("title", "无标题"))
		title_link.text = "[color=#4A7CFF][url=%s]%s[/url][/color]" % [item_url, title_text]
		title_link.meta_clicked.connect(_on_search_link_clicked.bind(item_url, item_design, page_context))
		body.add_child(title_link)

		var hint := Label.new()
		hint.text = str(item.get("hint", ""))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.add_theme_font_size_override("font_size", 20)
		hint.add_theme_color_override("font_color", BrowserThemeClass.COLOR_TEXT_DIM)
		body.add_child(hint)

		var url_label := Label.new()
		url_label.text = item_url
		url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		url_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		url_label.add_theme_font_size_override("font_size", 18)
		url_label.add_theme_color_override("font_color", BrowserThemeClass.COLOR_TEXT_MUTED)
		body.add_child(url_label)

		content_root.add_child(card)


func _render_page(page_content: Dictionary) -> void:
	_clear_content_root()
	if page_content.is_empty():
		_render_error("网页内容为空")
		return

	var current_url: String = ""
	var current = _find_tab_by_id(_current_tab_id)
	if current != null:
		current_url = current.display_url
	var scene_path: String = str(page_content.get("scene_path", "")).strip_edges()
	if not scene_path.is_empty():
		var scene_page: Control = _instantiate_scene_page(scene_path, page_content, current_url)
		if scene_page == null:
			_render_error("加载场景页面失败: %s" % scene_path)
			return
		content_root.add_child(scene_page)
		_configure_scene_page(scene_page, page_content, current_url)
		return

	var on_action := Callable(self, "_on_page_action")
	var rendered: Control = WebPageRendererClass.render(page_content, on_action, {"page_url": current_url})

	# content_root 已在 content_scroll 内，若渲染根节点也是 ScrollContainer
	# 会导致嵌套滚动容器、内层高度塌缩为 0 而显示空白，需解包
	if rendered is ScrollContainer and rendered.get_child_count() > 0:
		var inner: Control = rendered.get_child(0)
		rendered.remove_child(inner)
		rendered.queue_free()
		rendered = inner

	content_root.add_child(rendered)


func _instantiate_scene_page(scene_path: String, _page_content: Dictionary, _current_url: String) -> Control:
	if not ResourceLoader.exists(scene_path):
		push_warning("BrowserApp: scene page not found: %s" % scene_path)
		return null

	var scene_res: Resource = load(scene_path)
	if not scene_res is PackedScene:
		push_warning("BrowserApp: scene page is not a PackedScene: %s" % scene_path)
		return null

	var instance: Node = (scene_res as PackedScene).instantiate()
	if not instance is Control:
		push_warning("BrowserApp: scene page root must inherit Control: %s" % scene_path)
		if instance != null:
			instance.queue_free()
		return null

	var control := instance as Control
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return control


func _configure_scene_page(scene_page: Control, page_content: Dictionary, current_url: String) -> void:
	if scene_page == null or not is_instance_valid(scene_page):
		return
	if not scene_page.has_method("configure_browser_page"):
		return
	var page_context: Dictionary = page_content.duplicate(true)
	page_context["page_url"] = current_url
	scene_page.call_deferred("configure_browser_page", self, page_context)


func _clear_content_root() -> void:
	if content_root == null:
		return
	for child in content_root.get_children():
		child.queue_free()


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _set_tab_error(tab, message: String) -> void:
	tab.state = BrowserTabDataClass.TabState.ERROR
	tab.error_message = message
	_update_tab_title(tab)
	if tab.tab_id == _current_tab_id:
		_render_error(message)
		_set_status("失败")


func _update_tab_title(tab) -> void:
	if not _tab_widgets.has(tab.tab_id):
		return
	var widget: Dictionary = _tab_widgets[tab.tab_id]
	var button: Button = widget.get("button")
	if button:
		button.text = tab.title


func _find_tab_by_id(tab_id: String):
	for tab in _tabs:
		if tab.tab_id == tab_id:
			return tab
	return null


func _find_page_tab_by_url(url: String):
	for tab in _tabs:
		if tab.is_search_result:
			continue
		if tab.display_url == url:
			return tab
	return null


func _find_tab_by_request(request_id: String):
	if not _request_to_tab.has(request_id):
		return null
	var tab_id: String = _request_to_tab[request_id]
	return _find_tab_by_id(tab_id)


func _close_tab(tab_id: String) -> void:
	var tab = _find_tab_by_id(tab_id)
	if tab == null:
		return

	for i in range(_tabs.size()):
		if _tabs[i].tab_id == tab_id:
			_tabs.remove_at(i)
			break

	if _tab_widgets.has(tab_id):
		var holder: Control = _tab_widgets[tab_id].get("holder")
		if holder and is_instance_valid(holder):
			holder.queue_free()
		_tab_widgets.erase(tab_id)

	var remove_request_keys: Array = []
	for req_id in _request_to_tab.keys():
		if _request_to_tab[req_id] == tab_id:
			remove_request_keys.append(req_id)
	for req_id in remove_request_keys:
		_request_to_tab.erase(req_id)

	if _tabs.is_empty():
		_create_blank_tab()
		return

	if _current_tab_id == tab_id:
		_switch_tab(_tabs[0].tab_id)


func _on_search_pressed() -> void:
	_on_search_submitted(search_input.text if search_input else "")


func _on_search_submitted(text: String) -> void:
	var input_text: String = text.strip_edges()
	if input_text.is_empty():
		return

	# 如果当前标签页是空白页（IDLE），复用它
	var reuse_id: String = ""
	var current = _find_tab_by_id(_current_tab_id)
	if current != null and current.state == BrowserTabDataClass.TabState.IDLE:
		reuse_id = current.tab_id

	_start_search(input_text, reuse_id)


func _on_new_tab_pressed() -> void:
	_create_blank_tab()


func _on_tab_button_pressed(tab_id: String) -> void:
	_switch_tab(tab_id)


func _on_tab_close_pressed(tab_id: String) -> void:
	_close_tab(tab_id)


func _on_history_entry_pressed(entry_id: String) -> void:
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		return
	var entry: Dictionary = bm.get_history_entry(entry_id)
	if entry.is_empty():
		_set_status("历史记录不存在")
		return
	_open_page(str(entry.get("url", "")))
	_set_status("已打开历史网页")


func _on_browser_history_updated() -> void:
	var current = _find_tab_by_id(_current_tab_id)
	if current == null:
		return
	if current.state == BrowserTabDataClass.TabState.IDLE:
		_render_home_page()
	elif current.display_url == "browser://history":
		_render_history_page()


func _on_search_link_clicked(_meta: Variant, url: String, design_prompt: String, page_context: String = "") -> void:
	_open_page(url, design_prompt, "", page_context)


func _on_search_completed(request_id: String, keyword: String, results: Array) -> void:
	var tab = _find_tab_by_request(request_id)
	if tab == null:
		return
	_request_to_tab.erase(request_id)
	tab.state = BrowserTabDataClass.TabState.READY
	tab.keyword = keyword
	tab.search_results = results.duplicate(true)
	tab.title = "[搜索] %s" % keyword
	_update_tab_title(tab)
	if tab.tab_id == _current_tab_id:
		_render_search_results(tab.search_results)
		_set_status("搜索完成")


func _on_search_failed(request_id: String, _keyword: String, error: String) -> void:
	var tab = _find_tab_by_request(request_id)
	if tab == null:
		return
	_request_to_tab.erase(request_id)
	_set_tab_error(tab, error)


func _on_page_generated(request_id: String, url: String, content: Dictionary) -> void:
	var tab = _find_tab_by_request(request_id)
	if tab == null:
		return
	_request_to_tab.erase(request_id)
	tab.state = BrowserTabDataClass.TabState.READY
	tab.display_url = url
	tab.page_content = content.duplicate(true)
	tab.title = str(content.get("title", url))
	if tab.title.strip_edges().is_empty():
		tab.title = url
	_update_tab_title(tab)
	if tab.tab_id == _current_tab_id:
		if address_display:
			address_display.text = tab.display_url
		_render_page(tab.page_content)
		_set_status("网页已生成")


func _on_page_failed(request_id: String, _url: String, error: String) -> void:
	var tab = _find_tab_by_request(request_id)
	if tab == null:
		return
	_request_to_tab.erase(request_id)
	_set_tab_error(tab, error)


func _on_url_open_requested(url: String, design_prompt: String, page_context: String) -> void:
	_open_page(url, design_prompt, "", page_context)


# ── 统一页面动作路由 ──────────────────────────────────

func _on_page_action(action_data: Dictionary) -> void:
	var action: String = str(action_data.get("action", ""))
	match action:
		"open_url":
			_open_page(str(action_data.get("url", "")), str(action_data.get("design_prompt", "")))
		"perform_action":
			_set_status("互联网行动已经迁移到 Community 应用。")
		"search":
			_start_search(str(action_data.get("keyword", "")))
		"open_history":
			_on_history_entry_pressed(str(action_data.get("entry_id", "")))
		"open_history_page":
			_on_history_button_pressed()
		"submit_story_form":
			_submit_story_form(action_data)
		"story_event":
			_submit_story_event(action_data)
		"go_home":
			var current = _find_tab_by_id(_current_tab_id)
			if current != null:
				current.state = BrowserTabDataClass.TabState.IDLE
				current.display_url = "browser://home"
				_update_tab_title(current)
			_render_home_page()
		_:
			if not action.is_empty():
				push_warning("BrowserApp: 未知页面动作: %s" % action)


func _submit_story_form(action_data: Dictionary) -> void:
	var validation: Dictionary = action_data.get("__form_validation", {})
	if not validation.is_empty() and not bool(validation.get("is_valid", true)):
		var first_error: String = str(validation.get("first_error", "Invalid form input")).strip_edges()
		if first_error.is_empty():
			first_error = "Invalid form input"
		_set_status(first_error)
		return
	var payload: Dictionary = action_data.duplicate(true)
	payload["form_data"] = action_data.get("__form_data", {}).duplicate(true)
	_submit_story_event(payload)


func _submit_story_event(action_data: Dictionary) -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director == null:
		_set_status("StoryDirector missing")
		return

	var condition_type: String = str(action_data.get("story_condition", "variable_equals"))
	var payload: Dictionary = {}
	if action_data.has("form_data"):
		payload["form_data"] = action_data.get("form_data", {}).duplicate(true)

	var page_url: String = str(action_data.get("page_url", "")).strip_edges()
	if page_url.is_empty():
		var current = _find_tab_by_id(_current_tab_id)
		if current != null:
			page_url = current.display_url
	if not page_url.is_empty():
		payload["page_url"] = page_url

	var variables: Dictionary = {}
	var story_key: String = str(action_data.get("story_key", "")).strip_edges()
	if not story_key.is_empty():
		var story_value: Variant = _parse_story_value(action_data.get("story_value", true))
		payload["key"] = story_key
		payload["value"] = story_value
		variables[story_key] = story_value

	if story_director.has_method("submit_story_event"):
		story_director.submit_story_event(condition_type, payload, variables)
	else:
		story_director.notify_condition_met(condition_type, payload)
		for key in variables.keys():
			story_director.set_variable(str(key), variables[key])

	_set_status(str(action_data.get("success_status", "Story event submitted")))


func _parse_story_value(raw_value: Variant) -> Variant:
	if raw_value is String:
		var text: String = str(raw_value).strip_edges()
		if text == "true":
			return true
		if text == "false":
			return false
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return text.to_float()
	return raw_value


func _on_home_button_pressed() -> void:
	var current = _find_tab_by_id(_current_tab_id)
	if current != null:
		current.state = BrowserTabDataClass.TabState.IDLE
		current.display_url = "browser://home"
		current.title = "Browser"
		_update_tab_title(current)
		if address_display:
			address_display.text = "browser://home"
	_render_home_page()


func _on_history_button_pressed() -> void:
	_render_history_page()


func _render_history_page() -> void:
	_clear_content_root()
	var T := BrowserThemeClass
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_render_error("BrowserManager 不存在")
		return

	var current = _find_tab_by_id(_current_tab_id)
	if current != null:
		current.display_url = "browser://history"
		current.title = "浏览记录"
		_update_tab_title(current)
		if address_display:
			address_display.text = "browser://history"

	var history_entries: Array = bm.get_history_entries(30)

	# ── Header ──────────────────────────────────────────
	var header := PanelContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = T.COLOR_SURFACE
	header_style.border_width_bottom = 1
	header_style.border_color = T.COLOR_BORDER
	header_style.content_margin_left = 16
	header_style.content_margin_right = 16
	header_style.content_margin_top = 14
	header_style.content_margin_bottom = 14
	header.add_theme_stylebox_override("panel", header_style)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header.add_child(header_row)

	var header_title := Label.new()
	header_title.text = "浏览记录"
	header_title.add_theme_font_size_override("font_size", 20)
	header_title.add_theme_color_override("font_color", T.COLOR_TEXT)
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_title)

	var header_count := Label.new()
	header_count.text = "%d 条" % history_entries.size()
	header_count.add_theme_font_size_override("font_size", 13)
	header_count.add_theme_color_override("font_color", T.COLOR_TEXT_MUTED)
	header_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(header_count)

	content_root.add_child(header)

	# ── 条目列表 ─────────────────────────────────────────
	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.add_theme_constant_override("margin_right", 16)
	body_margin.add_theme_constant_override("margin_top", 10)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	content_root.add_child(body_margin)

	var body_vbox := VBoxContainer.new()
	body_vbox.add_theme_constant_override("separation", 0)
	body_margin.add_child(body_vbox)

	if history_entries.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无浏览记录"
		empty_lbl.add_theme_font_size_override("font_size", 15)
		empty_lbl.add_theme_color_override("font_color", T.COLOR_TEXT_DIM)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body_vbox.add_child(empty_lbl)

		var empty_sub := Label.new()
		empty_sub.text = "执行网络行动后，访问过的网页会出现在这里"
		empty_sub.add_theme_font_size_override("font_size", 13)
		empty_sub.add_theme_color_override("font_color", T.COLOR_TEXT_MUTED)
		empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body_vbox.add_child(empty_sub)
	else:
		var grouped: Dictionary = {}
		var day_order: Array = []
		for entry in history_entries:
			if not entry is Dictionary:
				continue
			var day_key: String = "Day %s" % str(entry.get("day", "?"))
			if not grouped.has(day_key):
				grouped[day_key] = []
				day_order.append(day_key)
			grouped[day_key].append(entry)

		for day_idx in range(day_order.size()):
			var day_key: String = day_order[day_idx]

			# 日期分组标题栏
			var day_bar := PanelContainer.new()
			day_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var day_style := StyleBoxFlat.new()
			day_style.bg_color = Color("#F2F3F7")
			day_style.content_margin_left = 10
			day_style.content_margin_right = 10
			day_style.content_margin_top = 6
			day_style.content_margin_bottom = 6
			if day_idx == 0:
				day_style.corner_radius_top_left = 6
				day_style.corner_radius_top_right = 6
			day_bar.add_theme_stylebox_override("panel", day_style)

			var day_lbl := Label.new()
			day_lbl.text = day_key
			day_lbl.add_theme_font_size_override("font_size", 13)
			day_lbl.add_theme_color_override("font_color", Color("#5A6580"))
			day_bar.add_child(day_lbl)
			body_vbox.add_child(day_bar)

			# 该日的条目
			var day_entries: Array = grouped[day_key]
			for idx in range(day_entries.size()):
				var entry: Dictionary = day_entries[idx]
				body_vbox.add_child(_build_history_item(entry))

	# ── Footer ────────────────────────────────────────────
	var footer_spacer := Control.new()
	footer_spacer.custom_minimum_size = Vector2(0, 8)
	body_vbox.add_child(footer_spacer)

	var footer := Label.new()
	footer.text = "仅显示最近 30 条记录"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", T.COLOR_TEXT_MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_vbox.add_child(footer)


## 构建单条历史记录行（简洁列表样式，底部分隔线）
func _build_history_item(entry: Dictionary) -> PanelContainer:
	var T := BrowserThemeClass
	var on_action := Callable(self, "_on_page_action")
	var entry_id: String = str(entry.get("entry_id", ""))
	var title: String = str(entry.get("title", "未命名网页")).strip_edges()
	var url: String = str(entry.get("url", "")).strip_edges()
	var summary: String = str(entry.get("summary", "")).strip_edges()
	var phase: String = str(entry.get("phase", "")).strip_edges()

	var item := PanelContainer.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item_style := StyleBoxFlat.new()
	item_style.bg_color = T.COLOR_SURFACE
	item_style.border_width_bottom = 1
	item_style.border_color = T.COLOR_BORDER
	item_style.content_margin_left = 10
	item_style.content_margin_right = 10
	item_style.content_margin_top = 8
	item_style.content_margin_bottom = 8
	item.add_theme_stylebox_override("panel", item_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	item.add_child(row)

	# 文字区
	var text_vbox := VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 2)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", T.COLOR_TEXT)
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.clip_text = true
	text_vbox.add_child(title_lbl)

	# 元信息行
	var meta_parts: PackedStringArray = []
	if not phase.is_empty():
		meta_parts.append(phase)
	if not summary.is_empty():
		meta_parts.append(summary)
	elif not url.is_empty():
		meta_parts.append(url)
	if not meta_parts.is_empty():
		var meta_lbl := Label.new()
		meta_lbl.text = " - ".join(meta_parts)
		meta_lbl.add_theme_font_size_override("font_size", 12)
		meta_lbl.add_theme_color_override("font_color", T.COLOR_TEXT_MUTED)
		meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		meta_lbl.clip_text = true
		text_vbox.add_child(meta_lbl)

	# 打开链接
	var open_btn := Button.new()
	open_btn.text = "打开"
	open_btn.flat = true
	open_btn.add_theme_font_size_override("font_size", 13)
	open_btn.add_theme_color_override("font_color", Color("#3D5AFE"))
	open_btn.add_theme_color_override("font_hover_color", Color("#3D5AFE"))
	open_btn.add_theme_color_override("font_pressed_color", Color("#3D5AFE"))
	open_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	open_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	open_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	open_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	open_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open_btn.pressed.connect(func(): on_action.call({"action": "open_history", "entry_id": entry_id}))
	row.add_child(open_btn)

	return item
