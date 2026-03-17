class_name AVGNode extends Resource
## AVG 超级节点
## 所有 AVG 可视节点的统一类型（角色节点、根节点、公共引用除外）。
## 通过属性组合决定行为：有 text → 显示文本，有 texture → 显示图片，
## 有 click 模式 command_tab → 可点击（即"按钮"），有 style_box → 背景样式。
## 使用归一化坐标系: (0,0)=左上角, (1,1)=右下角

# === 基本 ===
@export var node_id: String = ""
@export var node_name: String = "Node"
@export var norm_position: Vector2 = Vector2(0.0, 0.0)
@export var norm_size: Vector2 = Vector2(0.1, 0.1)
@export var position: Vector2 = Vector2.ZERO
@export var size: Vector2 = Vector2(100, 100)
@export var visible: bool = true
@export var note: String = ""
@export var children: Array[AVGNode] = []
@export var command_tabs: Array = []

# === 样式 ===
@export var style_box: Resource = null  # AVGStyleBox

# === 文本 ===
@export var text: String = ""
@export var font_size: int = 0  # 0=使用默认
@export var font_color: Color = Color.WHITE
@export var outline_size: int = 0
@export var outline_color: Color = Color.BLACK
@export var h_alignment: int = 0  # 0=左 1=中 2=右
@export var v_alignment: int = 0  # 0=上 1=中 2=下

# === 图片 ===
@export var texture: Texture2D = null
@export var modulate: Color = Color.WHITE
@export var stretch_mode: int = 0  # 0=保持比例 1=拉伸 2=平铺

# === 容器 ===
@export var clip_contents: bool = false


## 根据归一化坐标计算像素位置
func calc_pixel_position(resolution: Vector2) -> Vector2:
	return norm_position * resolution


## 根据归一化尺寸计算像素尺寸
func calc_pixel_size(resolution: Vector2) -> Vector2:
	return norm_size * resolution


## 从像素位置反算归一化坐标
func set_position_from_pixels(pixel_pos: Vector2, resolution: Vector2) -> void:
	if resolution.x > 0 and resolution.y > 0:
		norm_position = pixel_pos / resolution
		position = pixel_pos


## 从像素尺寸反算归一化尺寸
func set_size_from_pixels(pixel_size: Vector2, resolution: Vector2) -> void:
	if resolution.x > 0 and resolution.y > 0:
		norm_size = pixel_size / resolution
		size = pixel_size


## 同步像素值
func sync_pixel_values(resolution: Vector2) -> void:
	position = calc_pixel_position(resolution)
	size = calc_pixel_size(resolution)


## 获取节点类型名称
func get_node_type() -> String:
	return "node"


## 获取节点类型显示名称
func get_node_type_display() -> String:
	return "节点"


## 获取可编辑属性列表
func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "node_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "node_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
		{"name": "note", "type": TYPE_STRING, "editable": true, "category": "基本", "multiline": true},
		{"name": "norm_position", "type": TYPE_VECTOR2, "editable": true, "category": "变换", "hint": "归一化坐标 (0~1)"},
		{"name": "norm_size", "type": TYPE_VECTOR2, "editable": true, "category": "变换", "hint": "归一化尺寸 (0~1)"},
		{"name": "position", "type": TYPE_VECTOR2, "editable": false, "category": "变换", "hint": "像素位置(只读)"},
		{"name": "size", "type": TYPE_VECTOR2, "editable": false, "category": "变换", "hint": "像素尺寸(只读)"},
		{"name": "visible", "type": TYPE_BOOL, "editable": true, "category": "基本"},
		# 样式
		{"name": "style_box", "type": "sub_resource", "editable": true, "category": "样式",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
		# 文本
		{"name": "text", "type": TYPE_STRING, "editable": true, "category": "文本", "multiline": true},
		{"name": "font_size", "type": TYPE_INT, "editable": true, "category": "文本"},
		{"name": "font_color", "type": "color", "editable": true, "category": "文本"},
		{"name": "outline_size", "type": TYPE_INT, "editable": true, "category": "文本"},
		{"name": "outline_color", "type": "color", "editable": true, "category": "文本"},
		{"name": "h_alignment", "type": TYPE_INT, "editable": true, "category": "文本",
		 "enum": ["左对齐", "居中", "右对齐"]},
		{"name": "v_alignment", "type": TYPE_INT, "editable": true, "category": "文本",
		 "enum": ["顶部", "居中", "底部"]},
		# 图片
		{"name": "texture", "type": TYPE_OBJECT, "editable": true, "category": "图片", "class_hint": "Texture2D"},
		{"name": "modulate", "type": "color", "editable": true, "category": "图片"},
		{"name": "stretch_mode", "type": TYPE_INT, "editable": true, "category": "图片",
		 "enum": ["保持比例", "拉伸填充", "平铺"]},
		# 容器
		{"name": "clip_contents", "type": TYPE_BOOL, "editable": true, "category": "容器"},
	]


## 从编号生成节点 ID
static func make_node_id(num: int) -> String:
	return "node_%03d" % num


## 从编号生成公共节点 ID
static func make_shared_id(num: int) -> String:
	return "shared_%03d" % num


## 扫描节点树，收集所有已用的节点 ID 编号
static func collect_used_node_nums(nodes: Array, prefix: String = "node_") -> Array[int]:
	var used: Array[int] = []
	for node in nodes:
		if node == null:
			continue
		if node.node_id.begins_with(prefix):
			var num_str: String = node.node_id.substr(prefix.length())
			if num_str.is_valid_int():
				used.append(num_str.to_int())
		if "children" in node and node.children != null:
			used.append_array(collect_used_node_nums(node.children, prefix))
	return used


## 找到最小可用编号（补位制）
static func next_available_num(used: Array[int]) -> int:
	used.sort()
	var next_num: int = 1
	for n in used:
		if n == next_num:
			next_num += 1
		elif n > next_num:
			break
	return next_num
