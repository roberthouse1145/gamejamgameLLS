class_name AVGTitleConfig extends Resource
## 标题界面配置资源
## 存储标题界面的所有可定制属性。

## ---- 开关 ----
@export var enabled: bool = true  ## 是否显示标题界面
@export var first_scene_id: String = ""  ## "开始游戏"跳转的场景 ID

## ---- 背景 ----
@export var background_color: Color = Color(0.05, 0.05, 0.1, 1.0)  ## 背景颜色
@export var background_image: String = ""  ## 背景图路径（相对于项目资源目录）

## ---- 标题文字 ----
@export var title_text: String = ""  ## 标题文字（空则使用 project_name）
@export var title_norm_position: Vector2 = Vector2(0.5, 0.25)  ## 归一化位置（锚点=中心）
@export var title_font_size: int = 72
@export var title_color: Color = Color.WHITE

## ---- 按钮通用 ----
@export var button_font_size: int = 28
@export var button_size: Vector2 = Vector2(300, 60)  ## 按钮像素尺寸（设计分辨率下）
@export var button_spacing: float = 20.0  ## 按钮间距（像素）

## ---- 开始游戏按钮 ----
@export var start_button_text: String = "开始游戏"
@export var start_button_norm_position: Vector2 = Vector2(0.5, 0.55)  ## 归一化位置（锚点=中心）

## ---- 读档按钮 ----
@export var load_button_text: String = "读档"
@export var load_button_enabled: bool = false  ## TODO: LOAD_GAME 实现后启用
@export var load_button_norm_position: Vector2 = Vector2(0.5, 0.62)

## ---- 设置按钮 ----
@export var settings_button_text: String = "设置"
@export var settings_button_enabled: bool = false  ## TODO: OPEN_MENU 实现后启用
@export var settings_button_norm_position: Vector2 = Vector2(0.5, 0.69)


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "enabled", "type": TYPE_BOOL, "editable": true, "category": "基本"},
		{"name": "first_scene_id", "type": TYPE_STRING, "editable": false, "category": "基本", "hint": "scene_selector"},
		{"name": "background_color", "type": TYPE_COLOR, "editable": true, "category": "背景"},
		{"name": "background_image", "type": TYPE_STRING, "editable": true, "category": "背景"},
		{"name": "title_text", "type": TYPE_STRING, "editable": true, "category": "标题文字"},
		{"name": "title_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "标题文字"},
		{"name": "title_font_size", "type": TYPE_INT, "editable": true, "category": "标题文字"},
		{"name": "title_color", "type": TYPE_COLOR, "editable": true, "category": "标题文字"},
		{"name": "button_font_size", "type": TYPE_INT, "editable": true, "category": "按钮通用"},
		{"name": "button_size", "type": TYPE_VECTOR2, "editable": true, "category": "按钮通用"},
		{"name": "button_spacing", "type": TYPE_FLOAT, "editable": true, "category": "按钮通用"},
		{"name": "start_button_text", "type": TYPE_STRING, "editable": true, "category": "开始游戏"},
		{"name": "start_button_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "开始游戏"},
		{"name": "load_button_text", "type": TYPE_STRING, "editable": true, "category": "读档"},
		{"name": "load_button_enabled", "type": TYPE_BOOL, "editable": true, "category": "读档"},
		{"name": "load_button_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "读档"},
		{"name": "settings_button_text", "type": TYPE_STRING, "editable": true, "category": "设置"},
		{"name": "settings_button_enabled", "type": TYPE_BOOL, "editable": true, "category": "设置"},
		{"name": "settings_button_norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "设置"},
	]


## 解析初始场景索引：用 first_scene_id 在项目场景列表中查找
func resolve_first_scene_index(project: Resource) -> int:
	if project == null or not "scenes" in project:
		return 0
	if first_scene_id.is_empty():
		return 0
	for i in range(project.scenes.size()):
		var scene = project.scenes[i]
		if scene != null and "scene_id" in scene and scene.scene_id == first_scene_id:
			return i
	return 0
