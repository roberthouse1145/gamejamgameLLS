class_name MomentCommentRecord extends Resource
## 已发布动态下的一条评论。作者显示资料由 CharacterProfile 在展示时补充。

@export var comment_id: String = ""
@export var character_id: String = ""
@export_multiline var text_content: String = ""
@export var published_at: int = 0


func to_dict() -> Dictionary:
	return {
		"comment_id": comment_id,
		"character_id": character_id,
		"text_content": text_content,
		"published_at": published_at,
	}


static func from_dict(data: Dictionary) -> MomentCommentRecord:
	var record := MomentCommentRecord.new()
	record.comment_id = str(data.get("comment_id", ""))
	record.character_id = str(data.get("character_id", ""))
	record.text_content = str(data.get("text_content", ""))
	record.published_at = int(data.get("published_at", 0))
	return record
