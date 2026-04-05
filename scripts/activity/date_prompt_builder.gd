## Prompt builder for date (约会) activity scenes.
class_name DatePromptBuilder extends AVGScenePromptBuilder

const PROMPT_KEY: String = "date_scene_normal"


func build_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	var location: Dictionary = session.get("location", {})
	var detail_prompt: String = str(session.get("detail_prompt", location.get("detail_prompt", ""))).strip_edges()
	var day: int = int(session.get("start_day", 1))
	var phase: String = str(session.get("phase_after_action", "")).strip_edges()
	var loc_id: String = str(location.get("location_id", session.get("entry_id", "")))

	var story_guidance := _build_story_guidance_block(session)
	var activity_block: String
	if not story_guidance.is_empty():
		# 有导演指导 → 以叙事指导为主，不注入活动细节避免方向冲突
		activity_block = _build_guided_activity_block(location, story_guidance)
	else:
		# 无导演指导 → 使用事件的 activity_hint 驱动场景
		activity_block = _build_event_activity_block(location)

	var ctx: Dictionary = {
		"date_scene_location": _build_location_block(location, detail_prompt),
		"date_scene_activity": activity_block,
		"date_scene_time": _build_time_block(day, phase),
		"date_scene_state": _build_state_block(),
		"date_scene_history": _build_history_block(loc_id),
		"recent_chat_history": _build_chat_history_block(),
	}

	var result := _resolve_with_pipeline(PROMPT_KEY, ctx, session)
	if not result.is_empty():
		return result

	return "\n".join([
		"你要生成一段普通约会的 AVG 短场景。",
		"这不是重要剧情，不是表白，不是争吵爆发，也不是任务汇报。",
		"重点是两个人在一个具体地点里，自然相处了一段时间。",
		"",
		"## 时间",
		_build_time_block(day, phase),
		"",
		"## 地点",
		_build_location_block(location, detail_prompt),
		"",
		"## 本次约会活动与气氛",
		_build_event_activity_block(location),
		"",
		"## 当前人物状态",
		_build_state_block(),
		"",
		"## 历史约会参考（避免重复）",
		_build_history_block(loc_id),
		"",
		"## 场景结构要求",
		"- 必须包含四段：到达地点、一起活动、一次自然聊天选择、回家收尾。",
		"- 普通约会只允许一次选择，选项数为 2 到 3 个。",
		"- 选项必须像自然接话，不要像策略按钮或数值提示。",
		"- 整体氛围应当像 Galgame 里的日常约会，不要写成系统事件。",
		"- 可以轻微提到项目或最近状态，但不要变成议题讨论会。",
		"- 不要表白，不要定义关系，不要突然争吵升级，不要扯到过重的家庭或未来命题。",
		"- 场景必须在回家收尾处结束，不要把回家后的 LinkChat、朋友圈或系统结算写进 AVG 场景。",
		"",
		"## 多样性要求",
		"- 这次约会必须在具体行为、经过的店铺或角落、聊天话题上与之前的约会形成差异。",
		"- 不要总是走进同一类型的店，不要总是以相同的方式开始和结束。",
	]).strip_edges()


# ---------------------------------------------------------------------------
# Date-specific block builders
# ---------------------------------------------------------------------------
func _build_location_block(location: Dictionary, detail_prompt: String) -> String:
	var location_title: String = str(location.get("location_title", "")).strip_edges()
	var title: String = str(location.get("title", "未命名地点")).strip_edges()
	var subtitle: String = str(location.get("subtitle", "")).strip_edges()
	var description: String = str(location.get("description", "")).strip_edges()
	var display_name: String = location_title if not location_title.is_empty() else title
	var lines: Array[String] = ["约会地点：%s" % display_name]
	if not subtitle.is_empty():
		lines.append("地点氛围：%s" % subtitle)
	if not description.is_empty():
		lines.append("地点简介：%s" % description)
	if not detail_prompt.is_empty():
		lines.append("地点设定：%s" % detail_prompt)
	return "\n".join(lines)


func _build_date_activity_block(location: Dictionary, event_seed: String = "", activity_variant: String = "") -> String:
	var activity_text: String = ""
	if not activity_variant.is_empty():
		activity_text = activity_variant
	else:
		activity_text = str(location.get("base_activity", "")).strip_edges()
	if activity_text.is_empty():
		activity_text = "这次约会的自然活动应当贴合地点，不要硬塞节目。"

	var lines: Array[String] = [activity_text]
	var seed_text: String = event_seed.strip_edges()
	if not seed_text.is_empty():
		lines.append("")
		lines.append("本次约会的突发切入点（必须在场景中自然发生）：")
		lines.append("- " + seed_text)
		lines.append("- 这是一个客观发生的微小事件，请围绕它自然地展开互动，不要直接复述设定。")
	lines.append("选项必须像 Galgame 里的自然接话，不要写成策略按钮。")
	lines.append("让场景自己决定此刻最自然会发生的互动，不要套固定事件模板。")
	return "\n".join(lines)


## 事件驱动模式：使用事件的 activity_hint 构建活动块。
func _build_event_activity_block(event: Dictionary) -> String:
	var activity_hint: String = str(event.get("activity_hint", "")).strip_edges()
	var description: String = str(event.get("description", "")).strip_edges()

	var lines: Array[String] = []
	if not description.is_empty():
		lines.append("事件背景：%s" % description)
	if not activity_hint.is_empty():
		lines.append("活动方向：%s" % activity_hint)
	else:
		lines.append("这次约会的自然活动应当贴合事件本身，不要硬塞节目。")
	lines.append("选项必须像 Galgame 里的自然接话，不要写成策略按钮。")
	lines.append("让场景围绕事件自然展开互动，不要套固定事件模板。")
	return "\n".join(lines)


## 导演指导模式：以叙事指导为核心方向，地点活动仅提供环境氛围参考。
## 不注入 event_seed / activity_variant，避免与导演指导的叙事方向冲突。
func _build_guided_activity_block(location: Dictionary, guidance: String) -> String:
	var base_activity: String = str(location.get("base_activity", "")).strip_edges()
	var lines: Array[String] = [guidance]
	if not base_activity.is_empty():
		lines.append("")
		lines.append("[地点氛围参考（仅供补充环境细节，不要替代上述导演指导方向）]")
		lines.append(base_activity)
	return "\n".join(lines)


func _build_history_block(location_id: String) -> String:
	var date_manager: Node = _get_autoload("DateManager")
	if date_manager == null or not date_manager.has_method("get_recent_history_summaries"):
		return ""
	var summaries: Array = date_manager.get_recent_history_summaries(5)
	if summaries.is_empty():
		return ""
	var lines: Array[String] = [
		"以下是最近几次约会的摘要，请刻意避开已经出现过的场景模式、话题和桥段，让这次约会在体验上与之前不同：",
	]
	for s in summaries:
		lines.append("- %s" % str(s))
	if not location_id.is_empty() and date_manager.has_method("get_recent_history_for_location"):
		var loc_history: Array = date_manager.get_recent_history_for_location(location_id, 3)
		if not loc_history.is_empty():
			lines.append("")
			lines.append("尤其注意：你们之前来过这个地方，以下是同一地点的近期约会，请务必避免重复：")
			for h in loc_history:
				var outline := str(h.get("outline", h.get("outcome_summary", ""))).strip_edges()
				if not outline.is_empty():
					lines.append("- %s" % outline)
	return "\n".join(lines)
