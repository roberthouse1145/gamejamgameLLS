class_name DevWorkApp
extends Control
## 开发工作 APP — 玩家选择开发任务，消耗 AP 提升项目数值
## 任务列表每周轮换，从 dev_work_tasks.json 中按权重和 min_day 筛选

const TASKS_DATA_PATH: String = "res://resources/data/dev_work_tasks.json"
const TASKS_PER_PAGE: int = 4

@onready var task_list: VBoxContainer = %TaskList
@onready var status_label: Label = %StatusLabel
@onready var stats_label: Label = %StatsLabel

var _all_tasks: Array[Dictionary] = []
var _current_tasks: Array[Dictionary] = []
var _week_index: int = -1


func _ready() -> void:
	_load_all_tasks()
	_refresh_tasks()
	_update_stats_display()
	_connect_signals()


func _connect_signals() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("stats_changed"):
		gm.stats_changed.connect(_update_stats_display)
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		if glm.has_signal("ap_changed"):
			glm.ap_changed.connect(func(_c: int, _m: int) -> void: _render_task_list())
		if glm.has_signal("day_changed"):
			glm.day_changed.connect(func(_d: int) -> void: _refresh_tasks())


func _load_all_tasks() -> void:
	_all_tasks.clear()
	if not FileAccess.file_exists(TASKS_DATA_PATH):
		push_warning("[DevWorkApp] Tasks data not found: %s" % TASKS_DATA_PATH)
		return
	var file := FileAccess.open(TASKS_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for item in parsed:
			if item is Dictionary:
				_all_tasks.append(item)
	print("[DevWorkApp] Loaded %d task definitions" % _all_tasks.size())


func _refresh_tasks() -> void:
	var week: int = _get_current_week_index()
	if week == _week_index and not _current_tasks.is_empty():
		return
	_week_index = week
	_current_tasks = _build_weekly_tasks(week)
	_render_task_list()


func _build_weekly_tasks(week_index: int) -> Array[Dictionary]:
	var day: int = _get_current_day()
	var eligible: Array[Dictionary] = []
	for task in _all_tasks:
		if day >= int(task.get("min_day", 1)):
			eligible.append(task)
	if eligible.is_empty():
		return []

	# 按 weight 降序排列，然后用 week_index 做偏移轮换
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("weight", 0)) > int(b.get("weight", 0))
	)
	var result: Array[Dictionary] = []
	var start: int = posmod(week_index * TASKS_PER_PAGE, eligible.size())
	for i in range(mini(TASKS_PER_PAGE, eligible.size())):
		var idx: int = posmod(start + i, eligible.size())
		result.append(eligible[idx].duplicate(true))
	return result


func _render_task_list() -> void:
	if task_list == null:
		return
	for child in task_list.get_children():
		child.queue_free()

	if _current_tasks.is_empty():
		var empty := Label.new()
		empty.text = "暂无可用的开发任务"
		empty.add_theme_font_size_override("font_size", 22)
		empty.add_theme_color_override("font_color", Color("#888888"))
		task_list.add_child(empty)
		return

	var can_act: bool = _can_consume_ap()
	for task in _current_tasks:
		var card := _create_task_card(task, can_act)
		task_list.add_child(card)


func _create_task_card(task: Dictionary, enabled: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e2738")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("#2a3a52")
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title := Label.new()
	title.text = str(task.get("title", "未命名任务"))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#e8ecf5"))
	info.add_child(title)

	var desc := Label.new()
	desc.text = str(task.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color("#8899b0"))
	info.add_child(desc)

	var effect := Label.new()
	effect.text = _format_stat_changes(task)
	effect.add_theme_font_size_override("font_size", 16)
	effect.add_theme_color_override("font_color", Color("#5aa9ff"))
	info.add_child(effect)

	var button := Button.new()
	button.text = "执行"
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(88, 40)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_on_task_pressed.bind(str(task.get("task_id", ""))))
	row.add_child(button)

	return card


func _on_task_pressed(task_id: String) -> void:
	var task: Dictionary = _find_task(task_id)
	if task.is_empty():
		_set_status("任务不存在")
		return

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.can_consume_ap(1):
		_set_status("当前无法执行工作")
		return

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		_set_status("GameManager 不可用")
		return

	# 消耗 AP
	if not glm.consume_ap(1, "work_order", task_id):
		_set_status("行动消耗失败")
		return

	# 应用数值变化
	var stat_changes: Dictionary = task.get("stat_changes", {})
	gm.modify_stats(stat_changes)

	# 压力增加
	var stress_cost: int = int(task.get("stress_cost", 0))
	if stress_cost > 0:
		gm.modify_stat("stress", stress_cost)

	_set_status("完成: %s" % str(task.get("title", "")))
	print("[DevWorkApp] Task executed: %s | %s | stress+%d" % [task_id, str(stat_changes), stress_cost])
	_render_task_list()
	_update_stats_display()


func _find_task(task_id: String) -> Dictionary:
	for task in _current_tasks:
		if str(task.get("task_id", "")) == task_id:
			return task
	return {}


func _format_stat_changes(task: Dictionary) -> String:
	var parts: PackedStringArray = []
	var changes: Dictionary = task.get("stat_changes", {})
	var label_map: Dictionary = {
		"completion": "完成度",
		"quality": "质量",
		"stability": "稳定",
		"hype": "热度",
	}
	for key in changes:
		var display: String = label_map.get(key, key)
		var delta: int = int(changes[key])
		if delta > 0:
			parts.append("%s+%d" % [display, delta])
	var stress_cost: int = int(task.get("stress_cost", 0))
	if stress_cost > 0:
		parts.append("压力+%d" % stress_cost)
	return " · ".join(parts)


func _update_stats_display() -> void:
	if stats_label == null:
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		stats_label.text = "数据不可用"
		return
	stats_label.text = "完成度 %d  |  质量 %d  |  稳定 %d  |  热度 %d" % [
		int(gm.get("completion")),
		int(gm.get("quality")),
		int(gm.get("stability")),
		int(gm.get("hype")),
	]


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _can_consume_ap() -> bool:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	return glm != null and glm.can_consume_ap(1)


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		return int(glm.get("current_day"))
	return 1


func _get_current_week_index() -> int:
	return int((_get_current_day() - 1) / 7.0)
