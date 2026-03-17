class_name SbeamApp
extends Control

const DOWNLOAD_STAGES: Array[String] = [
	"正在校验共享库...",
	"正在从 SBEAM CDN 拉取内容...",
	"正在解压并准备启动..."
]

var _sbeam_manager: Node = null
var _selected_game_id: String = ""
var _catalog_by_id: Dictionary = {}
var _active_session_id: String = ""
var _download_progress: float = 0.0

var _status_label: Label = null
var _money_label: Label = null
var _game_list: ItemList = null

var _detail_title: Label = null
var _detail_pitch: Label = null
var _detail_hook: Label = null

var _recent_reviews: Label = null
var _all_reviews: Label = null
var _release_date: Label = null
var _publisher: Label = null
var _tags_container: HFlowContainer = null

var _buy_price_label: Label = null
var _start_button: Button = null

var _user_reviews_container: VBoxContainer = null
var _download_window: Control = null
var _download_title_label: Label = null
var _download_stage_label: Label = null
var _download_progress_bar: ProgressBar = null


func _ready() -> void:
	_sbeam_manager = get_node_or_null("/root/SbeamManager")
	_build_ui()
	_connect_signals()
	_refresh_catalog()
	_update_top_bar()
	set_process(false)


func _process(_delta: float) -> void:
	if _active_session_id.is_empty() or _download_window == null or not is_instance_valid(_download_window):
		set_process(false)
		return
	if _download_stage_label != null:
		var stage_index := mini(int(floor(_download_progress * float(DOWNLOAD_STAGES.size()))), DOWNLOAD_STAGES.size() - 1)
		_download_stage_label.text = DOWNLOAD_STAGES[stage_index]


func _build_ui() -> void:
	# Base Background (Sbeam Dark Blue/Gray)
	var background := ColorRect.new()
	background.color = Color("#1b2838")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# --- TOP NAVIGATION BAR ---
	var top_nav_bg := ColorRect.new()
	top_nav_bg.color = Color("#171a21")
	top_nav_bg.custom_minimum_size = Vector2(0, 78)
	root.add_child(top_nav_bg)
	
	var top_nav_margin := MarginContainer.new()
	top_nav_margin.add_theme_constant_override("margin_left", 30)
	top_nav_margin.add_theme_constant_override("margin_right", 30)
	top_nav_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_nav_bg.add_child(top_nav_margin)

	var top_nav_hbox := HBoxContainer.new()
	top_nav_hbox.add_theme_constant_override("separation", 30)
	top_nav_margin.add_child(top_nav_hbox)
	
	var logo_label := Label.new()
	logo_label.text = "SBEAM"
	logo_label.add_theme_font_size_override("font_size", 30)
	logo_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	logo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_nav_hbox.add_child(logo_label)
	
	var store_btn := Button.new()
	store_btn.text = "商店"
	store_btn.flat = true
	store_btn.add_theme_color_override("font_color", Color("#1a9fff"))
	store_btn.add_theme_font_size_override("font_size", 18)
	top_nav_hbox.add_child(store_btn)
	
	var lib_btn := Button.new()
	lib_btn.text = "库"
	lib_btn.flat = true
	lib_btn.add_theme_color_override("font_color", Color("#c7d5e0"))
	lib_btn.add_theme_font_size_override("font_size", 18)
	top_nav_hbox.add_child(lib_btn)
	
	var comm_btn := Button.new()
	comm_btn.text = "社区"
	comm_btn.flat = true
	comm_btn.add_theme_color_override("font_color", Color("#c7d5e0"))
	comm_btn.add_theme_font_size_override("font_size", 18)
	top_nav_hbox.add_child(comm_btn)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_nav_hbox.add_child(spacer)
	
	var user_info_vbox := VBoxContainer.new()
	user_info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_nav_hbox.add_child(user_info_vbox)
	
	_status_label = Label.new()
	_status_label.text = "在线"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color("#66c0f4"))
	user_info_vbox.add_child(_status_label)
	
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 15)
	_money_label.add_theme_color_override("font_color", Color("#8f98a0"))
	user_info_vbox.add_child(_money_label)

	# --- MAIN CONTENT AREA ---
	var main_margin := MarginContainer.new()
	main_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.add_theme_constant_override("margin_left", 30)
	main_margin.add_theme_constant_override("margin_top", 20)
	main_margin.add_theme_constant_override("margin_right", 30)
	main_margin.add_theme_constant_override("margin_bottom", 20)
	root.add_child(main_margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	main_margin.add_child(hbox)

	# Left Sidebar: Games List
	var left_sidebar := VBoxContainer.new()
	left_sidebar.custom_minimum_size = Vector2(300, 0)
	left_sidebar.add_theme_constant_override("separation", 12)
	hbox.add_child(left_sidebar)

	var filter_label := Label.new()
	filter_label.text = "您的推荐"
	filter_label.add_theme_font_size_override("font_size", 18)
	filter_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	left_sidebar.add_child(filter_label)

	_game_list = ItemList.new()
	_game_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game_list.select_mode = ItemList.SELECT_SINGLE
	_game_list.allow_reselect = true
	_game_list.add_theme_stylebox_override("panel", _empty_style())
	_game_list.add_theme_color_override("font_color", Color("#8f98a0"))
	_game_list.add_theme_color_override("font_selected_color", Color("#ffffff"))
	_game_list.add_theme_font_size_override("font_size", 16)
	left_sidebar.add_child(_game_list)

	# Right Main: Store Page
	var store_scroll := ScrollContainer.new()
	store_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(store_scroll)

	var store_vbox := VBoxContainer.new()
	store_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_vbox.add_theme_constant_override("separation", 18)
	store_scroll.add_child(store_vbox)
	
	# Title
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 30)
	_detail_title.add_theme_color_override("font_color", Color("#ffffff"))
	store_vbox.add_child(_detail_title)
	
	# Top Banner Row (Hero + Meta info)
	var banner_hbox := HBoxContainer.new()
	banner_hbox.add_theme_constant_override("separation", 18)
	store_vbox.add_child(banner_hbox)
	
	# Hero Image (Mock)
	var hero_rect := ColorRect.new()
	hero_rect.custom_minimum_size = Vector2(560, 262)
	hero_rect.color = Color("#000000")
	banner_hbox.add_child(hero_rect)
	
	var placeholder_img_lbl := Label.new()
	placeholder_img_lbl.text = "[ 游 戏 实 机 宣 传 图 ]"
	placeholder_img_lbl.add_theme_font_size_override("font_size", 18)
	placeholder_img_lbl.add_theme_color_override("font_color", Color("#455565"))
	placeholder_img_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_img_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_img_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_rect.add_child(placeholder_img_lbl)
	
	# Meta Column
	var meta_vbox := VBoxContainer.new()
	meta_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_vbox.add_theme_constant_override("separation", 8)
	banner_hbox.add_child(meta_vbox)
	
	_detail_pitch = Label.new()
	_detail_pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_pitch.add_theme_font_size_override("font_size", 16)
	_detail_pitch.add_theme_color_override("font_color", Color("#c6d4df"))
	_detail_pitch.custom_minimum_size = Vector2(0, 68)
	meta_vbox.add_child(_detail_pitch)
	
	var _create_meta_row = func(title_text: String) -> Array:
		var row_hbox = HBoxContainer.new()
		var t_lbl = Label.new()
		t_lbl.text = title_text
		t_lbl.custom_minimum_size = Vector2(112, 0)
		t_lbl.add_theme_font_size_override("font_size", 14)
		t_lbl.add_theme_color_override("font_color", Color("#556772"))
		row_hbox.add_child(t_lbl)
		var v_lbl = Label.new()
		v_lbl.add_theme_font_size_override("font_size", 14)
		v_lbl.add_theme_color_override("font_color", Color("#8f98a0"))
		row_hbox.add_child(v_lbl)
		meta_vbox.add_child(row_hbox)
		return [row_hbox, v_lbl]
	
	_recent_reviews = _create_meta_row.call("最近评测：")[1]
	_all_reviews = _create_meta_row.call("全部评测：")[1]
	
	_create_meta_row.call("")[0].custom_minimum_size = Vector2(0, 8) # spacer
	
	_release_date = _create_meta_row.call("发行日期：")[1]
	_publisher = _create_meta_row.call("开发商：")[1]
	
	var tags_title = Label.new()
	tags_title.text = "该产品的热门用户自定义标签："
	tags_title.add_theme_font_size_override("font_size", 14)
	tags_title.add_theme_color_override("font_color", Color("#556772"))
	meta_vbox.add_child(tags_title)
	
	_tags_container = HFlowContainer.new()
	_tags_container.add_theme_constant_override("h_separation", 6)
	_tags_container.add_theme_constant_override("v_separation", 6)
	meta_vbox.add_child(_tags_container)
	
	# Purchase / Hook Box
	var purchase_panel := MarginContainer.new()
	purchase_panel.add_theme_constant_override("margin_top", 12)
	purchase_panel.add_theme_constant_override("margin_bottom", 12)
	store_vbox.add_child(purchase_panel)
	
	var purchase_bg := PanelContainer.new()
	var pbg_style := StyleBoxFlat.new()
	pbg_style.bg_color = Color("#111923") # Darker background
	pbg_style.corner_radius_bottom_left = 4
	pbg_style.corner_radius_bottom_right = 4
	pbg_style.corner_radius_top_left = 4
	pbg_style.corner_radius_top_right = 4
	purchase_bg.add_theme_stylebox_override("panel", pbg_style)
	purchase_panel.add_child(purchase_bg)
	
	var purchase_margin := MarginContainer.new()
	purchase_margin.add_theme_constant_override("margin_left", 16)
	purchase_margin.add_theme_constant_override("margin_right", 16)
	purchase_margin.add_theme_constant_override("margin_top", 14)
	purchase_margin.add_theme_constant_override("margin_bottom", 14)
	purchase_bg.add_child(purchase_margin)
	
	var purchase_hbox := HBoxContainer.new()
	purchase_hbox.alignment = BoxContainer.ALIGNMENT_END
	purchase_margin.add_child(purchase_hbox)
	
	_detail_hook = Label.new()
	_detail_hook.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_hook.add_theme_font_size_override("font_size", 16)
	_detail_hook.add_theme_color_override("font_color", Color("#c6d4df"))
	purchase_hbox.add_child(_detail_hook)
	
	var buy_action_bg := PanelContainer.new()
	var buy_style := StyleBoxFlat.new()
	buy_style.bg_color = Color("#000000")
	buy_style.corner_radius_bottom_left = 4
	buy_style.corner_radius_bottom_right = 4
	buy_style.corner_radius_top_left = 4
	buy_style.corner_radius_top_right = 4
	buy_action_bg.add_theme_stylebox_override("panel", buy_style)
	purchase_hbox.add_child(buy_action_bg)
	
	var buy_action_hbox := HBoxContainer.new()
	buy_action_bg.add_child(buy_action_hbox)
	
	_buy_price_label = Label.new()
	_buy_price_label.add_theme_font_size_override("font_size", 16)
	_buy_price_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	_buy_price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var price_margin := MarginContainer.new()
	price_margin.add_theme_constant_override("margin_left", 16)
	price_margin.add_theme_constant_override("margin_right", 16)
	price_margin.add_child(_buy_price_label)
	buy_action_hbox.add_child(price_margin)
	
	_start_button = Button.new()
	_start_button.text = "添加至购物车"
	_start_button.custom_minimum_size = Vector2(156, 42)
	_start_button.add_theme_font_size_override("font_size", 16)
	var btn_style_n := StyleBoxFlat.new()
	btn_style_n.bg_color = Color("#749c25")
	btn_style_n.corner_radius_bottom_left = 3
	btn_style_n.corner_radius_bottom_right = 3
	btn_style_n.corner_radius_top_left = 3
	btn_style_n.corner_radius_top_right = 3
	_start_button.add_theme_stylebox_override("normal", btn_style_n)
	var btn_style_h := StyleBoxFlat.new()
	btn_style_h.bg_color = Color("#a4d041")
	_start_button.add_theme_stylebox_override("hover", btn_style_h)
	_start_button.add_theme_color_override("font_color", Color("#d2efa9"))
	buy_action_hbox.add_child(_start_button)
	
	# User Reviews Section
	var reviews_title = Label.new()
	reviews_title.text = "最有价值的评测"
	reviews_title.add_theme_font_size_override("font_size", 18)
	reviews_title.add_theme_color_override("font_color", Color("#ffffff"))
	var rt_margin = MarginContainer.new()
	rt_margin.add_theme_constant_override("margin_top", 18)
	rt_margin.add_child(reviews_title)
	store_vbox.add_child(rt_margin)
	
	var reviews_separator = ColorRect.new()
	reviews_separator.color = Color("#2a3f5a")
	reviews_separator.custom_minimum_size = Vector2(0, 1)
	store_vbox.add_child(reviews_separator)
	
	_user_reviews_container = VBoxContainer.new()
	_user_reviews_container.add_theme_constant_override("separation", 16)
	store_vbox.add_child(_user_reviews_container)


func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _connect_signals() -> void:
	if _game_list != null:
		_game_list.item_selected.connect(_on_game_selected)
	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)
	if _sbeam_manager != null:
		if not _sbeam_manager.catalog_refreshed.is_connected(_on_catalog_refreshed):
			_sbeam_manager.catalog_refreshed.connect(_on_catalog_refreshed)
		if not _sbeam_manager.play_session_started.is_connected(_on_play_session_started):
			_sbeam_manager.play_session_started.connect(_on_play_session_started)
		if _sbeam_manager.has_signal("download_started") and not _sbeam_manager.download_started.is_connected(_on_download_started):
			_sbeam_manager.download_started.connect(_on_download_started)
		if _sbeam_manager.has_signal("download_progress_updated") and not _sbeam_manager.download_progress_updated.is_connected(_on_download_progress_updated):
			_sbeam_manager.download_progress_updated.connect(_on_download_progress_updated)
		if _sbeam_manager.has_signal("play_session_completed") and not _sbeam_manager.play_session_completed.is_connected(_on_play_session_completed):
			_sbeam_manager.play_session_completed.connect(_on_play_session_completed)
		if not _sbeam_manager.play_session_failed.is_connected(_on_play_session_failed):
			_sbeam_manager.play_session_failed.connect(_on_play_session_failed)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("money_changed"):
		gm.money_changed.connect(func(_old_val: int, _new_val: int) -> void: _update_top_bar())
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("ap_changed"):
		glm.ap_changed.connect(func(_current: int, _max: int) -> void: _update_top_bar())


func _refresh_catalog() -> void:
	_catalog_by_id.clear()
	_game_list.clear()
	if _sbeam_manager == null:
		return

	var catalog: Array = _sbeam_manager.get_catalog()
	for entry in catalog:
		if not entry is Dictionary:
			continue
		var game: Dictionary = entry
		var game_id: String = str(game.get("game_id", ""))
		_catalog_by_id[game_id] = game.duplicate(true)
		var title: String = str(game.get("title", "未命名作品"))
		var badge: String = "✨ " if bool(game.get("is_featured_today", false)) else ""
		_game_list.add_item("%s%s" % [badge, title])
		_game_list.set_item_metadata(_game_list.item_count - 1, game_id)

	if _game_list.item_count > 0:
		_game_list.select(0)
		_on_game_selected(0)
	else:
		_render_empty_state()


func _render_empty_state() -> void:
	_selected_game_id = ""
	_detail_title.text = "没有找到产品"
	_detail_pitch.text = "此处暂无可显示的内容。"
	_recent_reviews.text = "-"
	_all_reviews.text = "-"
	_release_date.text = "-"
	_publisher.text = "-"
	_detail_hook.text = ""
	_buy_price_label.text = "¥ 0"
	_start_button.disabled = true
	
	for child in _tags_container.get_children():
		child.queue_free()
	for child in _user_reviews_container.get_children():
		child.queue_free()


func _on_game_selected(index: int) -> void:
	var game_id: String = str(_game_list.get_item_metadata(index))
	_selected_game_id = game_id
	if not _catalog_by_id.has(game_id):
		_render_empty_state()
		return

	var entry: Dictionary = _catalog_by_id[game_id]
	_detail_title.text = str(entry.get("title", "未命名作品"))
	_detail_pitch.text = str(entry.get("pitch", ""))
	
	var rec_rev = str(entry.get("recent_reviews_summary", "无评测"))
	_recent_reviews.text = rec_rev
	if "好评" in rec_rev and not "差评" in rec_rev:
		_recent_reviews.add_theme_color_override("font_color", Color("#66c0f4"))
	else:
		_recent_reviews.add_theme_color_override("font_color", Color("#8f98a0"))

	var all_rev = str(entry.get("all_reviews_summary", "无评测"))
	_all_reviews.text = all_rev
	if "好评" in all_rev and not "差评" in all_rev:
		_all_reviews.add_theme_color_override("font_color", Color("#66c0f4"))
	else:
		_all_reviews.add_theme_color_override("font_color", Color("#8f98a0"))
		
	_release_date.text = str(entry.get("release_date", "未知"))
	_publisher.text = str(entry.get("publisher", "未知开发商"))
	
	_buy_price_label.text = "¥ %d" % int(entry.get("price", 0))
	_detail_hook.text = str(entry.get("hook_moment", "看起来很有趣。"))
	_start_button.disabled = false
	
	_build_tags(entry.get("tone_tags", []))
	_build_user_reviews(entry.get("user_reviews", []))


func _build_tags(tags: Array) -> void:
	for child in _tags_container.get_children():
		child.queue_free()
	for t in tags:
		var tag_bg := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#111923")
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 2
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		tag_bg.add_theme_stylebox_override("panel", style)
		
		var t_margin := MarginContainer.new()
		t_margin.add_theme_constant_override("margin_left", 6)
		t_margin.add_theme_constant_override("margin_right", 6)
		t_margin.add_theme_constant_override("margin_top", 3)
		t_margin.add_theme_constant_override("margin_bottom", 3)
		tag_bg.add_child(t_margin)
		
		var lbl := Label.new()
		lbl.text = str(t)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color("#66c0f4"))
		t_margin.add_child(lbl)
		
		_tags_container.add_child(tag_bg)


func _build_user_reviews(reviews: Array) -> void:
	for child in _user_reviews_container.get_children():
		child.queue_free()
		
	if reviews.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "目前还没有玩家撰写评测。"
		empty_lbl.add_theme_color_override("font_color", Color("#8f98a0"))
		empty_lbl.add_theme_font_size_override("font_size", 16)
		_user_reviews_container.add_child(empty_lbl)
		return
		
	for rev in reviews:
		if not rev is Dictionary: continue
		var rev_panel = PanelContainer.new()
		var r_style = StyleBoxFlat.new()
		r_style.bg_color = Color("#16202d")
		r_style.bg_color.a = 0.5
		r_style.set_border_width_all(1)
		r_style.border_color = Color("#2a3f5a")
		rev_panel.add_theme_stylebox_override("panel", r_style)
		_user_reviews_container.add_child(rev_panel)
		
		var r_margin = MarginContainer.new()
		r_margin.add_theme_constant_override("margin_left", 16)
		r_margin.add_theme_constant_override("margin_right", 16)
		r_margin.add_theme_constant_override("margin_top", 12)
		r_margin.add_theme_constant_override("margin_bottom", 12)
		rev_panel.add_child(r_margin)
		
		var r_hbox = HBoxContainer.new()
		r_hbox.add_theme_constant_override("separation", 18)
		r_margin.add_child(r_hbox)
		
		# Left user info
		var user_vbox = VBoxContainer.new()
		user_vbox.custom_minimum_size = Vector2(160, 0)
		r_hbox.add_child(user_vbox)
		
		var username = Label.new()
		username.text = str(rev.get("user", "匿名玩家"))
		username.add_theme_color_override("font_color", Color("#e7e7e7"))
		username.add_theme_font_size_override("font_size", 16)
		user_vbox.add_child(username)
		
		var counts = Label.new()
		counts.text = "拥有 %d 项产品" % int(rev.get("owned_products", 1))
		counts.add_theme_color_override("font_color", Color("#8f98a0"))
		counts.add_theme_font_size_override("font_size", 12)
		user_vbox.add_child(counts)
		
		# Right content
		var content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.add_theme_constant_override("separation", 8)
		r_hbox.add_child(content_vbox)
		
		var rec_hbox = HBoxContainer.new()
		content_vbox.add_child(rec_hbox)
		
		var thumb_lbl = Label.new()
		var is_rec = bool(rev.get("is_recommended", true))
		thumb_lbl.text = "👍 推荐" if is_rec else "👎 不推荐"
		thumb_lbl.add_theme_color_override("font_color", Color("#c7d5e0"))
		thumb_lbl.add_theme_font_size_override("font_size", 16)
		rec_hbox.add_child(thumb_lbl)
		
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rec_hbox.add_child(spacer)
		
		var hours_lbl = Label.new()
		hours_lbl.text = "总时数 %s 小时" % str(rev.get("hours", "0.0"))
		hours_lbl.add_theme_color_override("font_color", Color("#8f98a0"))
		hours_lbl.add_theme_font_size_override("font_size", 13)
		rec_hbox.add_child(hours_lbl)
		
		var rev_text = Label.new()
		rev_text.text = str(rev.get("review", ""))
		rev_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rev_text.add_theme_color_override("font_color", Color("#acb2b8"))
		rev_text.add_theme_font_size_override("font_size", 15)
		content_vbox.add_child(rev_text)
		
		var helpful = Label.new()
		helpful.text = "%d 人认为这篇评测有价值" % int(rev.get("upvotes", 0))
		helpful.add_theme_color_override("font_color", Color("#8f98a0"))
		helpful.add_theme_font_size_override("font_size", 12)
		var helpful_margin = MarginContainer.new()
		helpful_margin.add_theme_constant_override("margin_top", 8)
		helpful_margin.add_child(helpful)
		content_vbox.add_child(helpful_margin)


func _on_start_pressed() -> void:
	if _selected_game_id.is_empty() or _sbeam_manager == null or not _active_session_id.is_empty():
		return
	var result: Dictionary = _sbeam_manager.begin_play_session(_selected_game_id)
	if not bool(result.get("success", false)):
		pass


func _on_catalog_refreshed(_catalog: Array) -> void:
	_refresh_catalog()
	_update_top_bar()


func _on_play_session_started(session_id: String, payload: Dictionary) -> void:
	_active_session_id = session_id
	_download_progress = 0.0
	var _game: Dictionary = payload.get("game", {})
	_open_linkchat_dm()
	_update_top_bar()


func _on_download_started(session_id: String, payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_download_progress = 0.0
	_show_download_window(payload.get("game", {}))
	set_process(true)


func _on_download_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	if session_id != _active_session_id:
		return
	_download_progress = progress
	if _download_progress_bar != null:
		_download_progress_bar.value = progress * 100.0
	if progress >= 1.0:
		_close_download_window()
		set_process(false)


func _on_play_session_completed(session_id: String, payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return
	_active_session_id = ""
	_download_progress = 0.0
	set_process(false)
	_close_download_window()
	var _game: Dictionary = payload.get("game", {})
	pass
	_update_top_bar()


func _on_play_session_failed(_error_message: String) -> void:
	_active_session_id = ""
	_download_progress = 0.0
	set_process(false)
	_close_download_window()


func _update_top_bar() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		_money_label.text = "钱包余额：¥ %d" % int(gm.money)


func _open_linkchat_dm() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("launch_app"):
		return
	var window: Control = app_manager.launch_app("linkchat")
	if window == null:
		return
	call_deferred("_select_linkchat_dm", window)


func _select_linkchat_dm(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	var content: Variant = window.get("content")
	if content != null and content.has_method("select_channel"):
		content.select_channel("dm_lin_xia")


func _show_download_window(game_data: Variant) -> void:
	_close_download_window()
	var game: Dictionary = game_data if game_data is Dictionary else {}
	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.get("window_manager") if app_manager != null else null
	if window_manager == null or not window_manager.has_method("create_window"):
		return

	# Steam 深色面板
	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color("#1b2838")
	outer_style.corner_radius_top_left = 4
	outer_style.corner_radius_top_right = 4
	outer_style.corner_radius_bottom_left = 4
	outer_style.corner_radius_bottom_right = 4
	outer.add_theme_stylebox_override("panel", outer_style)
	outer.custom_minimum_size = Vector2(560, 280)

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	content.add_child(box)

	# 游戏标题
	_download_title_label = Label.new()
	_download_title_label.text = str(game.get("title", "未命名作品"))
	_download_title_label.add_theme_font_size_override("font_size", 22)
	_download_title_label.add_theme_color_override("font_color", Color("#c7d5e0"))
	box.add_child(_download_title_label)

	# 阶段描述
	_download_stage_label = Label.new()
	_download_stage_label.text = DOWNLOAD_STAGES[0]
	_download_stage_label.add_theme_font_size_override("font_size", 14)
	_download_stage_label.add_theme_color_override("font_color", Color("#66c0f4"))
	box.add_child(_download_stage_label)

	# Steam 蓝色进度条
	_download_progress_bar = ProgressBar.new()
	_download_progress_bar.min_value = 0.0
	_download_progress_bar.max_value = 100.0
	_download_progress_bar.value = 0.0
	_download_progress_bar.show_percentage = false
	_download_progress_bar.custom_minimum_size = Vector2(0, 14)
	var pbg_style := StyleBoxFlat.new()
	pbg_style.bg_color = Color("#0e1621")
	pbg_style.corner_radius_top_left = 2
	pbg_style.corner_radius_top_right = 2
	pbg_style.corner_radius_bottom_left = 2
	pbg_style.corner_radius_bottom_right = 2
	pbg_style.border_color = Color("#2a3f5a")
	pbg_style.set_border_width_all(1)
	_download_progress_bar.add_theme_stylebox_override("background", pbg_style)
	var pfill_style := StyleBoxFlat.new()
	pfill_style.bg_color = Color("#1a9fff")
	pfill_style.corner_radius_top_left = 2
	pfill_style.corner_radius_top_right = 2
	pfill_style.corner_radius_bottom_left = 2
	pfill_style.corner_radius_bottom_right = 2
	_download_progress_bar.add_theme_stylebox_override("fill", pfill_style)
	box.add_child(_download_progress_bar)

	# 装饰性下载详情行
	var details_hbox := HBoxContainer.new()
	details_hbox.add_theme_constant_override("separation", 32)
	box.add_child(details_hbox)

	var _add_detail = func(label_text: String, value_text: String) -> void:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var lbl := Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color("#556772"))
		col.add_child(lbl)
		var val := Label.new()
		val.text = value_text
		val.add_theme_font_size_override("font_size", 13)
		val.add_theme_color_override("font_color", Color("#8f98a0"))
		col.add_child(val)
		details_hbox.add_child(col)

	_add_detail.call("下载速度", "%.1f MB/s" % randf_range(12.0, 48.0))
	_add_detail.call("已下载", "0 / %d MB" % (randi_range(800, 4200)))
	_add_detail.call("磁盘空间", "%d GB 可用" % randi_range(120, 500))

	_download_window = window_manager.create_window("下载 — %s" % str(game.get("title", "")), outer)
	if _download_window != null:
		_download_window.size = Vector2(580, 300)


func _close_download_window() -> void:
	if _download_window == null or not is_instance_valid(_download_window):
		_download_window = null
		_download_title_label = null
		_download_stage_label = null
		_download_progress_bar = null
		return
	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.get("window_manager") if app_manager != null else null
	if window_manager != null and window_manager.has_method("close_window"):
		window_manager.close_window(_download_window)
	else:
		_download_window.queue_free()
	_download_window = null
	_download_title_label = null
	_download_stage_label = null
	_download_progress_bar = null
