class_name SocialPostRecord extends Resource
## 一次公开发布记录：引用纯内容，并保存账号、时间和平台互动状态。

@export var post_id: String = ""
@export var author_account_id: String = ""
@export var source_session_id: String = ""
@export var content: PostContent = null
@export var published_at: int = 0
@export var liked: bool = false
@export var likes: int = 0
@export var reposts: int = 0
@export var replies: int = 0
@export var reply_items: Array[SocialPostReplyRecord] = []


func to_dict() -> Dictionary:
	var texture_path: String = ""
	if content != null and content.texture_content != null:
		texture_path = content.texture_content.resource_path
	var serialized_reply_items: Array[Dictionary] = []
	for reply: SocialPostReplyRecord in reply_items:
		if reply != null:
			serialized_reply_items.append(reply.to_dict())
	return {
		"post_id": post_id,
		"author_account_id": author_account_id,
		"source_session_id": source_session_id,
		"content_id": content.content_id if content != null else "",
		"text_content": content.text_content if content != null else "",
		"texture_path": texture_path,
		"linked_url": content.linked_url if content != null else "",
		"published_at": published_at,
		"liked": liked,
		"likes": maxi(likes, 0),
		"reposts": maxi(reposts, 0),
		"replies": maxi(replies, 0),
		"reply_items": serialized_reply_items,
	}


static func from_dict(data: Dictionary) -> SocialPostRecord:
	var record := SocialPostRecord.new()
	record.post_id = str(data.get("post_id", ""))
	record.author_account_id = str(data.get("author_account_id", ""))
	record.source_session_id = str(data.get("source_session_id", ""))
	record.published_at = int(data.get("published_at", 0))
	record.liked = bool(data.get("liked", false))
	record.likes = maxi(int(data.get("likes", 0)), 0)
	record.reposts = maxi(int(data.get("reposts", 0)), 0)
	record.replies = maxi(int(data.get("replies", 0)), 0)
	var raw_reply_items: Variant = data.get("reply_items", [])
	if raw_reply_items is Array:
		for value: Variant in raw_reply_items:
			if value is Dictionary:
				record.reply_items.append(SocialPostReplyRecord.from_dict(value))
	var post_content := PostContent.new()
	post_content.content_id = str(data.get("content_id", ""))
	post_content.text_content = str(data.get("text_content", ""))
	post_content.linked_url = str(data.get("linked_url", ""))
	var texture_path: String = str(data.get("texture_path", "")).strip_edges()
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		post_content.texture_content = ResourceLoader.load(texture_path) as Texture2D
	record.content = post_content
	return record
