extends Control
## 桌面壁纸管理器，提供可复用的壁纸切换与淡入能力。

## 渐变持续时间（秒）
const CROSSFADE_DURATION: float = 1.0

signal wallpaper_changed(texture: Texture2D)

var _bottom: TextureRect   # 当前显示层
var _top: TextureRect      # 淡入目标层
var _tween: Tween = null


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	# 底层（当前壁纸）
	_bottom = _create_layer("WallpaperBottom")
	add_child(_bottom)

	# 顶层（将要淡入的壁纸）
	_top = _create_layer("WallpaperTop")
	_top.modulate.a = 0.0
	add_child(_top)

	set_wallpaper(_create_default_wallpaper(), false)


func _create_default_wallpaper() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color("#17233D"), Color("#4B6FA8")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 3840
	texture.height = 2160
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.ONE
	return texture


func _create_layer(layer_name: String) -> TextureRect:
	var tex_rect := TextureRect.new()
	tex_rect.name = layer_name
	tex_rect.set_anchors_preset(PRESET_FULL_RECT)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.mouse_filter = MOUSE_FILTER_IGNORE
	return tex_rect


func set_wallpaper(texture: Texture2D, animated: bool = true) -> void:
	if texture == null:
		return
	if not animated or _bottom.texture == null:
		_bottom.texture = texture
		_bottom.modulate.a = 1.0
		_top.modulate.a = 0.0
		wallpaper_changed.emit(texture)
		return
	_crossfade_to(texture)


func _crossfade_to(texture: Texture2D) -> void:
	# 如果上一次渐变还在进行，立即完成它
	if _tween and _tween.is_valid():
		_tween.kill()
		_bottom.texture = _top.texture
		_bottom.modulate.a = 1.0
		_top.modulate.a = 0.0

	# 顶层放新壁纸，从透明渐入
	_top.texture = texture
	_top.modulate.a = 0.0

	_tween = create_tween()
	_tween.tween_property(_top, "modulate:a", 1.0, CROSSFADE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_crossfade_done.bind(texture))


func _on_crossfade_done(texture: Texture2D) -> void:
	# 把底层替换为新壁纸，重置顶层
	_bottom.texture = _top.texture
	_bottom.modulate.a = 1.0
	_top.modulate.a = 0.0
	wallpaper_changed.emit(texture)
