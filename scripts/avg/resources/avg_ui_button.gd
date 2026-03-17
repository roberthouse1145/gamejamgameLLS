class_name AVGUIButton extends Resource
## 游戏内 UI 按钮配置（单个按钮）
## 如：存档、读档、自动、快进、历史、隐藏UI、设置、菜单

## 按钮动作类型
const ACTIONS: Array[String] = [
	"save", "load", "auto", "skip", "log", "hide_ui", "settings", "menu",
]

## 动作 → 默认中文名
const ACTION_NAMES: Dictionary = {
	"save": "存档",
	"load": "读档",
	"auto": "自动",
	"skip": "快进",
	"log": "历史",
	"hide_ui": "隐藏",
	"settings": "设置",
	"menu": "菜单",
}

@export var button_id: String = ""
@export var display_text: String = ""
@export var action: String = ""  ## ACTIONS 中的值
@export var visible_default: bool = true
@export var norm_position: Vector2 = Vector2(0.9, 0.95)
@export var size: Vector2 = Vector2(100, 40)
@export var font_size: int = 20
@export var order: int = 0


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "button_id", "type": TYPE_STRING, "editable": false, "category": "基本"},
		{"name": "display_text", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "action", "type": TYPE_STRING, "editable": true, "category": "基本", "hint": "choices", "options": ACTIONS},
		{"name": "visible_default", "type": TYPE_BOOL, "editable": true, "category": "基本"},
		{"name": "norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "布局"},
		{"name": "size", "type": TYPE_VECTOR2, "editable": true, "category": "布局"},
		{"name": "font_size", "type": TYPE_INT, "editable": true, "category": "布局"},
		{"name": "order", "type": TYPE_INT, "editable": true, "category": "布局"},
	]


## 创建一个默认按钮
static func create_default(p_action: String, p_order: int, p_norm_pos: Vector2) -> AVGUIButton:
	var btn := AVGUIButton.new()
	btn.button_id = p_action
	btn.display_text = ACTION_NAMES.get(p_action, p_action)
	btn.action = p_action
	btn.order = p_order
	btn.norm_position = p_norm_pos
	return btn
