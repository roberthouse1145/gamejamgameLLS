class_name MapPlace extends Resource
## 城市中的稳定地点资料。动态可选内容由 OutingActivity 表达。

@export var place_id: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export var district: String = ""
@export_multiline var summary: String = ""
@export var map_position: Vector2 = Vector2(0.5, 0.5)
@export var cover: Texture2D = null
@export_range(0.0, 5.0, 0.1) var rating: float = 0.0
@export var review_count: int = 0


func is_valid() -> bool:
	return not place_id.strip_edges().is_empty() and not display_name.strip_edges().is_empty()
