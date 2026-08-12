class_name AVGScenePromptBuilder extends RefCounted
## 将调用方提供的中性场景需求整理为动态 AVG 生成提示。

static func create_for_session(_session: Dictionary) -> AVGScenePromptBuilder:
	return AVGScenePromptBuilder.new()


func build_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""
	var sections: PackedStringArray = []
	for block: String in [
		build_type_prompt_from_session(session),
		build_setting_prompt_from_session(session),
		build_runtime_prompt_from_session(session),
	]:
		if not block.is_empty():
			sections.append(block)
	return "\n\n".join(sections).strip_edges()


func build_type_prompt_from_session(session: Dictionary) -> String:
	var sections: PackedStringArray = []
	_append_optional_section(sections, "演出约束", session.get("constraints", ""))
	_append_optional_section(sections, "导演指导", session.get("story_guidance_prompt", ""))
	return "\n\n".join(sections).strip_edges()


func build_setting_prompt_from_session(session: Dictionary) -> String:
	var sections: PackedStringArray = []
	_append_optional_section(sections, "角色设定", session.get("setting_context", ""))
	return "\n\n".join(sections).strip_edges()


func build_runtime_prompt_from_session(session: Dictionary) -> String:
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
	_append_optional_section(sections, "补充上下文", session.get("context", ""))

	var title := str(session.get("title", "")).strip_edges()
	if not title.is_empty():
		sections.append("## 场景标题\n%s" % title)
	sections.append("## 场景需求\n%s" % scene_brief)

	_append_optional_section(sections, "本次运行上下文", session.get("runtime_context", ""))
	return "\n\n".join(sections).strip_edges()


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
