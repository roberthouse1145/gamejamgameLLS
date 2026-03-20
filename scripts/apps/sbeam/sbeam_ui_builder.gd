class_name SbeamUIBuilder
extends RefCounted


static func build_app_ui(target: Control, library_game_count: int, on_view_selected: Callable) -> Dictionary:
	var background := ColorRect.new()
	background.color = Color("#1b2838")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(root)

	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 78)
	top_bar.add_theme_stylebox_override("panel", _make_panel_style(Color("#171a21"), 0))
	root.add_child(top_bar)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 28)
	top_margin.add_theme_constant_override("margin_top", 14)
	top_margin.add_theme_constant_override("margin_right", 28)
	top_margin.add_theme_constant_override("margin_bottom", 14)
	top_bar.add_child(top_margin)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 18)
	top_margin.add_child(top_row)

	var logo_label := Label.new()
	logo_label.text = "SBEAM"
	logo_label.add_theme_font_size_override("font_size", 30)
	logo_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	top_row.add_child(logo_label)

	var store_nav_button := _build_nav_button("商店")
	store_nav_button.pressed.connect(func() -> void:
		if on_view_selected.is_valid():
			on_view_selected.call("store")
	)
	top_row.add_child(store_nav_button)

	var library_nav_button := _build_nav_button("游戏库")
	library_nav_button.pressed.connect(func() -> void:
		if on_view_selected.is_valid():
			on_view_selected.call("library")
	)
	top_row.add_child(library_nav_button)

	var community_nav_button := _build_nav_button("社区")
	community_nav_button.disabled = true
	top_row.add_child(community_nav_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	var user_info := VBoxContainer.new()
	user_info.alignment = BoxContainer.ALIGNMENT_CENTER
	user_info.add_theme_constant_override("separation", 2)
	top_row.add_child(user_info)

	var status_label := Label.new()
	status_label.text = "在线"
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color("#66c0f4"))
	user_info.add_child(status_label)

	var money_label := Label.new()
	money_label.add_theme_font_size_override("font_size", 14)
	money_label.add_theme_color_override("font_color", Color("#8f98a0"))
	user_info.add_child(money_label)

	var main_margin := MarginContainer.new()
	main_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.add_theme_constant_override("margin_left", 28)
	main_margin.add_theme_constant_override("margin_top", 20)
	main_margin.add_theme_constant_override("margin_right", 28)
	main_margin.add_theme_constant_override("margin_bottom", 20)
	root.add_child(main_margin)

	var content_stack := Control.new()
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.add_child(content_stack)

	var refs: Dictionary = {
		"store_nav_button": store_nav_button,
		"library_nav_button": library_nav_button,
		"community_nav_button": community_nav_button,
		"status_label": status_label,
		"money_label": money_label,
	}

	var store_view := build_store_view()
	var store_content: Control = store_view.get("store_content")
	store_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_stack.add_child(store_content)
	refs.merge(store_view, true)

	var library_view := build_library_view(library_game_count)
	var library_content: Control = library_view.get("library_content")
	library_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_stack.add_child(library_content)
	refs.merge(library_view, true)

	var notice_label := Label.new()
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", 14)
	notice_label.add_theme_color_override("font_color", Color("#8f98a0"))
	notice_label.text = ""
	root.add_child(_wrap_notice(notice_label))
	refs["notice_label"] = notice_label

	return refs


static func build_store_view() -> Dictionary:
	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 22)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(300, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_stylebox_override("panel", _make_panel_style(Color("#16202d"), 10))
	content_row.add_child(sidebar)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar_margin.add_theme_constant_override("margin_left", 16)
	sidebar_margin.add_theme_constant_override("margin_top", 16)
	sidebar_margin.add_theme_constant_override("margin_right", 16)
	sidebar_margin.add_theme_constant_override("margin_bottom", 16)
	sidebar.add_child(sidebar_margin)

	var sidebar_box := VBoxContainer.new()
	sidebar_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_box.add_theme_constant_override("separation", 12)
	sidebar_margin.add_child(sidebar_box)

	var filter_label := Label.new()
	filter_label.text = "本周推荐"
	filter_label.add_theme_font_size_override("font_size", 20)
	filter_label.add_theme_color_override("font_color", Color("#ffffff"))
	sidebar_box.add_child(filter_label)

	var game_list := ItemList.new()
	game_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_list.select_mode = ItemList.SELECT_SINGLE
	game_list.allow_reselect = true
	game_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	game_list.add_theme_color_override("font_color", Color("#8f98a0"))
	game_list.add_theme_color_override("font_selected_color", Color("#ffffff"))
	game_list.add_theme_font_size_override("font_size", 16)
	sidebar_box.add_child(game_list)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_child(detail_scroll)

	var detail_box := VBoxContainer.new()
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.add_theme_constant_override("separation", 16)
	detail_scroll.add_child(detail_box)

	var detail_title := Label.new()
	detail_title.add_theme_font_size_override("font_size", 32)
	detail_title.add_theme_color_override("font_color", Color("#ffffff"))
	detail_box.add_child(detail_title)

	var hero_panel := PanelContainer.new()
	hero_panel.custom_minimum_size = Vector2(0, 220)
	hero_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#0f1923"), 12))
	detail_box.add_child(hero_panel)

	var hero_margin := MarginContainer.new()
	hero_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_margin.add_theme_constant_override("margin_left", 20)
	hero_margin.add_theme_constant_override("margin_top", 20)
	hero_margin.add_theme_constant_override("margin_right", 20)
	hero_margin.add_theme_constant_override("margin_bottom", 20)
	hero_panel.add_child(hero_margin)

	var hero_box := VBoxContainer.new()
	hero_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_box.add_theme_constant_override("separation", 10)
	hero_margin.add_child(hero_box)

	var detail_pitch := Label.new()
	detail_pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_pitch.add_theme_font_size_override("font_size", 18)
	detail_pitch.add_theme_color_override("font_color", Color("#c6d4df"))
	hero_box.add_child(detail_pitch)

	var detail_meta := Label.new()
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_meta.add_theme_font_size_override("font_size", 14)
	detail_meta.add_theme_color_override("font_color", Color("#8f98a0"))
	hero_box.add_child(detail_meta)

	var tag_title := Label.new()
	tag_title.text = "热门标签"
	tag_title.add_theme_font_size_override("font_size", 18)
	tag_title.add_theme_color_override("font_color", Color("#ffffff"))
	detail_box.add_child(tag_title)

	var tags_container := HFlowContainer.new()
	tags_container.add_theme_constant_override("h_separation", 8)
	tags_container.add_theme_constant_override("v_separation", 8)
	detail_box.add_child(tags_container)

	var hook_panel := PanelContainer.new()
	hook_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#111923"), 12))
	detail_box.add_child(hook_panel)

	var hook_margin := MarginContainer.new()
	hook_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hook_margin.add_theme_constant_override("margin_left", 18)
	hook_margin.add_theme_constant_override("margin_top", 16)
	hook_margin.add_theme_constant_override("margin_right", 18)
	hook_margin.add_theme_constant_override("margin_bottom", 16)
	hook_panel.add_child(hook_margin)

	var detail_hook := Label.new()
	detail_hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_hook.add_theme_font_size_override("font_size", 16)
	detail_hook.add_theme_color_override("font_color", Color("#c6d4df"))
	hook_margin.add_child(detail_hook)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	detail_box.add_child(action_row)

	var price_panel := PanelContainer.new()
	price_panel.custom_minimum_size = Vector2(128, 44)
	price_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#000000"), 8))
	action_row.add_child(price_panel)

	var price_margin := MarginContainer.new()
	price_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	price_margin.add_theme_constant_override("margin_left", 16)
	price_margin.add_theme_constant_override("margin_right", 16)
	price_margin.add_theme_constant_override("margin_top", 10)
	price_margin.add_theme_constant_override("margin_bottom", 10)
	price_panel.add_child(price_margin)

	var buy_price_label := Label.new()
	buy_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_price_label.add_theme_font_size_override("font_size", 18)
	buy_price_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	price_margin.add_child(buy_price_label)

	var start_button := Button.new()
	start_button.text = "一起开玩"
	start_button.custom_minimum_size = Vector2(180, 44)
	_apply_primary_button_style(start_button)
	action_row.add_child(start_button)

	var reviews_title := Label.new()
	reviews_title.text = "最有价值的评测"
	reviews_title.add_theme_font_size_override("font_size", 18)
	reviews_title.add_theme_color_override("font_color", Color("#ffffff"))
	detail_box.add_child(reviews_title)

	var user_reviews_container := VBoxContainer.new()
	user_reviews_container.add_theme_constant_override("separation", 14)
	detail_box.add_child(user_reviews_container)

	return {
		"store_content": content_row,
		"game_list": game_list,
		"detail_title": detail_title,
		"detail_pitch": detail_pitch,
		"detail_meta": detail_meta,
		"detail_hook": detail_hook,
		"tags_container": tags_container,
		"buy_price_label": buy_price_label,
		"start_button": start_button,
		"user_reviews_container": user_reviews_container,
	}


static func build_library_view(library_game_count: int) -> Dictionary:
	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(240, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar_style := _make_panel_style(Color("#0e1621"), 0)
	sidebar_style.border_color = Color("#2a3f5a")
	sidebar_style.set_border_width_all(0)
	sidebar_style.border_width_right = 1
	sidebar.add_theme_stylebox_override("panel", sidebar_style)
	root.add_child(sidebar)

	var sidebar_vbox := VBoxContainer.new()
	sidebar_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar_vbox.add_theme_constant_override("separation", 0)
	sidebar.add_child(sidebar_vbox)

	var sidebar_header := PanelContainer.new()
	sidebar_header.custom_minimum_size = Vector2(0, 48)
	var header_style := _make_panel_style(Color("#0e1621"), 0)
	header_style.border_color = Color("#2a3f5a")
	header_style.set_border_width_all(0)
	header_style.border_width_bottom = 1
	sidebar_header.add_theme_stylebox_override("panel", header_style)
	sidebar_vbox.add_child(sidebar_header)

	var header_margin := MarginContainer.new()
	header_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_margin.add_theme_constant_override("margin_left", 16)
	header_margin.add_theme_constant_override("margin_right", 16)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	sidebar_header.add_child(header_margin)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_margin.add_child(header_row)

	var sidebar_title := Label.new()
	sidebar_title.text = "全部游戏"
	sidebar_title.add_theme_font_size_override("font_size", 15)
	sidebar_title.add_theme_color_override("font_color", Color("#8f98a0"))
	sidebar_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(sidebar_title)

	var count_label := Label.new()
	count_label.text = str(library_game_count)
	count_label.add_theme_font_size_override("font_size", 13)
	count_label.add_theme_color_override("font_color", Color("#5c6f7f"))
	header_row.add_child(count_label)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_vbox.add_child(list_scroll)

	var library_cards_root := VBoxContainer.new()
	library_cards_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_cards_root.add_theme_constant_override("separation", 0)
	list_scroll.add_child(library_cards_root)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#1b2838"), 0))
	root.add_child(detail_panel)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(detail_scroll)

	var detail_content := VBoxContainer.new()
	detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_content.add_theme_constant_override("separation", 0)
	detail_scroll.add_child(detail_content)

	return {
		"library_content": root,
		"library_cards_root": library_cards_root,
		"library_detail_root": detail_content,
	}


static func build_download_window_content(game: Dictionary, download_stages: Array[String]) -> Dictionary:
	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(560, 260)
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color("#1b2838"), 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title_label := Label.new()
	title_label.text = str(game.get("title", "未命名作品"))
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	box.add_child(title_label)

	var stage_label := Label.new()
	stage_label.text = download_stages[0] if not download_stages.is_empty() else ""
	stage_label.add_theme_font_size_override("font_size", 14)
	stage_label.add_theme_color_override("font_color", Color("#66c0f4"))
	box.add_child(stage_label)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 14)
	progress_bar.add_theme_stylebox_override("background", _make_card_style(Color("#0e1621"), Color("#2a3f5a")))
	progress_bar.add_theme_stylebox_override("fill", _make_panel_style(Color("#1a9fff"), 3))
	box.add_child(progress_bar)

	var details := Label.new()
	details.text = "下载速度 %.1f MB/s · 磁盘可用 %d GB" % [randf_range(12.0, 48.0), randi_range(120, 500)]
	details.add_theme_font_size_override("font_size", 13)
	details.add_theme_color_override("font_color", Color("#8f98a0"))
	box.add_child(details)

	return {
		"root": outer,
		"title_label": title_label,
		"stage_label": stage_label,
		"progress_bar": progress_bar,
	}


static func _build_nav_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	return button


static func _wrap_notice(label: Label) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_child(label)
	return margin


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
