extends MinigameBase

const REVIEW_TYPE_DESC: String = "搭档刚刚给一批台词做了情绪标注，帮忙校准角色演出的情感基调"
const MIN_OPTION_COUNT: int = 3
const ADVANCE_DELAY_SECONDS: float = 0.6

const BG_MAIN := Color("#f5f7fb")
const BG_PANEL := Color("#ffffff")
const BG_CARD := Color("#ffffff")
const BG_OPTION := Color("#f8fafc")
const BG_OPTION_HOVER := Color("#eef2ff")
const BG_OPTION_CORRECT := Color("#d1fae5")
const BG_OPTION_WRONG := Color("#fee2e2")
const BORDER_SOFT := Color("#e5e7eb")
const BORDER_CARD := Color("#e0e7ff")
const TEXT_PRIMARY := Color("#0f172a")
const TEXT_SECONDARY := Color("#64748b")
const TEXT_CARD := Color("#0f172a")
const TEXT_DIM := Color("#94a3b8")
const ACCENT := Color("#6366f1")
const ACCENT_SOFT := Color("#e0e7ff")
const SUCCESS := Color("#10b981")
const SUCCESS_DARK := Color("#047857")
const DANGER := Color("#f43f5e")
const DANGER_DARK := Color("#b91c1c")

var _rng := RandomNumberGenerator.new()
var _scene_brief: String = ""
var _items: Array[Dictionary] = []
var _current_index: int = 0
var _correct_count: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _locked: bool = false

var _title_label: Label = null
var _brief_label: Label = null
var _progress_label: Label = null
var _combo_label: Label = null
var _progress_fill: ColorRect = null
var _speaker_label: Label = null
var _line_label: RichTextLabel = null
var _status_label: Label = null
var _feedback_label: Label = null
var _option_row: HBoxContainer = null
var _option_buttons: Array[Button] = []
var _frame_panel: PanelContainer = null
var _flash_rect: ColorRect = null


func _ready() -> void:
	_build_ui()


func _on_minigame_start() -> void:
	_rng.randomize()
	var generated_content: Dictionary = config.get("generated_content", {})
	_scene_brief = str(generated_content.get("scene_brief", task_data.get("description", "判断这批句子的情绪落点，让角色演出更准一些。"))).strip_edges()
	_items = _normalize_items(generated_content.get("items", []))
	if _items.is_empty():
		_items = _build_fallback_items()

	_current_index = 0
	_correct_count = 0
	_combo = 0
	_max_combo = 0
	_locked = false

	_title_label.text = str(task_data.get("title", "情绪标注"))
	_brief_label.text = _scene_brief
	_feedback_label.text = ""
	_feedback_label.modulate.a = 0.0
	_render_current_item()


func _on_minigame_cleanup() -> void:
	_locked = false
	_option_buttons.clear()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_MAIN
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	header.add_child(_title_label)

	_brief_label = Label.new()
	_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_label.add_theme_font_size_override("font_size", 18)
	_brief_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	header.add_child(_brief_label)

	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 12)
	root.add_child(hud)

	_progress_label = _build_hud_chip("第 1 / 1 题", ACCENT)
	hud.add_child(_progress_label)

	_combo_label = _build_hud_chip("连中 x0", SUCCESS)
	hud.add_child(_combo_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)

	var progress_shell := PanelContainer.new()
	progress_shell.custom_minimum_size = Vector2(220, 12)
	var progress_shell_sb := StyleBoxFlat.new()
	progress_shell_sb.bg_color = Color("#e5e7eb")
	progress_shell_sb.set_corner_radius_all(999)
	progress_shell.add_theme_stylebox_override("panel", progress_shell_sb)
	hud.add_child(progress_shell)

	var progress_bg := ColorRect.new()
	progress_bg.custom_minimum_size = Vector2(220, 12)
	progress_bg.color = Color("#e5e7eb")
	progress_shell.add_child(progress_bg)

	_progress_fill = ColorRect.new()
	_progress_fill.color = ACCENT
	_progress_fill.anchor_right = 0.0
	_progress_fill.anchor_bottom = 0.0
	_progress_fill.custom_minimum_size = Vector2(0, 12)
	_progress_fill.size = Vector2(0, 12)
	progress_bg.add_child(_progress_fill)

	var stage_wrap := MarginContainer.new()
	stage_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_wrap.add_theme_constant_override("margin_left", 60)
	stage_wrap.add_theme_constant_override("margin_right", 60)
	root.add_child(stage_wrap)

	var frame := PanelContainer.new()
	_frame_panel = frame
	frame.custom_minimum_size = Vector2(0, 520)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = BG_PANEL
	frame_sb.border_color = BORDER_SOFT
	frame_sb.set_border_width_all(1)
	frame_sb.set_corner_radius_all(20)
	frame_sb.shadow_color = Color(0, 0, 0, 0.08)
	frame_sb.shadow_size = 20
	frame_sb.shadow_offset = Vector2(0, 8)
	frame_sb.content_margin_left = 40
	frame_sb.content_margin_top = 28
	frame_sb.content_margin_right = 40
	frame_sb.content_margin_bottom = 28
	frame.add_theme_stylebox_override("panel", frame_sb)
	stage_wrap.add_child(frame)

	var frame_box := VBoxContainer.new()
	frame_box.add_theme_constant_override("separation", 20)
	frame.add_child(frame_box)

	# Header: speaker badge + scene cue
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 16)
	frame_box.add_child(header_row)

	var speaker_badge := PanelContainer.new()
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = ACCENT_SOFT
	badge_sb.set_corner_radius_all(999)
	badge_sb.content_margin_left = 18
	badge_sb.content_margin_right = 18
	badge_sb.content_margin_top = 8
	badge_sb.content_margin_bottom = 8
	speaker_badge.add_theme_stylebox_override("panel", badge_sb)
	header_row.add_child(speaker_badge)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.add_theme_color_override("font_color", ACCENT)
	speaker_badge.add_child(_speaker_label)

	var cue_left := HSeparator.new()
	cue_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cue_line_sb := StyleBoxLine.new()
	cue_line_sb.color = BORDER_SOFT
	cue_line_sb.thickness = 1
	cue_left.add_theme_stylebox_override("separator", cue_line_sb)
	header_row.add_child(cue_left)

	var cue_label := Label.new()
	cue_label.text = "TAKE · 待校对"
	cue_label.add_theme_font_size_override("font_size", 15)
	cue_label.add_theme_color_override("font_color", TEXT_DIM)
	header_row.add_child(cue_label)

	# 台词卡
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 220)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = BG_CARD
	card_sb.border_color = BORDER_CARD
	card_sb.border_width_left = 6
	card_sb.border_width_top = 1
	card_sb.border_width_right = 1
	card_sb.border_width_bottom = 1
	card_sb.set_corner_radius_all(22)
	card_sb.shadow_color = Color(0, 0, 0, 0.06)
	card_sb.shadow_size = 12
	card_sb.shadow_offset = Vector2(0, 6)
	card_sb.content_margin_left = 48
	card_sb.content_margin_top = 32
	card_sb.content_margin_right = 48
	card_sb.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", card_sb)
	frame_box.add_child(card)

	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 14)
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(card_box)

	var quote_mark := Label.new()
	quote_mark.text = "“"
	quote_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quote_mark.add_theme_font_size_override("font_size", 72)
	quote_mark.add_theme_color_override("font_color", ACCENT_SOFT)
	card_box.add_child(quote_mark)

	_line_label = RichTextLabel.new()
	_line_label.bbcode_enabled = true
	_line_label.fit_content = true
	_line_label.scroll_active = false
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 不再硬设 custom_minimum_size.x。之前 720 会绕过 autowrap、让长段子把整个 panel
	# 顶出 minigame 窗口；改用 EXPAND_FILL 让 autowrap 根据实际父容器宽度工作。
	_line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_label.add_theme_font_size_override("normal_font_size", 40)
	_line_label.add_theme_color_override("default_color", TEXT_CARD)
	card_box.add_child(_line_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	frame_box.add_child(_status_label)

	_feedback_label = Label.new()
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_font_size_override("font_size", 26)
	_feedback_label.add_theme_color_override("font_color", ACCENT)
	_feedback_label.modulate.a = 0.0
	_feedback_label.custom_minimum_size = Vector2(0, 30)
	frame_box.add_child(_feedback_label)

	_option_row = HBoxContainer.new()
	_option_row.add_theme_constant_override("separation", 16)
	_option_row.alignment = BoxContainer.ALIGNMENT_CENTER
	frame_box.add_child(_option_row)

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)


func _build_hud_chip(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label


func _normalize_items(raw_items: Variant) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if not raw_items is Array:
		return items
	for raw_item in raw_items:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = _normalize_item(raw_item)
		if item.is_empty():
			continue
		items.append(item)
	return items


func _normalize_item(raw_item: Dictionary) -> Dictionary:
	var line: String = str(raw_item.get("line", "")).strip_edges()
	var correct_emotion: String = str(raw_item.get("correct_emotion", "")).strip_edges()
	if line.is_empty() or correct_emotion.is_empty():
		return {}

	var options: Array[String] = []
	var raw_options: Variant = raw_item.get("options", [])
	if raw_options is Array:
		for raw_option in raw_options:
			var option: String = str(raw_option).strip_edges()
			if option.is_empty() or option in options:
				continue
			options.append(option)
	if correct_emotion not in options:
		options.append(correct_emotion)
	if options.size() < MIN_OPTION_COUNT:
		for fallback in ["期待", "委屈", "冷淡", "愤怒", "犹豫"]:
			if fallback in options:
				continue
			options.append(fallback)
			if options.size() >= MIN_OPTION_COUNT:
				break

	var shuffled_options: Array[String] = options.duplicate()
	shuffled_options.shuffle()

	return {
		"speaker": str(raw_item.get("speaker", "")).strip_edges(),
		"line": line,
		"correct_emotion": correct_emotion,
		"options": shuffled_options,
	}


func _build_fallback_items() -> Array[Dictionary]:
	return [
		_normalize_item({
			"speaker": "赛琳",
			"line": "你为什么每次都这样？",
			"correct_emotion": "委屈",
			"options": ["愤怒", "委屈", "担忧", "冷淡", "期待"],
		}),
		_normalize_item({
			"speaker": "阿尔诺",
			"line": "我不是故意瞒着你，我只是没想好怎么说。",
			"correct_emotion": "犹豫",
			"options": ["犹豫", "骄傲", "释然", "冷淡", "欣喜"],
		}),
		_normalize_item({
			"speaker": "旁白",
			"line": "风从露台边灌进来，谁都没先把视线挪开。",
			"correct_emotion": "焦虑",
			"options": ["欣喜", "焦虑", "安心", "期待", "冷淡"],
		}),
		_normalize_item({
			"speaker": "赛琳",
			"line": "……算了，你至少先回来就好。",
			"correct_emotion": "安心",
			"options": ["愤怒", "安心", "绝望", "口是心非", "骄傲"],
		}),
		_normalize_item({
			"speaker": "阿尔诺",
			"line": "你别总把所有事都揽到自己身上。",
			"correct_emotion": "担忧",
			"options": ["担忧", "冷淡", "欣喜", "期待", "绝望"],
		}),
		_normalize_item({
			"speaker": "旁白",
			"line": "她明明想追问，却还是先把手松开了。",
			"correct_emotion": "口是心非",
			"options": ["感激", "口是心非", "释然", "骄傲", "欣喜"],
		}),
	]


func _render_current_item() -> void:
	if _current_index >= _items.size():
		_finish_game()
		return

	var item: Dictionary = _items[_current_index]
	var speaker: String = str(item.get("speaker", "")).strip_edges()
	if speaker.is_empty():
		speaker = "旁白"
	_speaker_label.text = speaker
	_line_label.text = "[center][color=#0f172a]%s[/color][/center]" % str(item.get("line", "")).strip_edges()
	_status_label.text = "这句更像什么情绪？"
	_status_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	_feedback_label.text = ""
	_feedback_label.modulate.a = 0.0
	_progress_label.text = "第 %d / %d 题" % [_current_index + 1, _items.size()]
	_combo_label.text = "连中 x%d" % _combo
	_combo_label.modulate = SUCCESS if _combo > 0 else TEXT_SECONDARY
	_update_progress_bar()

	for child in _option_row.get_children():
		child.queue_free()
	_option_buttons.clear()

	var options: Array = item.get("options", [])
	for raw_option in options:
		var option: String = str(raw_option).strip_edges()
		if option.is_empty():
			continue
		var button := Button.new()
		button.text = option
		button.custom_minimum_size = Vector2(104, 64)
		button.add_theme_font_size_override("font_size", 22)
		button.focus_mode = Control.FOCUS_NONE
		_apply_option_style(button, BG_OPTION, BORDER_SOFT, TEXT_CARD)
		var hover_sb: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
		hover_sb.bg_color = BG_OPTION_HOVER
		hover_sb.border_color = ACCENT
		hover_sb.set_border_width_all(2)
		hover_sb.shadow_color = Color(99.0 / 255.0, 102.0 / 255.0, 241.0 / 255.0, 0.18)
		hover_sb.shadow_size = 10
		hover_sb.shadow_offset = Vector2(0, 4)
		button.add_theme_stylebox_override("hover", hover_sb)
		button.add_theme_stylebox_override("pressed", hover_sb)
		button.pressed.connect(_on_option_pressed.bind(option))
		_option_row.add_child(button)
		_option_buttons.append(button)

	_play_card_transition()


func _apply_option_style(button: Button, bg_color: Color, border_color: Color, font_color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.1)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("disabled", sb)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_color)


func _on_option_pressed(selected_option: String) -> void:
	if _locked or _current_index >= _items.size():
		return
	_locked = true

	var item: Dictionary = _items[_current_index]
	var correct_emotion: String = str(item.get("correct_emotion", "")).strip_edges()
	var is_correct: bool = selected_option == correct_emotion
	if is_correct:
		_correct_count += 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_status_label.text = "命中：这句更偏「%s」。" % correct_emotion
		_status_label.add_theme_color_override("font_color", SUCCESS)
		_show_feedback_badge(_combo)
		_play_feedback_flash(SUCCESS)
	else:
		_combo = 0
		_status_label.text = "偏了一点，林夏会把它看成「%s」。" % correct_emotion
		_status_label.add_theme_color_override("font_color", DANGER)
		_show_feedback_badge(0, false)
		_play_feedback_flash(DANGER)

	for button in _option_buttons:
		button.disabled = true
		if button.text == correct_emotion:
			_apply_option_style(button, BG_OPTION_CORRECT, SUCCESS, SUCCESS_DARK)
		elif button.text == selected_option:
			_apply_option_style(button, BG_OPTION_WRONG, DANGER, DANGER_DARK)
		else:
			_apply_option_style(button, BG_OPTION, BORDER_SOFT, TEXT_DIM)

	_combo_label.text = "连中 x%d" % _combo
	_combo_label.modulate = SUCCESS if _combo > 0 else TEXT_SECONDARY

	# Visual pop and lock in
	for btn in _option_buttons:
		if btn.text == selected_option:
			btn.pivot_offset = btn.size / 2.0
			var btn_tween := create_tween()
			btn_tween.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			btn_tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			btn_tween.tween_property(btn, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(ADVANCE_DELAY_SECONDS).timeout
	if not _running:
		return
	_status_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	_current_index += 1
	_locked = false
	_render_current_item()


func _update_progress_bar() -> void:
	if _progress_fill == null:
		return
	var total_items: int = maxi(1, _items.size())
	var ratio: float = float(_current_index) / float(total_items)
	var target_x: float = maxf(8.0, 178.0 * ratio) if _current_index > 0 else 0.0
	
	if target_x == 0.0:
		_progress_fill.size.x = 0.0
	else:
		var tween := create_tween()
		tween.tween_property(_progress_fill, "size:x", target_x, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_card_transition() -> void:
	if _frame_panel == null:
		return
	_frame_panel.modulate = Color(1, 1, 1, 0.0)
	_frame_panel.scale = Vector2(0.96, 0.96)
	_frame_panel.position.y += 15  # Slight rise up
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_frame_panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_frame_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_frame_panel, "position:y", _frame_panel.position.y - 15, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _show_feedback_badge(combo_value: int, passed: bool = true) -> void:
	if _feedback_label == null:
		return
	if not passed:
		_feedback_label.text = "偏了"
		_feedback_label.add_theme_color_override("font_color", DANGER)
	elif combo_value >= 5:
		_feedback_label.text = "共鸣 x%d" % combo_value
		_feedback_label.add_theme_color_override("font_color", ACCENT)
	elif combo_value >= 3:
		_feedback_label.text = "连中 x%d" % combo_value
		_feedback_label.add_theme_color_override("font_color", SUCCESS)
	else:
		_feedback_label.text = "命中"
		_feedback_label.add_theme_color_override("font_color", SUCCESS)
	_feedback_label.modulate.a = 1.0
	_feedback_label.scale = Vector2(1.2, 1.2)
	_feedback_label.position.y = 0  # Reset drift relative base
	
	var tween := create_tween()
	tween.set_parallel(true)
	# pop in
	tween.tween_property(_feedback_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# drift up
	tween.tween_property(_feedback_label, "position:y", -10.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# fade out slightly delayed
	tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.3).set_delay(0.3)


func _play_feedback_flash(color: Color) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.10, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(_flash_rect, "color:a", 0.0, 0.25).set_ease(Tween.EASE_OUT)


func _finish_game() -> void:
	var total_items: int = maxi(1, _items.size())
	var score: float = float(_correct_count) / float(total_items)
	var result: Dictionary = {
		"score": score,
		"accuracy": score,
		"total_items": total_items,
		"correct_count": _correct_count,
		"max_combo": _max_combo,
		"scene_brief": _scene_brief,
		"review_type_desc": REVIEW_TYPE_DESC,
		"review_performance_desc": _build_review_performance_desc(score, _correct_count, total_items, _max_combo),
	}
	var stats: Array[String] = []
	stats.append("命中 %d / %d 条台词" % [_correct_count, total_items])
	if _max_combo >= 2:
		stats.append("最大连中 x%d" % _max_combo)
	present_summary_and_finish({
		"title": "情绪校对完成",
		"subtitle": "已把这批台词的情感基调交给林夏",
		"stats": stats,
		"result": result,
	})


func _build_review_performance_desc(score: float, correct_count: int, total_items: int, max_combo: int) -> String:
	if score >= 0.9:
		return "你几乎把这批句子的情绪都听准了，%d/%d 句没有跑偏，连着几次都抓得很稳。" % [correct_count, total_items]
	if score >= 0.7:
		return "你大部分都判断对了，%d/%d 句抓到了情绪落点，已经很接近这场戏真正的味道了。" % [correct_count, total_items]
	if score >= 0.5:
		return "你先听出了 %d/%d 句的情绪，方向有了，但还有几句卡在更微妙的地方。" % [correct_count, total_items]
	if max_combo >= 2:
		return "你偶尔能抓到一两句的情绪，但整体还不太稳，只有 %d/%d 句判断到位。" % [correct_count, total_items]
	return "这批句子的情绪你还没完全听准，目前只有 %d/%d 句对上了感觉。" % [correct_count, total_items]
