class_name TimeStatusBar extends PseudoWindow
## 今日进度小组件 — 继承 PseudoWindow，禁用缩放/关闭按钮
## 卡片化分区：天数 / 时段 / 完成度 / 属性状态 / 项目状态

const MAX_DAYS: int = 45

## 时段颜色
const C_MORNING:   Color = Color("#F5A623")
const C_AFTERNOON: Color = Color("#3FB27F")
const C_NIGHT:     Color = Color("#7B6BDB")

## 属性颜色
const C_AFFECTION: Color = Color("#E86088")
const C_STRESS: Color    = Color("#E89050")
const C_PASSION: Color   = Color("#5898E0")
const C_MONEY: Color     = Color("#D8B030")

## 项目数值颜色
const C_COMPLETION: Color = Color("#8368DC")
const C_QUALITY: Color    = Color("#3FB27F")
const C_STABILITY: Color  = Color("#5898E0")
const C_HYPE: Color       = Color("#E89050")

## 通用
const C_CARD_BG: Color   = Color("#FFFFFF")
const C_CARD_BG2: Color  = Color("#F4F6FB")
const C_BORDER: Color    = Color("#E4E8F0")
const C_TRACK: Color     = Color("#E9EDF5")
const C_DAY_FILL: Color  = Color("#7A8CEB")
const C_TEXT_MAIN: Color = Color("#1A1D27")
const C_TEXT_SUB: Color  = Color("#6B7086")
const C_TEXT_MUTED: Color = Color("#8A92A8")

## 字号 / 布局
const F_DAY: int   = 42
const F_DAY_UNIT: int = 17
const F_HD: int    = 16
const F_VAL: int   = 22
const F_CHIP: int  = 16
const F_LABEL: int = 14
const F_TAG: int   = 13
const BAR_H: int   = 10
const ICON_SIZE: int = 20
const CARD_PAD_X: int = 16
const CARD_PAD_Y: int = 14
const OUTER_PAD: int  = 16
const CARD_SEP: int   = 12

## 图标（有则用，没有就退到字符徽标）
const ICON_AFFECTION: Texture2D = preload("res://Assets/icons/icon_affection.png")
const ICON_STRESS: Texture2D    = preload("res://Assets/icons/icon_stress.png")
const ICON_PASSION: Texture2D   = preload("res://Assets/icons/icon_passion.png")
const ICON_MONEY: Texture2D     = preload("res://Assets/icons/icon_money.png")

var _day_label: Label          = null
var _day_unit: Label           = null
var _day_progress: ProgressBar = null
var _day_frac: Label           = null

var _phase_chips: Dictionary   = {}  ## phase_idx -> {panel, label, style_active, style_inactive, color}

## key -> Label（数值）
var _stat_labels: Dictionary   = {}

## 项目完成度
var _comp_progress: ProgressBar = null
var _comp_val: Label           = null

var _game_loop: Node    = null
var _game_manager: Node = null


func _ready() -> void:
	_game_loop    = get_node_or_null("/root/GameLoopManager")
	_game_manager = get_node_or_null("/root/GameManager")

	super._ready()

	window_title = "今日进度"
	resizable    = false

	# 简化标题栏：隐藏所有窗口按钮
	if minimize_button:
		minimize_button.hide()
	if maximize_button:
		maximize_button.hide()
	if close_button:
		close_button.hide()

	_build_content()
	_connect_signals()
	_refresh()

	# 延迟一帧后根据内容容器的最小尺寸自动调整窗口高度
	call_deferred("_fit_to_content")


func _fit_to_content() -> void:
	if not content_container or content_container.get_child_count() == 0:
		return
	var inner: Control = content_container.get_child(0)
	# 等一帧让 GridContainer/PanelContainer 计算好最小尺寸
	await get_tree().process_frame
	var need_h: float = inner.get_combined_minimum_size().y
	var tb_h: float = title_bar.size.y if title_bar else 52.0
	self.size.y = ceil(need_h + tb_h)


# =============================================================================
# Build
# =============================================================================

func _build_content() -> void:
	if not content_container:
		return

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left",   OUTER_PAD)
	mg.add_theme_constant_override("margin_right",  OUTER_PAD)
	mg.add_theme_constant_override("margin_top",    OUTER_PAD)
	mg.add_theme_constant_override("margin_bottom", OUTER_PAD)
	content_container.add_child(mg)
	mg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", CARD_SEP)
	mg.add_child(vb)

	_mk_day_card(vb)
	_mk_phase_card(vb)
	_mk_completion_card(vb)
	_mk_stats_card(vb, "林夏状态", [
		{"key": "affection", "label": "好感", "color": C_AFFECTION, "icon": ICON_AFFECTION},
		{"key": "stress",    "label": "压力", "color": C_STRESS,    "icon": ICON_STRESS},
		{"key": "passion",   "label": "热情", "color": C_PASSION,   "icon": ICON_PASSION},
	])
	_mk_stats_card(vb, "项目状态", [
		{"key": "quality",   "label": "质量", "color": C_QUALITY,   "glyph": "◈"},
		{"key": "stability", "label": "稳定", "color": C_STABILITY, "glyph": "◉"},
		{"key": "hype",      "label": "热度", "color": C_HYPE,      "glyph": "✦"},
	])


## 卡片外壳（圆角 + 浅边框 + 轻底色）
func _mk_card(p: Control, bg: Color = C_CARD_BG) -> MarginContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = C_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	_rc(style, 10)
	panel.add_theme_stylebox_override("panel", style)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left",   CARD_PAD_X)
	mg.add_theme_constant_override("margin_right",  CARD_PAD_X)
	mg.add_theme_constant_override("margin_top",    CARD_PAD_Y)
	mg.add_theme_constant_override("margin_bottom", CARD_PAD_Y)
	panel.add_child(mg)
	return mg


func _mk_day_card(p: Control) -> void:
	var body := _mk_card(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	body.add_child(vb)

	# 顶行：大号 "Day" 数字 + "/ 45" 副标
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_child(top)

	var tag := Label.new()
	tag.text = "DAY"
	tag.add_theme_font_size_override("font_size", F_TAG)
	tag.add_theme_color_override("font_color", C_TEXT_MUTED)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.custom_minimum_size.y = 32
	top.add_child(tag)

	_day_label = Label.new()
	_day_label.text = "1"
	_day_label.add_theme_font_size_override("font_size", F_DAY)
	_day_label.add_theme_color_override("font_color", C_TEXT_MAIN)
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(_day_label)

	_day_unit = Label.new()
	_day_unit.text = "/ %d" % MAX_DAYS
	_day_unit.add_theme_font_size_override("font_size", F_DAY_UNIT)
	_day_unit.add_theme_color_override("font_color", C_TEXT_SUB)
	_day_unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_day_unit.custom_minimum_size.y = 32
	top.add_child(_day_unit)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	_day_frac = Label.new()
	_day_frac.text = "GameJam 进度"
	_day_frac.add_theme_font_size_override("font_size", F_LABEL)
	_day_frac.add_theme_color_override("font_color", C_TEXT_MUTED)
	_day_frac.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_frac.custom_minimum_size.y = 32
	top.add_child(_day_frac)

	# 进度条
	_day_progress = ProgressBar.new()
	_day_progress.min_value = 0
	_day_progress.max_value = MAX_DAYS
	_day_progress.value = 1
	_day_progress.show_percentage = false
	_day_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_progress.custom_minimum_size.y = BAR_H

	var bg := StyleBoxFlat.new()
	bg.bg_color = C_TRACK
	_rc(bg, 4)
	_day_progress.add_theme_stylebox_override("background", bg)

	var fl := StyleBoxFlat.new()
	fl.bg_color = C_DAY_FILL
	_rc(fl, 4)
	_day_progress.add_theme_stylebox_override("fill", fl)
	vb.add_child(_day_progress)


func _mk_phase_card(p: Control) -> void:
	var body := _mk_card(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)

	_mk_phase_chip(row, 0, "上午", C_MORNING)
	_mk_phase_chip(row, 1, "下午", C_AFTERNOON)
	_mk_phase_chip(row, 2, "晚上", C_NIGHT)

	# 金钱区块（右对齐，与 phase chip 同一行）
	var sep := Control.new()
	sep.custom_minimum_size.x = 4
	row.add_child(sep)

	var money_box := HBoxContainer.new()
	money_box.add_theme_constant_override("separation", 4)
	money_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(money_box)

	var money_icon := TextureRect.new()
	money_icon.texture = ICON_MONEY
	money_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	money_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	money_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	money_box.add_child(money_icon)

	var money_val := Label.new()
	money_val.text = "0"
	money_val.add_theme_font_size_override("font_size", F_VAL)
	money_val.add_theme_color_override("font_color", C_MONEY)
	money_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	money_box.add_child(money_val)

	_stat_labels["money"] = {"label": money_val, "color": C_MONEY}


func _mk_phase_chip(row: HBoxContainer, phase_idx: int, text: String, color: Color) -> void:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style_active := StyleBoxFlat.new()
	style_active.bg_color = color
	_rc(style_active, 6)

	var style_inactive := StyleBoxFlat.new()
	style_inactive.bg_color = C_CARD_BG2
	style_inactive.border_color = C_BORDER
	style_inactive.border_width_left = 1
	style_inactive.border_width_top = 1
	style_inactive.border_width_right = 1
	style_inactive.border_width_bottom = 1
	_rc(style_inactive, 6)

	chip.add_theme_stylebox_override("panel", style_inactive)
	row.add_child(chip)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 4)
	mg.add_theme_constant_override("margin_right", 4)
	mg.add_theme_constant_override("margin_top", 5)
	mg.add_theme_constant_override("margin_bottom", 5)
	chip.add_child(mg)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", F_CHIP)
	lbl.add_theme_color_override("font_color", C_TEXT_SUB)
	mg.add_child(lbl)

	_phase_chips[phase_idx] = {
		"panel": chip,
		"label": lbl,
		"style_active": style_active,
		"style_inactive": style_inactive,
		"color": color,
	}


func _mk_completion_card(p: Control) -> void:
	var body := _mk_card(p, Color("#F8F5FD"))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	body.add_child(vb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var hd := Label.new()
	hd.text = "项目完成度"
	hd.add_theme_font_size_override("font_size", F_HD)
	hd.add_theme_color_override("font_color", C_TEXT_SUB)
	hd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hd)

	_comp_val = Label.new()
	_comp_val.text = "0%"
	_comp_val.add_theme_font_size_override("font_size", F_VAL)
	_comp_val.add_theme_color_override("font_color", C_COMPLETION)
	_comp_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_comp_val)

	_comp_progress = ProgressBar.new()
	_comp_progress.min_value = 0
	_comp_progress.max_value = 100
	_comp_progress.value = 0
	_comp_progress.show_percentage = false
	_comp_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comp_progress.custom_minimum_size.y = BAR_H

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#E5DEF5")
	_rc(bg, 4)
	_comp_progress.add_theme_stylebox_override("background", bg)

	var fl := StyleBoxFlat.new()
	fl.bg_color = C_COMPLETION
	_rc(fl, 4)
	_comp_progress.add_theme_stylebox_override("fill", fl)
	vb.add_child(_comp_progress)


## 统一的属性/项目三维卡片构造器
## entries: [{key, label, color, icon?, glyph?}, ...]
func _mk_stats_card(p: Control, title: String, entries: Array) -> void:
	var body := _mk_card(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	body.add_child(vb)

	var hd := Label.new()
	hd.text = title
	hd.add_theme_font_size_override("font_size", F_HD)
	hd.add_theme_color_override("font_color", C_TEXT_SUB)
	vb.add_child(hd)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	vb.add_child(grid)

	for entry in entries:
		_mk_stat_cell(grid, entry)


func _mk_stat_cell(row: HBoxContainer, entry: Dictionary) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 2)
	row.add_child(cell)

	# 顶行：图标/徽标 + 标签
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	cell.add_child(head)

	if entry.has("icon") and entry["icon"] != null:
		var ic := TextureRect.new()
		ic.texture = entry["icon"]
		ic.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		head.add_child(ic)
	elif entry.has("glyph"):
		var g := Label.new()
		g.text = str(entry["glyph"])
		g.add_theme_font_size_override("font_size", F_LABEL)
		g.add_theme_color_override("font_color", entry["color"])
		g.custom_minimum_size.x = ICON_SIZE
		head.add_child(g)

	var name_lbl := Label.new()
	name_lbl.text = str(entry["label"])
	name_lbl.add_theme_font_size_override("font_size", F_LABEL)
	name_lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_lbl)

	# 数值
	var val_lbl := Label.new()
	val_lbl.text = "0"
	val_lbl.add_theme_font_size_override("font_size", F_VAL)
	val_lbl.add_theme_color_override("font_color", entry["color"])
	cell.add_child(val_lbl)

	_stat_labels[entry["key"]] = {"label": val_lbl, "color": entry["color"]}


# =============================================================================
# Helpers
# =============================================================================

func _rc(s: StyleBoxFlat, r: int) -> void:
	s.corner_radius_top_left     = r
	s.corner_radius_top_right    = r
	s.corner_radius_bottom_left  = r
	s.corner_radius_bottom_right = r


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
		_upd_phase(0, false)
		return
	_upd_day(_game_loop.current_day)
	_upd_phase(_game_loop.time_phase, false)
	_upd_stats()


func _upd_day(day: int) -> void:
	if _day_label:
		_day_label.text = "%d" % day
	if _day_unit:
		_day_unit.text = "/ %d" % MAX_DAYS
	if _day_frac:
		_day_frac.text = "还剩 %d 天" % maxi(0, MAX_DAYS - day)
	if _day_progress:
		create_tween().tween_property(_day_progress, "value", float(day), 0.45) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _upd_phase(phase: int, animate: bool = true) -> void:
	for idx in _phase_chips.keys():
		var d: Dictionary = _phase_chips[idx]
		var panel: PanelContainer = d["panel"]
		var label: Label = d["label"]
		if int(idx) == phase:
			panel.add_theme_stylebox_override("panel", d["style_active"])
			label.add_theme_color_override("font_color", Color.WHITE)
			if animate:
				_chip_bounce(panel)
		else:
			panel.add_theme_stylebox_override("panel", d["style_inactive"])
			label.add_theme_color_override("font_color", C_TEXT_SUB)


func _chip_bounce(chip: Control) -> void:
	chip.pivot_offset = chip.size * 0.5
	var tw := create_tween()
	tw.tween_property(chip, "scale", Vector2(1.08, 1.08), 0.1) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(chip, "scale", Vector2.ONE, 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


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
	if _comp_val:
		_comp_val.text = "%d%%" % val
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
