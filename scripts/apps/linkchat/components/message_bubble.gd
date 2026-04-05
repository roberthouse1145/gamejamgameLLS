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

enum BubbleType {NPC, PLAYER, SYSTEM}

## 气泡最大宽度占父容器的比例
const MAX_WIDTH_RATIO: float = 0.82
const AVATAR_SIZE: float = 56.0
const AVATAR_FONT_SIZE: int = 20
const NAME_FONT_SIZE: int = 18
const TIME_FONT_SIZE: int = 16
const CONTENT_FONT_SIZE: int = 22
const SYSTEM_FONT_SIZE: int = 18

static var _image_regex: RegEx

var _type: BubbleType = BubbleType.NPC
## 气泡面板引用，用于延迟调整宽度
var _bubble_panel: PanelContainer = null
## 内容 Label 引用
var _content_label: Label = null
var _layout_watch_target: Control = null
var _is_adjusting_width: bool = false


static func _get_image_regex() -> RegEx:
	if _image_regex == null:
		_image_regex = RegEx.new()
		_image_regex.compile("\\[(图片|image)(:[^\\]]+)?\\]")
	return _image_regex


## 从消息字典创建气泡
static func create(msg: Dictionary) -> ChatMessageBubble:
	var bubble := ChatMessageBubble.new()
	var sender_id: String = msg.get("sender_id", "")

	if sender_id == "system":
		bubble._build_system(msg)
	elif sender_id == "player":
		bubble._build_player(msg)
	else:
		bubble._build_npc(msg)

	return bubble


func _build_npc(msg: Dictionary) -> void:
	_type = BubbleType.NPC
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	add_theme_constant_override("margin_left", 10)
	add_theme_constant_override("margin_right", 84)
	add_theme_constant_override("margin_top", 2)
	add_theme_constant_override("margin_bottom", 2)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 10)
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
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	# 名字 + 时间
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = msg.get("sender_name", "")
	name_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SENDER_NPC)
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	header.add_child(name_label)

	var time_label := Label.new()
	time_label.text = _resolve_time_text(msg)
	time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_TIME)
	time_label.add_theme_font_size_override("font_size", TIME_FONT_SIZE)
	header.add_child(time_label)

	# 气泡 — SHRINK_BEGIN 让短消息不撑满
	_bubble_panel = PanelContainer.new()
	_bubble_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_bubble_panel.add_theme_stylebox_override("panel", LCTheme.get_npc_bubble_style())
	vbox.add_child(_bubble_panel)

	_build_content(_bubble_panel, msg)


func _build_player(msg: Dictionary) -> void:
	_type = BubbleType.PLAYER
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	add_theme_constant_override("margin_left", 84)
	add_theme_constant_override("margin_right", 10)
	add_theme_constant_override("margin_top", 2)
	add_theme_constant_override("margin_bottom", 2)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	var time_label := Label.new()
	time_label.text = _resolve_time_text(msg)
	time_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_TIME)
	time_label.add_theme_font_size_override("font_size", TIME_FONT_SIZE)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(time_label)

	var align := HBoxContainer.new()
	align.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(align)

	# 左侧弹性空间，把气泡推到右边
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align.add_child(spacer)

	# 气泡 — SHRINK_END 让短消息不撑满，靠右
	_bubble_panel = PanelContainer.new()
	_bubble_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bubble_panel.add_theme_stylebox_override("panel", LCTheme.get_player_bubble_style())
	align.add_child(_bubble_panel)

	_build_content(_bubble_panel, msg)


func _build_system(msg: Dictionary) -> void:
	_type = BubbleType.SYSTEM
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	add_theme_constant_override("margin_left", 64)
	add_theme_constant_override("margin_right", 64)
	add_theme_constant_override("margin_top", 4)
	add_theme_constant_override("margin_bottom", 4)

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
	# 等一帧让布局引擎分配尺寸
	await get_tree().process_frame
	_adjust_bubble_width()
	_animate_entry()


func _animate_entry() -> void:
	# 进场动画：透明度淡入 + 竖向轻微展开（scale 不影响布局尺寸，不会抢占空间）
	modulate.a = 0.0
	pivot_offset = Vector2(size.x * 0.5, 0.0)
	scale = Vector2(1.0, 0.82)

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(self, "scale:y", 1.0, 0.22)


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

	# 气泡内 padding（从 StyleBoxFlat 读取）
	var padding: float = 24.0 # 默认 12+12
	var style: StyleBox = _bubble_panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		padding = style.content_margin_left + style.content_margin_right

	# 头像 + 间距占用的固定宽度
	var fixed_width: float = AVATAR_SIZE + 24.0 # avatar + spacing + outer margin

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

	_is_adjusting_width = false


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
	vbox.add_theme_constant_override("separation", 6)
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
	panel.custom_minimum_size = Vector2(320, 180)
	var bg_color := Color("#E8E8EC") if _type == BubbleType.NPC else Color("#D5EED0")
	panel.add_theme_stylebox_override("panel", LCTheme.rounded_flat(bg_color, LCTheme.RADIUS_SM))

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(inner)

	var icon_label := Label.new()
	icon_label.text = "🖼"
	icon_label.add_theme_font_size_override("font_size", 32)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(icon_label)

	var desc_label := Label.new()
	desc_label.text = description
	desc_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	desc_label.add_theme_font_size_override("font_size", 15)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(desc_label)

	return panel


func _create_avatar(display_name: String, texture: Texture2D = null) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)

	var hue := float(display_name.hash() & 0xFFFF) / 65535.0
	# Brighter pastel colors for Anime style
	var avatar_color := Color.from_hsv(hue, 0.55, 0.95)
	panel.add_theme_stylebox_override("panel", LCTheme.get_avatar_style(avatar_color))

	if texture != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = texture
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tex_rect)
	else:
		var initial := Label.new()
		initial.text = display_name.substr(0, 1) if not display_name.is_empty() else "?"
		initial.add_theme_color_override("font_color", Color.WHITE)
		initial.add_theme_font_size_override("font_size", AVATAR_FONT_SIZE)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		initial.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(initial)

	return panel


static func _resolve_avatar_texture(msg: Dictionary) -> Texture2D:
	var sender_id := str(msg.get("sender_id", "")).strip_edges()
	if sender_id.is_empty() or sender_id == "player" or sender_id == "system":
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var chat_manager := tree.root.get_node_or_null("ChatManager")
	if chat_manager == null or not chat_manager.has_method("get_npc"):
		return null
	var npc = chat_manager.call("get_npc", sender_id)
	if npc == null:
		return null
	var avatar = npc.get("avatar")
	return avatar as Texture2D if avatar != null else null


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
