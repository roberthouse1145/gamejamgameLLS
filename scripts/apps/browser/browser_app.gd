class_name BrowserApp
extends Control

signal page_action_requested(action_data: Dictionary)

const BrowserTabDataClass = preload("res://scripts/apps/browser/browser_tab_data.gd")
const BrowserThemeClass = preload("res://scripts/apps/browser/browser_theme.gd")
const WebPageRendererClass = preload("res://scripts/apps/browser/web_page_renderer.gd")
const BrowserHomePageScene: PackedScene = preload("res://scenes/apps/browser/browser_home_page.tscn")

@onready var toolbar: PanelContainer = %ToolBar
@onready var address_display: LineEdit = %AddressDisplay
@onready var tab_buttons: HBoxContainer = %TabButtons
@onready var new_tab_button: Button = %NewTabButton
@onready var content_scroll: ScrollContainer = %ContentScroll
@onready var content_root: VBoxContainer = %ContentRoot
@onready var status_label: Label = %StatusLabel

var _home_button: Button = null
var _history_button: Button = null
var _loading_tween: Tween = null
var _loading_progress: ProgressBar = null
var _loading_dots_label: Label = null
var _loading_phase_label: Label = null
var _loading_phase_index: int = 0

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


## 供桌面剧情和其他 App 打开虚拟网页的稳定入口。
func navigate_to(url: String, design_prompt: String = "", page_context: String = "") -> void:
	_open_page(url, design_prompt, "", page_context)


func _apply_theme() -> void:
	# toolbar panel、nav buttons、address/search input、new_tab_button、status_bar —
	# 由 browser_light.tres Theme 提供，无需 override

	# Background ColorRect — Theme 管不到 ColorRect，保留
	if self.has_node("Background"):
		var bg: ColorRect = $Background
		bg.color = BrowserThemeClass.COLOR_BG

	# 状态栏比正文略小，但在 4K 桌面中仍需保持可读。
	if status_label:
		status_label.add_theme_font_size_override("font_size", 24)


func _make_flat_btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = border
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


## 为所有动态创建的内容按钮统一设置字体颜色（防止 Godot 默认白色 hover/pressed/focus）
func _style_content_button(btn: Button) -> void:
	var T := BrowserThemeClass
	var ns := _make_flat_btn_style(T.COLOR_ACCENT, T.COLOR_ACCENT, 14)
	var hs := _make_flat_btn_style(Color("#497FC8"), Color("#497FC8"), 14)
	btn.add_theme_stylebox_override("normal", ns)
	btn.add_theme_stylebox_override("hover", hs)
	btn.add_theme_stylebox_override("pressed", hs)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 30)


func _make_content_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.shadow_color = Color(0.1, 0.17, 0.28, 0.12)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	return style


func _connect_ui() -> void:
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

	var on_surf_started := Callable(self, "_on_surf_started")
	if not bm.is_connected("surf_started", on_surf_started):
		bm.connect("surf_started", on_surf_started)

	var on_surf_completed := Callable(self, "_on_surf_completed")
	if not bm.is_connected("surf_completed", on_surf_completed):
		bm.connect("surf_completed", on_surf_completed)

	var on_surf_failed := Callable(self, "_on_surf_failed")
	if not bm.is_connected("surf_failed", on_surf_failed):
		bm.connect("surf_failed", on_surf_failed)

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


## 旧页面动作仍可进入这里；BrowserManager 会给出快速关闭提示。
func _start_surf(keyword: String) -> void:
	var query: String = keyword.strip_edges()
	if query.is_empty():
		_set_status("先输点关键词。")
		return

	# 每次冲浪都新开一个标签页，保留主页和已有结果
	var tab = BrowserTabDataClass.new()
	_tab_counter += 1
	tab.tab_id = "tab_%d" % _tab_counter
	_tabs.append(tab)
	_create_tab_widget(tab)

	tab.keyword = query
	tab.display_url = "browser://surf?q=%s" % query
	tab.state = BrowserTabDataClass.TabState.LOADING
	tab.title = "[冲浪] %s" % query
	tab.page_content = {}
	tab.error_message = ""
	_update_tab_title(tab)
	_switch_tab(tab.tab_id)
	_set_status("正在查找相关网页...")
	_render_loading(tab, "正在打开新的网页...")

	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_set_tab_error(tab, "浏览服务暂时不可用")
		return

	var request_id: String = bm.surf(query)
	if request_id.is_empty():
		_set_tab_error(tab, "暂时无法连接这个站点")
		return
	_request_to_tab[request_id] = tab.tab_id
	tab.request_id = request_id
	_refresh_window_lock()


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
	tab.state = BrowserTabDataClass.TabState.LOADING
	tab.title = target_url
	tab.page_content = {}
	tab.error_message = ""
	_update_tab_title(tab)
	_switch_tab(tab.tab_id)
	_set_status("页面打开中...")
	_render_loading(tab, "正在打开页面...")

	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_set_tab_error(tab, "浏览服务暂时不可用")
		return

	var request_id: String = bm.open_page(target_url, design_prompt, page_context)
	if request_id.is_empty():
		_set_tab_error(tab, "暂时无法打开这个页面")
		return
	_request_to_tab[request_id] = tab.tab_id
	tab.request_id = request_id
	_refresh_window_lock()


func _create_tab_widget(tab) -> void:
	if tab_buttons == null:
		return

	var T := BrowserThemeClass

	# 外层 PanelContainer 作为统一的标签背景
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(270, 58)
	var holder_style := StyleBoxFlat.new()
	holder_style.bg_color = T.COLOR_SURFACE
	holder_style.corner_radius_top_left = 15
	holder_style.corner_radius_top_right = 15
	holder_style.corner_radius_bottom_left = 0
	holder_style.corner_radius_bottom_right = 0
	holder_style.border_width_left = 2
	holder_style.border_width_top = 2
	holder_style.border_width_right = 2
	holder_style.border_width_bottom = 0
	holder_style.border_color = T.COLOR_BORDER
	holder.add_theme_stylebox_override("panel", holder_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	holder.add_child(row)

	var tab_btn := Button.new()
	tab_btn.text = tab.title
	tab_btn.icon = _load_tab_icon(str(tab.icon_path))
	tab_btn.expand_icon = true
	tab_btn.add_theme_constant_override("icon_max_width", 34)
	tab_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	tab_btn.add_theme_font_size_override("font_size", 28)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(48, 0)
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
	close_btn.add_theme_font_size_override("font_size", 30)

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
		style.corner_radius_top_left = 15
		style.corner_radius_top_right = 15
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 0
		style.border_color = T.COLOR_BORDER
		if tab_id == _current_tab_id:
			style.bg_color = T.COLOR_SURFACE
		else:
			style.bg_color = T.COLOR_SURFACE_ALT
		holder.add_theme_stylebox_override("panel", style)


func _render_tab(tab) -> void:
	_clear_content_root()

	match tab.state:
		BrowserTabDataClass.TabState.LOADING:
			_render_loading(tab, "加载中...")
		BrowserTabDataClass.TabState.ERROR:
			_render_error(tab.error_message)
		BrowserTabDataClass.TabState.READY:
			_render_page(tab.page_content)
		_:
			_render_idle_placeholder()


func _render_loading(_tab, text: String) -> void:
	_clear_content_root()
	var T := BrowserThemeClass
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 18)
	content_root.add_child(wrapper)

	var top_spacer := Control.new()
	top_spacer.custom_minimum_size.y = 56
	wrapper.add_child(top_spacer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _make_content_panel_style(T.COLOR_SURFACE, T.COLOR_BORDER, 18))
	wrapper.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_bottom", 36)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)

	var title := Label.new()
	title.text = "正在加载网页"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", T.COLOR_TEXT)
	body.add_child(title)

	_loading_dots_label = Label.new()
	_loading_dots_label.text = text
	_loading_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_dots_label.add_theme_font_size_override("font_size", 27)
	_loading_dots_label.add_theme_color_override("font_color", T.COLOR_TEXT_DIM)
	body.add_child(_loading_dots_label)

	if _tab != null and not str(_tab.keyword).strip_edges().is_empty():
		var keyword := Label.new()
		keyword.text = "关键词：%s" % str(_tab.keyword).strip_edges()
		keyword.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keyword.add_theme_font_size_override("font_size", 24)
		keyword.add_theme_color_override("font_color", T.COLOR_TEXT_MUTED)
		body.add_child(keyword)

	_loading_progress = ProgressBar.new()
	_loading_progress.min_value = 0
	_loading_progress.max_value = 100
	_loading_progress.value = 14
	_loading_progress.custom_minimum_size = Vector2(0, 12)
	_loading_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_loading_progress)

	_loading_phase_label = Label.new()
	_loading_phase_label.text = "正在连接站点"
	_loading_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_phase_label.add_theme_font_size_override("font_size", 23)
	_loading_phase_label.add_theme_color_override("font_color", T.COLOR_TEXT_DIM)
	body.add_child(_loading_phase_label)

	var skeleton := VBoxContainer.new()
	skeleton.add_theme_constant_override("separation", 8)
	body.add_child(skeleton)
	for ratio in [0.92, 0.72, 0.84]:
		skeleton.add_child(_make_loading_skeleton_line(ratio))

	call_deferred("_start_loading_animation")


func _make_loading_skeleton_line(width_ratio: float) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var line := PanelContainer.new()
	line.custom_minimum_size = Vector2(0, 12)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_stretch_ratio = clampf(width_ratio, 0.05, 1.0)
	line.add_theme_stylebox_override("panel", _make_content_panel_style(BrowserThemeClass.COLOR_SURFACE_ALT, BrowserThemeClass.COLOR_SURFACE_ALT, 6))
	row.add_child(line)

	if width_ratio < 0.999:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_stretch_ratio = maxf(0.01, 1.0 - width_ratio)
		row.add_child(spacer)
	return row


func _start_loading_animation() -> void:
	if _loading_progress == null or not is_instance_valid(_loading_progress):
		return
	if _loading_tween != null and is_instance_valid(_loading_tween):
		_loading_tween.kill()
	_loading_tween = null
	_loading_phase_index = 0
	_advance_loading_phase()
	_loading_tween = create_tween()
	_loading_tween.set_loops()
	_loading_tween.tween_property(_loading_progress, "value", 92.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_loading_tween.tween_callback(_advance_loading_phase)
	_loading_tween.tween_property(_loading_progress, "value", 16.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_loading_tween.tween_callback(_advance_loading_phase)


func _advance_loading_phase() -> void:
	var phases: PackedStringArray = [
		"正在连接站点",
		"正在获取页面",
		"正在加载内容",
		"即将完成"
	]
	if _loading_phase_label != null and is_instance_valid(_loading_phase_label):
		_loading_phase_label.text = phases[_loading_phase_index % phases.size()]
	if _loading_dots_label != null and is_instance_valid(_loading_dots_label):
		var dots := ".".repeat(1 + (_loading_phase_index % 3))
		_loading_dots_label.text = "页面加载中%s" % dots
	_loading_phase_index += 1


func _stop_loading_animation() -> void:
	if _loading_tween != null and is_instance_valid(_loading_tween):
		_loading_tween.kill()
	_loading_tween = null
	_loading_progress = null
	_loading_dots_label = null
	_loading_phase_label = null


func _render_error(text: String) -> void:
	_set_scene_page_scroll_mode(false)
	_clear_content_root()
	var T := BrowserThemeClass
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(840, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _make_content_panel_style(T.COLOR_SURFACE, T.COLOR_BORDER, 14))
	content_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	margin.add_child(body)

	var label := Label.new()
	label.text = "加载失败：%s" % text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", BrowserThemeClass.COLOR_ERROR)
	label.add_theme_font_size_override("font_size", 30)
	body.add_child(label)

	var home_btn := Button.new()
	home_btn.text = "返回主页"
	home_btn.pressed.connect(_on_home_button_pressed)
	_style_content_button(home_btn)
	body.add_child(home_btn)


func _render_idle_placeholder() -> void:
	_render_home_page()


func _render_home_page() -> void:
	_set_scene_page_scroll_mode(false)
	_clear_content_root()
	var home_page: Control = BrowserHomePageScene.instantiate() as Control
	if home_page == null:
		_render_error("浏览器主页加载失败")
		return
	home_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if home_page.has_signal("search_requested"):
		home_page.connect("search_requested", Callable(self, "_on_home_search_requested"))
	if home_page.has_signal("url_requested"):
		home_page.connect("url_requested", Callable(self, "_on_home_url_requested"))
	content_root.add_child(home_page)


func _on_home_search_requested(query: String) -> void:
	var normalized: String = query.strip_edges()
	if normalized.is_empty():
		return
	if normalized.contains("://") or normalized.begins_with("www."):
		if not normalized.contains("://"):
			normalized = "https://" + normalized
		_open_page(normalized)
		return
	_start_surf(normalized)


func _on_home_url_requested(url: String) -> void:
	_open_page(url)


func _render_page(page_content: Dictionary) -> void:
	_set_scene_page_scroll_mode(bool(page_content.get("owns_scroll", false)))
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


func _set_scene_page_scroll_mode(owns_scroll: bool) -> void:
	if content_scroll == null:
		return
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED \
		if owns_scroll else ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED \
		if owns_scroll else ScrollContainer.SCROLL_MODE_AUTO
	if owns_scroll:
		content_scroll.scroll_vertical = 0
		content_scroll.scroll_horizontal = 0


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
	_stop_loading_animation()
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
	_refresh_window_lock()


func _has_loading_tabs() -> bool:
	for tab in _tabs:
		if tab != null and tab.state == BrowserTabDataClass.TabState.LOADING:
			return true
	return false


func _refresh_window_lock() -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		return
	if _has_loading_tabs():
		if app_mgr.has_method("lock_app_window"):
			app_mgr.call("lock_app_window", "browser")
	else:
		if app_mgr.has_method("unlock_app_window"):
			app_mgr.call("unlock_app_window", "browser")


func _update_tab_title(tab) -> void:
	if not _tab_widgets.has(tab.tab_id):
		return
	var widget: Dictionary = _tab_widgets[tab.tab_id]
	var button: Button = widget.get("button")
	if button:
		button.text = tab.title
		button.icon = _load_tab_icon(str(tab.icon_path))


func _load_tab_icon(icon_path: String) -> Texture2D:
	var resolved_path: String = icon_path.strip_edges()
	if resolved_path.is_empty() or not ResourceLoader.exists(resolved_path):
		resolved_path = "res://Assets/images/app_icons/sp_icon_browser.png"
	return ResourceLoader.load(resolved_path) as Texture2D


func _find_tab_by_id(tab_id: String):
	for tab in _tabs:
		if tab.tab_id == tab_id:
			return tab
	return null


func _find_page_tab_by_url(url: String):
	for tab in _tabs:
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

	if tab.state == BrowserTabDataClass.TabState.LOADING:
		_set_status("页面仍在加载，先等它打开再关闭。")
		_switch_tab(tab_id)
		return

	var closed_index: int = -1
	for i in range(_tabs.size()):
		if _tabs[i].tab_id == tab_id:
			closed_index = i
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
		_refresh_window_lock()
		return

	if _current_tab_id == tab_id:
		var fallback_index: int = clampi(closed_index - 1, 0, _tabs.size() - 1)
		_switch_tab(_tabs[fallback_index].tab_id)
	_refresh_window_lock()


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


func _on_page_generated(request_id: String, url: String, content: Dictionary) -> void:
	var tab = _find_tab_by_request(request_id)
	if tab == null:
		return
	_request_to_tab.erase(request_id)
	tab.state = BrowserTabDataClass.TabState.READY
	tab.display_url = url
	tab.page_content = content.duplicate(true)
	tab.title = str(content.get("title", url))
	tab.icon_path = str(content.get("icon_path", tab.icon_path))
	if tab.title.strip_edges().is_empty():
		tab.title = url
	_update_tab_title(tab)
	if tab.tab_id == _current_tab_id:
		if address_display:
			address_display.text = tab.display_url
		_render_page(tab.page_content)
		_set_status("页面已打开")
	_refresh_window_lock()


func _on_page_failed(request_id: String, _url: String, error: String) -> void:
	var tab = _find_tab_by_request(request_id)
	if tab == null:
		return
	_request_to_tab.erase(request_id)
	push_warning("Browser page failed: %s" % error)
	_set_tab_error(tab, "这个页面暂时无法打开")


func _on_url_open_requested(url: String, design_prompt: String, page_context: String) -> void:
	_open_page(url, design_prompt, "", page_context)


func _on_surf_started(_request_id: String, _keyword: String) -> void:
	_set_status("正在搜索网页...")


func _on_surf_completed(request_id: String, _keyword: String, url: String, _page_summary: String, page: Dictionary) -> void:
	if not _request_to_tab.has(request_id):
		return
	var tab_id: String = _request_to_tab[request_id]
	_request_to_tab.erase(request_id)
	var tab = _find_tab_by_id(tab_id)
	if tab == null:
		return
	tab.state = BrowserTabDataClass.TabState.READY
	tab.display_url = url
	tab.page_content = page.duplicate(true)
	tab.icon_path = str(page.get("icon_path", tab.icon_path))
	var page_title: String = str(page.get("title", "")).strip_edges()
	if page_title.is_empty():
		page_title = url
	tab.title = page_title
	_update_tab_title(tab)
	if tab.tab_id == _current_tab_id:
		if address_display:
			address_display.text = tab.display_url
		_render_page(tab.page_content)
		_set_status("页面已打开。")
	_refresh_window_lock()


func _on_surf_failed(request_id: String, _keyword: String, error: String) -> void:
	if not _request_to_tab.has(request_id):
		return
	var tab_id: String = _request_to_tab[request_id]
	_request_to_tab.erase(request_id)
	var tab = _find_tab_by_id(tab_id)
	if tab != null:
		push_warning("Browser surf failed: %s" % error)
		_set_tab_error(tab, "没有找到可以打开的页面")


# ── 统一页面动作路由 ──────────────────────────────────

func _on_page_action(action_data: Dictionary) -> void:
	var action: String = str(action_data.get("action", ""))
	match action:
		"open_url":
			_open_premade_link(str(action_data.get("url", "")), str(action_data.get("design_prompt", "")))
		"perform_action":
			page_action_requested.emit(action_data.duplicate(true))
		"surf":
			var form_data: Dictionary = action_data.get("__form_data", {})
			var keyword: String = str(form_data.get("keyword", action_data.get("keyword", ""))).strip_edges()
			_start_surf(keyword)
		"open_history":
			_on_history_entry_pressed(str(action_data.get("entry_id", "")))
		"open_history_page":
			_on_history_button_pressed()
		"submit_story_form":
			_submit_story_form(action_data)
		"story_event":
			_submit_story_event(action_data)
		"go_home":
			_on_home_button_pressed()
		_:
			if not action.is_empty():
				page_action_requested.emit(action_data.duplicate(true))
				push_warning("BrowserApp: 未知页面动作: %s" % action)


func _open_premade_link(url: String, design_prompt: String = "") -> void:
	var normalized := url.strip_edges()
	if normalized.is_empty():
		return
	_open_page(normalized, design_prompt)


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
		_set_status("当前页面操作不可用")
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
	var form_data: Dictionary = action_data.get("form_data", {})
	var form_fields_value: Variant = action_data.get("story_form_fields", "")
	var form_fields: PackedStringArray = []
	if form_fields_value is Array or form_fields_value is PackedStringArray:
		for field_value: Variant in form_fields_value:
			form_fields.append(str(field_value))
	else:
		form_fields = str(form_fields_value).split(",", false)
	for field_value: String in form_fields:
		var field_name: String = field_value.strip_edges()
		if not field_name.is_empty() and form_data.has(field_name):
			variables[field_name] = form_data[field_name]
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

	_set_status(str(action_data.get("success_status", "已提交")))
	var success_url: String = str(action_data.get("success_url", "")).strip_edges()
	if not success_url.is_empty():
		_open_page(success_url)
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
	# 优先切到已有的主页 tab；没有就新开一个，避免覆盖当前 LOADING/READY tab
	for tab in _tabs:
		if tab != null and tab.state == BrowserTabDataClass.TabState.IDLE and tab.display_url == "browser://home":
			_switch_tab(tab.tab_id)
			return
	_create_blank_tab()


func _on_history_button_pressed() -> void:
	_render_history_page()


func _render_history_page() -> void:
	_clear_content_root()
	var T := BrowserThemeClass
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		_render_error("浏览服务暂时不可用")
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
