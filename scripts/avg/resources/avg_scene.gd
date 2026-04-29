class_name AVGScene extends Resource
## AVG Scene Resource
## Represents a complete AVG scene with background, BGM, nodes, and command lists.
## Uses gap-filling ID system: scene_id = "scene_NNN", fills lowest available slot.

## 补位 ID（如 scene_001），扫描空位分配
@export var scene_id: String = ""
@export var scene_name: String = "New Scene"
@export var folder: String = ""  # 文件夹分组
@export var scene_note: String = ""  # 给编辑器/Agent 用的场景摘要备注，不参与运行时
@export var nodes: Array = []  # Array of AVGNode
## 已废弃：历史兼容字段。新的变量系统仅支持项目级变量。
@export var local_variables: Array = []  # Legacy compatibility only; ignored at runtime.


static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "scene_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "scene_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "folder", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "scene_note", "type": TYPE_STRING, "editable": true, "category": "基本", "multiline": true},
	]


## 从编号生成 ID
static func make_id(num: int) -> String:
	return "scene_%03d" % num


## 扫描已有场景，找到最小可用编号
static func next_available_id(scenes: Array) -> String:
	var used: Array[int] = []
	for s in scenes:
		if s == null or s.scene_id.is_empty():
			continue
		if s.scene_id.begins_with("scene_"):
			var num_str: String = s.scene_id.substr(6)
			if num_str.is_valid_int():
				used.append(num_str.to_int())
	used.sort()
	var next_num: int = 1
	for n in used:
		if n == next_num:
			next_num += 1
		elif n > next_num:
			break
	return make_id(next_num)
