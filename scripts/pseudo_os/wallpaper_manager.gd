extends Control
## 时段壁纸管理器 —— 根据 GameLoopManager.phase_changed 自动切换壁纸（crossfade）。
## 放在 Desktop 的 Background 层上方，作为子节点挂载。

const WALLPAPER_MORNING: String = "res://Assets/images/wallpapers/day.png"
const WALLPAPER_AFTERNOON: String = "res://Assets/images/wallpapers/noon.png"
const WALLPAPER_NIGHT: String = "res://Assets/images/wallpapers/night.png"

## 渐变持续时间（秒）
const CROSSFADE_DURATION: float = 1.0

## 当壁纸切换完成时发出 —— phase: GameLoopManager.TimePhase
signal wallpaper_changed(phase: int)

var _bottom: TextureRect   # 当前显示层
var _top: TextureRect      # 淡入目标层
var _current_phase: int = -1
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

	# 连接信号
	var glm := get_node_or_null("/root/GameLoopManager")
	if glm:
		_apply_phase_instant(glm.time_phase)
		glm.phase_changed.connect(_on_phase_changed)
	else:
		# 没有 GameLoopManager 时默认用早晨壁纸
		_apply_phase_instant(0)


func _create_layer(layer_name: String) -> TextureRect:
	var tex_rect := TextureRect.new()
	tex_rect.name = layer_name
	tex_rect.set_anchors_preset(PRESET_FULL_RECT)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.mouse_filter = MOUSE_FILTER_IGNORE
	return tex_rect


func _get_wallpaper_for_phase(phase: int) -> Texture2D:
	var path: String
	match phase:
		0:  # MORNING
			path = WALLPAPER_MORNING
		1:  # AFTERNOON
			path = WALLPAPER_AFTERNOON
		2:  # NIGHT
			path = WALLPAPER_NIGHT
		_:
			path = WALLPAPER_MORNING
	return load(path) as Texture2D


## 立即设置壁纸（无动画），用于初始化或存档加载
func _apply_phase_instant(phase: int) -> void:
	_current_phase = phase
	var tex := _get_wallpaper_for_phase(phase)
	_bottom.texture = tex
	_bottom.modulate.a = 1.0
	_top.modulate.a = 0.0


func _on_phase_changed(new_phase: int) -> void:
	if new_phase == _current_phase:
		return
	_crossfade_to(new_phase)


func _crossfade_to(phase: int) -> void:
	# 如果上一次渐变还在进行，立即完成它
	if _tween and _tween.is_valid():
		_tween.kill()
		_bottom.texture = _top.texture
		_bottom.modulate.a = 1.0
		_top.modulate.a = 0.0

	_current_phase = phase
	var new_tex := _get_wallpaper_for_phase(phase)

	# 顶层放新壁纸，从透明渐入
	_top.texture = new_tex
	_top.modulate.a = 0.0

	_tween = create_tween()
	_tween.tween_property(_top, "modulate:a", 1.0, CROSSFADE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_crossfade_done.bind(phase))


func _on_crossfade_done(phase: int) -> void:
	# 把底层替换为新壁纸，重置顶层
	_bottom.texture = _top.texture
	_bottom.modulate.a = 1.0
	_top.modulate.a = 0.0
	wallpaper_changed.emit(phase)
