class_name DateEventPlayer extends Control
## AVG 剧情播放器 APP
## 包含首页、播放记录、普通 AVG 播放、streaming AVG 播放
## 外部通过 play_scene_package / play_event / play_stream_package 触发播放，播放结束后回到首页

signal playback_finished(session_id: String, outcome: Dictionary)
## 剧情开始播放时发出（用于通知 music_player 之类的 App 进入互斥状态）
## 注意：只在真正进入播放页并成功启动对应播放器时发出
signal playback_started(session_id: String)

enum Page { HOME, HISTORY, PLAYBACK, STREAMING }

const CHOICE_VAR_ID: String = "var_001"
const DESIGN_RESOLUTION: Vector2 = Vector2(2560, 1440)

## 历史记录
const MAX_HISTORY_ENTRIES: int = 50

# -- 播放区节点 --
@onready var scene_runner: Control = %AVGSceneRunner
@onready var title_label: Label = %TitleLabel
@onready var content_container: Control = %ContentContainer
@onready var preview_container: SubViewportContainer = %PreviewContainer

# -- 页面节点 --
@onready var top_bar: PanelContainer = %TopBar
@onready var content_area: Control = %ContentArea
@onready var home_page: ScrollContainer = %HomePage
@onready var history_page: ScrollContainer = %HistoryPage
@onready var playback_page: Control = %PlaybackPage
@onready var streaming_page: Control = %StreamingPage
@onready var home_content: VBoxContainer = %HomeContent
@onready var history_list: VBoxContainer = %HistoryList
@onready var streaming_player: Control = %StreamingAVGPlayer

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

## 历史数据缓存
var _history_entries: Array = []
## Whether we paused the global AudioManager BGM during playback
var _did_pause_global_bgm: bool = false
## 是否正处于剧情播放中（介于 scene_runner.start() 和 _emit_outcome() 之间）
var _is_playing_scene: bool = false


func _ready() -> void:
	if scene_runner != null:
		scene_runner.scene_ended.connect(_on_scene_ended)
	if streaming_player != null and streaming_player.has_signal("stream_finished"):
		streaming_player.stream_finished.connect(_on_stream_finished)
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
	if streaming_page != null:
		streaming_page.visible = (page == Page.STREAMING)

	# 顶部导航在播放时隐藏
	if top_bar != null:
		top_bar.visible = (page != Page.PLAYBACK and page != Page.STREAMING)

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

	# 剧情信息
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
	_stop_streaming_player()
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
	_stop_streaming_player()
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


func play_stream_package(session_id: String, stream_package: Dictionary, record_history: bool = true) -> void:
	_session_id = session_id
	_event_request.clear()
	_scene_package = stream_package.duplicate(true)
	_finished = false
	_record_history_on_finish = record_history
	print("[DateEventPlayer] Playing stream_package (session=%s)" % session_id)
	if title_label != null:
		title_label.text = str(_scene_package.get("title", "直播"))

	navigate_to(Page.STREAMING)

	if streaming_player == null or not streaming_player.has_method("play"):
		_emit_outcome({"success": false, "error": "invalid_stream_player"})
		return

	if scene_runner != null and scene_runner.has_method("stop"):
		scene_runner.stop()
	set_process(false)
	_pause_global_bgm()
	_is_playing_scene = true
	streaming_player.call("play", session_id, _scene_package)
	if not _finished:
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


func _on_stream_finished(_finished_session_id: String, outcome: Dictionary) -> void:
	if _finished:
		return
	_emit_outcome(outcome)


func _emit_outcome(outcome: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_is_playing_scene = false
	set_process(false)
	_resume_global_bgm()

	if _record_history_on_finish:
		var title: String = ""
		if title_label != null:
			title = title_label.text.strip_edges()
		_add_history_entry(_session_id, title, "", str(outcome.get("summary", outcome.get("choice_text", ""))))

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


func _stop_streaming_player() -> void:
	if streaming_player != null and streaming_player.has_method("stop"):
		streaming_player.call("stop")


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


func enable_thumbnail_capture() -> void:
	pass


func get_cover_image() -> Image:
	return null


func get_first_capture() -> Image:
	return null


func save_cover_to_disk(_unused_session_id: String) -> String:
	return ""


# =============================================================================
# 历史记录持久化
# =============================================================================

func _add_history_entry(session_id: String, title: String, _cover_path: String, outcome_summary: String) -> void:
	var entry := {
		"session_id": session_id,
		"title": title,
		"timestamp": int(Time.get_unix_time_from_system()),
		"outcome_summary": outcome_summary,
	}
	# 新条目放在最前面
	_history_entries.insert(0, entry)
	if _history_entries.size() > MAX_HISTORY_ENTRIES:
		_history_entries.resize(MAX_HISTORY_ENTRIES)
	# 写入 DateManager，随存档持久化
	var dm := _get_date_manager()
	if dm != null:
		dm.add_avg_history_entry(entry)


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
