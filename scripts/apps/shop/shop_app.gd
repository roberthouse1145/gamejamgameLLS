class_name ShopApp
extends Control
## 好买 —— 仿电商平台 UI（主框架）
## 卡片构建委托给 ShopCardBuilder

# ── 状态 ──────────────────────────────────────────────
var _shop: Node = null
var _gm: Node = null
var _gl: Node = null

var _current_tab: int = 0  # 0=商品 1=订单 2=背包
var _selected_item_id: String = ""
var _detail_visible: bool = false

# ── 节点引用 ──────────────────────────────────────────
var _nav_tabs: Array[Button] = []
var _wallet_label: Label = null
var _toast_label: Label = null
var _body_stack: Array[Control] = []
var _grid: GridContainer = null
var _orders_box: VBoxContainer = null
var _inventory_box: VBoxContainer = null
var _detail_panel: PanelContainer = null
var _detail_title: Label = null
var _detail_subtitle: Label = null
var _detail_price: Label = null
var _detail_meta: Label = null
var _detail_desc: RichTextLabel = null
var _detail_comments_box: VBoxContainer = null
var _detail_tags: HFlowContainer = null
var _detail_buy_btn: Button = null
var _detail_close_btn: Button = null
var _detail_seller: Label = null
var _detail_rating_row: HBoxContainer = null
var _toast_timer: Timer = null
var _detail_tween: Tween = null
var _tab_tween: Tween = null


func _ready() -> void:
	_shop = get_node_or_null("/root/ShopManager")
	_gm = get_node_or_null("/root/GameManager")
	_gl = get_node_or_null("/root/GameLoopManager")
	_build_ui()
	_connect_signals()
	_switch_tab(0)
	_refresh_all()


# ══════════════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = ShopCardBuilder.C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_nav_bar())

	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 36)
	body_margin.add_theme_constant_override("margin_top", 24)
	body_margin.add_theme_constant_override("margin_right", 36)
	body_margin.add_theme_constant_override("margin_bottom", 24)
	root.add_child(body_margin)

	var body_hbox := HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 24)
	body_margin.add_child(body_hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_child(left)

	var shop_page := _build_shop_page()
	shop_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(shop_page)
	_body_stack.append(shop_page)

	var orders_page := _build_orders_page()
	orders_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orders_page.visible = false
	left.add_child(orders_page)
	_body_stack.append(orders_page)

	var inv_page := _build_inventory_page()
	inv_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_page.visible = false
	left.add_child(inv_page)
	_body_stack.append(inv_page)

	_detail_panel = _build_detail_panel()
	_detail_panel.visible = false
	_detail_panel.custom_minimum_size = Vector2(520, 0)
	body_hbox.add_child(_detail_panel)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 3.0
	_toast_timer.timeout.connect(_hide_toast)
	add_child(_toast_timer)


func _build_nav_bar() -> Control:
	var nav := PanelContainer.new()
	nav.custom_minimum_size = Vector2(0, 80)
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = ShopCardBuilder.C_WHITE
	nav_style.border_color = ShopCardBuilder.C_BORDER
	nav_style.border_width_bottom = 1
	nav.add_theme_stylebox_override("panel", nav_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	nav.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(row)

	var logo := Label.new()
	logo.text = "好买"
	logo.add_theme_font_size_override("font_size", 40)
	logo.add_theme_color_override("font_color", ShopCardBuilder.C_NAV)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(logo)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(48, 0)
	row.add_child(spacer1)

	var tab_names: PackedStringArray = ["今日推荐", "我的订单", "我的物品"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.flat = true
		btn.custom_minimum_size = Vector2(130, 80)
		btn.add_theme_font_size_override("font_size", 24)
		btn.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
		btn.add_theme_color_override("font_hover_color", ShopCardBuilder.C_NAV)
		btn.add_theme_color_override("font_pressed_color", ShopCardBuilder.C_NAV)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_pressed.bind(i))
		row.add_child(btn)
		_nav_tabs.append(btn)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)

	_toast_label = Label.new()
	_toast_label.text = ""
	_toast_label.add_theme_font_size_override("font_size", 20)
	_toast_label.add_theme_color_override("font_color", ShopCardBuilder.C_SUCCESS)
	_toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_toast_label)

	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(24, 0)
	row.add_child(spacer3)

	_wallet_label = Label.new()
	_wallet_label.add_theme_font_size_override("font_size", 24)
	_wallet_label.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT)
	_wallet_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_wallet_label)

	return nav


func _build_shop_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 24)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	return scroll


func _build_orders_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orders_box = VBoxContainer.new()
	_orders_box.add_theme_constant_override("separation", 18)
	_orders_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_orders_box)
	return scroll


func _build_inventory_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var inv_header := Label.new()
	inv_header.text = "全部物品"
	inv_header.add_theme_font_size_override("font_size", 26)
	inv_header.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT)
	vbox.add_child(inv_header)

	_inventory_box = VBoxContainer.new()
	_inventory_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_inventory_box)

	return scroll


func _build_detail_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ShopCardBuilder.C_WHITE
	style.border_color = ShopCardBuilder.C_BORDER
	style.border_width_left = 1
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# 关闭按钮行
	var close_row := HBoxContainer.new()
	vbox.add_child(close_row)
	var close_spacer := Control.new()
	close_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(close_spacer)
	_detail_close_btn = Button.new()
	_detail_close_btn.text = "✕"
	_detail_close_btn.flat = true
	_detail_close_btn.add_theme_font_size_override("font_size", 28)
	_detail_close_btn.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
	_detail_close_btn.add_theme_color_override("font_hover_color", ShopCardBuilder.C_TEXT)
	_detail_close_btn.focus_mode = Control.FOCUS_NONE
	_detail_close_btn.pressed.connect(_close_detail)
	close_row.add_child(_detail_close_btn)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 32)
	_detail_title.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_title)

	_detail_subtitle = Label.new()
	_detail_subtitle.add_theme_font_size_override("font_size", 20)
	_detail_subtitle.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
	_detail_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_subtitle)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 18)
	vbox.add_child(price_row)
	_detail_price = Label.new()
	_detail_price.add_theme_font_size_override("font_size", 44)
	_detail_price.add_theme_color_override("font_color", ShopCardBuilder.C_PRICE)
	price_row.add_child(_detail_price)
	var price_spacer := Control.new()
	price_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(price_spacer)
	_detail_rating_row = HBoxContainer.new()
	_detail_rating_row.add_theme_constant_override("separation", 6)
	_detail_rating_row.size_flags_vertical = Control.SIZE_SHRINK_END
	price_row.add_child(_detail_rating_row)

	vbox.add_child(ShopCardBuilder.make_separator())

	_detail_seller = Label.new()
	_detail_seller.add_theme_font_size_override("font_size", 18)
	_detail_seller.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
	vbox.add_child(_detail_seller)

	_detail_meta = Label.new()
	_detail_meta.add_theme_font_size_override("font_size", 20)
	_detail_meta.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_meta)

	_detail_tags = HFlowContainer.new()
	_detail_tags.add_theme_constant_override("h_separation", 10)
	_detail_tags.add_theme_constant_override("v_separation", 10)
	vbox.add_child(_detail_tags)

	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = false
	_detail_desc.fit_content = true
	_detail_desc.scroll_active = false
	_detail_desc.add_theme_font_size_override("normal_font_size", 22)
	_detail_desc.add_theme_color_override("default_color", ShopCardBuilder.C_TEXT)
	vbox.add_child(_detail_desc)

	vbox.add_child(ShopCardBuilder.make_separator())

	var comments_header := HBoxContainer.new()
	comments_header.add_theme_constant_override("separation", 12)
	vbox.add_child(comments_header)
	var ch_label := Label.new()
	ch_label.text = "宝贝评价"
	ch_label.add_theme_font_size_override("font_size", 24)
	ch_label.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT)
	comments_header.add_child(ch_label)

	_detail_comments_box = VBoxContainer.new()
	_detail_comments_box.add_theme_constant_override("separation", 16)
	vbox.add_child(_detail_comments_box)

	_detail_buy_btn = Button.new()
	_detail_buy_btn.text = "立即购买"
	_detail_buy_btn.custom_minimum_size = Vector2(0, 60)
	ShopCardBuilder.style_primary_btn(_detail_buy_btn)
	_detail_buy_btn.pressed.connect(_on_buy_pressed)
	vbox.add_child(_detail_buy_btn)

	return panel


# ══════════════════════════════════════════════════════
#  数据刷新
# ══════════════════════════════════════════════════════

func _connect_signals() -> void:
	if _shop != null:
		_shop.catalog_refreshed.connect(_on_shop_changed)
		_shop.catalog_generation_started.connect(_on_generation_started)
		_shop.catalog_generation_failed.connect(_on_generation_failed)
		_shop.purchase_completed.connect(_on_purchase_completed)
		_shop.delivery_arrived.connect(_on_delivery_arrived)
		_shop.inventory_changed.connect(_on_shop_changed)
		_shop.active_effects_changed.connect(_on_shop_changed)
	if _gm != null and _gm.has_signal("money_changed"):
		_gm.money_changed.connect(_on_money_changed)
	if _gl != null and _gl.has_signal("day_changed"):
		_gl.day_changed.connect(_on_day_changed)


func _refresh_all() -> void:
	_refresh_wallet()
	_refresh_grid()
	_refresh_orders()
	_refresh_inventory()
	_refresh_detail()


func _refresh_wallet() -> void:
	var money: int = int(_gm.get("money")) if _gm != null else 0
	var day: int = int(_gl.get("current_day")) if _gl != null else 1
	_wallet_label.text = "第%d天 · 余额 ￥%d" % [day, money]


func _refresh_grid() -> void:
	_clear_children(_grid)
	var items: Array = _shop.get_catalog() if _shop != null else []
	if _selected_item_id.is_empty() and not items.is_empty():
		_selected_item_id = str((items[0] as Dictionary).get("instance_id", ""))
	for raw_item in items:
		var item: Dictionary = raw_item as Dictionary
		var iid: String = str(item.get("instance_id", ""))
		_grid.add_child(ShopCardBuilder.build_product_card(item, iid == _selected_item_id, _on_item_selected.bind(iid)))


func _refresh_orders() -> void:
	_clear_children(_orders_box)
	var orders: Array = _shop.get_orders() if _shop != null else []
	if orders.is_empty():
		_orders_box.add_child(ShopCardBuilder.empty_hint("还没有订单，去逛逛吧"))
		return
	for i in range(orders.size() - 1, -1, -1):
		_orders_box.add_child(ShopCardBuilder.build_order_card(orders[i] as Dictionary))


func _refresh_inventory() -> void:
	_clear_children(_inventory_box)
	var inv: Array = _shop.get_inventory() if _shop != null else []
	if inv.is_empty():
		_inventory_box.add_child(ShopCardBuilder.empty_hint("背包空空如也"))
		return
	for raw_item in inv:
		var item: Dictionary = raw_item as Dictionary
		_inventory_box.add_child(ShopCardBuilder.build_inv_card(item, _on_inventory_action_pressed.bind(
			str(item.get("inventory_id", "")),
			str(item.get("category", ""))
		)))


func _refresh_detail() -> void:
	if not _detail_visible:
		return
	var item := _find_selected_catalog_item()
	if item.is_empty():
		_close_detail()
		return

	_detail_title.text = str(item.get("title", ""))
	_detail_subtitle.text = str(item.get("subtitle", ""))
	_detail_price.text = "￥%d" % int(item.get("price", 0))

	_detail_meta.text = "%s · %s" % [
		ShopCardBuilder.category_text(str(item.get("category", ""))),
		ShopCardBuilder.item_effect_summary(item),
	]

	_detail_desc.text = str(item.get("desc", ""))

	_clear_children(_detail_tags)
	for raw_tag in item.get("tags", []):
		_detail_tags.add_child(ShopCardBuilder.make_tag(str(raw_tag)))

	# 评分 + 已售
	_clear_children(_detail_rating_row)
	var rating: float = float(item.get("rating", 4.8))
	var full_stars: int = int(rating)
	for _i in range(full_stars):
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 20)
		star.add_theme_color_override("font_color", ShopCardBuilder.C_WARN)
		_detail_rating_row.add_child(star)
	if rating - full_stars >= 0.5:
		var half_star := Label.new()
		half_star.text = "★"
		half_star.add_theme_font_size_override("font_size", 20)
		half_star.add_theme_color_override("font_color", Color("#FFD700", 0.5))
		_detail_rating_row.add_child(half_star)
	var rating_num := Label.new()
	rating_num.text = " %.1f" % rating
	rating_num.add_theme_font_size_override("font_size", 20)
	rating_num.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
	_detail_rating_row.add_child(rating_num)
	var sales_label := Label.new()
	sales_label.text = "  已售%s" % ShopCardBuilder.format_sales_count(int(item.get("sales_count", 0)))
	sales_label.add_theme_font_size_override("font_size", 20)
	sales_label.add_theme_color_override("font_color", ShopCardBuilder.C_TEXT_SEC)
	_detail_rating_row.add_child(sales_label)

	_detail_seller.text = "店铺：%s" % str(item.get("seller_name", "好买自营"))

	_clear_children(_detail_comments_box)
	var comments_arr: Array = item.get("user_comments", [])
	for ci in range(comments_arr.size()):
		_detail_comments_box.add_child(ShopCardBuilder.build_review_card(str(comments_arr[ci]), item, ci))

	var can_buy: bool = _gm != null and int(_gm.get("money")) >= int(item.get("price", 0))
	var already_bought: bool = _shop != null and _shop.has_purchased_item(str(item.get("instance_id", "")))
	if already_bought:
		_detail_buy_btn.disabled = true
		_detail_buy_btn.text = "已购买"
	elif not can_buy:
		_detail_buy_btn.disabled = true
		_detail_buy_btn.text = "余额不足"
	else:
		_detail_buy_btn.disabled = false
		_detail_buy_btn.text = "立即购买"
	ShopCardBuilder.style_primary_btn(_detail_buy_btn)


# ══════════════════════════════════════════════════════
#  交互回调
# ══════════════════════════════════════════════════════

func _on_tab_pressed(index: int) -> void:
	_switch_tab(index)


func _switch_tab(index: int) -> void:
	_current_tab = index
	if index != 0:
		_force_close_detail()
	for i in range(_body_stack.size()):
		var page: Control = _body_stack[i]
		if i == index:
			page.visible = true
			page.modulate.a = 0.0
			if _tab_tween != null and _tab_tween.is_valid():
				_tab_tween.kill()
			_tab_tween = create_tween()
			_tab_tween.tween_property(page, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
		else:
			page.visible = false
			page.modulate.a = 1.0
	for i in range(_nav_tabs.size()):
		var active: bool = (i == index)
		_nav_tabs[i].add_theme_color_override("font_color", ShopCardBuilder.C_NAV if active else ShopCardBuilder.C_TEXT_SEC)
	_refresh_all()


func _on_item_selected(instance_id: String) -> void:
	_selected_item_id = instance_id
	_detail_visible = true
	_refresh_grid()
	_refresh_detail()
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	var already_open: bool = _detail_panel.visible
	_detail_panel.visible = true
	if not already_open:
		_detail_panel.modulate.a = 0.0
		_detail_tween = create_tween()
		_detail_tween.tween_property(_detail_panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	else:
		_detail_panel.modulate.a = 1.0


func _close_detail() -> void:
	if not _detail_panel.visible:
		return
	_detail_visible = false
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	_detail_tween = create_tween()
	_detail_tween.tween_property(_detail_panel, "modulate:a", 0.0, 0.15).set_ease(Tween.EASE_IN)
	_detail_tween.tween_callback(func(): _detail_panel.visible = false)


func _force_close_detail() -> void:
	_detail_visible = false
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	_detail_panel.visible = false
	_detail_panel.modulate.a = 1.0


func _on_buy_pressed() -> void:
	if _shop == null or _selected_item_id.is_empty():
		return
	var result: Dictionary = _shop.purchase_item(_selected_item_id)
	if bool(result.get("success", false)):
		_detail_buy_btn.text = "✔ 已购买"
		_detail_buy_btn.disabled = true
		ShopCardBuilder.style_primary_btn(_detail_buy_btn)
		var item_title: String = str(result.get("order", {}).get("item_snapshot", {}).get("title", ""))
		var money: int = int(_gm.get("money")) if _gm != null else 0
		_show_toast("已购买：%s · 已放入库存 · 余额 ￥%d" % [item_title, money], ShopCardBuilder.C_SUCCESS)
		var tw := create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(_refresh_detail)
	else:
		_show_toast(str(result.get("error", "购买失败")), ShopCardBuilder.C_WARN)
		_shake_node(_detail_buy_btn)
	_refresh_all()


func _on_inventory_action_pressed(inventory_id: String, category: String) -> void:
	if _shop == null:
		return
	var target: String = "heroine" if category == "gift" else "self"
	var result: Dictionary = _shop.use_inventory_item(inventory_id, target)
	if bool(result.get("success", false)):
		var mode: String = str(result.get("mode", "consume"))
		var item_title: String = str(result.get("item", {}).get("title", ""))
		var verb: String = "已使用"
		if mode == "gift":
			verb = "已赠出"
		var stats_text: String = ShopCardBuilder.format_stats_change(result)
		var msg: String = "%s：%s" % [verb, item_title]
		if not stats_text.is_empty():
			msg += " · %s" % stats_text
		_show_toast(msg, ShopCardBuilder.C_SUCCESS)
	else:
		_show_toast(str(result.get("error", "使用失败")), ShopCardBuilder.C_WARN)
	_refresh_all()


func _on_shop_changed(_arg = null) -> void:
	_refresh_all()


func _on_generation_started(_day: int) -> void:
	_show_toast("正在生成今日推荐...", ShopCardBuilder.C_WARN)


func _on_generation_failed(error_msg: String) -> void:
	_show_toast(error_msg, ShopCardBuilder.C_WARN)
	_refresh_all()


func _on_purchase_completed(_order: Dictionary) -> void:
	_refresh_all()


func _on_delivery_arrived(_order_id: String, inv_item: Dictionary) -> void:
	if inv_item.is_empty():
		return
	_refresh_all()


func _on_money_changed(_old: int, _new: int) -> void:
	_refresh_wallet()
	_refresh_detail()


func _on_day_changed(_day: int) -> void:
	_show_toast("新的一天，商品已更新", ShopCardBuilder.C_SUCCESS)
	_refresh_all()


# ══════════════════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════════════════

func _find_selected_catalog_item() -> Dictionary:
	if _shop == null:
		return {}
	for raw_item in _shop.get_catalog():
		var item: Dictionary = raw_item as Dictionary
		if str(item.get("instance_id", "")) == _selected_item_id:
			return item
	return {}


func _show_toast(msg: String, color: Color) -> void:
	_toast_label.text = msg
	_toast_label.add_theme_color_override("font_color", color)
	_toast_timer.start()


func _hide_toast() -> void:
	_toast_label.text = ""


func _clear_children(container: Control) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _shake_node(node: Control) -> void:
	var original_x: float = node.position.x
	var tw := create_tween()
	tw.tween_property(node, "position:x", original_x + 6.0, 0.05)
	tw.tween_property(node, "position:x", original_x - 6.0, 0.05)
	tw.tween_property(node, "position:x", original_x + 3.0, 0.05)
	tw.tween_property(node, "position:x", original_x, 0.05)
