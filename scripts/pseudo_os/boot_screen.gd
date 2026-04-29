class_name BootScreen extends Control
## 自定义 OS 启动动画与年龄确认弹窗

signal boot_finished

@onready var log_container: VBoxContainer = %LogContainer
@onready var warning_popup: Control = %WarningPopup
@onready var agree_button: Button = %AgreeButton

var _boot_logs: Array[String] = [
	"[ OK ] Booting Link OS Core v1.0.0...",
	"[ OK ] Loading Engine Module...",
	"[ OK ] Studio Module Initialized...",
	"[ OK ] Checking User Age >= 18... [Pass] (´・ω・`)b",
	"[ OK ] Loading Love_Story.sys...",
	"[ OK ] System Ready."
]

func _ready() -> void:
	# 初始化 UI 状态
	warning_popup.modulate.a = 0.0
	warning_popup.visible = false
	
	agree_button.pressed.connect(_on_agree_pressed)
	# 按钮交互动画
	agree_button.pivot_offset = agree_button.size / 2.0
	agree_button.button_down.connect(func() -> void:
		var tw: Tween = create_tween()
		tw.tween_property(agree_button, "scale", Vector2(0.95, 0.95), 0.1)
	)
	agree_button.button_up.connect(func() -> void:
		var tw: Tween = create_tween()
		tw.tween_property(agree_button, "scale", Vector2.ONE, 0.1)
	)
	
	for child in log_container.get_children():
		child.queue_free()
		
	_play_boot_sequence()

func _play_boot_sequence() -> void:
	for i in range(_boot_logs.size()):
		await get_tree().create_timer(0.3).timeout
		var log_label := Label.new()
		log_label.text = _boot_logs[i]
		log_label.add_theme_font_size_override("font_size", 18)
		log_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		
		# 特殊行加点颜色
		if "[Pass]" in _boot_logs[i]:
			log_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1.0))
			
		log_container.add_child(log_label)
		
	await get_tree().create_timer(0.6).timeout
	_show_warning_popup()

func _show_warning_popup() -> void:
	warning_popup.visible = true
	var tw: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(warning_popup, "modulate:a", 1.0, 0.5)

func _on_agree_pressed() -> void:
	# 按钮按下的反馈
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: boot_finished.emit())
