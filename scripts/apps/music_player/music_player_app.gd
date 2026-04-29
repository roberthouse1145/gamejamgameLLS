class_name MusicPlayerApp
extends Control

## 云节拍 — 仿网易云音乐风格的音乐播放器

# ==================== 配色 ====================
const COLOR_BG := Color("#0c0c14")
const COLOR_BG_TOP := Color("#2d0a0a")
const COLOR_ACCENT := Color("#ec4141")
const COLOR_ACCENT_LIGHT := Color("#ff6b6b")
const COLOR_ACCENT_DIM := Color("#8b2424")
const COLOR_TEXT := Color("#ffffff")
const COLOR_TEXT_SEC := Color("#a0a0a8")
const COLOR_TEXT_MUTED := Color("#5a5a66")
const COLOR_PANEL := Color(0.09, 0.09, 0.13, 0.95)
const COLOR_ITEM_HOVER := Color(1, 1, 1, 0.06)
const COLOR_ITEM_ACTIVE := Color("#ec414120")
const COLOR_DIVIDER := Color(1, 1, 1, 0.06)
const COLOR_SLIDER_BG := Color(1, 1, 1, 0.12)
const COLOR_NEEDLE_GLOW := Color("#ec414160")

const BGM_DIR := "res://Assets/sounds/bgm/"

# ==================== 播放模式 ====================
enum PlayMode { SEQUENTIAL, SHUFFLE, SINGLE_LOOP }

# ==================== 状态 ====================
var _playlist: Array[Dictionary] = []    # [{title, path, stream}]
var _current_index: int = -1
var _play_mode: PlayMode = PlayMode.SEQUENTIAL
var _is_playing: bool = false
var _seeking: bool = false
var _owns_bgm: bool = false

# ==================== 节点引用 ====================
var _disc_container: Control = null
var _disc_circle: Control = null
var _disc_rotation: float = 0.0
var _title_label: Label = null
var _artist_label: Label = null
var _time_current: Label = null
var _time_total: Label = null
var _progress_slider: HSlider = null
var _btn_play: Button = null
var _btn_prev: Button = null
var _btn_next: Button = null
var _btn_mode: Button = null
var _playlist_container: VBoxContainer = null
var _song_items: Array[Control] = []
var _now_playing_header: Label = null

var _audio_manager: Node = null
var _app_manager: Node = null
var _disabled_overlay: ColorRect = null
var _disabled_label: Label = null
var _is_disabled: bool = false


func _ready() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	_app_manager = get_node_or_null("/root/AppManager")

	_scan_music()
	_build_ui()
	_build_disabled_overlay()

	if _app_manager:
		_app_manager.app_launched.connect(_on_any_app_launched)
		_app_manager.app_closed.connect(_on_any_app_closed)
		if _app_manager.is_app_running("avg_player"):
			_set_disabled(true)

	if _audio_manager:
		if _audio_manager.has_signal("bgm_changed"):
			_audio_manager.bgm_changed.connect(_on_system_bgm_changed)
		if _audio_manager.has_signal("bgm_finished"):
			_audio_manager.bgm_finished.connect(_on_global_bgm_finished)

	if not _sync_from_global_bgm() and _playlist.size() > 0:
		_select_track(0, false)


func _process(_delta: float) -> void:
	if _disc_circle and _is_playing:
		_disc_rotation += _delta * 30.0
		_disc_circle.rotation_degrees = fmod(_disc_rotation, 360.0)
	if not _seeking:
		_refresh_progress_from_global()


# ==================== 扫描音乐 ====================
func _scan_music() -> void:
	var dir := DirAccess.open(BGM_DIR)
	if dir == null:
		push_warning("MusicPlayer: Cannot open BGM directory")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "ogg":
			var display := file_name.get_basename()
			# 去掉 " (loop)" 后缀作为显示名
			display = display.replace(" (loop)", "").strip_edges()
			_playlist.append({
				"title": display,
				"path": BGM_DIR + file_name,
				"stream": null,  # 延迟加载
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	# 按名称排序
	_playlist.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["title"].to_lower() < b["title"].to_lower()
	)


# ==================== 构建 UI ====================
func _build_ui() -> void:
	# 底色
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 主容器
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# ---- 上半部分：封面 + 信息 ----
	_build_top_section(root_vbox)
	# ---- 进度条 ----
	_build_progress_section(root_vbox)
	# ---- 控制按钮 ----
	_build_controls(root_vbox)
	# ---- 分隔 ----
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = COLOR_DIVIDER
	sep_style.content_margin_top = 0
	sep_style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.add_theme_constant_override("separation", 1)
	root_vbox.add_child(sep)
	# ---- 播放列表头 ----
	_build_playlist_header(root_vbox)
	# ---- 歌曲列表 ----
	_build_playlist(root_vbox)


func _build_top_section(parent: VBoxContainer) -> void:
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 260)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = COLOR_BG
	top_style.content_margin_left = 0
	top_style.content_margin_right = 0
	top_style.content_margin_top = 0
	top_style.content_margin_bottom = 0
	top.add_theme_stylebox_override("panel", top_style)
	parent.add_child(top)

	# 渐变背景
	var grad_rect := TextureRect.new()
	var grad_tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([COLOR_BG_TOP, Color("#1a0a0a"), COLOR_BG])
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.5, 0)
	grad_tex.fill_to = Vector2(0.5, 1)
	grad_tex.width = 4
	grad_tex.height = 4
	grad_rect.texture = grad_tex
	grad_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
	top.add_child(grad_rect)

	# 居中容器
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_theme_constant_override("separation", 8)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(center)

	# 唱片容器
	_disc_container = CenterContainer.new()
	_disc_container.custom_minimum_size = Vector2(0, 140)
	center.add_child(_disc_container)

	# 唱片视觉 (用嵌套圆形模拟)
	_disc_circle = Control.new()
	_disc_circle.custom_minimum_size = Vector2(130, 130)
	_disc_circle.pivot_offset = Vector2(65, 65)
	_disc_container.add_child(_disc_circle)

	# 外圈
	var outer_ring := _create_circle_panel(130, Color("#1a1a1a"), Color("#333333"), 2)
	_disc_circle.add_child(outer_ring)

	# 唱片纹理（深色圆环）
	var mid_ring := _create_circle_panel(100, Color("#0d0d0d"), COLOR_ACCENT_DIM, 1)
	mid_ring.position = Vector2(15, 15)
	_disc_circle.add_child(mid_ring)

	# 中心标签（音符图标）
	var inner := _create_circle_panel(40, COLOR_ACCENT, COLOR_ACCENT_LIGHT, 2)
	inner.position = Vector2(45, 45)
	_disc_circle.add_child(inner)

	var note_label := Label.new()
	note_label.text = "♪"
	note_label.add_theme_font_size_override("font_size", 20)
	note_label.add_theme_color_override("font_color", COLOR_TEXT)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_child(note_label)

	# 发光效果
	var glow := _create_circle_panel(140, Color.TRANSPARENT, COLOR_NEEDLE_GLOW, 3)
	glow.position = Vector2(-5, -5)
	glow.modulate.a = 0.4
	_disc_circle.add_child(glow)

	# 歌名
	_title_label = Label.new()
	_title_label.text = "未播放"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_title_label)

	# 艺术家
	_artist_label = Label.new()
	_artist_label.text = "GameJam OST"
	_artist_label.add_theme_font_size_override("font_size", 12)
	_artist_label.add_theme_color_override("font_color", COLOR_TEXT_SEC)
	_artist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_artist_label)


func _build_progress_section(parent: VBoxContainer) -> void:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", 24)
	wrapper.add_theme_constant_override("margin_right", 24)
	wrapper.add_theme_constant_override("margin_top", 4)
	wrapper.add_theme_constant_override("margin_bottom", 0)
	parent.add_child(wrapper)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	wrapper.add_child(vbox)

	# 滑块
	_progress_slider = HSlider.new()
	_progress_slider.min_value = 0
	_progress_slider.max_value = 100
	_progress_slider.step = 0.1
	_progress_slider.custom_minimum_size = Vector2(0, 24)

	# 滑块样式
	var slider_bg_style := StyleBoxFlat.new()
	slider_bg_style.bg_color = COLOR_SLIDER_BG
	slider_bg_style.set_corner_radius_all(2)
	slider_bg_style.content_margin_top = 10
	slider_bg_style.content_margin_bottom = 10
	_progress_slider.add_theme_stylebox_override("slider", slider_bg_style)

	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = COLOR_ACCENT
	slider_fill.set_corner_radius_all(2)
	slider_fill.content_margin_top = 10
	slider_fill.content_margin_bottom = 10
	_progress_slider.add_theme_stylebox_override("grabber_area", slider_fill)
	_progress_slider.add_theme_stylebox_override("grabber_area_highlight", slider_fill)

	# 滑块抓手
	var grabber_tex := _create_grabber_texture(10, COLOR_TEXT)
	_progress_slider.add_theme_icon_override("grabber", grabber_tex)
	_progress_slider.add_theme_icon_override("grabber_highlight", grabber_tex)
	_progress_slider.add_theme_icon_override("grabber_disabled", grabber_tex)

	_progress_slider.drag_started.connect(func() -> void: _seeking = true)
	_progress_slider.drag_ended.connect(_on_seek_ended)
	_progress_slider.value_changed.connect(_on_slider_value_changed)
	vbox.add_child(_progress_slider)

	# 时间标签行
	var time_row := HBoxContainer.new()
	vbox.add_child(time_row)

	_time_current = Label.new()
	_time_current.text = "0:00"
	_time_current.add_theme_font_size_override("font_size", 10)
	_time_current.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	time_row.add_child(_time_current)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(spacer)

	_time_total = Label.new()
	_time_total.text = "0:00"
	_time_total.add_theme_font_size_override("font_size", 10)
	_time_total.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	time_row.add_child(_time_total)


func _build_controls(parent: VBoxContainer) -> void:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", 30)
	wrapper.add_theme_constant_override("margin_right", 30)
	wrapper.add_theme_constant_override("margin_top", 4)
	wrapper.add_theme_constant_override("margin_bottom", 12)
	parent.add_child(wrapper)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	wrapper.add_child(hbox)

	# 播放模式
	_btn_mode = _create_control_button("🔁", 14)
	_btn_mode.tooltip_text = "顺序播放"
	_btn_mode.pressed.connect(_on_mode_pressed)
	hbox.add_child(_btn_mode)

	# 上一首
	_btn_prev = _create_control_button("⏮", 18)
	_btn_prev.pressed.connect(_on_prev_pressed)
	hbox.add_child(_btn_prev)

	# 播放/暂停 (大按钮)
	_btn_play = Button.new()
	_btn_play.text = "▶"
	_btn_play.custom_minimum_size = Vector2(52, 52)
	var play_style := StyleBoxFlat.new()
	play_style.bg_color = COLOR_ACCENT
	play_style.set_corner_radius_all(26)
	play_style.content_margin_left = 12
	play_style.content_margin_right = 12
	play_style.content_margin_top = 8
	play_style.content_margin_bottom = 8
	_btn_play.add_theme_stylebox_override("normal", play_style)
	var play_hover := play_style.duplicate()
	play_hover.bg_color = COLOR_ACCENT_LIGHT
	_btn_play.add_theme_stylebox_override("hover", play_hover)
	var play_pressed := play_style.duplicate()
	play_pressed.bg_color = COLOR_ACCENT_DIM
	_btn_play.add_theme_stylebox_override("pressed", play_pressed)
	_btn_play.add_theme_font_size_override("font_size", 20)
	_btn_play.add_theme_color_override("font_color", COLOR_TEXT)
	_btn_play.pressed.connect(_on_play_pressed)
	hbox.add_child(_btn_play)

	# 下一首
	_btn_next = _create_control_button("⏭", 18)
	_btn_next.pressed.connect(_on_next_pressed)
	hbox.add_child(_btn_next)

	# 列表按钮 (装饰)
	var btn_list := _create_control_button("☰", 14)
	hbox.add_child(btn_list)


func _build_playlist_header(parent: VBoxContainer) -> void:
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 20)
	header_margin.add_theme_constant_override("margin_right", 20)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 4)
	parent.add_child(header_margin)

	var hbox := HBoxContainer.new()
	header_margin.add_child(hbox)

	_now_playing_header = Label.new()
	_now_playing_header.text = "播放列表 (%d)" % _playlist.size()
	_now_playing_header.add_theme_font_size_override("font_size", 13)
	_now_playing_header.add_theme_color_override("font_color", COLOR_TEXT)
	hbox.add_child(_now_playing_header)


func _build_playlist(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 平滑的滚动体验
	var scroll_style := StyleBoxFlat.new()
	scroll_style.bg_color = Color.TRANSPARENT
	scroll.add_theme_stylebox_override("panel", scroll_style)
	parent.add_child(scroll)

	_playlist_container = VBoxContainer.new()
	_playlist_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playlist_container.add_theme_constant_override("separation", 0)
	scroll.add_child(_playlist_container)

	for i in _playlist.size():
		var item := _create_song_item(i)
		_playlist_container.add_child(item)
		_song_items.append(item)


func _create_song_item(index: int) -> PanelContainer:
	var song: Dictionary = _playlist[index]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 48)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(hbox)

	# 序号
	var num_label := Label.new()
	num_label.text = "%02d" % (index + 1)
	num_label.add_theme_font_size_override("font_size", 12)
	num_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	num_label.custom_minimum_size = Vector2(24, 0)
	num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(num_label)

	# 歌名
	var title := Label.new()
	title.text = song["title"]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(title)

	# 点击绑定
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select_track(index, true)
	)
	# 悬停效果
	panel.mouse_entered.connect(func() -> void:
		if index != _current_index:
			var s := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			s.bg_color = COLOR_ITEM_HOVER
			panel.add_theme_stylebox_override("panel", s)
	)
	panel.mouse_exited.connect(func() -> void:
		if index != _current_index:
			var s := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			s.bg_color = Color.TRANSPARENT
			panel.add_theme_stylebox_override("panel", s)
	)

	return panel


# ==================== 播放控制 ====================
func _select_track(index: int, auto_play: bool = true) -> void:
	if index < 0 or index >= _playlist.size():
		return

	var old_index := _current_index
	_current_index = index
	var song: Dictionary = _playlist[index]
	_ensure_song_stream(index)

	_title_label.text = song["title"]
	_update_playlist_highlight(old_index, index)

	if auto_play:
		_play()
	else:
		_update_time_display()


func _play() -> void:
	if _is_disabled or _audio_manager == null or _current_index < 0:
		return
	var stream: AudioStream = _ensure_song_stream(_current_index)
	if stream == null:
		return
	var current_stream: AudioStream = null
	if _audio_manager.has_method("get_current_bgm_stream"):
		current_stream = _audio_manager.get_current_bgm_stream()
	if current_stream == stream:
		if _audio_manager.has_method("resume_bgm"):
			_audio_manager.resume_bgm()
	else:
		_audio_manager.play_bgm(stream, 0.3)
	_owns_bgm = true
	_is_playing = true
	_btn_play.text = "⏸"
	_update_time_display()


func _pause() -> void:
	if _audio_manager and _audio_manager.has_method("pause_bgm") and _owns_bgm:
		_audio_manager.pause_bgm()
	_is_playing = false
	_btn_play.text = "▶"


func _resume() -> void:
	_play()


func _on_play_pressed() -> void:
	if _is_disabled:
		return
	if _current_index < 0 and _playlist.size() > 0:
		_select_track(0, true)
		return

	if _owns_bgm and not _is_playing:
		_resume()
	elif _is_playing:
		_pause()
	else:
		_play()


func _on_prev_pressed() -> void:
	if _is_disabled:
		return
	if _playlist.size() == 0:
		return
	if _owns_bgm and _audio_manager and _audio_manager.has_method("get_bgm_playback_position") and _audio_manager.get_bgm_playback_position() > 3.0:
		if _audio_manager.has_method("seek_bgm"):
			_audio_manager.seek_bgm(0.0)
		return
	var idx := _current_index - 1
	if idx < 0:
		idx = _playlist.size() - 1
	_select_track(idx, true)


func _on_next_pressed() -> void:
	if _is_disabled:
		return
	_advance_track()


func _advance_track() -> void:
	if _playlist.size() == 0:
		return
	var idx := (_current_index + 1) % _playlist.size()
	_select_track(idx, true)


func _on_mode_pressed() -> void:
	_play_mode = (_play_mode + 1) % 3 as PlayMode
	match _play_mode:
		PlayMode.SEQUENTIAL:
			_btn_mode.text = "🔁"
			_btn_mode.tooltip_text = "顺序播放"
		PlayMode.SHUFFLE:
			_btn_mode.text = "🔀"
			_btn_mode.tooltip_text = "随机播放"
		PlayMode.SINGLE_LOOP:
			_btn_mode.text = "🔂"
			_btn_mode.tooltip_text = "单曲循环"


func _on_seek_ended(value_changed: bool) -> void:
	_seeking = false
	var stream: AudioStream = _get_selected_stream()
	if value_changed and stream and _owns_bgm and _audio_manager and _audio_manager.has_method("seek_bgm"):
		var length: float = stream.get_length()
		_audio_manager.seek_bgm(_progress_slider.value / 100.0 * length)
	_refresh_progress_from_global()


func _on_slider_value_changed(value: float) -> void:
	var stream: AudioStream = _get_selected_stream()
	if _seeking and stream:
		var length: float = stream.get_length()
		_time_current.text = _format_time(value / 100.0 * length)


# ==================== UI 更新 ====================
func _update_playlist_highlight(old_idx: int, new_idx: int) -> void:
	# 还原旧项
	if old_idx >= 0 and old_idx < _song_items.size():
		var old_panel := _song_items[old_idx]
		var s := old_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		s.bg_color = Color.TRANSPARENT
		old_panel.add_theme_stylebox_override("panel", s)
		# 还原数字颜色
		var hbox := old_panel.get_child(0) as HBoxContainer
		(hbox.get_child(0) as Label).add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		(hbox.get_child(1) as Label).add_theme_color_override("font_color", COLOR_TEXT)

	# 高亮新项
	if new_idx >= 0 and new_idx < _song_items.size():
		var new_panel := _song_items[new_idx]
		var s := new_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		s.bg_color = COLOR_ITEM_ACTIVE
		new_panel.add_theme_stylebox_override("panel", s)
		var hbox := new_panel.get_child(0) as HBoxContainer
		(hbox.get_child(0) as Label).add_theme_color_override("font_color", COLOR_ACCENT)
		(hbox.get_child(1) as Label).add_theme_color_override("font_color", COLOR_ACCENT)


func _update_time_display() -> void:
	var stream: AudioStream = _get_selected_stream()
	if stream == null:
		_time_total.text = "0:00"
		_time_current.text = "0:00"
		_progress_slider.set_value_no_signal(0)
		return
	var playback_position: float = 0.0
	if _owns_bgm and _audio_manager and _audio_manager.has_method("get_bgm_playback_position"):
		playback_position = _audio_manager.get_bgm_playback_position()
	var length: float = stream.get_length()
	_time_total.text = _format_time(length)
	_time_current.text = _format_time(playback_position)
	if length > 0.0:
		_progress_slider.set_value_no_signal(playback_position / length * 100.0)
	else:
		_progress_slider.set_value_no_signal(0)


# ==================== 辅助函数 ====================
func _format_time(seconds: float) -> String:
	@warning_ignore("integer_division")
	var m := int(seconds) / 60
	@warning_ignore("integer_division")
	var s := int(seconds) % 60
	return "%d:%02d" % [m, s]


func _create_control_button(icon_text: String, font_size: int) -> Button:
	var btn := Button.new()
	btn.text = icon_text
	btn.custom_minimum_size = Vector2(36, 36)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color.TRANSPARENT
	btn_style.set_corner_radius_all(18)
	btn.add_theme_stylebox_override("normal", btn_style)
	var hover_style := btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_ITEM_HOVER
	btn.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := btn_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(1, 1, 1, 0.1)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", COLOR_TEXT_SEC)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
	return btn


func _create_circle_panel(diameter: float, bg_color: Color, border_color: Color, border_width: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(diameter, diameter)
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(int(diameter / 2.0))
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _create_grabber_texture(tex_size: int, color: Color) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(tex_size / 2.0, tex_size / 2.0)
	var radius := tex_size / 2.0
	for x in tex_size:
		for y in tex_size:
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color.TRANSPARENT)
	return ImageTexture.create_from_image(img)


func _ensure_song_stream(index: int) -> AudioStream:
	if index < 0 or index >= _playlist.size():
		return null
	var song: Dictionary = _playlist[index]
	var stream: AudioStream = song.get("stream", null)
	if stream == null:
		stream = load(song.get("path", "")) as AudioStream
		song["stream"] = stream
		_playlist[index] = song
	return stream


func _get_selected_stream() -> AudioStream:
	return _ensure_song_stream(_current_index)


func _refresh_progress_from_global() -> void:
	if _audio_manager == null or not _owns_bgm:
		return
	var stream: AudioStream = _get_selected_stream()
	if stream == null:
		return
	var current_stream: AudioStream = null
	if _audio_manager.has_method("get_current_bgm_stream"):
		current_stream = _audio_manager.get_current_bgm_stream()
	if current_stream != stream:
		_owns_bgm = false
		_is_playing = false
		_btn_play.text = "▶"
		return
	if _audio_manager.has_method("is_bgm_playing"):
		_is_playing = _audio_manager.is_bgm_playing()
	_btn_play.text = "⏸" if _is_playing else "▶"
	_update_time_display()


func _find_track_index_for_stream(stream: AudioStream) -> int:
	if stream == null:
		return -1
	var resource_path: String = stream.resource_path
	for i in _playlist.size():
		var song: Dictionary = _playlist[i]
		if song.get("path", "") == resource_path:
			return i
		var song_stream: AudioStream = _ensure_song_stream(i)
		if song_stream == stream:
			return i
	return -1


func _sync_from_global_bgm() -> bool:
	if _audio_manager == null or not _audio_manager.has_method("get_current_bgm_stream"):
		return false
	var stream: AudioStream = _audio_manager.get_current_bgm_stream()
	var index: int = _find_track_index_for_stream(stream)
	if index < 0:
		return false
	var old_index := _current_index
	_current_index = index
	var song: Dictionary = _playlist[index]
	_title_label.text = song["title"]
	_update_playlist_highlight(old_index, index)
	_owns_bgm = true
	_is_playing = _audio_manager.is_bgm_playing() if _audio_manager.has_method("is_bgm_playing") else false
	_btn_play.text = "⏸" if _is_playing else "▶"
	_update_time_display()
	return true


# ==================== AVG Player 联动 ====================
func _on_any_app_launched(app_id: String, _window: Control) -> void:
	if app_id == "avg_player":
		_set_disabled(true)


func _on_any_app_closed(app_id: String) -> void:
	if app_id == "avg_player":
		_set_disabled(false)


func _on_system_bgm_changed(stream: AudioStream) -> void:
	var index: int = _find_track_index_for_stream(stream)
	if index >= 0:
		var old_index := _current_index
		_current_index = index
		var song: Dictionary = _playlist[index]
		_title_label.text = song["title"]
		_update_playlist_highlight(old_index, index)
		_owns_bgm = true
		_is_playing = _audio_manager.is_bgm_playing() if _audio_manager and _audio_manager.has_method("is_bgm_playing") else true
		_btn_play.text = "⏸" if _is_playing else "▶"
		_update_time_display()
		return
	_owns_bgm = false
	_is_playing = false
	_btn_play.text = "▶"


func _on_global_bgm_finished(stream: AudioStream) -> void:
	if _is_disabled:
		return
	var selected_stream: AudioStream = _get_selected_stream()
	if selected_stream == null or stream != selected_stream:
		return
	match _play_mode:
		PlayMode.SINGLE_LOOP:
			_play()
		PlayMode.SEQUENTIAL:
			_advance_track()
		PlayMode.SHUFFLE:
			if _playlist.size() <= 1:
				_play()
			else:
				var idx := _current_index
				while idx == _current_index:
					idx = randi() % _playlist.size()
				_select_track(idx, true)


func _set_disabled(disabled: bool) -> void:
	_is_disabled = disabled
	if disabled:
		if _owns_bgm and _audio_manager and _audio_manager.has_method("stop_bgm"):
			_audio_manager.stop_bgm(0.2)
		_owns_bgm = false
		_is_playing = false
		_btn_play.text = "▶"
		_update_time_display()
		if _disabled_overlay:
			_disabled_overlay.visible = true
	else:
		if _disabled_overlay:
			_disabled_overlay.visible = false


func _build_disabled_overlay() -> void:
	_disabled_overlay = ColorRect.new()
	_disabled_overlay.color = Color(0, 0, 0, 0.7)
	_disabled_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_disabled_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_disabled_overlay.visible = false
	add_child(_disabled_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_disabled_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)

	var icon_lbl := Label.new()
	icon_lbl.text = "🎬"
	icon_lbl.add_theme_font_size_override("font_size", 32)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon_lbl)

	_disabled_label = Label.new()
	_disabled_label.text = "AVG 播放中，音乐播放器已暂停"
	_disabled_label.add_theme_font_size_override("font_size", 13)
	_disabled_label.add_theme_color_override("font_color", COLOR_TEXT_SEC)
	_disabled_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_disabled_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_disabled_label)
