class_name AVGGameUIConfig extends Resource
## 游戏内 UI 配置（非标题界面的常驻按钮面板）
## 管理存档/读档/自动/快进/历史/隐藏UI/设置/菜单等按钮

const AVGUIButtonClass = preload("res://scripts/avg/resources/avg_ui_button.gd")

@export var buttons: Array = []  ## Array[AVGUIButton]
@export var show_on_title: bool = false
@export var panel_bg_color: Color = Color(0, 0, 0, 0.3)
@export var panel_opacity: float = 1.0
@export var button_style: Resource = null  ## AVGStyleBox，按钮样式（自动派生 hover/pressed/disabled）


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "show_on_title", "type": TYPE_BOOL, "editable": true, "category": "通用"},
		{"name": "panel_bg_color", "type": TYPE_COLOR, "editable": true, "category": "通用"},
		{"name": "panel_opacity", "type": TYPE_FLOAT, "editable": true, "category": "通用"},
		{"name": "button_style", "type": "sub_resource", "editable": true, "category": "通用",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
	]


## 初始化默认按钮（8 个常见 AVG 按钮，横排在底部右侧）
func init_defaults() -> void:
	buttons.clear()
	var actions: Array[String] = ["save", "load", "auto", "skip", "log", "hide_ui", "settings", "menu"]
	var count: int = actions.size()
	for i in range(count):
		# 横排排列：从左到右，y 固定在底部
		var x: float = 0.55 + i * 0.055
		var pos := Vector2(x, 0.96)
		var btn: Resource = AVGUIButtonClass.create_default(actions[i], i, pos)
		buttons.append(btn)
