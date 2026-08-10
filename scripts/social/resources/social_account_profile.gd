class_name SocialAccountProfile extends Resource
## 一个角色在公开社交平台上的具体身份。角色可同时拥有主播账号与个人账号。

const IDENTITY_STREAMER: String = "streamer"
const IDENTITY_PERSONAL: String = "personal"

@export var account_id: String = ""
@export var platform_id: String = "linkposta"
@export_enum("streamer", "personal") var identity_type: String = IDENTITY_PERSONAL
@export var streamer_persona: StreamPersonaResource = null
@export var display_name: String = ""
@export var handle: String = ""
@export var avatar: Texture2D = null
@export_multiline var bio: String = ""
@export var verified: bool = false
@export var post_contents: Array[PostContent] = []


func get_resolved_display_name() -> String:
	if identity_type == IDENTITY_STREAMER and streamer_persona != null:
		var channel_name: String = streamer_persona.channel_name.strip_edges()
		if not channel_name.is_empty():
			return channel_name
	return display_name


func get_resolved_avatar() -> Texture2D:
	if identity_type == IDENTITY_STREAMER and streamer_persona != null \
		and streamer_persona.channel_avatar != null:
		return streamer_persona.channel_avatar
	return avatar


func get_post_content(content_id: String) -> PostContent:
	var normalized_id: String = content_id.strip_edges()
	for content: PostContent in post_contents:
		if content != null and content.content_id == normalized_id:
			return content
	return null
