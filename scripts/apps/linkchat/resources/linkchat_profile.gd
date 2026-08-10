class_name LinkChatProfile extends Resource
## 角色拥有的 LinkChat 账号资料与可供剧情发布的预制动态内容。

@export var account_name: String = ""
@export var avatar: Texture2D = null
@export var initially_friend: bool = false
@export var moment_contents: Array[MomentContent] = []


func get_moment_content(moment_id: String) -> MomentContent:
	var normalized_id: String = moment_id.strip_edges()
	for content: MomentContent in moment_contents:
		if content != null and content.moment_id == normalized_id:
			return content
	return null
