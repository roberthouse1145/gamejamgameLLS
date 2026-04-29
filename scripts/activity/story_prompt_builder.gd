class_name StoryPromptBuilder extends AVGScenePromptBuilder


func build_prompt_from_session(session: Dictionary) -> String:
	var scene_prompt := str(session.get("story_scene_prompt", "")).strip_edges()
	if scene_prompt.is_empty():
		return ""

	var title := str(session.get("story_scene_title", session.get("scene_window_title", "剧情事件"))).strip_edges()
	var day := int(session.get("start_day", 1))
	var phase := str(session.get("phase_after_action", session.get("start_phase", "MORNING"))).strip_edges()
	var parts: Array[String] = [
		"你正在编写一段由 StoryDirector 直接触发的 AVG 剧情片段。",
		"这不是普通活动流程，不要强行套用约会、兼职或日常活动模板。",
	]

	if not title.is_empty():
		parts.append("场景标题：%s" % title)

	var time_block := _build_time_block(day, phase)
	if not time_block.is_empty():
		parts.append(time_block)

	var state_block := _build_state_block()
	if not state_block.is_empty():
		parts.append(state_block)

	var preamble := str(session.get("story_scene_preamble", "")).strip_edges()
	if not preamble.is_empty():
		parts.append("[前置上下文]\n%s" % preamble)

	var history_block := _build_story_chat_history_block(session)
	if not history_block.is_empty():
		parts.append("[前情参考（仅用于承接，不要逐句照抄）]\n这些内容是本段剧情开始前刚发生过的聊天或对话，仅用于帮助你理解人物情绪、关系状态、冲突来源和事实边界。\n除非本段事件明确要求回放、复述或紧接上一句原话继续，否则不要把下面的内容逐句原样搬进 AVG 正文。\n%s" % history_block)

	var event_block := "[本段事件]\n%s" % scene_prompt
	event_block = _merge_story_guidance(event_block, session)
	parts.append(event_block)

	var rules: Array[String] = [
		"只写这一次剧情片段本身，不要擅自补写长期后续。",
		"开场要尽快进入事件，不要用太长铺垫。",
		"优先用画面、动作和对话推进，而不是旁白解释。",
		"如果上方给了前情聊天记录，把它当作前因背景来承接，不要先逐句复读一遍聊天记录再进入剧情。",
		"除非导演指令明确要求复述原话，否则不要把聊天记录里的句子机械复制成场景开场对白。",
	]
	if bool(session.get("allow_branching", true)):
		rules.append("如果情境自然需要，可以包含少量选择分支，但整体保持收束。")
	else:
		rules.append("不要写额外选择分支，保持单线推进。")
	parts.append("[写作要求]\n- %s" % "\n- ".join(rules))

	return "\n\n".join(parts).strip_edges()


func _build_story_chat_history_block(session: Dictionary) -> String:
	var raw_conversation: Variant = session.get("story_trigger_conversation", [])
	if raw_conversation is Array and not (raw_conversation as Array).is_empty():
		var lines: Array[String] = []
		for entry in raw_conversation:
			if not (entry is Dictionary):
				continue
			var message: Dictionary = entry as Dictionary
			var speaker_name := str(message.get("speaker_name", message.get("speaker_id", "对方"))).strip_edges()
			var content := str(message.get("content", "")).strip_edges()
			if content.is_empty():
				continue
			if speaker_name.is_empty():
				speaker_name = "对方"
			lines.append("%s: %s" % [speaker_name, content])
		if not lines.is_empty():
			return "\n".join(lines)

	if bool(session.get("include_chat_history", false)):
		return _build_chat_history_block().strip_edges()
	return ""
