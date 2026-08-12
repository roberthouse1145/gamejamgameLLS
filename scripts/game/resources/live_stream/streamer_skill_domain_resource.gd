class_name StreamerSkillDomainResource extends Resource
## 中之人的一个直播能力领域，以及每级提供给演出 LLM 的能力描述。

@export var family: StringName = &"talk"
@export var display_name: String = ""
@export_multiline var level_prompts: PackedStringArray = PackedStringArray()


func get_level_prompt(level: int) -> String:
	if level_prompts.is_empty():
		return ""
	return level_prompts[clampi(level, 1, level_prompts.size()) - 1].strip_edges()


func is_valid() -> bool:
	if family not in GameState.SKILL_FAMILIES or display_name.strip_edges().is_empty():
		return false
	if level_prompts.size() != 5:
		return false
	for prompt_text: String in level_prompts:
		if prompt_text.strip_edges().is_empty():
			return false
	return true
