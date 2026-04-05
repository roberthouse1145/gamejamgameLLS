class_name ChatPromptBuilder extends RefCounted
const PromptPipelineScript = preload("res://scripts/prompt/prompt_pipeline.gd")
## 聊天Prompt构建器
## 利用 PromptManager 的 {{key}} 模板机制构建 prompt
## 支持私聊和群聊（多 NPC）


## 构建完整的聊天请求数据
## [param channel] 当前的聊天频道资源
## [param npcs] 频道内所有实体 NPC 列表（主要指女主等，群聊天可能为空）
## [param topic] 当前 Topic（可为 null）
static func build(
	channel: ChatChannel,
	npcs: Array,
	chat_history: Array[Dictionary],
	player_messages: Array[String],
	relevant_memories: Array = [],
	topic: ChatTopic = null,
) -> Dictionary:
	# 构建上下文变量，通过 resolve_with_vars 传入（不污染全局状态）
	# 注：player_name / player_web_name / player_team / game_time
	# 已通过 PromptBindings 的 Provider 全局注册，无需再传。
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("PromptManager") == null:
		push_error("ChatPromptBuilder: PromptManager not found")
		return {"messages": []}

	var ctx: Dictionary = {
		"characters": _build_characters(channel, npcs),
		"player_identity": _build_player_identity(),
		"chat_history": _build_history(chat_history),
		"memories": _build_memories(relevant_memories),
		"lore_facts": "",
		"lore_constraints": "",
		"topic": _build_topic(topic),
		"topic_complete_hint":
			"5. 达成对话目标后，单独输出一行 [TOPIC_COMPLETE] 作为完成标记。" if topic else "",
		"speaker_ids": _build_speaker_ids(npcs),
	}

	# 两遍 resolve：先展开完整 prompt → 用完整文本匹配 lore → 注入 lore 后二次 resolve
	var pipeline_result := PromptPipelineScript.build_prompt(
		"linkchat_system",
		ctx,
		{
			"lore_mode": "chat",
			"lore_args": {
				"channel": channel,
				"npcs": npcs,
				"chat_history": chat_history,
				"player_messages": player_messages,
				"topic": topic,
			},
		}
	)
	var system_prompt: String = str(pipeline_result.get("prompt", ""))
	var user_message := _build_user_message(player_messages)

	return {
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_message},
		]
	}


static func _build_characters(channel: ChatChannel, npcs: Array) -> String:
	var parts: Array[String] = []

	if channel and not channel.channel_prompt.is_empty():
		parts.append("### 频道（群组）环境设定\n%s" % _resolve_player_placeholders(channel.channel_prompt))

	if npcs.is_empty() and parts.is_empty():
		return "（当前频道无 NPC 及特殊环境设定）"

	for npc in npcs:
		var prompt_text: String = npc.prompt.strip_edges()
		if prompt_text.is_empty():
			prompt_text = "（该角色暂无设定）"
			
		parts.append("### %s\n%s" % [npc.display_name, prompt_text])

	return "\n\n".join(parts)



## 将 prompt 模板中的 {player_name} 替换为玩家实际名称（优先真实姓名）
static func _resolve_player_placeholders(text: String) -> String:
	if "{player_name}" not in text:
		return text
	var story_director: Node = Engine.get_main_loop().root.get_node_or_null("StoryDirector")
	var real_name: String = ""
	var nickname: String = ""
	if story_director != null and story_director.has_method("get_variable"):
		real_name = str(story_director.get_variable("player_real_name", "")).strip_edges()
		nickname = str(story_director.get_variable("player_name", "")).strip_edges()
	var name: String = real_name if not real_name.is_empty() else nickname
	if name.is_empty():
		name = "玩家"
	return text.replace("{player_name}", name)


static func _build_player_identity() -> String:
	var player_real_name: String = ""
	var player_nickname: String = ""
	var university_name: String = "蓝鲸大学"
	var college_name: String = ""

	var story_director: Node = Engine.get_main_loop().root.get_node_or_null("StoryDirector")
	if story_director != null and story_director.has_method("get_variable"):
		player_real_name = str(story_director.get_variable("player_real_name", "")).strip_edges()
		player_nickname = str(story_director.get_variable("player_name", "")).strip_edges()
		university_name = str(story_director.get_variable("player_university", university_name)).strip_edges()
		college_name = str(story_director.get_variable("player_college", "")).strip_edges()

	if university_name.is_empty():
		university_name = "蓝鲸大学"

	# 优先使用真实姓名；报名前只有网名时用网名
	var display_name: String = player_real_name if not player_real_name.is_empty() else player_nickname
	if display_name.is_empty():
		display_name = "（未知）"

	var identity_line := "玩家真实姓名：%s" % display_name
	if not player_nickname.is_empty() and player_nickname != display_name:
		identity_line += "（网名：%s）" % player_nickname
	if not college_name.is_empty():
		identity_line += "（%s%s学生）" % [university_name, college_name]
	else:
		identity_line += "（%s学生）" % university_name

	return "%s。与女友林夏一起参加 ARCADE GRAND JAM 2027。\n【绝对禁止】用其他名字称呼玩家，也禁止自行编造玩家的言行。" % identity_line


static func _build_history(chat_history: Array[Dictionary], max_count: int = 20) -> String:
	if chat_history.is_empty():
		return "（这是对话的开始）"

	var lines: Array[String] = []
	for msg in chat_history.slice(-max_count):
		var sender: String = msg.get("sender_name", "未知")
		var time_str: String = msg.get("time", "")
		var content: String = msg.get("content", "").strip_edges()
		if msg.has("card") and msg["card"] is Dictionary:
			var card_summary := _summarize_card(msg["card"])
			if not card_summary.is_empty():
				if content.is_empty():
					content = card_summary
				else:
					content += " " + card_summary
		if content.is_empty():
			continue
		lines.append("[%s] %s: %s" % [time_str, sender, content])
	return "\n".join(lines)


static func _summarize_card(card: Dictionary) -> String:
	var card_type := str(card.get("type", "")).strip_edges().to_lower()
	var title := str(card.get("title", "")).strip_edges()
	var hint := str(card.get("hint", "")).strip_edges()
	match card_type:
		"image":
			return "[分享了图片卡片：%s]" % (
				hint if not hint.is_empty() else str(card.get("image_id", "图片"))
			)
		"location":
			return "[分享了地点卡片：%s %s]" % [
				title if not title.is_empty() else "未命名地点",
				str(card.get("footer", "")).strip_edges()
			]
		"mock_image":
			return "[分享了伪图片卡片：%s]" % (title if not title.is_empty() else "未命名卡片")
		"web_page":
			return "[分享了网页卡片：%s %s]" % [
				title if not title.is_empty() else "未命名网页",
				str(card.get("url", "")).strip_edges()
			]
		"game":
			var footer := str(card.get("footer", "")).strip_edges()
			var subtitle := str(card.get("subtitle", "")).strip_edges()
			var parts: Array[String] = []
			if not title.is_empty():
				parts.append(title)
			if not subtitle.is_empty():
				parts.append(subtitle)
			if not footer.is_empty():
				parts.append(footer)
			return "[分享了游戏卡片：%s]" % "，".join(parts) if not parts.is_empty() else "[分享了游戏卡片]"
		"product":
			var price := str(card.get("price", "")).strip_edges()
			var badge := str(card.get("badge", "")).strip_edges()
			var parts: Array[String] = []
			if not title.is_empty():
				parts.append(title)
			if not badge.is_empty():
				parts.append(badge)
			if not price.is_empty():
				parts.append(price)
			return "[分享了商品卡片：%s]" % "，".join(parts)
		_:
			return "[分享了一张卡片]"


static func _build_memories(relevant_memories: Array) -> String:
	if relevant_memories.is_empty():
		return "（暂无相关记忆）"

	var lines: Array[String] = []
	for memory in relevant_memories:
		if memory is MemoryEntry:
			lines.append("- %s" % memory.content)
		elif memory is Dictionary:
			lines.append("- %s" % memory.get("content", ""))
	return "\n".join(lines)


static func _build_topic(topic: ChatTopic) -> String:
	if topic == null:
		return "当前无特定话题，自由聊天即可。"

	var parts: Array[String] = [_resolve_player_placeholders(topic.system_prompt)]
	if not topic.goal_description.is_empty():
		parts.append("\n对话目标：%s" % topic.goal_description)
	return "\n".join(parts)


static func _build_user_message(player_messages: Array[String]) -> String:
	if player_messages.is_empty():
		return "这是 NPC 主动发起的一轮开场回复。玩家此刻还没有发送新消息，请直接按照当前 topic 要求自然开口。"

	if player_messages.size() == 1:
		return player_messages[0]

	var lines: Array[String] = ["玩家发送了以下消息："]
	for msg in player_messages:
		lines.append("- %s" % msg)
	return "\n".join(lines)


static func _build_speaker_ids(npcs: Array) -> String:
	if npcs.is_empty():
		return "（无）"
	var ids: Array[String] = []
	for npc in npcs:
		if not npc is NPCCharacter:
			continue
		ids.append("%s（%s）" % [npc.character_id, npc.display_name])
	return ", ".join(ids)
