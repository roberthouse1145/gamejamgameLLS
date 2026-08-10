class_name MomentPostRecord extends Resource
## 已发布朋友圈记录：关联作者与纯内容，并保存发布时间和互动状态。

@export var post_id: String = ""
@export var character_id: String = ""
@export var content: MomentContent = null
@export var published_at: int = 0
@export var liked: bool = false
@export var likes: int = 0
@export var comments: Array[MomentCommentRecord] = []


func to_dict() -> Dictionary:
	var texture_path: String = ""
	if content != null and content.texture_content != null:
		texture_path = content.texture_content.resource_path
	var comment_data: Array[Dictionary] = []
	for comment: MomentCommentRecord in comments:
		if comment != null:
			comment_data.append(comment.to_dict())
	return {
		"post_id": post_id,
		"character_id": character_id,
		"moment_id": content.moment_id if content != null else "",
		"text_content": content.text_content if content != null else "",
		"texture_path": texture_path,
		"published_at": published_at,
		"liked": liked,
		"likes": maxi(likes, 0),
		"comments": comment_data,
	}


static func from_dict(data: Dictionary) -> MomentPostRecord:
	var record := MomentPostRecord.new()
	record.post_id = str(data.get("post_id", ""))
	record.character_id = str(data.get("character_id", ""))
	record.published_at = int(data.get("published_at", 0))
	record.liked = bool(data.get("liked", false))
	record.likes = maxi(int(data.get("likes", 0)), 0)
	var comment_values: Variant = data.get("comments", [])
	if comment_values is Array:
		for comment_value: Variant in comment_values:
			if comment_value is Dictionary:
				record.comments.append(MomentCommentRecord.from_dict(comment_value))
	var moment := MomentContent.new()
	moment.moment_id = str(data.get("moment_id", ""))
	moment.text_content = str(data.get("text_content", ""))
	var texture_path: String = str(data.get("texture_path", "")).strip_edges()
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		moment.texture_content = ResourceLoader.load(texture_path) as Texture2D
	record.content = moment
	return record
