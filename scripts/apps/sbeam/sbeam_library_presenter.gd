class_name SbeamLibraryPresenter
extends RefCounted


static func build_list_item(game: Dictionary, is_running: bool, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var left_margin := Control.new()
	left_margin.custom_minimum_size = Vector2(14, 0)
	left_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left_margin)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.color = Color("#a4d041") if is_running else Color("#5c6f7f")
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dot_center := CenterContainer.new()
	dot_center.custom_minimum_size = Vector2(6, 0)
	dot_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_center.add_child(dot)
	row.add_child(dot_center)

	var title_label := Label.new()
	title_label.text = str(game.get("title", "未命名"))
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title_label)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("#1a2940")
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)

	if on_pressed.is_valid():
		button.pressed.connect(func() -> void:
			on_pressed.call()
		)
	return button


static func apply_list_selection(buttons: Dictionary, selected_game_id: String) -> void:
	for gid: String in buttons:
		var btn: Button = buttons[gid]
		if btn == null or not is_instance_valid(btn):
			continue
		var is_selected: bool = gid == selected_game_id
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#1a3a5c") if is_selected else Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", style)
		if is_selected:
			style.border_color = Color("#66c0f4")
			style.set_border_width_all(0)
			style.border_width_left = 3


static func render_detail(
	container: VBoxContainer,
	game: Dictionary,
	is_running: bool,
	stats: Array,
	on_play_pressed: Callable
) -> Array[Label]:
	_clear_container(container)
	if container == null or game.is_empty():
		return []

	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(0, 200)
	banner.add_theme_stylebox_override("panel", _make_panel_style(Color("#0e1621"), 0))
	container.add_child(banner)

	var banner_margin := MarginContainer.new()
	banner_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_margin.add_theme_constant_override("margin_left", 36)
	banner_margin.add_theme_constant_override("margin_top", 32)
	banner_margin.add_theme_constant_override("margin_right", 36)
	banner_margin.add_theme_constant_override("margin_bottom", 32)
	banner.add_child(banner_margin)

	var banner_box := VBoxContainer.new()
	banner_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	banner_box.alignment = BoxContainer.ALIGNMENT_END
	banner_box.add_theme_constant_override("separation", 12)
	banner_margin.add_child(banner_box)

	var game_title := Label.new()
	game_title.text = str(game.get("title", "未命名"))
	game_title.add_theme_font_size_override("font_size", 36)
	game_title.add_theme_color_override("font_color", Color("#ffffff"))
	banner_box.add_child(game_title)

	var genre_label := Label.new()
	genre_label.text = str(game.get("genre", "小游戏"))
	genre_label.add_theme_font_size_override("font_size", 16)
	genre_label.add_theme_color_override("font_color", Color("#66c0f4"))
	banner_box.add_child(genre_label)

	var action_bar := PanelContainer.new()
	var action_bar_style := _make_panel_style(Color("#16202d"), 0)
	action_bar_style.border_color = Color("#2a3f5a")
	action_bar_style.set_border_width_all(0)
	action_bar_style.border_width_bottom = 1
	action_bar.add_theme_stylebox_override("panel", action_bar_style)
	container.add_child(action_bar)

	var action_margin := MarginContainer.new()
	action_margin.add_theme_constant_override("margin_left", 36)
	action_margin.add_theme_constant_override("margin_top", 16)
	action_margin.add_theme_constant_override("margin_right", 36)
	action_margin.add_theme_constant_override("margin_bottom", 16)
	action_bar.add_child(action_margin)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 16)
	action_margin.add_child(action_row)

	var play_button := Button.new()
	play_button.text = "切回窗口" if is_running else "▶ 开始游戏"
	play_button.custom_minimum_size = Vector2(180, 46)
	_apply_primary_button_style(play_button)
	if on_play_pressed.is_valid():
		play_button.pressed.connect(func() -> void:
			on_play_pressed.call()
		)
	action_row.add_child(play_button)

	var status_label := Label.new()
	if is_running:
		status_label.text = "● 运行中"
		status_label.add_theme_color_override("font_color", Color("#a4d041"))
	else:
		status_label.text = "已安装"
		status_label.add_theme_color_override("font_color", Color("#8f98a0"))
	status_label.add_theme_font_size_override("font_size", 15)
	var status_center := CenterContainer.new()
	status_center.add_child(status_label)
	action_row.add_child(status_center)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 36)
	info_margin.add_theme_constant_override("margin_top", 24)
	info_margin.add_theme_constant_override("margin_right", 36)
	info_margin.add_theme_constant_override("margin_bottom", 24)
	container.add_child(info_margin)

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 20)
	info_margin.add_child(info_box)

	var about_title := Label.new()
	about_title.text = "关于此游戏"
	about_title.add_theme_font_size_override("font_size", 20)
	about_title.add_theme_color_override("font_color", Color("#ffffff"))
	info_box.add_child(about_title)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color("#2a3f5a")
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_child(divider)

	var summary_label := Label.new()
	summary_label.text = str(game.get("summary", "暂无介绍。"))
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_font_size_override("font_size", 16)
	summary_label.add_theme_color_override("font_color", Color("#acb2b8"))
	info_box.add_child(summary_label)

	var meta_panel := PanelContainer.new()
	meta_panel.add_theme_stylebox_override("panel", _make_card_style(Color("#0e1621"), Color("#2a3f5a")))
	info_box.add_child(meta_panel)

	var meta_margin := MarginContainer.new()
	meta_margin.add_theme_constant_override("margin_left", 20)
	meta_margin.add_theme_constant_override("margin_top", 16)
	meta_margin.add_theme_constant_override("margin_right", 20)
	meta_margin.add_theme_constant_override("margin_bottom", 16)
	meta_panel.add_child(meta_margin)

	var meta_grid := GridContainer.new()
	meta_grid.columns = 2
	meta_grid.add_theme_constant_override("h_separation", 24)
	meta_grid.add_theme_constant_override("v_separation", 10)
	meta_margin.add_child(meta_grid)

	_add_meta_row(meta_grid, "类型", str(game.get("genre", "小游戏")))
	_add_meta_row(meta_grid, "操作", "方向键 / WASD")
	_add_meta_row(meta_grid, "来源", "SBEAM 游戏库")
	_add_meta_row(meta_grid, "价格", "免费")

	var value_labels: Array[Label] = []
	if not stats.is_empty():
		var score_section_title := Label.new()
		score_section_title.text = "游戏统计"
		score_section_title.add_theme_font_size_override("font_size", 20)
		score_section_title.add_theme_color_override("font_color", Color("#ffffff"))
		info_box.add_child(score_section_title)

		var score_divider := ColorRect.new()
		score_divider.custom_minimum_size = Vector2(0, 1)
		score_divider.color = Color("#2a3f5a")
		score_divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.add_child(score_divider)

		var score_row := HBoxContainer.new()
		score_row.add_theme_constant_override("separation", 16)
		info_box.add_child(score_row)

		for stat in stats:
			if not stat is Dictionary:
				continue
			var card := _build_score_stat_card(str(stat.get("label", "")), str(stat.get("value", "-")))
			score_row.add_child(card.get("panel"))
			value_labels.append(card.get("value_label"))

	return value_labels


static func _add_meta_row(grid: GridContainer, key: String, value: String) -> void:
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 14)
	key_label.add_theme_color_override("font_color", Color("#5c6f7f"))
	key_label.custom_minimum_size = Vector2(80, 0)
	grid.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	grid.add_child(value_label)


static func _build_score_stat_card(title: String, initial_value: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(Color("#0e1621"), Color("#2a3f5a")))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", Color("#5c6f7f"))
	box.add_child(title_label)

	var value_label := Label.new()
	value_label.text = initial_value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 24)
	value_label.add_theme_color_override("font_color", Color("#66c0f4"))
	box.add_child(value_label)

	return {"panel": panel, "value_label": value_label}


static func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


static func _apply_primary_button_style(button: Button) -> void:
	var normal := _make_panel_style(Color("#749c25"), 6)
	normal.content_margin_left = 14
	normal.content_margin_top = 10
	normal.content_margin_right = 14
	normal.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", normal)

	var hover := _make_panel_style(Color("#a4d041"), 6)
	hover.content_margin_left = 14
	hover.content_margin_top = 10
	hover.content_margin_right = 14
	hover.content_margin_bottom = 10
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("#d2efa9"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))


static func _make_panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


static func _make_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _make_panel_style(bg, 10)
	style.set_border_width_all(1)
	style.border_color = border
	return style
