class_name DevWorkApp
extends Control
## 开发工作 APP — 玩家选择开发任务，通过 DevCycleManager 驱动开发循环
## 任务从 chapter_plans.json 动态解锁，激活后自动派发隐藏工单

const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")

@onready var task_list: VBoxContainer = %TaskList
@onready var status_label: Label = %StatusLabel
@onready var stats_label: Label = %StatsLabel


func _ready() -> void:
	_render_task_list()
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

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null:
		if dcm.has_signal("tasks_updated"):
			dcm.tasks_updated.connect(_render_task_list)
		if dcm.has_signal("task_status_changed"):
			dcm.task_status_changed.connect(func(_id: String, _st: String) -> void: _render_task_list())


func _render_task_list() -> void:
	if task_list == null:
		return
	for child in task_list.get_children():
		child.queue_free()

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	var tasks: Array[Dictionary] = []
	if dcm != null:
		tasks = dcm.get_visible_tasks()

	if tasks.is_empty():
		var empty := Label.new()
		empty.text = "暂无可用的开发任务"
		empty.add_theme_font_size_override("font_size", 22)
		empty.add_theme_color_override("font_color", Color("#888888"))
		task_list.add_child(empty)
		return

	var can_act: bool = _can_consume_ap()
	for task in tasks:
		var card := _create_task_card(task, can_act)
		task_list.add_child(card)


func _create_task_card(task: Dictionary, enabled: bool) -> PanelContainer:
	var task_status: String = str(task.get("status", "available"))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()

	# 根据任务状态设置不同的卡片样式
	match task_status:
		"active":
			style.bg_color = Color("#1e3328")
			style.border_color = Color("#2a5242")
		"queued":
			style.bg_color = Color("#2a2a1e")
			style.border_color = Color("#52522a")
		_:
			style.bg_color = Color("#1e2738")
			style.border_color = Color("#2a3a52")

	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	card.add_theme_stylebox_override("panel", style)

	var hint := ActivityPreviewHintClass.new()
	card.add_child(hint)
	hint.set_payload_resolver(func() -> Dictionary:
		return _build_task_preview_payload(task, enabled)
	)

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
	var title_text: String = str(task.get("title", "未命名任务"))
	# 状态标签
	match task_status:
		"active":
			title_text = "⏳ " + title_text
		"queued":
			title_text = "📋 " + title_text
	title.text = title_text
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
	# 按钮文字和可用性根据状态变化
	match task_status:
		"active":
			button.text = "进行中"
			button.disabled = true
		"queued":
			button.text = "排队中"
			button.disabled = true
		_:
			button.text = "执行"
			button.disabled = not enabled
	button.custom_minimum_size = Vector2(88, 40)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_on_task_pressed.bind(str(task.get("task_id", ""))))
	row.add_child(button)

	return card


func _on_task_pressed(task_id: String) -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		_set_status("DevCycleManager 不可用")
		return

	if not dcm.activate_task(task_id):
		_set_status("无法执行此任务")
		return

	var task: Dictionary = dcm.get_task(task_id)
	var status: String = str(task.get("status", ""))
	match status:
		"active":
			_set_status("任务进行中: %s" % str(task.get("title", "")))
		"queued":
			_set_status("已加入队列: %s" % str(task.get("title", "")))
		"completed":
			_set_status("完成: %s" % str(task.get("title", "")))
		_:
			_set_status("已启动: %s" % str(task.get("title", "")))

	_render_task_list()
	_update_stats_display()


func _format_stat_changes(task: Dictionary) -> String:
	var parts: PackedStringArray = []
	var label_map: Dictionary = {
		"affection": "好感",
		"stress": "压力",
		"passion": "激情",
		"completion": "完成度",
		"quality": "质量",
		"stability": "稳定",
		"hype": "热度",
	}
	var changes: Dictionary = _get_task_reward_preview(task)
	for key in changes:
		var display: String = label_map.get(key, key)
		var delta: int = int(changes[key])
		if delta == 0:
			continue
		if delta > 0:
			parts.append("%s+%d" % [display, delta])
		else:
			parts.append("%s%d" % [display, delta])
	return " · ".join(parts)


func _build_task_preview_payload(task: Dictionary, enabled: bool) -> Dictionary:
	var task_status: String = str(task.get("status", "available"))
	var conditions: Array[String] = ["消耗 1 点行动力"]
	match task_status:
		"active":
			conditions.append("当前状态：进行中")
		"queued":
			conditions.append("当前状态：排队中")
		_:
			conditions.append("当前状态：可执行" if enabled else "当前状态：行动力不足")

	return {
		"title": str(task.get("title", "开发任务")),
		"text": "开发会明显消耗林夏的状态。连续埋头做活会快速提高压力，也会降低创作热情。",
		"conditions": conditions,
		"rewards": _get_task_reward_preview(task),
		"disabled_reason": "" if enabled or task_status in ["active", "queued"] else "当前行动力不足，不能继续开发。",
	}


func _get_task_reward_preview(task: Dictionary) -> Dictionary:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null and dcm.has_method("build_task_reward_preview"):
		return dcm.build_task_reward_preview(task)
	return task.get("stat_changes", {}).duplicate(true)


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
