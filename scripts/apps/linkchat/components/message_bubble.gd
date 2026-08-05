class_name ChatMessageBubble extends MarginContainer
## 聊天消息气泡组件
## 支持三种类型：NPC（左对齐+头像）、玩家（右对齐）、系统（居中灰字）
## 支持消息内嵌图片占位符：[图片]、[图片:描述]、[image:描述]
##
## 气泡宽度策略（参考微信）：
## - 短消息：气泡 shrink 到文字宽度
## - 长消息：气泡最大占容器 70%，自动换行
## - 通过延迟一帧测量实际文字宽度来决定

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const MessageCardClass := preload("res://scripts/apps/linkchat/components/message_card.gd")
const UIIconLibraryClass := preload("res://scripts/ui/ui_icon_library.gd")
const RoundedAvatarScene := preload("res://scenes/ui/rounded_avatar.tscn")

enum BubbleType {NPC, PLAYER, SYSTEM}

## 气泡最大宽度占父容器的比例
const MAX_WIDTH_RATIO: float = 0.78
const AVATAR_SIZE: float = 144.0
const NAME_FONT_SIZE: int = 27
const TIME_FONT_SIZE: int = 24
const CONTENT_FONT_SIZE: int = 33
const SYSTEM_FONT_SIZE: int = 27

static var _image_regex: RegEx

var _type: BubbleType = BubbleType.NPC
## 气泡面板引用，用于延迟调整宽度
var _bubble_panel: PanelContainer = null
## 内容 Label 引用
var _content_label: Label = null
var _layout_watch_target: Control = null
var _is_adjusting_width: bool = false
var _width_preconfigured: bool = false
var _bubble_tail: Node2D = null
var _tail_is_player: bool = false


static func _get_image_regex() -> RegEx:
	if _image_regex == null:
		_image_regex = RegEx.new()
		_image_regex.compile("\\[(图片|image)(:[^\\]]+)?\\]")
	return _image_regex


## 从消息字典创建气泡
static func create(msg: Dictionary, container_width: float = 0.0) -> ChatMessageBubble:
	var bubble := ChatMessageBubble.new()
	var sender_id: String = msg.get("sender_id", "")

	if sender_id == "system":
		bubble._build_system(msg)
	elif sender_id == "player":
		bubble._build_player(msg)
	else:
		bubble._build_npc(msg)
	if container_width > 0.0:
		bubble._apply_bubble_width(container_width)
		bubble._width_preconfigured = true

	return bubble


func _build_npc(msg: Dictionary) -> void:
	_type = BubbleType.NPC
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	add_theme_constant_override("margin_left", 30)
	add_theme_constant_override("margin_right", 156)
	add_theme_constant_override("margin_top", 12)
	add_theme_constant_override("margin_bottom", 12)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 24)
	add_child(hbox)

	var avatar := _create_avatar(
		str(msg.get("sender_name", "?")),
		_resolve_avatar_texture(msg)
	)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hbox.add_child(avatar)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_theme_constant_override("separation", 9)
	hbox.add_child(vbox)

	vbox.add_child(_create_name_tag(str(msg.get("sender_name", "")), _resolve_time_text(msg), false))

	# 气泡 — SHRINK_BEGIN 让短消息不撑满
	_bubble_panel = PanelContainer.new()
	_bubble_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_bubble_panel.add_theme_stylebox_override("panel", LCTheme.get_npc_bubble_style())
	vbox.add_child(_bubble_panel)
	_attach_bubble_tail(false)

	_build_content(_bubble_panel, msg)


func _build_player(msg: Dictionary) -> void:
	_type = BubbleType.PLAYER
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	add_theme_constant_override("margin_left", 156)
	add_theme_constant_override("margin_right", 30)
	add_theme_constant_override("margin_top", 12)
	add_theme_constant_override("margin_bottom", 12)

	var align := HBoxContainer.new()
	align.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align.add_theme_constant_override("separation", 24)
	add_child(align)

	# 左侧弹性空间，把气泡推到右边
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align.add_child(spacer)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	content_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content_vbox.add_theme_constant_override("separation", 9)
	content_vbox.add_child(_create_name_tag(str(msg.get("sender_name", "")), _resolve_time_text(msg), true))
	align.add_child(content_vbox)

	# 气泡 — SHRINK_END 让短消息不撑满，靠右
	_bubble_panel = PanelContainer.new()
	_bubble_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bubble_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bubble_panel.add_theme_stylebox_override("panel", LCTheme.get_player_bubble_style())
	content_vbox.add_child(_bubble_panel)
	_attach_bubble_tail(true)

	_build_content(_bubble_panel, msg)

	var avatar := _create_avatar(
		str(msg.get("sender_name", "?")),
		_resolve_avatar_texture(msg)
	)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	align.add_child(avatar)


func _build_system(msg: Dictionary) -> void:
	_type = BubbleType.SYSTEM
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	add_theme_constant_override("margin_left", 96)
	add_theme_constant_override("margin_right", 96)
	add_theme_constant_override("margin_top", 6)
	add_theme_constant_override("margin_bottom", 6)

	var label := Label.new()
	label.text = msg.get("content", "")
	label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	label.add_theme_font_size_override("font_size", SYSTEM_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


## 气泡加入场景树后，延迟一帧测量文字宽度并调整换行
func _ready() -> void:
	# 用 modulate.a=0 代替 visible=false，保持布局占位以确保 scroll 能正确计算 max_value
	modulate.a = 0.0
	if _content_label == null or _bubble_panel == null:
		_animate_entry()
		return
	_bind_layout_watchers()
	if _width_preconfigured:
		_animate_entry()
		return
	# 等一帧让布局引擎分配尺寸
	await get_tree().process_frame
	_adjust_bubble_width()
	_animate_entry()


func _animate_entry() -> void:
	# 只做透明度淡入，避免消息出现时产生纵向缩放造成的视觉颤动。
	modulate.a = 0.0
	scale = Vector2.ONE

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _adjust_bubble_width() -> void:
	if _content_label == null or _bubble_panel == null or _is_adjusting_width:
		return
	_is_adjusting_width = true

	# 获取消息列表容器的宽度（气泡的祖先 ScrollContainer 内的 VBoxContainer）
	var container_width: float = 0.0
	var p: Control = get_parent() as Control
	if p:
		container_width = p.size.x
	if container_width <= 0:
		container_width = get_viewport_rect().size.x * 0.6

	_apply_bubble_width(container_width)
	_is_adjusting_width = false


func _apply_bubble_width(container_width: float) -> void:
	if _content_label == null or _bubble_panel == null or container_width <= 0.0:
		return

	# 气泡内 padding（从 StyleBoxFlat 读取）
	var padding: float = 24.0 # 默认 12+12
	var style: StyleBox = _bubble_panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		padding = style.content_margin_left + style.content_margin_right

	# 头像 + 间距占用的固定宽度
	var fixed_width: float = AVATAR_SIZE + 36.0 # avatar + spacing + outer margin

	# 最大内容宽度
	var max_content_w: float = container_width * MAX_WIDTH_RATIO - fixed_width - padding
	max_content_w = maxf(max_content_w, 80.0)
	var max_bubble_w: float = max_content_w + padding

	# 测量文字单行宽度
	var font: Font = _content_label.get_theme_font("font")
	var font_size: int = _content_label.get_theme_font_size("font_size")
	if font == null:
		font = ThemeDB.fallback_font
	if font_size <= 0:
		font_size = ThemeDB.fallback_font_size

	var text_width: float = font.get_string_size(
		_content_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x

	if text_width > max_content_w:
		# 长消息：限制宽度，开启换行
		_content_label.custom_minimum_size.x = max_content_w
		_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble_panel.custom_minimum_size.x = max_bubble_w
	else:
		# 短消息：恢复自然 shrink
		_content_label.custom_minimum_size.x = 0.0
		_content_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_bubble_panel.custom_minimum_size.x = 0.0

func _bind_layout_watchers() -> void:
	if not resized.is_connected(_on_layout_resized):
		resized.connect(_on_layout_resized)

	var parent_control := get_parent() as Control
	if parent_control == null:
		return

	_layout_watch_target = parent_control
	if not parent_control.resized.is_connected(_on_layout_resized):
		parent_control.resized.connect(_on_layout_resized)


func _on_layout_resized() -> void:
	call_deferred("_adjust_bubble_width")
	call_deferred("_position_bubble_tail")


func _create_name_tag(display_name: String, time_text: String, is_player: bool) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.size_flags_horizontal = Control.SIZE_SHRINK_END if is_player else Control.SIZE_SHRINK_BEGIN
	tag.add_theme_stylebox_override("panel", LCTheme.get_name_tag_style(is_player))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tag.add_child(row)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_color_override(
		"font_color",
		LCTheme.COLOR_TEXT_SENDER_PLAYER if is_player else LCTheme.COLOR_TEXT_SENDER_NPC
	)
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	row.add_child(name_label)

	if not time_text.is_empty():
		var time_label := Label.new()
		time_label.text = time_text
		time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_TIME)
		time_label.add_theme_font_size_override("font_size", TIME_FONT_SIZE)
		row.add_child(time_label)

	return tag


func _attach_bubble_tail(is_player: bool) -> void:
	_tail_is_player = is_player
	_bubble_tail = Node2D.new()
	_bubble_tail.show_behind_parent = true
	_bubble_panel.add_child(_bubble_tail)

	var direction: float = 1.0 if is_player else -1.0
	var border := Polygon2D.new()
	border.polygon = PackedVector2Array([
		Vector2(20.0 * direction, 0.0),
		Vector2(-5.0 * direction, -11.0),
		Vector2(-5.0 * direction, 14.0),
	])
	border.color = LCTheme.COLOR_BUBBLE_PLAYER_BORDER if is_player else LCTheme.COLOR_BUBBLE_NPC_BORDER
	_bubble_tail.add_child(border)

	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([
		Vector2(15.0 * direction, 0.0),
		Vector2(-5.0 * direction, -7.0),
		Vector2(-5.0 * direction, 10.0),
	])
	fill.color = LCTheme.COLOR_BUBBLE_PLAYER if is_player else LCTheme.COLOR_BUBBLE_NPC
	_bubble_tail.add_child(fill)

	_bubble_panel.resized.connect(_position_bubble_tail)
	call_deferred("_position_bubble_tail")


func _position_bubble_tail() -> void:
	if _bubble_tail == null or _bubble_panel == null:
		return
	_bubble_tail.position = Vector2(_bubble_panel.size.x if _tail_is_player else 0.0, 30.0)


## 构建气泡内容（支持文本+图片占位混排）

func _build_content(parent: Control, msg: Dictionary) -> void:
	var content: String = str(msg.get("content", ""))
	var has_card: bool = msg.has("card") and msg["card"] is Dictionary and not (msg["card"] as Dictionary).is_empty()
	var segments := _parse_content(content)

	# 纯文本（无图片无卡片）
	if not has_card and segments.size() == 1 and segments[0].type == "text":
		_content_label = _create_text_label(segments[0].value)
		parent.add_child(_content_label)
		return

	# 混合内容
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	parent.add_child(vbox)

	for seg in segments:
		if seg.type == "text" and not seg.value.strip_edges().is_empty():
			var lbl := _create_text_label(seg.value)
			if _content_label == null:
				_content_label = lbl # 记录第一个文本标签用于宽度调整
			vbox.add_child(lbl)
		elif seg.type == "image":
			var img_block := _create_image_placeholder(seg.value)
			vbox.add_child(img_block)

	if has_card:
		vbox.add_child(MessageCardClass.create(msg["card"], _type))


static func _parse_content(content: String) -> Array[Dictionary]:
	var regex := _get_image_regex()
	var results: Array[Dictionary] = []
	var matches := regex.search_all(content)

	if matches.is_empty():
		results.append({"type": "text", "value": content})
		return results

	var last_end: int = 0
	for m in matches:
		if m.get_start() > last_end:
			results.append({"type": "text", "value": content.substr(last_end, m.get_start() - last_end)})
		var desc: String = m.get_string(2)
		if not desc.is_empty():
			desc = desc.substr(1)
		else:
			desc = "图片"
		results.append({"type": "image", "value": desc})
		last_end = m.get_end()

	if last_end < content.length():
		results.append({"type": "text", "value": content.substr(last_end)})
	return results


func _create_text_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	lbl.add_theme_font_size_override("font_size", CONTENT_FONT_SIZE)
	# 默认不换行，_ready 中根据测量结果决定是否开启
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	return lbl


func _create_image_placeholder(description: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 270)
	var bg_color := Color("#E8E8EC") if _type == BubbleType.NPC else Color("#DCEAFF")
	panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(bg_color, LCTheme.RADIUS_SM))

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(inner)

	var icon_rect := TextureRect.new()
	icon_rect.texture = UIIconLibraryClass.get_icon("image")
	icon_rect.custom_minimum_size = Vector2(54, 54)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.modulate = LCTheme.COLOR_TEXT_MUTED
	inner.add_child(icon_rect)

	var desc_label := Label.new()
	desc_label.text = description
	desc_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	desc_label.add_theme_font_size_override("font_size", 23)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(desc_label)

	return panel


func _create_avatar(display_name: String, texture: Texture2D = null) -> RoundedAvatar:
	var avatar := RoundedAvatarScene.instantiate() as RoundedAvatar
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar.set_avatar(texture, display_name)
	return avatar


static func _resolve_avatar_texture(msg: Dictionary) -> Texture2D:
	var avatar: Variant = msg.get("avatar")
	return avatar as Texture2D if avatar is Texture2D else null


static func _resolve_time_text(msg: Dictionary) -> String:
	var phase_text := str(msg.get("time_phase", "")).strip_edges()
	if not phase_text.is_empty():
		return phase_text
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var glm := tree.root.get_node_or_null("GameLoopManager")
		if glm != null and glm.has_method("get_phase_display_name"):
			return str(glm.call("get_phase_display_name", glm.get("time_phase")))
	return str(msg.get("time", ""))
