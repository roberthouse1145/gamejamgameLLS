extends Control
## 时段壁纸切换测试 —— 用按键模拟 phase_changed

var _wallpaper_mgr: Node = null
var _simulated_phase: int = 0  # 0=MORNING, 1=AFTERNOON, 2=NIGHT
const PHASE_NAMES: Array[String] = ["上午 (MORNING)", "下午 (AFTERNOON)", "晚上 (NIGHT)"]


func _ready() -> void:
	print("[TestWallpaper] 按 Space 切换到下一个时段")
	print("[TestWallpaper] 按 1/2/3 直接跳到 上午/下午/晚上")
	print("[TestWallpaper] 当前时段: %s" % PHASE_NAMES[_simulated_phase])

	var WallpaperManagerScript = preload("res://scripts/pseudo_os/wallpaper_manager.gd")
	_wallpaper_mgr = WallpaperManagerScript.new()
	_wallpaper_mgr.name = "WallpaperManager"
	add_child(_wallpaper_mgr)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_SPACE:
			_simulated_phase = (_simulated_phase + 1) % 3
			print("[TestWallpaper] → %s" % PHASE_NAMES[_simulated_phase])
			_wallpaper_mgr._crossfade_to(_simulated_phase)
		KEY_1:
			_simulated_phase = 0
			print("[TestWallpaper] → %s" % PHASE_NAMES[0])
			_wallpaper_mgr._crossfade_to(0)
		KEY_2:
			_simulated_phase = 1
			print("[TestWallpaper] → %s" % PHASE_NAMES[1])
			_wallpaper_mgr._crossfade_to(1)
		KEY_3:
			_simulated_phase = 2
			print("[TestWallpaper] → %s" % PHASE_NAMES[2])
			_wallpaper_mgr._crossfade_to(2)
