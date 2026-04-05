class_name SbeamApp
extends Control

const ActivityPreviewLayerClass = preload("res://scripts/ui/activity_preview/activity_preview_layer.gd")

const DOWNLOAD_STAGES: Array[String] = [
	"正在连接 SBEAM 内容服务器...",
	"正在校验本地共享运行库...",
	"正在下载游戏数据 (1/3)...",
	"正在下载游戏数据 (2/3)...",
	"正在下载游戏数据 (3/3)...",
	"正在校验文件完整性...",
	"正在解压并配置运行环境...",
	"准备启动..."
]

const MINI_GAME_2048_SCENE: PackedScene = preload("res://scenes/apps/sbeam/games/game_2048.tscn")
const MINI_GAME_SNAKE_SCENE: PackedScene = preload("res://scenes/apps/sbeam/games/game_snake.tscn")
const VIEW_STORE: String = "store"
const VIEW_LIBRARY: String = "library"
const STATS_SAVE_PATH: String = "user://sbeam_game_stats.json"

var _sbeam_manager: Node = null
var _selected_game_id: String = ""
var _catalog_by_id: Dictionary = {}
var _active_session_id: String = ""
var _download_progress: float = 0.0
var _current_view: String = VIEW_STORE
var _persisted_stats: Dictionary = {}  # game_id -> Array[Dictionary] (last known stats)

var _library_games: Array[Dictionary] = []
var _library_windows: Dictionary = {}

var _store_nav_button: Button = null
var _library_nav_button: Button = null
var _community_nav_button: Button = null
var _status_label: Label = null
var _money_label: Label = null
var _notice_label: Label = null

var _store_content: Control = null
var _library_content: Control = null
var _game_list: ItemList = null
var _preview_layer: Control = null
var _hovered_game_id: String = ""

var _detail_title: Label = null
var _detail_pitch: Label = null
var _detail_meta: Label = null
var _detail_hook: Label = null
var _tags_container: HFlowContainer = null
var _buy_price_label: Label = null
var _start_button: Button = null
var _user_reviews_container: VBoxContainer = null

var _library_cards_root: VBoxContainer = null
var _library_detail_root: VBoxContainer = null
var _selected_library_game_id: String = ""
var _library_list_buttons: Dictionary = {}
var _library_score_labels: Dictionary = {}  # game_id -> Array[Label] (value labels for stat cards)

var _download_window: Control = null
var _download_title_label: Label = null
var _download_stage_label: Label = null
var _download_progress_bar: ProgressBar = null


func _ready() -> void:
	_sbeam_manager = get_node_or_null("/root/SbeamManager")
	_library_games = _build_library_catalog()
	_load_persisted_stats()
	_build_ui()
	_preview_layer = ActivityPreviewLayerClass.ensure_for(self)
	_connect_signals()
	_refresh_catalog()
	_refresh_library_view()
	_set_active_view(VIEW_STORE)
	_update_top_bar()
	set_process(false)


func _process(_delta: float) -> void:
	if _active_session_id.is_empty() or _download_window == null or not is_instance_valid(_download_window):
		set_process(false)
		return

	if _download_stage_label != null:
		var stage_index: int = clampi(
			int(floor(_download_progress * float(DOWNLOAD_STAGES.size()))),
			0,
			DOWNLOAD_STAGES.size() - 1
		)
		_download_stage_label.text = DOWNLOAD_STAGES[stage_index]


func set_active_view(view_id: String) -> void:
	_set_active_view(view_id)


func launch_library_game(game_id: String) -> Control:
	return _launch_library_game(game_id)


func _build_ui() -> void:
	var refs := SbeamUIBuilder.build_app_ui(self, _library_games.size(), Callable(self, "_set_active_view"))
	_store_nav_button = refs.get("store_nav_button")
	_library_nav_button = refs.get("library_nav_button")
	_community_nav_button = refs.get("community_nav_button")
	_status_label = refs.get("status_label")
	_money_label = refs.get("money_label")
	_notice_label = refs.get("notice_label")
	_store_content = refs.get("store_content")
	_library_content = refs.get("library_content")
	_game_list = refs.get("game_list")
	_detail_title = refs.get("detail_title")
	_detail_pitch = refs.get("detail_pitch")
	_detail_meta = refs.get("detail_meta")
	_detail_hook = refs.get("detail_hook")
	_tags_container = refs.get("tags_container")
	_buy_price_label = refs.get("buy_price_label")
	_start_button = refs.get("start_button")
	_user_reviews_container = refs.get("user_reviews_container")
	_library_cards_root = refs.get("library_cards_root")
	_library_detail_root = refs.get("library_detail_root")


func _connect_signals() -> void:
	if _game_list != null:
		_game_list.item_selected.connect(_on_game_selected)
		_game_list.gui_input.connect(_on_game_list_gui_input)
		_game_list.mouse_exited.connect(_on_game_list_mouse_exited)
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


func _build_library_catalog() -> Array[Dictionary]:
	return [
		{
			"game_id": "2048",
			"title": "2048",
			"genre": "数字合并",
			"summary": "将相同数字的方块合并，挑战最高分。支持方向键与 WASD 操作。",
			"window_title": "2048",
			"scene": MINI_GAME_2048_SCENE,
		},
		{
			"game_id": "snake",
			"title": "贪吃蛇",
			"genre": "经典街机",
			"summary": "控制蛇吃掉食物不断变长，速度会逐渐加快。撞到自己就结束。",
			"window_title": "贪吃蛇",
			"scene": MINI_GAME_SNAKE_SCENE,
		},
	]


func _refresh_catalog() -> void:
	_catalog_by_id.clear()
	if _game_list != null:
		_game_list.clear()

	if _sbeam_manager == null:
		_render_empty_state()
		return

	var catalog: Array = _sbeam_manager.get_catalog()
	for entry in catalog:
		if not entry is Dictionary:
			continue

		var game: Dictionary = (entry as Dictionary).duplicate(true)
		var game_id: String = str(game.get("game_id", ""))
		if game_id.is_empty():
			continue

		_catalog_by_id[game_id] = game
		var title: String = str(game.get("title", "未命名作品"))
		var prefix: String = "✨ " if bool(game.get("is_featured_today", false)) else ""
		_game_list.add_item("%s%s" % [prefix, title])
		_game_list.set_item_metadata(_game_list.item_count - 1, game_id)

	if _game_list != null and _game_list.item_count > 0:
		_game_list.select(0)
		_on_game_selected(0)
	else:
		_render_empty_state()


func _render_empty_state() -> void:
	_selected_game_id = ""
	SbeamStorePresenter.render_empty_state(_get_store_refs())
	_update_store_action_state()


func _on_game_selected(index: int) -> void:
	if _game_list == null or index < 0 or index >= _game_list.item_count:
		_render_empty_state()
		return

	var game_id: String = str(_game_list.get_item_metadata(index))
	_selected_game_id = game_id
	if not _catalog_by_id.has(game_id):
		_render_empty_state()
		return

	var entry: Dictionary = _catalog_by_id[game_id]
	SbeamStorePresenter.render_game_detail(_get_store_refs(), entry)
	_update_store_action_state()


func _on_game_list_gui_input(event: InputEvent) -> void:
	if _game_list == null or _preview_layer == null:
		return
	if not event is InputEventMouseMotion:
		return

	var index: int = _game_list.get_item_at_position(_game_list.get_local_mouse_position(), true)
	if index < 0 or index >= _game_list.item_count:
		_hovered_game_id = ""
		_preview_layer.hide_preview(_game_list)
		return

	var game_id: String = str(_game_list.get_item_metadata(index))
	if game_id == _hovered_game_id and _preview_layer.visible:
		return

	_hovered_game_id = game_id
	if not _catalog_by_id.has(game_id):
		_preview_layer.hide_preview(_game_list)
		return

	_preview_layer.show_preview(_game_list, _build_sbeam_preview_payload(_catalog_by_id[game_id]))


func _on_game_list_mouse_exited() -> void:
	_hovered_game_id = ""
	if _preview_layer != null:
		_preview_layer.hide_preview(_game_list)


func _build_tags(tags: Array) -> void:
	_clear_container(_tags_container)
	if _tags_container == null:
		return

	for tag in tags:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _make_panel_style(Color("#111923"), 8))
		_tags_container.add_child(chip)

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


func _build_user_reviews(reviews: Array) -> void:
	_clear_container(_user_reviews_container)
	if _user_reviews_container == null:
		return

	if reviews.is_empty():
		var empty_label := Label.new()
		empty_label.text = "目前还没有玩家撰写评测。"
		empty_label.add_theme_font_size_override("font_size", 15)
		empty_label.add_theme_color_override("font_color", Color("#8f98a0"))
		_user_reviews_container.add_child(empty_label)
		return

	for review_data in reviews:
		if not review_data is Dictionary:
			continue

		var review: Dictionary = review_data
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _make_card_style(Color("#16202d"), Color("#2a3f5a")))
		_user_reviews_container.add_child(panel)

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
		hours_label.text = "总时数 %s 小时" % str(review.get("hours", "0.0"))
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


func _refresh_library_view() -> void:
	_clear_container(_library_cards_root)
	_library_list_buttons.clear()
	if _library_cards_root == null:
		return

	for game in _library_games:
		_library_cards_root.add_child(_build_library_list_item(game))

	# 自动选中第一个或之前选中的
	if not _library_games.is_empty():
		var target_id: String = _selected_library_game_id
		if target_id.is_empty():
			target_id = str(_library_games[0].get("game_id", ""))
		_select_library_game(target_id)


func _build_library_list_item(game: Dictionary) -> Control:
	var game_id: String = str(game.get("game_id", ""))
	var is_running: bool = _find_open_library_window(game_id) != null
	var presenter_button := SbeamLibraryPresenter.build_list_item(game, is_running, _select_library_game.bind(game_id))
	_library_list_buttons[game_id] = presenter_button
	return presenter_button


func _select_library_game(game_id: String) -> void:
	_selected_library_game_id = game_id
	SbeamLibraryPresenter.apply_list_selection(_library_list_buttons, game_id)
	_show_library_detail(game_id)


func _show_library_detail(game_id: String) -> void:
	if _library_detail_root == null:
		return
	_library_score_labels.clear()
	_clear_container(_library_detail_root)

	var game := _find_library_game(game_id)
	if game.is_empty():
		return

	var is_running: bool = _find_open_library_window(game_id) != null

	# ── 顶部横幅区域 ──
	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(0, 200)
	var banner_style := _make_panel_style(Color("#0e1621"), 0)
	banner.add_theme_stylebox_override("panel", banner_style)
	_library_detail_root.add_child(banner)

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

	# ── 操作栏 ──
	var action_bar := PanelContainer.new()
	var action_bar_style := _make_panel_style(Color("#16202d"), 0)
	action_bar_style.border_color = Color("#2a3f5a")
	action_bar_style.set_border_width_all(0)
	action_bar_style.border_width_bottom = 1
	action_bar.add_theme_stylebox_override("panel", action_bar_style)
	_library_detail_root.add_child(action_bar)

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
	play_button.text = "切回窗口" if is_running else "▶  开始游戏"
	play_button.custom_minimum_size = Vector2(180, 46)
	_apply_primary_button_style(play_button)
	play_button.pressed.connect(func() -> void:
		_launch_library_game(game_id)
		# 刷新详情面板状态
		call_deferred("_show_library_detail", game_id)
		call_deferred("_refresh_library_view")
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

	# ── 详情内容区 ──
	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 36)
	info_margin.add_theme_constant_override("margin_top", 24)
	info_margin.add_theme_constant_override("margin_right", 36)
	info_margin.add_theme_constant_override("margin_bottom", 24)
	_library_detail_root.add_child(info_margin)

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 20)
	info_margin.add_child(info_box)

	# 关于此游戏
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

	# 游戏信息卡片
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

	# ── 统计面板 ──
	var stats: Array = []
	var game_instance := _get_library_game_content(game_id)
	if game_instance != null and game_instance.has_method("get_stats"):
		stats = game_instance.get_stats()
		_persist_game_stats(game_id, stats)
	else:
		stats = _get_persisted_stats(game_id)

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

		var value_labels: Array[Label] = []
		for stat in stats:
			if not stat is Dictionary:
				continue
			var card := _build_score_stat_card(str(stat.get("label", "")), str(stat.get("value", "-")))
			score_row.add_child(card.panel)
			value_labels.append(card.value_label)
		_library_score_labels[game_id] = value_labels




func _add_meta_row(grid: GridContainer, key: String, value: String) -> void:
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


func _build_score_stat_card(title: String, initial_value: String) -> Dictionary:
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


func _get_store_refs() -> Dictionary:
	return {
		"detail_title": _detail_title,
		"detail_pitch": _detail_pitch,
		"detail_meta": _detail_meta,
		"detail_hook": _detail_hook,
		"buy_price_label": _buy_price_label,
		"tags_container": _tags_container,
		"user_reviews_container": _user_reviews_container,
	}


func _resolve_library_stats(game_id: String) -> Array:
	var stats: Array = []
	var game_instance := _get_library_game_content(game_id)
	if game_instance != null and game_instance.has_method("get_stats"):
		stats = game_instance.get_stats()
		_persist_game_stats(game_id, stats)
	else:
		stats = _get_persisted_stats(game_id)
	return stats


func _load_persisted_stats() -> void:
	_persisted_stats.clear()
	if not FileAccess.file_exists(STATS_SAVE_PATH):
		return
	var file := FileAccess.open(STATS_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_persisted_stats = json.data
	file.close()


func _save_persisted_stats() -> void:
	var file := FileAccess.open(STATS_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_persisted_stats, "\t"))
	file.close()


func _persist_game_stats(game_id: String, stats: Array) -> void:
	var serialized: Array = []
	for s in stats:
		if s is Dictionary:
			serialized.append({"label": str(s.get("label", "")), "value": str(s.get("value", ""))})
	_persisted_stats[game_id] = serialized
	_save_persisted_stats()


func _get_persisted_stats(game_id: String) -> Array:
	if _persisted_stats.has(game_id):
		return _persisted_stats[game_id]
	return []


func _get_library_game_content(game_id: String) -> Control:
	var window := _find_open_library_window(game_id)
	if window == null:
		return null
	var content: Variant = window.get("content")
	if content is Control:
		return content as Control
	return null


func _refresh_score_display(game_id: String) -> void:
	if game_id != _selected_library_game_id:
		return
	if not _library_score_labels.has(game_id):
		return
	var labels: Array[Label] = []
	for candidate in _library_score_labels[game_id]:
		if not is_instance_valid(candidate):
			continue
		var label_node := candidate as Label
		if label_node != null:
			labels.append(label_node)
	if labels.is_empty():
		_library_score_labels.erase(game_id)
		return
	_library_score_labels[game_id] = labels
	var stats: Array = []
	var game_instance := _get_library_game_content(game_id)
	if game_instance != null and game_instance.has_method("get_stats"):
		stats = game_instance.get_stats()
	else:
		stats = _get_persisted_stats(game_id)
	if stats.is_empty():
		for label_node in labels:
			label_node.text = "-"
		return
	for i in range(mini(stats.size(), labels.size())):
		var label_node: Label = labels[i]
		label_node.text = str(stats[i].get("value", "-"))


func _on_library_game_stats_changed(game_id: String) -> void:
	var game_instance := _get_library_game_content(game_id)
	if game_instance != null and game_instance.has_method("get_stats"):
		_persist_game_stats(game_id, game_instance.get_stats())
	_refresh_score_display(game_id)


func _on_start_pressed() -> void:
	if _selected_game_id.is_empty() or _sbeam_manager == null:
		return
	if not _active_session_id.is_empty():
		_set_notice("有下载任务正在进行。")
		return

	var result: Dictionary = _sbeam_manager.begin_play_session(_selected_game_id)
	if not bool(result.get("success", false)):
		_set_notice(str(result.get("error", "启动失败，请稍后再试。")))


func _on_catalog_refreshed(_catalog: Array) -> void:
	_refresh_catalog()
	_update_top_bar()


func _on_play_session_started(session_id: String, payload: Dictionary) -> void:
	_active_session_id = session_id
	_download_progress = 0.0
	_update_store_action_state()
	_open_linkchat_dm()
	var game: Dictionary = payload.get("game", {})
	_set_notice("正在准备《%s》的下载..." % str(game.get("title", "未命名作品")))


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


func _on_play_session_completed(session_id: String, _payload: Dictionary) -> void:
	if session_id != _active_session_id:
		return

	_active_session_id = ""
	_download_progress = 0.0
	set_process(false)
	_close_download_window()
	_update_store_action_state()
	_update_top_bar()
	_set_notice("")


func _on_play_session_failed(error_message: String) -> void:
	_active_session_id = ""
	_download_progress = 0.0
	set_process(false)
	_close_download_window()
	_update_store_action_state()
	_set_notice(error_message)


func _update_top_bar() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and _money_label != null:
		_money_label.text = "钱包余额：¥ %d" % int(gm.money)


func _update_store_action_state() -> void:
	if _start_button == null:
		return

	_start_button.disabled = _selected_game_id.is_empty() or not _active_session_id.is_empty()
	_start_button.text = "正在下载..." if not _active_session_id.is_empty() else "一起开玩"


func _build_sbeam_preview_payload(entry: Dictionary) -> Dictionary:
	var meta_parts: Array[String] = []
	var genre: String = str(entry.get("genre", "")).strip_edges()
	if not genre.is_empty():
		meta_parts.append(genre)
	var review_summary: String = str(entry.get("recent_reviews_summary", "")).strip_edges()
	if not review_summary.is_empty():
		meta_parts.append(review_summary)

	return {
		"title": str(entry.get("title", "SBEAM")),
		"rewards": (entry.get("rewards", {}) as Dictionary).duplicate(true),
		"text": " / ".join(meta_parts),
	}


func _set_active_view(view_id: String) -> void:
	if view_id != VIEW_STORE and view_id != VIEW_LIBRARY:
		return

	_current_view = view_id
	if _store_content != null:
		_store_content.visible = view_id == VIEW_STORE
	if _library_content != null:
		_library_content.visible = view_id == VIEW_LIBRARY

	_refresh_nav_buttons()
	if view_id == VIEW_LIBRARY:
		_refresh_library_view()


func _refresh_nav_buttons() -> void:
	_set_nav_button_active(_store_nav_button, _current_view == VIEW_STORE)
	_set_nav_button_active(_library_nav_button, _current_view == VIEW_LIBRARY)
	_set_nav_button_active(_community_nav_button, false)


func _set_nav_button_active(button: Button, active: bool) -> void:
	if button == null:
		return

	button.add_theme_color_override("font_color", Color("#1a9fff") if active else Color("#c7d5e0"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6f7f"))


func _find_library_game(game_id: String) -> Dictionary:
	for game in _library_games:
		if str(game.get("game_id", "")) == game_id:
			return game
	return {}


func _launch_library_game(game_id: String) -> Control:
	var existing := _find_open_library_window(game_id)
	if existing != null:
		_focus_library_window(existing)
		_set_notice("")
		_refresh_library_view()
		return existing

	var game := _find_library_game(game_id)
	if game.is_empty():
		_set_notice("未找到该游戏。")
		return null

	var scene: PackedScene = game.get("scene", null)
	if scene == null:
		_set_notice("游戏内容暂不可用。")
		return null

	var content: Control = scene.instantiate() as Control
	if content == null:
		_set_notice("游戏启动失败。")
		return null

	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.window_manager if app_manager != null else null
	if window_manager == null or not window_manager.has_method("create_window"):
		content.queue_free()
		_set_notice("窗口管理器不可用。")
		return null

	var window: Control = window_manager.create_window(str(game.get("window_title", "小游戏")), content)
	if window == null:
		content.queue_free()
		_set_notice("窗口创建失败。")
		return null

	window.set_meta("library_game_id", game_id)
	window.set_meta("library_source", "sbeam")
	window.min_size = Vector2(460, 560)
	window.size = Vector2(560, 720)
	window.tree_exited.connect(_forget_library_window.bind(game_id), CONNECT_ONE_SHOT)

	_library_windows[game_id] = window
	_refresh_library_view()
	_set_notice("")

	# 连接统计信号（通用接口）
	if content.has_signal("stats_changed"):
		content.stats_changed.connect(_on_library_game_stats_changed.bind(game_id))
		# 从存档恢复历史最高分
		var saved: Array = _get_persisted_stats(game_id)
		if not saved.is_empty() and content.has_method("restore_best_score"):
			for s in saved:
				if s is Dictionary and str(s.get("label", "")) == "最高得分":
					content.restore_best_score(int(str(s.get("value", "0"))))
					break
		call_deferred("_refresh_score_display", game_id)
	return window


func _find_open_library_window(game_id: String) -> Control:
	if _library_windows.has(game_id):
		var cached: Control = _library_windows[game_id]
		if cached != null and is_instance_valid(cached):
			return cached
		_library_windows.erase(game_id)

	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.window_manager if app_manager != null else null
	if window_manager == null or not window_manager.has_method("get_windows"):
		return null

	for candidate in window_manager.get_windows():
		if candidate == null or not is_instance_valid(candidate):
			continue
		if str(candidate.get_meta("library_game_id", "")) == game_id:
			_library_windows[game_id] = candidate
			return candidate
	return null


func _focus_library_window(window: Control) -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.window_manager if app_manager != null else null
	if window_manager == null:
		return

	if window.is_minimized:
		window_manager.restore_window(window)
	else:
		window_manager.focus_window(window)


func _forget_library_window(game_id: String) -> void:
	if _library_windows.has(game_id):
		_library_windows.erase(game_id)
	if is_inside_tree():
		_refresh_library_view()


func _open_linkchat_dm() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("launch_app"):
		return

	var window: Control = app_manager.launch_app("linkchat")
	if window != null:
		call_deferred("_select_linkchat_dm", window)


func _select_linkchat_dm(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return

	var content: Variant = window.get("content")
	if content != null and content.has_method("select_channel"):
		content.select_channel("dm_lin_xia")


func _show_download_window(game_data: Variant) -> void:
	_close_download_window()

	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.window_manager if app_manager != null else null
	if window_manager == null or not window_manager.has_method("create_window"):
		return

	var game: Dictionary = game_data if game_data is Dictionary else {}
	var refs := SbeamUIBuilder.build_download_window_content(game, DOWNLOAD_STAGES)
	var outer: Control = refs.get("root")
	_download_title_label = refs.get("title_label")
	_download_stage_label = refs.get("stage_label")
	_download_progress_bar = refs.get("progress_bar")

	_download_window = window_manager.create_window("下载中", outer)
	if _download_window != null:
		_download_window.min_size = Vector2(420, 220)
		_download_window.size = Vector2(580, 300)


func _close_download_window() -> void:
	if _download_window == null or not is_instance_valid(_download_window):
		_download_window = null
		_download_title_label = null
		_download_stage_label = null
		_download_progress_bar = null
		return

	var app_manager: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_manager.window_manager if app_manager != null else null
	if window_manager != null and window_manager.has_method("close_window"):
		window_manager.close_window(_download_window)
	else:
		_download_window.queue_free()

	_download_window = null
	_download_title_label = null
	_download_stage_label = null
	_download_progress_bar = null


func _set_notice(text_value: String) -> void:
	if _notice_label != null:
		_notice_label.text = text_value


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _wrap_notice(label: Label) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_child(label)
	return margin


func _apply_primary_button_style(button: Button) -> void:
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


func _make_panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _make_panel_style(bg, 10)
	style.set_border_width_all(1)
	style.border_color = border
	return style
