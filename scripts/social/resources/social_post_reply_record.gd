class_name SocialPostReplyRecord extends Resource
## 帖子下的一条真实回复。互动栏的回复数是独立指标，不由这里的记录数量推导。

@export var reply_id: String = ""
@export var author_account_id: String = ""
@export var author_display_name: String = ""
@export var author_handle: String = ""
@export var parent_reply_id: String = ""
@export_multiline var text_content: String = ""
@export var published_at: int = 0


func to_dict() -> Dictionary:
	return {
		"reply_id": reply_id,
		"author_account_id": author_account_id,
		"author_display_name": author_display_name,
		"author_handle": author_handle,
		"parent_reply_id": parent_reply_id,
		"text_content": text_content,
		"published_at": published_at,
	}


static func from_dict(data: Dictionary) -> SocialPostReplyRecord:
	var record := SocialPostReplyRecord.new()
	record.reply_id = str(data.get("reply_id", ""))
	record.author_account_id = str(data.get("author_account_id", ""))
	record.author_display_name = str(data.get("author_display_name", ""))
	record.author_handle = str(data.get("author_handle", ""))
	record.parent_reply_id = str(data.get("parent_reply_id", ""))
	record.text_content = str(data.get("text_content", ""))
	record.published_at = int(data.get("published_at", 0))
	return record
