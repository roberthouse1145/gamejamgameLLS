extends MinigameBase
## 代码打字小游戏 — 关键字飘落
##
## 伪 IDE 界面中，代码关键字从代码行之间飘落。
## 玩家在底部输入框打字命中飘落的关键字即消除。
## 连击积累分数。漏掉的关键字累积 Bug 进度条，满则游戏结束。

#region 关键字库
const KEYWORD_FILE := "res://resources/minigame/typing_keywords.txt"
var _keyword_pool: Array[String] = []

static func _load_keywords_from_file(path: String) -> Array[String]:
	var result: Array[String] = []
	if not FileAccess.file_exists(path):
		push_warning("[TypingCode] Keyword file not found: " + path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if not line in result:
			result.append(line)
	return result
#endregion

#region 代码片段库（背景装饰用）
const CODE_SNIPPETS: Array[Dictionary] = [
	{
		"title": "save_manager.gd",
		"tab_name": "存档系统",
		"lines": [
			"# SaveManager.serialize_slot()",
			"func serialize_slot(slot_id: int) -> Dictionary:",
			"\tvar snapshot := {}",
			"\tsnapshot[\"version\"] = SAVE_FORMAT_VERSION",
			"\tsnapshot[\"timestamp\"] = Time.get_unix_time()",
			"\tsnapshot[\"scene_id\"] = current_scene.scene_id",
			"\tsnapshot[\"variables\"] = _deep_copy(runtime_vars)",
			"\tsnapshot[\"character_states\"] = _capture_characters()",
			"\tsnapshot[\"dialog_history\"] = dialog_log.slice(-50)",
			"\tvar compressed := _compress_snapshot(snapshot)",
			"\tFileAccess.store_var(compressed, slot_path(slot_id))",
			"\tsave_completed.emit(slot_id)",
			"\treturn snapshot",
		],
	},
	{
		"title": "message_router.gd",
		"tab_name": "聊天系统",
		"lines": [
			"# MessageRouter.dispatch()",
			"func dispatch(msg: ChatMessage) -> void:",
			"\tvar channel := resolve_channel(msg.channel_id)",
			"\tif channel == null:",
			"\t\tpush_warning(\"Channel not found\")",
			"\t\treturn",
			"\tif msg.is_system:",
			"\t\tchannel.append_system(msg)",
			"\t\treturn",
			"\tvar filtered := InputGuard.sanitize(msg.text)",
			"\tmsg.text = filtered",
			"\tchannel.append(msg)",
			"\tnpc_reply_queue.enqueue(channel, msg)",
			"\tmessage_dispatched.emit(msg)",
		],
	},
	{
		"title": "transition_ctrl.gd",
		"tab_name": "转场控制器",
		"lines": [
			"# TransitionController.execute()",
			"func execute(transition: TransitionData) -> void:",
			"\tvar old_bg := viewport.get_current_background()",
			"\tvar new_bg := AssetLoader.load_bg(transition.target)",
			"\tmatch transition.effect:",
			"\t\t\"fade\":",
			"\t\t\tawait _crossfade(old_bg, new_bg, transition.duration)",
			"\t\t\"slide_left\":",
			"\t\t\tawait _slide(old_bg, new_bg, Vector2.LEFT)",
			"\t\t\"dissolve\":",
			"\t\t\tawait _dissolve(old_bg, new_bg, 0.8)",
			"\tviewport.set_background(new_bg)",
			"\told_bg.queue_free()",
			"\ttransition_finished.emit()",
		],
	},
	{
		"title": "dialog_presenter.gd",
		"tab_name": "对话演出",
		"lines": [
			"# DialogPresenter.play_text()",
			"func play_text(speaker: String, text: String) -> void:",
			"\t_set_speaker_label(speaker)",
			"\tvar visible_count := 0",
			"\tfor ch in text:",
			"\t\tdialog_label.visible_characters = visible_count",
			"\t\tvisible_count += 1",
			"\t\tif ch in PAUSE_CHARS:",
			"\t\t\tawait get_tree().create_timer(0.15).timeout",
			"\t\telse:",
			"\t\t\tawait get_tree().create_timer(char_delay).timeout",
			"\tdialog_label.visible_characters = -1",
			"\ttext_finished.emit()",
		],
	},
	{
		"title": "choice_evaluator.gd",
		"tab_name": "选项分支",
		"lines": [
			"# ChoiceEvaluator.resolve()",
			"func resolve(choices: Array[ChoiceData]) -> Array:",
			"\tvar visible_choices := []",
			"\tfor choice in choices:",
			"\t\tif choice.condition.is_empty():",
			"\t\t\tvisible_choices.append(choice)",
			"\t\t\tcontinue",
			"\t\tvar result := ExprParser.evaluate(choice.condition)",
			"\t\tif result:",
			"\t\t\tvisible_choices.append(choice)",
			"\t\telif not choice.hidden_when_unmet:",
			"\t\t\tchoice.disabled = true",
			"\t\t\tvisible_choices.append(choice)",
			"\treturn visible_choices",
		],
	},
]
#endregion

#region 游戏常量
## 飘落参数
const FALL_SPEED_BASE: float = 58.0     ## 基础下落速度 px/s
const FALL_SPEED_GROWTH: float = 0.28   ## 每秒加速
const FALL_SPEED_MAX: float = 165.0     ## 最大下落速度
const SPAWN_INTERVAL_BASE: float = 2.05 ## 基础生成间隔
const SPAWN_INTERVAL_MIN: float = 0.52  ## 最小生成间隔
const SPAWN_INTERVAL_DECAY: float = 0.018 ## 间隔衰减/秒
const MAX_FALLING: int = 8              ## 同屏最大飘落数

## Bug 进度条
const BUG_BAR_MAX: float = 10.0         ## Bug 满值（漏掉 10 个即结束）
const BUG_PER_MISS: float = 1.0         ## 每漏一个增加
const BUG_REPAIR_ON_HIT: float = 0.15   ## 每命中减少

## Combo 里程碑
const COMBO_MILESTONES: Dictionary = {
	5: {"text": "NICE!", "color_hex": "#89b4fa"},
	10: {"text": "COOL!", "color_hex": "#a6e3a1"},
	20: {"text": "AMAZING!", "color_hex": "#f9e2af"},
	35: {"text": "FEVER!!", "color_hex": "#f5c2e7"},
	50: {"text": "UNSTOPPABLE!", "color_hex": "#fab387"},
}

const SCORE_PER_HIT: int = 100
const COMBO_BONUS_MULT: float = 0.05    ## 每级 combo 额外分数比例

## IDE 代码推进
const CODE_PROGRESS_HIT_IMPULSE: float = 22.0   ## 每次命中给予的代码推进速度
const CODE_PROGRESS_COMBO_IMPULSE: float = 2.5  ## 连击带来的额外推进速度
const CODE_PROGRESS_DECAY: float = 16.0         ## 推进速度衰减率
const CODE_PROGRESS_MAX_SPEED: float = 110.0    ## 最大推进速度（字符/秒）
#endregion

#region 视觉常量
const FONT_SIZE_CODE: int = 22
const FONT_SIZE_UI: int = 19
const FONT_SIZE_KEYWORD: int = 26
const LINE_HEIGHT: float = 31.0

const BG_EDITOR := Color("#1e1e2e")
const BG_GUTTER := Color("#181825")
const BG_TITLEBAR := Color("#11111b")
const BG_STATUSBAR := Color("#181825")
const BG_TAB_ACTIVE := Color("#1e1e2e")
const BG_TAB_INACTIVE := Color("#11111b")
const TEXT_GHOST := Color(0.58, 0.63, 0.73, 0.25)
const TEXT_CODE_DONE := Color("#cdd6f4")
const TEXT_CODE_TYPED := Color("#f9e2af")
const TEXT_CODE_REMAIN := Color("#6c7086")
const TEXT_CODE_PENDING := Color("#585b70")
const TEXT_TYPED := Color("#a6e3a1")
const TEXT_LINENUM := Color("#585b70")
const TEXT_TITLE := Color("#cdd6f4")
const TEXT_STATUS := Color("#a6adc8")
const ACCENT := Color("#89b4fa")
const COLOR_KEYWORD := Color("#cba6f7")
const COLOR_HIT := Color("#a6e3a1")
const COLOR_MISS := Color("#f38ba8")

# 关键字分类调色板（按语义类型染色）
const KW_COLOR_CTRL := Color("#c7a0ff")   # if/else/for/while/return/break/match — 紫
const KW_COLOR_DECL := Color("#89b4fa")   # var/func/class/signal/enum/extends — 蓝
const KW_COLOR_TYPE := Color("#94e2d5")   # int/float/bool/Vector2/String/null — 青
const KW_COLOR_LOGIC := Color("#f5c2e7")  # and/or/not/in/is/as/await — 粉
const KW_COLOR_DEFAULT := Color("#f9e2af") # 内置函数 / 其余 — 黄

const KW_SET_CTRL: Array[String] = ["if", "else", "elif", "for", "while", "match", "return", "break", "continue", "pass", "when", "then"]
const KW_SET_DECL: Array[String] = ["var", "const", "func", "class", "class_name", "enum", "signal", "static", "extends", "@export", "@onready", "@tool", "@warning_ignore"]
const KW_SET_TYPE: Array[String] = ["int", "float", "bool", "String", "Array", "Dictionary", "Vector2", "Vector3", "Color", "null", "true", "false", "void", "Variant", "Node", "Node2D", "Control", "Callable", "StringName", "NodePath"]
const KW_SET_LOGIC: Array[String] = ["and", "or", "not", "in", "is", "as", "await", "yield"]
const COLOR_INPUT_BG := Color("#313244")
const PROGRESS_BG := Color("#313244")
const PROGRESS_FILL := Color("#a6e3a1")
const PROGRESS_WARN := Color("#fab387")
const PROGRESS_DANGER := Color("#f38ba8")
#endregion

#region 游戏状态
var _rng := RandomNumberGenerator.new()

var _snippet_a: Dictionary = {}
var _snippet_b: Dictionary = {}
var _base_lines: Array[String] = []
var _lines: Array[String] = []
var _ghost_labels: Array[RichTextLabel] = []

var _falling_words: Array[Dictionary] = []
var _typed_input: String = ""
var _hits: int = 0
var _misses: int = 0
var _input_errors: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _total_score: int = 0
var _bug_meter: float = 0.0
var _elapsed: float = 0.0
var _spawn_timer: float = 0.0
var _target_hits: int = 24
var _finished: bool = false
var _countdown: float = -1.0
var _countdown_label: Label = null
var _scroll_offset: float = 0.0
var _code_progress_speed: float = 0.0
var _single_set_height: float = 0.0
var _single_line_count: int = 0
var _code_progress_line: int = 0
var _code_progress_char: float = 0.0
#endregion

#region 节点引用
var _root_panel: PanelContainer
var _status_bar: HBoxContainer

var _gutter_panel: PanelContainer
var _gutter: VBoxContainer
var _ghost_container: VBoxContainer
var _code_area: Control
var _keyword_layer: Control
var _input_panel: PanelContainer

var _timer_label: Label
var _build_bar_fill: ColorRect
var _bug_bar_fill: ColorRect
var _status_hits: Label
var _status_bug: Label
var _status_score: Label
var _combo_number: Label
var _combo_label: Label
var _hint_label: Label
var _input_value_label: Label
var _milestone_label: Label
var _flash_rect: ColorRect
#endregion


#region 生命周期
func _on_minigame_start() -> void:
	_rng.randomize()
	_keyword_pool = _load_keywords_from_file(KEYWORD_FILE)
	if _keyword_pool.is_empty():
		push_warning("[TypingCode] Keyword pool empty, using fallback")
		_keyword_pool = ["var", "func", "class", "return", "signal", "export", "process", "connect"]
	_pick_snippets()
	_set_target_hits()
	_scroll_offset = 0.0
	_code_progress_speed = 0.0
	_single_set_height = 0.0
	_code_progress_line = _single_line_count
	_code_progress_char = 0.0
	_build_ui()
	_render_ghost_code()
	_update_input_display()
	_update_progress_bars()
	_update_status_bar()
	_start_countdown()
	set_process(true)
	set_process_input(false)
	_running = false


func _on_minigame_cleanup() -> void:
	set_process(false)
	set_process_input(false)
	for word in _falling_words:
		var label: RichTextLabel = word.get("label", null)
		if label != null and is_instance_valid(label):
			label.queue_free()
	_falling_words.clear()


func _process(delta: float) -> void:
	if _countdown > 0.0:
		_process_countdown(delta)
		return

	if _finished or not _running:
		return

	_elapsed += delta
	_spawn_timer -= delta
	_timer_label.text = "%d s" % ceili(_elapsed)

	if _spawn_timer <= 0.0 and _falling_words.size() < MAX_FALLING:
		_spawn_keyword()
		_spawn_timer = _current_spawn_interval()

	_update_code_scroll(delta)
	_update_falling_words(delta)
	_update_progress_bars()

	if _hits >= _target_hits:
		_end_game(true)
	elif _bug_meter >= BUG_BAR_MAX:
		_end_game(false)
#endregion


#region 初始化
func _pick_snippets() -> void:
	var indices: Array[int] = []
	for i in range(CODE_SNIPPETS.size()):
		indices.append(i)
	indices.shuffle()
	_snippet_a = CODE_SNIPPETS[indices[0]]
	_snippet_b = CODE_SNIPPETS[indices[1 % indices.size()]]
	_base_lines.clear()
	for line in _snippet_a.get("lines", []):
		_base_lines.append(str(line))
	_base_lines.append("")
	for line in _snippet_b.get("lines", []):
		_base_lines.append(str(line))

	_single_line_count = _base_lines.size()
	_lines = _base_lines.duplicate()
	_lines.append_array(_base_lines)
	_lines.append_array(_base_lines)


func _set_target_hits() -> void:
	var day: int = get_current_day()
	if day <= 10:
		_target_hits = 18
	elif day <= 25:
		_target_hits = 26
	else:
		_target_hits = 34


func _start_countdown() -> void:
	_countdown = 3.0
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.add_theme_font_size_override("font_size", 120)
	_countdown_label.add_theme_color_override("font_color", TEXT_TITLE)
	_countdown_label.text = "3"
	_countdown_label.z_index = 100
	add_child(_countdown_label)


func _process_countdown(delta: float) -> void:
	_countdown -= delta
	if _countdown <= 0.0:
		if _countdown_label != null and is_instance_valid(_countdown_label):
			_countdown_label.text = "GO!"
			var tw := create_tween()
			tw.tween_property(_countdown_label, "modulate:a", 0.0, 0.35)
			tw.tween_callback(func() -> void:
				if _countdown_label != null and is_instance_valid(_countdown_label):
					_countdown_label.queue_free()
					_countdown_label = null
			)
		_running = true
		set_process_input(true)
		_hint_label.text = "在底部输入框键入飘落的关键字"
		return

	if _countdown_label != null and is_instance_valid(_countdown_label):
		_countdown_label.text = str(ceili(_countdown))
		_countdown_label.scale = _countdown_label.scale.lerp(Vector2.ONE, delta * 8.0)
#endregion


#region UI
func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root_sb := StyleBoxFlat.new()
	root_sb.bg_color = BG_EDITOR
	_root_panel.add_theme_stylebox_override("panel", root_sb)
	add_child(_root_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 0)
	_root_panel.add_child(outer_vbox)

	_build_title_bar(outer_vbox)
	_build_tab_bar(outer_vbox)
	_build_hud_bar(outer_vbox)
	_build_code_view(outer_vbox)
	_build_status_bar(outer_vbox)

	_build_input_panel()

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)


func _build_title_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_TITLEBAR
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	for c in [Color("#f38ba8"), Color("#fab387"), Color("#a6e3a1")]:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = c
		hbox.add_child(dot)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp1)

	var title := Label.new()
	title.text = _snippet_a.get("title", "typing_code.gd") + " — AVG Engine IDE"
	title.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	title.add_theme_color_override("font_color", TEXT_STATUS)
	hbox.add_child(title)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp2)

	_timer_label = Label.new()
	_timer_label.text = "0 s"
	_timer_label.add_theme_font_size_override("font_size", FONT_SIZE_UI + 2)
	_timer_label.add_theme_color_override("font_color", ACCENT)
	hbox.add_child(_timer_label)


func _build_tab_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_TAB_INACTIVE
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	bar.add_child(hbox)

	var active_tab := _make_tab(str(_snippet_a.get("title", "untitled.gd")), true)
	hbox.add_child(active_tab)
	hbox.add_child(_make_tab(str(_snippet_b.get("title", "util.gd")), false))
	hbox.add_child(_make_tab("bug_tracker.log", false))


func _make_tab(text: String, active: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_TAB_ACTIVE if active else BG_TAB_INACTIVE
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if active:
		sb.border_width_top = 2
		sb.border_color = ACCENT
	panel.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	label.add_theme_color_override("font_color", TEXT_TITLE if active else TEXT_LINENUM)
	panel.add_child(label)
	return panel


func _build_hud_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_STATUSBAR
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	bar.add_child(hbox)

	hbox.add_child(_make_meter_block("构建进度", "输入并清理关键字", "build"))
	hbox.add_child(_make_meter_block("Bug 进度", "漏掉关键字会累积", "bug"))

	var combo_box := VBoxContainer.new()
	combo_box.custom_minimum_size = Vector2(170, 0)
	combo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(combo_box)

	_combo_number = Label.new()
	_combo_number.text = "0"
	_combo_number.add_theme_font_size_override("font_size", 54)
	_combo_number.add_theme_color_override("font_color", TEXT_LINENUM)
	_combo_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_box.add_child(_combo_number)

	_combo_label = Label.new()
	_combo_label.text = "COMBO"
	_combo_label.add_theme_font_size_override("font_size", 16)
	_combo_label.add_theme_color_override("font_color", TEXT_LINENUM)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_box.add_child(_combo_label)

	_milestone_label = Label.new()
	_milestone_label.text = ""
	_milestone_label.add_theme_font_size_override("font_size", 18)
	_milestone_label.add_theme_color_override("font_color", ACCENT)
	_milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone_label.modulate.a = 0.0
	combo_box.add_child(_milestone_label)


func _make_meter_block(title_text: String, sub_text: String, kind: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	title.add_theme_color_override("font_color", TEXT_TITLE)
	box.add_child(title)

	var sub := Label.new()
	sub.text = sub_text
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", TEXT_LINENUM)
	box.add_child(sub)

	var meter := Control.new()
	meter.custom_minimum_size = Vector2(280, 10)
	box.add_child(meter)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = PROGRESS_BG
	meter.add_child(bg)

	var fill := ColorRect.new()
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = 0.0
	fill.color = PROGRESS_FILL
	meter.add_child(fill)

	if kind == "build":
		_build_bar_fill = fill
	else:
		_bug_bar_fill = fill

	return box


func _build_code_view(parent: VBoxContainer) -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(body)

	_gutter_panel = PanelContainer.new()
	var gutter_sb := StyleBoxFlat.new()
	gutter_sb.bg_color = BG_GUTTER
	gutter_sb.content_margin_left = 8
	gutter_sb.content_margin_right = 8
	gutter_sb.content_margin_top = 4
	_gutter_panel.add_theme_stylebox_override("panel", gutter_sb)
	_gutter_panel.custom_minimum_size = Vector2(52, 0)
	_gutter_panel.clip_contents = true
	body.add_child(_gutter_panel)

	_gutter = VBoxContainer.new()
	_gutter.add_theme_constant_override("separation", 0)
	_gutter_panel.add_child(_gutter)
	for i in range(_lines.size()):
		var ln := Label.new()
		ln.text = str((i % max(_single_line_count, 1)) + 1)
		ln.add_theme_font_size_override("font_size", FONT_SIZE_CODE)
		ln.add_theme_color_override("font_color", TEXT_LINENUM)
		ln.custom_minimum_size = Vector2(0, LINE_HEIGHT)
		ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_gutter.add_child(ln)

	_code_area = Control.new()
	_code_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_area.clip_contents = true
	body.add_child(_code_area)

	var ghost_host := Control.new()
	ghost_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	ghost_host.offset_left = 12
	ghost_host.offset_top = 8
	ghost_host.offset_right = -12
	ghost_host.offset_bottom = 0
	ghost_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_host.clip_contents = true
	_code_area.add_child(ghost_host)

	_ghost_container = VBoxContainer.new()
	_ghost_container.add_theme_constant_override("separation", 0)
	ghost_host.add_child(_ghost_container)

	_keyword_layer = Control.new()
	_keyword_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_keyword_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_code_area.add_child(_keyword_layer)

	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint_label.offset_top = 18
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", TEXT_STATUS)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_code_area.add_child(_hint_label)

	# Input panel is built separately and added to self (top-level) to avoid being occluded by scrolling code


func _build_input_panel() -> void:
	_input_panel = PanelContainer.new()
	_input_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_input_panel.offset_left = 72
	_input_panel.offset_right = -20
	_input_panel.offset_bottom = -36
	_input_panel.offset_top = -128
	_input_panel.z_index = 50
	var input_sb := StyleBoxFlat.new()
	input_sb.bg_color = Color(COLOR_INPUT_BG.r, COLOR_INPUT_BG.g, COLOR_INPUT_BG.b, 0.95)
	input_sb.set_corner_radius_all(10)
	input_sb.set_border_width_all(2)
	input_sb.border_color = ACCENT
	input_sb.shadow_color = Color(0, 0, 0, 0.5)
	input_sb.shadow_size = 12
	input_sb.content_margin_left = 16
	input_sb.content_margin_right = 16
	input_sb.content_margin_top = 12
	input_sb.content_margin_bottom = 12
	_input_panel.add_theme_stylebox_override("panel", input_sb)
	add_child(_input_panel)

	var input_vbox := VBoxContainer.new()
	input_vbox.add_theme_constant_override("separation", 6)
	_input_panel.add_child(input_vbox)

	var prompt_label := Label.new()
	prompt_label.text = "键入飘落的关键字 ▸"
	prompt_label.add_theme_font_size_override("font_size", 13)
	prompt_label.add_theme_color_override("font_color", TEXT_STATUS)
	input_vbox.add_child(prompt_label)

	_input_value_label = Label.new()
	_input_value_label.text = "> _"
	_input_value_label.add_theme_font_size_override("font_size", 28)
	_input_value_label.add_theme_color_override("font_color", TEXT_TITLE)
	input_vbox.add_child(_input_value_label)


func _build_status_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_STATUSBAR
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

	_status_bar = HBoxContainer.new()
	_status_bar.add_theme_constant_override("separation", 20)
	bar.add_child(_status_bar)

	_status_hits = _make_status_label("命中 0/0")
	_status_bug = _make_status_label("漏失 0")
	_status_score = _make_status_label("得分 0")

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.add_child(sp)

	var mode := _make_status_label("GDScript · 关键字防守")
	mode.add_theme_color_override("font_color", TEXT_LINENUM)


func _make_status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	label.add_theme_color_override("font_color", TEXT_STATUS)
	_status_bar.add_child(label)
	return label
#endregion


#region 代码背景
func _render_ghost_code() -> void:
	_ghost_labels.clear()
	for child in _ghost_container.get_children():
		child.queue_free()
	for line in _lines:
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.add_theme_font_size_override("normal_font_size", FONT_SIZE_CODE)
		label.custom_minimum_size = Vector2(0, LINE_HEIGHT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ghost_container.add_child(label)
		_ghost_labels.append(label)
	_single_set_height = float(_single_line_count) * LINE_HEIGHT
	_scroll_offset = _single_set_height
	_update_code_scroll(0.0)
#endregion


#region 输入
func _input(event: InputEvent) -> void:
	if _finished or not _running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			return
		if key_event.keycode == KEY_BACKSPACE:
			if not _typed_input.is_empty():
				_typed_input = _typed_input.substr(0, _typed_input.length() - 1)
				_update_input_display()
				_refresh_keyword_visuals()
			get_viewport().set_input_as_handled()
			return
		if key_event.unicode <= 0:
			return
		var ch: String = char(key_event.unicode).to_lower()
		if ch < "a" or ch > "z":
			return
		_handle_char_input(ch)
		get_viewport().set_input_as_handled()


func _handle_char_input(ch: String) -> void:
	var candidate := _typed_input + ch
	if _has_prefix_match(candidate):
		_typed_input = candidate
		_update_input_display()
		_refresh_keyword_visuals()
		var exact_idx := _find_best_match(candidate, true)
		if exact_idx != -1:
			_consume_keyword(exact_idx)
		return

	_input_errors += 1
	_combo = 0
	_show_hint("MISS", COLOR_MISS)
	_show_flash(Color(COLOR_MISS, 0.08))

	if _has_prefix_match(ch):
		_typed_input = ch
	else:
		_typed_input = ""

	_update_combo_display()
	_update_input_display()
	_refresh_keyword_visuals()
#endregion


#region 关键字逻辑
func _current_spawn_interval() -> float:
	return maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_BASE - _elapsed * SPAWN_INTERVAL_DECAY)


func _current_fall_speed() -> float:
	return minf(FALL_SPEED_MAX, FALL_SPEED_BASE + _elapsed * FALL_SPEED_GROWTH * 10.0)


func _pick_keyword() -> String:
	var day: int = get_current_day()
	var candidates: Array[String] = []
	for text in _keyword_pool:
		if day <= 10 and text.length() > 5:
			continue
		if day <= 25 and text.length() > 7:
			continue
		candidates.append(text)
	if candidates.is_empty():
		candidates.assign(_keyword_pool)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _classify_keyword(word: String) -> Color:
	if KW_SET_CTRL.has(word):
		return KW_COLOR_CTRL
	if KW_SET_DECL.has(word):
		return KW_COLOR_DECL
	if KW_SET_TYPE.has(word):
		return KW_COLOR_TYPE
	if KW_SET_LOGIC.has(word):
		return KW_COLOR_LOGIC
	return KW_COLOR_DEFAULT


func _spawn_keyword() -> void:
	var keyword := _pick_keyword()
	var keyword_color := _classify_keyword(keyword)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("normal_font_size", FONT_SIZE_KEYWORD)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color("#1e1e2e"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "[color=#" + keyword_color.to_html(false) + "]" + keyword + "[/color]"
	_keyword_layer.add_child(label)

	var available_width: float = maxf(_code_area.size.x - 180.0, 420.0)
	var lanes: int = 6
	var lane_idx: int = _rng.randi_range(0, lanes - 1)
	var lane_width: float = available_width / float(lanes)
	var spawn_x: float = 26.0 + lane_width * lane_idx + _rng.randf_range(0.0, maxf(lane_width - 64.0, 8.0))
	var word := {
		"text": keyword,
		"label": label,
		"x": spawn_x,
		"y": -16.0,
		"speed": _current_fall_speed(),
		"color": keyword_color,
	}
	_falling_words.append(word)
	_refresh_keyword_visuals()
	_update_keyword_positions()


func _update_falling_words(delta: float) -> void:
	for i in range(_falling_words.size() - 1, -1, -1):
		var word: Dictionary = _falling_words[i]
		word["y"] = float(word.get("y", 0.0)) + float(word.get("speed", FALL_SPEED_BASE)) * delta
		_falling_words[i] = word
		if float(word.get("y", 0.0)) >= _keyword_floor_y():
			_miss_keyword(i)

	_update_keyword_positions()
	_refresh_keyword_visuals()


func _keyword_floor_y() -> float:
	return maxf(_code_area.size.y - 150.0, 240.0)


func _update_code_scroll(delta: float) -> void:
	if _single_set_height <= 0.0:
		return

	if delta > 0.0 and _code_progress_speed > 0.0:
		_advance_code_progress(_code_progress_speed * delta)
		_code_progress_speed = maxf(0.0, _code_progress_speed - CODE_PROGRESS_DECAY * delta)

	while _code_progress_line >= _single_line_count * 2:
		_code_progress_line -= _single_line_count
		_scroll_offset -= _single_set_height

	var visible_height := maxf(_code_area.size.y - 120.0, 220.0)
	var follow_anchor := visible_height * 0.5
	var cursor_y := float(_code_progress_line) * LINE_HEIGHT
	if cursor_y > _scroll_offset + follow_anchor:
		_scroll_offset = cursor_y - follow_anchor

	var min_offset := _single_set_height
	var max_offset := _single_set_height * 2.0
	_scroll_offset = clampf(_scroll_offset, min_offset, max_offset)

	_ghost_container.position.y = -_scroll_offset
	_gutter.position.y = -_scroll_offset
	_refresh_ghost_code_visuals()


func _advance_code_progress(amount: float) -> void:
	if amount <= 0.0 or _lines.is_empty():
		return

	var remaining := amount
	while remaining > 0.0:
		var line_text := _lines[_code_progress_line]
		var line_length := maxi(line_text.length(), 1)
		var available := float(line_length) - _code_progress_char
		var consumed := minf(remaining, available)
		_code_progress_char += consumed
		remaining -= consumed

		if _code_progress_char >= float(line_length):
			_code_progress_line += 1
			if _code_progress_line >= _lines.size():
				_code_progress_line = _single_line_count
			_code_progress_char = 0.0


func _refresh_ghost_code_visuals() -> void:
	for i in range(_ghost_labels.size()):
		var label := _ghost_labels[i]
		var line_text := _lines[i]
		var escaped_line := _escape_bbcode_text(line_text)
		if i < _code_progress_line:
			label.text = "[color=#" + TEXT_CODE_DONE.to_html(false) + "]" + escaped_line + "[/color]"
		elif i == _code_progress_line:
			var visible_chars := clampi(int(floor(_code_progress_char)), 0, line_text.length())
			var cursor := "_" if _running and not _finished else ""
			var typed_text := _escape_bbcode_text(line_text.substr(0, visible_chars))
			var remain_text := _escape_bbcode_text(line_text.substr(visible_chars))
			label.text = "[color=#" + TEXT_CODE_TYPED.to_html(false) + "]" + typed_text + "[/color]" \
				+ "[color=#" + TEXT_CODE_REMAIN.to_html(false) + "]" + cursor + remain_text + "[/color]"
		else:
			label.text = "[color=#" + TEXT_CODE_PENDING.to_html(false) + "]" + escaped_line + "[/color]"


func _escape_bbcode_text(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _has_prefix_match(prefix: String) -> bool:
	if prefix.is_empty():
		return true
	var lower_prefix := prefix.to_lower()
	for word in _falling_words:
		var text := str(word.get("text", "")).to_lower()
		if text.begins_with(lower_prefix):
			return true
	return false


func _find_best_match(text: String, exact: bool) -> int:
	var best_idx := -1
	var best_y := -INF
	var lower_text := text.to_lower()
	for i in range(_falling_words.size()):
		var word_text := str(_falling_words[i].get("text", "")).to_lower()
		var matched := word_text == lower_text if exact else word_text.begins_with(lower_text)
		if not matched:
			continue
		var y := float(_falling_words[i].get("y", 0.0))
		if y > best_y:
			best_y = y
			best_idx = i
	return best_idx


func _consume_keyword(index: int) -> void:
	var word: Dictionary = _falling_words[index]
	var label: RichTextLabel = word.get("label", null)
	var popup_pos := Vector2(float(word.get("x", 0.0)), float(word.get("y", 0.0)))

	_hits += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_bug_meter = maxf(0.0, _bug_meter - BUG_REPAIR_ON_HIT)
	_total_score += roundi(float(SCORE_PER_HIT) * (1.0 + minf(float(_combo - 1), 12.0) * COMBO_BONUS_MULT))
	_typed_input = ""

	if label != null and is_instance_valid(label):
		var word_text := str(word.get("text", ""))
		label.text = "[color=#" + COLOR_HIT.to_html(false) + "]" + word_text + "[/color]"
		var tw := create_tween()
		tw.tween_property(label, "scale", Vector2(1.2, 1.2), 0.08)
		tw.tween_property(label, "modulate:a", 0.0, 0.18)
		tw.tween_callback(label.queue_free)
		_spawn_hit_particles(label.position + label.size * 0.5, word.get("color", COLOR_HIT))

	_falling_words.remove_at(index)
	_code_progress_speed = minf(
		CODE_PROGRESS_MAX_SPEED,
		_code_progress_speed + CODE_PROGRESS_HIT_IMPULSE + float(_combo - 1) * CODE_PROGRESS_COMBO_IMPULSE
	)
	_show_hint("HIT", COLOR_HIT, popup_pos)
	_show_flash(Color(COLOR_HIT, 0.05))
	_update_combo_display()
	_update_input_display()
	_update_status_bar()
	_update_progress_bars()
	_refresh_keyword_visuals()

	if COMBO_MILESTONES.has(_combo):
		var milestone: Dictionary = COMBO_MILESTONES[_combo]
		_show_milestone(str(milestone.get("text", "")), Color(str(milestone.get("color_hex", "#89b4fa"))))


func _miss_keyword(index: int) -> void:
	var word: Dictionary = _falling_words[index]
	var label: RichTextLabel = word.get("label", null)
	var popup_pos := Vector2(float(word.get("x", 0.0)), _keyword_floor_y() - 12.0)

	_misses += 1
	_combo = 0
	_bug_meter = minf(BUG_BAR_MAX, _bug_meter + BUG_PER_MISS)

	if label != null and is_instance_valid(label):
		var word_text := str(word.get("text", ""))
		label.text = "[color=#" + COLOR_MISS.to_html(false) + "]" + word_text + "[/color]"
		var tw := create_tween()
		tw.tween_property(label, "modulate:a", 0.0, 0.15)
		tw.tween_callback(label.queue_free)

	_falling_words.remove_at(index)
	if not _has_prefix_match(_typed_input):
		_typed_input = ""

	_show_hint("BUG!", COLOR_MISS, popup_pos)
	_show_flash(Color(COLOR_MISS, 0.08))
	_update_combo_display()
	_update_input_display()
	_update_status_bar()
	_update_progress_bars()


func _update_keyword_positions() -> void:
	for word in _falling_words:
		var label: RichTextLabel = word.get("label", null)
		if label == null or not is_instance_valid(label):
			continue
		label.position = Vector2(float(word.get("x", 0.0)), float(word.get("y", 0.0)))


func _refresh_keyword_visuals() -> void:
	var prefix_idx := -1
	if not _typed_input.is_empty():
		prefix_idx = _find_best_match(_typed_input, false)

	for i in range(_falling_words.size()):
		var word: Dictionary = _falling_words[i]
		var label: RichTextLabel = word.get("label", null)
		if label == null or not is_instance_valid(label):
			continue

		var text := str(word.get("text", ""))
		var text_lower := text.to_lower()
		var y := float(word.get("y", 0.0))
		var base_color: Color = word.get("color", COLOR_KEYWORD)

		var typed_len := 0
		var rest_color := base_color
		var _is_best := false

		if not _typed_input.is_empty() and text_lower.begins_with(_typed_input.to_lower()):
			typed_len = _typed_input.length()
			if i == prefix_idx:
				_is_best = true
				rest_color = ACCENT
				label.scale = Vector2(1.08, 1.08)
			else:
				rest_color = ACCENT
				label.scale = Vector2.ONE
		else:
			label.scale = Vector2.ONE

		if y >= _keyword_floor_y() - 40.0 and typed_len == 0:
			rest_color = COLOR_MISS

		var bbcode := ""
		if typed_len > 0:
			bbcode += "[color=#" + COLOR_HIT.to_html(false) + "]" + text.substr(0, typed_len) + "[/color]"
			if typed_len < text.length():
				bbcode += "[color=#" + rest_color.to_html(false) + "]" + text.substr(typed_len) + "[/color]"
		else:
			bbcode += "[color=#" + rest_color.to_html(false) + "]" + text + "[/color]"
		label.text = bbcode


func _spawn_hit_particles(world_pos: Vector2, color: Color) -> void:
	if _keyword_layer == null:
		return
	var particle_count := 10
	for i in range(particle_count):
		var p := ColorRect.new()
		p.color = color
		p.size = Vector2(6, 6)
		p.position = world_pos - p.size * 0.5
		p.pivot_offset = p.size * 0.5
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keyword_layer.add_child(p)

		var angle: float = _rng.randf_range(0.0, TAU)
		var distance: float = _rng.randf_range(40.0, 90.0)
		var target := p.position + Vector2(cos(angle), sin(angle)) * distance
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", target, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2(0.1, 0.1), 0.42).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(p, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD)
		tw.chain().tween_callback(p.queue_free)
#endregion


#region HUD 更新
func _update_input_display() -> void:
	var has_match := _typed_input.is_empty() or _has_prefix_match(_typed_input)
	var display := _typed_input if not _typed_input.is_empty() else "_"
	_input_value_label.text = "> " + display
	_input_value_label.add_theme_color_override("font_color", TEXT_TITLE if has_match else COLOR_MISS)


func _update_combo_display() -> void:
	_combo_number.text = str(_combo)
	if _combo >= 35:
		_combo_number.add_theme_color_override("font_color", Color("#f5c2e7"))
		_combo_label.text = "FEVER"
	elif _combo >= 10:
		_combo_number.add_theme_color_override("font_color", ACCENT)
		_combo_label.text = "COMBO"
	else:
		_combo_number.add_theme_color_override("font_color", TEXT_LINENUM)
		_combo_label.text = "COMBO"

	_combo_number.scale = Vector2(1.0 + minf(float(_combo), 10.0) * 0.03, 1.0 + minf(float(_combo), 10.0) * 0.03)
	var tw := create_tween()
	tw.tween_property(_combo_number, "scale", Vector2.ONE, 0.12)


func _update_progress_bars() -> void:
	if _build_bar_fill != null and is_instance_valid(_build_bar_fill):
		_build_bar_fill.anchor_right = clampf(float(_hits) / maxf(float(_target_hits), 1.0), 0.0, 1.0)
		_build_bar_fill.color = PROGRESS_FILL

	if _bug_bar_fill != null and is_instance_valid(_bug_bar_fill):
		var ratio := clampf(_bug_meter / BUG_BAR_MAX, 0.0, 1.0)
		_bug_bar_fill.anchor_right = ratio
		if ratio < 0.5:
			_bug_bar_fill.color = PROGRESS_FILL
		elif ratio < 0.8:
			_bug_bar_fill.color = PROGRESS_WARN
		else:
			_bug_bar_fill.color = PROGRESS_DANGER


func _update_status_bar() -> void:
	_status_hits.text = "命中 %d/%d" % [_hits, _target_hits]
	_status_bug.text = "漏失 %d" % _misses
	_status_score.text = "得分 %d" % _total_score


func _show_hint(text: String, color: Color, world_pos: Vector2 = Vector2.INF) -> void:
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", color)
	_hint_label.modulate.a = 1.0

	if world_pos != Vector2.INF:
		var popup := Label.new()
		popup.text = text
		popup.add_theme_font_size_override("font_size", 20)
		popup.add_theme_color_override("font_color", color)
		popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup.position = world_pos
		_keyword_layer.add_child(popup)
		var tw := create_tween()
		tw.tween_property(popup, "position:y", popup.position.y - 30.0, 0.35)
		tw.parallel().tween_property(popup, "modulate:a", 0.0, 0.35)
		tw.tween_callback(popup.queue_free)


func _show_milestone(text: String, color: Color) -> void:
	_milestone_label.text = text
	_milestone_label.add_theme_color_override("font_color", color)
	_milestone_label.modulate.a = 1.0
	_milestone_label.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(_milestone_label, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(0.5)
	tw.tween_property(_milestone_label, "modulate:a", 0.0, 0.35)
	_show_flash(Color(color, 0.12))


func _show_flash(color: Color) -> void:
	if _flash_rect == null or not is_instance_valid(_flash_rect):
		return
	_flash_rect.color = color
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.18)
#endregion


#region 结算
func _end_game(success: bool) -> void:
	if _finished:
		return
	_finished = true
	set_process_input(false)

	for word in _falling_words:
		var label: RichTextLabel = word.get("label", null)
		if label != null and is_instance_valid(label):
			label.queue_free()
	_falling_words.clear()

	var score := _calculate_score(success)
	_show_result_overlay(success, score)


func _calculate_score(success: bool) -> float:
	var hit_ratio := clampf(float(_hits) / maxf(float(_target_hits), 1.0), 0.0, 1.0)
	var accuracy := float(_hits) / maxf(float(_hits + _input_errors), 1.0)
	var bug_survival := 1.0 - clampf(_bug_meter / BUG_BAR_MAX, 0.0, 1.0)
	var combo_ratio := clampf(float(_max_combo) / 20.0, 0.0, 1.0)
	var success_bonus := 0.1 if success else 0.0
	return clampf(hit_ratio * 0.45 + accuracy * 0.25 + bug_survival * 0.2 + combo_ratio * 0.1 + success_bonus, 0.0, 1.0)


func _show_result_overlay(success: bool, score: float) -> void:
	var overlay := PanelContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	overlay.add_theme_stylebox_override("panel", sb)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 10)
	center.add_child(card)

	var grade: String = "D"
	var grade_color: Color = COLOR_MISS
	if score >= 0.9:
		grade = "S"
		grade_color = Color("#f9e2af")
	elif score >= 0.75:
		grade = "A"
		grade_color = COLOR_HIT
	elif score >= 0.5:
		grade = "B"
		grade_color = ACCENT
	elif score >= 0.3:
		grade = "C"
		grade_color = PROGRESS_WARN

	var title := Label.new()
	title.text = "✓ 编译稳定" if success else "✗ Bug 爆表"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_HIT if success else COLOR_MISS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title)

	var gl := Label.new()
	gl.text = grade
	gl.add_theme_font_size_override("font_size", 64)
	gl.add_theme_color_override("font_color", grade_color)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(gl)

	var accuracy_pct := float(_hits) / maxf(float(_hits + _input_errors), 1.0) * 100.0
	var stats := Label.new()
	stats.text = "命中 %d/%d  ·  漏失 %d  ·  最大连击 %d" % [_hits, _target_hits, _misses, _max_combo]
	stats.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	stats.add_theme_color_override("font_color", TEXT_STATUS)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(stats)

	var info := Label.new()
	info.text = "准确率 %.0f%%  ·  Bug 条 %.1f/%.0f  ·  用时 %d 秒" % [accuracy_pct, _bug_meter, BUG_BAR_MAX, int(_elapsed)]
	info.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	info.add_theme_color_override("font_color", TEXT_STATUS)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(info)

	var score_label := Label.new()
	score_label.text = "总分 %d" % _total_score
	score_label.add_theme_font_size_override("font_size", FONT_SIZE_UI + 4)
	score_label.add_theme_color_override("font_color", ACCENT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(score_label)

	var btn := Button.new()
	btn.text = "完成"
	btn.custom_minimum_size = Vector2(140, 44)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_UI + 2)
	btn.pressed.connect(func() -> void:
		finish({
			"score": score,
			"accuracy": float(_hits) / maxf(float(_hits + _input_errors), 1.0),
			"max_combo": _max_combo,
			"elapsed": _elapsed,
			"completed_lines": _hits,
			"total_lines": _target_hits,
			"miss_count": _misses,
			"bug_meter": _bug_meter,
			"snippet_title": _snippet_a.get("tab_name", ""),
		})
	)
	var bc := CenterContainer.new()
	bc.add_child(btn)
	card.add_child(bc)
#endregion
