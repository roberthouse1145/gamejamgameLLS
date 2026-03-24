class_name ShopCardBuilder
extends RefCounted
## 好买 UI 卡片工厂 — 纯静态工具类，不持有状态
## 负责构建商品卡片、订单卡片、库存卡片、生效卡片、评论卡片等 Control 节点

# ── 配色（与 ShopApp 保持一致）──────────────────────
const C_BG := Color("#F5F5F5")
const C_WHITE := Color("#FFFFFF")
const C_NAV := Color("#FF4D00")
const C_NAV_HOVER := Color("#FF6A2A")
const C_TEXT := Color("#333333")
const C_TEXT_SEC := Color("#999999")
const C_TEXT_LIGHT := Color("#BBBBBB")
const C_PRICE := Color("#FF4D00")
const C_BORDER := Color("#E8E8E8")
const C_TAG_BG := Color("#FFF4F0")
const C_TAG_TEXT := Color("#FF4D00")
const C_SUCCESS := Color("#52C41A")
const C_WARN := Color("#FAAD14")
const C_DISABLED_BG := Color("#F0F0F0")
const C_DISABLED_TEXT := Color("#CCCCCC")
const C_CARD_HOVER := Color("#FAFAFA")
const C_SELECTED := Color("#FFF7E6")
const C_SELECTED_BORDER := Color("#FF4D00")
const C_SHIPPING := Color("#1890FF")
const C_DELIVERED := Color("#52C41A")


# ══════════════════════════════════════════════════════
#  商品卡片
# ══════════════════════════════════════════════════════

static func build_product_card(item: Dictionary, selected: bool, on_click: Callable) -> Control:
	var card := MarginContainer.new()
	card.custom_minimum_size = Vector2(200, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = C_SELECTED if selected else C_WHITE
	card_style.border_color = C_SELECTED_BORDER if selected else C_BORDER
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(8)
	card_style.shadow_color = Color(0, 0, 0, 0.04)
	card_style.shadow_size = 4
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", card_style)
	card.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var cat_row := HBoxContainer.new()
	vbox.add_child(cat_row)
	cat_row.add_child(make_tag(category_text(str(item.get("category", "")))))

	var title := Label.new()
	title.text = str(item.get("title", ""))
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var full_desc: String = str(item.get("desc", ""))
	var first_line: String = full_desc.split("\n", false)[0] if not full_desc.is_empty() else ""
	var desc := Label.new()
	desc.text = first_line
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", C_TEXT_SEC)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(desc)

	var bottom := HBoxContainer.new()
	vbox.add_child(bottom)
	var price := Label.new()
	price.text = "¥%d" % int(item.get("price", 0))
	price.add_theme_font_size_override("font_size", 20)
	price.add_theme_color_override("font_color", C_PRICE)
	bottom.add_child(price)
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(bottom_spacer)
	var card_sales := Label.new()
	card_sales.text = "%s人付款" % format_sales_count(int(item.get("sales_count", 0)))
	card_sales.add_theme_font_size_override("font_size", 11)
	card_sales.add_theme_color_override("font_color", C_TEXT_LIGHT)
	card_sales.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(card_sales)

	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(on_click)
	panel.add_child(btn)

	return card


# ══════════════════════════════════════════════════════
#  订单卡片
# ══════════════════════════════════════════════════════

static func build_order_card(order: Dictionary) -> Control:
	var snapshot: Dictionary = order.get("item_snapshot", {})
	var status: String = str(order.get("status", ""))
	var is_shipping: bool = status == "shipping"

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = C_WHITE
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", s)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_bottom", 14)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title := Label.new()
	title.text = str(snapshot.get("title", "商品"))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", C_TEXT)
	info.add_child(title)

	var tracking := Label.new()
	tracking.text = str(order.get("tracking_text", ""))
	tracking.add_theme_font_size_override("font_size", 13)
	tracking.add_theme_color_override("font_color", C_SHIPPING if is_shipping else C_DELIVERED)
	info.add_child(tracking)

	var price_label := Label.new()
	price_label.text = "¥%d" % int(snapshot.get("price", 0))
	price_label.add_theme_font_size_override("font_size", 15)
	price_label.add_theme_color_override("font_color", C_PRICE)
	price_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price_label)

	var status_label := Label.new()
	status_label.text = "配送中" if is_shipping else "已送达"
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", C_SHIPPING if is_shipping else C_DELIVERED)
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status_label)

	return card


# ══════════════════════════════════════════════════════
#  库存卡片
# ══════════════════════════════════════════════════════

static func build_inv_card(item: Dictionary, on_action: Callable) -> Control:
	var state: String = str(item.get("state", "ready"))
	var used: bool = state == "gifted" or state == "consumed" or state == "equipped"

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = C_WHITE
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", s)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_bottom", 12)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title := Label.new()
	title.text = str(item.get("title", ""))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", C_TEXT if not used else C_TEXT_LIGHT)
	info.add_child(title)

	var meta := Label.new()
	meta.text = "%s · %s" % [state_text(state), effect_summary(str(item.get("effect_archetype", "")))]
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", C_TEXT_SEC)
	info.add_child(meta)

	if not used:
		var btn := Button.new()
		btn.text = inventory_action_label(item)
		btn.custom_minimum_size = Vector2(80, 32)
		_style_outline_btn_static(btn)
		btn.pressed.connect(on_action)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
	else:
		var state_lbl := Label.new()
		state_lbl.text = state_text(state)
		state_lbl.add_theme_font_size_override("font_size", 13)
		state_lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
		state_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(state_lbl)

	return card


# ══════════════════════════════════════════════════════
#  生效中卡片
# ══════════════════════════════════════════════════════

static func build_effect_card(effect: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#F6FFED")
	s.border_color = Color("#B7EB8F")
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", s)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_bottom", 10)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	m.add_child(row)

	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 10)
	dot.add_theme_color_override("font_color", C_SUCCESS)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var title := Label.new()
	title.text = str(effect.get("title", ""))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_TEXT)
	info.add_child(title)

	var summary := Label.new()
	summary.text = str(effect.get("summary", ""))
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", C_SUCCESS)
	info.add_child(summary)

	return card


# ══════════════════════════════════════════════════════
#  评论卡片
# ══════════════════════════════════════════════════════

static func build_review_card(comment: String, item: Dictionary, index: int) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var fake_rng := RandomNumberGenerator.new()
	fake_rng.seed = abs(hash("%s_review_%d" % [str(item.get("instance_id", item.get("item_id", ""))), index]))
	var usernames: PackedStringArray = ["小*花", "用***3", "匿名买家", "t***8", "爱*的猫", "夜***r", "买*狂", "懒*虫", "深*客", "咸*党"]
	var uname := usernames[fake_rng.randi_range(0, usernames.size() - 1)]

	var name_label := Label.new()
	name_label.text = uname
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", C_TEXT_SEC)
	header.add_child(name_label)

	var star_count: int = fake_rng.randi_range(4, 5)
	var stars_label := Label.new()
	stars_label.text = "★".repeat(star_count)
	stars_label.add_theme_font_size_override("font_size", 11)
	stars_label.add_theme_color_override("font_color", C_WARN)
	header.add_child(stars_label)

	var content := Label.new()
	content.text = comment
	content.add_theme_font_size_override("font_size", 13)
	content.add_theme_color_override("font_color", C_TEXT)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(content)

	return vbox


# ══════════════════════════════════════════════════════
#  通用 UI 工具
# ══════════════════════════════════════════════════════

static func make_tag(text: String) -> Control:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = C_TAG_BG
	s.set_corner_radius_all(4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", s)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", C_TAG_TEXT)
	panel.add_child(label)
	return panel


static func make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	return sep


static func empty_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", C_TEXT_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func style_primary_btn(btn: Button) -> void:
	var enabled: bool = not btn.disabled
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", C_WHITE if enabled else C_DISABLED_TEXT)
	btn.add_theme_color_override("font_hover_color", C_WHITE)
	btn.add_theme_color_override("font_pressed_color", C_WHITE)
	btn.add_theme_color_override("font_disabled_color", C_DISABLED_TEXT)
	btn.add_theme_stylebox_override("normal", _btn_style_flat(C_NAV if enabled else C_DISABLED_BG))
	btn.add_theme_stylebox_override("hover", _btn_style_flat(C_NAV_HOVER if enabled else C_DISABLED_BG))
	btn.add_theme_stylebox_override("pressed", _btn_style_flat(C_NAV_HOVER if enabled else C_DISABLED_BG))
	btn.add_theme_stylebox_override("disabled", _btn_style_flat(C_DISABLED_BG))


static func _style_outline_btn_static(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", C_NAV)
	btn.add_theme_color_override("font_hover_color", C_NAV_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_NAV_HOVER)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_WHITE
	normal.border_color = C_NAV
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = C_NAV_HOVER
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)


static func _btn_style_flat(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


# ══════════════════════════════════════════════════════
#  文本映射
# ══════════════════════════════════════════════════════

static func category_text(category: String) -> String:
	return ShopCatalogStaticData.get_category_display(category)


static func effect_summary(effect_id: String) -> String:
	return ShopCatalogStaticData.get_effect_display(effect_id)


static func state_text(state: String) -> String:
	return ShopCatalogStaticData.get_state_label(state)


static func inventory_action_label(item: Dictionary) -> String:
	var category: String = str(item.get("category", ""))
	var effect_id: String = str(item.get("effect_archetype", ""))
	if category == "gift":
		return "送给她"
	if effect_id == "flavor_no_effect":
		return "摆放"
	return "使用"


static func format_sales_count(count: int) -> String:
	if count >= 10000:
		return "%.1f万+" % (count / 10000.0)
	if count >= 1000:
		var rounded: int = floori(float(count) / 100.0) * 100
		return "%d+" % rounded
	return str(count)


static func format_stats_change(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	var stats: Dictionary = result.get("instant_stats", {})
	for key in stats.keys():
		var val: int = int(stats[key])
		if val == 0:
			continue
		var label: String = stat_label(str(key))
		parts.append("%s%+d" % [label, val])
	var modifiers: Array = result.get("persistent_modifiers", [])
	if not modifiers.is_empty() and parts.is_empty():
		for mod in modifiers:
			var mod_label: String = str((mod as Dictionary).get("label", ""))
			if not mod_label.is_empty():
				parts.append(mod_label)
				break
	return " ".join(parts)


static func stat_label(key: String) -> String:
	return ShopCatalogStaticData.get_stat_label(key)
