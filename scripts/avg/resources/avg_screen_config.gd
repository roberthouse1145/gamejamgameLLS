class_name AVGScreenConfig extends Resource
## 通用子界面配置资源
## 用于菜单、存档、读档、历史记录、设置等界面的样式配置。

## 界面类型枚举
enum ScreenType {
	MENU = 0,      ## 菜单（暂停菜单）
	SAVE = 1,      ## 存档
	LOAD = 2,      ## 读档
	HISTORY = 3,   ## 历史记录
	SETTINGS = 4,  ## 设置
}

## 界面类型中文名
const SCREEN_TYPE_NAMES: Dictionary = {
	ScreenType.MENU: "菜单",
	ScreenType.SAVE: "存档",
	ScreenType.LOAD: "读档",
	ScreenType.HISTORY: "历史记录",
	ScreenType.SETTINGS: "设置",
}

## ---- 基本 ----
@export var screen_type: ScreenType = ScreenType.MENU
@export var enabled: bool = true

## ---- 背景 ----
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.85)
@export var background_image: String = ""

## ---- 标题 ----
@export var title_text: String = ""
@export var title_font_size: int = 48
@export var title_color: Color = Color.WHITE
@export var title_norm_position: Vector2 = Vector2(0.5, 0.08)

## ---- 内容面板 ----
@export var panel_style: Resource = null  # AVGStyleBox
@export var panel_norm_position: Vector2 = Vector2(0.5, 0.5)
@export var panel_norm_size: Vector2 = Vector2(0.8, 0.7)

## ---- 关闭按钮 ----
@export var close_button_text: String = "返回"
@export var close_button_norm_position: Vector2 = Vector2(0.5, 0.93)
@export var close_button_size: Vector2 = Vector2(200, 50)
@export var close_button_font_size: int = 24

## ---- 按钮样式 ----
@export var button_style: Resource = null  ## AVGStyleBox，按钮样式（自动派生 hover/pressed/disabled）

## ---- 菜单专用 ----
@export var menu_button_texts: PackedStringArray = PackedStringArray([
	"继续游戏", "存档", "读档", "历史记录", "设置", "回到标题", "退出游戏"
])
@export var menu_button_size: Vector2 = Vector2(280, 55)
@export var menu_button_font_size: int = 26
@export var menu_button_spacing: int = 12

## ---- 存档/读档专用 ----
@export var slot_count: int = 12
@export var grid_columns: int = 3
@export var slot_size: Vector2 = Vector2(300, 180)
@export var slot_spacing: int = 16

## ---- 历史记录专用 ----
@export var history_entry_font_size: int = 20
@export var history_entry_spacing: int = 8
@export var history_speaker_color: Color = Color(0.4, 0.8, 1.0)


## 获取默认标题文字
func get_display_title() -> String:
	if not title_text.is_empty():
		return title_text
	return SCREEN_TYPE_NAMES.get(screen_type, "界面")


## 初始化默认值（根据类型）
func init_defaults_for_type(type: ScreenType) -> void:
	screen_type = type
	match type:
		ScreenType.MENU:
			title_text = "菜单"
			panel_norm_size = Vector2(0.4, 0.7)
		ScreenType.SAVE:
			title_text = "存档"
			panel_norm_size = Vector2(0.85, 0.72)
		ScreenType.LOAD:
			title_text = "读档"
			panel_norm_size = Vector2(0.85, 0.72)
		ScreenType.HISTORY:
			title_text = "历史记录"
			panel_norm_size = Vector2(0.75, 0.75)
		ScreenType.SETTINGS:
			title_text = "设置"
			panel_norm_size = Vector2(0.6, 0.65)


## 属性定义（供 PropertyEditor 使用）
static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "enabled", "type": TYPE_BOOL, "editable": true, "category": "基本"},
		{"name": "background_color", "type": TYPE_COLOR, "editable": true, "category": "背景"},
		{"name": "background_image", "type": TYPE_STRING, "editable": true, "category": "背景"},
		{"name": "title_text", "type": TYPE_STRING, "editable": true, "category": "标题"},
		{"name": "title_font_size", "type": TYPE_INT, "editable": true, "category": "标题"},
		{"name": "title_color", "type": TYPE_COLOR, "editable": true, "category": "标题"},
		{"name": "title_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "标题"},
		{"name": "panel_style", "type": "sub_resource", "editable": true, "category": "内容面板",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
		{"name": "panel_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "内容面板"},
		{"name": "panel_norm_size", "type": TYPE_VECTOR2, "editable": true, "category": "内容面板"},
		{"name": "close_button_text", "type": TYPE_STRING, "editable": true, "category": "关闭按钮"},
		{"name": "close_button_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "关闭按钮"},
		{"name": "close_button_size", "type": TYPE_VECTOR2, "editable": true, "category": "关闭按钮"},
		{"name": "close_button_font_size", "type": TYPE_INT, "editable": true, "category": "关闭按钮"},
		{"name": "button_style", "type": "sub_resource", "editable": true, "category": "按钮样式",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
		# 菜单专用
		{"name": "menu_button_texts", "type": TYPE_PACKED_STRING_ARRAY, "editable": true, "category": "菜单按钮",
		 "visible_when": "screen_type == 0"},
		{"name": "menu_button_size", "type": TYPE_VECTOR2, "editable": true, "category": "菜单按钮",
		 "visible_when": "screen_type == 0"},
		{"name": "menu_button_font_size", "type": TYPE_INT, "editable": true, "category": "菜单按钮",
		 "visible_when": "screen_type == 0"},
		{"name": "menu_button_spacing", "type": TYPE_INT, "editable": true, "category": "菜单按钮",
		 "visible_when": "screen_type == 0"},
		# 存档/读档专用
		{"name": "slot_count", "type": TYPE_INT, "editable": true, "category": "存档槽",
		 "visible_when": "screen_type == 1 or screen_type == 2"},
		{"name": "grid_columns", "type": TYPE_INT, "editable": true, "category": "存档槽",
		 "visible_when": "screen_type == 1 or screen_type == 2"},
		{"name": "slot_size", "type": TYPE_VECTOR2, "editable": true, "category": "存档槽",
		 "visible_when": "screen_type == 1 or screen_type == 2"},
		{"name": "slot_spacing", "type": TYPE_INT, "editable": true, "category": "存档槽",
		 "visible_when": "screen_type == 1 or screen_type == 2"},
		# 历史记录专用
		{"name": "history_entry_font_size", "type": TYPE_INT, "editable": true, "category": "历史记录",
		 "visible_when": "screen_type == 3"},
		{"name": "history_entry_spacing", "type": TYPE_INT, "editable": true, "category": "历史记录",
		 "visible_when": "screen_type == 3"},
		{"name": "history_speaker_color", "type": TYPE_COLOR, "editable": true, "category": "历史记录",
		 "visible_when": "screen_type == 3"},
	]
