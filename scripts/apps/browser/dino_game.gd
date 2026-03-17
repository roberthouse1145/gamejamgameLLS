class_name DinoGame
extends Control
## 浏览器加载等待小游戏 — 类似 Chrome 离线恐龙跑酷
## 空格/点击跳跃，躲避障碍物，纯装饰不影响数值

const GROUND_Y: float = 0.75       # 地面位置（相对高度）
const DINO_SIZE: Vector2 = Vector2(32, 40)
const OBSTACLE_W: float = 20.0
const OBSTACLE_MIN_H: float = 28.0
const OBSTACLE_MAX_H: float = 52.0
const GRAVITY: float = 1400.0
const JUMP_VEL: float = -520.0
const BASE_SPEED: float = 280.0
const SPEED_ACCEL: float = 8.0
const SPAWN_MIN: float = 0.9
const SPAWN_MAX: float = 2.2

var _running: bool = false
var _game_over: bool = false
var _dino_y: float = 0.0
var _dino_vy: float = 0.0
var _ground_abs: float = 0.0
var _speed: float = BASE_SPEED
var _score: int = 0
var _obstacles: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _next_spawn: float = 1.5

var _hint_label: Label = null
var _score_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	set_process(false)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_reset()
	# 延迟一帧抢焦点，确保节点已加入场景树
	call_deferred("grab_focus")


func _build_ui() -> void:
	# 提示文字
	_hint_label = Label.new()
	_hint_label.text = "按 空格 或 点击 开始"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", Color("#888888"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)

	# 分数
	_score_label = Label.new()
	_score_label.text = "0"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_size_override("font_size", 16)
	_score_label.add_theme_color_override("font_color", Color("#666666"))
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_score_label.offset_left = -80
	_score_label.offset_right = -12
	_score_label.offset_top = 8
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score_label)

	# 状态（game over）
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("#aa4444"))
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status_label.offset_top = 20
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)


func _reset() -> void:
	_ground_abs = size.y * GROUND_Y
	_dino_y = _ground_abs
	_dino_vy = 0.0
	_speed = BASE_SPEED
	_score = 0
	_obstacles.clear()
	_spawn_timer = 0.0
	_next_spawn = 1.5
	_game_over = false
	_running = false
	if _hint_label:
		_hint_label.visible = true
	if _status_label:
		_status_label.text = ""
	if _score_label:
		_score_label.text = "0"
	queue_redraw()


func _start() -> void:
	if _running:
		return
	_reset()
	_running = true
	_hint_label.visible = false
	set_process(true)


func _jump() -> void:
	if _dino_y >= _ground_abs - 1.0:
		_dino_vy = JUMP_VEL


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_handle_action()
		accept_event()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_UP:
			_handle_action()
			accept_event()


func _handle_action() -> void:
	if not _running:
		_start()
	else:
		_jump()


func _process(delta: float) -> void:
	if not _running or _game_over:
		return

	_speed += SPEED_ACCEL * delta
	_score += 1
	if _score_label:
		_score_label.text = str(_score)

	# 恐龙物理
	_dino_vy += GRAVITY * delta
	_dino_y += _dino_vy * delta
	if _dino_y >= _ground_abs:
		_dino_y = _ground_abs
		_dino_vy = 0.0

	# 障碍物移动
	for i in range(_obstacles.size() - 1, -1, -1):
		_obstacles[i]["x"] -= _speed * delta
		if _obstacles[i]["x"] < -OBSTACLE_W:
			_obstacles.remove_at(i)

	# 生成障碍物
	_spawn_timer += delta
	if _spawn_timer >= _next_spawn:
		_spawn_timer = 0.0
		_next_spawn = randf_range(SPAWN_MIN, SPAWN_MAX)
		var h: float = randf_range(OBSTACLE_MIN_H, OBSTACLE_MAX_H)
		_obstacles.append({"x": size.x + 10.0, "h": h})

	# 碰撞检测
	var dino_rect := Rect2(40.0, _dino_y - DINO_SIZE.y, DINO_SIZE.x, DINO_SIZE.y)
	for obs in _obstacles:
		var obs_rect := Rect2(obs["x"], _ground_abs - obs["h"], OBSTACLE_W, obs["h"])
		if dino_rect.intersects(obs_rect):
			_game_over = true
			_running = false
			set_process(false)
			if _status_label:
				_status_label.text = "GAME OVER — 点击或空格重试"
			break

	queue_redraw()


func _draw() -> void:
	_ground_abs = size.y * GROUND_Y

	# 地面线
	draw_line(Vector2(0, _ground_abs), Vector2(size.x, _ground_abs), Color("#cccccc"), 2.0)

	# 恐龙（简单方块）
	var dino_color := Color("#555555") if not _game_over else Color("#aa4444")
	var dino_rect := Rect2(40.0, _dino_y - DINO_SIZE.y, DINO_SIZE.x, DINO_SIZE.y)
	draw_rect(dino_rect, dino_color)
	# 眼睛
	draw_rect(Rect2(60.0, _dino_y - DINO_SIZE.y + 6.0, 6.0, 6.0), Color.WHITE)

	# 障碍物
	for obs in _obstacles:
		var obs_rect := Rect2(obs["x"], _ground_abs - obs["h"], OBSTACLE_W, obs["h"])
		draw_rect(obs_rect, Color("#77aa77"))


func stop_game() -> void:
	_running = false
	_game_over = true
	set_process(false)
