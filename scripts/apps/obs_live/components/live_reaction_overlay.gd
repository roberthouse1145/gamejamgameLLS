class_name LiveReactionOverlay extends Control
## 直播画面内的弹幕与打赏礼物动画。右侧聊天栏仍由 StreamChat 独立显示。

const GIFT_TEXTURES: Array[Texture2D] = [
	preload("res://Assets/images/live_stream/gifts/strawberry_shortcake.png"),
	preload("res://Assets/images/live_stream/gifts/swirl_lollipop.png"),
	preload("res://Assets/images/live_stream/gifts/glowsticks.png"),
	preload("res://Assets/images/live_stream/gifts/citrus_soda.png"),
	preload("res://Assets/images/live_stream/gifts/rose_bouquet.png"),
	preload("res://Assets/images/live_stream/gifts/jeweled_tiara.png"),
]
const MAX_SCREEN_CHAT_ITEMS: int = 28
const MAX_GIFT_ITEMS: int = 8

@export_group("Live Reactions")
@export var screen_chat_enabled: bool = true
@export var donation_animation_enabled: bool = true

var _rng := RandomNumberGenerator.new()
var _lane_cursor: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func reset(seed_value: int) -> void:
	clear()
	_rng.seed = seed_value ^ 0x71F7A11
	_lane_cursor = _rng.randi_range(0, 7)


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()


func set_screen_chat_enabled(enabled: bool) -> void:
	screen_chat_enabled = enabled
	if not enabled:
		_clear_effect_kind(&"screen_chat")


func set_donation_animation_enabled(enabled: bool) -> void:
	donation_animation_enabled = enabled
	if not enabled:
		_clear_effect_kind(&"gift")


func handle_live_chat_event(event: Dictionary) -> void:
	var kind: String = str(event.get("kind", ""))
	match kind:
		"send":
			if not screen_chat_enabled:
				return
			var entries: Array = event.get("entries", [])
			for value: Variant in entries:
				if value is Dictionary:
					_spawn_screen_chat(str(value.get("text", "")), Color.WHITE, false)
		"sc":
			var text: String = str(event.get("text", "")).strip_edges()
			var color: Color = _read_color(event.get("color", Color("#E5486D")))
			if screen_chat_enabled:
				_spawn_screen_chat(text, color, true)
			if donation_animation_enabled:
				_spawn_donation_gift(color)


func _spawn_screen_chat(text: String, color: Color, is_superchat: bool) -> void:
	if text.strip_edges().is_empty() or size.x < 2.0 or size.y < 2.0:
		return
	_trim_effect_kind(&"screen_chat", MAX_SCREEN_CHAT_ITEMS)

	var item: Control
	if is_superchat:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _make_superchat_style(color))
		var label := _make_screen_chat_label(text, Color.WHITE)
		panel.add_child(label)
		item = panel
	else:
		item = _make_screen_chat_label(text, Color.WHITE)

	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("effect_kind", &"screen_chat")
	add_child(item)
	item.size = item.get_combined_minimum_size()

	var lane_height: float = maxf(item.size.y + 10.0, 52.0)
	var top_safe: float = 104.0
	var bottom_safe: float = 148.0
	var usable_height: float = maxf(size.y - top_safe - bottom_safe, lane_height)
	var lane_count: int = maxi(int(floor(usable_height / lane_height)), 1)
	var lane: int = _lane_cursor % lane_count
	_lane_cursor += _rng.randi_range(1, 2)
	var y: float = top_safe + float(lane) * lane_height + _rng.randf_range(-4.0, 4.0)
	item.position = Vector2(size.x + 28.0, y)

	var travel_seconds: float = _rng.randf_range(6.2, 8.4)
	if is_superchat:
		travel_seconds += 0.8
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "position:x", -item.size.x - 36.0, travel_seconds)
	tween.tween_callback(item.queue_free)


func _make_screen_chat_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.92))
	label.add_theme_constant_override("outline_size", 7)
	return label


func _make_superchat_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.88)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = color.lightened(0.32)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 18.0
	style.content_margin_top = 8.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 8.0
	return style


func _spawn_donation_gift(accent_color: Color) -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	_trim_effect_kind(&"gift", MAX_GIFT_ITEMS)

	var icon := TextureRect.new()
	icon.texture = GIFT_TEXTURES[_rng.randi_range(0, GIFT_TEXTURES.size() - 1)]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(144.0, 144.0)
	icon.size = icon.custom_minimum_size
	icon.pivot_offset = icon.size * 0.5
	icon.scale = Vector2.ZERO
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color.WHITE.lerp(accent_color.lightened(0.35), 0.08)
	icon.set_meta("effect_kind", &"gift")
	add_child(icon)

	var margin: float = 92.0
	var max_x: float = maxf(size.x - icon.size.x - margin, margin)
	var top_safe: float = 132.0
	var max_y: float = maxf(size.y - icon.size.y - 184.0, top_safe)
	var start_position := Vector2(
		_rng.randf_range(margin, max_x),
		_rng.randf_range(top_safe, max_y)
	)
	icon.position = start_position

	var tween: Tween = icon.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "scale", Vector2.ONE, 0.3)
	tween.parallel().tween_property(icon, "position:y", start_position.y - 46.0, 0.3)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "scale", Vector2(1.1, 1.1), 0.14)
	tween.tween_interval(0.16)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(icon, "scale", Vector2.ZERO, 0.38)
	tween.parallel().tween_property(icon, "position:y", start_position.y + 18.0, 0.38)
	tween.tween_callback(icon.queue_free)


func _read_color(value: Variant) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), Color("#E5486D"))


func _clear_effect_kind(kind: StringName) -> void:
	for child: Node in get_children():
		if child.get_meta("effect_kind", &"") == kind:
			child.queue_free()


func _trim_effect_kind(kind: StringName, maximum: int) -> void:
	var matching: Array[Node] = []
	for child: Node in get_children():
		if child.get_meta("effect_kind", &"") == kind:
			matching.append(child)
	while matching.size() >= maximum:
		var oldest: Node = matching.pop_front()
		oldest.queue_free()
