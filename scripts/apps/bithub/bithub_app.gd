class_name BithubApp
extends Control
## Bithub APP — 玩家可见的项目提交记录与里程碑版本入口。

const COLOR_BG := Color("#f6f8fa")
const COLOR_CARD := Color("#ffffff")
const COLOR_BORDER := Color("#d0d7de")
const COLOR_TEXT := Color("#24292f")
const COLOR_MUTED := Color("#57606a")
const COLOR_ACCENT := Color("#0969da")
const COLOR_GREEN := Color("#1a7f37")
const COLOR_GREEN_BG := Color("#dafbe1")

var _mode: String = "commits"
var _pending_milestone_id: String = ""

var _repo_title: Label
var _repo_meta: Label
var _commits_button: Button
var _milestones_button: Button
var _content_list: VBoxContainer
var _toast: PanelContainer
var _toast_title: Label
var _toast_body: Label
var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	_connect_manager()
	_refresh()


func _connect_manager() -> void:
	var manager: Node = _get_manager()
	if manager == null:
		return
	if manager.has_signal("repository_changed") and not manager.repository_changed.is_connected(_refresh):
		manager.repository_changed.connect(_refresh)
	if manager.has_signal("commit_recorded") and not manager.commit_recorded.is_connected(_on_commit_recorded):
		manager.commit_recorded.connect(_on_commit_recorded)
	if manager.has_signal("milestone_created") and not manager.milestone_created.is_connected(_on_milestone_created):
		manager.milestone_created.connect(_on_milestone_created)
	if manager.has_signal("milestone_play_started") and not manager.milestone_play_started.is_connected(_on_milestone_play_started):
		manager.milestone_play_started.connect(_on_milestone_play_started)
	if manager.has_signal("milestone_play_finished") and not manager.milestone_play_finished.is_connected(_on_milestone_play_finished):
		manager.milestone_play_finished.connect(_on_milestone_play_finished)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 34)
	root.add_theme_constant_override("margin_top", 26)
	root.add_theme_constant_override("margin_right", 34)
	root.add_theme_constant_override("margin_bottom", 28)
	add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	root.add_child(column)

	column.add_child(_create_repo_header())
	column.add_child(_create_tab_bar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_content_list = VBoxContainer.new()
	_content_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_content_list)

	_build_toast()
	_build_confirm_dialog()


func _create_repo_header() -> Control:
	var header := PanelContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_stylebox_override("panel", _panel_style(COLOR_CARD, 14, COLOR_BORDER))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	header.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)

	_repo_title = Label.new()
	_repo_title.add_theme_color_override("font_color", COLOR_TEXT)
	_repo_title.add_theme_font_size_override("font_size", 30)
	left.add_child(_repo_title)

	_repo_meta = Label.new()
	_repo_meta.add_theme_color_override("font_color", COLOR_MUTED)
	_repo_meta.add_theme_font_size_override("font_size", 17)
	left.add_child(_repo_meta)

	var branch := _create_pill("main", COLOR_GREEN_BG, COLOR_GREEN)
	branch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(branch)
	return header


func _create_tab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_commits_button = _create_tab_button("Commits")
	_milestones_button = _create_tab_button("Milestones")
	_commits_button.pressed.connect(func() -> void: _set_mode("commits"))
	_milestones_button.pressed.connect(func() -> void: _set_mode("milestones"))
	bar.add_child(_commits_button)
	bar.add_child(_milestones_button)
	return bar


func _create_tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(180, 44)
	btn.add_theme_font_size_override("font_size", 18)
	return btn


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_STOP
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.offset_left = -420
	_toast.offset_top = 24
	_toast.offset_right = -28
	_toast.offset_bottom = 132
	_toast.add_theme_stylebox_override("panel", _panel_style(COLOR_CARD, 14, COLOR_BORDER))
	add_child(_toast)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_toast.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	_toast_title = Label.new()
	_toast_title.add_theme_color_override("font_color", COLOR_TEXT)
	_toast_title.add_theme_font_size_override("font_size", 18)
	column.add_child(_toast_title)

	_toast_body = Label.new()
	_toast_body.add_theme_color_override("font_color", COLOR_MUTED)
	_toast_body.add_theme_font_size_override("font_size", 15)
	_toast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_toast_body)


func _build_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "运行里程碑版本"
	_confirm_dialog.dialog_text = "将打开试玩窗口，加载里程碑快照；关闭后恢复当前工程。"
	_confirm_dialog.confirmed.connect(_on_confirm_play_milestone)
	add_child(_confirm_dialog)


func _set_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	_refresh()


func _refresh() -> void:
	_update_header()
	_update_tabs()
	_clear_content()
	if _mode == "milestones":
		_render_milestones()
	else:
		_render_commits()


func _update_header() -> void:
	var project_name := "streaming_game"
	if StorageManager != null and StorageManager.current_project != null and "project_name" in StorageManager.current_project:
		project_name = str(StorageManager.current_project.project_name)
	_repo_title.text = "%s / %s" % [_get_player_handle(), project_name]

	var manager: Node = _get_manager()
	var commit_count: int = 0
	var milestone_count: int = 0
	var latest_text: String = "暂无推送"
	if manager != null:
		var commits: Array = manager.call("get_commits")
		var milestones: Array = manager.call("get_milestones")
		commit_count = commits.size()
		milestone_count = milestones.size()
		if not commits.is_empty() and commits[0] is Dictionary:
			latest_text = "最近推送：%s" % _format_relative_time(int((commits[0] as Dictionary).get("created_at", 0)))
	_repo_meta.text = "%s · %d commits · %d milestones" % [latest_text, commit_count, milestone_count]


func _update_tabs() -> void:
	_commits_button.button_pressed = _mode == "commits"
	_milestones_button.button_pressed = _mode == "milestones"


func _clear_content() -> void:
	for child in _content_list.get_children():
		child.queue_free()


func _render_commits() -> void:
	var manager: Node = _get_manager()
	var commits: Array = manager.call("get_commits") if manager != null else []
	if commits.is_empty():
		_show_empty("还没有推送；完成工单后会在这里留下记录。")
		return
	for commit in commits:
		if commit is Dictionary:
			_content_list.add_child(_create_commit_card(commit as Dictionary))


func _render_milestones() -> void:
	var manager: Node = _get_manager()
	var milestones: Array = manager.call("get_milestones") if manager != null else []
	if milestones.is_empty():
		_show_empty("正式试玩等里程碑出现后，你可以在这里玩到当时的版本。")
		return
	for milestone in milestones:
		if milestone is Dictionary:
			_content_list.add_child(_create_milestone_card(milestone as Dictionary))


func _show_empty(text: String) -> void:
	var empty_state := Label.new()
	empty_state.text = text
	empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_state.add_theme_color_override("font_color", COLOR_MUTED)
	empty_state.add_theme_font_size_override("font_size", 22)
	empty_state.custom_minimum_size.y = 420
	empty_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_list.add_child(empty_state)


func _create_commit_card(commit: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style(COLOR_CARD, 12, COLOR_BORDER))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	column.add_child(title_row)

	title_row.add_child(_create_pill(_short_hash(str(commit.get("commit_id", ""))), Color("#ddf4ff"), COLOR_ACCENT))

	var title := Label.new()
	title.text = str(commit.get("title", "完成一次开发提交"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.add_theme_font_size_override("font_size", 21)
	title_row.add_child(title)

	var body := Label.new()
	body.text = str(commit.get("message", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", COLOR_MUTED)
	body.add_theme_font_size_override("font_size", 17)
	column.add_child(body)

	var footer := Label.new()
	footer.text = "%s · %s" % [
		_format_relative_time(int(commit.get("created_at", 0))),
		_format_order_id(str(commit.get("order_id", ""))),
	]
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	footer.add_theme_font_size_override("font_size", 14)
	column.add_child(footer)
	return card


func _create_milestone_card(milestone: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style(COLOR_CARD, 12, COLOR_BORDER))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	row.add_child(info)

	var title := Label.new()
	title.text = str(milestone.get("name", "可玩里程碑"))
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.add_theme_font_size_override("font_size", 22)
	info.add_child(title)

	var details := Label.new()
	details.text = "tag %s · 快照 %s" % [
		_short_hash(str(milestone.get("milestone_id", ""))),
		_format_relative_time(int(milestone.get("created_at", 0))),
	]
	details.add_theme_color_override("font_color", COLOR_MUTED)
	details.add_theme_font_size_override("font_size", 16)
	info.add_child(details)

	var play_btn := Button.new()
	play_btn.text = "运行该版本"
	play_btn.custom_minimum_size = Vector2(160, 48)
	play_btn.add_theme_font_size_override("font_size", 17)
	play_btn.pressed.connect(func() -> void:
		_pending_milestone_id = str(milestone.get("milestone_id", ""))
		_confirm_dialog.popup_centered(Vector2(560, 220))
	)
	row.add_child(play_btn)
	return card


func _on_confirm_play_milestone() -> void:
	if _pending_milestone_id.is_empty():
		return
	var manager: Node = _get_manager()
	if manager == null or not manager.has_method("play_milestone"):
		_show_toast("无法运行", "BithubManager 不可用。")
		return
	var ok: bool = bool(manager.call("play_milestone", _pending_milestone_id))
	if not ok:
		_show_toast("无法运行", "里程碑快照加载失败。")


func _on_commit_recorded(commit: Dictionary) -> void:
	_refresh()
	_show_toast("main 有新推送", str(commit.get("title", "")))


func _on_milestone_created(milestone: Dictionary) -> void:
	_refresh()
	_show_toast("新增可玩里程碑", str(milestone.get("name", "")))


func _on_milestone_play_started(_milestone_id: String) -> void:
	_show_toast("正在运行里程碑", "已打开 Game Previewer。")


func _on_milestone_play_finished(_milestone_id: String) -> void:
	_show_toast("试玩结束", "已恢复当前工程。")


func _show_toast(title: String, body: String) -> void:
	_toast_title.text = title
	_toast_body.text = body
	_toast.visible = true
	_toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	tween.tween_interval(3.2)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void: _toast.visible = false)


func _create_pill(text: String, bg: Color, fg: Color) -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _panel_style(bg, 999, Color.TRANSPARENT))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 4)
	pill.add_child(margin)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", fg)
	label.add_theme_font_size_override("font_size", 14)
	margin.add_child(label)
	return pill


func _panel_style(bg: Color, radius: int, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	if border.a > 0.0:
		style.set_border_width_all(1)
		style.border_color = border
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


func _get_manager() -> Node:
	return get_node_or_null("/root/BithubManager")


func _get_player_handle() -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and "player_name" in gm:
		var player_name: String = str(gm.get("player_name")).strip_edges()
		if not player_name.is_empty():
			return "@%s" % player_name
	return "@player"


func _short_hash(value: String) -> String:
	if value.length() <= 6:
		return value
	return value.substr(maxi(0, value.length() - 6), 6)


func _format_order_id(order_id: String) -> String:
	if order_id.is_empty():
		return "WO-0000"
	return order_id.replace("wo_", "WO-")


func _format_relative_time(timestamp: int) -> String:
	if timestamp <= 0:
		return "刚刚"
	var delta: int = maxi(0, int(Time.get_unix_time_from_system()) - timestamp)
	if delta < 60:
		return "刚刚"
	if delta < 3600:
		return "%d 分钟前" % int(delta / 60.0)
	if delta < 86400:
		return "%d 小时前" % int(delta / 3600.0)
	return "%d 天前" % int(delta / 86400.0)
