class_name StreamApproach extends Resource
## 一次开播准备期间临时生成的直播构思。可见说明与导演指令分别存放。

@export var approach_id: StringName = &""
@export var approach_type: StringName = &""
@export var display_name: String = ""
@export_multiline var display_description: String = ""
@export_multiline var director_prompt: String = ""


func is_valid(allowed_types: Array[StringName] = []) -> bool:
	if String(approach_id).strip_edges().is_empty():
		return false
	if String(approach_type).strip_edges().is_empty():
		return false
	if not allowed_types.is_empty() and approach_type not in allowed_types:
		return false
	return (
		not display_name.strip_edges().is_empty()
		and not display_description.strip_edges().is_empty()
		and not director_prompt.strip_edges().is_empty()
	)


func to_dict() -> Dictionary:
	return {
		"approach_id": String(approach_id),
		"approach_type": String(approach_type),
		"display_name": display_name,
		"display_description": display_description,
		"director_prompt": director_prompt,
	}


static func from_dict(data: Dictionary) -> StreamApproach:
	var approach := StreamApproach.new()
	approach.approach_id = StringName(str(data.get("approach_id", "")).strip_edges())
	approach.approach_type = StringName(str(data.get("approach_type", "")).strip_edges())
	approach.display_name = str(data.get("display_name", "")).strip_edges()
	approach.display_description = str(data.get("display_description", "")).strip_edges()
	approach.director_prompt = str(data.get("director_prompt", "")).strip_edges()
	return approach
