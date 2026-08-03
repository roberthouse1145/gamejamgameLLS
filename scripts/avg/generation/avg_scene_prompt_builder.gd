class_name AVGScenePromptBuilder extends RefCounted
## 将调用方提供的中性场景需求整理为动态 AVG 生成提示。

const AVGKnowledgeToolsClass = preload("res://scripts/avg/generation/avg_knowledge_tools.gd")


static func create_for_session(_session: Dictionary) -> AVGScenePromptBuilder:
	return AVGScenePromptBuilder.new()


func build_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	var scene_brief := _first_text(session, [
		"scene_prompt",
		"story_scene_prompt",
		"scene_brief",
		"prompt",
	])
	if scene_brief.is_empty():
		return ""

	var sections: PackedStringArray = []
	var title := str(session.get("title", "")).strip_edges()
	if not title.is_empty():
		sections.append("## 场景标题\n%s" % title)
	sections.append("## 场景需求\n%s" % scene_brief)

	_append_optional_section(sections, "补充上下文", session.get("context", ""))
	_append_optional_section(sections, "角色与世界设定", session.get("setting_context", ""))
	_append_optional_section(sections, "演出约束", session.get("constraints", ""))
	_append_optional_section(sections, "导演指导", session.get("story_guidance_prompt", ""))
	return "\n\n".join(sections).strip_edges()


static func build_avg_project_shared_context() -> String:
	var kb_index: String = AVGKnowledgeToolsClass.build_index_context().strip_edges()
	if kb_index.is_empty():
		return "当前没有预设剧情文档。只使用本次场景需求和调用方显式提供的设定。"
	return "%s\n\n如需读取某份文档全文，可调用 kb_read(doc_id=\"...\")。" % kb_index


static func _first_text(source: Dictionary, keys: Array[String]) -> String:
	for key in keys:
		var value := str(source.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


static func _append_optional_section(sections: PackedStringArray, title: String, raw_value: Variant) -> void:
	var value: String
	if raw_value is Dictionary or raw_value is Array:
		value = JSON.stringify(raw_value, "  ").strip_edges()
	else:
		value = str(raw_value).strip_edges()
	if not value.is_empty():
		sections.append("## %s\n%s" % [title, value])
