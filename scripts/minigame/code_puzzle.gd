extends MinigameBase
## 代码排序小游戏
##
## 玩家需要将被打乱的代码行重新排列成正确顺序。题库来自
## res://resources/minigame/code_puzzles.json，一局连玩多题。

const PUZZLE_JSON_PATH := "res://resources/minigame/code_puzzles.json"
const PUZZLES_PER_RUN := 3

## 兜底题库：JSON 读取失败时使用
const FALLBACK_SNIPPETS: Array[Dictionary] = [
	{
		"title": "play_line.gd",
		"objective": "让一句台词正确地播完",
		"lines": [
			"📜 从剧本节点读出下一句台词",
			"📜 显示说话人的名字和立绘",
			"📜 用打字机效果把文字铺上屏幕",
			"📜 等玩家点击或自动延时结束",
			"📜 把当前节点向后推一位",
		],
	},
	{
		"title": "save_slot.gd",
		"objective": "把当前进度写入指定存档槽",
		"lines": [
			"💾 收集当前章节和节点索引",
			"💾 记录玩家属性与好感数值",
			"💾 打包立绘、BGM、CG 状态",
			"💾 生成截图作为存档缩略图",
			"💾 写入 user://save_%d.tres",
		],
	},
	{
		"title": "show_portrait.gd",
		"objective": "把新立绘淡入、旧立绘淡出",
		"lines": [
			"🎭 卸下当前角色的旧立绘",
			"🎭 加载新立绘的 PNG 资源",
			"🎭 把新立绘的 alpha 设为 0",
			"🎭 用 Tween 0.3 秒淡入到 1.0",
			"🎭 同步把表情参数广播给 live2d",
		],
	},
]

const BG_MAIN := Color("#1e1e2e")
const BG_TITLEBAR := Color("#11111b")
const BG_PANEL := Color("#181825")
const BG_ROW := Color("#313244")
const BG_ROW_HOVER := Color("#3b425b")
const BG_ROW_CORRECT := Color("#1f3a2e")
const BG_ROW_SELECTED := Color("#2c3257")
const BORDER_DEFAULT := Color("#45475a")
const BORDER_CORRECT := Color("#a6e3a1")
const BORDER_SELECTED := Color("#89b4fa")
const TEXT_TITLE := Color("#cdd6f4")
const TEXT_BODY := Color("#bac2de")
const TEXT_DIM := Color("#7f849c")
const ACCENT := Color("#89b4fa")
const SUCCESS := Color("#a6e3a1")
const WARNING := Color("#f9e2af")
const LINE_NUMBER_COLOR := Color("#585b70")

const FONT_SIZE_TITLE := 18
const FONT_SIZE_BODY := 20
const FONT_SIZE_CODE := 24
const FONT_SIZE_HINT := 17

var _rng := RandomNumberGenerator.new()
var _queue: Array[Dictionary] = []
var _queue_index: int = 0
var _per_puzzle_results: Array[Dictionary] = []
var _snippet: Dictionary = {}
var _target_lines: Array[String] = []
var _current_lines: Array[String] = []
var _moves: int = 0
var _elapsed: float = 0.0
var _puzzle_start_elapsed: float = 0.0
var _phase: String = "idle"
var _selected_index: int = -1
var _row_buttons: Array[Button] = []

var _root_panel: PanelContainer = null
var _timer_label: Label = null
var _title_label: Label = null
var _objective_label: Label = null
var _progress_label: Label = null
var _moves_label: Label = null
var _hint_label: Label = null
var _round_label: Label = null
var _lines_box: VBoxContainer = null


func _on_minigame_start() -> void:
	_rng.randomize()
	_queue = _pick_puzzle_queue()
	_queue_index = 0
	_per_puzzle_results.clear()
	_load_queue_entry(0)
	_build_ui()
	_refresh_board(true)
	_phase = "playing"
	set_process(true)


func _on_minigame_cleanup() -> void:
	_phase = "ended"
	set_process(false)


func _process(delta: float) -> void:
	if _phase != "playing":
		return
	_elapsed += delta
	if _timer_label != null and is_instance_valid(_timer_label):
		_timer_label.text = "%.1f s" % _elapsed


## 载入所有题目 + 随机选 PUZZLES_PER_RUN 题
func _pick_puzzle_queue() -> Array[Dictionary]:
	var pool: Array[Dictionary] = _load_puzzle_pool()
	if pool.is_empty():
		pool = FALLBACK_SNIPPETS.duplicate()

	pool.shuffle()
	var count: int = mini(PUZZLES_PER_RUN, pool.size())
	var result: Array[Dictionary] = []
	for i in range(count):
		result.append(pool[i])
	return result


## 从外部 JSON 加载题库
func _load_puzzle_pool() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(PUZZLE_JSON_PATH):
		push_warning("[code_puzzle] JSON 题库不存在，使用兜底题库：%s" % PUZZLE_JSON_PATH)
		return result
	var file := FileAccess.open(PUZZLE_JSON_PATH, FileAccess.READ)
	if file == null:
		push_warning("[code_puzzle] 打开 JSON 失败：%s" % PUZZLE_JSON_PATH)
		return result
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		push_warning("[code_puzzle] JSON 根节点不是 Dictionary")
		return result
	var raw_puzzles: Variant = (parsed as Dictionary).get("puzzles", [])
	if raw_puzzles is not Array:
		push_warning("[code_puzzle] JSON 缺 puzzles 字段")
		return result
	for raw in (raw_puzzles as Array):
		if raw is not Dictionary:
			continue
		var entry: Dictionary = raw
		var lines_raw: Variant = entry.get("lines", [])
		if lines_raw is not Array or (lines_raw as Array).is_empty():
			continue
		var lines: Array[String] = []
		for line in (lines_raw as Array):
			lines.append(str(line))
		result.append({
			"title": str(entry.get("title", entry.get("id", "untitled.gd"))),
			"objective": str(entry.get("objective", "恢复代码顺序")),
			"lines": lines,
		})
	return result


func _load_queue_entry(index: int) -> void:
	if _queue.is_empty() or index >= _queue.size():
		return
	_snippet = _queue[index]
	_target_lines = _copy_lines(_snippet.get("lines", []))
	_current_lines = _copy_lines(_snippet.get("lines", []))
	var attempts: int = 0
	while _same_order(_current_lines, _target_lines) and attempts < 12:
		_current_lines.shuffle()
		attempts += 1
	if _same_order(_current_lines, _target_lines) and _current_lines.size() >= 2:
		var first_line: String = _current_lines[0]
		_current_lines[0] = _current_lines[1]
		_current_lines[1] = first_line
	_moves = 0
	_selected_index = -1
	_puzzle_start_elapsed = _elapsed


func _copy_lines(source: Array) -> Array[String]:
	var result: Array[String] = []
	for line in source:
		result.append(str(line))
	return result


func _same_order(left: Array[String], right: Array[String]) -> bool:
	if left.size() != right.size():
		return false
	for i in range(left.size()):
		if left[i] != right[i]:
			return false
	return true


func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root_style := StyleBoxFlat.new()
	root_style.bg_color = BG_MAIN
	_root_panel.add_theme_stylebox_override("panel", root_style)
	add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	_root_panel.add_child(vbox)

	_build_title_bar(vbox)
	_build_main_content(vbox)
	_build_status_bar(vbox)


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

	for color in [Color("#f38ba8"), Color("#fab387"), Color("#a6e3a1")]:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = color
		hbox.add_child(dot)

	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer_left)

	var title := Label.new()
	title.text = "code_puzzle.gd — 步骤排一排"
	title.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", TEXT_BODY)
	hbox.add_child(title)

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer_right)

	_timer_label = Label.new()
	_timer_label.text = "0.0 s"
	_timer_label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE + 2)
	_timer_label.add_theme_color_override("font_color", ACCENT)
	hbox.add_child(_timer_label)


func _build_main_content(parent: VBoxContainer) -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(center)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(980, 0)
	content.add_theme_constant_override("separation", 18)
	center.add_child(content)

	var intro := PanelContainer.new()
	var intro_style := StyleBoxFlat.new()
	intro_style.bg_color = BG_PANEL
	intro_style.border_width_left = 1
	intro_style.border_width_top = 1
	intro_style.border_width_right = 1
	intro_style.border_width_bottom = 1
	intro_style.border_color = BORDER_DEFAULT
	intro_style.corner_radius_top_left = 12
	intro_style.corner_radius_top_right = 12
	intro_style.corner_radius_bottom_right = 12
	intro_style.corner_radius_bottom_left = 12
	intro_style.shadow_color = Color(0, 0, 0, 0.25)
	intro_style.shadow_size = 8
	intro_style.shadow_offset = Vector2(0, 4)
	intro_style.content_margin_left = 18
	intro_style.content_margin_right = 18
	intro_style.content_margin_top = 16
	intro_style.content_margin_bottom = 16
	intro.add_theme_stylebox_override("panel", intro_style)
	content.add_child(intro)

	var intro_box := VBoxContainer.new()
	intro_box.add_theme_constant_override("separation", 8)
	intro.add_child(intro_box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	intro_box.add_child(title_row)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", TEXT_TITLE)
	_title_label.text = str(_snippet.get("title", "untitled.gd"))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", FONT_SIZE_HINT)
	_round_label.add_theme_color_override("font_color", ACCENT)
	title_row.add_child(_round_label)

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	_objective_label.add_theme_color_override("font_color", TEXT_BODY)
	_objective_label.text = "// 目标：%s" % str(_snippet.get("objective", "恢复代码顺序"))
	intro_box.add_child(_objective_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", FONT_SIZE_HINT)
	_hint_label.add_theme_color_override("font_color", WARNING)
	_hint_label.text = "点击两行以交换它们的位置。排对的行会自动锁定。"
	intro_box.add_child(_hint_label)

	var lines_panel := PanelContainer.new()
	var lines_style := StyleBoxFlat.new()
	lines_style.bg_color = BG_PANEL
	lines_style.border_width_left = 1
	lines_style.border_width_top = 1
	lines_style.border_width_right = 1
	lines_style.border_width_bottom = 1
	lines_style.border_color = BORDER_DEFAULT
	lines_style.corner_radius_top_left = 14
	lines_style.corner_radius_top_right = 14
	lines_style.corner_radius_bottom_right = 14
	lines_style.corner_radius_bottom_left = 14
	lines_style.shadow_color = Color(0, 0, 0, 0.3)
	lines_style.shadow_size = 12
	lines_style.shadow_offset = Vector2(0, 8)
	lines_style.content_margin_left = 20
	lines_style.content_margin_right = 20
	lines_style.content_margin_top = 20
	lines_style.content_margin_bottom = 20
	lines_panel.add_theme_stylebox_override("panel", lines_style)
	content.add_child(lines_panel)

	_lines_box = VBoxContainer.new()
	_lines_box.add_theme_constant_override("separation", 10)
	lines_panel.add_child(_lines_box)


func _build_status_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_TITLEBAR
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 32)
	bar.add_child(hbox)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", FONT_SIZE_HINT)
	_progress_label.add_theme_color_override("font_color", SUCCESS)
	hbox.add_child(_progress_label)

	_moves_label = Label.new()
	_moves_label.add_theme_font_size_override("font_size", FONT_SIZE_HINT)
	_moves_label.add_theme_color_override("font_color", TEXT_BODY)
	hbox.add_child(_moves_label)

	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(filler)

	var help := Label.new()
	help.add_theme_font_size_override("font_size", FONT_SIZE_HINT - 1)
	help.add_theme_color_override("font_color", TEXT_DIM)
	help.text = "差双换法 · 锁定的行不再参与交换"
	hbox.add_child(help)


func _refresh_board(animate_in: bool = false) -> void:
	if _lines_box == null or not is_instance_valid(_lines_box):
		return
	for child in _lines_box.get_children():
		child.queue_free()
	_row_buttons.clear()

	var correct_count := _count_correct_lines()
	for i in range(_current_lines.size()):
		var row := _build_line_row(i)
		_lines_box.add_child(row)
		_row_buttons.append(row)
		if animate_in:
			row.modulate.a = 0.0
			var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(row, "modulate:a", 1.0, 0.4).set_delay(i * 0.08)

	if _progress_label != null and is_instance_valid(_progress_label):
		_progress_label.text = "已排好 %d / %d" % [correct_count, _target_lines.size()]
	if _moves_label != null and is_instance_valid(_moves_label):
		_moves_label.text = "交换次数 %d" % _moves
	if _round_label != null and is_instance_valid(_round_label):
		_round_label.text = "第 %d / %d 题" % [_queue_index + 1, maxi(1, _queue.size())]
	if _title_label != null and is_instance_valid(_title_label):
		_title_label.text = str(_snippet.get("title", "untitled.gd"))
	if _objective_label != null and is_instance_valid(_objective_label):
		_objective_label.text = "// 目标：%s" % str(_snippet.get("objective", "恢复代码顺序"))
	if _hint_label != null and is_instance_valid(_hint_label):
		if _selected_index >= 0:
			_hint_label.text = "已选中第 %02d 行，再点另一行完成交换（再次点击取消）" % (_selected_index + 1)
			_hint_label.add_theme_color_override("font_color", ACCENT)
		else:
			_hint_label.text = "点击两行以交换它们的位置。排对的行会自动锁定。"
			_hint_label.add_theme_color_override("font_color", WARNING)

	if correct_count == _target_lines.size():
		_finish_current_puzzle()


func _build_line_row(index: int) -> Button:
	var is_correct: bool = _current_lines[index] == _target_lines[index]
	var is_selected: bool = _selected_index == index

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 64)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = ""
	button.disabled = is_correct
	if not is_correct:
		button.pressed.connect(_on_row_clicked.bind(index))

	var bg_color: Color = BG_ROW
	var border_color: Color = BORDER_DEFAULT
	var border_width: int = 1
	if is_correct:
		bg_color = BG_ROW_CORRECT
		border_color = BORDER_CORRECT
		border_width = 1
	elif is_selected:
		bg_color = BG_ROW_SELECTED
		border_color = BORDER_SELECTED
		border_width = 2

	_apply_row_stylebox(button, "normal", bg_color, border_color, border_width)
	_apply_row_stylebox(button, "disabled", bg_color, border_color, border_width)
	if not is_correct:
		_apply_row_stylebox(button, "hover", BG_ROW_HOVER if not is_selected else BG_ROW_SELECTED, border_color if is_selected else ACCENT, maxi(border_width, 1))
		_apply_row_stylebox(button, "pressed", BG_ROW_SELECTED, BORDER_SELECTED, 2)
	button.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))

	var overlay := MarginContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_theme_constant_override("margin_left", 14)
	overlay.add_theme_constant_override("margin_right", 14)
	overlay.add_theme_constant_override("margin_top", 10)
	overlay.add_theme_constant_override("margin_bottom", 10)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(overlay)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hbox)

	var number := Label.new()
	number.custom_minimum_size = Vector2(44, 0)
	number.text = "%02d" % (index + 1)
	number.add_theme_font_size_override("font_size", 18)
	number.add_theme_color_override("font_color", SUCCESS if is_correct else (ACCENT if is_selected else LINE_NUMBER_COLOR))
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(number)

	var code := Label.new()
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.text = _current_lines[index]
	code.add_theme_font_size_override("font_size", FONT_SIZE_CODE)
	code.add_theme_color_override("font_color", TEXT_TITLE if (is_correct or is_selected) else TEXT_BODY)
	code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(code)

	var marker := Label.new()
	marker.custom_minimum_size = Vector2(32, 0)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	marker.add_theme_font_size_override("font_size", 18)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_correct:
		marker.text = "✓"
		marker.add_theme_color_override("font_color", SUCCESS)
	elif is_selected:
		marker.text = "⇅"
		marker.add_theme_color_override("font_color", ACCENT)
	else:
		marker.text = "⋮⋮"
		marker.add_theme_color_override("font_color", TEXT_DIM)
	hbox.add_child(marker)

	return button


func _apply_row_stylebox(button: Button, state: String, bg: Color, border: Color, border_width: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.border_color = border
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.2)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	button.add_theme_stylebox_override(state, sb)


func _on_row_clicked(index: int) -> void:
	if _phase != "playing":
		return
	if index < 0 or index >= _current_lines.size():
		return
	if _current_lines[index] == _target_lines[index]:
		return  # 已锁定

	if _selected_index == -1:
		_selected_index = index
		_refresh_board()
		return

	if _selected_index == index:
		_selected_index = -1
		_refresh_board()
		return

	var a: int = _selected_index
	var b: int = index
	var tmp: String = _current_lines[a]
	_current_lines[a] = _current_lines[b]
	_current_lines[b] = tmp
	_moves += 1
	_selected_index = -1
	_refresh_board()


func _count_correct_lines() -> int:
	var correct_count: int = 0
	for i in range(mini(_current_lines.size(), _target_lines.size())):
		if _current_lines[i] == _target_lines[i]:
			correct_count += 1
	return correct_count


func _finish_current_puzzle() -> void:
	if _phase != "playing":
		return
	var puzzle_elapsed: float = maxf(_elapsed - _puzzle_start_elapsed, 0.0)
	var line_count: int = maxi(_target_lines.size(), 1)
	var expected_moves: int = maxi(line_count - 1, 1)
	var move_efficiency: float = clampf(float(expected_moves) / maxf(float(_moves), float(expected_moves)), 0.45, 1.0)
	var pace_window: float = 14.0 + float(line_count) * 4.5
	var pace: float = clampf(1.0 - puzzle_elapsed / pace_window, 0.3, 1.0)
	var puzzle_score: float = clampf(0.55 + move_efficiency * 0.25 + pace * 0.20, 0.0, 1.0)
	_per_puzzle_results.append({
		"title": str(_snippet.get("title", "")),
		"score": puzzle_score,
		"moves": _moves,
		"elapsed": snappedf(puzzle_elapsed, 0.01),
		"lines": line_count,
	})

	# 推进下一题或结算
	_queue_index += 1
	if _queue_index < _queue.size():
		_phase = "transition"
		_load_queue_entry(_queue_index)
		# 给一点小节奏感，让玩家看到刚排好的题
		await get_tree().create_timer(0.6).timeout
		if not _running:
			return
		_phase = "playing"
		_refresh_board(true)
	else:
		_finish_all_puzzles()


func _finish_all_puzzles() -> void:
	_phase = "ended"
	set_process(false)

	var total_score: float = 0.0
	var total_moves: int = 0
	for entry in _per_puzzle_results:
		total_score += float(entry.get("score", 0.0))
		total_moves += int(entry.get("moves", 0))
	var puzzle_count: int = maxi(_per_puzzle_results.size(), 1)
	var avg_score: float = total_score / float(puzzle_count)

	var result: Dictionary = {
		"score": avg_score,
		"moves": total_moves,
		"elapsed": snappedf(_elapsed, 0.01),
		"puzzle_count": puzzle_count,
		"puzzle_results": _per_puzzle_results.duplicate(true),
	}

	var stats: Array[String] = []
	stats.append("连续搞定 %d / %d 题" % [puzzle_count, maxi(_queue.size(), puzzle_count)])
	stats.append("总计交换 %d 次 · 用时 %.1f 秒" % [total_moves, _elapsed])
	var titles: PackedStringArray = []
	for entry in _per_puzzle_results:
		var t: String = str(entry.get("title", "")).strip_edges()
		if not t.is_empty():
			titles.append(t)
	if titles.size() > 0:
		stats.append("已提交：%s" % ", ".join(titles))

	present_summary_and_finish({
		"title": "代码排序完成",
		"subtitle": "把今天的 %d 段流程都理顺了" % puzzle_count,
		"stats": stats,
		"button_text": "把改动 push 上去",
		"result": result,
	})
