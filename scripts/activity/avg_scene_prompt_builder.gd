class_name AVGScenePromptBuilder extends RefCounted

const NORMAL_PROMPT_KEY: String = "date_scene_normal"
const PART_TIME_PROMPT_KEY: String = "part_time_scene_normal"
const SBEAM_PROMPT_KEY: String = "sbeam_scene_normal"


func build_normal_date_prompt(session_id: String) -> String:
	var session: Dictionary = {}

	var date_manager: Node = _get_autoload("DateManager")
	if date_manager != null and date_manager.has_method("get_session_snapshot"):
		session = date_manager.get_session_snapshot(session_id)

	if session.is_empty():
		var part_time_manager: Node = _get_autoload("PartTimeJobManager")
		if part_time_manager != null and part_time_manager.has_method("get_session_snapshot"):
			session = part_time_manager.get_session_snapshot(session_id)

	if session.is_empty():
		push_warning("[AVGScenePromptBuilder] Session '%s' not found" % session_id)
		return ""
	return build_normal_date_prompt_from_session(session)


func build_normal_date_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	if _is_sbeam_session(session):
		return build_sbeam_prompt_from_session(session)
	if _is_part_time_session(session):
		return build_part_time_prompt_from_session(session)

	var prompt_manager: Node = _get_autoload("PromptManager")
	if prompt_manager == null or not prompt_manager.has_method("register_prompt") or not prompt_manager.has_method("resolve"):
		push_warning("[AVGScenePromptBuilder] PromptManager unavailable")
		return ""

	var location: Dictionary = session.get("location", {})
	var detail_prompt: String = str(session.get("detail_prompt", location.get("detail_prompt", ""))).strip_edges()
	var day: int = int(session.get("start_day", 1))
	var phase: String = str(session.get("phase_after_action", "")).strip_edges()

	prompt_manager.register_prompt("date_scene_location", _build_location_block(location, detail_prompt))
	prompt_manager.register_prompt("date_scene_activity", _build_date_activity_block(location, str(session.get("event_seed", ""))))
	prompt_manager.register_prompt("date_scene_time", _build_time_block(day, phase))
	prompt_manager.register_prompt("date_scene_state", _build_state_block())

	if prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(NORMAL_PROMPT_KEY):
		return str(prompt_manager.resolve(NORMAL_PROMPT_KEY)).strip_edges()

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
		_build_date_activity_block(location, str(session.get("event_seed", ""))),
		"",
		"## 当前人物状态",
		_build_state_block(),
		"",
		"## 场景结构要求",
		"- 必须包含四段：到达地点、一起活动、一次自然聊天选择、回家收尾。",
		"- 普通约会只允许一次选择，选项数为 2 到 3 个。",
		"- 选项必须像自然接话，不要像策略按钮或数值提示。",
		"- 整体氛围应当像 Galgame 里的日常约会，不要写成系统事件。",
		"- 可以轻微提到项目或最近状态，但不要变成议题讨论会。",
		"- 不要表白，不要定义关系，不要突然争吵升级，不要扯到过重的家庭或未来命题。",
		"- 场景必须在回家收尾处结束，不要把回家后的 LinkChat、朋友圈或系统结算写进 AVG 场景。",
	]).strip_edges()


func build_part_time_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	var prompt_manager: Node = _get_autoload("PromptManager")
	if prompt_manager == null or not prompt_manager.has_method("register_prompt") or not prompt_manager.has_method("resolve"):
		push_warning("[AVGScenePromptBuilder] PromptManager unavailable")
		return ""

	var job: Dictionary = session.get("job", session.get("location", {}))
	var detail_prompt: String = str(session.get("detail_prompt", job.get("detail_prompt", ""))).strip_edges()
	var day: int = int(session.get("start_day", 1))
	var phase: String = str(session.get("phase_after_action", "")).strip_edges()

	prompt_manager.register_prompt("part_time_scene_job", _build_part_time_job_block(job, detail_prompt))
	prompt_manager.register_prompt("part_time_scene_activity", _build_part_time_activity_block(job, str(session.get("event_seed", ""))))
	prompt_manager.register_prompt("part_time_scene_time", _build_time_block(day, phase))
	prompt_manager.register_prompt("part_time_scene_state", _build_state_block())

	if prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(PART_TIME_PROMPT_KEY):
		return str(prompt_manager.resolve(PART_TIME_PROMPT_KEY)).strip_edges()

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


func build_sbeam_prompt_from_session(session: Dictionary) -> String:
	if session.is_empty():
		return ""

	var prompt_manager: Node = _get_autoload("PromptManager")
	if prompt_manager == null or not prompt_manager.has_method("register_prompt") or not prompt_manager.has_method("resolve"):
		push_warning("[AVGScenePromptBuilder] PromptManager unavailable")
		return ""

	var game: Dictionary = session.get("game", {})
	var day: int = int(session.get("start_day", 1))
	var phase: String = str(session.get("phase_after_action", "")).strip_edges()
	var detail_prompt: String = str(session.get("detail_prompt", "")).strip_edges()

	prompt_manager.register_prompt("sbeam_game_block", _build_sbeam_game_block(game, day, phase, detail_prompt))
	prompt_manager.register_prompt("sbeam_state_block", _build_state_block())

	if prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(SBEAM_PROMPT_KEY):
		return str(prompt_manager.resolve(SBEAM_PROMPT_KEY)).strip_edges()

	return "\n".join([
		"你要生成一段一起玩 sbeam 游戏的普通活动场景要求。",
		"这不是项目讨论，不是作品评测，也不是高潮剧情。",
		"重点是两个人在当前时段里，共同体验了一款虚构游戏，并因此产生了自然互动。",
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


func _get_autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)


func _is_sbeam_session(session: Dictionary) -> bool:
	return str(session.get("activity_type", "")).strip_edges() == "sbeam" or session.has("game")


func _is_part_time_session(session: Dictionary) -> bool:
	return str(session.get("activity_type", "")).strip_edges() == "part_time" or session.has("job")


func _build_location_block(location: Dictionary, detail_prompt: String) -> String:
	var title: String = str(location.get("title", "未命名地点")).strip_edges()
	var subtitle: String = str(location.get("subtitle", "")).strip_edges()
	var description: String = str(location.get("description", "")).strip_edges()
	var lines: Array[String] = ["约会地点：%s" % title]
	if not subtitle.is_empty():
		lines.append("地点氛围：%s" % subtitle)
	if not description.is_empty():
		lines.append("地点简介：%s" % description)
	if not detail_prompt.is_empty():
		lines.append("地点设定：%s" % detail_prompt)
	return "\n".join(lines)


func _build_date_activity_block(location: Dictionary, event_seed: String = "") -> String:
	var activity_text: String = str(location.get("base_activity", "")).strip_edges()
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
	lines.append("让场景自己决定今晚最自然会发生的互动，不要套固定事件模板。")
	return "\n".join(lines)


func _build_part_time_job_block(job: Dictionary, detail_prompt: String) -> String:
	var job_title: String = str(job.get("job_title", job.get("title", "兼职"))).strip_edges()
	var company_name: String = str(job.get("company_name", job.get("title", ""))).strip_edges()
	var district: String = str(job.get("district", "")).strip_edges()
	var subtitle: String = str(job.get("subtitle", "")).strip_edges()
	var description: String = str(job.get("description", "")).strip_edges()
	var duo_note: String = str(job.get("duo_note", "")).strip_edges()
	var salary_text: String = str(job.get("salary_text", "")).strip_edges()

	var lines: Array[String] = ["兼职岗位：%s" % job_title]
	if not company_name.is_empty():
		lines.append("店铺 / 公司：%s" % company_name)
	if not district.is_empty():
		lines.append("地点：%s" % district)
	if not salary_text.is_empty():
		lines.append("报酬：%s" % salary_text)
	if not subtitle.is_empty():
		lines.append("岗位气质：%s" % subtitle)
	if not description.is_empty():
		lines.append("工作内容：%s" % description)
	if not duo_note.is_empty():
		lines.append("双人设定：%s" % duo_note)
	if not detail_prompt.is_empty():
		lines.append("现场设定：%s" % detail_prompt)
	return "\n".join(lines)


func _build_part_time_activity_block(job: Dictionary, event_seed: String = "") -> String:
	var activity_text: String = str(job.get("base_activity", "")).strip_edges()
	if activity_text.is_empty():
		activity_text = "这次兼职的自然活动应该贴合岗位本身，不要写成泛泛的职场日常。"

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


func _build_time_block(day: int, phase: String) -> String:
	var phase_text: String = phase if not phase.is_empty() else "UNKNOWN"
	return "当前时间：比赛第 %d 天，时段为 %s。" % [day, phase_text]


func _build_state_block() -> String:
	var game_manager: Node = _get_autoload("GameManager")
	if game_manager == null or not game_manager.has_method("get_llm_state_prompt"):
		return "当前人物状态：请以正在交往中的大学情侣日常相处为基准。"
	return str(game_manager.get_llm_state_prompt()).strip_edges()


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
