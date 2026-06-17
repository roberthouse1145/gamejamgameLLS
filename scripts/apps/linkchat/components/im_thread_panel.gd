class_name IMThreadPanel
extends PanelContainer
## 可嵌入式 LinkChat 风 IM 线程面板。
##
## 用于小游戏或其它 App 内部的局部 IM 对话，不绑定 ChatManager 频道，
## 但复用 LinkChat 的 MessageBubble、主题、推荐回复 chip 和 NPC 输入延迟。

signal reply_selected(reply: Dictionary)
signal custom_submitted(text: String)
signal presentation_started()
signal presentation_finished()

const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const MessageBubbleClass = preload("res://scripts/apps/linkchat/components/message_bubble.gd")

const DEFAULT_NPC_ID: String = "npc_lin_xia"
const DEFAULT_NPC_NAME: String = "林夏"

var npc_id: String = DEFAULT_NPC_ID
var npc_name: String = DEFAULT_NPC_NAME

var _message_scroll: ScrollContainer = null
var _message_list: VBoxContainer = null
var _typing_indicator: Label = null
var _reply_container: HFlowContainer = null
var _input_area: PanelContainer = null
var _input_field: LineEdit = null
var _send_button: Button = null

var _presentation_token: int = 0
var _presenting: bool = false
var _replies: Array[Dictionary] = []


func _ready() -> void:
	if _message_scroll != null:
		return
	_build_ui()


func setup(p_npc_id: String = DEFAULT_NPC_ID, p_npc_name: String = DEFAULT_NPC_NAME) -> void:
	npc_id = p_npc_id
	npc_name = p_npc_name
	if _message_scroll == null:
		_build_ui()


func clear() -> void:
	if _message_list == null:
		return
	for child in _message_list.get_children():
		child.queue_free()
	set_replies([])
	_set_typing(false)


func append_message(message: Dictionary, play_sound: bool = false) -> void:
	if _message_list == null:
		_build_ui()
	var normalized := _normalize_message(message)
	var bubble := MessageBubbleClass.create(normalized)
	_message_list.add_child(bubble)
	if play_sound:
		_play_chat_sfx(_resolve_sfx_key(normalized))
	_scroll_to_bottom()


func append_player_message(text: String, extras: Dictionary = {}) -> Dictionary:
	var msg := _make_message("player", "你", text, extras)
	append_message(msg, true)
	return msg


func append_npc_message(text: String, extras: Dictionary = {}) -> Dictionary:
	var msg := _make_message(npc_id, npc_name, text, extras)
	append_message(msg, true)
	return msg


## 与 [method present_npc_messages] 相同：先显示“正在输入”再出气泡。调用后请 [code]await presentation_finished[/code]。
func present_player_message(text: String, extras: Dictionary = {}) -> void:
	_presentation_token += 1
	var token := _presentation_token
	_presenting = true
	_set_replies_enabled(false)
	presentation_started.emit()

	var preview_text := str(text).strip_edges()
	if preview_text.is_empty():
		_presenting = false
		presentation_finished.emit()
		return

	_set_typing(true, "你 正在输入...")
	var delay := NPCResponseHandler.calculate_typing_delay(preview_text)
	await get_tree().create_timer(delay).timeout
	if token != _presentation_token:
		return
	_set_typing(false)

	var msg := _make_message("player", "你", preview_text, extras)
	append_message(msg, true)

	if token != _presentation_token:
		return
	_presenting = false
	presentation_finished.emit()


func present_npc_messages(messages: Array, replies: Array = []) -> void:
	_presentation_token += 1
	var token := _presentation_token
	_presenting = true
	_set_replies_enabled(false)
	presentation_started.emit()

	for i in range(messages.size()):
		if token != _presentation_token:
			return
		var msg: Dictionary = _normalize_npc_message(messages[i])
		var preview_text: String = str(msg.get("content", "")).strip_edges()
		_set_typing(true, "%s 正在输入..." % str(msg.get("sender_name", npc_name)))
		var delay := NPCResponseHandler.calculate_typing_delay(preview_text)
		await get_tree().create_timer(delay).timeout
		if token != _presentation_token:
			return
		_set_typing(false)
		append_message(msg, true)
		if i < messages.size() - 1:
			await get_tree().create_timer(randf_range(0.45, 1.2)).timeout

	if token != _presentation_token:
		return
	_presenting = false
	set_replies(replies)
	_set_replies_enabled(true)
	presentation_finished.emit()


func cancel_presentation() -> void:
	_presentation_token += 1
	_presenting = false
	_set_typing(false)
	_set_replies_enabled(true)


func set_replies(replies: Array) -> void:
	_replies.clear()
	for reply in replies:
		if reply is Dictionary:
			_replies.append((reply as Dictionary).duplicate(true))
		else:
			_replies.append({
				"key": "",
				"title": str(reply),
				"subtitle": "",
			})
	_render_replies()


func set_input_enabled(enabled: bool) -> void:
	_set_replies_enabled(enabled and not _presenting)
	if _input_field != null:
		_input_field.editable = enabled and not _presenting
		_input_field.placeholder_text = "等待林夏回复中..." if not enabled or _presenting else "自己说一句..."
	if _send_button != null:
		_send_button.disabled = not enabled or _presenting


func _build_ui() -> void:
	add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_MAIN, 0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_HEADER, 0))
	root.add_child(header)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 22)
	header_margin.add_theme_constant_override("margin_right", 22)
	header_margin.add_theme_constant_override("margin_top", 12)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	header.add_child(header_margin)

	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 2)
	header_margin.add_child(header_box)

	var title := Label.new()
	title.text = "创意讨论室"
	title.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", 24)
	header_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "和林夏把想法聊成可以写进文档的方向"
	subtitle.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	subtitle.add_theme_font_size_override("font_size", 16)
	header_box.add_child(subtitle)

	_message_scroll = ScrollContainer.new()
	_message_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_message_scroll)

	_message_list = VBoxContainer.new()
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_theme_constant_override("separation", 4)
	_message_scroll.add_child(_message_list)

	_typing_indicator = Label.new()
	_typing_indicator.text = ""
	_typing_indicator.visible = false
	_typing_indicator.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT)
	_typing_indicator.add_theme_font_size_override("font_size", 18)
	_typing_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_typing_indicator)

	_reply_container = HFlowContainer.new()
	_reply_container.visible = false
	_reply_container.add_theme_constant_override("h_separation", 8)
	_reply_container.add_theme_constant_override("v_separation", 8)
	root.add_child(_reply_container)

	_input_area = PanelContainer.new()
	_input_area.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_INPUT_AREA, 0))
	root.add_child(_input_area)

	var input_margin := MarginContainer.new()
	input_margin.add_theme_constant_override("margin_left", 16)
	input_margin.add_theme_constant_override("margin_right", 16)
	input_margin.add_theme_constant_override("margin_top", 10)
	input_margin.add_theme_constant_override("margin_bottom", 10)
	_input_area.add_child(input_margin)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	input_margin.add_child(input_row)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "自己说一句..."
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.add_theme_stylebox_override("normal", LCTheme.get_input_field_style())
	_input_field.add_theme_stylebox_override("focus", LCTheme.get_input_field_focus_style())
	_input_field.add_theme_stylebox_override("read_only", LCTheme.get_input_field_disabled_style())
	_input_field.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	_input_field.add_theme_color_override("font_placeholder_color", LCTheme.COLOR_TEXT_MUTED)
	_input_field.add_theme_color_override("caret_color", LCTheme.COLOR_ACCENT)
	_input_field.add_theme_font_size_override("font_size", 18)
	_input_field.text_submitted.connect(_on_input_submitted)
	input_row.add_child(_input_field)

	_send_button = Button.new()
	_send_button.text = "发送"
	_send_button.custom_minimum_size = Vector2(96, 0)
	_send_button.add_theme_stylebox_override("normal", LCTheme.get_send_button_style())
	_send_button.add_theme_stylebox_override("hover", LCTheme.get_send_button_hover_style())
	_send_button.add_theme_stylebox_override("pressed", LCTheme.get_send_button_hover_style())
	_send_button.add_theme_stylebox_override("disabled", LCTheme.get_send_button_style())
	_send_button.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	_send_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_send_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_send_button.add_theme_color_override("font_disabled_color", LCTheme.COLOR_TEXT_MUTED)
	_send_button.add_theme_font_size_override("font_size", 17)
	_send_button.pressed.connect(_on_send_pressed)
	input_row.add_child(_send_button)


func _render_replies() -> void:
	if _reply_container == null:
		return
	for child in _reply_container.get_children():
		child.queue_free()
	if _replies.is_empty():
		_reply_container.visible = false
		return
	for reply in _replies:
		var btn := Button.new()
		var title := str(reply.get("title", "")).strip_edges()
		var subtitle := str(reply.get("subtitle", "")).strip_edges()
		btn.text = title if subtitle.is_empty() else "%s\n%s" % [title, subtitle]
		btn.tooltip_text = subtitle
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
		btn.add_theme_color_override("font_hover_color", LCTheme.COLOR_ACCENT_HOVER)
		btn.add_theme_stylebox_override("normal", LCTheme.get_chip_style())
		btn.add_theme_stylebox_override("hover", LCTheme.get_chip_hover_style())
		btn.add_theme_stylebox_override("pressed", LCTheme.get_chip_hover_style())
		btn.add_theme_stylebox_override("focus", LCTheme.get_chip_hover_style())
		btn.add_theme_stylebox_override("disabled", LCTheme.get_chip_disabled_style())
		btn.add_theme_stylebox_override("disabled_mirrored", LCTheme.get_chip_disabled_style())
		btn.add_theme_color_override("font_disabled_color", LCTheme.COLOR_TEXT_MUTED)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(func() -> void:
			if _presenting:
				return
			reply_selected.emit(reply.duplicate(true))
		)
		_reply_container.add_child(btn)
	_reply_container.visible = true


func _set_replies_enabled(enabled: bool) -> void:
	if _reply_container != null:
		for child in _reply_container.get_children():
			if child is BaseButton:
				(child as BaseButton).disabled = not enabled


func _set_typing(typing: bool, text: String = "") -> void:
	if _typing_indicator == null:
		return
	_typing_indicator.visible = typing
	if not text.is_empty():
		_typing_indicator.text = text


func _make_message(sender_id: String, sender_name: String, content: String, extras: Dictionary = {}) -> Dictionary:
	var msg := {
		"sender_id": sender_id,
		"sender_name": sender_name,
		"content": content,
		"timestamp": int(Time.get_unix_time_from_system()),
		"time": _format_time(),
		"time_phase": _get_current_time_phase_display(),
		"game_day": _get_current_game_day(),
	}
	for key in extras:
		msg[key] = extras[key]
	return msg


func _normalize_message(message: Dictionary) -> Dictionary:
	var msg := message.duplicate(true)
	if not msg.has("sender_id"):
		msg["sender_id"] = str(msg.get("speaker", "system"))
	if not msg.has("sender_name"):
		var sid := str(msg.get("sender_id", ""))
		msg["sender_name"] = "你" if sid == "player" else (npc_name if sid == npc_id else sid)
	if not msg.has("content"):
		msg["content"] = ""
	if not msg.has("time"):
		msg["time"] = _format_time()
	if not msg.has("time_phase"):
		msg["time_phase"] = _get_current_time_phase_display()
	if not msg.has("game_day"):
		msg["game_day"] = _get_current_game_day()
	return msg


func _normalize_npc_message(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		var msg: Dictionary = (raw as Dictionary).duplicate(true)
		if not msg.has("sender_id"):
			msg["sender_id"] = npc_id
		if not msg.has("sender_name"):
			msg["sender_name"] = npc_name
		return _normalize_message(msg)
	return _make_message(npc_id, npc_name, str(raw))


func _on_input_submitted(text: String) -> void:
	_submit_custom_text(text)


func _on_send_pressed() -> void:
	if _input_field == null:
		return
	_submit_custom_text(_input_field.text)


func _submit_custom_text(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or _presenting:
		return
	if _input_field != null:
		_input_field.text = ""
	custom_submitted.emit(trimmed)


func _scroll_to_bottom() -> void:
	if _message_scroll == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var bar := _message_scroll.get_v_scroll_bar()
	if bar != null:
		_message_scroll.scroll_vertical = int(bar.max_value)


func _play_chat_sfx(key: String) -> void:
	if key.is_empty():
		return
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx_key"):
		audio.play_sfx_key(key)


func _resolve_sfx_key(msg: Dictionary) -> String:
	var sender_id := str(msg.get("sender_id", "")).strip_edges()
	if sender_id == "player":
		return "chat_send"
	if sender_id != "system" and not sender_id.is_empty():
		return "chat_receive"
	return ""


func _format_time() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%02d:%02d" % [dt.hour, dt.minute]


func _get_current_game_day() -> int:
	var glm := get_node_or_null("/root/GameLoopManager")
	if glm != null:
		return int(glm.get("current_day"))
	return 0


func _get_current_time_phase_display() -> String:
	var glm := get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_phase_display_name"):
		return str(glm.call("get_phase_display_name", glm.get("time_phase")))
	return ""
