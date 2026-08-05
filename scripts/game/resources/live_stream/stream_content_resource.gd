class_name StreamContentResource extends Resource
## 直播业务静态内容的公共定义。运行时状态不得写回 Resource。

@export var content_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var tags: Array[StringName] = []
@export_multiline var prompt_fragment: String = ""


func is_valid_base() -> bool:
	return (
		not String(content_id).strip_edges().is_empty()
		and not display_name.strip_edges().is_empty()
		and icon != null
	)
