## Prompt builder for part-time job (兼职) activity scenes.
class_name PartTimePromptBuilder extends AVGScenePromptBuilder

const PROMPT_KEY: String = "part_time_scene_normal"


func build_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	var job: Dictionary = session.get("job", session.get("location", {}))
	var detail_prompt: String = str(session.get("detail_prompt", job.get("detail_prompt", ""))).strip_edges()
	var day: int = int(session.get("start_day", 1))
	var phase: String = str(session.get("phase_after_action", "")).strip_edges()

	var ctx: Dictionary = {
		"part_time_scene_job": _build_part_time_job_block(job, detail_prompt),
		"part_time_scene_activity": _build_part_time_activity_with_guidance(job, session),
		"part_time_scene_time": _build_time_block(day, phase),
		"part_time_scene_state": _build_state_block(),
		"recent_chat_history": _build_chat_history_block(),
	}

	var result := _resolve_with_pipeline(PROMPT_KEY, ctx, session)
	if not result.is_empty():
		return result

	return "\n".join([
		"你要生成一段情侣一起做兼职的 AVG 短场景。",
		"这不是正式职场剧，也不是工作总结。",
		"重点是两个人在一个具体兼职岗位里并肩干活，在忙碌、尴尬或琐碎里产生自然互动。",
		"",
		"## 时间",
		_build_time_block(day, phase),
		"",
		"## 岗位",
		_build_part_time_job_block(job, detail_prompt),
		"",
		"## 本次兼职活动与气氛",
		_build_part_time_activity_block(job, str(session.get("event_seed", ""))),
		"",
		"## 当前人物状态",
		_build_state_block(),
		"",
		"## 场景结构要求",
		"- 必须包含四段：到岗、一起干活、一次自然聊天选择、下班收尾。",
		"- 只允许一次选择，选项数为 2 到 3 个。",
		"- 选项必须像自然接话，不要写成策略按钮或数值提示。",
		"- 整体氛围要像 Galgame 里的共同打工小事件，不是现实向职场剧。",
		"- 可以有一点手忙脚乱、社死、疲惫、被照顾到的感觉，但不要升级成严重冲突。",
		"- 不要把这场兼职写成效率展示，更不要写成老板视角的工作报告。",
		"- 场景必须停在下班收尾处结束，不要把回家后的 LinkChat、朋友圈或系统结算写进 AVG 场景。",
	]).strip_edges()


# ---------------------------------------------------------------------------
# Part-time-specific block builders
# ---------------------------------------------------------------------------
func _build_part_time_job_block(job: Dictionary, detail_prompt: String) -> String:
	var job_title: String = str(job.get("job_title", "兼职")).strip_edges()
	var company_name: String = str(job.get("company_name", "")).strip_edges()
	var district: String = str(job.get("district", "")).strip_edges()
	var subtitle: String = str(job.get("subtitle", "")).strip_edges()
	var description: String = str(job.get("description", "")).strip_edges()
	var reward_money: int = _get_money_reward(job)

	var lines: Array[String] = ["兼职岗位：%s" % job_title]
	if not company_name.is_empty():
		lines.append("店铺 / 公司：%s" % company_name)
	if not district.is_empty():
		lines.append("地点：%s" % district)
	if reward_money > 0:
		lines.append("报酬：%d元 / 班" % reward_money)
	if not subtitle.is_empty():
		lines.append("岗位气质：%s" % subtitle)
	if not description.is_empty():
		lines.append("工作内容：%s" % description)
	if not detail_prompt.is_empty():
		lines.append("现场设定：%s" % detail_prompt)
	return "\n".join(lines)


func _get_money_reward(job: Dictionary) -> int:
	var rewards: Dictionary = job.get("rewards", {}) as Dictionary
	return int(rewards.get("money", 0))


func _build_part_time_activity_block(job: Dictionary, event_seed: String = "") -> String:
	var activity_text: String = "这次兼职的自然活动应该贴合岗位本身，不要写成泛泛的职场日常。"

	var lines: Array[String] = [activity_text]
	var seed_text: String = event_seed.strip_edges()
	if not seed_text.is_empty():
		lines.append("")
		lines.append("本次兼职的突发切入点（必须在场景中自然发生）：")
		lines.append("- " + seed_text)
		lines.append("- 这是一个客观发生的微小事件，请围绕它自然地展开互动，不要直接复述设定。")
	lines.append("选项必须像两个人忙里偷闲时的自然接话，不要写成策略按钮。")
	lines.append("让场景自己决定这一班里最自然的配合和小波动，不要套固定事件模板。")
	return "\n".join(lines)


## 导演指导模式：以叙事指导为核心方向，不注入 event_seed 避免冲突。
func _build_part_time_activity_with_guidance(job: Dictionary, session: Dictionary) -> String:
	var guidance := _build_story_guidance_block(session)
	if guidance.is_empty():
		return _build_part_time_activity_block(job, str(session.get("event_seed", "")))
	return guidance
