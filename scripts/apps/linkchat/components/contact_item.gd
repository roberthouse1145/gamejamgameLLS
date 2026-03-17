class_name ChatContactItem extends PanelContainer
## 侧边栏联系人/频道条目
## 显示头像、名称、最后一条消息预览、未读红点

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")

signal selected(channel_id: String)

var channel_id: String = ""
var _is_selected: bool = false

var _name_label: Label
var _preview_label: Label
var _time_label: Label
var _unread_badge: PanelContainer
var _unread_count_label: Label
var _avatar_panel: PanelContainer
var _bg_rect: Panel
var _bg_style: StyleBoxFlat
var _select_tween: Tween


static func create(channel: Resource, _npc: Resource = null) -> ChatContactItem:
	var item := ChatContactItem.new()
	item.channel_id = channel.channel_id
	item._build(channel)
	return item


func _build(channel: Resource) -> void:
	custom_minimum_size = Vector2(0, 72)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 默认透明背景
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# 选中背景层（Panel + StyleBoxFlat，支持圆角 + 颜色过渡）
	_bg_style = LCTheme.rounded_flat(Color.TRANSPARENT, LCTheme.RADIUS_SM)
	_bg_rect = Panel.new()
	_bg_rect.add_theme_stylebox_override("panel", _bg_style)
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg_rect)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	# 头像
	var display_name: String = channel.display_name
	_avatar_panel = _create_avatar(display_name, channel.channel_type)
	hbox.add_child(_avatar_panel)

	# 中间：名称 + 预览
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_vbox)

	_name_label = Label.new()
	_name_label.text = display_name
	_name_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(_name_label)

	_preview_label = Label.new()
	_preview_label.text = ""
	_preview_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	_preview_label.add_theme_font_size_override("font_size", 14)
	_preview_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(_preview_label)

	# 右侧：时间 + 未读
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 4)
	right_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(right_vbox)

	_time_label = Label.new()
	_time_label.text = ""
	_time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_vbox.add_child(_time_label)

	# 未读红点
	_unread_badge = PanelContainer.new()
	_unread_badge.custom_minimum_size = Vector2(24, 24)
	_unread_badge.add_theme_stylebox_override("panel", LCTheme.get_unread_badge_style())
	_unread_badge.visible = false
	_unread_badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	_unread_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_vbox.add_child(_unread_badge)

	_unread_count_label = Label.new()
	_unread_count_label.add_theme_color_override("font_color", Color.WHITE)
	_unread_count_label.add_theme_font_size_override("font_size", 12)
	_unread_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unread_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unread_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unread_badge.add_child(_unread_count_label)

	# 更新预览
	_update_preview(channel)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(channel_id)


func set_selected(value: bool) -> void:
	_is_selected = value
	var target_color: Color = LCTheme.COLOR_CONTACT_SELECTED if _is_selected else Color.TRANSPARENT
	if _select_tween and _select_tween.is_valid():
		_select_tween.kill()
	_select_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_select_tween.tween_property(_bg_style, "bg_color", target_color, 0.15)


func update_from_channel(channel: Resource) -> void:
	_update_preview(channel)
	if channel.unread_count > 0:
		_unread_badge.visible = true
		_unread_count_label.text = str(channel.unread_count) if channel.unread_count < 100 else "99+"
	else:
		_unread_badge.visible = false


func _update_preview(channel: Resource) -> void:
	if channel.messages.size() > 0:
		var last_msg: Dictionary = channel.messages[-1]
		var sender: String = last_msg.get("sender_name", "")
		var content: String = last_msg.get("content", "")
		_preview_label.text = "%s: %s" % [sender, content] if not sender.is_empty() else content
		_time_label.text = last_msg.get("time", "")
	else:
		_preview_label.text = ""
		_time_label.text = ""


func _create_avatar(display_name: String, channel_type: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(48, 48)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var avatar_color: Color
	match channel_type:
		0: avatar_color = Color("#5C7CFA") # WORK: Indigo (Bright)
		1: avatar_color = Color("#40C057") # SOCIAL: Green (Bright)
		2: # DM
			var hue := float(display_name.hash() & 0xFFFF) / 65535.0
			# S:0.5-0.6, V:0.9-0.95 (Pastel/Bright)
			avatar_color = Color.from_hsv(hue, 0.55, 0.95)
		3: avatar_color = Color("#ADB5BD") # SYSTEM: Light Gray
		_: avatar_color = Color("#868E96")

	panel.add_theme_stylebox_override("panel", LCTheme.get_avatar_style(avatar_color))

	var initial := Label.new()
	var first_char := display_name.substr(0, 1) if not display_name.is_empty() else "?"
	if channel_type == 0 or channel_type == 1:
		first_char = "#"
	initial.text = first_char
	initial.add_theme_color_override("font_color", Color.WHITE)
	initial.add_theme_font_size_override("font_size", 18)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	initial.size_flags_vertical = Control.SIZE_EXPAND_FILL
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(initial)

	return panel
