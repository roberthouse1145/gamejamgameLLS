class_name AVGCanvasLayerNode extends AVGNode
## AVG 画布层节点
## 类似 Godot 的 CanvasLayer，子节点不受 Camera2D 影响。
## 用于 HUD、计分板、血条等需要固定在屏幕上的 UI 元素。
## 本身是逻辑容器，没有位置/尺寸概念，不可拖拽。

## 画布层级（数值越大越靠前，默认 100）
@export var layer: int = 100


## 获取节点类型名称
func get_node_type() -> String:
	return "canvas_layer"


## 获取节点类型显示名称
func get_node_type_display() -> String:
	return "画布层"


## 获取可编辑属性列表（去掉 position/size 相关属性）
func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "node_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "node_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "note", "type": TYPE_STRING, "editable": true, "category": "基本", "multiline": true},
		{"name": "visible", "type": TYPE_BOOL, "editable": true, "category": "基本"},
		{"name": "layer", "type": TYPE_INT, "editable": true, "category": "画布层", "hint": "层级 (数值越大越靠前)"},
	]
