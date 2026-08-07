class_name StreamSceneDisplay extends Control
## StreamScene 的视觉显示层：直播背景与主播立绘。

@export var background_texture: Texture2D = null
@export_range(0.0, 2.0, 0.05) var expression_fade_duration: float = 0.2

@onready var _background: TextureRect = %Background
@onready var _portrait_current: TextureRect = %PortraitCurrent
@onready var _portrait_outgoing: TextureRect = %PortraitOutgoing

var _streamer: StreamerCharacterResource = null
var _current_expression: StringName = &""
var _fade_tween: Tween = null


func _ready() -> void:
	_background.texture = background_texture
	_portrait_current.modulate.a = 1.0
	_portrait_outgoing.modulate.a = 0.0
	resized.connect(_layout_portraits)


func setup(streamer: StreamerCharacterResource) -> void:
	_streamer = streamer
	_background.texture = background_texture
	_current_expression = &""
	_portrait_current.texture = null
	_portrait_outgoing.texture = null
	_portrait_current.modulate.a = 1.0
	_portrait_outgoing.modulate.a = 0.0
	if _streamer != null:
		set_expression(_streamer.default_expression, 0.0)


func set_background(texture: Texture2D) -> void:
	background_texture = texture
	if _background != null:
		_background.texture = texture


func set_expression(expression_name: StringName, duration: float = -1.0) -> bool:
	if _streamer == null or not _streamer.has_expression(expression_name):
		return false
	if expression_name == _current_expression and _portrait_current.texture != null:
		return true
	var texture: Texture2D = _streamer.get_expression_texture(expression_name)
	if texture == null:
		return false

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var fade_time: float = expression_fade_duration if duration < 0.0 else maxf(duration, 0.0)

	if _portrait_current.texture == null or fade_time <= 0.0:
		_portrait_current.texture = texture
		_portrait_current.modulate.a = 1.0
		_portrait_outgoing.texture = null
		_portrait_outgoing.modulate.a = 0.0
		_layout_portrait(_portrait_current)
	else:
		# 新表情在底层保持完全不透明，旧表情叠在上层并单独淡出。
		_portrait_outgoing.texture = _portrait_current.texture
		_portrait_outgoing.modulate.a = 1.0
		_portrait_current.texture = texture
		_portrait_current.modulate.a = 1.0
		_layout_portrait(_portrait_current)
		_layout_portrait(_portrait_outgoing)
		_fade_tween = create_tween()
		_fade_tween.tween_property(_portrait_outgoing, "modulate:a", 0.0, fade_time)

	_current_expression = expression_name
	return true


func get_current_expression() -> StringName:
	return _current_expression


func _layout_portraits() -> void:
	_layout_portrait(_portrait_current)
	_layout_portrait(_portrait_outgoing)


func _layout_portrait(portrait: TextureRect) -> void:
	if portrait == null or portrait.texture == null or _streamer == null:
		return
	var texture_size: Vector2 = portrait.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or size.y <= 0.0:
		return
	var target_height: float = size.y * _streamer.portrait_scale
	var target_size := Vector2(target_height * texture_size.x / texture_size.y, target_height)
	var center: Vector2 = size * 0.5 + _streamer.portrait_offset * size
	portrait.size = target_size
	portrait.position = center - target_size * 0.5
