class_name DateEventPlayer extends Control
## AVG 剧情播放器 APP
## 包含三个页面：首页 (Home) / 播放记录 (History) / 播放 (Playback)
## 外部通过 play_scene_package / play_event 触发播放，播放结束后回到首页

signal playback_finished(session_id: String, outcome: Dictionary)
## 剧情开始播放时发出（用于通知 music_player 之类的 App 进入互斥状态）
## 注意：只在真正进入 PLAYBACK 页并成功启动 scene_runner 时发出
signal playback_started(session_id: String)

enum Page { HOME, HISTORY, PLAYBACK }

const CHOICE_VAR_ID: String = "var_001"
const DESIGN_RESOLUTION: Vector2 = Vector2(2560, 1440)

## 截图相关常量
const THUMBNAIL_DIR: String = "user://avg_thumbnails"
const THUMBNAIL_SIZE: Vector2i = Vector2i(640, 360)
const MAX_ROLLING_CAPTURES: int = 3
const CAPTURE_WORTHY_COMMANDS: Array[String] = [
	"CHANGE_BACKGROUND", "DIALOGUE", "SHOW_CHARACTER", "CHOICE",
]
const CAPTURE_DELAY: float = 0.3

## 历史记录
const MAX_HISTORY_ENTRIES: int = 50

# -- 播放区节点 --
@onready var scene_runner: Control = %AVGSceneRunner
@onready var title_label: Label = %TitleLabel
@onready var content_container: Control = %ContentContainer
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var preview_viewport: SubViewport = %PreviewViewport

# -- 页面节点 --
@onready var top_bar: PanelContainer = %TopBar
@onready var content_area: Control = %ContentArea
@onready var home_page: ScrollContainer = %HomePage
@onready var history_page: ScrollContainer = %HistoryPage
@onready var playback_page: Control = %PlaybackPage
@onready var home_content: VBoxContainer = %HomeContent
@onready var history_list: VBoxContainer = %HistoryList

# -- 导航按钮 --
@onready var nav_home_btn: Button = %NavHomeBtn
@onready var nav_history_btn: Button = %NavHistoryBtn

# -- 状态 --
var _session_id: String = ""
var _event_request: Dictionary = {}
var _scene_package: Dictionary = {}
var _finished: bool = false
var _current_page: Page = Page.HOME
var _record_history_on_finish: bool = true

## 截图功能开关
var _capture_enabled: bool = false
var _rolling_captures: Array[Image] = []
var _first_capture: Image = null
var _capture_timer: Timer = null

## 历史数据缓存
var _history_entries: Array = []
## Whether we paused the global AudioManager BGM during playback
var _did_pause_global_bgm: bool = false
## 是否正处于剧情播放中（介于 scene_runner.start() 和 _emit_outcome() 之间）
var _is_playing_scene: bool = false


func _ready() -> void:
	if scene_runner != null:
		scene_runner.scene_ended.connect(_on_scene_ended)
	if content_container != null:
		content_container.resized.connect(_on_content_resized)
	if preview_container != null:
		preview_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		preview_container.anchor_right = 0.0
		preview_container.anchor_bottom = 0.0

	# 导航信号
	if nav_home_btn != null:
		nav_home_btn.pressed.connect(func() -> void: navigate_to(Page.HOME))
	if nav_history_btn != null:
		nav_history_btn.pressed.connect(func() -> void: navigate_to(Page.HISTORY))

	# 从 DateManager 加载历史数据 & 显示首页
	_history_entries = _get_date_manager_history()
	call_deferred("_on_content_resized")
	call_deferred("_refresh_current_page")
	set_process(false)


# =============================================================================
# 页面导航
# =============================================================================

func navigate_to(page: Page) -> void:
	_current_page = page
	if home_page != null:
		home_page.visible = (page == Page.HOME)
	if history_page != null:
		history_page.visible = (page == Page.HISTORY)
	if playback_page != null:
		playback_page.visible = (page == Page.PLAYBACK)

	# 顶部导航在播放时隐藏
	if top_bar != null:
		top_bar.visible = (page != Page.PLAYBACK)

	# 按钮高亮
	_update_nav_highlight()

	# 刷新页面内容
	_refresh_current_page()


func _update_nav_highlight() -> void:
	if nav_home_btn != null:
		nav_home_btn.button_pressed = (_current_page == Page.HOME)
	if nav_history_btn != null:
		nav_history_btn.button_pressed = (_current_page == Page.HISTORY)


func _refresh_current_page() -> void:
	match _current_page:
		Page.HOME:
			_build_home_page()
		Page.HISTORY:
			_build_history_page()


# =============================================================================
# 首页
# =============================================================================

func _build_home_page() -> void:
	if home_content == null:
		return
	# 清空旧内容
	for child in home_content.get_children():
		child.queue_free()

	# 顶部边距
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 4)
	home_content.add_child(top_spacer)

	if _history_entries.is_empty():
		var empty := _create_empty_state("还没有播放过任何剧情\n等待新的剧情到来...")
		home_content.add_child(empty)
		return

	# 最新剧情 Hero Banner
	var latest: Dictionary = _history_entries[0]
	var hero := _create_hero_banner(latest)
	home_content.add_child(hero)

	# 最近播放（跳过第一个）
	if _history_entries.size() > 1:
		var recent_title := _create_section_title("最近播放")
		home_content.add_child(recent_title)

		var grid := _create_recent_grid()
		home_content.add_child(grid)


func _create_hero_banner(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0, 0, 0, 0.05)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.92, 0.95, 1)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	margin.add_child(hbox)

	# 封面图
	var cover_rect := TextureRect.new()
	cover_rect.custom_minimum_size = Vector2(320, 180)
	cover_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	var cover_path: String = str(entry.get("cover_path", ""))
	if cover_path != "" and FileAccess.file_exists(cover_path):
		var img := Image.load_from_file(cover_path)
		if img != null:
			cover_rect.texture = ImageTexture.create_from_image(img)
	if cover_rect.texture == null:
		# 无封面时显示占位色块
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.9, 0.92, 0.95, 1)
		placeholder.custom_minimum_size = Vector2(320, 180)
		hbox.add_child(placeholder)
	else:
		hbox.add_child(cover_rect)

	# 右侧信息
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 10)
	hbox.add_child(info_vbox)

	var title_lbl := Label.new()
	title_lbl.text = str(entry.get("title", "未知剧情"))
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.15, 0.2, 0.25, 1))
	info_vbox.add_child(title_lbl)

	var summary_lbl := Label.new()
	summary_lbl.text = str(entry.get("outcome_summary", ""))
	summary_lbl.add_theme_font_size_override("font_size", 14)
	summary_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5, 1))
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(summary_lbl)

	var time_lbl := Label.new()
	var ts: int = int(entry.get("timestamp", 0))
	time_lbl.text = _format_timestamp(ts) if ts > 0 else ""
	time_lbl.add_theme_font_size_override("font_size", 12)
	time_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	info_vbox.add_child(time_lbl)

	# 占位弹性空间
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(spacer)

	var tag_label := Label.new()
	tag_label.text = "最新"
	tag_label.add_theme_font_size_override("font_size", 13)
	tag_label.add_theme_color_override("font_color", Color(0, 0.631373, 0.839216, 1))
	info_vbox.add_child(tag_label)

	return panel


func _create_recent_grid() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	margin.add_child(grid)

	# 从第2个开始，最多显示6个
	var count: int = mini(_history_entries.size() - 1, 6)
	for i in range(1, 1 + count):
		var entry: Dictionary = _history_entries[i]
		var card := _create_history_card(entry)
		grid.add_child(card)

	return margin


# =============================================================================
# 历史记录页
# =============================================================================

func _build_history_page() -> void:
	if history_list == null:
		return
	for child in history_list.get_children():
		child.queue_free()

	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 4)
	history_list.add_child(top_spacer)

	if _history_entries.is_empty():
		var empty := _create_empty_state("暂无播放记录")
		history_list.add_child(empty)
		return

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 24)
	list_margin.add_theme_constant_override("margin_right", 24)
	list_margin.add_theme_constant_override("margin_top", 4)
	history_list.add_child(list_margin)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	list_margin.add_child(grid)

	for entry in _history_entries:
		var card := _create_history_card(entry)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)


func _create_history_card(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.04)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.9, 0.94, 0.96, 1)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)

	# 缩略图
	var thumb_rect := TextureRect.new()
	thumb_rect.custom_minimum_size = Vector2(160, 90)
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	var cover_path: String = str(entry.get("cover_path", ""))
	if cover_path != "" and FileAccess.file_exists(cover_path):
		var img := Image.load_from_file(cover_path)
		if img != null:
			thumb_rect.texture = ImageTexture.create_from_image(img)
	if thumb_rect.texture == null:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.92, 0.94, 0.96, 1)
		placeholder.custom_minimum_size = Vector2(160, 90)
		hbox.add_child(placeholder)
	else:
		hbox.add_child(thumb_rect)

	# 信息
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	hbox.add_child(info)

	var card_title := Label.new()
	card_title.text = str(entry.get("title", "未知剧情"))
	card_title.add_theme_font_size_override("font_size", 16)
	card_title.add_theme_color_override("font_color", Color(0.15, 0.2, 0.25, 1))
	info.add_child(card_title)

	var card_summary := Label.new()
	card_summary.text = str(entry.get("outcome_summary", ""))
	card_summary.add_theme_font_size_override("font_size", 13)
	card_summary.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
	card_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(card_summary)

	var card_time := Label.new()
	var ts: int = int(entry.get("timestamp", 0))
	card_time.text = _format_timestamp(ts) if ts > 0 else ""
	card_time.add_theme_font_size_override("font_size", 12)
	card_time.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	info.add_child(card_time)

	# 添加一个轻量级操作区
	var action_vbox := VBoxContainer.new()
	action_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(action_vbox)

	var btn := Button.new()
	var can_replay: bool = bool(entry.get("has_replay", false))
	btn.text = "重播" if can_replay else "无法重播"
	btn.disabled = not can_replay
	btn.add_theme_font_size_override("font_size", 13)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.9, 0.94, 0.98, 1)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	btn_style.content_margin_left = 12
	btn_style.content_margin_right = 12
	btn_style.content_margin_top = 6
	btn_style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_color_override("font_color", Color(0, 0.631373, 0.839216, 1))

	btn.pressed.connect(func() -> void:
		_replay_history_entry(entry)
	)
	action_vbox.add_child(btn)

	return panel


# =============================================================================
# 通用 UI 工具
# =============================================================================

func _create_section_title(text: String) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 2)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.28, 0.36, 1))
	margin.add_child(lbl)
	return margin


func _create_empty_state(text: String) -> Label:
	var empty_label := Label.new()
	empty_label.text = text
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_font_size_override("font_size", 16)
	empty_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.7, 1))
	empty_label.custom_minimum_size = Vector2(0, 220)
	return empty_label


func _create_page_header(text: String) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 6)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.15, 0.2, 0.26, 1))
	margin.add_child(lbl)
	return margin


func _format_timestamp(unix_time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [dt.get("year", 0), dt.get("month", 0), dt.get("day", 0), dt.get("hour", 0), dt.get("minute", 0)]


# =============================================================================
# 播放 (外部接口 — 保持与之前完全兼容)
# =============================================================================

func play_event(session_id: String, event_request: Dictionary, record_history: bool = true) -> void:
	_session_id = session_id
	_event_request = event_request.duplicate(true)
	_scene_package.clear()
	_finished = false
	_record_history_on_finish = record_history
	if title_label != null:
		title_label.text = str(_event_request.get("title", "Important Date"))

	navigate_to(Page.PLAYBACK)

	var project: Resource = _event_request.get("project", null)
	var scene: Resource = _event_request.get("scene", null)
	if project == null or scene == null or scene_runner == null:
		_emit_outcome({"success": false, "error": "invalid_event_request"})
		return

	scene_runner.reset()
	scene_runner.load_project(project)
	scene_runner.load_scene(scene)
	scene_runner.start()
	set_process(true)
	_pause_global_bgm()
	_is_playing_scene = true
	playback_started.emit(_session_id)


func play_scene_package(session_id: String, scene_package: Dictionary, record_history: bool = true) -> void:
	_session_id = session_id
	_event_request.clear()
	_scene_package = scene_package.duplicate(true)
	_finished = false
	_record_history_on_finish = record_history
	print("[DateEventPlayer] Playing scene_package (session=%s):\n%s" % [session_id, str(scene_package.get("scene_outline", "(no outline)"))])
	if title_label != null:
		title_label.text = str(_scene_package.get("title", "Date Scene"))

	navigate_to(Page.PLAYBACK)

	var project: Resource = _scene_package.get("project", null)
	var scene: Resource = _scene_package.get("scene", null)
	if project == null or scene == null or scene_runner == null:
		_emit_outcome({"success": false, "error": "invalid_scene_package"})
		return

	scene_runner.reset()
	scene_runner.load_project(project)
	scene_runner.load_scene(scene)
	scene_runner.start()
	set_process(true)
	_pause_global_bgm()
	_is_playing_scene = true
	playback_started.emit(_session_id)


func _on_scene_ended(_scene_id: String) -> void:
	if _finished:
		return

	var variable_manager: RefCounted = null
	if scene_runner != null and scene_runner.has_method("get_variable_manager"):
		variable_manager = scene_runner.get_variable_manager()

	var choice_id: int = 0
	if variable_manager != null and variable_manager.has_method("get_value_by_id"):
		var choice_value: Variant = variable_manager.get_value_by_id(CHOICE_VAR_ID)
		if choice_value != null:
			choice_id = int(choice_value)

	if not _event_request.is_empty():
		var outcomes: Dictionary = _event_request.get("outcomes", {})
		var selected_outcome: Dictionary = outcomes.get(choice_id, {})
		_emit_outcome({
			"success": true,
			"choice_id": choice_id,
			"choice_text": str(selected_outcome.get("text", "")),
			"summary": str(selected_outcome.get("summary", "")),
			"affection_delta": int(selected_outcome.get("affection_delta", 0)),
			"tag": str(selected_outcome.get("tag", "")),
		})
		return

	var choice_labels: Dictionary = _scene_package.get("choice_labels", {})
	var selected_choice_text: String = str(choice_labels.get(choice_id, "")).strip_edges()
	_emit_outcome({
		"success": true,
		"choice_id": choice_id,
		"choice_text": selected_choice_text,
		"summary": selected_choice_text,
		"affection_delta": 0,
		"tag": "",
	})


func _emit_outcome(outcome: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_is_playing_scene = false
	set_process(false)
	_resume_global_bgm()

	# 保存历史记录（仅首次播放，即截图开启时）
	if _capture_enabled and _record_history_on_finish:
		var cover_path: String = save_cover_to_disk(_session_id)
		var title: String = ""
		if title_label != null:
			title = title_label.text.strip_edges()
		_add_history_entry(_session_id, title, cover_path, str(outcome.get("summary", outcome.get("choice_text", ""))))

	# 标题标记结束
	if title_label != null:
		var ended_title := title_label.text.strip_edges()
		if not ended_title.ends_with(" · 已结束"):
			title_label.text = "%s · 已结束" % ended_title

	playback_finished.emit(_session_id, outcome)

	# 延迟返回首页（给玩家一点时间看结束状态）
	var return_timer := get_tree().create_timer(1.5)
	return_timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			navigate_to(Page.HOME)
	)


func _process(_delta: float) -> void:
	if _finished or scene_runner == null:
		return
	if scene_runner.has_method("is_playback_complete") and scene_runner.is_playback_complete():
		if scene_runner.has_method("stop"):
			scene_runner.stop()
		else:
			_on_scene_ended("")


func _on_content_resized() -> void:
	if content_container == null or preview_container == null:
		return

	var available_size: Vector2 = content_container.size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return

	var aspect_ratio: float = DESIGN_RESOLUTION.x / DESIGN_RESOLUTION.y
	var container_aspect: float = available_size.x / available_size.y

	var new_size: Vector2
	if container_aspect > aspect_ratio:
		new_size.y = available_size.y
		new_size.x = available_size.y * aspect_ratio
	else:
		new_size.x = available_size.x
		new_size.y = available_size.x / aspect_ratio

	preview_container.size = new_size
	preview_container.position = (available_size - new_size) / 2.0


# =============================================================================
# 截图功能
# =============================================================================

func enable_thumbnail_capture() -> void:
	_capture_enabled = true
	_rolling_captures.clear()
	_first_capture = null
	if scene_runner != null and not scene_runner.command_executed.is_connected(_on_command_executed_for_capture):
		scene_runner.command_executed.connect(_on_command_executed_for_capture)


func get_cover_image() -> Image:
	if _rolling_captures.size() > 0:
		return _rolling_captures[_rolling_captures.size() - 1]
	return _first_capture


func get_first_capture() -> Image:
	return _first_capture


func _on_command_executed_for_capture(command_type: String, _command_index: int) -> void:
	if not _capture_enabled or _finished:
		return
	if command_type not in CAPTURE_WORTHY_COMMANDS:
		return
	_schedule_capture()


func _schedule_capture() -> void:
	if _capture_timer != null and is_instance_valid(_capture_timer):
		_capture_timer.stop()
		_capture_timer.queue_free()
	_capture_timer = Timer.new()
	_capture_timer.wait_time = CAPTURE_DELAY
	_capture_timer.one_shot = true
	_capture_timer.timeout.connect(_do_capture)
	add_child(_capture_timer)
	_capture_timer.start()


func _do_capture() -> void:
	if _capture_timer != null and is_instance_valid(_capture_timer):
		_capture_timer.queue_free()
		_capture_timer = null

	if preview_viewport == null or not is_instance_valid(preview_viewport):
		return

	var image: Image = preview_viewport.get_texture().get_image()
	if image == null:
		return

	image.resize(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, Image.INTERPOLATE_LANCZOS)

	if _first_capture == null:
		_first_capture = image

	_rolling_captures.append(image)
	if _rolling_captures.size() > MAX_ROLLING_CAPTURES:
		_rolling_captures.remove_at(0)


func save_cover_to_disk(session_id: String) -> String:
	var cover: Image = get_cover_image()
	if cover == null:
		return ""

	if not DirAccess.dir_exists_absolute(THUMBNAIL_DIR):
		DirAccess.make_dir_recursive_absolute(THUMBNAIL_DIR)

	var file_path: String = "%s/%s_cover.png" % [THUMBNAIL_DIR, session_id]
	var err: int = cover.save_png(file_path)
	if err != OK:
		push_warning("DateEventPlayer: Failed to save cover image to %s (error %d)" % [file_path, err])
		return ""
	return file_path


# =============================================================================
# 历史记录持久化
# =============================================================================

func _add_history_entry(session_id: String, title: String, cover_path: String, outcome_summary: String) -> void:
	var entry := {
		"session_id": session_id,
		"title": title,
		"timestamp": int(Time.get_unix_time_from_system()),
		"cover_path": cover_path,
		"outcome_summary": outcome_summary,
	}
	var replay_info := _register_current_replay_payload(session_id)
	if not replay_info.is_empty():
		entry["has_replay"] = true
		entry["replay_type"] = str(replay_info.get("type", ""))
	# 新条目放在最前面
	_history_entries.insert(0, entry)
	if _history_entries.size() > MAX_HISTORY_ENTRIES:
		_history_entries.resize(MAX_HISTORY_ENTRIES)
	# 写入 DateManager，随存档持久化
	var dm := _get_date_manager()
	if dm != null:
		dm.add_avg_history_entry(entry)


func _register_current_replay_payload(session_id: String) -> Dictionary:
	var replay_type: String = ""
	var replay_payload: Dictionary = {}
	if not _event_request.is_empty():
		replay_type = "event_request"
		replay_payload = _event_request.duplicate(true)
	elif not _scene_package.is_empty():
		replay_type = "scene_package"
		replay_payload = _scene_package.duplicate(true)
	if replay_payload.is_empty():
		return {}

	var dm := _get_date_manager()
	if dm != null and dm.has_method("register_avg_history_replay"):
		dm.register_avg_history_replay(session_id, replay_type, replay_payload)
	return {"type": replay_type}


func _replay_history_entry(entry: Dictionary) -> void:
	var session_id := str(entry.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		return

	var replay := _get_history_replay(session_id)
	if replay.is_empty():
		return
	var replay_type := str(replay.get("type", "")).strip_edges()
	var payload_value: Variant = replay.get("payload", {})
	if not payload_value is Dictionary:
		return
	var payload: Dictionary = payload_value
	if payload.is_empty():
		return

	match replay_type:
		"event_request":
			play_event(session_id, payload, false)
		"scene_package":
			play_scene_package(session_id, payload, false)


func _get_history_replay(session_id: String) -> Dictionary:
	var dm := _get_date_manager()
	if dm != null and dm.has_method("get_avg_history_replay"):
		return dm.get_avg_history_replay(session_id)
	return {}


func _get_date_manager() -> Node:
	var dm: Node = get_node_or_null("/root/DateManager")
	return dm


func _get_date_manager_history() -> Array:
	var dm := _get_date_manager()
	if dm != null and dm.has_method("get_avg_history"):
		return dm.get_avg_history()
	return []


# =============================================================================
# 全局 BGM 互斥
# =============================================================================

## 是否正处于剧情播放中（供 music_player 等 App 查询）
func is_playing_scene() -> bool:
	return _is_playing_scene


func _pause_global_bgm() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("pause_bgm"):
		_did_pause_global_bgm = true
		audio.pause_bgm()


func _resume_global_bgm() -> void:
	if not _did_pause_global_bgm:
		return
	_did_pause_global_bgm = false
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("resume_bgm"):
		audio.resume_bgm()
