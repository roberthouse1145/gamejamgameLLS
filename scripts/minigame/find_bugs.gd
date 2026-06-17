extends MinigameBase
## Bug修复小游戏 — 记忆翻牌配对
##
## 桌面上排列着若干背面朝上的"Bug 卡片"。
## 玩家每次翻两张，配对相同 Bug 类型则消除。
## 全部消除即为修复完成。

#region Bug 类型库
const BUG_TYPES: Array = [
	{"id": "emotion", "label": "表情错误", "symbol": "T_T", "color_hex": "#f38ba8"},
	{"id": "bgm", "label": "BGM错误", "symbol": "~#~", "color_hex": "#89b4fa"},
	{"id": "name", "label": "名字错误", "symbol": "A?B", "color_hex": "#fab387"},
	{"id": "position", "label": "位置跳变", "symbol": "<->", "color_hex": "#a6e3a1"},
	{"id": "null_ref", "label": "空引用", "symbol": "nil", "color_hex": "#f5c2e7"},
	{"id": "loop", "label": "死循环", "symbol": "...", "color_hex": "#f9e2af"},
	{"id": "transition", "label": "转场错误", "symbol": ">>|", "color_hex": "#94e2d5"},
	{"id": "type_err", "label": "类型错误", "symbol": "!=#", "color_hex": "#cba6f7"},
]
#endregion

#region 视觉常量（白色活力风）
const BG_MAIN := Color("#f5f7fb")
const BG_TITLEBAR := Color("#ffffff")
const BG_STATUSBAR := Color("#ffffff")
const BG_CARD_BACK := Color("#f8fafc")
const BG_CARD_HOVER := Color("#eef2ff")
const BG_CARD_FRONT := Color("#ffffff")
const BORDER_DEFAULT := Color("#e5e7eb")
const BORDER_SOFT := Color("#e0e7ff")
const TEXT_TITLE := Color("#0f172a")
const TEXT_STATUS := Color("#475569")
const TEXT_DIM := Color("#94a3b8")
const ACCENT := Color("#6366f1")
const ACCENT_SOFT := Color("#e0e7ff")
const COLOR_MATCH := Color("#10b981")
const COLOR_MATCH_DARK := Color("#047857")
const COLOR_FAIL := Color("#f43f5e")
const COLOR_STREAK := Color("#f59e0b")

const CARD_SIZE := Vector2(128, 168)
const CARD_GAP: int = 18
const FONT_SIZE_SYMBOL: int = 40
const FONT_SIZE_LABEL: int = 15
const FONT_SIZE_UI: int = 17
const FLIP_DURATION: float = 0.15
const SHOW_DURATION: float = 0.45
const PREVIEW_DURATION: float = 1.4
#endregion

#region 游戏状态
enum Phase { PREVIEW, PLAYING, ENDED }
var _phase: Phase = Phase.PREVIEW
var _preview_timer: float = PREVIEW_DURATION
var _cards: Array[Dictionary] = []
var _first_idx: int = -1
var _second_idx: int = -1
var _matched_pairs: int = 0
var _total_pairs: int = 4
var _attempts: int = 0
var _streak: int = 0
var _max_streak: int = 0
var _input_locked: bool = false
var _elapsed: float = 0.0
#endregion

#region 节点引用
var _root_panel: PanelContainer
var _card_panels: Array[PanelContainer] = []
var _card_symbols: Array[Label] = []
var _card_names: Array[Label] = []
var _timer_label: Label
var _attempts_label: Label
var _pairs_label: Label
var _streak_label: Label
var _hint_label: Label
var _flash_rect: ColorRect
#endregion


#region 生命周期
func _on_minigame_start() -> void:
	_determine_difficulty()
	_generate_cards()
	_build_ui()
	_show_preview()


func _on_minigame_cleanup() -> void:
	_phase = Phase.ENDED


func _process(delta: float) -> void:
	match _phase:
		Phase.PREVIEW:
			_preview_timer -= delta
			if _hint_label != null and is_instance_valid(_hint_label):
				_hint_label.text = "记住位置！ %d" % ceili(maxf(_preview_timer, 0.0))
			if _preview_timer <= 0.0:
				_end_preview()
		Phase.PLAYING:
			_elapsed += delta
			if _timer_label != null and is_instance_valid(_timer_label):
				_timer_label.text = "%d s" % int(_elapsed)
#endregion


#region 卡牌生成
func _determine_difficulty() -> void:
	var day: int = get_current_day()
	if day <= 10:
		_total_pairs = 5
	elif day <= 25:
		_total_pairs = 6
	else:
		_total_pairs = 6


func _generate_cards() -> void:
	_cards.clear()
	var indices: Array[int] = []
	for i in range(BUG_TYPES.size()):
		indices.append(i)
	indices.shuffle()
	for i in range(_total_pairs):
		var type_idx: int = indices[i]
		_cards.append({"type_idx": type_idx, "flipped": false, "matched": false})
		_cards.append({"type_idx": type_idx, "flipped": false, "matched": false})
	_cards.shuffle()
#endregion


#region UI 构建
func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root_sb := StyleBoxFlat.new()
	root_sb.bg_color = BG_MAIN
	_root_panel.add_theme_stylebox_override("panel", root_sb)
	add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root_panel.add_child(vbox)

	_build_title_bar(vbox)

	# 主内容区居中
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(center)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 20)
	center.add_child(inner)

	_build_info_bar(inner)
	_build_card_grid(inner)

	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", COLOR_STREAK)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_hint_label)

	_build_status_bar(vbox)

	# 全屏闪光层
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)


func _build_title_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_TITLEBAR
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	bar.add_child(hbox)

	for c in [Color("#f43f5e"), Color("#f59e0b"), Color("#10b981")]:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = c
		hbox.add_child(dot)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp1)

	var title := Label.new()
	title.text = "🐞 Bug Tracker · 内测问题看板"
	title.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	title.add_theme_color_override("font_color", TEXT_TITLE)
	hbox.add_child(title)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp2)

	_timer_label = Label.new()
	_timer_label.text = "0 s"
	_timer_label.add_theme_font_size_override("font_size", FONT_SIZE_UI + 2)
	_timer_label.add_theme_color_override("font_color", ACCENT)
	hbox.add_child(_timer_label)


func _build_info_bar(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 32)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)

	_pairs_label = Label.new()
	_pairs_label.text = "已修复 0/%d" % _total_pairs
	_pairs_label.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	_pairs_label.add_theme_color_override("font_color", TEXT_TITLE)
	hbox.add_child(_pairs_label)

	_attempts_label = Label.new()
	_attempts_label.text = "尝试 0 次"
	_attempts_label.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	_attempts_label.add_theme_color_override("font_color", TEXT_STATUS)
	hbox.add_child(_attempts_label)

	_streak_label = Label.new()
	_streak_label.text = ""
	_streak_label.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	_streak_label.add_theme_color_override("font_color", COLOR_STREAK)
	hbox.add_child(_streak_label)


func _build_card_grid(parent: VBoxContainer) -> void:
	var cols: int = _total_pairs
	if _total_pairs == 6:
		cols = 4

	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", CARD_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GAP)

	var wrapper := CenterContainer.new()
	wrapper.add_child(grid)
	parent.add_child(wrapper)

	_card_panels.clear()
	_card_symbols.clear()
	_card_names.clear()
	for i in range(_cards.size()):
		var card := _create_card(i)
		_card_panels.append(card)
		grid.add_child(card)


func _create_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _make_card_back_sb())

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var sp_top := Control.new()
	sp_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sp_top)

	var symbol_lbl := Label.new()
	symbol_lbl.text = "?"
	symbol_lbl.add_theme_font_size_override("font_size", 42)
	symbol_lbl.add_theme_color_override("font_color", TEXT_DIM)
	symbol_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(symbol_lbl)
	_card_symbols.append(symbol_lbl)

	var name_lbl := Label.new()
	name_lbl.text = ""
	name_lbl.add_theme_font_size_override("font_size", FONT_SIZE_LABEL)
	name_lbl.add_theme_color_override("font_color", TEXT_DIM)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	_card_names.append(name_lbl)

	var sp_bot := Control.new()
	sp_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sp_bot)

	card.gui_input.connect(_on_card_input.bind(index))
	card.mouse_entered.connect(_on_card_hover_enter.bind(index))
	card.mouse_exited.connect(_on_card_hover_exit.bind(index))

	return card


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

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	bar.add_child(hbox)

	var mode := Label.new()
	mode.text = "Memory Check · 本轮反馈"
	mode.add_theme_font_size_override("font_size", FONT_SIZE_UI - 1)
	mode.add_theme_color_override("font_color", TEXT_DIM)
	hbox.add_child(mode)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp)

	var ver := Label.new()
	ver.text = "· 打开两张相同的卡片即为匹配 ·"
	ver.add_theme_font_size_override("font_size", FONT_SIZE_UI - 1)
	ver.add_theme_color_override("font_color", TEXT_DIM)
	hbox.add_child(ver)
#endregion


#region 预览阶段
func _show_preview() -> void:
	_phase = Phase.PREVIEW
	_preview_timer = PREVIEW_DURATION
	_input_locked = true
	for i in range(_cards.size()):
		_set_card_front(i)
	if _hint_label != null:
		_hint_label.text = "记住位置！ %d" % ceili(PREVIEW_DURATION)
		_hint_label.add_theme_font_size_override("font_size", 20)
		_hint_label.add_theme_color_override("font_color", COLOR_STREAK)


func _end_preview() -> void:
	_phase = Phase.PLAYING
	for i in range(_cards.size()):
		_flip_to_back_anim(i, float(i) * 0.06)
	if _hint_label != null:
		_hint_label.add_theme_font_size_override("font_size", FONT_SIZE_UI)
		_hint_label.add_theme_color_override("font_color", TEXT_DIM)
	# 等所有翻牌动画完后再解锁输入
	var total_delay: float = float(_cards.size()) * 0.06 + FLIP_DURATION * 2.0 + 0.1
	var tw := create_tween()
	tw.tween_interval(total_delay)
	tw.tween_callback(func():
		_input_locked = false
		if _hint_label != null and is_instance_valid(_hint_label):
			_hint_label.text = "翻开两张卡片，找出相同的 Bug"
	)
#endregion


#region 卡牌显示
func _set_card_front(index: int) -> void:
	var card: PanelContainer = _card_panels[index]
	var type_data: Dictionary = BUG_TYPES[_cards[index].type_idx]
	var color := Color(str(type_data.color_hex))

	card.add_theme_stylebox_override("panel", _card_front_sb(color))
	_card_symbols[index].text = str(type_data.symbol)
	_card_symbols[index].add_theme_font_size_override("font_size", FONT_SIZE_SYMBOL)
	_card_symbols[index].add_theme_color_override("font_color", color)
	_card_names[index].text = str(type_data.label)
	_card_names[index].add_theme_color_override("font_color", TEXT_STATUS)


func _set_card_back(index: int) -> void:
	var card: PanelContainer = _card_panels[index]
	card.add_theme_stylebox_override("panel", _make_card_back_sb())
	_card_symbols[index].text = "?"
	_card_symbols[index].add_theme_font_size_override("font_size", 44)
	_card_symbols[index].add_theme_color_override("font_color", ACCENT)
	_card_names[index].text = ""
#endregion


#region 翻牌动画
func _flip_to_front_anim(index: int) -> void:
	_cards[index].flipped = true
	var card: PanelContainer = _card_panels[index]
	card.pivot_offset = card.size / 2.0
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2(0.0, 1.0), FLIP_DURATION)
	tw.tween_callback(_set_card_front.bind(index))
	tw.tween_property(card, "scale", Vector2(1.0, 1.0), FLIP_DURATION)

func _flip_to_back_anim(index: int, delay: float = 0.0) -> void:
	_cards[index].flipped = false
	var card: PanelContainer = _card_panels[index]
	card.pivot_offset = card.size / 2.0
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(card, "scale", Vector2(0.0, 1.0), FLIP_DURATION)
	tw.tween_callback(_set_card_back.bind(index))
	tw.tween_property(card, "scale", Vector2(1.0, 1.0), FLIP_DURATION)
#endregion


#region 卡牌交互
func _on_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_card_clicked(index)


func _on_card_hover_enter(index: int) -> void:
	if _phase != Phase.PLAYING or _input_locked:
		return
	if _cards[index].matched or _cards[index].flipped:
		return
	_card_panels[index].add_theme_stylebox_override("panel", _card_sb(BG_CARD_HOVER, ACCENT, 12, 2))
	var card: PanelContainer = _card_panels[index]
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card.pivot_offset = card.size / 2.0
	tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.15)


func _on_card_hover_exit(index: int) -> void:
	if _cards[index].matched or _cards[index].flipped:
		return
	_card_panels[index].add_theme_stylebox_override("panel", _make_card_back_sb())
	var card: PanelContainer = _card_panels[index]
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card.pivot_offset = card.size / 2.0
	tw.tween_property(card, "scale", Vector2.ONE, 0.15)


func _on_card_clicked(index: int) -> void:
	if _phase != Phase.PLAYING or _input_locked:
		return
	if _cards[index].matched or _cards[index].flipped:
		return

	_flip_to_front_anim(index)

	if _first_idx == -1:
		_first_idx = index
	elif _second_idx == -1:
		_second_idx = index
		_attempts += 1
		_update_info()
		_input_locked = true
		# 等翻牌动画完成后再检测配对
		var tw := create_tween()
		tw.tween_interval(FLIP_DURATION * 2.0 + SHOW_DURATION)
		tw.tween_callback(_resolve_match)
#endregion


#region 配对检测
func _resolve_match() -> void:
	if _cards[_first_idx].type_idx == _cards[_second_idx].type_idx:
		_on_match_success()
	else:
		_on_match_fail()


func _on_match_success() -> void:
	_cards[_first_idx].matched = true
	_cards[_second_idx].matched = true
	_matched_pairs += 1
	_streak += 1
	_max_streak = maxi(_max_streak, _streak)

	_pulse_card(_first_idx)
	_pulse_card(_second_idx)
	_show_flash(Color(COLOR_MATCH, 0.1))

	var type_data: Dictionary = BUG_TYPES[_cards[_first_idx].type_idx]
	_hint_label.text = "✓ 修复了「%s」！" % str(type_data.label)
	_hint_label.add_theme_color_override("font_color", COLOR_MATCH)
	_streak_label.text = "连续修复 x%d" % _streak if _streak >= 2 else ""
	_update_info()

	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		_fade_card(_first_idx)
		_fade_card(_second_idx)
	)
	tw.tween_interval(0.3)
	tw.tween_callback(func():
		_first_idx = -1
		_second_idx = -1
		_input_locked = false
		if _matched_pairs >= _total_pairs:
			_phase = Phase.ENDED
			var end_tw := create_tween()
			end_tw.tween_interval(0.4)
			end_tw.tween_callback(_end_game)
	)


func _on_match_fail() -> void:
	_streak = 0
	_streak_label.text = ""

	_hint_label.text = "✗ 不匹配"
	_hint_label.add_theme_color_override("font_color", COLOR_FAIL)
	_show_flash(Color(COLOR_FAIL, 0.05))

	_flip_to_back_anim(_first_idx)
	_flip_to_back_anim(_second_idx)

	var tw := create_tween()
	tw.tween_interval(FLIP_DURATION * 2.0 + 0.1)
	tw.tween_callback(func():
		_first_idx = -1
		_second_idx = -1
		_input_locked = false
	)
#endregion


#region 视觉效果
func _pulse_card(index: int) -> void:
	var card: PanelContainer = _card_panels[index]
	var type_data: Dictionary = BUG_TYPES[_cards[index].type_idx]
	var color := Color(str(type_data.color_hex))
	card.add_theme_stylebox_override("panel", _card_sb(Color(color, 0.15), COLOR_MATCH, 12, 3))
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(1.1, 1.1)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card, "scale", Vector2.ONE, 0.2)


func _fade_card(index: int) -> void:
	var card: PanelContainer = _card_panels[index]
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 0.15, 0.3)


func _show_flash(color: Color) -> void:
	if _flash_rect == null or not is_instance_valid(_flash_rect):
		return
	_flash_rect.color = color
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.2)


func _update_info() -> void:
	if _pairs_label != null:
		_pairs_label.text = "已修复 %d/%d" % [_matched_pairs, _total_pairs]
	if _attempts_label != null:
		_attempts_label.text = "尝试 %d 次" % _attempts
#endregion


#region 结算
func _end_game() -> void:
	var score: float = _calculate_score()
	_show_result_overlay(score)


func _calculate_score() -> float:
	# 效率：尝试次数越少越好（完美 = total_pairs 次）
	var min_attempts: int = _total_pairs
	var efficiency: float = clampf(float(min_attempts) / maxf(float(_attempts), 1.0), 0.0, 1.0)
	# 时间：越快越好（每对约 12 秒为基准）
	var time_par: float = float(_total_pairs) * 12.0
	var time_bonus: float = clampf(1.0 - maxf(_elapsed - float(_total_pairs) * 4.0, 0.0) / time_par, 0.0, 1.0)
	# 连续配对奖励
	var streak_bonus: float = clampf(float(_max_streak) / maxf(float(_total_pairs), 1.0), 0.0, 1.0)
	return clampf(efficiency * 0.5 + time_bonus * 0.3 + streak_bonus * 0.2, 0.0, 1.0)


func _show_result_overlay(score: float) -> void:
	var overlay := PanelContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(15.0 / 255.0, 23.0 / 255.0, 42.0 / 255.0, 0.55)
	overlay.add_theme_stylebox_override("panel", sb)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color("#ffffff")
	card_sb.set_corner_radius_all(20)
	card_sb.border_color = BORDER_SOFT
	card_sb.set_border_width_all(1)
	card_sb.shadow_color = Color(0, 0, 0, 0.18)
	card_sb.shadow_size = 24
	card_sb.shadow_offset = Vector2(0, 8)
	card_sb.content_margin_left = 40
	card_sb.content_margin_right = 40
	card_sb.content_margin_top = 32
	card_sb.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var grade: String
	var grade_color: Color
	if score >= 0.9:
		grade = "S"; grade_color = COLOR_STREAK
	elif score >= 0.75:
		grade = "A"; grade_color = COLOR_MATCH
	elif score >= 0.5:
		grade = "B"; grade_color = ACCENT
	elif score >= 0.3:
		grade = "C"; grade_color = Color("#f97316")
	else:
		grade = "D"; grade_color = COLOR_FAIL

	var title_lbl := Label.new()
	title_lbl.text = "✓ 全部 Bug 已修复！"
	title_lbl.add_theme_font_size_override("font_size", 32)
	title_lbl.add_theme_color_override("font_color", COLOR_MATCH_DARK)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var gl := Label.new()
	gl.text = grade
	gl.add_theme_font_size_override("font_size", 76)
	gl.add_theme_color_override("font_color", grade_color)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gl)

	var eff_pct: float = float(_total_pairs) / maxf(float(_attempts), 1.0) * 100.0
	var stats := Label.new()
	stats.text = "修复 %d 个 Bug · 尝试 %d 次 · 用时 %d 秒" % [_total_pairs, _attempts, int(_elapsed)]
	stats.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	stats.add_theme_color_override("font_color", TEXT_STATUS)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	var info := Label.new()
	info.text = "效率 %.0f%% · 最大连续 %d" % [eff_pct, _max_streak]
	info.add_theme_font_size_override("font_size", FONT_SIZE_UI)
	info.add_theme_color_override("font_color", TEXT_DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	var btn := Button.new()
	btn.text = "完成"
	btn.custom_minimum_size = Vector2(160, 52)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_UI + 3)
	_style_finish_button(btn)
	btn.pressed.connect(func():
		finish({
			"score": score,
			"accuracy": float(_total_pairs) / maxf(float(_attempts), 1.0),
			"max_combo": _max_streak,
			"elapsed": _elapsed,
			"total_pairs": _total_pairs,
			"attempts": _attempts,
			"completed_lines": _matched_pairs,
			"total_lines": _total_pairs,
		})
	)
	var bc := CenterContainer.new()
	bc.add_child(btn)
	vbox.add_child(bc)


func _style_finish_button(btn: Button) -> void:
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = COLOR_MATCH
	normal_sb.set_corner_radius_all(26)
	normal_sb.content_margin_left = 24
	normal_sb.content_margin_right = 24
	normal_sb.content_margin_top = 12
	normal_sb.content_margin_bottom = 12
	normal_sb.shadow_color = Color(COLOR_MATCH.r, COLOR_MATCH.g, COLOR_MATCH.b, 0.35)
	normal_sb.shadow_size = 8
	normal_sb.shadow_offset = Vector2(0, 3)
	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = COLOR_MATCH_DARK
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
#endregion


#region 工具方法
func _card_sb(bg: Color, border: Color, radius: int = 12, border_w: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.shadow_color = Color(15.0 / 255.0, 23.0 / 255.0, 42.0 / 255.0, 0.10)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	return s


func _card_front_sb(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_CARD_FRONT
	s.set_corner_radius_all(12)
	s.border_color = accent
	s.border_width_left = 5
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	return s


func _make_card_back_sb() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_CARD_BACK
	s.set_corner_radius_all(12)
	s.border_color = BORDER_SOFT
	s.set_border_width_all(2)
	s.shadow_color = Color(15.0 / 255.0, 23.0 / 255.0, 42.0 / 255.0, 0.06)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s
#endregion
