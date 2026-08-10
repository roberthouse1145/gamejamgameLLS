class_name PostContent extends Resource
## 跨平台帖子的纯内容元素，不保存作者、账号、平台、发布时间或互动状态。

@export var content_id: String = ""
@export_multiline var text_content: String = ""
@export var texture_content: Texture2D = null
@export var linked_url: String = ""


func is_empty() -> bool:
	return text_content.strip_edges().is_empty() \
		and texture_content == null \
		and linked_url.strip_edges().is_empty()
