extends MinigameBase
## 创意决策小游戏
##
## 替代旧的 chat_topic 讨论流程。
## 每轮由 LLM 生成一个创意问题 + 2~3 个选项，玩家选择或自由输入。
## 固定轮次后自动结束，所有决策汇总为 result 传给后续 KB 工单。

const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")

const LLM_ROLE: String = "creative_decision"
const LLM_FALLBACK_ROLES: Array[String] = ["chat_default"]
const SYSTEM_PROMPT_KEY: String = "minigame_creative_decision_system"

const DEFAULT_TOTAL_ROUNDS: int = 4
const MIN_OPTIONS: int = 2
const MAX_OPTIONS: int = 3
const OPTION_KEYS: Array[String] = ["A", "B", "C"]

const COLOR_BG := Color("#f5f7fb")
const COLOR_PANEL := Color("#ffffff")
const COLOR_CARD := Color("#ffffff")
const COLOR_CARD_HOVER := Color("#eef2ff")
const COLOR_CARD_SELECTED := Color("#eef2ff")
const COLOR_CARD_BORDER := Color("#e5e7eb")
const COLOR_CARD_SELECTED_BORDER := Color("#6366f1")
const COLOR_CARD_SHADOW := Color(0.34, 0.38, 0.51, 0.15)
const COLOR_TEXT := Color("#0f172a")
const COLOR_TEXT_MUTED := Color("#64748b")
const COLOR_TEXT_DETAIL := Color("#475569")
const COLOR_ACCENT := Color("#6366f1")
const COLOR_ACCENT_SOFT := Color("#e0e7ff")
const COLOR_PROGRESS_BG := Color("#e5e7eb")
const COLOR_INPUT_BG := Color("#ffffff")
const COLOR_INPUT_BORDER := Color("#cbd5e1")
const COLOR_BTN_PRIMARY := Color("#10b981")
const COLOR_BTN_PRIMARY_HOVER := Color("#059669")
const COLOR_BUBBLE_BORDER := Color("#a78bfa")

#region 状态
var _llm_service: ActivityOptionLLMService = null
var _total_rounds: int = DEFAULT_TOTAL_ROUNDS
var _current_round: int = 0
var _decisions: Array[Dictionary] = []
var _conversation_history: Array[Dictionary] = []
var _current_options: Array[Dictionary] = []
var _selected_index: int = -1
var _waiting_for_llm: bool = false
var _goal_description: String = ""
var _system_prompt: String = ""
var _extra_role_context: String = ""
var _kb_context: String = ""
var _pending_request_id: String = ""
#endregion

#region UI 引用
var _root_container: VBoxContainer = null
var _header_label: Label = null
var _question_label: Label = null
var _reaction_bubble: PanelContainer = null
var _reaction_label: Label = null
var _options_container: VBoxContainer = null
var _option_buttons: Array[Control] = []
var _custom_input: LineEdit = null
var _confirm_button: Button = null
var _progress_bar: ProgressBar = null
var _loading_label: Label = null
var _button_row: HBoxContainer = null
var _dots_timer: Timer = null
var _dots_frame: int = 0
var _loading_base_text: String = "林夏正在思考"
#endregion


func _on_minigame_start() -> void:
	_parse_config()
	_setup_llm()
	_build_ui()
	_request_first_round()


func _on_minigame_cleanup() -> void:
	if _llm_service != null:
		_llm_service.clear_pending_requests()


#region 配置解析
func _parse_config() -> void:
	_total_rounds = int(task_data.get("rounds", DEFAULT_TOTAL_ROUNDS))
	if _total_rounds < 2:
		_total_rounds = 2
	if _total_rounds > 8:
		_total_rounds = 8

	var topic_config: Dictionary = task_data.get("topic_config", {})
	_goal_description = str(topic_config.get("goal_description", str(task_data.get("description", "")))).strip_edges()

	# DSL 格式规格必须由小游戏本身强制掌控，不能被 topic_config.system_prompt 覆盖。
	# 若 topic_config 里带了额外角色/语气信息，留作 user prompt 里的辅助上下文。
	_system_prompt = _build_default_system_prompt()
	_extra_role_context = str(topic_config.get("system_prompt", "")).strip_edges()

	_kb_context = _gather_kb_context()
#endregion


#region LLM 服务
func _setup_llm() -> void:
	_llm_service = ActivityOptionLLMServiceClass.new()
	_llm_service.name = "CreativeDecisionLLM"
	add_child(_llm_service)
	_llm_service.request_completed.connect(_on_llm_completed)
	_llm_service.request_failed.connect(_on_llm_failed)
	_llm_service.configure(
		"CreativeDecisionLLM",
		LLM_ROLE,
		LLM_FALLBACK_ROLES,
		{},
		{
			"temperature": 0.7,
		}
	)


func _build_default_system_prompt() -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_prompt(SYSTEM_PROMPT_KEY):
		var resolved: String = str(pm.resolve(SYSTEM_PROMPT_KEY)).strip_edges()
		if not resolved.is_empty():
			return resolved
	return _inline_default_system_prompt()


func _inline_default_system_prompt() -> String:
	return """你是一个游戏开发搭档（林夏），正在和玩家一起做创意决策。

规则：
- 用口语化的短句，不要用 markdown、不要用 JSON。
- 每轮严格按下面的 DSL 输出，不要输出任何 DSL 之外的文字。
- reaction 是对上一轮选择的一句话反应（第一轮写 `reaction:` 留空）。
- question 是本轮要讨论的创意问题。
- option 提供 2~3 个方向，KEY 依次为 A / B / C。
- option 的 title 不超过 8 个字，detail 不超过 20 个字。

DSL 格式（每行一个字段，不要空行，不要 code fence）：
reaction: <上一轮反应，第一轮留空>
question: <本轮要讨论的问题>
option A | <方向名> | <简短说明>
option B | <方向名> | <简短说明>
option C | <方向名> | <简短说明>   (可选)"""


func _build_round_prompt(player_choice: Dictionary = {}) -> String:
	var parts: PackedStringArray = []

	if not _extra_role_context.is_empty():
		parts.append("【角色与语气补充】\n%s" % _extra_role_context)

	if not _kb_context.is_empty():
		parts.append("【当前项目背景】\n%s" % _kb_context)

	parts.append("【讨论目标】\n%s" % _goal_description)
	parts.append("【当前进度】第 %d/%d 轮" % [_current_round + 1, _total_rounds])

	if not _decisions.is_empty():
		var history_lines: PackedStringArray = []
		for i in range(_decisions.size()):
			var d: Dictionary = _decisions[i]
			var choice_text: String = str(d.get("choice_text", ""))
			history_lines.append("第%d轮：%s" % [i + 1, choice_text])
		parts.append("【已做决策】\n%s" % "\n".join(history_lines))

	if not player_choice.is_empty():
		var choice_type: String = str(player_choice.get("type", ""))
		if choice_type == "custom":
			parts.append("【玩家本轮选择】自由输入：%s" % str(player_choice.get("text", "")))
		else:
			parts.append("【玩家本轮选择】%s. %s" % [
				str(player_choice.get("key", "")),
				str(player_choice.get("title", "")),
			])

	if _current_round >= _total_rounds - 1:
		parts.append("这是最后一轮，请在 question 中做一个简短总结性提问，帮助收束讨论。")

	parts.append("请输出本轮的 DSL（严格遵守 system prompt 里的 DSL 格式，不要输出 DSL 以外的任何文字）：")
	return "\n\n".join(parts)


func _request_first_round() -> void:
	_current_round = 0
	_set_loading(true)
	var prompt: String = _build_round_prompt()
	_pending_request_id = _llm_service.request_text(prompt, _system_prompt, {"round": 0})
	if _pending_request_id.is_empty():
		_handle_llm_failure("LLM 服务不可用，使用默认问题")


func _request_next_round(player_choice: Dictionary) -> void:
	_set_loading(true)
	var prompt: String = _build_round_prompt(player_choice)
	_pending_request_id = _llm_service.request_text(prompt, _system_prompt, {"round": _current_round})
	if _pending_request_id.is_empty():
		_handle_llm_failure("LLM 服务不可用，使用默认问题")


func _on_llm_completed(request_id: String, _context: Dictionary, raw_text: String, _response: Dictionary) -> void:
	if request_id != _pending_request_id:
		return
	_pending_request_id = ""
	_debug_log_raw(raw_text)
	var parsed: Dictionary = _parse_llm_response(raw_text)
	_show_round(parsed)


func _debug_log_raw(raw_text: String) -> void:
	var config_mgr := AIConfigManager.get_instance()
	if config_mgr != null and config_mgr.is_quiet_logs_enabled():
		return
	print("[CreativeDecision] raw (round %d):\n%s" % [_current_round + 1, raw_text])


func _on_llm_failed(request_id: String, _context: Dictionary, error_message: String, _error_code: int) -> void:
	if request_id != _pending_request_id:
		return
	_pending_request_id = ""
	print("[CreativeDecision] LLM failed: %s" % error_message)
	_handle_llm_failure(error_message)


func _handle_llm_failure(reason: String) -> void:
	print("[CreativeDecision] Using fallback for round %d: %s" % [_current_round + 1, reason])
	_show_round({
		"reaction": "",
		"question": "你觉得接下来应该怎么推进？（%s）" % _goal_description,
		"options": [
			{"key": "A", "title": "先这样吧", "detail": "按目前的方向继续"},
			{"key": "B", "title": "换个思路", "detail": "从另一个角度切入"},
		],
	})


func _parse_llm_response(raw_text: String) -> Dictionary:
	# 行导向 DSL 解析器：
	#   reaction: ...
	#   question: ...
	#   option A | title | detail
	#   option B | title | detail
	# 忽略前后空行、markdown code fence、以及无法识别的行。
	# 对 JSON 风格的回退：如果整段看起来是一个 JSON 对象，尝试按 JSON 解析作为兼容。
	var text: String = raw_text.strip_edges()
	if text.is_empty():
		return {}

	# 剥离 markdown code fence
	if text.begins_with("```"):
		var first_newline: int = text.find("\n")
		if first_newline >= 0:
			text = text.substr(first_newline + 1)
		if text.ends_with("```"):
			text = text.substr(0, text.length() - 3).strip_edges()

	var reaction: String = ""
	var question: String = ""
	var options: Array[Dictionary] = []

	for raw_line in text.split("\n"):
		var line: String = str(raw_line).strip_edges()
		if line.is_empty():
			continue
		var lower: String = line.to_lower()
		if lower.begins_with("reaction:") or lower.begins_with("reaction："):
			reaction = _strip_label(line, ["reaction:", "reaction："])
			continue
		if lower.begins_with("question:") or lower.begins_with("question："):
			question = _strip_label(line, ["question:", "question："])
			continue
		if lower.begins_with("option"):
			var opt: Dictionary = _parse_option_line(line, options.size())
			if not opt.is_empty():
				options.append(opt)
			continue
		# 其它行直接忽略，容忍 LLM 多嘴

	if options.size() < MIN_OPTIONS:
		# 兼容 fallback：尝试 JSON 解析（向后兼容旧模型输出）
		var json_result: Dictionary = _parse_json_fallback(text)
		if not json_result.is_empty():
			return json_result
		return {}

	if options.size() > MAX_OPTIONS:
		options = options.slice(0, MAX_OPTIONS)

	return {
		"reaction": reaction,
		"question": question,
		"options": options,
	}


func _strip_label(line: String, labels: Array) -> String:
	for label in labels:
		var label_str: String = str(label)
		if line.to_lower().begins_with(label_str.to_lower()):
			return line.substr(label_str.length()).strip_edges()
	return line.strip_edges()


func _parse_option_line(line: String, fallback_index: int) -> Dictionary:
	# 支持：`option A | title | detail`，也兼容全角竖线 `｜` 与中英文冒号。
	# 先剥掉前缀 "option" / "选项"。
	var body: String = line
	var prefixes: Array[String] = ["option ", "option\t", "option:", "option：", "选项 ", "选项\t", "选项:", "选项："]
	for prefix in prefixes:
		if body.to_lower().begins_with(prefix.to_lower()):
			body = body.substr(prefix.length()).strip_edges()
			break
	if body.to_lower().begins_with("option"):
		body = body.substr(len("option")).strip_edges()

	# 全角竖线 → 半角
	body = body.replace("｜", "|")
	var parts: PackedStringArray = body.split("|", false)
	if parts.size() < 2:
		return {}

	var key: String = str(parts[0]).strip_edges().to_upper()
	# 去掉 key 末尾可能的 ":" "." 等
	while not key.is_empty() and (key.ends_with(":") or key.ends_with("：") or key.ends_with(".") or key.ends_with("、")):
		key = key.substr(0, key.length() - 1).strip_edges().to_upper()
	if key.is_empty() or key.length() > 2:
		key = OPTION_KEYS[fallback_index] if fallback_index < OPTION_KEYS.size() else str(fallback_index + 1)

	var title: String = str(parts[1]).strip_edges()
	var detail: String = ""
	if parts.size() >= 3:
		# 把第 3 段及之后的全部合回去，允许 detail 内部出现 |
		var rest: Array[String] = []
		for i in range(2, parts.size()):
			rest.append(str(parts[i]).strip_edges())
		detail = " ".join(rest).strip_edges()

	if title.is_empty():
		title = "选项%s" % key
	return {
		"key": key,
		"title": title,
		"detail": detail,
	}


func _parse_json_fallback(text: String) -> Dictionary:
	# 兼容旧 JSON 输出：只在 DSL 解析失败时才尝试。
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		var json_start: int = text.find("{")
		var json_end: int = text.rfind("}")
		if json_start >= 0 and json_end > json_start:
			parsed = JSON.parse_string(text.substr(json_start, json_end - json_start + 1))
		if not parsed is Dictionary:
			return {}
	var result: Dictionary = parsed as Dictionary
	var raw_options: Array = result.get("options", [])
	var valid_options: Array[Dictionary] = []
	for i in range(mini(raw_options.size(), MAX_OPTIONS)):
		var opt: Variant = raw_options[i]
		if opt is Dictionary:
			var key: String = str((opt as Dictionary).get("key", OPTION_KEYS[i] if i < OPTION_KEYS.size() else str(i + 1)))
			valid_options.append({
				"key": key,
				"title": str((opt as Dictionary).get("title", "选项%s" % key)),
				"detail": str((opt as Dictionary).get("detail", "")),
			})
	if valid_options.size() < MIN_OPTIONS:
		return {}
	return {
		"reaction": str(result.get("reaction", "")),
		"question": str(result.get("question", "")),
		"options": valid_options,
	}
#endregion


#region UI 构建
func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 外层居中
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_root_container = VBoxContainer.new()
	_root_container.custom_minimum_size = Vector2(560, 0)
	_root_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_root_container.add_theme_constant_override("separation", 16)
	center.add_child(_root_container)

	# 标题行
	_header_label = Label.new()
	_header_label.text = "创意决策 · 准备中..."
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 28)
	_header_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_root_container.add_child(_header_label)

	# 林夏反应气泡（上一轮反馈）
	_reaction_bubble = PanelContainer.new()
	_reaction_bubble.visible = false
	var bubble_sb := StyleBoxFlat.new()
	bubble_sb.bg_color = COLOR_ACCENT_SOFT
	bubble_sb.border_color = COLOR_BUBBLE_BORDER
	bubble_sb.border_width_left = 4
	bubble_sb.set_corner_radius_all(10)
	bubble_sb.content_margin_left = 14
	bubble_sb.content_margin_right = 14
	bubble_sb.content_margin_top = 10
	bubble_sb.content_margin_bottom = 10
	_reaction_bubble.add_theme_stylebox_override("panel", bubble_sb)
	_root_container.add_child(_reaction_bubble)

	_reaction_label = Label.new()
	_reaction_label.text = ""
	_reaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reaction_label.add_theme_font_size_override("font_size", 20)
	_reaction_label.add_theme_color_override("font_color", Color("#3730a3"))
	_reaction_bubble.add_child(_reaction_label)

	# 问题
	_question_label = Label.new()
	_question_label.text = ""
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.add_theme_font_size_override("font_size", 26)
	_question_label.add_theme_color_override("font_color", COLOR_TEXT)
	_root_container.add_child(_question_label)

	# 选项容器
	_options_container = VBoxContainer.new()
	_options_container.add_theme_constant_override("separation", 8)
	_root_container.add_child(_options_container)

	# 自定义输入
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	_root_container.add_child(input_row)

	_custom_input = LineEdit.new()
	_custom_input.placeholder_text = "或者你有别的想法..."
	_custom_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_input.custom_minimum_size = Vector2(0, 46)
	_custom_input.add_theme_font_size_override("font_size", 20)
	_custom_input.add_theme_color_override("font_color", COLOR_TEXT)
	_custom_input.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED)
	var input_sb := StyleBoxFlat.new()
	input_sb.bg_color = COLOR_INPUT_BG
	input_sb.border_color = COLOR_INPUT_BORDER
	input_sb.set_border_width_all(1)
	input_sb.set_corner_radius_all(10)
	input_sb.content_margin_left = 14
	input_sb.content_margin_right = 14
	input_sb.content_margin_top = 8
	input_sb.content_margin_bottom = 8
	_custom_input.add_theme_stylebox_override("normal", input_sb)
	var input_focus_sb := input_sb.duplicate() as StyleBoxFlat
	input_focus_sb.border_color = COLOR_ACCENT
	input_focus_sb.set_border_width_all(2)
	_custom_input.add_theme_stylebox_override("focus", input_focus_sb)
	_custom_input.text_changed.connect(_on_custom_input_changed)
	_custom_input.text_submitted.connect(_on_custom_input_submitted)
	input_row.add_child(_custom_input)

	# 按钮行
	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 12)
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_root_container.add_child(_button_row)

	_confirm_button = Button.new()
	_confirm_button.text = "确定"
	_confirm_button.custom_minimum_size = Vector2(140, 52)
	_confirm_button.add_theme_font_size_override("font_size", 22)
	_confirm_button.disabled = true
	_style_pill_button(_confirm_button, COLOR_BTN_PRIMARY, COLOR_BTN_PRIMARY_HOVER, Color("#ffffff"))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_button_row.add_child(_confirm_button)

	# 进度条
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.show_percentage = false
	_progress_bar.value = 0.0
	_progress_bar.max_value = 100.0
	var progress_bg_sb := StyleBoxFlat.new()
	progress_bg_sb.bg_color = COLOR_PROGRESS_BG
	progress_bg_sb.set_corner_radius_all(5)
	_progress_bar.add_theme_stylebox_override("background", progress_bg_sb)
	var progress_fill_sb := StyleBoxFlat.new()
	progress_fill_sb.bg_color = COLOR_ACCENT
	progress_fill_sb.set_corner_radius_all(5)
	_progress_bar.add_theme_stylebox_override("fill", progress_fill_sb)
	_root_container.add_child(_progress_bar)

	# 加载提示
	_loading_label = Label.new()
	_loading_label.text = _loading_base_text
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 20)
	_loading_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_loading_label.visible = false
	_root_container.add_child(_loading_label)

	# 思考 dots 定时器
	_dots_timer = Timer.new()
	_dots_timer.wait_time = 0.35
	_dots_timer.autostart = false
	_dots_timer.one_shot = false
	_dots_timer.timeout.connect(_on_dots_tick)
	add_child(_dots_timer)

	# 按钮 hover
	_attach_button_hover(_confirm_button, 1.04)
#endregion


func _style_pill_button(btn: Button, base: Color, hover: Color, text_color: Color) -> void:
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = base
	normal_sb.set_corner_radius_all(26)
	normal_sb.content_margin_left = 22
	normal_sb.content_margin_right = 22
	normal_sb.content_margin_top = 12
	normal_sb.content_margin_bottom = 12
	normal_sb.shadow_color = Color(base.r, base.g, base.b, 0.35)
	normal_sb.shadow_size = 6
	normal_sb.shadow_offset = Vector2(0, 3)

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = hover

	var pressed_sb := normal_sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = hover
	pressed_sb.shadow_size = 2

	var disabled_sb := normal_sb.duplicate() as StyleBoxFlat
	disabled_sb.bg_color = Color("#cbd5e1")
	disabled_sb.shadow_size = 0

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)
	btn.add_theme_color_override("font_disabled_color", Color("#94a3b8"))


func _attach_button_hover(node: Control, target_scale: float) -> void:
	if node == null:
		return
	node.pivot_offset = node.size / 2.0
	node.mouse_entered.connect(func() -> void:
		if node is BaseButton and (node as BaseButton).disabled:
			return
		node.pivot_offset = node.size / 2.0
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector2(target_scale, target_scale), 0.12).set_trans(Tween.TRANS_QUAD)
	)
	node.mouse_exited.connect(func() -> void:
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)
	)


func _attach_card_hover(card: Control) -> void:
	card.mouse_entered.connect(func() -> void:
		if _waiting_for_llm:
			return
		card.pivot_offset = card.size / 2.0
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2(1.02, 1.02), 0.12).set_trans(Tween.TRANS_QUAD)
	)
	card.mouse_exited.connect(func() -> void:
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)
	)


func _bounce_card(card: Control) -> void:
	card.pivot_offset = card.size / 2.0
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2(1.06, 1.06), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _start_dots() -> void:
	if _dots_timer == null:
		return
	_dots_frame = 0
	if _dots_timer.is_stopped():
		_dots_timer.start()


func _stop_dots() -> void:
	if _dots_timer != null and not _dots_timer.is_stopped():
		_dots_timer.stop()
	_dots_frame = 0
	if _loading_label != null:
		_loading_label.text = _loading_base_text


func _on_dots_tick() -> void:
	if _loading_label == null:
		return
	_dots_frame = (_dots_frame + 1) % 4
	_loading_label.text = "%s%s" % [_loading_base_text, ".".repeat(_dots_frame)]


#region UI 更新
func _show_round(data: Dictionary) -> void:
	_set_loading(false)
	if data.is_empty():
		_handle_llm_failure("LLM 返回了无效数据")
		return

	var reaction: String = str(data.get("reaction", "")).strip_edges()
	var question: String = str(data.get("question", "")).strip_edges()
	_current_options = []
	var raw_options: Array = data.get("options", [])
	for opt in raw_options:
		if opt is Dictionary:
			_current_options.append(opt as Dictionary)

	# 更新 UI
	_header_label.text = "创意决策 · 第 %d/%d 轮" % [_current_round + 1, _total_rounds]

	if not reaction.is_empty():
		_reaction_label.text = "林夏：%s" % reaction
		_reaction_bubble.visible = true
	else:
		_reaction_bubble.visible = false

	_question_label.text = question if not question.is_empty() else _goal_description
	_progress_bar.value = float(_current_round) / float(_total_rounds) * 100.0

	# 重建选项
	_rebuild_option_cards()
	_selected_index = -1
	_custom_input.text = ""
	_confirm_button.disabled = true


func _rebuild_option_cards() -> void:
	for child in _options_container.get_children():
		child.queue_free()
	_option_buttons.clear()

	for i in range(_current_options.size()):
		var opt: Dictionary = _current_options[i]
		var card := _create_option_card(i, opt)
		_options_container.add_child(card)
		_option_buttons.append(card)
		# 进场淡入：每张卡片错开 0.05s
		card.modulate.a = 0.0
		card.position.y += 6.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.22).set_delay(i * 0.06)
		tw.tween_property(card, "position:y", card.position.y - 6.0, 0.22).set_delay(i * 0.06).set_trans(Tween.TRANS_QUAD)


func _create_option_card(index: int, opt: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 56)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("option_index", index)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD
	style.border_color = COLOR_CARD_BORDER
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.shadow_color = COLOR_CARD_SHADOW
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var key: String = str(opt.get("key", OPTION_KEYS[index] if index < OPTION_KEYS.size() else str(index + 1)))
	var title_label := Label.new()
	title_label.text = "%s. %s" % [key, str(opt.get("title", ""))]
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	var detail: String = str(opt.get("detail", "")).strip_edges()
	if not detail.is_empty():
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.add_theme_font_size_override("font_size", 18)
		detail_label.add_theme_color_override("font_color", COLOR_TEXT_DETAIL)
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(detail_label)

	card.gui_input.connect(_on_option_card_input.bind(index))
	_attach_card_hover(card)
	return card


func _set_loading(loading: bool) -> void:
	_waiting_for_llm = loading
	if _loading_label != null:
		_loading_label.visible = loading
	if _options_container != null:
		_options_container.visible = not loading
	if _custom_input != null:
		_custom_input.visible = not loading
		_custom_input.editable = not loading
	if _confirm_button != null:
		_confirm_button.visible = not loading
	if _question_label != null:
		_question_label.visible = not loading
	if loading:
		_start_dots()
	else:
		_stop_dots()


func _update_option_visuals() -> void:
	for i in range(_option_buttons.size()):
		var card: PanelContainer = _option_buttons[i] as PanelContainer
		if card == null:
			continue
		var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		if i == _selected_index:
			style.bg_color = COLOR_CARD_SELECTED
			style.border_color = COLOR_CARD_SELECTED_BORDER
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		else:
			style.bg_color = COLOR_CARD
			style.border_color = COLOR_CARD_BORDER
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
#endregion


#region 交互回调
func _on_option_card_input(event: InputEvent, index: int) -> void:
	if _waiting_for_llm:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_selected_index = index
		_custom_input.text = ""
		_update_option_visuals()
		_confirm_button.disabled = false
		if index < _option_buttons.size():
			_bounce_card(_option_buttons[index])


func _on_custom_input_changed(new_text: String) -> void:
	if not new_text.strip_edges().is_empty():
		_selected_index = -1
		_update_option_visuals()
		_confirm_button.disabled = false
	elif _selected_index < 0:
		_confirm_button.disabled = true


func _on_custom_input_submitted(_text: String) -> void:
	if not _confirm_button.disabled:
		_on_confirm_pressed()


func _on_confirm_pressed() -> void:
	if _waiting_for_llm:
		return

	var player_choice: Dictionary = _build_player_choice()
	if player_choice.is_empty():
		return

	# 记录决策
	_decisions.append({
		"round": _current_round + 1,
		"question": _question_label.text,
		"choice_text": str(player_choice.get("display", "")),
		"choice_type": str(player_choice.get("type", "")),
		"choice_key": str(player_choice.get("key", "")),
	})

	_current_round += 1
	if _current_round >= _total_rounds:
		_finish_game()
		return

	_request_next_round(player_choice)


func _build_player_choice() -> Dictionary:
	var custom_text: String = _custom_input.text.strip_edges()
	if not custom_text.is_empty():
		return {
			"type": "custom",
			"text": custom_text,
			"display": custom_text,
		}

	if _selected_index >= 0 and _selected_index < _current_options.size():
		var opt: Dictionary = _current_options[_selected_index]
		return {
			"type": "option",
			"key": str(opt.get("key", "")),
			"title": str(opt.get("title", "")),
			"display": "%s. %s" % [str(opt.get("key", "")), str(opt.get("title", ""))],
		}

	return {}
#endregion


#region 结算
func _finish_game() -> void:
	var summary: String = _build_decision_summary()
	var result: Dictionary = {
		"score": 1.0,
		"decisions": _decisions.duplicate(true),
		"decision_summary": summary,
		"creative_prompt": summary,
		"total_rounds": _total_rounds,
		"goal_description": _goal_description,
	}
	var stats: Array[String] = []
	stats.append("完成 %d 轮关键决策" % _decisions.size())
	stats.append("创作方向：%s" % _goal_description)
	present_summary_and_finish({
		"title": "创意落椴",
		"subtitle": "和林夏敲定了这条故事线的关键取舍",
		"stats": stats,
		"button_text": "把这个方向写进文档",
		"result": result,
	})


func _build_decision_summary() -> String:
	var lines: PackedStringArray = []
	lines.append("讨论目标：%s" % _goal_description)
	lines.append("共 %d 轮决策：" % _decisions.size())
	for d in _decisions:
		lines.append("- 第%d轮｜%s → %s" % [
			int(d.get("round", 0)),
			str(d.get("question", "")),
			str(d.get("choice_text", "")),
		])
	return "\n".join(lines)
#endregion


#region KB 上下文
func _gather_kb_context() -> String:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_documents"):
		return ""

	var docs: Array = kb.get_documents()
	if docs.is_empty():
		return ""

	var parts: PackedStringArray = []
	var total_chars: int = 0
	for doc in docs:
		if not doc is Dictionary:
			continue
		var doc_dict: Dictionary = doc as Dictionary
		var title: String = str(doc_dict.get("title", "")).strip_edges()
		var content: String = str(doc_dict.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		if total_chars + content.length() > 2000:
			break
		parts.append("[%s] %s" % [title, content.left(400)])
		total_chars += content.length()

	return "\n".join(parts) if not parts.is_empty() else ""
#endregion
