class_name CommunityApp
extends Control

const SocialPostRendererClass = preload("res://scripts/apps/community/social_post_renderer.gd")
const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")

const LOADING_HINTS: PackedStringArray = [
	"正在加载最新帖子，稍等片刻…",
	"新的讨论正在刷新，马上就好…",
	"千度贴吧加载中，请稍候…",
]
const LOADING_CARD_HEIGHTS: PackedFloat32Array = [188.0, 208.0, 176.0, 196.0, 224.0, 184.0]

# ── Modern palette ──────────────────────────────────────────
const C_PANEL_BG := Color("#FFFFFF")
const C_PANEL_BORDER := Color("#E5E7EB")
const C_TITLE := Color("#111827")
const C_BODY := Color("#374151")
const C_META := Color("#9CA3AF")
const C_ACCENT := Color("#E9475A")
const C_ACCENT_CHILL := Color("#3B82F6")
const C_ACCENT_LEARN := Color("#F59E0B")
const C_ACCENT_PROMO := Color("#10B981")
const C_BTN_ENABLED := Color("#E9475A")
const C_BTN_DISABLED := Color("#E5E7EB")
const C_BTN_TEXT := Color("#FFFFFF")
const C_BTN_TEXT_OFF := Color("#9CA3AF")
const C_TAB_ACTIVE := Color("#6366F1")
const C_TAB_INACTIVE := Color("#6B7280")
const C_LOADING_BG := Color("#F3F4F6")
const C_LOADING_LINE := Color("#E5E7EB")
const C_LOADING_LINE_ALT := Color("#D1D5DB")

@onready var feed_scroll: ScrollContainer = %FeedScroll
@onready var feed_container: VBoxContainer = %FeedContainer
@onready var actions_container: VBoxContainer = %ActionsContainer
@onready var status_label: Label = %StatusLabel
@onready var loading_view: Control = %LoadingView
@onready var loading_scroll: ScrollContainer = %LoadingScroll
@onready var loading_list: VBoxContainer = %LoadingList
@onready var tab_bar: HBoxContainer = %TabBar

@onready var home_page: Control = %HomePage
@onready var feed_page: Control = %FeedPage
@onready var nav_home_btn: Button = %NavHomeButton
@onready var nav_feed_btn: Button = %NavFeedButton

var _action_buttons: Dictionary = {}
var _is_loading: bool = false
var _loading_action_id: String = ""
var _loading_tween: Tween = null
var _selected_entry_id: String = ""
var _active_category: String = "all"
var _fab_button: Button = null
var _search_input: LineEdit = null
var _free_search_button: Button = null
var _random_search_button: Button = null

const CATEGORY_TABS: Array[Dictionary] = [
	{"id": "all",             "label": "推荐"},
	{"id": "chill_browse",    "label": "日常"},
	{"id": "learn_dev",       "label": "教程"},
	{"id": "follow_contest",  "label": "项目"},
]


func _ready() -> void:
	_connect_signals()
	_build_tab_bar()
	_setup_bottom_nav()
	_setup_fab()
	_set_loading_visible(false)
	_set_status("选个板块进去看看。")
	_switch_to_page("home")
	_refresh_view()

func _setup_bottom_nav() -> void:
	if nav_home_btn:
		nav_home_btn.pressed.connect(_switch_to_page.bind("home"))
	if nav_feed_btn:
		nav_feed_btn.pressed.connect(_switch_to_page.bind("feed"))

func _switch_to_page(page_name: String) -> void:
	if home_page == null or feed_page == null:
		return
	
	if page_name == "home":
		home_page.visible = true
		feed_page.visible = false
		if nav_home_btn:
			nav_home_btn.add_theme_color_override("font_color", C_ACCENT)
		if nav_feed_btn:
			nav_feed_btn.add_theme_color_override("font_color", C_META)
		if _fab_button:
			_fab_button.visible = false
	else:
		home_page.visible = false
		feed_page.visible = true
		if nav_home_btn:
			nav_home_btn.add_theme_color_override("font_color", C_META)
		if nav_feed_btn:
			nav_feed_btn.add_theme_color_override("font_color", C_ACCENT)
		if _fab_button:
			_fab_button.visible = true


## 右下角悬浮发帖按钮（FAB）
func _setup_fab() -> void:
	_fab_button = Button.new()
	_fab_button.text = "+"
	_fab_button.custom_minimum_size = Vector2(56, 56)
	_fab_button.add_theme_font_size_override("font_size", 32)
	_fab_button.add_theme_color_override("font_color", Color.WHITE)
	_fab_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_fab_button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT
	style.corner_radius_top_left = 28
	style.corner_radius_top_right = 28
	style.corner_radius_bottom_left = 28
	style.corner_radius_bottom_right = 28
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color("#4F46E5")

	_fab_button.add_theme_stylebox_override("normal", style)
	_fab_button.add_theme_stylebox_override("hover", hover_style)
	_fab_button.add_theme_stylebox_override("pressed", style)
	_fab_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# 锚定右下角 — 距底栏上方 80px、右侧 24px
	_fab_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fab_button.offset_right = -24
	_fab_button.offset_bottom = -88
	_fab_button.offset_left = -80
	_fab_button.offset_top = -144
	_fab_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fab_button.visible = false
	_fab_button.pressed.connect(_on_fab_pressed)
	add_child(_fab_button)


func _on_fab_pressed() -> void:
	_set_status("先进个板块看看别人怎么写的，再发帖。")

func _connect_signals() -> void:
	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null:
		return

	var started := Callable(self, "_on_action_started")
	if not manager.is_connected("community_action_started", started):
		manager.connect("community_action_started", started)

	var completed := Callable(self, "_on_action_completed")
	if not manager.is_connected("community_action_completed", completed):
		manager.connect("community_action_completed", completed)

	var failed := Callable(self, "_on_action_failed")
	if not manager.is_connected("community_action_failed", failed):
		manager.connect("community_action_failed", failed)

	var feed_updated := Callable(self, "_on_feed_updated")
	if not manager.is_connected("community_feed_updated", feed_updated):
		manager.connect("community_feed_updated", feed_updated)

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		var refresh := Callable(self, "_on_runtime_state_changed")
		if glm.has_signal("ap_changed") and not glm.is_connected("ap_changed", refresh):
			glm.connect("ap_changed", refresh)
		if glm.has_signal("phase_changed") and not glm.is_connected("phase_changed", refresh):
			glm.connect("phase_changed", refresh)
		if glm.has_signal("day_changed") and not glm.is_connected("day_changed", refresh):
			glm.connect("day_changed", refresh)

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null:
		var chat_refresh := Callable(self, "_on_runtime_state_changed")
		if chat.has_signal("chat_state_changed") and not chat.is_connected("chat_state_changed", chat_refresh):
			chat.connect("chat_state_changed", chat_refresh)


func _refresh_view() -> void:
	if _is_loading:
		return
	_render_actions()
	_render_feed()


func _build_tab_bar() -> void:
	if tab_bar == null:
		return
	_clear_container(tab_bar)
	var wrapper := MarginContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("margin_left", 6)
	wrapper.add_theme_constant_override("margin_right", 6)
	wrapper.add_theme_constant_override("margin_top", 6)
	wrapper.add_theme_constant_override("margin_bottom", 0)
	tab_bar.add_child(wrapper)

	# 详情模式 —— 显示"返回列表"+ 标题
	if not _selected_entry_id.is_empty():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		wrapper.add_child(row)

		var back_button := Button.new()
		back_button.text = "← 返回列表"
		back_button.flat = true
		back_button.add_theme_color_override("font_color", C_ACCENT)
		back_button.add_theme_color_override("font_hover_color", Color("#4F46E5"))
		back_button.add_theme_color_override("font_pressed_color", C_ACCENT)
		back_button.add_theme_font_size_override("font_size", 15)
		back_button.pressed.connect(_show_history_index)
		row.add_child(back_button)

		var title := Label.new()
		title.text = _get_selected_entry_title()
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", C_TITLE)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)

		# 右侧占位保持标题居中
		var tail := Control.new()
		tail.custom_minimum_size.x = 100
		row.add_child(tail)
		return

	# 列表模式 —— 显示分类 tab
	var tabs_row := HBoxContainer.new()
	tabs_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_row.add_theme_constant_override("separation", 24)
	wrapper.add_child(tabs_row)

	for tab in CATEGORY_TABS:
		tabs_row.add_child(_make_category_tab(str(tab.get("id", "")), str(tab.get("label", ""))))


func _make_category_tab(tab_id: String, label: String) -> Control:
	var active: bool = (_active_category == tab_id)

	var btn := Button.new()
	btn.flat = true
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_TITLE if active else C_META)
	btn.add_theme_color_override("font_hover_color", C_TITLE)
	btn.add_theme_color_override("font_pressed_color", C_TITLE)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_category_selected.bind(tab_id))

	# 底部 3px 强调条（active 时显示）
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(btn)

	var underline := ColorRect.new()
	underline.custom_minimum_size = Vector2(0, 3)
	underline.color = C_ACCENT if active else Color.TRANSPARENT
	col.add_child(underline)

	return col


func _on_category_selected(tab_id: String) -> void:
	if _active_category == tab_id:
		return
	_active_category = tab_id
	_render_feed()
	call_deferred("_scroll_feed_to_top")


func _render_actions() -> void:
	_clear_container(actions_container)
	_action_buttons.clear()
	_search_input = null
	_free_search_button = null
	_random_search_button = null

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("get_available_actions"):
		_add_empty_state(actions_container, "服务连接中，稍后重试…")
		return

	var actions: Array = manager.get_available_actions()
	if actions.is_empty():
		_add_empty_state(actions_container, "暂无可用动作。")
		return

	actions_container.add_child(_build_home_search_card())
	actions_container.add_child(_build_home_section_title("板块", "选一个板块花点时间"))

	for action_data in actions:
		if action_data is Dictionary:
			actions_container.add_child(_build_action_tile(action_data))

	actions_container.add_child(_build_history_entry_card())


func _build_home_search_card() -> Control:
	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	var blocking_reason: String = ""
	if manager != null and manager.has_method("get_search_blocking_reason"):
		blocking_reason = str(manager.call("get_search_blocking_reason")).strip_edges()
	var enabled: bool = blocking_reason.is_empty() and not _is_loading

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(Color("#FFFFFF"), Color("#F1D5DA"), 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)

	var search_bar := PanelContainer.new()
	search_bar.add_theme_stylebox_override("panel", _make_plain_style(Color.WHITE, 18))
	body.add_child(search_bar)

	var search_margin := MarginContainer.new()
	search_margin.add_theme_constant_override("margin_left", 14)
	search_margin.add_theme_constant_override("margin_top", 8)
	search_margin.add_theme_constant_override("margin_right", 14)
	search_margin.add_theme_constant_override("margin_bottom", 8)
	search_bar.add_child(search_margin)

	var search_body := VBoxContainer.new()
	search_body.add_theme_constant_override("separation", 8)
	search_margin.add_child(search_body)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	search_body.add_child(input_row)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "自由搜索帖子关键词"
	_search_input.clear_button_enabled = true
	_search_input.editable = enabled
	_search_input.custom_minimum_size = Vector2(0, 38)
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.text_submitted.connect(_on_free_search_submitted)
	input_row.add_child(_search_input)

	_free_search_button = Button.new()
	_free_search_button.text = "搜索"
	_free_search_button.disabled = not enabled
	_free_search_button.custom_minimum_size = Vector2(72, 38)
	_free_search_button.pressed.connect(_on_free_search_pressed)
	_style_action_button(_free_search_button, enabled)
	input_row.add_child(_free_search_button)

	_random_search_button = Button.new()
	_random_search_button.text = "随心一搜"
	_random_search_button.disabled = not enabled
	_random_search_button.custom_minimum_size = Vector2(0, 36)
	_random_search_button.pressed.connect(_on_random_search_pressed)
	_style_action_button(_random_search_button, enabled)
	search_body.add_child(_random_search_button)

	var trend := Label.new()
	trend.text = "提示：长按板块卡可以查看本时段会发生什么" if enabled else blocking_reason
	trend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trend.add_theme_font_size_override("font_size", 12)
	trend.add_theme_color_override("font_color", C_BODY if enabled else Color("#EF4444"))
	body.add_child(trend)

	return panel


func _on_free_search_submitted(text: String) -> void:
	_submit_free_search(text)


func _on_free_search_pressed() -> void:
	if _search_input == null or not is_instance_valid(_search_input):
		return
	_submit_free_search(_search_input.text)


func _submit_free_search(query: String) -> void:
	if _is_loading:
		return
	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("search_feed"):
		_set_status("连接中断，请稍后再试。")
		return
	var result: Dictionary = manager.call("search_feed", query)
	if not bool(result.get("success", false)):
		_set_status(str(result.get("error", "搜索失败")))
		_refresh_view()
		return
	if bool(result.get("async", false)):
		_begin_loading_state("free_search")
	else:
		_set_status("搜索结果已出现。")
		_refresh_view()
		_switch_to_page("feed")
		call_deferred("_scroll_feed_to_top")


func _on_random_search_pressed() -> void:
	if _is_loading:
		return
	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("random_feed"):
		_set_status("连接中断，请稍后再试。")
		return
	var result: Dictionary = manager.call("random_feed")
	if not bool(result.get("success", false)):
		_set_status(str(result.get("error", "刷新失败")))
		_refresh_view()
		return
	if bool(result.get("async", false)):
		_begin_loading_state("random_search")
	else:
		_set_status("随手刷到一条新帖。")
		_refresh_view()
		_switch_to_page("feed")
		call_deferred("_scroll_feed_to_top")


func _build_home_section_title(title_text: String, subtitle_text: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(4, 18)
	accent.color = C_ACCENT
	row.add_child(accent)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TITLE)
	row.add_child(title)

	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", C_META)
	row.add_child(subtitle)

	return row


func _build_action_tile(action_data: Dictionary) -> Control:
	var action_id: String = str(action_data.get("action_id", "")).strip_edges()
	var accent: Color = _get_action_accent(action_id)
	var enabled: bool = bool(action_data.get("enabled", true)) and not _is_loading

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(C_PANEL_BG, C_PANEL_BORDER, 8))

	var hint := ActivityPreviewHintClass.new()
	panel.add_child(hint)
	hint.set_payload_resolver(func() -> Dictionary:
		return _build_action_preview_payload(action_data)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	row.add_child(_build_board_avatar(action_id, accent))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title := Label.new()
	title.text = _get_board_label(action_id)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TITLE)
	info.add_child(title)

	var desc := Label.new()
	desc.text = _get_board_description(action_id)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", C_META)
	info.add_child(desc)

	if not enabled:
		var reason := Label.new()
		reason.text = str(action_data.get("blocked_reason", "这个时间段已经安排过事情了"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", Color("#EF4444"))
		info.add_child(reason)

	var action_button := Button.new()
	action_button.name = "ActionButton_%s" % action_id
	action_button.text = "进入"
	action_button.disabled = not enabled
	action_button.custom_minimum_size = Vector2(72, 36)
	action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_button.pressed.connect(_on_action_button_pressed.bind(action_id))
	_style_action_button(action_button, enabled)
	row.add_child(action_button)

	_action_buttons[action_id] = action_button
	return panel


func _build_history_entry_card() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(C_PANEL_BG, C_PANEL_BORDER, 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_theme_stylebox_override("panel", _make_plain_style(Color(C_TAB_ACTIVE.r, C_TAB_ACTIVE.g, C_TAB_ACTIVE.b, 0.14), 8))
	var icon_label := Label.new()
	icon_label.text = "册"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 18)
	icon_label.add_theme_color_override("font_color", C_TAB_ACTIVE)
	icon.add_child(icon_label)
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title := Label.new()
	title.text = "历史帖子"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TITLE)
	info.add_child(title)

	var desc := Label.new()
	desc.text = "翻看之前刷到、看过、发过的所有帖子"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", C_META)
	info.add_child(desc)

	var enter_btn := Button.new()
	enter_btn.text = "查看"
	enter_btn.custom_minimum_size = Vector2(72, 36)
	enter_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enter_btn.pressed.connect(func() -> void:
		_switch_to_page("feed")
		call_deferred("_scroll_feed_to_top")
	)
	_style_action_button(enter_btn, true)
	row.add_child(enter_btn)

	return panel


func _get_board_label(action_id: String) -> String:
	match action_id:
		"chill_browse":
			return "日常吧"
		"learn_dev":
			return "教程吧"
		"follow_contest":
			return "项目吧"
		_:
			return "板块"


func _get_board_description(action_id: String) -> String:
	match action_id:
		"chill_browse":
			return "随便逛逛，看看大家最近都在聊什么"
		"learn_dev":
			return "翻翻教程帖、踩坑记录和上手分享"
		"follow_contest":
			return "看看其他人晒的项目，顺手发点自己的"
		_:
			return "进入这个板块花点时间"


func _build_board_avatar(action_id: String, accent: Color) -> Control:
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.add_theme_stylebox_override("panel", _make_plain_style(Color(accent.r, accent.g, accent.b, 0.14), 8))

	var label := Label.new()
	label.text = _get_board_initial(action_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", accent)
	avatar.add_child(label)
	return avatar


func _get_board_initial(action_id: String) -> String:
	match action_id:
		"chill_browse":
			return "刷"
		"learn_dev":
			return "学"
		"follow_contest":
			return "晒"
		_:
			return "发"


func _render_feed() -> void:
	_clear_container(feed_container)
	_build_tab_bar()

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("get_recent_entries"):
		_add_empty_state(feed_container, "千度贴吧暂时离线，稍后再回来看看。")
		return

	var entries: Array = manager.get_recent_entries(18)
	if entries.is_empty():
		_add_empty_state(feed_container, "还没有历史帖子，回首页进个板块试试。")
		return

	if _selected_entry_id.is_empty():
		_render_history_list(entries)
		return

	_render_selected_entry(entries)


func _render_history_list(entries: Array) -> void:
	var filtered: Array = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var entry_dict: Dictionary = entry
		if _active_category != "all":
			if str(entry_dict.get("action_id", "")) != _active_category:
				continue
		filtered.append(entry_dict)

	if filtered.is_empty():
		_add_empty_state(feed_container, "这个分类下暂时还没有帖子，换个分类试试。")
		return

	for i in range(filtered.size()):
		var entry_dict: Dictionary = filtered[i]
		var item := SocialPostRendererClass.create_history_card(entry_dict)
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.gui_input.connect(_on_history_item_gui_input.bind(str(entry_dict.get("entry_id", ""))))
		feed_container.add_child(item)
		feed_container.add_child(SocialPostRendererClass.build_feed_divider())

	# 尾部"已加载全部"提示
	var end_tip := Label.new()
	end_tip.text = "— 已经到底了 —"
	end_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_tip.add_theme_font_size_override("font_size", 14)
	end_tip.add_theme_color_override("font_color", C_META)
	end_tip.custom_minimum_size = Vector2(0, 56)
	feed_container.add_child(end_tip)


func _render_selected_entry(entries: Array) -> void:
	var entry := _find_entry_by_id(entries, _selected_entry_id)
	if entry.is_empty():
		_selected_entry_id = ""
		_build_tab_bar()
		_render_history_list(entries)
		return
	feed_container.add_child(SocialPostRendererClass.create_feed_entry(entry))


func _on_history_item_gui_input(event: InputEvent, entry_id: String) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	_open_history_entry(entry_id)


func _open_history_entry(entry_id: String) -> void:
	_selected_entry_id = entry_id
	_render_feed()
	call_deferred("_scroll_feed_to_top")


func _show_history_index() -> void:
	_selected_entry_id = ""
	_render_feed()
	call_deferred("_scroll_feed_to_top")


func _find_entry_by_id(entries: Array, entry_id: String) -> Dictionary:
	for entry in entries:
		if not entry is Dictionary:
			continue
		var entry_dict: Dictionary = entry
		if str(entry_dict.get("entry_id", "")) == entry_id:
			return entry_dict.duplicate(true)
	return {}


func _get_selected_entry_title() -> String:
	if _selected_entry_id.is_empty():
		return "动态"
	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("get_recent_entries"):
		return "帖子详情"
	var entry := _find_entry_by_id(manager.get_recent_entries(18), _selected_entry_id)
	var title: String = str(entry.get("title", "帖子详情")).strip_edges()
	return title if not title.is_empty() else "帖子详情"


func _build_feed_intro_card() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(Color("#EEF2FF"), Color("#C7D2FE"), 10))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)

	var title := Label.new()
	title.text = "欢迎来到千度贴吧"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_ACCENT)
	body.add_child(title)

	var desc := Label.new()
	desc.text = "这里会刷到参赛者、玩家和路人的动态。新的讨论会随着你的浏览和发布逐渐浮上来。"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", C_BODY)
	body.add_child(desc)

	return panel


func _build_action_preview_payload(action_data: Dictionary) -> Dictionary:
	var action_id: String = str(action_data.get("action_id", "")).strip_edges()
	var enabled: bool = bool(action_data.get("enabled", true))
	var blocked: String = str(action_data.get("blocked_reason", ""))
	var tags: Array = action_data.get("tags", [])

	var conditions: Array = []
	conditions.append("占用当前时间段")
	if not tags.is_empty():
		conditions.append("标签：%s" % " · ".join(PackedStringArray(tags)))
	if enabled:
		conditions.append("当前状态：可以打开")
	else:
		conditions.append("当前状态：暂时刷不到")

	return {
		"title": _get_board_label(action_id),
		"text": _get_board_description(action_id),
		"conditions": conditions,
		"rewards": (action_data.get("stat_changes", {}) as Dictionary).duplicate(true),
		"disabled_reason": blocked if not enabled else "",
		"accent_color": _get_action_accent(action_id),
	}


func _get_action_accent(action_id: String) -> Color:
	match action_id:
		"chill_browse":
			return C_ACCENT_CHILL
		"learn_dev":
			return C_ACCENT_LEARN
		"follow_contest":
			return C_ACCENT_PROMO
		_:
			return C_ACCENT_CHILL


func _style_action_button(button: Button, enabled: bool) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.bg_color = C_BTN_ENABLED if enabled else C_BTN_DISABLED
	var hover_style: StyleBoxFlat = style.duplicate()
	if enabled:
		hover_style.bg_color = Color("#D93248")
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", C_BTN_TEXT if enabled else C_BTN_TEXT_OFF)
	button.add_theme_color_override("font_hover_color", C_BTN_TEXT if enabled else C_BTN_TEXT_OFF)
	button.add_theme_color_override("font_pressed_color", C_BTN_TEXT if enabled else C_BTN_TEXT_OFF)
	button.add_theme_font_size_override("font_size", 13)


func _set_action_buttons_enabled(enabled_state: bool) -> void:
	for button in _action_buttons.values():
		if not button is Button:
			continue
		var action_button: Button = button
		action_button.disabled = not enabled_state
		_style_action_button(action_button, enabled_state)


func _on_action_button_pressed(action_id: String) -> void:
	if _is_loading:
		return

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("perform_action"):
		_set_status("连接中断，请稍后再试。")
		return

	var result: Dictionary = manager.perform_action(action_id)
	if not bool(result.get("success", false)):
		_set_status(str(result.get("error", "操作失败")))
		_refresh_view()
		return

	if bool(result.get("async", false)):
		_begin_loading_state(action_id)
	else:
		_set_status("新的动态已出现。")
		_refresh_view()
		_switch_to_page("feed")
		call_deferred("_scroll_feed_to_top")


func _on_action_started(action_id: String, _request_id: String) -> void:
	_begin_loading_state(action_id)


func _on_action_completed(action_id: String, entry: Dictionary) -> void:
	if action_id == _loading_action_id or _is_loading:
		_end_loading_state()
	_set_status(_build_completion_status(action_id, entry))
	_selected_entry_id = str(entry.get("entry_id", "")).strip_edges()
	_refresh_view()
	_switch_to_page("feed")
	call_deferred("_scroll_feed_to_top")


func _on_action_failed(action_id: String, error: String) -> void:
	if action_id == _loading_action_id and _is_loading:
		_set_status("网络有点慢，先看缓存内容…")
	else:
		_set_status("刷新中断，稍后再试。")
	if not error.strip_edges().is_empty():
		push_warning("CommunityApp action failed: %s" % error)


func _on_feed_updated() -> void:
	if not _is_loading:
		_render_actions()
		_render_feed()


func _on_runtime_state_changed(_arg1: Variant = null, _arg2: Variant = null) -> void:
	if _is_loading:
		return
	_render_actions()


func _build_completion_status(action_id: String, entry: Dictionary) -> String:
	var title: String = str(entry.get("title", "新动态")).strip_edges()
	var source_type: String = str(entry.get("source_type", "llm")).strip_edges()
	if title.is_empty():
		title = "新动态"
	var suffix: String = "（缓存）" if source_type == "fallback" else ""
	match action_id:
		"free_search":
			return "搜索结果已打开%s：%s" % [suffix, title]
		"random_search":
			return "随手刷到一条新帖%s：%s" % [suffix, title]
		"chill_browse":
			return "推荐刷新完成%s：%s" % [suffix, title]
		"learn_dev":
			return "开发笔记已打开%s：%s" % [suffix, title]
		"follow_contest":
			return "项目反馈已出现%s：%s" % [suffix, title]
		_:
			return "动态已更新%s：%s" % [suffix, title]


func _scroll_feed_to_top() -> void:
	if feed_scroll != null:
		feed_scroll.scroll_vertical = 0


func _begin_loading_state(action_id: String) -> void:
	if _is_loading and _loading_action_id == action_id:
		return
	_is_loading = true
	_loading_action_id = action_id
	_set_loading_visible(true)
	_render_loading_feed()
	_set_action_buttons_enabled(false)
	_set_status(_pick_loading_hint(action_id))
	call_deferred("_restart_loading_animation")


func _end_loading_state() -> void:
	_is_loading = false
	_loading_action_id = ""
	_stop_loading_animation()
	_set_loading_visible(false)


func _set_loading_visible(visible_state: bool) -> void:
	if feed_scroll != null:
		feed_scroll.visible = not visible_state
	if loading_view != null:
		loading_view.visible = visible_state


func _render_loading_feed() -> void:
	_clear_container(loading_list)
	for cycle in range(2):
		for index in range(LOADING_CARD_HEIGHTS.size()):
			loading_list.add_child(_build_loading_card(index + cycle * LOADING_CARD_HEIGHTS.size()))


func _build_loading_card(index: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, LOADING_CARD_HEIGHTS[index % LOADING_CARD_HEIGHTS.size()])
	panel.add_theme_stylebox_override("panel", _make_card_style(C_PANEL_BG, C_PANEL_BORDER, 10))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	body.add_child(top_row)
	top_row.add_child(_make_skeleton_circle(28, C_LOADING_LINE))
	top_row.add_child(_make_skeleton_block(92, 13, C_LOADING_LINE, 4))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	top_row.add_child(_make_skeleton_block(54, 11, C_LOADING_LINE_ALT, 4))

	if index % 2 == 0:
		body.add_child(_make_skeleton_block(0, 14, C_LOADING_LINE, 4, true, 0.68))

	body.add_child(_make_skeleton_block(0, 14, C_LOADING_LINE_ALT, 4, true, 0.88))
	body.add_child(_make_skeleton_block(0, 12, C_LOADING_LINE, 4, true, 0.96))
	body.add_child(_make_skeleton_block(0, 12, C_LOADING_LINE_ALT, 4, true, 0.62))

	if index % 3 != 1:
		body.add_child(_make_skeleton_block(0, 70 + float(index % 3) * 16.0, C_LOADING_BG, 8, true))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	body.add_child(footer)
	footer.add_child(_make_skeleton_block(52, 12, C_LOADING_LINE, 4))
	footer.add_child(_make_skeleton_block(46, 12, C_LOADING_LINE_ALT, 4))
	footer.add_child(_make_skeleton_block(58, 12, C_LOADING_LINE, 4))

	return panel


func _make_skeleton_circle(diameter: float, color_value: Color) -> Control:
	var block := PanelContainer.new()
	block.custom_minimum_size = Vector2(diameter, diameter)
	block.add_theme_stylebox_override("panel", _make_plain_style(color_value, int(diameter / 2.0)))
	return block


func _make_skeleton_block(
	width_value: float,
	height_value: float,
	color_value: Color,
	radius: int,
	expand_width: bool = false,
	width_ratio: float = 1.0
) -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var block := PanelContainer.new()
	block.custom_minimum_size = Vector2(width_value, height_value)
	block.add_theme_stylebox_override("panel", _make_plain_style(color_value, radius))

	if expand_width:
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.size_flags_stretch_ratio = maxf(0.01, width_ratio)
		wrapper.add_child(block)
		if width_ratio < 0.999:
			var right_spacer := Control.new()
			right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			right_spacer.size_flags_stretch_ratio = maxf(0.01, 1.0 - width_ratio)
			wrapper.add_child(right_spacer)
	else:
		wrapper.add_child(block)

	return wrapper


func _restart_loading_animation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _is_loading:
		return

	_stop_loading_animation()
	loading_scroll.scroll_vertical = 0
	var one_set_height: float = loading_list.size.y / 2.0
	if one_set_height <= 8.0:
		return
	_start_scroll_cycle(one_set_height)


func _start_scroll_cycle(set_height: float) -> void:
	if not _is_loading:
		return
	_stop_loading_animation()
	loading_scroll.scroll_vertical = 0
	var duration: float = maxf(2.8, set_height / 70.0)
	_loading_tween = create_tween()
	_loading_tween.tween_property(loading_scroll, "scroll_vertical", int(set_height), duration)
	_loading_tween.tween_callback(_start_scroll_cycle.bind(set_height))


func _stop_loading_animation() -> void:
	if _loading_tween != null and is_instance_valid(_loading_tween):
		_loading_tween.kill()
	_loading_tween = null
	if loading_scroll != null:
		loading_scroll.scroll_vertical = 0


func _pick_loading_hint(action_id: String) -> String:
	match action_id:
		"free_search":
			return "正在搜索相关帖子…"
		"random_search":
			return "正在随手刷新一条帖子…"
		"chill_browse":
			return "正在刷新今日推荐…"
		"learn_dev":
			return "正在打开开发笔记…"
		"follow_contest":
			return "笔记发布中，等待第一波反馈…"
		_:
			return LOADING_HINTS[abs(hash(action_id)) % LOADING_HINTS.size()]


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _add_empty_state(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", C_META)
	container.add_child(label)


func _make_card_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_plain_style(bg_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
