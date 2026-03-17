class_name TimeStatusBar extends PseudoWindow
## 日程状态小组件 — 继承 PseudoWindow，禁用关闭按钮
## 显示当前天数、时段、角色属性、项目数值

const MAX_DAYS: int = 45

## 时段颜色
const C_MORNING:   Color = Color("#E8A830")
const C_AFTERNOON: Color = Color("#48B068")
const C_NIGHT:     Color = Color("#8868C8")

## 属性颜色
const C_AFFECTION: Color = Color("#E86088")
const C_STRESS: Color    = Color("#E89050")
const C_PASSION: Color   = Color("#5898E0")
const C_MONEY: Color     = Color("#D8B030")

## 项目数值颜色
const C_COMPLETION: Color = Color("#B088D8")
const C_QUALITY: Color    = Color("#60C090")
const C_STABILITY: Color  = Color("#5898E0")
const C_HYPE: Color       = Color("#E8A830")

## 进度条
const C_TRACK: Color    = Color("#E8E0F0")
const C_DAY_FILL: Color = Color("#B088D8")

## 布局常量 — 适配 2560x1440
const BAR_H: int = 10
const F_DAY: int = 48
const F_SUB: int = 20
const F_PH: int  = 24
const F_LBL: int = 20
const F_VAL: int = 20
const F_HD: int  = 22
const SEP: int   = 14
const PAD: int   = 24

var _day_label: Label          = null
var _day_progress: ProgressBar = null
var _day_frac: Label           = null
var _phase_dot: ColorRect      = null
var _phase_label: Label        = null

## key -> Label（只存数值 Label，无进度条）
var _stat_labels: Dictionary   = {}

## 项目完成度（单独一行，保留进度条）
var _comp_progress: ProgressBar = null
var _comp_frac: Label          = null

var _game_loop: Node    = null
var _game_manager: Node = null
var _pulse_tw: Tween    = null


func _ready() -> void:
	_game_loop    = get_node_or_null("/root/GameLoopManager")
	_game_manager = get_node_or_null("/root/GameManager")

	super._ready()

	window_title = "今日进度"
	resizable    = false

	if minimize_button:
		minimize_button.hide()
	if maximize_button:
		maximize_button.hide()
	if close_button:
		close_button.hide()

	_build_content()
	_connect_signals()
	_refresh()


# =============================================================================
# Build
# =============================================================================

func _build_content() -> void:
	if not content_container:
		return

	var mg := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(s, PAD)
	content_container.add_child(mg)
	mg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", SEP)
	mg.add_child(vb)

	_mk_day(vb)
	_mk_div(vb)
	_mk_phase(vb)
	_mk_div(vb)
	_mk_completion(vb)
	_mk_div(vb)
	_mk_stats(vb)
	_mk_div(vb)
	_mk_project_stats(vb)


func _mk_day(p: VBoxContainer) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)

	_day_label = Label.new()
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", F_DAY)
	vb.add_child(_day_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)

	_day_progress = ProgressBar.new()
	_day_progress.min_value = 0
	_day_progress.max_value = MAX_DAYS
	_day_progress.value = 1
	_day_progress.show_percentage = false
	_day_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_progress.custom_minimum_size.y = BAR_H

	var bg := StyleBoxFlat.new()
	bg.bg_color = C_TRACK
	_rc(bg, 5)
	_day_progress.add_theme_stylebox_override("background", bg)

	var fl := StyleBoxFlat.new()
	fl.bg_color = C_DAY_FILL
	_rc(fl, 5)
	_day_progress.add_theme_stylebox_override("fill", fl)
	row.add_child(_day_progress)

	_day_frac = Label.new()
	_day_frac.add_theme_font_size_override("font_size", F_SUB)
	_day_frac.custom_minimum_size.x = 72
	_day_frac.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_day_frac.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	#row.add_child(_day_frac)


func _mk_phase(p: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)

	_phase_dot = ColorRect.new()
	_phase_dot.custom_minimum_size = Vector2(14, 14)
	_phase_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_phase_dot.color = C_MORNING
	row.add_child(_phase_dot)

	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", F_PH)
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_phase_label)

	# 金钱：右对齐，与时段同行
	var money_lbl := Label.new()
	money_lbl.text = "¥"
	money_lbl.add_theme_font_size_override("font_size", F_LBL)
	money_lbl.add_theme_color_override("font_color", Color("#8899b0"))
	money_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(money_lbl)

	var money_val := Label.new()
	money_val.text = "0"
	money_val.add_theme_font_size_override("font_size", F_PH)
	money_val.add_theme_color_override("font_color", C_MONEY)
	money_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(money_val)

	_stat_labels["money"] = {"label": money_val, "color": C_MONEY}


func _mk_completion(p: VBoxContainer) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)

	# 进度条
	_comp_progress = ProgressBar.new()
	_comp_progress.min_value = 0
	_comp_progress.max_value = 100
	_comp_progress.value = 0
	_comp_progress.show_percentage = false
	_comp_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comp_progress.custom_minimum_size.y = BAR_H

	var bg := StyleBoxFlat.new()
	bg.bg_color = C_TRACK
	_rc(bg, 5)
	_comp_progress.add_theme_stylebox_override("background", bg)

	var fl := StyleBoxFlat.new()
	fl.bg_color = C_COMPLETION
	_rc(fl, 5)
	_comp_progress.add_theme_stylebox_override("fill", fl)
	vb.add_child(_comp_progress)

	# 进度条下方：「完成度  0%」居中
	_comp_frac = Label.new()
	_comp_frac.text = "完成度  0%"
	_comp_frac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_comp_frac.add_theme_font_size_override("font_size", F_HD)
	_comp_frac.add_theme_color_override("font_color", C_COMPLETION)
	vb.add_child(_comp_frac)


func _mk_stats(p: VBoxContainer) -> void:
	var hd := Label.new()
	hd.text = "林夏"
	hd.add_theme_font_size_override("font_size", F_HD)
	p.add_child(hd)

	# 第一行：好感 压力 热情（三列）
	var row1 := GridContainer.new()
	row1.columns = 6
	row1.add_theme_constant_override("h_separation", 16)
	row1.add_theme_constant_override("v_separation", 10)
	p.add_child(row1)

	_mk_inline(row1, "好感", "affection", C_AFFECTION)
	_mk_inline(row1, "压力", "stress",    C_STRESS)
	_mk_inline(row1, "热情", "passion",   C_PASSION)


func _mk_project_stats(p: VBoxContainer) -> void:
	var hd := Label.new()
	hd.text = "项目"
	hd.add_theme_font_size_override("font_size", F_HD)
	p.add_child(hd)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	p.add_child(grid)

	_mk_inline(grid, "质量", "quality",   C_QUALITY)
	_mk_inline(grid, "稳定", "stability", C_STABILITY)
	_mk_inline(grid, "热度", "hype",      C_HYPE)


## 在容器中添加一对 [名称 Label] + [数值 Label]
func _mk_inline(container: Control, text: String, key: String, color: Color) -> void:
	var name_lbl := Label.new()
	name_lbl.text = text
	name_lbl.add_theme_font_size_override("font_size", F_LBL)
	name_lbl.add_theme_color_override("font_color", Color("#8899b0"))
	container.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "0"
	val_lbl.add_theme_font_size_override("font_size", F_VAL)
	val_lbl.add_theme_color_override("font_color", color)
	val_lbl.custom_minimum_size.x = 52
	container.add_child(val_lbl)

	_stat_labels[key] = {"label": val_lbl, "color": color}


# =============================================================================
# Helpers
# =============================================================================

func _rc(s: StyleBoxFlat, r: int) -> void:
	s.corner_radius_top_left     = r
	s.corner_radius_top_right    = r
	s.corner_radius_bottom_left  = r
	s.corner_radius_bottom_right = r


func _mk_div(p: VBoxContainer) -> void:
	p.add_child(HSeparator.new())


# =============================================================================
# Signals
# =============================================================================

func _connect_signals() -> void:
	if _game_loop:
		_game_loop.day_changed.connect(_on_day_changed)
		_game_loop.phase_changed.connect(_on_phase_changed)
	if _game_manager:
		_game_manager.stats_changed.connect(_on_stats_changed)


# =============================================================================
# Refresh
# =============================================================================

func _refresh() -> void:
	if _game_loop == null:
		_upd_day(1)
		_upd_phase(0)
		return
	_upd_day(_game_loop.current_day)
	_upd_phase(_game_loop.time_phase)
	_upd_stats()


func _upd_day(day: int) -> void:
	if _day_label:
		_day_label.text = "Day  %d" % day
	if _day_frac:
		_day_frac.text = "%d / %d" % [day, MAX_DAYS]
	if _day_progress:
		create_tween().tween_property(_day_progress, "value", float(day), 0.45) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _upd_phase(phase: int) -> void:
	var nm: Dictionary = {0: "上午", 1: "下午", 2: "晚上"}
	var cm: Dictionary = {0: C_MORNING, 1: C_AFTERNOON, 2: C_NIGHT}
	var n: String = nm.get(phase, "—")
	var c: Color  = cm.get(phase, Color("#6B7086"))
	if _phase_label:
		_phase_label.text = n
		_phase_label.add_theme_color_override("font_color", c)
	if _phase_dot:
		_phase_dot.color = c
		_pulse(c)


func _pulse(base: Color) -> void:
	if _pulse_tw and _pulse_tw.is_valid():
		_pulse_tw.kill()
	var bright := base.lightened(0.3)
	_pulse_tw = create_tween().set_loops()
	_pulse_tw.tween_property(_phase_dot, "color", bright, 1.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tw.tween_property(_phase_dot, "color", base, 1.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _upd_stats() -> void:
	if _game_manager == null:
		return
	_set_s("affection", _game_manager.affection)
	_set_s("stress",    _game_manager.stress)
	_set_s("passion",   _game_manager.passion)
	_set_s("money",     _game_manager.money)
	_set_s("quality",   _game_manager.quality)
	_set_s("stability", _game_manager.stability)
	_set_s("hype",      _game_manager.hype)
	_upd_completion(_game_manager.completion)


func _upd_completion(val: int) -> void:
	if _comp_frac:
		_comp_frac.text = "完成度  %d%%" % val
	if _comp_progress:
		var old: int = int(_comp_progress.value)
		if old != val:
			create_tween().tween_property(_comp_progress, "value", float(val), 0.35) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			_comp_progress.value = val


func _set_s(key: String, val: int) -> void:
	if not _stat_labels.has(key):
		return
	var d: Dictionary = _stat_labels[key]
	var lbl: Label    = d["label"]
	var old_text: String = lbl.text
	var new_text: String = str(val)
	if old_text != new_text:
		lbl.text = new_text
		_flash(lbl, d["color"], val > old_text.to_int())


func _flash(lbl: Label, base_c: Color, up: bool) -> void:
	var fc := Color("#30B060") if up else Color("#D04050")
	lbl.add_theme_color_override("font_color", fc)
	create_tween().tween_property(lbl, "theme_override_colors/font_color",
		base_c, 0.7).set_delay(0.2)


# =============================================================================
# Callbacks
# =============================================================================

func _on_day_changed(d: int) -> void:
	_upd_day(d)

func _on_phase_changed(p: int) -> void:
	_upd_phase(p)

func _on_stats_changed() -> void:
	_upd_stats()
