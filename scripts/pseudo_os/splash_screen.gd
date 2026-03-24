class_name SplashScreen extends Control
## 传统的 Galgame 工作室/引擎 Logo 闪屏展出

signal splash_finished

@onready var engine_logo: Control = %EngineLogo
@onready var studio_logo: Control = %StudioLogo

func _ready() -> void:
	engine_logo.modulate.a = 0.0
	studio_logo.modulate.a = 0.0
	# 确保一开始鼠标不可点，并隐形
	mouse_filter = MOUSE_FILTER_IGNORE
	_play_sequence()


func _play_sequence() -> void:
	var tw: Tween = create_tween()
	tw.set_parallel(false)
	
	# 停顿 0.5s
	tw.tween_interval(0.5)
	
	# 引擎 Logo 淡入留存淡出
	tw.tween_property(engine_logo, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.5)
	tw.tween_property(engine_logo, "modulate:a", 0.0, 0.8)
	
	# 停顿 0.5s
	tw.tween_interval(0.5)
	
	# 工作室 Logo 淡入留存淡出
	tw.tween_property(studio_logo, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.5)
	tw.tween_property(studio_logo, "modulate:a", 0.0, 0.8)
	
	# 停顿并结束
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: splash_finished.emit())
