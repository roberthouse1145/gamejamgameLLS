class_name AVGRootNode extends AVGNode
## AVG Root Node
## 场景根节点，作为AVG场景的基底
## size 固定为项目分辨率，可设置背景和BGM

@export var background: Texture2D
@export var bgm: AudioStream


func get_node_type() -> String:
	return "root"


func get_node_type_display() -> String:
	return "根节点"


func get_avg_properties() -> Array[Dictionary]:
	var props: Array[Dictionary] = super.get_avg_properties()
	# 根节点的坐标和尺寸不可编辑（固定为 0,0 - 1,1）
	for prop in props:
		if prop["name"] in ["norm_position", "norm_size", "position", "size"]:
			prop["editable"] = false
	# 添加根节点特有属性（放在前面）
	var unique_props: Array[Dictionary] = [
		{"name": "background", "type": TYPE_OBJECT, "editable": true, "category": "外观", "class_hint": "Texture2D"},
		{"name": "bgm", "type": TYPE_OBJECT, "editable": true, "category": "音频", "class_hint": "AudioStream"},
	]
	unique_props.append_array(props)
	return unique_props
