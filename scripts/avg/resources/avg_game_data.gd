class_name AVGGameData extends Resource
## 游戏本体唯一的 AVG 数据资源。

const DATA_PATH: String = "res://resources/avg/game_data.tres"

@export var game_name: String = "未命名游戏"
@export var resolution: Vector2i = Vector2i(2560, 1440)
@export var dialog_settings: Resource  # AVGDialogSettings
@export var scenes: Array = []  # Array of AVGScene
@export var characters: Array = []  # Array of AVGCharacter
@export var variables: Array = []  # Array of AVGVariable
@export var events: Array = []  # Array of AVGEvent
@export var shared_nodes: Array = []  # Array of AVGNode (公共节点模板)

## ---- 标题界面配置 ----
@export var title_config: Resource = null  # AVGTitleConfig

## ---- 游戏内 UI 配置 ----
@export var game_ui_config: Resource = null  # AVGGameUIConfig

## ---- 子界面配置 ----
## key: screen_type 字符串 ("menu", "save", "load", "history", "settings")
## value: AVGScreenConfig
@export var screen_configs: Dictionary = {}


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "game_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "resolution", "type": TYPE_VECTOR2I, "editable": true, "category": "基本"},
	]


static func load_game_data() -> Resource:
	if not ResourceLoader.exists(DATA_PATH):
		return null
	return ResourceLoader.load(DATA_PATH)


static func duplicate_game_data() -> Resource:
	var data := load_game_data()
	return data.duplicate(true) if data != null else AVGGameData.new()
