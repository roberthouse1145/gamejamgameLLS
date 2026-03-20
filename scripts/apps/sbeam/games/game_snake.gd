class_name GameSnake
extends Control

signal stats_changed

const CELL_SIZE: int = 20
const GRID_W: int = 20
const GRID_H: int = 20
const TICK_FAST: float = 0.08
const TICK_NORMAL: float = 0.12
const TICK_START: float = 0.15

const COLOR_BG := Color("#1a1a2e")
const COLOR_GRID := Color("#16213e")
const COLOR_SNAKE_HEAD := Color("#e94560")
const COLOR_SNAKE_BODY := Color("#0f3460")
const COLOR_FOOD := Color("#e9b872")
const COLOR_TEXT := Color("#eaeaea")
const COLOR_DIM := Color("#8a8a8a")

var _snake: Array[Vector2i] = []
var _direction: Vector2i = Vector2i.RIGHT
var _next_direction: Vector2i = Vector2i.RIGHT
var _food: Vector2i = Vector2i(-1, -1)
var _score: int = 0
var _best_score: int = 0
var _alive: bool = false
var _started: bool = false
var _tick_interval: float = TICK_START
var _tick_timer: float = 0.0
var _total_foods: int = 0

var _score_label: Label = null
var _best_label: Label = null
var _status_label: Label = null
var _board: Control = null
var _game_over_overlay: Control = null


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_reset_game()
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

	if not _alive and _started:
		if key_event.keycode == KEY_R:
			_reset_game()
			get_viewport().set_input_as_handled()
		return

	match key_event.keycode:
		KEY_LEFT, KEY_A:
			if _direction != Vector2i.RIGHT:
				_next_direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D:
			if _direction != Vector2i.LEFT:
				_next_direction = Vector2i.RIGHT
		KEY_UP, KEY_W:
			if _direction != Vector2i.DOWN:
				_next_direction = Vector2i.UP
		KEY_DOWN, KEY_S:
			if _direction != Vector2i.UP:
				_next_direction = Vector2i.DOWN
		KEY_R:
			_reset_game()
		_:
			return
	if not _started:
		_started = true
		_alive = true
		_set_status("吃到食物会加速")
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _alive or not _started:
		return
	_tick_timer += delta
	if _tick_timer >= _tick_interval:
		_tick_timer = 0.0
		_step()
		_board.queue_redraw()


func _step() -> void:
	_direction = _next_direction
	var head: Vector2i = _snake[0] + _direction
	# 穿墙
	head.x = posmod(head.x, GRID_W)
	head.y = posmod(head.y, GRID_H)

	# 撞自己
	if _snake.has(head):
		_die()
		return

	_snake.push_front(head)
	if head == _food:
		_score += 10
		_total_foods += 1
		_best_score = maxi(_best_score, _score)
		_tick_interval = maxf(TICK_FAST, _tick_interval - 0.004)
		_spawn_food()
		_update_labels()
		stats_changed.emit()
	else:
		_snake.pop_back()


func _die() -> void:
	_alive = false
	_best_score = maxi(_best_score, _score)
	_set_status("Game Over · R 重新开始")
	_show_game_over()
	stats_changed.emit()


func _reset_game() -> void:
	_hide_game_over()
	_snake.clear()
	var cx: int = GRID_W >> 1
	var cy: int = GRID_H >> 1
	for i in range(3):
		_snake.append(Vector2i(cx - i, cy))
	_direction = Vector2i.RIGHT
	_next_direction = Vector2i.RIGHT
	_score = 0
	_alive = false
	_started = false
	_tick_interval = TICK_START
	_tick_timer = 0.0
	_total_foods = 0
	_spawn_food()
	_update_labels()
	_set_status("方向键或 WASD 开始")
	if _board != null:
		_board.queue_redraw()
	stats_changed.emit()


func _spawn_food() -> void:
	var empties: Array[Vector2i] = []
	for x in range(GRID_W):
		for y in range(GRID_H):
			var cell := Vector2i(x, y)
			if not _snake.has(cell):
				empties.append(cell)
	if empties.is_empty():
		return
	_food = empties[randi_range(0, empties.size() - 1)]


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
	root.add_theme_constant_override("separation", 14)
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
	title.text = "贪吃蛇"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "方向键或 WASD 控制，R 重新开始"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", COLOR_DIM)
	title_box.add_child(subtitle)

	var stat_box := HBoxContainer.new()
	stat_box.add_theme_constant_override("separation", 10)
	header.add_child(stat_box)

	_score_label = _create_stat_card(stat_box, "SCORE")
	_best_label = _create_stat_card(stat_box, "BEST")

	# ── Status ──
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	root.add_child(controls)

	_status_label = Label.new()
	_status_label.text = "方向键或 WASD 开始"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", COLOR_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_status_label)

	var new_game_btn := Button.new()
	new_game_btn.text = "新的一局"
	new_game_btn.custom_minimum_size = Vector2(112, 38)
	new_game_btn.add_theme_font_size_override("font_size", 14)
	_apply_button_style(new_game_btn)
	new_game_btn.pressed.connect(_reset_game)
	controls.add_child(new_game_btn)

	# ── Board ──
	var board_wrapper := PanelContainer.new()
	board_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_wrapper.custom_minimum_size = Vector2(GRID_W * CELL_SIZE + 4, GRID_H * CELL_SIZE + 4)
	board_wrapper.add_theme_stylebox_override("panel", _make_panel_style(COLOR_GRID, 8))
	root.add_child(board_wrapper)

	var board_center := CenterContainer.new()
	board_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_wrapper.add_child(board_center)

	_board = Control.new()
	_board.custom_minimum_size = Vector2(GRID_W * CELL_SIZE, GRID_H * CELL_SIZE)
	_board.draw.connect(_draw_board)
	board_center.add_child(_board)


func _draw_board() -> void:
	# 背景网格
	for x in range(GRID_W):
		for y in range(GRID_H):
			var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var c: Color = COLOR_GRID.lightened(0.03) if (x + y) % 2 == 0 else COLOR_GRID
			_board.draw_rect(rect, c)

	# 食物
	if _food.x >= 0:
		var food_rect := Rect2(Vector2(_food.x * CELL_SIZE + 2, _food.y * CELL_SIZE + 2), Vector2(CELL_SIZE - 4, CELL_SIZE - 4))
		_board.draw_rect(food_rect, COLOR_FOOD)

	# 蛇身
	for i in range(_snake.size()):
		var seg: Vector2i = _snake[i]
		var gap: int = 1 if i > 0 else 0
		var seg_rect := Rect2(
			Vector2(seg.x * CELL_SIZE + gap, seg.y * CELL_SIZE + gap),
			Vector2(CELL_SIZE - gap * 2, CELL_SIZE - gap * 2)
		)
		var color: Color = COLOR_SNAKE_HEAD if i == 0 else COLOR_SNAKE_BODY.lerp(COLOR_SNAKE_HEAD, 0.15 * maxf(0.0, 1.0 - float(i) / 8.0))
		_board.draw_rect(seg_rect, color)


func _show_game_over() -> void:
	if _board == null:
		return
	_hide_game_over()

	_game_over_overlay = Control.new()
	_game_over_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.add_child(_game_over_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.18, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.add_child(dim)

	var tween := create_tween()
	tween.tween_property(dim, "color:a", 0.75, 0.35)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_overlay.add_child(center)

	var go_title := Label.new()
	go_title.text = "Game Over"
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_title.add_theme_font_size_override("font_size", 36)
	go_title.add_theme_color_override("font_color", COLOR_TEXT)
	center.add_child(go_title)

	var score_lbl := Label.new()
	score_lbl.text = "得分：%d" % _score
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 20)
	score_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	center.add_child(score_lbl)

	var food_lbl := Label.new()
	food_lbl.text = "吃到：%d 个" % _total_foods
	food_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	food_lbl.add_theme_font_size_override("font_size", 15)
	food_lbl.add_theme_color_override("font_color", COLOR_DIM)
	center.add_child(food_lbl)

	var retry_btn := Button.new()
	retry_btn.text = "再来一局"
	retry_btn.custom_minimum_size = Vector2(130, 40)
	retry_btn.add_theme_font_size_override("font_size", 15)
	_apply_button_style(retry_btn)
	retry_btn.pressed.connect(_reset_game)
	center.add_child(retry_btn)

	center.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_interval(0.15)
	fade.tween_property(center, "modulate:a", 1.0, 0.25)


func _hide_game_over() -> void:
	if _game_over_overlay != null and is_instance_valid(_game_over_overlay):
		_game_over_overlay.queue_free()
	_game_over_overlay = null


func _update_labels() -> void:
	if _score_label != null:
		_score_label.text = str(_score)
	if _best_label != null:
		_best_label.text = str(_best_score)


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _create_stat_card(parent: Control, title: String) -> Label:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(90, 64)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color("#0f3460"), 8))
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
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", COLOR_DIM)
	box.add_child(title_label)

	var value_label := Label.new()
	value_label.text = "0"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(value_label)
	return value_label


func _apply_button_style(button: Button) -> void:
	var normal := _make_panel_style(Color("#e94560"), 8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal)
	var hover := _make_panel_style(Color("#ff6b81"), 8)
	hover.content_margin_left = 14
	hover.content_margin_right = 14
	hover.content_margin_top = 8
	hover.content_margin_bottom = 8
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))


func _make_panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


## Generic stats interface for Sbeam integration
func get_stats() -> Array[Dictionary]:
	return [
		{"label": "当前得分", "value": str(_score)},
		{"label": "最高得分", "value": str(_best_score)},
		{"label": "吃到食物", "value": str(_total_foods)},
	]


## Restore best score from persisted data
func restore_best_score(value: int) -> void:
	if value > _best_score:
		_best_score = value
		if _best_label != null:
			_best_label.text = str(_best_score)
