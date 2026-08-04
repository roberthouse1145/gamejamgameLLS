class_name GameScreenManager extends RefCounted
## 游戏内子界面管理器
## 负责在运行时渲染菜单、存档、读档、历史记录、设置等覆盖界面。
## 使用 AVGScreenConfig 配置外观，动态构建 UI 节点。

const AVGScreenConfigClass = preload("res://scripts/avg/resources/avg_screen_config.gd")
const AVGSaveManagerClass = preload("res://scripts/avg/runtime/save_manager.gd")
const HistoryManagerClass = preload("res://scripts/avg/runtime/history_manager.gd")
const AVGResourceLoaderClass = preload("res://scripts/avg/assets/avg_resource_loader.gd")

## 界面操作信号
signal screen_closed()
signal resume_requested()
signal save_requested(slot_index: int)
signal load_requested(slot_index: int)
signal return_to_title_requested()
signal quit_requested()

## 当前显示的界面根节点
var _screen_root: Control = null
## 父容器（由外部传入）
var _parent: Control = null
## AVG 设计分辨率
var _project_resolution: Vector2 = Vector2(2560, 1440)
## 游戏本体 AVG 数据
var _game_data: Resource = null
## 存档管理器
var _save_manager: RefCounted = null  # AVGSaveManager
## 历史记录管理器
var _history_manager: RefCounted = null  # HistoryManager
## 当前显示的界面类型（-1 = 无）
var _current_screen_type: int = -1


## 初始化
func setup(parent: Control, resolution: Vector2, game_data: Resource, save_mgr: RefCounted, history_mgr: RefCounted) -> void:
	_parent = parent
	_project_resolution = resolution
	_game_data = game_data
	_save_manager = save_mgr
	_history_manager = history_mgr


## 是否正在显示界面
func is_showing() -> bool:
	return _screen_root != null and is_instance_valid(_screen_root)


## 关闭当前界面
func close_screen() -> void:
	if _screen_root != null and is_instance_valid(_screen_root):
		_screen_root.queue_free()
	_screen_root = null
	_current_screen_type = -1
	screen_closed.emit()


## 显示指定类型的界面
func show_screen(screen_type: int) -> void:
	close_screen()
	_current_screen_type = screen_type
	var config: Resource = _get_config(screen_type)
	if config == null:
		config = AVGScreenConfigClass.new()
		config.init_defaults_for_type(screen_type as AVGScreenConfigClass.ScreenType)

	if not config.enabled:
		return

	_screen_root = Control.new()
	_screen_root.name = "GameScreen"
	_screen_root.size = _project_resolution
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP

	# 背景
	_build_background(config)
	# 标题
	_build_title(config)
	# 内容面板
	var content_panel: Panel = _build_content_panel(config)
	# 内容区域
	_build_content(config, content_panel)
	# 关闭按钮
	_build_close_button(config)

	if _parent != null:
		_parent.add_child(_screen_root)


## 获取配置
func _get_config(screen_type: int) -> Resource:
	if _game_data == null:
		return null
	if not "screen_configs" in _game_data:
		return null
	var key: String = _type_to_key(screen_type)
	return _game_data.screen_configs.get(key, null)


func _type_to_key(t: int) -> String:
	match t:
		0: return "menu"
		1: return "save"
		2: return "load"
		3: return "history"
		4: return "settings"
		_: return "menu"


## 构建背景
func _build_background(config: Resource) -> void:
	var bg := ColorRect.new()
	bg.size = _project_resolution
	bg.color = config.background_color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(bg)

	if not config.background_image.is_empty():
		var tex: Texture2D = AVGResourceLoaderClass.load_texture(config.background_image)
		if tex != null:
			var bg_img := TextureRect.new()
			bg_img.texture = tex
			bg_img.size = _project_resolution
			bg_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_screen_root.add_child(bg_img)


## 构建标题
func _build_title(config: Resource) -> void:
	var label := Label.new()
	label.text = config.get_display_title()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", config.title_font_size)
	label.add_theme_color_override("font_color", config.title_color)
	var label_size := Vector2(_project_resolution.x * 0.5, 80)
	label.size = label_size
	var norm_pos: Vector2 = config.title_norm_position
	label.position = Vector2(
		norm_pos.x * _project_resolution.x - label_size.x / 2.0,
		norm_pos.y * _project_resolution.y - label_size.y / 2.0
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(label)


## 构建内容面板
func _build_content_panel(config: Resource) -> Panel:
	var panel := Panel.new()
	var panel_size: Vector2 = config.panel_norm_size * _project_resolution
	var panel_pos: Vector2 = Vector2(
		config.panel_norm_position.x * _project_resolution.x - panel_size.x / 2.0,
		config.panel_norm_position.y * _project_resolution.y - panel_size.y / 2.0
	)
	panel.position = panel_pos
	panel.size = panel_size
	panel.clip_contents = true

	if config.panel_style != null and config.panel_style.has_method("to_stylebox"):
		panel.add_theme_stylebox_override("panel", config.panel_style.to_stylebox())
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		style.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", style)

	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(panel)
	return panel


## 构建关闭按钮
func _build_close_button(config: Resource) -> void:
	var btn := Button.new()
	btn.text = config.close_button_text
	btn.custom_minimum_size = config.close_button_size
	btn.size = config.close_button_size
	btn.add_theme_font_size_override("font_size", config.close_button_font_size)
	var norm_pos: Vector2 = config.close_button_norm_position
	btn.position = Vector2(
		norm_pos.x * _project_resolution.x - config.close_button_size.x / 2.0,
		norm_pos.y * _project_resolution.y - config.close_button_size.y / 2.0
	)
	_apply_button_style(btn, config)
	btn.pressed.connect(close_screen)
	_screen_root.add_child(btn)


## 构建内容区域（根据类型不同）
func _build_content(config: Resource, content_panel: Panel) -> void:
	match config.screen_type:
		AVGScreenConfigClass.ScreenType.MENU:
			_build_menu_content(config, content_panel)
		AVGScreenConfigClass.ScreenType.SAVE:
			_build_save_load_content(config, content_panel, true)
		AVGScreenConfigClass.ScreenType.LOAD:
			_build_save_load_content(config, content_panel, false)
		AVGScreenConfigClass.ScreenType.HISTORY:
			_build_history_content(config, content_panel)
		AVGScreenConfigClass.ScreenType.SETTINGS:
			_build_settings_content(config, content_panel)


## ---- 菜单 ----
func _build_menu_content(config: Resource, panel: Panel) -> void:
	var container := VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", config.menu_button_spacing)

	var actions: Array[String] = [
		"resume", "save", "load", "history", "settings", "title", "quit"
	]

	for i in range(config.menu_button_texts.size()):
		var text: String = config.menu_button_texts[i]
		var action: String = actions[i] if i < actions.size() else "resume"
		var btn := Button.new()
		btn.text = text
		btn.custom_minimum_size = config.menu_button_size
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", config.menu_button_font_size)
		_apply_button_style(btn, config)
		btn.pressed.connect(_on_menu_action.bind(action))
		container.add_child(btn)

	panel.add_child(container)


func _on_menu_action(action: String) -> void:
	match action:
		"resume":
			close_screen()
			resume_requested.emit()
		"save":
			close_screen()
			show_screen(AVGScreenConfigClass.ScreenType.SAVE)
		"load":
			close_screen()
			show_screen(AVGScreenConfigClass.ScreenType.LOAD)
		"history":
			close_screen()
			show_screen(AVGScreenConfigClass.ScreenType.HISTORY)
		"settings":
			close_screen()
			show_screen(AVGScreenConfigClass.ScreenType.SETTINGS)
		"title":
			close_screen()
			return_to_title_requested.emit()
		"quit":
			close_screen()
			quit_requested.emit()


## ---- 存档/读档 ----
func _build_save_load_content(config: Resource, panel: Panel, is_save: bool) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var grid := GridContainer.new()
	grid.columns = config.grid_columns
	grid.add_theme_constant_override("h_separation", config.slot_spacing)
	grid.add_theme_constant_override("v_separation", config.slot_spacing)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 获取已有存档摘要
	var summaries: Dictionary = {}
	if _save_manager != null:
		summaries = _save_manager.get_all_slot_summaries(config.slot_count)

	for i in range(config.slot_count):
		var slot := _create_slot_button(i, config, summaries.get(i, {}), is_save)
		grid.add_child(slot)

	scroll.add_child(grid)
	margin.add_child(scroll)
	panel.add_child(margin)


func _create_slot_button(slot_index: int, config: Resource, summary: Dictionary, is_save: bool) -> Control:
	var slot := Button.new()
	slot.custom_minimum_size = config.slot_size
	slot.clip_text = true

	if summary.is_empty():
		slot.text = "空槽位 %d" % (slot_index + 1)
		slot.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		# 空槽位：存档可用，读档不可用
		if not is_save:
			slot.disabled = true
	else:
		var display: String = "槽位 %d\n%s" % [slot_index + 1, summary.get("timestamp", "")]
		var text_preview: String = summary.get("text", "")
		if not text_preview.is_empty():
			display += "\n" + text_preview.left(30)
		slot.text = display

	_apply_button_style(slot, config)

	if is_save:
		slot.pressed.connect(_on_save_slot_pressed.bind(slot_index))
	else:
		slot.pressed.connect(_on_load_slot_pressed.bind(slot_index))

	return slot


func _on_save_slot_pressed(slot_index: int) -> void:
	save_requested.emit(slot_index)
	# 刷新界面
	close_screen()
	show_screen(AVGScreenConfigClass.ScreenType.SAVE)


func _on_load_slot_pressed(slot_index: int) -> void:
	load_requested.emit(slot_index)
	close_screen()


## ---- 历史记录 ----
func _build_history_content(config: Resource, panel: Panel) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 20)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", config.history_entry_spacing)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var entries: Array[Dictionary] = []
	if _history_manager != null:
		entries = _history_manager.get_entries()

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无历史记录"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(empty_label)
	else:
		for entry in entries:
			var entry_vbox := VBoxContainer.new()
			entry_vbox.add_theme_constant_override("separation", 2)

			var speaker: String = entry.get("speaker", "")
			if not speaker.is_empty():
				var speaker_label := Label.new()
				speaker_label.text = speaker
				speaker_label.add_theme_font_size_override("font_size", config.history_entry_font_size)
				speaker_label.add_theme_color_override("font_color", config.history_speaker_color)
				speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				entry_vbox.add_child(speaker_label)

			var text_label := Label.new()
			text_label.text = entry.get("text", "")
			text_label.add_theme_font_size_override("font_size", config.history_entry_font_size)
			text_label.add_theme_color_override("font_color", Color.WHITE)
			text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry_vbox.add_child(text_label)

			var sep := HSeparator.new()
			sep.modulate = Color(1, 1, 1, 0.2)
			entry_vbox.add_child(sep)

			entry_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(entry_vbox)

	scroll.add_child(vbox)
	margin.add_child(scroll)
	panel.add_child(margin)

	# 滚动到底部（最新记录）
	scroll.call_deferred("set_v_scroll", 999999)


## ---- 设置 ----
func _build_settings_content(_config: Resource, panel: Panel) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)

	# TODO: 实际设置项需要与音频管理器等集成
	var settings_items: Array[Dictionary] = [
		{"label": "BGM 音量", "key": "bgm_volume", "value": 70},
		{"label": "SE 音量", "key": "se_volume", "value": 70},
		{"label": "文字速度", "key": "text_speed", "value": 50},
		{"label": "自动播放速度", "key": "auto_speed", "value": 50},
	]

	for item in settings_items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var label := Label.new()
		label.text = item["label"]
		label.custom_minimum_size.x = 200
		label.add_theme_color_override("font_color", Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.value = item["value"]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)

		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)

	margin.add_child(vbox)
	panel.add_child(margin)


## 将 config.button_style（AVGStyleBox）的四状态应用到按钮
func _apply_button_style(btn: BaseButton, config: Resource) -> void:
	if config == null:
		return
	if "button_style" in config and config.button_style != null and config.button_style.has_method("apply_to_button"):
		config.button_style.apply_to_button(btn)
