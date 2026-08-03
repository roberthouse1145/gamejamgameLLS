class_name Main extends Control
## 中性基础设施入口。具体游戏流程由后续项目接入。

const DesktopScene: PackedScene = preload("res://scenes/pseudo_os/desktop.tscn")


func _ready() -> void:
	var desktop: Control = DesktopScene.instantiate()
	add_child(desktop)
