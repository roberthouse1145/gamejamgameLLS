class_name DialogBox extends Control
## AVG 对话框 UI 节点
## 支持打字机效果、BBCode、说话者名字框、位置切换、透明模式、语音同步。

## 打字完成
signal text_finished
## 对话框被点击（推进主线）
signal clicked

# =============================================================================
# 子节点引用
# =============================================================================

## 对话框背景面板
@onready var box_panel: PanelContainer = %BoxPanel
@onready var text_margin_container: MarginContainer = %MarginContainer
## 名字框背景面板
@onready var name_panel: PanelContainer = %NamePanel
@onready var name_margin_container: MarginContainer = %NameMarginContainer
## 名字标签
@onready var name_label: Label = %NameLabel
## 文本标签（RichTextLabel，支持 BBCode）
@onready var text_label: RichTextLabel = %TextLabel
## 点击继续指示器
@onready var click_indicator: Control = %ClickIndicator
@onready var cursor_texture_rect: TextureRect = %CursorTexture
@onready var cursor_arrow_label: Label = %Arrow

# =============================================================================
# State
# =============================================================================

## 当前完整文本
var _full_text: String = ""
## 是否正在打字
var _is_typing: bool = false
## 打字 Tween
var _type_tween: Tween = null
## 点击指示器循环动画 Tween（呼吸 + 上下浮动）
var _indicator_tween: Tween = null
## 指示器动画目标节点 & 基础 Y（用于停止时恢复，避免 base_y 漂移）
@warning_ignore("unused_private_class_variable") var _indicator_target: Control = null
@warning_ignore("unused_private_class_variable") var _indicator_base_y: float = 0.0
## 角色数据（character_id -> data）
var _character_data: Dictionary = {}
## 对话设置引用
var _dialog_settings: Resource = null  # AVGDialogSettings
## 变量管理器引用（用于 {var_name} 替换）
var _variable_manager: RefCounted = null
## 项目分辨率
var _project_resolution: Vector2 = Vector2(2560, 1440)
## 语音播放中
var _voice_playing: bool = false
## 上次使用的位置参数（用于 resize 时重新布局）
var _last_position: String = "default"
## 上次透明模式
var _last_transparent: bool = false


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	visible = false
	if click_indicator != null:
		click_indicator.visible = false
		click_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_click_indicator_style()
	# 视觉子节点必须 IGNORE，否则它们默认 STOP 会吞掉点击，
	# 导致点在对话框本身上时推进不了剧情（只有点空白才推进）。
	if box_panel != null:
		box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if text_margin_container != null:
		text_margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if text_label != null:
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if name_panel != null:
		name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if name_margin_container != null:
		name_margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if name_label != null:
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cursor_arrow_label != null:
		cursor_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cursor_texture_rect != null:
		cursor_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)


func _on_resized() -> void:
	# Viewport 大小变化时重新布局对话框
	if visible and box_panel != null:
		_apply_settings()
		# 如果当前有对话在显示，重新定位
		_relayout_current()
		# 若指示器可见，需要基于新布局重启动画（base_y 会变）
		if click_indicator != null and click_indicator.visible:
			_start_indicator_animation()


## 使用上次的参数重新布局（viewport resize 时调用）
func _relayout_current() -> void:
	_update_position(_last_position)
	_update_transparency(_last_transparent)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click()


func _handle_click() -> void:
	if _is_typing:
		_skip_typewriter()
	else:
		clicked.emit()


# =============================================================================
# Public API
# =============================================================================

## 设置对话设置（从项目加载时调用）
func set_dialog_settings(settings: Resource) -> void:
	_dialog_settings = settings
	_apply_settings()
	_update_click_indicator_style()


## 设置项目分辨率
func set_project_resolution(resolution: Vector2) -> void:
	_project_resolution = resolution


## 设置角色数据
func set_character_data(characters: Dictionary) -> void:
	_character_data = characters


## 设置变量管理器（用于文本中 {var_name} 替换）
func set_variable_manager(vm: RefCounted) -> void:
	_variable_manager = vm


## 显示对话（统一接口，合并了原 show_dialogue 和 show_narration）
func show_dialogue(params: Dictionary) -> void:
	var text: String = params.get("text", "")
	var speaker: String = params.get("speaker", "")
	var emotion: String = params.get("emotion", "")
	var text_speed: float = params.get("text_speed", -1.0)
	var box_position: String = params.get("position", "default")
	var transparent: bool = params.get("transparent", false)

	# 处理说话者
	_update_speaker(speaker, emotion)

	# 处理位置
	_last_position = box_position
	_update_position(box_position)

	# 处理透明模式
	_last_transparent = transparent
	_update_transparency(transparent)
	# Cursor 依赖最终的 BoxPanel size，必须在布局完成后再更新样式。
	_update_click_indicator_style()

	# 计算实际打字速度
	var actual_speed: float = text_speed
	if actual_speed <= 0:
		actual_speed = _get_default_text_speed()

	# 预处理扩展标签：替换 {var_name} 为变量值
	var processed_text: String = _process_extended_tags(text)

	# 提取 {wait:N} 标记并转换为打字机暂停点
	var wait_data: Dictionary = _extract_wait_tags(processed_text)
	var clean_text: String = wait_data.get("text", processed_text)
	var wait_points: Dictionary = wait_data.get("waits", {})  # char_index -> seconds

	# 启动打字机
	_start_typewriter(clean_text, actual_speed, wait_points)

	visible = true


## 清空对话框
func clear() -> void:
	if name_panel != null:
		name_panel.visible = false
	if name_label != null:
		name_label.text = ""
	if text_label != null:
		text_label.text = ""
		text_label.visible_characters = 0
	if click_indicator != null:
		click_indicator.visible = false
	_stop_indicator_animation()
	_full_text = ""
	_is_typing = false
	_voice_playing = false
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
		_type_tween = null


## 隐藏对话框
func hide_box() -> void:
	visible = false
	_stop_indicator_animation()


## 是否正在打字
func is_typing() -> bool:
	return _is_typing


## 语音播放结束回调（由外部 AudioManager 调用）
func on_voice_finished() -> void:
	_voice_playing = false
	if _is_typing:
		_skip_typewriter()


# =============================================================================
# Internal — Speaker
# =============================================================================

## 更新说话者显示
func _update_speaker(speaker: String, emotion: String) -> void:
	if speaker.is_empty():
		# 旁白模式：隐藏名字框
		if name_panel != null:
			name_panel.visible = false
		if name_label != null:
			name_label.text = ""
		return

	# 尝试解析为角色（支持 character_id、character_name、display_name 匹配）
	var display_name: String = speaker
	var char_data: Dictionary = _find_character_data(speaker)
	if not char_data.is_empty():
		if char_data.has("display_name") and not char_data["display_name"].is_empty():
			display_name = char_data["display_name"]
		elif char_data.has("character_name") and not char_data["character_name"].is_empty():
			display_name = char_data["character_name"]
		# emotion 仅对有效角色生效（预留，后续可用于切换立绘等）
		if not emotion.is_empty():
			pass  # TODO: 通知 CharacterDisplay 切换表情

	if name_label != null:
		name_label.text = display_name
	if name_panel != null:
		name_panel.visible = true


## 根据 speaker 引用查找角色数据（支持 character_id、character_name、display_name）
func _find_character_data(speaker: String) -> Dictionary:
	var normalized_speaker: String = str(speaker).strip_edges()
	if normalized_speaker.is_empty():
		return {}
	if _character_data.has(normalized_speaker):
		return _character_data[normalized_speaker]
	for char_id in _character_data:
		var cd: Dictionary = _character_data[char_id]
		if str(cd.get("character_name", "")).strip_edges() == normalized_speaker:
			return cd
		if str(cd.get("display_name", "")).strip_edges() == normalized_speaker:
			return cd
	return {}


# =============================================================================
# Internal — Position
# =============================================================================

## 位置枚举值
const POS_BOTTOM: int = 0
const POS_CENTER: int = 1
const POS_TOP: int = 2

## 更新对话框位置
func _update_position(position_str: String) -> void:
	var pos_index: int = _resolve_position(position_str)
	if box_panel == null:
		return

	# 对话框尺寸和间距
	var box_size: Vector2 = _get_box_pixel_size()
	var margin: int = _get_box_margin()
	var parent_size: Vector2 = size

	# 水平居中
	var x: float = (parent_size.x - box_size.x) / 2.0

	# 垂直位置
	var y: float = 0.0
	match pos_index:
		POS_BOTTOM:
			y = parent_size.y - box_size.y - margin
		POS_CENTER:
			y = (parent_size.y - box_size.y) / 2.0
		POS_TOP:
			y = margin

	box_panel.position = Vector2(x, y)
	box_panel.size = box_size
	# PanelContainer 会根据子节点最小尺寸自动扩展，需要裁剪并限制
	box_panel.clip_contents = true
	_layout_click_indicator()

	# 更新名字框位置（相对于对话框）
	_update_name_panel_position()


## 解析位置字符串为索引
func _resolve_position(position_str: String) -> int:
	match position_str:
		"bottom":
			return POS_BOTTOM
		"center":
			return POS_CENTER
		"top":
			return POS_TOP
		_:
			# "default" 或其他 → 使用项目设置
			if _dialog_settings != null and "default_position" in _dialog_settings:
				return _dialog_settings.default_position
			return POS_BOTTOM


## 更新名字框位置（相对于对话框左上角偏移）
func _update_name_panel_position() -> void:
	if name_panel == null or box_panel == null:
		return
	if not name_panel.visible:
		return

	var box_size: Vector2 = box_panel.size
	var name_offset: Vector2 = _get_name_norm_offset()
	var name_size: Vector2 = _get_name_pixel_size()

	# 名字框位置 = 对话框位置 + 偏移（归一化 * 对话框尺寸）
	var offset_pixels: Vector2 = Vector2(
		name_offset.x * box_size.x,
		name_offset.y * box_size.y
	)
	name_panel.position = box_panel.position + offset_pixels
	name_panel.size = name_size


# =============================================================================
# Internal — Transparency
# =============================================================================

## 更新透明模式
func _update_transparency(transparent: bool) -> void:
	if box_panel != null:
		if transparent:
			box_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		else:
			var style: StyleBox = _get_box_stylebox()
			box_panel.add_theme_stylebox_override("panel", style)

	if name_panel != null and name_panel.visible:
		if transparent:
			name_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		else:
			var style: StyleBox = _get_name_stylebox()
			name_panel.add_theme_stylebox_override("panel", style)


# =============================================================================
# Internal — Extended Tags
# =============================================================================

## 替换 {var_name} 为变量值
func _process_extended_tags(text: String) -> String:
	if _variable_manager == null:
		return text

	var result: String = text
	var regex := RegEx.new()
	regex.compile("\\{([a-zA-Z_][a-zA-Z0-9_]*)\\}")
	var matches: Array = regex.search_all(result)

	# 从后往前替换，避免偏移问题
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var var_name: String = m.get_string(1)
		# 排除 wait:N 格式
		if var_name.begins_with("wait:"):
			continue
		if _variable_manager.has_variable(var_name):
			var val = _variable_manager.get_value(var_name)
			result = result.substr(0, m.get_start()) + str(val) + result.substr(m.get_end())

	return result


## 提取 {wait:N} 标记，返回 {text: 清理后文本, waits: {纯文本字符索引 -> 秒数}}
func _extract_wait_tags(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("\\{wait:(\\d+\\.?\\d*)\\}")
	var matches: Array = regex.search_all(text)

	if matches.is_empty():
		return {"text": text, "waits": {}}

	var waits: Dictionary = {}
	var clean: String = ""
	var last_end: int = 0
	var char_count: int = 0

	for m in matches:
		var before: String = text.substr(last_end, m.get_start() - last_end)
		clean += before
		# Count visible characters in 'before' (strip BBCode tags)
		char_count += _count_visible_chars(before)
		# Record wait point at current visible char position
		var seconds: float = m.get_string(1).to_float()
		waits[char_count] = seconds
		last_end = m.get_end()

	# Append remaining text
	clean += text.substr(last_end)

	return {"text": clean, "waits": waits}


## 计算文本中可见字符数（去除 BBCode 标签）
func _count_visible_chars(text: String) -> int:
	var regex := RegEx.new()
	regex.compile("\\[.*?\\]")
	var stripped: String = regex.sub(text, "", true)
	return stripped.length()


# =============================================================================
# Internal — Typewriter
# =============================================================================

## 启动打字机效果
func _start_typewriter(text: String, speed: float, wait_points: Dictionary = {}) -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()

	_full_text = text
	_is_typing = true

	if text_label != null:
		text_label.text = text
		text_label.visible_characters = 0

		if click_indicator != null:
			click_indicator.visible = false
		_stop_indicator_animation()

		var stripped_length: int = _get_stripped_text_length(text)

		if stripped_length > 0 and speed > 0:
			if wait_points.is_empty():
				# 无暂停点，简单 tween
				var duration: float = float(stripped_length) / speed
				_type_tween = create_tween()
				_type_tween.tween_property(text_label, "visible_characters", stripped_length, duration)
				_type_tween.finished.connect(_on_typewriter_finished)
			else:
				# 有暂停点，分段 tween
				_start_typewriter_with_waits(stripped_length, speed, wait_points)
		else:
			text_label.visible_characters = -1
			_on_typewriter_finished()


## 带暂停点的打字机（分段 tween）
func _start_typewriter_with_waits(total_chars: int, speed: float, wait_points: Dictionary) -> void:
	# 收集并排序暂停点
	var sorted_points: Array = wait_points.keys()
	sorted_points.sort()

	_type_tween = create_tween()
	var current_pos: int = 0

	for point in sorted_points:
		var target: int = point as int
		if target <= current_pos:
			# 暂停点在当前位置或之前，直接插入等待
			_type_tween.tween_callback(func(): pass)
			_type_tween.tween_interval(wait_points[point])
			continue

		var chars_to_type: int = target - current_pos
		var segment_duration: float = float(chars_to_type) / speed
		_type_tween.tween_property(text_label, "visible_characters", target, segment_duration)
		_type_tween.tween_interval(wait_points[point])
		current_pos = target

	# 打完剩余字符
	if current_pos < total_chars:
		var remaining: int = total_chars - current_pos
		var remaining_duration: float = float(remaining) / speed
		_type_tween.tween_property(text_label, "visible_characters", total_chars, remaining_duration)

	_type_tween.finished.connect(_on_typewriter_finished)


## 跳过打字机，直接显示全文
func _skip_typewriter() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
		_type_tween = null
	if text_label != null:
		text_label.visible_characters = -1
	_on_typewriter_finished()


## 打字完成回调
func _on_typewriter_finished() -> void:
	_is_typing = false
	if click_indicator != null:
		click_indicator.visible = true
		_start_indicator_animation()
	text_finished.emit()


## 启动点击指示器循环动画（呼吸 + 上下浮动）
## 作用在当前可见的子节点（CursorTexture 或 Arrow）上，不影响 ClickIndicator 自身的 layout。
func _start_indicator_animation() -> void:
	_stop_indicator_animation()
	if click_indicator == null or not click_indicator.visible:
		return

	var target: Control = null
	if cursor_texture_rect != null and cursor_texture_rect.visible:
		target = cursor_texture_rect
	elif cursor_arrow_label != null and cursor_arrow_label.visible:
		target = cursor_arrow_label
	if target == null:
		return

	# 重置基础状态并记录基准 Y（下次 stop 时用于精确还原）
	target.modulate.a = 1.0
	_indicator_target = target
	_indicator_base_y = target.position.y
	var float_distance: float = 6.0
	var half_duration: float = 0.6

	_indicator_tween = create_tween().set_loops()
	# 相位 1：淡出 + 向下浮动（并行）
	_indicator_tween.set_parallel(true)
	_indicator_tween.tween_property(target, "modulate:a", 0.35, half_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_indicator_tween.tween_property(target, "position:y", _indicator_base_y + float_distance, half_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 相位 2：淡入 + 回到原位（并行，chain 切换到新的 step）
	_indicator_tween.chain()
	_indicator_tween.tween_property(target, "modulate:a", 1.0, half_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_indicator_tween.tween_property(target, "position:y", _indicator_base_y, half_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 停止点击指示器动画，恢复基础状态
func _stop_indicator_animation() -> void:
	if _indicator_tween != null and _indicator_tween.is_valid():
		_indicator_tween.kill()
	_indicator_tween = null
	# 恢复到动画开始前的状态，避免 position.y 漂移
	if _indicator_target != null and is_instance_valid(_indicator_target):
		_indicator_target.position.y = _indicator_base_y
		_indicator_target.modulate.a = 1.0
	_indicator_target = null
	if cursor_texture_rect != null:
		cursor_texture_rect.modulate.a = 1.0
	if cursor_arrow_label != null:
		cursor_arrow_label.modulate.a = 1.0


## 获取去除 BBCode 标签后的纯文本长度
## RichTextLabel.visible_characters 计数的是纯文本字符
func _get_stripped_text_length(bbcode_text: String) -> int:
	# 使用临时 RichTextLabel 解析 BBCode 获取纯文本长度
	if text_label != null:
		# RichTextLabel 设置 text 后，get_total_character_count() 返回纯文本字符数
		text_label.text = bbcode_text
		return text_label.get_total_character_count()
	# Fallback: 简单正则去除标签
	var regex := RegEx.new()
	regex.compile("\\[.*?\\]")
	var stripped: String = regex.sub(bbcode_text, "", true)
	return stripped.length()


# =============================================================================
# Internal — Settings Helpers
# =============================================================================

## 应用对话设置到 UI
func _apply_settings() -> void:
	if _dialog_settings == null:
		return

	var ref_scale: float = _get_reference_size().y / _project_resolution.y
	if ref_scale <= 0:
		ref_scale = 1.0

	# 应用对话框样式
	if box_panel != null:
		var style: StyleBox = _get_box_stylebox()
		box_panel.add_theme_stylebox_override("panel", style)
		_apply_text_padding()

	# 应用名字框样式
	if name_panel != null:
		var style: StyleBox = _get_name_stylebox()
		name_panel.add_theme_stylebox_override("panel", style)
		_apply_name_padding()

	# 应用字体设置（按比例缩放）
	if text_label != null:
		if "text_font_size" in _dialog_settings and _dialog_settings.text_font_size > 0:
			var scaled_size: int = maxi(int(_dialog_settings.text_font_size * ref_scale), 8)
			text_label.add_theme_font_size_override("normal_font_size", scaled_size)
		if "text_color" in _dialog_settings:
			text_label.add_theme_color_override("default_color", _dialog_settings.text_color)
		if "text_outline_size" in _dialog_settings:
			text_label.add_theme_constant_override("outline_size", maxi(int(_dialog_settings.text_outline_size * ref_scale), 0))
		if "text_outline_color" in _dialog_settings:
			text_label.add_theme_color_override("font_outline_color", _dialog_settings.text_outline_color)

	if name_label != null:
		if "name_font_size" in _dialog_settings and _dialog_settings.name_font_size > 0:
			var scaled_size: int = maxi(int(_dialog_settings.name_font_size * ref_scale), 8)
			name_label.add_theme_font_size_override("font_size", scaled_size)
		if "name_color" in _dialog_settings:
			name_label.add_theme_color_override("font_color", _dialog_settings.name_color)
		if "name_outline_size" in _dialog_settings:
			name_label.add_theme_constant_override("outline_size", maxi(int(_dialog_settings.name_outline_size * ref_scale), 0))
		if "name_outline_color" in _dialog_settings:
			name_label.add_theme_color_override("font_outline_color", _dialog_settings.name_outline_color)

	_update_click_indicator_style()


func _apply_text_padding() -> void:
	if text_margin_container == null:
		return

	var padding: Vector4i = Vector4i(20, 15, 20, 15)
	if _dialog_settings != null and "text_padding" in _dialog_settings:
		padding = _dialog_settings.text_padding

	var outline: int = 0
	if _dialog_settings != null and "text_outline_size" in _dialog_settings:
		var ref_scale: float = _get_reference_size().y / _project_resolution.y
		outline = maxi(int(_dialog_settings.text_outline_size * ref_scale), 0)

	# RichTextLabel 的描边会超出 glyph 边界，这里补一圈安全边距避免被 BoxPanel 裁掉。
	text_margin_container.add_theme_constant_override("margin_left", padding.x + outline)
	text_margin_container.add_theme_constant_override("margin_top", padding.y + outline)
	text_margin_container.add_theme_constant_override("margin_right", padding.z + outline)
	text_margin_container.add_theme_constant_override("margin_bottom", padding.w + outline)


func _apply_name_padding() -> void:
	if name_margin_container == null:
		return

	var padding: Vector4i = Vector4i(10, 5, 10, 5)
	if _dialog_settings != null and "name_padding" in _dialog_settings:
		padding = _dialog_settings.name_padding

	var outline: int = 0
	if _dialog_settings != null and "name_outline_size" in _dialog_settings:
		var ref_scale: float = _get_reference_size().y / _project_resolution.y
		outline = maxi(int(_dialog_settings.name_outline_size * ref_scale), 0)

	name_margin_container.add_theme_constant_override("margin_left", padding.x + outline)
	name_margin_container.add_theme_constant_override("margin_top", padding.y + outline)
	name_margin_container.add_theme_constant_override("margin_right", padding.z + outline)
	name_margin_container.add_theme_constant_override("margin_bottom", padding.w + outline)


func _update_click_indicator_style() -> void:
	if click_indicator == null:
		return

	_layout_click_indicator()
	var ref: Vector2 = box_panel.size if box_panel != null and box_panel.size.length() > 0.0 else _get_box_pixel_size()
	var use_texture: bool = (
		_dialog_settings != null
		and "cursor_texture" in _dialog_settings
		and _dialog_settings.cursor_texture != null
	)

	if cursor_texture_rect != null:
		cursor_texture_rect.visible = use_texture
		if use_texture:
			cursor_texture_rect.texture = _dialog_settings.cursor_texture
			var norm_size: Vector2 = Vector2(0.026, 0.022)
			if "cursor_norm_size" in _dialog_settings:
				norm_size = _dialog_settings.cursor_norm_size
			var pixel_size: Vector2 = Vector2(
				maxf(norm_size.x * ref.x, 8.0),
				maxf(norm_size.y * ref.y, 8.0)
			)
			cursor_texture_rect.custom_minimum_size = pixel_size
			cursor_texture_rect.size = pixel_size
			var norm_offset: Vector2 = Vector2(-0.045, -0.08)
			if "cursor_norm_offset" in _dialog_settings:
				norm_offset = _dialog_settings.cursor_norm_offset
			cursor_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			cursor_texture_rect.position = Vector2(
				norm_offset.x * ref.x,
				norm_offset.y * ref.y
			)

	if cursor_arrow_label != null:
		cursor_arrow_label.visible = not use_texture


func _layout_click_indicator() -> void:
	if click_indicator == null or box_panel == null:
		return
	click_indicator.top_level = false
	click_indicator.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	click_indicator.position = box_panel.position
	click_indicator.size = box_panel.size


## 获取对话框样式
func _get_box_stylebox() -> StyleBox:
	if _dialog_settings != null and _dialog_settings.has_method("get_box_stylebox"):
		return _dialog_settings.get_box_stylebox()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	sb.set_corner_radius_all(8)
	return sb


## 获取名字框样式
func _get_name_stylebox() -> StyleBox:
	if _dialog_settings != null and _dialog_settings.has_method("get_name_stylebox"):
		return _dialog_settings.get_name_stylebox()
	return _get_box_stylebox()


## 获取默认打字速度
func _get_default_text_speed() -> float:
	if _override_text_speed > 0:
		return _override_text_speed
	if _dialog_settings != null and "default_text_speed" in _dialog_settings:
		return _dialog_settings.default_text_speed
	return 30.0


## 设置覆盖打字速度（由 SET_TEXT_SPEED 命令调用）
## speed <= 0 表示恢复默认
var _override_text_speed: float = 0.0

func set_override_text_speed(speed: float) -> void:
	_override_text_speed = speed


## 获取当前实际参考尺寸（DialogBox 自身 size，跟随 viewport 缩放）
func _get_reference_size() -> Vector2:
	var s: Vector2 = size
	if s.x > 0 and s.y > 0:
		return s
	return _project_resolution


## 获取对话框像素尺寸（基于实际参考尺寸）
func _get_box_pixel_size() -> Vector2:
	var ref: Vector2 = _get_reference_size()
	if _dialog_settings != null and "box_norm_size" in _dialog_settings:
		return _dialog_settings.box_norm_size * ref
	return Vector2(ref.x * 0.83, ref.y * 0.28)


## 获取对话框间距（按比例缩放）
func _get_box_margin() -> int:
	var base_margin: int = 40
	if _dialog_settings != null and "box_margin" in _dialog_settings:
		base_margin = _dialog_settings.box_margin
	var ref_scale: float = _get_reference_size().y / _project_resolution.y
	return int(base_margin * ref_scale)


## 获取名字框归一化偏移
func _get_name_norm_offset() -> Vector2:
	if _dialog_settings != null and "name_norm_offset" in _dialog_settings:
		return _dialog_settings.name_norm_offset
	return Vector2(0.02, -0.06)


## 获取名字框像素尺寸（基于实际参考尺寸）
func _get_name_pixel_size() -> Vector2:
	var ref: Vector2 = _get_reference_size()
	if _dialog_settings != null and "name_norm_size" in _dialog_settings:
		return _dialog_settings.name_norm_size * ref
	return Vector2(ref.x * 0.15, ref.y * 0.05)


# =============================================================================
# Save / Restore — 存档/读档用
# =============================================================================

## 获取当前对话框状态（用于存档）
func get_state() -> Dictionary:
	var state: Dictionary = {
		"visible": visible,
		"full_text": _full_text,
		"speaker": name_label.text if name_label != null else "",
		"name_visible": name_panel.visible if name_panel != null else false,
		"position": _last_position,
		"transparent": _last_transparent,
	}
	return state


## 从存档数据恢复对话框状态（不触发打字机，直接显示）
func restore_state(state: Dictionary) -> void:
	var should_visible: bool = state.get("visible", false)
	var full_text: String = state.get("full_text", "")
	var speaker: String = state.get("speaker", "")
	var name_visible: bool = state.get("name_visible", false)
	var box_position: String = state.get("position", "default")
	var transparent: bool = state.get("transparent", false)

	# 停止任何正在进行的打字机
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
		_type_tween = null
	_is_typing = false

	# 恢复文本
	_full_text = full_text
	if text_label != null:
		text_label.text = full_text
		text_label.visible_characters = -1  # 显示全部

	# 恢复说话者
	if name_label != null:
		name_label.text = speaker
	if name_panel != null:
		name_panel.visible = name_visible

	# 恢复位置和透明度
	_last_position = box_position
	_last_transparent = transparent
	_update_position(box_position)
	_update_transparency(transparent)

	# 恢复可见性
	visible = should_visible

	# 显示点击指示器（如果对话框可见且有文本）
	if click_indicator != null:
		click_indicator.visible = should_visible and not full_text.is_empty()
		if click_indicator.visible:
			_start_indicator_animation()
		else:
			_stop_indicator_animation()
