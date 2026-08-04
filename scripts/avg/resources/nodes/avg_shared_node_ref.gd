class_name AVGSharedNodeRef extends AVGNode
## AVG Shared Node Reference
## 引用 SharedNode 模板的节点
## 在场景中作为单一节点显示，运行时解析为完整节点树

## 引用的 SharedNode ID（稳定标识，不随重命名变化）
@export var shared_node_id: String = ""

## 引用的 SharedNode 名称（仅用于显示，创建时记录）
@export var shared_node_name: String = ""

## 是否已唯一化（唯一化后不再引用模板）
@export var is_unique: bool = false

## 唯一化后的节点数据（深拷贝）
@export var unique_data: Resource = null


func get_node_type() -> String:
	return "shared_ref"


func get_node_type_display() -> String:
	if is_unique:
		return "公共节点 (已唯一化)"
	return "公共节点"


func get_avg_properties() -> Array[Dictionary]:
	var unique_props: Array[Dictionary] = [
		{"name": "shared_node_id", "type": TYPE_STRING, "editable": false, "category": "引用"},
		{"name": "shared_node_name", "type": TYPE_STRING, "editable": false, "category": "引用"},
		{"name": "is_unique", "type": TYPE_BOOL, "editable": false, "category": "引用"},
	]
	unique_props.append_array(super.get_avg_properties())
	return unique_props


## 获取解析后的节点（运行时使用）
func get_resolved_node(game_data: Resource) -> Resource:
	if is_unique and unique_data != null:
		return unique_data
	
	if game_data == null or shared_node_id.is_empty():
		return null
	
	# 通过 node_id 从项目的 shared_nodes 中查找
	for shared_node in game_data.shared_nodes:
		if shared_node.node_id == shared_node_id:
			return shared_node
	
	return null


## 唯一化：将引用转为独立副本
func make_unique(game_data: Resource) -> void:
	if is_unique:
		return
	
	var source_node: Resource = get_resolved_node(game_data)
	if source_node == null:
		return
	
	# 深拷贝节点树
	unique_data = _deep_copy_node(source_node)
	is_unique = true
	
	# 复制命令标签页
	command_tabs = source_node.command_tabs.duplicate(true)


## 深拷贝节点（使用补位制生成 unique_ ID）
func _deep_copy_node(node: Resource, used_nums: Array[int] = []) -> Resource:
	var new_node: Resource = node.duplicate(true)
	
	# 使用补位制生成 unique_ ID
	var next_num: int = AVGNode.next_available_num(used_nums)
	new_node.node_id = "unique_%03d" % next_num
	used_nums.append(next_num)
	
	var new_children: Array[AVGNode] = []
	for child in node.children:
		new_children.append(_deep_copy_node(child, used_nums))
	new_node.children = new_children
	
	return new_node
