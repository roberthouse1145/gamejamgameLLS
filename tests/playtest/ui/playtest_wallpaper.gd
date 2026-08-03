extends Control
## 按键切换两张中性测试纹理，人工检查壁纸淡入。

const WallpaperManagerScript = preload("res://scripts/pseudo_os/wallpaper_manager.gd")
var _wallpaper_manager: Node = null
var _show_first_texture: bool = true
var _first_texture: Texture2D = null
var _second_texture: Texture2D = null


func _ready() -> void:
	print("[PlaytestWallpaper] 按 Space 切换测试纹理")
	_first_texture = _make_texture(Color("#17233D"), Color("#4B6FA8"))
	_second_texture = _make_texture(Color("#2C1847"), Color("#8B5FBF"))
	_wallpaper_manager = WallpaperManagerScript.new()
	add_child(_wallpaper_manager)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_show_first_texture = not _show_first_texture
		_wallpaper_manager.set_wallpaper(_first_texture if _show_first_texture else _second_texture)


func _make_texture(first_color: Color, second_color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([first_color, second_color])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 2560
	texture.height = 1440
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.ONE
	return texture
