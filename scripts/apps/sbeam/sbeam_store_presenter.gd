class_name SbeamStorePresenter
extends RefCounted


static func render_empty_state(refs: Dictionary) -> void:
	var detail_title: Label = refs.get("detail_title")
	var detail_pitch: Label = refs.get("detail_pitch")
	var detail_meta: Label = refs.get("detail_meta")
	var detail_hook: Label = refs.get("detail_hook")
	var buy_price_label: Label = refs.get("buy_price_label")
	var tags_container: Node = refs.get("tags_container")
	var user_reviews_container: Node = refs.get("user_reviews_container")

	if detail_title != null:
		detail_title.text = "没有找到产品"
	if detail_pitch != null:
		detail_pitch.text = "此处暂无可显示的内容。"
	if detail_meta != null:
		detail_meta.text = "-"
	if detail_hook != null:
		detail_hook.text = ""
	if buy_price_label != null:
		buy_price_label.text = "¥ 0"

	_clear_container(tags_container)
	_clear_container(user_reviews_container)


static func render_game_detail(refs: Dictionary, entry: Dictionary) -> void:
	var detail_title: Label = refs.get("detail_title")
	var detail_pitch: Label = refs.get("detail_pitch")
	var detail_meta: Label = refs.get("detail_meta")
	var detail_hook: Label = refs.get("detail_hook")
	var buy_price_label: Label = refs.get("buy_price_label")

	if detail_title != null:
		detail_title.text = str(entry.get("title", "未命名作品"))
	if detail_pitch != null:
		detail_pitch.text = str(entry.get("pitch", ""))
	if detail_meta != null:
		detail_meta.text = "\n".join([
			"最近评测：%s" % str(entry.get("recent_reviews_summary", "无评测")),
			"全部评测：%s" % str(entry.get("all_reviews_summary", "无评测")),
			"发行日期：%s" % str(entry.get("release_date", "未知")),
			"开发商：%s" % str(entry.get("publisher", "未知开发商")),
			"类型：%s" % str(entry.get("genre", "未知类型")),
		])
	if detail_hook != null:
		detail_hook.text = str(entry.get("hook_moment", "看起来很有趣。"))
	if buy_price_label != null:
		buy_price_label.text = "¥ %d" % _get_purchase_cost(entry)

	_build_user_reviews(refs.get("user_reviews_container"), entry.get("user_reviews", []))


static func _get_purchase_cost(entry: Dictionary) -> int:
	var rewards: Dictionary = entry.get("rewards", {}) as Dictionary
	return maxi(0, -int(rewards.get("money", 0)))


static func _build_tags(tags_container: HFlowContainer, tags: Array) -> void:
	_clear_container(tags_container)
	if tags_container == null:
		return

	for tag in tags:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _make_panel_style(Color("#111923"), 8))
		tags_container.add_child(chip)

		var chip_margin := MarginContainer.new()
		chip_margin.add_theme_constant_override("margin_left", 8)
		chip_margin.add_theme_constant_override("margin_top", 4)
		chip_margin.add_theme_constant_override("margin_right", 8)
		chip_margin.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(chip_margin)

		var chip_label := Label.new()
		chip_label.text = str(tag)
		chip_label.add_theme_font_size_override("font_size", 13)
		chip_label.add_theme_color_override("font_color", Color("#66c0f4"))
		chip_margin.add_child(chip_label)


static func _build_user_reviews(user_reviews_container: VBoxContainer, reviews: Array) -> void:
	_clear_container(user_reviews_container)
	if user_reviews_container == null:
		return

	if reviews.is_empty():
		var empty_label := Label.new()
		empty_label.text = "目前还没有玩家撰写评测。"
		empty_label.add_theme_font_size_override("font_size", 15)
		empty_label.add_theme_color_override("font_color", Color("#8f98a0"))
		user_reviews_container.add_child(empty_label)
		return

	for review_data in reviews:
		if not review_data is Dictionary:
			continue

		var review: Dictionary = review_data
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _make_card_style(Color("#16202d"), Color("#2a3f5a")))
		user_reviews_container.add_child(panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_top", 14)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_bottom", 14)
		panel.add_child(margin)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		margin.add_child(box)

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		box.add_child(header)

		var user_label := Label.new()
		user_label.text = "%s · 拥有 %d 项产品" % [
			str(review.get("user", "匿名玩家")),
			int(review.get("owned_products", 1))
		]
		user_label.add_theme_font_size_override("font_size", 14)
		user_label.add_theme_color_override("font_color", Color("#e7e7e7"))
		header.add_child(user_label)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)

		var hours_label := Label.new()
		hours_label.text = "总时数：%s 小时" % str(review.get("hours", "0.0"))
		hours_label.add_theme_font_size_override("font_size", 12)
		hours_label.add_theme_color_override("font_color", Color("#8f98a0"))
		header.add_child(hours_label)

		var recommend_label := Label.new()
		recommend_label.text = "推荐" if bool(review.get("is_recommended", true)) else "不推荐"
		recommend_label.add_theme_font_size_override("font_size", 14)
		recommend_label.add_theme_color_override("font_color", Color("#66c0f4") if bool(review.get("is_recommended", true)) else Color("#d96c6c"))
		box.add_child(recommend_label)

		var body_label := Label.new()
		body_label.text = str(review.get("review", ""))
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.add_theme_font_size_override("font_size", 15)
		body_label.add_theme_color_override("font_color", Color("#acb2b8"))
		box.add_child(body_label)

		var helpful_label := Label.new()
		helpful_label.text = "%d 人认为这篇评测有价值" % int(review.get("upvotes", 0))
		helpful_label.add_theme_font_size_override("font_size", 12)
		helpful_label.add_theme_color_override("font_color", Color("#8f98a0"))
		box.add_child(helpful_label)


static func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


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
