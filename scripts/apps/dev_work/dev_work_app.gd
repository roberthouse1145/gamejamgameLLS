class_name DevWorkApp
extends Control
## 开发工作 APP — 玩家选择开发任务，通过 DevCycleManager 驱动开发循环
##
## 重构目标：从「占位功能面板」改成「白底叙事风」——
##   · 顶部：大标题 + 副标题 + stats 小 pill 徽章
##   · 中部：当前任务大卡片（左侧状态 stripe、白底圆角、阴影）
##   · 下部：后续计划的轻卡片
## 视觉色与 minigame 结算卡片保持一致。

const ActivityPreviewHintClass = preload("res://scripts/ui/activity_preview/activity_preview_hint.gd")

## 白底卡片 / 统一叙事风配色
const COLOR_CARD_BG := Color("#ffffff")
const COLOR_TEXT_TITLE := Color("#0f172a")
const COLOR_TEXT_BODY := Color("#475569")
const COLOR_TEXT_MUTED := Color("#94a3b8")
const COLOR_FOCUS_BG := Color("#f1f5f9")
const COLOR_FOCUS_TEXT := Color("#475569")
const COLOR_PILL_REWARD_BG := Color("#e0e7ff")
const COLOR_PILL_REWARD_TEXT := Color("#4338ca")
const COLOR_PILL_NEGATIVE_BG := Color("#fee2e2")
const COLOR_PILL_NEGATIVE_TEXT := Color("#b91c1c")
const COLOR_BUTTON_ACCENT := Color("#6366f1")

## 任务状态对应的 stripe 颜色 + 徽章配色
const STATUS_STRIPE: Dictionary = {
	"available": Color("#6366f1"),
	"active": Color("#10b981"),
	"queued": Color("#f59e0b"),
}

const STATUS_LABEL: Dictionary = {
	"available": "待开始",
	"active": "进行中",
	"queued": "排队中",
}

const STATUS_PILL_BG: Dictionary = {
	"available": Color("#e0e7ff"),
	"active": Color("#d1fae5"),
	"queued": Color("#fef3c7"),
}

const STATUS_PILL_TEXT: Dictionary = {
	"available": Color("#4338ca"),
	"active": Color("#047857"),
	"queued": Color("#b45309"),
}

@onready var task_list: VBoxContainer = %TaskList
@onready var subtitle_label: Label = %Subtitle
@onready var stats_bar: HBoxContainer = %StatsBar


func _ready() -> void:
	_render_task_list()
	_update_stats_display()
	_connect_signals()


func _connect_signals() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("stats_changed"):
		gm.stats_changed.connect(_update_stats_display)

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("ap_changed"):
		glm.ap_changed.connect(func(_c: int, _m: int) -> void:
			_render_task_list()
		)

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null:
		if dcm.has_signal("tasks_updated"):
			dcm.tasks_updated.connect(_render_task_list)
		if dcm.has_signal("task_status_changed"):
			dcm.task_status_changed.connect(func(_id: String, _st: String) -> void: _render_task_list())


# ---------------------------------------------------------------------------
# 渲染入口
# ---------------------------------------------------------------------------

func _render_task_list() -> void:
	if task_list == null:
		return
	for child in task_list.get_children():
		child.queue_free()

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	var current_task: Dictionary = {}
	var upcoming_tasks: Array[Dictionary] = []
	if dcm != null:
		if dcm.has_method("get_current_surface_task"):
			current_task = dcm.get_current_surface_task()
		else:
			var fallback_tasks: Array[Dictionary] = dcm.get_visible_tasks()
			if not fallback_tasks.is_empty():
				current_task = fallback_tasks[0]
		if dcm.has_method("get_upcoming_surface_tasks"):
			upcoming_tasks = dcm.get_upcoming_surface_tasks(2)

	if current_task.is_empty():
		task_list.add_child(_create_empty_state())
		_set_subtitle("今天先喘口气，没有排上新的工作")
		return

	var can_act: bool = _can_consume_ap()
	task_list.add_child(_create_current_task_card(current_task, can_act))
	_set_subtitle(_build_subtitle_text(current_task, can_act))

	if not upcoming_tasks.is_empty():
		task_list.add_child(_create_upcoming_section(upcoming_tasks))


# ---------------------------------------------------------------------------
# 当前任务大卡片
# ---------------------------------------------------------------------------

func _create_current_task_card(task: Dictionary, enabled: bool) -> Control:
	var task_status: String = str(task.get("status", "available"))
	var stripe_color: Color = STATUS_STRIPE.get(task_status, STATUS_STRIPE["available"])

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = COLOR_CARD_BG
	card_sb.set_corner_radius_all(18)
	card_sb.shadow_color = Color(0.055, 0.094, 0.16, 0.10)
	card_sb.shadow_size = 18
	card_sb.shadow_offset = Vector2(0, 6)
	card_sb.content_margin_left = 0
	card_sb.content_margin_right = 0
	card_sb.content_margin_top = 0
	card_sb.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", card_sb)

	var hint := ActivityPreviewHintClass.new()
	card.add_child(hint)
	hint.set_payload_resolver(func() -> Dictionary:
		return _build_task_preview_payload(task, enabled)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	card.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = stripe_color
	stripe.custom_minimum_size = Vector2(6, 0)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(stripe)

	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 28)
	body_margin.add_theme_constant_override("margin_right", 28)
	body_margin.add_theme_constant_override("margin_top", 22)
	body_margin.add_theme_constant_override("margin_bottom", 22)
	row.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body_margin.add_child(body)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	body.add_child(top_row)
	top_row.add_child(_create_status_badge(task_status))
	var type_hint_text: String = _build_type_hint(task)
	if not type_hint_text.is_empty():
		var type_hint := Label.new()
		type_hint.text = type_hint_text
		type_hint.add_theme_font_size_override("font_size", 15)
		type_hint.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		type_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top_row.add_child(type_hint)

	var title := Label.new()
	title.text = str(task.get("title", "未命名任务"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_TEXT_TITLE)
	body.add_child(title)

	var desc_text: String = str(task.get("description", "")).strip_edges()
	if not desc_text.is_empty():
		var desc := Label.new()
		desc.text = desc_text
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 17)
		desc.add_theme_color_override("font_color", COLOR_TEXT_BODY)
		body.add_child(desc)

	var focus_text: String = _build_task_focus_line(task)
	if not focus_text.is_empty():
		body.add_child(_create_focus_block(focus_text))

	var reward_row := _create_reward_row(task)
	if reward_row != null:
		body.add_child(reward_row)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(btn_row)

	var button := Button.new()
	button.custom_minimum_size = Vector2(168, 48)
	button.add_theme_font_size_override("font_size", 18)
	match task_status:
		"active":
			button.text = "工作进行中"
			button.disabled = true
		"queued":
			button.text = "等待后台完成"
			button.disabled = true
		_:
			button.text = "开始这项工作"
			button.disabled = not enabled
	_style_action_button(button)
	_attach_button_hover(button)
	button.pressed.connect(_on_task_pressed.bind(str(task.get("task_id", ""))))
	btn_row.add_child(button)

	return card


func _create_status_badge(task_status: String) -> Control:
	var pill := PanelContainer.new()
	var pill_bg: Color = STATUS_PILL_BG.get(task_status, STATUS_PILL_BG["available"])
	var pill_text: Color = STATUS_PILL_TEXT.get(task_status, STATUS_PILL_TEXT["available"])
	var sb := StyleBoxFlat.new()
	sb.bg_color = pill_bg
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = STATUS_LABEL.get(task_status, "待开始")
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", pill_text)
	pill.add_child(lbl)
	return pill


func _create_focus_block(text: String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_FOCUS_BG
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var icon := Label.new()
	icon.text = "◆"
	icon.add_theme_font_size_override("font_size", 14)
	icon.add_theme_color_override("font_color", COLOR_BUTTON_ACCENT)
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", COLOR_FOCUS_TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	return panel


func _create_reward_row(task: Dictionary) -> Control:
	var changes: Dictionary = _get_task_reward_preview(task)
	if changes.is_empty():
		return null
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("separation", 8)

	var label_map: Dictionary = {
		"affection": "好感",
		"stress": "压力",
		"passion": "激情",
		"completion": "完成度",
		"quality": "质量",
		"stability": "稳定",
		"hype": "热度",
	}
	var has_any: bool = false
	for key in changes:
		var delta: int = int(changes[key])
		if delta == 0:
			continue
		has_any = true
		var display: String = str(label_map.get(key, key))
		var sign_char: String = "+" if delta > 0 else ""
		flow.add_child(_create_reward_pill("%s %s%d" % [display, sign_char, delta], delta > 0))
	if not has_any:
		return null
	return flow


func _create_reward_pill(text: String, is_positive: bool) -> Control:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PILL_REWARD_BG if is_positive else COLOR_PILL_NEGATIVE_BG
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", COLOR_PILL_REWARD_TEXT if is_positive else COLOR_PILL_NEGATIVE_TEXT)
	pill.add_child(lbl)
	return pill


func _style_action_button(btn: Button) -> void:
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = COLOR_BUTTON_ACCENT
	normal_sb.set_corner_radius_all(24)
	normal_sb.content_margin_left = 20
	normal_sb.content_margin_right = 20
	normal_sb.content_margin_top = 10
	normal_sb.content_margin_bottom = 10
	normal_sb.shadow_color = Color(COLOR_BUTTON_ACCENT.r, COLOR_BUTTON_ACCENT.g, COLOR_BUTTON_ACCENT.b, 0.32)
	normal_sb.shadow_size = 8
	normal_sb.shadow_offset = Vector2(0, 3)
	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = COLOR_BUTTON_ACCENT.darkened(0.12)
	var disabled_sb := StyleBoxFlat.new()
	disabled_sb.bg_color = Color("#e2e8f0")
	disabled_sb.set_corner_radius_all(24)
	disabled_sb.content_margin_left = 20
	disabled_sb.content_margin_right = 20
	disabled_sb.content_margin_top = 10
	disabled_sb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#94a3b8"))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _attach_button_hover(btn: Button) -> void:
	var hover_tween: Array[Tween] = [null]
	var play_hover := func(target_scale: Vector2) -> void:
		if btn.disabled:
			return
		if hover_tween[0] != null and is_instance_valid(hover_tween[0]):
			hover_tween[0].kill()
		btn.pivot_offset = btn.size * 0.5
		hover_tween[0] = btn.create_tween()
		hover_tween[0].set_trans(Tween.TRANS_CUBIC)
		hover_tween[0].set_ease(Tween.EASE_OUT)
		hover_tween[0].tween_property(btn, "scale", target_scale, 0.12)
	btn.mouse_entered.connect(func() -> void: play_hover.call(Vector2(1.03, 1.03)))
	btn.mouse_exited.connect(func() -> void: play_hover.call(Vector2.ONE))


# ---------------------------------------------------------------------------
# 后续计划
# ---------------------------------------------------------------------------

func _create_upcoming_section(tasks: Array[Dictionary]) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)

	var header := Label.new()
	header.text = "接下来还排着"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	root.add_child(header)

	for task in tasks:
		root.add_child(_create_upcoming_item(task))
	return root


func _create_upcoming_item(task: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CARD_BG
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0.055, 0.094, 0.16, 0.06)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	card.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = Color("#cbd5e1")
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(stripe)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	row.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title := Label.new()
	title.text = str(task.get("title", "未命名任务"))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_TEXT_TITLE)
	box.add_child(title)

	var desc_text: String = str(task.get("description", "")).strip_edges()
	if not desc_text.is_empty():
		var desc := Label.new()
		desc.text = desc_text
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 14)
		desc.add_theme_color_override("font_color", COLOR_TEXT_BODY)
		box.add_child(desc)

	var focus_text: String = _build_task_focus_line(task)
	if not focus_text.is_empty():
		var focus := Label.new()
		focus.text = "◆ " + focus_text
		focus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		focus.add_theme_font_size_override("font_size", 13)
		focus.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		box.add_child(focus)

	return card


func _create_empty_state() -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CARD_BG
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0.055, 0.094, 0.16, 0.08)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 48
	sb.content_margin_bottom = 48
	card.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	var headline := Label.new()
	headline.text = "今天工程先停一停"
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 24)
	headline.add_theme_color_override("font_color", COLOR_TEXT_TITLE)
	box.add_child(headline)

	var sub := Label.new()
	sub.text = "没有新的工作被排进来，陪林夏聊聊天也是好事"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	box.add_child(sub)
	return card


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_task_pressed(task_id: String) -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		_set_subtitle("DevCycleManager 不可用")
		return

	if not dcm.activate_task(task_id):
		_set_subtitle("这个时间段已经安排过事情了")
		return

	_render_task_list()
	_update_stats_display()


# ---------------------------------------------------------------------------
# 文案 / 预览
# ---------------------------------------------------------------------------

func _build_task_preview_payload(task: Dictionary, enabled: bool) -> Dictionary:
	var task_status: String = str(task.get("status", "available"))
	var conditions: Array[String] = ["占用当前时间段"]
	var task_type: String = str(task.get("task_type", "")).strip_edges()
	var minigame_type: String = str(task.get("minigame_type", "")).strip_edges()
	if task_type == "chat_topic" or minigame_type == "creative_decision":
		conditions.append("交互方式：创意讨论")
	elif minigame_type == "structured_form":
		conditions.append("交互方式：方案填写")
	else:
		conditions.append("交互方式：小游戏执行")
	match task_status:
		"active":
			conditions.append("当前状态：进行中")
		"queued":
			conditions.append("当前状态：排队中")
		_:
			conditions.append("当前状态：可执行" if enabled else "当前状态：本时段已安排")

	return {
		"title": str(task.get("title", "开发任务")),
		"text": "开发会明显消耗林夏的状态。连续埋头做活会快速提高压力，也会降低创作热情。",
		"conditions": conditions,
		"rewards": _get_task_reward_preview(task),
		"disabled_reason": "" if enabled or task_status in ["active", "queued"] else "这个时间段已经安排过事情了。",
	}


func _build_type_hint(task: Dictionary) -> String:
	var task_type: String = str(task.get("task_type", "")).strip_edges()
	var minigame_type: String = str(task.get("minigame_type", "")).strip_edges()
	if task_type == "chat_topic" or minigame_type == "creative_decision":
		return "创意讨论 · 和林夏敲定方向"
	if minigame_type == "structured_form":
		return "方案填写 · 把想法落成表单"
	if not minigame_type.is_empty():
		return "动手执行 · 一段小工作"
	return ""


func _build_task_focus_line(task: Dictionary) -> String:
	var task_type: String = str(task.get("task_type", "")).strip_edges()
	var minigame_type: String = str(task.get("minigame_type", "")).strip_edges()
	if task_type == "chat_topic" or minigame_type == "creative_decision":
		return "这轮只围绕一个缺口讨论，不顺手扩到别的维度。"
	if minigame_type == "structured_form":
		return "这轮先收束成一份可继续开发的结构化方案。"
	var work_order: Dictionary = task.get("post_task_work_order", {})
	var kb_sources: Array = work_order.get("kb_sources", []) if work_order is Dictionary else []
	if not kb_sources.is_empty():
		return "本轮聚焦：%s。越界信息先保留待定。" % "/".join(kb_sources)
	return ""


func _build_subtitle_text(task: Dictionary, can_act: bool) -> String:
	var title: String = str(task.get("title", "当前工作")).strip_edges()
	match str(task.get("status", "available")):
		"active":
			return "正在推进：%s" % title
		"queued":
			return "后台继续跑：%s" % title
		_:
			if can_act:
				return "和林夏一起，把工程一点一点往前推"
			return "这个时间段已经安排过事情了，先把当前节奏走完"


func _get_task_reward_preview(task: Dictionary) -> Dictionary:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null and dcm.has_method("build_task_reward_preview"):
		return dcm.build_task_reward_preview(task)
	return task.get("stat_changes", {}).duplicate(true)


# ---------------------------------------------------------------------------
# 顶部状态徽章组
# ---------------------------------------------------------------------------

func _update_stats_display() -> void:
	if stats_bar == null:
		return
	for child in stats_bar.get_children():
		child.queue_free()

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var entries: Array = [
		{"label": "完成", "value": int(gm.get("completion")), "tint": Color("#6366f1")},
		{"label": "质量", "value": int(gm.get("quality")), "tint": Color("#0ea5e9")},
		{"label": "稳定", "value": int(gm.get("stability")), "tint": Color("#10b981")},
		{"label": "热度", "value": int(gm.get("hype")), "tint": Color("#f97316")},
	]
	for entry in entries:
		stats_bar.add_child(_create_stat_pill(str(entry["label"]), int(entry["value"]), entry["tint"]))


func _create_stat_pill(label: String, value: int, tint: Color) -> Control:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CARD_BG
	sb.set_corner_radius_all(14)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color("#e2e8f0")
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)

	var dot := ColorRect.new()
	dot.color = tint
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var label_node := Label.new()
	label_node.text = label
	label_node.add_theme_font_size_override("font_size", 13)
	label_node.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	row.add_child(label_node)

	var value_node := Label.new()
	value_node.text = str(value)
	value_node.add_theme_font_size_override("font_size", 16)
	value_node.add_theme_color_override("font_color", COLOR_TEXT_TITLE)
	row.add_child(value_node)

	return pill


func _format_stat_changes(task: Dictionary) -> String:
	var rewards: Dictionary = _get_task_reward_preview(task)
	if rewards.is_empty():
		return ""
	var label_map: Dictionary = {
		"money": "金钱",
		"affection": "好感",
		"stress": "压力",
		"passion": "激情",
		"completion": "完成度",
		"quality": "质量",
		"stability": "稳定",
		"hype": "热度",
	}
	var order: Array[String] = ["money", "affection", "stress", "passion", "completion", "quality", "stability", "hype"]
	var parts: Array[String] = []
	var consumed: Dictionary = {}
	for key in order:
		if not rewards.has(key):
			continue
		_append_stat_part(parts, consumed, key, rewards, label_map)
	var extra_keys: Array[String] = []
	for raw_key in rewards.keys():
		var key_text: String = str(raw_key)
		if not consumed.has(key_text):
			extra_keys.append(key_text)
	extra_keys.sort()
	for key in extra_keys:
		_append_stat_part(parts, consumed, key, rewards, label_map)
	return " · ".join(parts)


func _append_stat_part(parts: Array[String], consumed: Dictionary, key: String, rewards: Dictionary, label_map: Dictionary) -> void:
	var delta: int = int(rewards.get(key, 0))
	if delta == 0:
		return
	var sign_char: String = "+" if delta > 0 else ""
	parts.append("%s%s%d" % [str(label_map.get(key, key)), sign_char, delta])
	consumed[key] = true


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _set_subtitle(text: String) -> void:
	if subtitle_label != null:
		subtitle_label.text = text


func _can_consume_ap() -> bool:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	return glm != null and glm.can_consume_ap(1)
