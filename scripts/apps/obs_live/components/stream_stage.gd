class_name StreamStage extends Control
## 直播镜头视窗：房间背景 + 半身立绘 + 字幕气泡 + 当前节目信息。

const AVG_CHARACTER: AVGCharacter = preload("res://resources/avg/characters/ruan_yunyou.tres")
const ROOM_BG: Texture2D = preload("res://Assets/images/backgrounds/yunyou_desktop.png")

const COLOR_PAGE: Color = Color("#F0F4F8")
const COLOR_CARD: Color = Color("#FFFFFF")
const COLOR_BORDER: Color = Color("#C8D6EA")
const COLOR_TEXT: Color = Color("#1A2238")
const COLOR_TEXT_MUTED: Color = Color("#5A6885")
const COLOR_ACCENT: Color = Color("#E5486D")
const COLOR_FAMILY: Color = Color("#3A5FA8")
const COLOR_SUBTITLE_BG: Color = Color(1.0, 1.0, 1.0, 0.92)

var _camera_clip: Control = null
var _room_rect: TextureRect = null
var _character_rect: TextureRect = null
var _subtitle_label: Label = null
var _program_label: Label = null
var _texture_cache: Dictionary = {}
var _current_program: String = ""


func _ready() -> void:
	var page_bg := ColorRect.new()
	page_bg.color = COLOR_PAGE
	page_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var camera_card := PanelContainer.new()
	camera_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camera_card.add_theme_stylebox_override("panel", _make_style(COLOR_CARD, COLOR_BORDER, 18, true))
	root.add_child(camera_card)

	var camera_margin := MarginContainer.new()
	camera_margin.add_theme_constant_override("margin_left", 10)
	camera_margin.add_theme_constant_override("margin_top", 10)
	camera_margin.add_theme_constant_override("margin_right", 10)
	camera_margin.add_theme_constant_override("margin_bottom", 10)
	camera_card.add_child(camera_margin)

	_camera_clip = Control.new()
	_camera_clip.clip_contents = true
	_camera_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camera_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_camera_clip.resized.connect(_layout_camera_contents)
	camera_margin.add_child(_camera_clip)

	_room_rect = TextureRect.new()
	_room_rect.texture = ROOM_BG
	_room_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_room_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_room_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_clip.add_child(_room_rect)

	_character_rect = TextureRect.new()
	_character_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_character_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_clip.add_child(_character_rect)
	_set_emotion("default")

	var subtitle_panel := PanelContainer.new()
	subtitle_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle_panel.offset_left = 24
	subtitle_panel.offset_right = -24
	subtitle_panel.offset_bottom = -20
	subtitle_panel.offset_top = -120
	subtitle_panel.add_theme_stylebox_override("panel", _make_style(COLOR_SUBTITLE_BG, COLOR_BORDER, 14, false))
	_camera_clip.add_child(subtitle_panel)
	var subtitle_margin := MarginContainer.new()
	subtitle_margin.add_theme_constant_override("margin_left", 22)
	subtitle_margin.add_theme_constant_override("margin_top", 14)
	subtitle_margin.add_theme_constant_override("margin_right", 22)
	subtitle_margin.add_theme_constant_override("margin_bottom", 14)
	subtitle_panel.add_child(subtitle_margin)
	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 28)
	_subtitle_label.add_theme_color_override("font_color", COLOR_TEXT)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_margin.add_child(_subtitle_label)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 12)
	root.add_child(meta_row)
	var meta_badge := Label.new()
	meta_badge.text = "▶"
	meta_badge.add_theme_font_size_override("font_size", 22)
	meta_badge.add_theme_color_override("font_color", COLOR_ACCENT)
	meta_row.add_child(meta_badge)
	_program_label = Label.new()
	_program_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_program_label.add_theme_font_size_override("font_size", 22)
	_program_label.add_theme_color_override("font_color", COLOR_FAMILY)
	_program_label.text = "准备开播"
	meta_row.add_child(_program_label)

	call_deferred("_layout_camera_contents")


func show_beat(beat: Dictionary) -> void:
	_subtitle_label.text = String(beat.get("line", ""))
	_set_emotion(String(beat.get("emotion", "default")))
	_update_program(beat)
	var tween := create_tween()
	tween.tween_property(_character_rect, "modulate:a", 0.7, 0.1)
	tween.tween_property(_character_rect, "modulate:a", 1.0, 0.18)


func _update_program(beat: Dictionary) -> void:
	if beat.get("kind") != StreamShowDirector.KIND_CARD:
		_program_label.text = _current_program if not _current_program.is_empty() else "直播中"
		return
	var fill_ratio: float = float(beat.get("fill_ratio", 1.0))
	var fill_multiplier: float = float(beat.get("fill_multiplier", 1.0))
	var fill_text: String = "满填充 ×%.1f" % fill_multiplier if fill_ratio >= 1.0 else "接缝 %d%% ×%.1f" % [int(round(fill_ratio * 100.0)), fill_multiplier]
	_current_program = "当前节目：%s　·　%s" % [String(beat.get("card_name", "")), fill_text]
	_program_label.text = _current_program


func _set_emotion(emotion: String) -> void:
	var texture: Texture2D = _load_emotion_texture(emotion)
	if texture == null and emotion != "default":
		texture = _load_emotion_texture("default")
	if texture != null:
		_character_rect.texture = texture
		_layout_camera_contents()


func _layout_camera_contents() -> void:
	if _camera_clip == null or _character_rect == null:
		return
	var view_size: Vector2 = _camera_clip.size
	if view_size.x < 2.0 or view_size.y < 2.0:
		return
	var texture: Texture2D = _character_rect.texture
	if texture == null:
		return
	var tex_size: Vector2 = texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	# 按视窗宽度铺开立绘，底部裁切，形成半身镜头。
	var aspect: float = tex_size.x / tex_size.y
	var draw_w: float = view_size.x * 0.72
	var draw_h: float = draw_w / aspect
	var boost: float = maxf(AVG_CHARACTER.display_scale, 1.0)
	draw_w *= boost
	draw_h *= boost
	var x: float = (view_size.x - draw_w) * 0.5
	# 把头肩放进画面上半区，脚部裁到镜头外。
	var y: float = view_size.y - draw_h * 0.58
	y += AVG_CHARACTER.display_offset.y * view_size.y * 0.15
	_character_rect.position = Vector2(x, y)
	_character_rect.size = Vector2(draw_w, draw_h)


func _load_emotion_texture(emotion: String) -> Texture2D:
	if _texture_cache.has(emotion):
		return _texture_cache[emotion]
	var texture: Texture2D = null
	var slot: String = str(AVG_CHARACTER.emotion_slots.get(emotion, ""))
	if not slot.is_empty() and not AVG_CHARACTER.sprite_path_pattern.is_empty():
		var path: String = AVG_CHARACTER.sprite_path_pattern \
			.replace("{outfit}", AVG_CHARACTER.default_outfit) \
			.replace("{slot}", slot) \
			.replace("{character_key}", AVG_CHARACTER.character_key)
		if ResourceLoader.exists(path):
			texture = load(path)
	_texture_cache[emotion] = texture
	return texture


func _make_style(bg_color: Color, border_color: Color, radius: int, with_shadow: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border_color.a > 0.0:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = border_color
	if with_shadow:
		style.shadow_color = Color(0.18, 0.22, 0.32, 0.08)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 2)
	return style
