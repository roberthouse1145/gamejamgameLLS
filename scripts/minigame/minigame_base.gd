class_name MinigameBase extends Control
## 小游戏基类
## 所有开发小游戏继承此类，实现统一的启动/结算接口。
##
## 生命周期：
##   setup(config) → 小游戏初始化
##   _on_minigame_start() → 子类覆写，开始游戏逻辑
##   finish(result) → 子类调用，通知结算
##
## 子类必须覆写：
##   _on_minigame_start() — 启动小游戏的具体逻辑
##   _on_minigame_cleanup() — 清理资源（可选）

## 小游戏完成，携带结算数据
## result: { score: float (0.0~1.0), choices: Dictionary, ... }
signal minigame_finished(result: Dictionary)

## 玩家主动放弃
signal minigame_cancelled()

## 小游戏配置（由 MinigameManager 传入）
var config: Dictionary = {}

## 关联的任务数据（由 DevCycleManager / MinigameManager 注入）
var task_data: Dictionary = {}

## 是否正在运行
var _running: bool = false


## 由 MinigameManager 调用，初始化并启动小游戏
func setup(p_config: Dictionary) -> void:
	config = p_config
	task_data = config.get("task_data", {})
	_running = true
	_on_minigame_start()


## 子类覆写：小游戏开始时的逻辑
func _on_minigame_start() -> void:
	push_warning("[MinigameBase] _on_minigame_start() not implemented by subclass")


## 子类覆写：清理资源（可选）
func _on_minigame_cleanup() -> void:
	pass


## 子类调用：完成小游戏
## score: 0.0 ~ 1.0，影响数值结算的系数
func finish(result: Dictionary) -> void:
	if not _running:
		return
	_running = false
	if not result.has("score"):
		result["score"] = 1.0
	result["score"] = clampf(float(result.get("score", 1.0)), 0.0, 1.0)
	result["task_id"] = str(task_data.get("task_id", ""))
	result["minigame_type"] = str(config.get("minigame_type", ""))
	_on_minigame_cleanup()
	minigame_finished.emit(result)


## 子类调用：放弃小游戏
func cancel() -> void:
	if not _running:
		return
	_running = false
	_on_minigame_cleanup()
	minigame_cancelled.emit()


## 工具方法：获取林夏当前状态（子类可用于调整难度/提示）
func get_heroine_mood() -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return {}
	return {
		"affection": int(gm.get("affection")),
		"stress": int(gm.get("stress")),
		"passion": int(gm.get("passion")),
	}


## 工具方法：获取当前天数（子类可用于难度递增）
func get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return 1
	return int(glm.get("current_day"))


## 通用结算浮层：展示标题 + 叙事统计，玩家点按钮后才真正 finish。
## 子类若有自定义结算画面可以不用此 helper；否则应在原本 finish() 位置改调此方法。
## summary 字段：
##   title: String            结算标题，如 "剧情分歧敲定"
##   subtitle: String         次级描述（可选）
##   stats: Array[String]     多行统计信息（每行一条）
##   button_text: String      结算按钮文字（可选，默认“完成”）
##   result: Dictionary       点完成后传给 finish() 的原始结算数据
func present_summary_and_finish(summary: Dictionary) -> void:
	if not _running:
		return
	var layer := _build_summary_layer(summary)
	add_child(layer)
	layer.modulate.a = 0.0
	layer.scale = Vector2(0.985, 0.985)
	layer.pivot_offset = size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(layer, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(layer, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_summary_layer(summary: Dictionary) -> Control:
	var layer := Control.new()
	layer.name = "MinigameSummaryLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP

	var mask := ColorRect.new()
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0.06, 0.09, 0.15, 0.55)
	layer.add_child(mask)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color("#ffffff")
	card_sb.set_corner_radius_all(20)
	card_sb.shadow_color = Color(0, 0, 0, 0.25)
	card_sb.shadow_size = 24
	card_sb.shadow_offset = Vector2(0, 10)
	card_sb.content_margin_left = 44
	card_sb.content_margin_right = 44
	card_sb.content_margin_top = 36
	card_sb.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var accent := Color("#6366f1")

	var title_text: String = str(summary.get("title", "完成！"))
	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", Color("#0f172a"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var subtitle: String = str(summary.get("subtitle", "")).strip_edges()
	if not subtitle.is_empty():
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.add_theme_font_size_override("font_size", 17)
		sub_lbl.add_theme_color_override("font_color", Color("#64748b"))
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(sub_lbl)

	var stats: Array = summary.get("stats", [])
	if stats.size() > 0:
		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 14)
		var sep_style := StyleBoxLine.new()
		sep_style.color = Color("#e2e8f0")
		sep_style.thickness = 1
		sep.add_theme_stylebox_override("separator", sep_style)
		vbox.add_child(sep)

		for line in stats:
			var text: String = str(line).strip_edges()
			if text.is_empty():
				continue
			var stat_lbl := Label.new()
			stat_lbl.text = text
			stat_lbl.add_theme_font_size_override("font_size", 17)
			stat_lbl.add_theme_color_override("font_color", Color("#334155"))
			stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(stat_lbl)

	var btn := Button.new()
	btn.text = str(summary.get("button_text", "完成"))
	btn.custom_minimum_size = Vector2(180, 54)
	btn.add_theme_font_size_override("font_size", 21)
	_style_summary_button(btn, accent)
	_attach_summary_button_hover(btn)
	var stored_result: Dictionary = summary.get("result", {})
	btn.pressed.connect(func() -> void:
		finish(stored_result)
	)
	var btn_center := CenterContainer.new()
	btn_center.add_child(btn)
	vbox.add_child(btn_center)

	return layer


func _style_summary_button(btn: Button, accent: Color) -> void:
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = accent
	normal_sb.set_corner_radius_all(27)
	normal_sb.content_margin_left = 24
	normal_sb.content_margin_right = 24
	normal_sb.content_margin_top = 12
	normal_sb.content_margin_bottom = 12
	normal_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	normal_sb.shadow_size = 8
	normal_sb.shadow_offset = Vector2(0, 3)
	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = accent.darkened(0.12)
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _attach_summary_button_hover(btn: Button) -> void:
	var hover_tween: Array[Tween] = [null]
	var play_hover := func(target_scale: Vector2) -> void:
		if hover_tween[0] != null and is_instance_valid(hover_tween[0]):
			hover_tween[0].kill()
		btn.pivot_offset = btn.size * 0.5
		hover_tween[0] = btn.create_tween()
		hover_tween[0].set_trans(Tween.TRANS_CUBIC)
		hover_tween[0].set_ease(Tween.EASE_OUT)
		hover_tween[0].tween_property(btn, "scale", target_scale, 0.12)
	btn.mouse_entered.connect(func() -> void: play_hover.call(Vector2(1.04, 1.04)))
	btn.mouse_exited.connect(func() -> void: play_hover.call(Vector2.ONE))

