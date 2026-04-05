extends Control
## 天数过渡动画测试脚本 —— 模拟 GameLoopManager.day_changed 信号

var _overlay: Node = null
var _simulated_day: int = 1


func _ready() -> void:
	print("[TestDayTransition] 按 Space 触发换天动画")
	print("[TestDayTransition] 按 R   重置到第 1 天")

	# 加载并实例化过渡场景
	var overlay_scene: PackedScene = load("res://scenes/pseudo_os/day_transition_overlay.tscn")
	_overlay = overlay_scene.instantiate()
	add_child(_overlay)

	# 没有真正的 GameLoopManager，手动初始化
	_overlay._last_known_day = _simulated_day
	print("[TestDayTransition] 当前模拟天数: %d" % _simulated_day)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_trigger_next_day()
			KEY_R:
				_simulated_day = 1
				_overlay._last_known_day = 1
				print("[TestDayTransition] 已重置到第 1 天")


func _trigger_next_day() -> void:
	if _overlay._is_playing:
		print("[TestDayTransition] 动画播放中，请等待")
		return
	var old_day: int = _simulated_day
	_simulated_day += 1
	print("[TestDayTransition] 换天: %d → %d" % [old_day, _simulated_day])
	_overlay.play_transition(old_day, _simulated_day)
