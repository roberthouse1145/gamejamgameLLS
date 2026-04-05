extends MinigameBase
## 代码打字小游戏 — 双面板：单词打字 + 代码推进
##
## 左侧：伪 IDE 代码编辑器（代码根据玩家打字自动推进）
## 右侧：单词输入区 + Combo 面板
##
## 玩家在右侧逐字输入英文单词：
##   - 每完成一个单词 → 左侧代码自动推进若干字符
##   - 连击越高 → 代码推进越快，视觉越爽
##   - 打错字 → 连击断裂

#region 单词库
const WORD_POOL: Array = [
	# 4 letters
	"code", "game", "play", "hero", "data", "file", "loop", "node",
	"save", "load", "draw", "emit", "call", "push", "grid", "jump",
	"star", "moon", "fire", "rain", "wind", "fast", "gold", "blue",
	"free", "wave", "rock", "lake", "bird", "fish", "tree", "path",
	# 5-6 letters
	"scene", "debug", "spawn", "input", "start", "build", "level",
	"score", "bonus", "chain", "timer", "delta", "ready", "tween",
	"scale", "color", "audio", "pixel", "mouse", "click", "event",
	"array", "class", "stack", "queue", "frame", "state", "light",
	"apple", "world", "ocean", "dream", "magic", "story", "quest",
	"brave", "night", "speed", "power", "music", "storm", "river",
	"cloud", "crown", "stone", "eagle", "sword", "flame", "space",
	# 7+ letters
	"process", "animate", "dynamic", "network", "program", "command",
	"execute", "virtual", "display", "gravity", "texture", "pattern",
	"runtime", "compile", "handler", "connect", "abandon", "freedom",
	"journey", "crystal", "thunder", "fantasy", "kingdom", "warrior",
	"mystery", "horizon", "phoenix", "eclipse", "silence", "rainbow",
]
#endregion

#region 代码片段库
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
const TIME_LIMIT: float = 60.0

## 打字速度判定窗口（秒，相邻两次正确按键的间隔）
const SPEED_PERFECT: float = 0.15
const SPEED_GREAT: float = 0.30
const SPEED_GOOD: float = 0.60

## 判定得分
const SCORE_PERFECT: int = 100
const SCORE_GREAT: int = 70
const SCORE_GOOD: int = 40

## 代码推进参数
const BASE_CODE_SPEED: float = 15.0   ## 基础代码推进速度（字符/秒）
const MAX_CODE_SPEED: float = 60.0    ## 最大代码推进速度
const CODE_CHARS_PER_LETTER: float = 4.0  ## 每个单词字母对应的代码字符数

## Combo 里程碑
const COMBO_MILESTONES: Dictionary = {
	10: {"text": "NICE!", "color_hex": "#89b4fa"},
	25: {"text": "COOL!", "color_hex": "#a6e3a1"},
	50: {"text": "AMAZING!", "color_hex": "#f9e2af"},
	75: {"text": "FEVER!!", "color_hex": "#f5c2e7"},
	100: {"text": "UNSTOPPABLE!", "color_hex": "#fab387"},
}

const UPCOMING_WORD_COUNT: int = 3
#endregion

#region 视觉常量
const FONT_SIZE_CODE: int = 19
const FONT_SIZE_UI: int = 16
const FONT_SIZE_WORD: int = 36
const LINE_HEIGHT: float = 28.0
const WORD_PANEL_WIDTH: float = 320.0

const BG_EDITOR := Color("#1e1e2e")
const BG_GUTTER := Color("#181825")
const BG_TITLEBAR := Color("#11111b")
const BG_STATUSBAR := Color("#181825")
const BG_TAB_ACTIVE := Color("#1e1e2e")
const BG_TAB_INACTIVE := Color("#11111b")
const BG_WORD_PANEL := Color("#11111b")
const TEXT_GHOST := Color(0.58, 0.63, 0.73, 0.35)
const TEXT_TYPED := Color("#a6e3a1")
const TEXT_CURSOR := Color("#f5e0dc")
const TEXT_LINENUM := Color("#585b70")
const TEXT_TITLE := Color("#cdd6f4")
const TEXT_STATUS := Color("#a6adc8")
const ACCENT := Color("#89b4fa")
const COLOR_PERFECT := Color("#a6e3a1")
const COLOR_GREAT := Color("#89b4fa")
const COLOR_GOOD := Color("#f9e2af")
const COLOR_MISS := Color("#f38ba8")
const COLOR_EXTRA := Color("#f5c2e7")
const PROGRESS_BG := Color("#313244")
const PROGRESS_FILL := Color("#a6e3a1")
const PROGRESS_WARN := Color("#fab387")
const PROGRESS_DANGER := Color("#f38ba8")
#endregion

#region 游戏状态
## 单词
var _word_queue: Array[String] = []
var _current_word: String = ""
var _word_cursor: int = 0
var _words_completed: int = 0
var _total_chars_typed: int = 0

## 代码动画
var _snippet_a: Dictionary = {}
var _snippet_b: Dictionary = {}
var _lines: Array = []
var _code_total_chars: int = 0
var _code_reveal_idx: int = 0
var _code_pending: float = 0.0
var _code_reveal_accum: float = 0.0
var _code_scroll_y: float = 0.0
var _last_revealed_line: int = -1
var _line_char_offsets: Array[int] = []

## 分数 / Combo
var _combo: int = 0
var _max_combo: int = 0
var _total_score: int = 0
var _perfect_count: int = 0
var _great_count: int = 0
var _good_count: int = 0
var _miss_count: int = 0

## 计时
var _time_remaining: float = TIME_LIMIT
var _finished: bool = false
var _game_time: float = 0.0
var _last_key_time: float = 0.0
var _countdown: float = -1.0
var _countdown_label: Label = null

## 特效
var _screen_flash: ColorRect = null
var _hit_burst_container: Control = null
var _milestone_label: Label = null
var _combo_energy_fill: ColorRect = null
#endregion

#region 节点引用
var _root_panel: PanelContainer
var _main_hbox: HBoxContainer

## 左侧 IDE
var _gutter: VBoxContainer
var _ghost_container: VBoxContainer
var _typed_container: VBoxContainer
var _code_area: Control
var _gutter_panel: PanelContainer

## 右侧单词 + Combo
var _word_display: RichTextLabel
var _check_label: Label
var _upcoming_container: VBoxContainer
var _judge_label: Label
var _extra_label: Label
var _combo_number: Label
var _combo_label: Label

## 状态栏 / 计时
var _timer_label: Label
var _timer_bar: Control
var _timer_bar_fill: ColorRect
var _status_bar: HBoxContainer
var _status_words: Label
var _status_code: Label
var _status_score: Label
#endregion

#region 初始化
func _on_minigame_start() -> void:
	_pick_snippets()
	_compute_line_offsets()
	_init_word_queue()
	_advance_to_next_word()
	_build_ui()
	_render_ghost_code()
	_update_code_overlay()
	_update_word_display()
	_update_upcoming_display()
	set_process_input(false)
	_running = false
	_start_countdown()


func _on_minigame_cleanup() -> void:
	set_process_input(false)


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


func _pick_snippets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_current_day() * 1000 + randi())
	var indices: Array[int] = []
	for i in range(CODE_SNIPPETS.size()):
		indices.append(i)
	indices.shuffle()
	_snippet_a = CODE_SNIPPETS[indices[0]]
	_snippet_b = CODE_SNIPPETS[indices[1 % indices.size()]]
	_lines = []
	_lines.append_array(_snippet_a.get("lines", []))
	_lines.append("")
	_lines.append_array(_snippet_b.get("lines", []))


func _compute_line_offsets() -> void:
	_line_char_offsets.clear()
	var total: int = 0
	for line in _lines:
		_line_char_offsets.append(total)
		total += str(line).length()
	_line_char_offsets.append(total)
	_code_total_chars = total
#endregion

#region 单词管理
func _init_word_queue() -> void:
	_word_queue.clear()
	var pool: Array[String] = []
	for w in WORD_POOL:
		pool.append(str(w))
	pool.shuffle()
	_word_queue.assign(pool)


func _advance_to_next_word() -> void:
	if _word_queue.is_empty():
		_init_word_queue()
	_current_word = _word_queue.pop_front()
	_word_cursor = 0
	_last_key_time = _game_time


func _peek_upcoming() -> Array[String]:
	var result: Array[String] = []
	for i in range(mini(UPCOMING_WORD_COUNT, _word_queue.size())):
		result.append(_word_queue[i])
	return result
#endregion

#region UI 构建
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
	_build_timer_bar(outer_vbox)

	_main_hbox = HBoxContainer.new()
	_main_hbox.add_theme_constant_override("separation", 0)
	_main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_main_hbox)

	_build_code_panel(_main_hbox)
	_build_word_panel(_main_hbox)

	_build_status_bar(outer_vbox)

	# 特效层
	_hit_burst_container = Control.new()
	_hit_burst_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_burst_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_burst_container)
	_screen_flash = ColorRect.new()
	_screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_flash.color = Color(1, 1, 1, 0)
	_screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_flash)


func _build_title_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_TITLEBAR
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
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
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp)
	var t := Label.new()
	t.text = _snippet_a.get("title", "untitled.gd") + " — AVG Engine IDE"
	t.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	t.add_theme_color_override("font_color", TEXT_STATUS)
	hbox.add_child(t)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp2)
	_timer_label = Label.new()
	_timer_label.text = "%d s" % int(TIME_LIMIT)
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
	var at := PanelContainer.new()
	var asb := StyleBoxFlat.new()
	asb.bg_color = BG_TAB_ACTIVE
	asb.content_margin_left = 14; asb.content_margin_right = 14
	asb.content_margin_top = 6; asb.content_margin_bottom = 6
	asb.border_width_top = 2; asb.border_color = ACCENT
	at.add_theme_stylebox_override("panel", asb)
	hbox.add_child(at)
	var al := Label.new()
	al.text = _snippet_a.get("title", "untitled.gd")
	al.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	al.add_theme_color_override("font_color", TEXT_TITLE)
	at.add_child(al)
	for ft in [_snippet_b.get("title", "util.gd"), "command_bus.gd"]:
		var ip := PanelContainer.new()
		var isb := StyleBoxFlat.new()
		isb.bg_color = BG_TAB_INACTIVE
		isb.content_margin_left = 14; isb.content_margin_right = 14
		isb.content_margin_top = 6; isb.content_margin_bottom = 6
		ip.add_theme_stylebox_override("panel", isb)
		hbox.add_child(ip)
		var fl := Label.new()
		fl.text = ft
		fl.add_theme_font_size_override("font_size", FONT_SIZE_UI)
		fl.add_theme_color_override("font_color", TEXT_LINENUM)
		ip.add_child(fl)


func _build_timer_bar(parent: VBoxContainer) -> void:
	_timer_bar = Control.new()
	_timer_bar.custom_minimum_size = Vector2(0, 3)
	parent.add_child(_timer_bar)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = PROGRESS_BG
	_timer_bar.add_child(bg)
	_timer_bar_fill = ColorRect.new()
	_timer_bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_timer_bar_fill.anchor_right = 1.0
	_timer_bar_fill.color = PROGRESS_FILL
	_timer_bar.add_child(_timer_bar_fill)


func _build_code_panel(parent: HBoxContainer) -> void:
	var ide := VBoxContainer.new()
	ide.add_theme_constant_override("separation", 0)
	ide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ide.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(ide)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ide.add_child(body)

	# 行号
	_gutter_panel = PanelContainer.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = BG_GUTTER
	gsb.content_margin_left = 8; gsb.content_margin_right = 8; gsb.content_margin_top = 4
	_gutter_panel.add_theme_stylebox_override("panel", gsb)
	_gutter_panel.custom_minimum_size = Vector2(48, 0)
	_gutter_panel.clip_contents = true
	body.add_child(_gutter_panel)
	_gutter = VBoxContainer.new()
	_gutter.add_theme_constant_override("separation", 0)
	_gutter_panel.add_child(_gutter)
	for i in range(_lines.size()):
		var ln := Label.new()
		ln.text = str(i + 1)
		ln.add_theme_font_size_override("font_size", FONT_SIZE_CODE)
		ln.add_theme_color_override("font_color", TEXT_LINENUM)
		ln.custom_minimum_size = Vector2(0, LINE_HEIGHT)
		ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_gutter.add_child(ln)

	# 代码双层
	_code_area = Control.new()
	_code_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_area.clip_contents = true
	body.add_child(_code_area)

	var gm := MarginContainer.new()
	gm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gm.add_theme_constant_override("margin_left", 12)
	gm.add_theme_constant_override("margin_top", 4)
	_code_area.add_child(gm)
	_ghost_container = VBoxContainer.new()
	_ghost_container.add_theme_constant_override("separation", 0)
	gm.add_child(_ghost_container)

	var tm := MarginContainer.new()
	tm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tm.add_theme_constant_override("margin_left", 12)
	tm.add_theme_constant_override("margin_top", 4)
	_code_area.add_child(tm)
	_typed_container = VBoxContainer.new()
	_typed_container.add_theme_constant_override("separation", 0)
	tm.add_child(_typed_container)


func _build_word_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_WORD_PANEL
	sb.border_width_left = 1
	sb.border_color = Color("#313244")
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(WORD_PANEL_WIDTH, 0)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# 上方弹性间距
	var sp_top := Control.new()
	sp_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp_top.size_flags_stretch_ratio = 0.6
	vbox.add_child(sp_top)

	# 提示文字
	var hint := Label.new()
	hint.text = "输入单词"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", TEXT_LINENUM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	# 当前单词
	_word_display = RichTextLabel.new()
	_word_display.bbcode_enabled = true
	_word_display.fit_content = true
	_word_display.scroll_active = false
	_word_display.autowrap_mode = TextServer.AUTOWRAP_OFF
	_word_display.add_theme_font_size_override("normal_font_size", FONT_SIZE_WORD)
	_word_display.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(_word_display)

	# 完成对勾
	_check_label = Label.new()
	_check_label.text = ""
	_check_label.add_theme_font_size_override("font_size", 24)
	_check_label.add_theme_color_override("font_color", TEXT_TYPED)
	_check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_check_label.modulate.a = 0.0
	vbox.add_child(_check_label)

	# 间距
	var sp_mid := Control.new()
	sp_mid.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sp_mid)

	# 即将到来的单词
	_upcoming_container = VBoxContainer.new()
	_upcoming_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_upcoming_container)
	for i in range(UPCOMING_WORD_COUNT):
		var wl := Label.new()
		wl.text = ""
		wl.add_theme_font_size_override("font_size", 18)
		wl.add_theme_color_override("font_color", Color(TEXT_LINENUM, 0.5))
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_upcoming_container.add_child(wl)

	# 弹性间距
	var sp_flex := Control.new()
	sp_flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(sp_flex)

	# 判定飘字
	_judge_label = Label.new()
	_judge_label.text = ""
	_judge_label.add_theme_font_size_override("font_size", 28)
	_judge_label.add_theme_color_override("font_color", COLOR_PERFECT)
	_judge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_judge_label)

	# EXTRA
	_extra_label = Label.new()
	_extra_label.text = ""
	_extra_label.add_theme_font_size_override("font_size", 20)
	_extra_label.add_theme_color_override("font_color", COLOR_EXTRA)
	_extra_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_extra_label)

	# Combo 数字
	_combo_number = Label.new()
	_combo_number.text = "0"
	_combo_number.add_theme_font_size_override("font_size", 72)
	_combo_number.add_theme_color_override("font_color", ACCENT)
	_combo_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_combo_number)

	# COMBO 文字
	_combo_label = Label.new()
	_combo_label.text = "COMBO"
	_combo_label.add_theme_font_size_override("font_size", 18)
	_combo_label.add_theme_color_override("font_color", TEXT_LINENUM)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_combo_label)

	# 里程碑飘字
	_milestone_label = Label.new()
	_milestone_label.text = ""
	_milestone_label.add_theme_font_size_override("font_size", 24)
	_milestone_label.add_theme_color_override("font_color", COLOR_EXTRA)
	_milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone_label.modulate.a = 0.0
	vbox.add_child(_milestone_label)

	# Combo 能量条
	var energy_container := Control.new()
	energy_container.custom_minimum_size = Vector2(200, 8)
	var energy_wrap := CenterContainer.new()
	energy_wrap.add_child(energy_container)
	vbox.add_child(energy_wrap)
	var energy_bg := ColorRect.new()
	energy_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	energy_bg.color = Color("#313244")
	energy_container.add_child(energy_bg)
	_combo_energy_fill = ColorRect.new()
	_combo_energy_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_combo_energy_fill.anchor_right = 0.0
	_combo_energy_fill.color = ACCENT
	energy_container.add_child(_combo_energy_fill)

	# 下方间距
	var sp_bottom := Control.new()
	sp_bottom.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(sp_bottom)


func _build_status_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_STATUSBAR
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)
	_status_bar = HBoxContainer.new()
	_status_bar.add_theme_constant_override("separation", 20)
	bar.add_child(_status_bar)
	_status_words = _mk_label("单词 0")
	_status_code = _mk_label("代码 0%%")
	_status_score = _mk_label("得分 0")
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.add_child(sp)
	var mode := _mk_label("GDScript · 打字模式")
	mode.add_theme_color_override("font_color", TEXT_LINENUM)


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	l.add_theme_color_override("font_color", TEXT_STATUS)
	_status_bar.add_child(l)
	return l
#endregion

#region 代码渲染
func _render_ghost_code() -> void:
	for child in _ghost_container.get_children():
		child.queue_free()
	for i in range(_lines.size()):
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size = Vector2(0, LINE_HEIGHT)
		label.add_theme_font_size_override("normal_font_size", FONT_SIZE_CODE)
		label.text = "[color=#%s]%s[/color]" % [TEXT_GHOST.to_html(true), _bb_escape(str(_lines[i]))]
		_ghost_container.add_child(label)


func _update_code_overlay() -> void:
	# 确保 typed_container 有足够子节点
	while _typed_container.get_child_count() < _lines.size():
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size = Vector2(0, LINE_HEIGHT)
		label.add_theme_font_size_override("normal_font_size", FONT_SIZE_CODE)
		label.text = ""
		_typed_container.add_child(label)

	var lc: Vector2i = _idx_to_line_col(_code_reveal_idx)
	var current_line: int = lc.x

	# 更新从上次到当前行
	for i in range(maxi(_last_revealed_line, 0), mini(current_line + 1, _lines.size())):
		var label: RichTextLabel = _typed_container.get_child(i) as RichTextLabel
		if label != null:
			label.text = _code_typed_bbcode(i)
		# 行号高亮
		if i < current_line and i < _gutter.get_child_count():
			var ln: Label = _gutter.get_child(i) as Label
			if ln != null:
				ln.add_theme_color_override("font_color", TEXT_TYPED)
	_last_revealed_line = current_line


func _code_typed_bbcode(line_idx: int) -> String:
	var target: String = str(_lines[line_idx])
	if target.is_empty():
		return ""
	var line_start: int = _line_char_offsets[line_idx]
	var chars_on_line: int = target.length()
	var reveal_on_line: int = clampi(_code_reveal_idx - line_start, 0, chars_on_line)
	if reveal_on_line <= 0:
		return ""
	var result: String = ""
	for i in range(reveal_on_line):
		result += "[color=#%s]%s[/color]" % [TEXT_TYPED.to_html(false), _bb_escape(target[i])]
	if reveal_on_line < chars_on_line:
		result += "[color=#%s]▎[/color]" % TEXT_CURSOR.to_html(false)
	return result


func _idx_to_line_col(idx: int) -> Vector2i:
	for i in range(_lines.size()):
		if idx < _line_char_offsets[i + 1]:
			return Vector2i(i, idx - _line_char_offsets[i])
	return Vector2i(_lines.size() - 1, str(_lines[_lines.size() - 1]).length())


func _update_code_scroll(delta: float) -> void:
	var lc: Vector2i = _idx_to_line_col(_code_reveal_idx)
	var cursor_y: float = float(lc.x) * LINE_HEIGHT
	var visible_h: float = _code_area.size.y if _code_area != null else 400.0
	var target_scroll: float = maxf(0.0, cursor_y - visible_h * 0.6)
	_code_scroll_y = lerpf(_code_scroll_y, target_scroll, minf(delta * 8.0, 1.0))

	if _ghost_container != null:
		_ghost_container.position.y = -_code_scroll_y
	if _typed_container != null:
		_typed_container.position.y = -_code_scroll_y
	if _gutter != null:
		_gutter.position.y = -_code_scroll_y


func _bb_escape(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")
#endregion

#region 单词渲染
func _update_word_display() -> void:
	if _word_display == null or not is_instance_valid(_word_display):
		return
	_word_display.text = _word_bbcode()


func _word_bbcode() -> String:
	var result: String = "[center]"
	for i in range(_current_word.length()):
		if i > 0:
			result += "  "
		var ch: String = _current_word[i].to_upper()
		if i < _word_cursor:
			result += "[color=#%s]%s[/color]" % [TEXT_TYPED.to_html(false), ch]
		elif i == _word_cursor:
			result += "[color=#%s]%s[/color]" % [TEXT_TITLE.to_html(false), ch]
		else:
			result += "[color=#%s]%s[/color]" % [TEXT_LINENUM.to_html(false), ch]
	result += "[/center]"
	return result


func _update_upcoming_display() -> void:
	var upcoming: Array[String] = _peek_upcoming()
	for i in range(_upcoming_container.get_child_count()):
		var label: Label = _upcoming_container.get_child(i) as Label
		if label == null:
			continue
		if i < upcoming.size():
			label.text = upcoming[i]
		else:
			label.text = ""
#endregion

#region 输入与判定
func _input(event: InputEvent) -> void:
	if _finished or not _running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			return
		_handle_typing_input(event as InputEventKey)
		get_viewport().set_input_as_handled()


func _handle_typing_input(event: InputEventKey) -> void:
	if event.unicode <= 0:
		return
	var ch: String = char(event.unicode)
	# 只接受字母输入
	if ch.to_lower() < "a" or ch.to_lower() > "z":
		return
	var target_ch: String = _current_word[_word_cursor]

	if ch.to_lower() == target_ch.to_lower():
		_on_correct_key()
	else:
		_on_miss()


func _on_correct_key() -> void:
	# 速度判定
	var now: float = _game_time
	var key_delta: float = now - _last_key_time
	_last_key_time = now

	var judge: String = ""
	var judge_score: int = 0
	var judge_color: Color = COLOR_GOOD

	if key_delta <= SPEED_PERFECT:
		judge = "PERFECT"
		judge_score = SCORE_PERFECT
		judge_color = COLOR_PERFECT
		_perfect_count += 1
	elif key_delta <= SPEED_GREAT:
		judge = "GREAT"
		judge_score = SCORE_GREAT
		judge_color = COLOR_GREAT
		_great_count += 1
	else:
		judge = "GOOD"
		judge_score = SCORE_GOOD
		judge_color = COLOR_GOOD
		_good_count += 1

	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_total_score += judge_score

	# 推进单词光标
	_word_cursor += 1

	# 视觉反馈
	_show_judge(judge, judge_color, judge == "PERFECT")
	_update_combo_display()
	_update_word_display()
	_update_status_bar()

	# 检查单词是否完成
	if _word_cursor >= _current_word.length():
		_on_word_complete()


func _on_word_complete() -> void:
	_words_completed += 1
	_total_chars_typed += _current_word.length()

	# 计算代码推进量
	var combo_mult: float = 1.0 + minf(float(_combo), 50.0) * 0.03
	var chars_to_add: int = int(float(_current_word.length()) * CODE_CHARS_PER_LETTER * combo_mult)
	_code_pending += float(chars_to_add)

	# 单词完成特效
	_show_word_complete_effect()

	# 切换下一个单词
	_advance_to_next_word()
	_update_word_display()
	_update_upcoming_display()


func _show_word_complete_effect() -> void:
	if _check_label != null and is_instance_valid(_check_label):
		_check_label.text = "✓"
		_check_label.modulate.a = 1.0
		_check_label.scale = Vector2(1.5, 1.5)
		_check_label.pivot_offset = _check_label.size / 2.0
		var tw := create_tween()
		tw.tween_property(_check_label, "scale", Vector2.ONE, 0.1)
		tw.tween_property(_check_label, "modulate:a", 0.0, 0.3)
	# 单词显示弹跳
	if _word_display != null and is_instance_valid(_word_display):
		_word_display.pivot_offset = _word_display.size / 2.0
		_word_display.scale = Vector2(1.12, 1.12)
		var tw2 := create_tween()
		tw2.tween_property(_word_display, "scale", Vector2.ONE, 0.12)


func _on_miss() -> void:
	_miss_count += 1
	var was_high_combo: bool = _combo >= 10
	_combo = 0
	_show_judge("MISS", COLOR_MISS, false)
	_update_combo_display()
	_update_status_bar()
	if was_high_combo and _root_panel != null and is_instance_valid(_root_panel):
		var shake_tw := create_tween()
		shake_tw.tween_property(_root_panel, "position", Vector2(6, 0), 0.03)
		shake_tw.tween_property(_root_panel, "position", Vector2(-4, 0), 0.03)
		shake_tw.tween_property(_root_panel, "position", Vector2(2, 0), 0.03)
		shake_tw.tween_property(_root_panel, "position", Vector2.ZERO, 0.03)
		_show_screen_flash(Color(COLOR_MISS, 0.12))
#endregion

#region 视觉反馈
func _show_judge(text: String, color: Color, is_extra: bool) -> void:
	_judge_label.text = text
	_judge_label.add_theme_color_override("font_color", color)
	_judge_label.scale = Vector2(1.5, 1.5)
	_judge_label.pivot_offset = _judge_label.size / 2.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(_judge_label, "scale", Vector2.ONE, 0.3)

	if is_extra:
		_extra_label.text = "✦ EXTRA ✦"
		_extra_label.modulate.a = 1.0
		_extra_label.scale = Vector2(1.3, 1.3)
		_extra_label.pivot_offset = _extra_label.size / 2.0
		var tw2 := create_tween()
		tw2.tween_property(_extra_label, "scale", Vector2.ONE, 0.15)
		tw2.parallel().tween_property(_extra_label, "modulate:a", 0.0, 0.8)
	else:
		_extra_label.text = ""

	if text == "PERFECT":
		_show_screen_flash(Color(color, 0.15))
	elif text == "GREAT":
		_show_screen_flash(Color(color, 0.08))

	if text != "MISS":
		_show_hit_burst(color)


func _show_screen_flash(color: Color) -> void:
	if _screen_flash == null or not is_instance_valid(_screen_flash):
		return
	_screen_flash.color = color
	var tw := create_tween()
	tw.tween_property(_screen_flash, "color:a", 0.0, 0.2)


func _show_hit_burst(color: Color) -> void:
	if _hit_burst_container == null or not is_instance_valid(_hit_burst_container):
		return
	if _hit_burst_container.get_child_count() > 20:
		return
	var center: Vector2 = _combo_number.global_position + _combo_number.size / 2.0
	var burst_count: int = 6 if _combo >= 15 else 4
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(burst_count):
		var line := ColorRect.new()
		var angle: float = rng.randf_range(0, TAU)
		var length: float = rng.randf_range(30, 60)
		line.size = Vector2(3, length)
		line.color = Color(color, 0.8)
		line.position = center - Vector2(1.5, length / 2)
		line.pivot_offset = Vector2(1.5, length / 2)
		line.rotation = angle
		_hit_burst_container.add_child(line)
		var tw := create_tween()
		var end_pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * rng.randf_range(60, 120)
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(line, "position", end_pos - Vector2(1.5, length / 2), 0.35)
		tw.parallel().tween_property(line, "modulate:a", 0.0, 0.35)
		tw.tween_callback(line.queue_free)
#endregion

#region Combo 显示
func _update_combo_display() -> void:
	_combo_number.text = str(_combo)
	if _combo >= 75:
		_combo_number.add_theme_color_override("font_color", COLOR_EXTRA)
		_combo_label.text = "FEVER!"
	elif _combo >= 30:
		_combo_number.add_theme_color_override("font_color", Color("#f9e2af"))
		_combo_label.text = "COMBO"
	elif _combo >= 10:
		_combo_number.add_theme_color_override("font_color", ACCENT)
		_combo_label.text = "COMBO"
	else:
		_combo_number.add_theme_color_override("font_color", TEXT_LINENUM)
		_combo_label.text = "COMBO"

	if _combo > 0:
		var bounce: float = 1.2 + minf(float(_combo) / 80.0, 0.3)
		_combo_number.scale = Vector2(bounce, bounce)
		_combo_number.pivot_offset = _combo_number.size / 2.0
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_combo_number, "scale", Vector2.ONE, 0.15)

	# 能量条
	if _combo_energy_fill != null and is_instance_valid(_combo_energy_fill):
		var next_ms: int = _get_next_milestone(_combo)
		var prev_ms: int = _get_prev_milestone(_combo)
		if next_ms > prev_ms:
			var energy_ratio: float = float(_combo - prev_ms) / float(next_ms - prev_ms)
			_combo_energy_fill.anchor_right = clampf(energy_ratio, 0.0, 1.0)
			if _combo >= 75:
				_combo_energy_fill.color = COLOR_EXTRA
			elif _combo >= 30:
				_combo_energy_fill.color = Color("#f9e2af")
			else:
				_combo_energy_fill.color = ACCENT
		else:
			_combo_energy_fill.anchor_right = 1.0
			_combo_energy_fill.color = COLOR_EXTRA

	# 里程碑
	if COMBO_MILESTONES.has(_combo):
		var ms: Dictionary = COMBO_MILESTONES[_combo]
		_show_milestone(str(ms["text"]), Color(str(ms["color_hex"])))


func _show_milestone(text: String, color: Color) -> void:
	if _milestone_label == null or not is_instance_valid(_milestone_label):
		return
	_milestone_label.text = text
	_milestone_label.add_theme_color_override("font_color", color)
	_milestone_label.add_theme_font_size_override("font_size", 32)
	_milestone_label.modulate.a = 1.0
	_milestone_label.scale = Vector2(2.0, 2.0)
	_milestone_label.pivot_offset = _milestone_label.size / 2.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_milestone_label, "scale", Vector2.ONE, 0.3)
	tw.tween_interval(0.5)
	tw.tween_property(_milestone_label, "modulate:a", 0.0, 0.4)
	_show_screen_flash(Color(color, 0.2))


func _get_next_milestone(current_combo: int) -> int:
	var keys: Array = COMBO_MILESTONES.keys()
	keys.sort()
	for k in keys:
		if int(k) > current_combo:
			return int(k)
	return int(keys[-1]) if not keys.is_empty() else 100


func _get_prev_milestone(current_combo: int) -> int:
	var keys: Array = COMBO_MILESTONES.keys()
	keys.sort()
	var prev: int = 0
	for k in keys:
		if int(k) <= current_combo:
			prev = int(k)
		else:
			break
	return prev


func _update_status_bar() -> void:
	var code_pct: float = float(_code_reveal_idx) / maxf(float(_code_total_chars), 1.0) * 100.0
	_status_words.text = "单词 %d" % _words_completed
	_status_code.text = "代码 %d%%" % int(code_pct)
	_status_score.text = "得分 %d" % _total_score
#endregion

#region 代码动画
func _get_code_speed() -> float:
	return minf(BASE_CODE_SPEED + float(_combo) * 0.6, MAX_CODE_SPEED)
#endregion

#region 主循环与结算
func _process(delta: float) -> void:
	# 开场倒计时
	if _countdown > 0.0:
		_countdown -= delta
		if _countdown <= 0.0:
			if _countdown_label != null and is_instance_valid(_countdown_label):
				_countdown_label.text = "GO!"
				var tw := create_tween()
				tw.tween_property(_countdown_label, "modulate:a", 0.0, 0.4)
				tw.tween_callback(func() -> void:
					if _countdown_label != null and is_instance_valid(_countdown_label):
						_countdown_label.queue_free()
						_countdown_label = null
				)
			set_process_input(true)
			_running = true
		else:
			if _countdown_label != null and is_instance_valid(_countdown_label):
				var num: int = ceili(_countdown)
				_countdown_label.text = str(num)
				var frac: float = _countdown - floorf(_countdown)
				if frac > 0.85:
					_countdown_label.scale = Vector2(1.3, 1.3)
				else:
					_countdown_label.scale = _countdown_label.scale.lerp(Vector2.ONE, delta * 5.0)
		return

	if _finished or not _running:
		return

	_game_time += delta
	_time_remaining -= delta

	# 代码自动推进动画
	if _code_pending > 0.0 and _code_reveal_idx < _code_total_chars:
		var speed: float = _get_code_speed()
		var chars_this_frame: float = speed * delta
		chars_this_frame = minf(chars_this_frame, _code_pending)
		_code_pending -= chars_this_frame
		_code_reveal_accum += chars_this_frame
		var new_chars: int = int(_code_reveal_accum)
		if new_chars > 0:
			_code_reveal_accum -= float(new_chars)
			_code_reveal_idx = mini(_code_reveal_idx + new_chars, _code_total_chars)
			_update_code_overlay()
			_update_status_bar()

	# 代码面板自动滚动
	_update_code_scroll(delta)

	# 时间
	if _time_remaining <= 0.0:
		_time_remaining = 0.0
		_end_game()
		return

	_timer_label.text = "%d s" % ceili(_time_remaining)
	var ratio: float = _time_remaining / TIME_LIMIT
	_timer_bar_fill.anchor_right = ratio
	if ratio > 0.5:
		_timer_bar_fill.color = PROGRESS_FILL
	elif ratio > 0.2:
		_timer_bar_fill.color = PROGRESS_WARN
		_timer_label.add_theme_color_override("font_color", PROGRESS_WARN)
	else:
		_timer_bar_fill.color = PROGRESS_DANGER
		_timer_label.add_theme_color_override("font_color", PROGRESS_DANGER)

	# 全部代码打完 → 提前结束
	if _code_reveal_idx >= _code_total_chars and _code_pending <= 0.0:
		_end_game()


func _end_game() -> void:
	_finished = true
	set_process_input(false)

	var total_correct: int = _perfect_count + _great_count + _good_count
	var total_attempts: int = maxi(total_correct + _miss_count, 1)
	var accuracy: float = float(total_correct) / float(total_attempts)
	var perfect_ratio: float = float(_perfect_count) / maxf(float(total_correct), 1.0)
	var code_completion: float = float(_code_reveal_idx) / maxf(float(_code_total_chars), 1.0)
	var score: float = clampf(accuracy * 0.3 + code_completion * 0.4 + perfect_ratio * 0.3, 0.0, 1.0)

	_show_result_overlay(score)


func _show_result_overlay(score: float) -> void:
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

	var grade: String = ""
	var grade_color: Color = TEXT_TYPED
	if score >= 0.9:
		grade = "S"; grade_color = Color("#f9e2af")
	elif score >= 0.75:
		grade = "A"; grade_color = TEXT_TYPED
	elif score >= 0.5:
		grade = "B"; grade_color = ACCENT
	elif score >= 0.3:
		grade = "C"; grade_color = PROGRESS_WARN
	else:
		grade = "D"; grade_color = COLOR_MISS

	var title := Label.new()
	title.text = "✓ 编译通过"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TEXT_TYPED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title)

	var gl := Label.new()
	gl.text = grade
	gl.add_theme_font_size_override("font_size", 64)
	gl.add_theme_color_override("font_color", grade_color)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(gl)

	var code_pct: float = float(_code_reveal_idx) / maxf(float(_code_total_chars), 1.0) * 100.0
	var stats := Label.new()
	stats.text = "PERFECT %d  ·  GREAT %d  ·  GOOD %d  ·  MISS %d" % [
		_perfect_count, _great_count, _good_count, _miss_count
	]
	stats.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	stats.add_theme_color_override("font_color", TEXT_STATUS)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(stats)

	var total_correct: int = _perfect_count + _great_count + _good_count
	var total_attempts: int = maxi(total_correct + _miss_count, 1)
	var accuracy_pct: float = float(total_correct) / float(total_attempts) * 100.0

	var info := Label.new()
	info.text = "单词 %d  ·  代码 %.0f%%  ·  最大连击 %d  ·  准确率 %.0f%%" % [
		_words_completed, code_pct, _max_combo, accuracy_pct
	]
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
		var _total_correct: int = _perfect_count + _great_count + _good_count
		var _total_attempts: int = maxi(_total_correct + _miss_count, 1)
		finish({
			"score": score,
			"accuracy": float(_total_correct) / float(_total_attempts),
			"max_combo": _max_combo,
			"elapsed": TIME_LIMIT - _time_remaining,
			"words_completed": _words_completed,
			"code_completion": float(_code_reveal_idx) / maxf(float(_code_total_chars), 1.0),
			"snippet_title": _snippet_a.get("tab_name", ""),
		})
	)
	var bc := CenterContainer.new()
	bc.add_child(btn)
	card.add_child(bc)
#endregion
