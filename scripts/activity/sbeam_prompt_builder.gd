## Prompt builder for Sbeam co-op gaming activity scenes.
class_name SbeamPromptBuilder extends AVGScenePromptBuilder

const PROMPT_KEY: String = "sbeam_scene_normal"


func build_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	var game: Dictionary = session.get("game", {})
	var day: int = int(session.get("start_day", 1))
	var phase: String = str(session.get("phase_after_action", "")).strip_edges()
	var detail_prompt: String = str(session.get("detail_prompt", "")).strip_edges()

	var ctx: Dictionary = {
		"sbeam_game_block": _build_sbeam_game_with_guidance(game, day, phase, detail_prompt, session),
		"sbeam_state_block": _build_state_block(),
		"recent_chat_history": _build_chat_history_block(),
	}

	var result := _resolve_with_pipeline(PROMPT_KEY, ctx, session)
	if not result.is_empty():
		return result

	return "\n".join([
		"你要生成一段一起玩 sbeam 游戏的普通活动场景要求。",
		"这不是项目讨论，不是作品评测，也不是高潮剧情。",
		"重点是两个人在当前时段里，共同体验了一款虚构游戏，并因此产生了自然互动。",
		"",
		"## 地点",
		"两人合住的公寓内。背景和服装必须使用室内/居家相关的素材。",
		"- 背景从资产清单中选择室内类别（如有 apartment、room 类 alias 优先使用）。",
		"- 角色服装使用居家/睡衣类服装（如资产清单中有 loungewear、pajama 等 alias 优先使用）。",
		"- 绝对不要使用公园、街道等外景背景。",
		"",
		"## 这次选择的游戏",
		_build_sbeam_game_block(game, day, phase, detail_prompt),
		"",
		"## 当前人物状态",
		_build_state_block(),
		"",
		"## 场景结构要求",
		"- 必须包含四段：开始前、玩到中途、一次自然接话选择、结束后的余韵。",
		"- 这是一段共同体验场景，不是完整游玩记录，不要模拟整部游戏流程。",
		"- 只允许一次选择，选项数为 2 到 3 个。",
		"- 选项必须是玩家对她当下反应的自然接话，不要写成策略按钮。",
		"- 游戏内容只写到足够触发情绪即可，不要详细解释玩法系统。",
		"- 重点是两个人之间的气氛变化，不是那款游戏本身有多复杂。",
		"- 不要把话题扯回 GameJam、工单、AVG 开发讨论。",
		"- 结尾必须收在玩完后的余韵，不要再追加手机消息、朋友圈或系统结算。",
	]).strip_edges()


# ---------------------------------------------------------------------------
# Sbeam-specific block builder
# ---------------------------------------------------------------------------
func _build_sbeam_game_block(game: Dictionary, day: int, phase: String, detail_prompt: String, event_prompt: String = "") -> String:
	var title: String = str(game.get("title", "未命名游戏")).strip_edges()
	var genre: String = str(game.get("genre", "")).strip_edges()
	var pitch: String = str(game.get("pitch", "")).strip_edges()
	var hook_moment: String = str(game.get("hook_moment", "")).strip_edges()
	var review_summary: String = str(game.get("review_summary", "")).strip_edges()
	var player_hint: String = str(game.get("player_count_hint", "")).strip_edges()
	var lines: Array[String] = [
		"当前时间：比赛第 %d 天，时段为 %s。" % [day, phase if not phase.is_empty() else "UNKNOWN"],
		"这次要一起玩的是《%s》。" % title,
	]
	if not genre.is_empty():
		lines.append("类型：%s" % genre)
	if not pitch.is_empty():
		lines.append("作品印象：%s" % pitch)
	if not player_hint.is_empty():
		lines.append("游玩方式：%s" % player_hint)
	if not hook_moment.is_empty():
		lines.append("最容易触发情绪的片段：%s" % hook_moment)
	if not review_summary.is_empty():
		lines.append("玩家普遍观感：%s" % review_summary)
	if not detail_prompt.is_empty():
		lines.append("现实环境：%s" % detail_prompt)
	if not event_prompt.is_empty():
		lines.append("本次气氛参考：%s" % event_prompt)
	lines.append("重点不是完整试玩记录，而是一起玩的反应、停顿、接话和余韵。")
	lines.append("让场景自己决定今晚最能带出两人反应的片段，不要依赖预设桥段。")
	return "\n".join(lines)


## 导演指导模式：游戏信息作为事实背景保留，导演指导驱动叙事方向。
func _build_sbeam_game_with_guidance(game: Dictionary, day: int, phase: String, detail_prompt: String, session: Dictionary) -> String:
	var game_block := _build_sbeam_game_block(game, day, phase, detail_prompt)
	var guidance := _build_story_guidance_block(session)
	if guidance.is_empty():
		return game_block
	return game_block + "\n\n[导演指导（以此为叙事核心方向）]\n" + guidance
