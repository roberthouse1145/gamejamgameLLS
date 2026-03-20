class_name Game2048
extends Control

signal score_changed(current_score: int, best_score: int)
signal stats_changed

const GRID_SIZE: int = 4
const TARGET_VALUE: int = 2048
const ANIM_DURATION: float = 0.1
const SPAWN_DURATION: float = 0.12
const MERGE_BUMP_SCALE: float = 1.15

const COLOR_BG := Color("#FAF8EF")
const COLOR_BOARD := Color("#BBADA0")
const COLOR_EMPTY := Color("#CDC1B4")
const COLOR_TEXT_DARK := Color("#776E65")
const COLOR_TEXT_LIGHT := Color("#F9F6F2")

var _board: Array = []
var _prev_board: Array = []
var _tile_panels: Array[PanelContainer] = []
var _tile_labels: Array[Label] = []

var _score: int = 0
var _best_score: int = 0
var _won_announced: bool = false
var _game_over: bool = false
var _animating: bool = false
var _max_tile: int = 0
var _move_count: int = 0

var _score_label: Label = null
var _best_label: Label = null
var _status_label: Label = null
var _score_add_label: Label = null
var _game_over_overlay: Control = null
var _game_over_score_label: Label = null
var _game_over_max_label: Label = null
var _game_over_moves_label: Label = null
var _board_shell: PanelContainer = null


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_new_game()
	call_deferred("grab_focus")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _animating:
		return

	match key_event.keycode:
		KEY_LEFT, KEY_A:
			_attempt_move("left")
		KEY_RIGHT, KEY_D:
			_attempt_move("right")
		KEY_UP, KEY_W:
			_attempt_move("up")
		KEY_DOWN, KEY_S:
			_attempt_move("down")
		KEY_R:
			_new_game()
		_:
			return
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	# ── Header ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 4)
	header.add_child(title_box)

	var title := Label.new()
	title.text = "2048"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "方向键或 WASD 合并数字，R 重新开始"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#8F7A66"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(subtitle)

	var stat_box := HBoxContainer.new()
	stat_box.add_theme_constant_override("separation", 10)
	header.add_child(stat_box)

	_score_label = _create_stat_card(stat_box, "SCORE")
	_best_label = _create_stat_card(stat_box, "BEST")

	# ── Controls row ──
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	root.add_child(controls)

	_status_label = Label.new()
	_status_label.text = "拼到 2048 也可以继续玩"
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color("#8F7A66"))
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_status_label)

	var new_game_button := Button.new()
	new_game_button.text = "新的一局"
	new_game_button.custom_minimum_size = Vector2(112, 40)
	new_game_button.add_theme_font_size_override("font_size", 15)
	_apply_button_style(new_game_button)
	new_game_button.pressed.connect(_new_game)
	controls.add_child(new_game_button)

	# ── Board ──
	_board_shell = PanelContainer.new()
	_board_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_shell.custom_minimum_size = Vector2(420, 420)
	_board_shell.add_theme_stylebox_override("panel", _make_panel_style(COLOR_BOARD, 12))
	root.add_child(_board_shell)

	var board_margin := MarginContainer.new()
	board_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_margin.add_theme_constant_override("margin_left", 12)
	board_margin.add_theme_constant_override("margin_top", 12)
	board_margin.add_theme_constant_override("margin_right", 12)
	board_margin.add_theme_constant_override("margin_bottom", 12)
	_board_shell.add_child(board_margin)

	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_margin.add_child(aspect)

	var board_root := Control.new()
	board_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aspect.add_child(board_root)

	var grid := GridContainer.new()
	grid.columns = GRID_SIZE
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	board_root.add_child(grid)

	for _row in range(GRID_SIZE):
		for _column in range(GRID_SIZE):
			var tile := PanelContainer.new()
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tile.custom_minimum_size = Vector2(88, 88)
			tile.add_theme_stylebox_override("panel", _make_panel_style(COLOR_EMPTY, 8))
			tile.pivot_offset = Vector2(44, 44)
			grid.add_child(tile)

			var label := Label.new()
			label.text = ""
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.add_theme_font_size_override("font_size", 30)
			tile.add_child(label)

			_tile_panels.append(tile)
			_tile_labels.append(label)

	# ── Score add floating label (reused) ──
	_score_add_label = Label.new()
	_score_add_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_add_label.add_theme_font_size_override("font_size", 18)
	_score_add_label.add_theme_color_override("font_color", Color("#776E65"))
	_score_add_label.modulate.a = 0.0
	_score_add_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score_add_label)


func _create_stat_card(parent: Control, title: String) -> Label:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(96, 72)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color("#BBADA0"), 8))
	parent.add_child(card)

	var content := MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 10)
	content.add_theme_constant_override("margin_top", 8)
	content.add_theme_constant_override("margin_right", 10)
	content.add_theme_constant_override("margin_bottom", 8)
	card.add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	content.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color("#EEE4DA"))
	box.add_child(title_label)

	var value_label := Label.new()
	value_label.text = "0"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	box.add_child(value_label)
	return value_label


func _apply_button_style(button: Button) -> void:
	var normal := _make_panel_style(Color("#8F7A66"), 8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", normal)
	var hover := _make_panel_style(Color("#9F8B77"), 8)
	hover.content_margin_left = 14
	hover.content_margin_right = 14
	hover.content_margin_top = 10
	hover.content_margin_bottom = 10
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_LIGHT)


func _make_panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _new_game() -> void:
	_hide_game_over_overlay()
	_board.clear()
	for _y in range(GRID_SIZE):
		var row: Array = []
		for _x in range(GRID_SIZE):
			row.append(0)
		_board.append(row)
	_score = 0
	_game_over = false
	_won_announced = false
	_animating = false
	_max_tile = 0
	_move_count = 0
	_spawn_tile()
	_spawn_tile()
	_update_view()
	_set_status("拼到 2048 也可以继续玩")
	score_changed.emit(_score, _best_score)
	stats_changed.emit()


func _attempt_move(direction: String) -> void:
	if _game_over:
		return
	_save_prev_board()
	var result := _move_board(direction)
	if not bool(result.get("moved", false)):
		return

	var gain: int = int(result.get("score_gain", 0))
	_score += gain
	_best_score = maxi(_best_score, _score)
	_move_count += 1
	_spawn_tile()
	_update_max_tile()
	_update_view()
	score_changed.emit(_score, _best_score)
	stats_changed.emit()

	# 得分浮动动画
	if gain > 0:
		_show_score_popup(gain)

	# 合并动画：对发生变化的格子做 bump
	_play_merge_animations()

	if _has_tile(TARGET_VALUE) and not _won_announced:
		_won_announced = true
		_set_status("🎉 你拼出了 2048！可以继续冲更高分")
	elif not _can_move():
		_game_over = true
		_set_status("游戏结束")
		_show_game_over_overlay()
	else:
		if _score >= 500 and not _won_announced:
			_set_status("势头不错，继续合并吧")
		else:
			_set_status("继续合并更大的数字吧")


func _save_prev_board() -> void:
	_prev_board.clear()
	for row in _board:
		_prev_board.append(row.duplicate())


func _update_max_tile() -> void:
	for row in _board:
		for val in row:
			if int(val) > _max_tile:
				_max_tile = int(val)


func _play_merge_animations() -> void:
	_animating = true
	var has_any: bool = false
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cur: int = int(_board[row][col])
			var prev: int = int(_prev_board[row][col]) if row < _prev_board.size() and col < _prev_board[row].size() else 0
			var idx: int = row * GRID_SIZE + col
			var panel := _tile_panels[idx]
			if cur != prev and cur != 0:
				has_any = true
				# bump scale animation
				var tween := create_tween()
				tween.tween_property(panel, "scale", Vector2(MERGE_BUMP_SCALE, MERGE_BUMP_SCALE), ANIM_DURATION * 0.5)
				tween.tween_property(panel, "scale", Vector2.ONE, ANIM_DURATION * 0.5)
			elif cur == 0 and prev != 0:
				# tile disappeared — no animation needed
				pass
	# New tile spawn animation
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cur: int = int(_board[row][col])
			var prev: int = int(_prev_board[row][col]) if row < _prev_board.size() and col < _prev_board[row].size() else 0
			if cur != 0 and prev == 0:
				var idx: int = row * GRID_SIZE + col
				var panel := _tile_panels[idx]
				has_any = true
				panel.scale = Vector2(0.0, 0.0)
				var tween := create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_BACK)
				tween.tween_property(panel, "scale", Vector2.ONE, SPAWN_DURATION)

	# Unlock input after animations
	if has_any:
		get_tree().create_timer(SPAWN_DURATION + 0.02).timeout.connect(func() -> void: _animating = false)
	else:
		_animating = false


func _show_score_popup(gain: int) -> void:
	if _score_add_label == null:
		return
	_score_add_label.text = "+%d" % gain
	_score_add_label.modulate.a = 1.0
	_score_add_label.position = Vector2(size.x * 0.5 - 30, 60)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_score_add_label, "position:y", 30.0, 0.5)
	tween.tween_property(_score_add_label, "modulate:a", 0.0, 0.5)


func _show_game_over_overlay() -> void:
	if _board_shell == null:
		return
	_hide_game_over_overlay()

	_game_over_overlay = Control.new()
	_game_over_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_shell.add_child(_game_over_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.98, 0.97, 0.94, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.add_child(dim)

	# Fade in the dim
	var dim_tween := create_tween()
	dim_tween.tween_property(dim, "color:a", 0.7, 0.4)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 12)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_overlay.add_child(center)

	var go_title := Label.new()
	go_title.text = "Game Over"
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_title.add_theme_font_size_override("font_size", 40)
	go_title.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	center.add_child(go_title)

	_game_over_score_label = Label.new()
	_game_over_score_label.text = "得分：%d" % _score
	_game_over_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_score_label.add_theme_font_size_override("font_size", 22)
	_game_over_score_label.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	center.add_child(_game_over_score_label)

	_game_over_max_label = Label.new()
	_game_over_max_label.text = "最大方块：%d" % _max_tile
	_game_over_max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_max_label.add_theme_font_size_override("font_size", 16)
	_game_over_max_label.add_theme_color_override("font_color", Color("#8F7A66"))
	center.add_child(_game_over_max_label)

	_game_over_moves_label = Label.new()
	_game_over_moves_label.text = "步数：%d" % _move_count
	_game_over_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_moves_label.add_theme_font_size_override("font_size", 16)
	_game_over_moves_label.add_theme_color_override("font_color", Color("#8F7A66"))
	center.add_child(_game_over_moves_label)

	var retry_btn := Button.new()
	retry_btn.text = "再来一局"
	retry_btn.custom_minimum_size = Vector2(140, 44)
	retry_btn.add_theme_font_size_override("font_size", 16)
	_apply_button_style(retry_btn)
	retry_btn.pressed.connect(_new_game)
	center.add_child(retry_btn)

	# Fade in the whole overlay content
	center.modulate.a = 0.0
	var content_tween := create_tween()
	content_tween.tween_interval(0.2)
	content_tween.tween_property(center, "modulate:a", 1.0, 0.3)


func _hide_game_over_overlay() -> void:
	if _game_over_overlay != null and is_instance_valid(_game_over_overlay):
		_game_over_overlay.queue_free()
	_game_over_overlay = null
	_game_over_score_label = null
	_game_over_max_label = null
	_game_over_moves_label = null


func _move_board(direction: String) -> Dictionary:
	var moved: bool = false
	var score_gain: int = 0
	match direction:
		"left":
			for row_index in range(GRID_SIZE):
				var line: Array = _board[row_index].duplicate()
				var result := _collapse_line(line)
				if bool(result.get("moved", false)):
					moved = true
				score_gain += int(result.get("score_gain", 0))
				_board[row_index] = result.get("line", []).duplicate()
		"right":
			for row_index in range(GRID_SIZE):
				var reversed_line: Array = _board[row_index].duplicate()
				reversed_line.reverse()
				var result := _collapse_line(reversed_line)
				var next_line: Array = result.get("line", []).duplicate()
				next_line.reverse()
				if next_line != _board[row_index]:
					moved = true
				score_gain += int(result.get("score_gain", 0))
				_board[row_index] = next_line
		"up":
			for column in range(GRID_SIZE):
				var line: Array = _get_column(column)
				var result := _collapse_line(line)
				if bool(result.get("moved", false)):
					moved = true
				score_gain += int(result.get("score_gain", 0))
				_set_column(column, result.get("line", []).duplicate())
		"down":
			for column in range(GRID_SIZE):
				var reversed_line: Array = _get_column(column)
				reversed_line.reverse()
				var result := _collapse_line(reversed_line)
				var next_line: Array = result.get("line", []).duplicate()
				next_line.reverse()
				if next_line != _get_column(column):
					moved = true
				score_gain += int(result.get("score_gain", 0))
				_set_column(column, next_line)
	return {"moved": moved, "score_gain": score_gain}


func _collapse_line(line: Array) -> Dictionary:
	var original: Array = line.duplicate()
	var compact: Array = []
	for value in line:
		if int(value) != 0:
			compact.append(int(value))
	var merged: Array = []
	var score_gain: int = 0
	var index: int = 0
	while index < compact.size():
		var value: int = int(compact[index])
		if index + 1 < compact.size() and int(compact[index + 1]) == value:
			value *= 2
			score_gain += value
			index += 2
		else:
			index += 1
		merged.append(value)
	while merged.size() < GRID_SIZE:
		merged.append(0)
	return {"line": merged, "score_gain": score_gain, "moved": merged != original}


func _get_column(column: int) -> Array:
	var result: Array = []
	for row in range(GRID_SIZE):
		result.append(int(_board[row][column]))
	return result


func _set_column(column: int, values: Array) -> void:
	for row in range(GRID_SIZE):
		_board[row][column] = int(values[row])


func _spawn_tile() -> void:
	var empties: Array[Vector2i] = []
	for row in range(GRID_SIZE):
		for column in range(GRID_SIZE):
			if int(_board[row][column]) == 0:
				empties.append(Vector2i(column, row))
	if empties.is_empty():
		return
	var slot: Vector2i = empties[randi_range(0, empties.size() - 1)]
	_board[slot.y][slot.x] = 4 if randf() < 0.1 else 2


func _can_move() -> bool:
	for row in range(GRID_SIZE):
		for column in range(GRID_SIZE):
			var value: int = int(_board[row][column])
			if value == 0:
				return true
			if column + 1 < GRID_SIZE and int(_board[row][column + 1]) == value:
				return true
			if row + 1 < GRID_SIZE and int(_board[row + 1][column]) == value:
				return true
	return false


func _has_tile(target: int) -> bool:
	for row in _board:
		for value in row:
			if int(value) == target:
				return true
	return false


func _update_view() -> void:
	if _score_label != null:
		_score_label.text = str(_score)
	if _best_label != null:
		_best_label.text = str(_best_score)
	for row in range(GRID_SIZE):
		for column in range(GRID_SIZE):
			var value: int = int(_board[row][column])
			var flat_index: int = row * GRID_SIZE + column
			var panel := _tile_panels[flat_index]
			var label := _tile_labels[flat_index]
			var colors := _get_tile_colors(value)
			panel.add_theme_stylebox_override("panel", _make_panel_style(colors.get("bg", COLOR_EMPTY), 8))
			label.text = "" if value == 0 else str(value)
			label.add_theme_color_override("font_color", colors.get("fg", COLOR_TEXT_DARK))
			label.add_theme_font_size_override("font_size", _font_size_for_value(value))


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _font_size_for_value(value: int) -> int:
	if value >= 1024:
		return 24
	if value >= 128:
		return 28
	return 32


func _get_tile_colors(value: int) -> Dictionary:
	match value:
		0:
			return {"bg": COLOR_EMPTY, "fg": Color(0, 0, 0, 0)}
		2:
			return {"bg": Color("#EEE4DA"), "fg": COLOR_TEXT_DARK}
		4:
			return {"bg": Color("#EDE0C8"), "fg": COLOR_TEXT_DARK}
		8:
			return {"bg": Color("#F2B179"), "fg": COLOR_TEXT_LIGHT}
		16:
			return {"bg": Color("#F59563"), "fg": COLOR_TEXT_LIGHT}
		32:
			return {"bg": Color("#F67C5F"), "fg": COLOR_TEXT_LIGHT}
		64:
			return {"bg": Color("#F65E3B"), "fg": COLOR_TEXT_LIGHT}
		128:
			return {"bg": Color("#EDCF72"), "fg": COLOR_TEXT_LIGHT}
		256:
			return {"bg": Color("#EDCC61"), "fg": COLOR_TEXT_LIGHT}
		512:
			return {"bg": Color("#EDC850"), "fg": COLOR_TEXT_LIGHT}
		1024:
			return {"bg": Color("#EDC53F"), "fg": COLOR_TEXT_LIGHT}
		2048:
			return {"bg": Color("#EDC22E"), "fg": COLOR_TEXT_LIGHT}
		_:
			return {"bg": Color("#3C3A32"), "fg": COLOR_TEXT_LIGHT}


## Generic stats interface for Sbeam integration
func get_stats() -> Array[Dictionary]:
	return [
		{"label": "当前得分", "value": str(_score)},
		{"label": "最高得分", "value": str(_best_score)},
		{"label": "最大方块", "value": str(_max_tile) if _max_tile > 0 else "-"},
		{"label": "步数", "value": str(_move_count)},
	]


## Restore best score from persisted data
func restore_best_score(value: int) -> void:
	if value > _best_score:
		_best_score = value
		if _best_label != null:
			_best_label.text = str(_best_score)
