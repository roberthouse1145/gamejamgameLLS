extends PanelContainer
class_name DeepCodeSessionSidebar
## 会话侧边栏 — 管理多个对话 session

signal session_selected(session_id: String)
signal session_created(session_id: String)
signal session_deleted(session_id: String)

@onready var new_session_button: Button = %NewSessionButton
@onready var session_list: VBoxContainer = %SessionList

## {id: String, title: String, messages: Array, created_at: float}
var _sessions: Array[Dictionary] = []
var _active_session_id: String = ""
var _session_buttons: Dictionary = {}  # session_id -> Button


func _ready() -> void:
	# Panel style
	var panel_style := DeepCodeTheme.rounded_flat(DeepCodeTheme.COLOR_BG_SIDEBAR, 0)
	panel_style.border_width_right = 1
	panel_style.border_color = DeepCodeTheme.COLOR_BORDER
	add_theme_stylebox_override("panel", panel_style)

	# New session button style
	if new_session_button:
		var btn_style := DeepCodeTheme.rounded_flat(DeepCodeTheme.COLOR_SURFACE, DeepCodeTheme.RADIUS_SM, DeepCodeTheme.COLOR_BORDER, 1)
		btn_style.content_margin_left = 10
		btn_style.content_margin_top = 8
		btn_style.content_margin_right = 10
		btn_style.content_margin_bottom = 8
		new_session_button.add_theme_stylebox_override("normal", btn_style)
		var hover_style := DeepCodeTheme.rounded_flat(DeepCodeTheme.COLOR_SURFACE_HOVER, DeepCodeTheme.RADIUS_SM, DeepCodeTheme.COLOR_BORDER, 1)
		hover_style.content_margin_left = 10
		hover_style.content_margin_top = 8
		hover_style.content_margin_right = 10
		hover_style.content_margin_bottom = 8
		new_session_button.add_theme_stylebox_override("hover", hover_style)
		new_session_button.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_SECONDARY)
		new_session_button.add_theme_color_override("font_hover_color", DeepCodeTheme.COLOR_TEXT_PRIMARY)
		new_session_button.add_theme_font_size_override("font_size", 13)
		new_session_button.pressed.connect(_on_new_session_pressed)


# ============ Public API ============

## 创建新 session，返回 id。如果已有空 session 则切换到它。
func create_session() -> String:
	# 检查是否已有空 session
	for s in _sessions:
		if s.get("messages", []).is_empty():
			select_session(s.id)
			return s.id

	var sid: String = "session_%d_%d" % [Time.get_ticks_msec(), randi()]
	var session: Dictionary = {
		"id": sid,
		"title": "新对话",
		"messages": [],
		"created_at": Time.get_unix_time_from_system(),
	}
	_sessions.insert(0, session)
	_rebuild_list()
	select_session(sid)
	session_created.emit(sid)
	return sid


## 删除 session
func delete_session(sid: String) -> void:
	for i in range(_sessions.size()):
		if _sessions[i].id == sid:
			_sessions.remove_at(i)
			break

	if _session_buttons.has(sid):
		_session_buttons.erase(sid)

	_rebuild_list()
	session_deleted.emit(sid)

	# 如果删除的是当前 session，切换到第一个或创建新的
	if _active_session_id == sid:
		_active_session_id = ""
		if _sessions.size() > 0:
			select_session(_sessions[0].id)
		else:
			create_session()


## 选中 session
func select_session(sid: String) -> void:
	_active_session_id = sid
	_update_button_states()
	session_selected.emit(sid)


## 获取当前 session id
func get_active_session_id() -> String:
	return _active_session_id


## 获取 session 数据
func get_session(sid: String) -> Dictionary:
	for s in _sessions:
		if s.id == sid:
			return s
	return {}


## 更新 session 的消息（外部调用，用于保存/恢复）
func update_session_messages(sid: String, messages: Array) -> void:
	for s in _sessions:
		if s.id == sid:
			s.messages = messages.duplicate(true)
			# 用第一条用户消息作为标题
			if s.title == "新对话":
				for msg in messages:
					if msg.get("role", "") == "user":
						var title_text: String = msg.get("content", "")
						s.title = title_text.left(20) + ("..." if title_text.length() > 20 else "")
						_rebuild_list()
						break
			break


## 获取所有 session
func get_all_sessions() -> Array[Dictionary]:
	return _sessions


# ============ Internal ============

func _on_new_session_pressed() -> void:
	create_session()


func _rebuild_list() -> void:
	# 清空列表
	for child in session_list.get_children():
		child.queue_free()
	_session_buttons.clear()

	for s in _sessions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)

		# Session button
		var btn := Button.new()
		btn.text = s.get("title", "新对话")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(select_session.bind(s.id))
		_apply_session_button_style(btn, s.id == _active_session_id)
		_session_buttons[s.id] = btn

		# Delete button
		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.custom_minimum_size = Vector2(28, 0)
		del_btn.flat = true
		del_btn.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_MUTED)
		del_btn.add_theme_color_override("font_hover_color", DeepCodeTheme.COLOR_ERROR)
		del_btn.add_theme_font_size_override("font_size", 15)
		del_btn.pressed.connect(delete_session.bind(s.id))

		row.add_child(btn)
		row.add_child(del_btn)
		session_list.add_child(row)


func _update_button_states() -> void:
	for sid in _session_buttons:
		var btn: Button = _session_buttons[sid]
		_apply_session_button_style(btn, sid == _active_session_id)


func _apply_session_button_style(btn: Button, active: bool) -> void:
	if active:
		var active_style := DeepCodeTheme.rounded_flat(DeepCodeTheme.COLOR_SURFACE, DeepCodeTheme.RADIUS_SM)
		active_style.content_margin_left = 8
		active_style.content_margin_top = 6
		active_style.content_margin_right = 8
		active_style.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", active_style)
		btn.add_theme_stylebox_override("hover", active_style)
		btn.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_PRIMARY)
	else:
		var normal_style := StyleBoxEmpty.new()
		normal_style.content_margin_left = 8
		normal_style.content_margin_top = 6
		normal_style.content_margin_right = 8
		normal_style.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", normal_style)
		var hover_style := DeepCodeTheme.rounded_flat(DeepCodeTheme.COLOR_SURFACE_HOVER, DeepCodeTheme.RADIUS_SM)
		hover_style.content_margin_left = 8
		hover_style.content_margin_top = 6
		hover_style.content_margin_right = 8
		hover_style.content_margin_bottom = 6
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_SECONDARY)
