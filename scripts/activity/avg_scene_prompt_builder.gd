## Base class for AVG scene prompt builders.
## Subclasses: DatePromptBuilder, PartTimePromptBuilder, SbeamPromptBuilder.
class_name AVGScenePromptBuilder extends RefCounted

const PromptPipelineScript = preload("res://scripts/prompt/prompt_pipeline.gd")
const ChatProjectContextBuilderClass = preload("res://scripts/chat/chat_project_context_builder.gd")


# ---------------------------------------------------------------------------
# Factory: returns the correct subclass based on session activity_type
# ---------------------------------------------------------------------------
static func create_for_session(session: Dictionary) -> AVGScenePromptBuilder:
	var activity_type := str(session.get("activity_type", "")).strip_edges()
	if activity_type == "story" or session.has("story_scene_prompt"):
		return preload("res://scripts/activity/story_prompt_builder.gd").new()
	if activity_type == "sbeam" or session.has("game"):
		return preload("res://scripts/activity/sbeam_prompt_builder.gd").new()
	if activity_type == "part_time" or session.has("job"):
		return preload("res://scripts/activity/part_time_prompt_builder.gd").new()
	return preload("res://scripts/activity/date_prompt_builder.gd").new()


# ---------------------------------------------------------------------------
# Virtual — subclasses must override
# ---------------------------------------------------------------------------
func build_prompt_from_session(_session: Dictionary) -> String:
	push_warning("[AVGScenePromptBuilder] build_prompt_from_session() not overridden")
	return ""


# ---------------------------------------------------------------------------
# Backward-compat wrappers (existing callers keep working)
# ---------------------------------------------------------------------------
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
	var builder := AVGScenePromptBuilder.create_for_session(session)
	return builder.build_prompt_from_session(session)


# ---------------------------------------------------------------------------
# Shared utilities — available to all subclasses
# ---------------------------------------------------------------------------
func _get_autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)


func _build_time_block(day: int, phase: String) -> String:
	var phase_text: String = phase if not phase.is_empty() else "UNKNOWN"
	var display_name: String = _phase_display_name(phase_text)
	var time_range: String = _phase_time_range(phase_text)

	# 使用 session 快照中的 day/phase 构建时间描述，而不是实时读 GameLoopManager。
	# 因为 prompt 构建可能晚于 consume_ap，此时 GameLoopManager 的 phase 已推进。
	var glm: Node = _get_autoload("GameLoopManager")
	var calendar_line: String = ""
	if glm != null and glm.has_method("get_calendar_date"):
		var cal: Dictionary = glm.get_calendar_date()
		# 用 session 快照的 day 重新计算日历日期
		var saved_day: int = max(day, 1)
		var day_offset: int = saved_day - glm.get("current_day")
		if day_offset == 0:
			# 同一天，直接用当前日历
			var weekday: String = glm.get_weekday_name() if glm.has_method("get_weekday_name") else ""
			calendar_line = "当前时间：%d年%d月%d日（%s）・%s，比赛第 %d 天。%s" % [
				cal["year"], cal["month"], cal["day"], weekday, display_name, saved_day, time_range]
		else:
			# session 来自不同天（罕见），只用基础格式
			calendar_line = "当前时间：比赛第 %d 天，%s（%s）。" % [saved_day, display_name, time_range]
	else:
		calendar_line = "当前时间：比赛第 %d 天，%s（%s）。" % [day, display_name, time_range]

	return calendar_line


func _phase_display_name(phase: String) -> String:
	match phase.to_upper():
		"MORNING":
			return "上午"
		"AFTERNOON":
			return "下午"
		"NIGHT":
			return "晚上"
	return phase


func _phase_time_range(phase: String) -> String:
	match phase.to_upper():
		"MORNING":
			return "大约 8:00-12:00"
		"AFTERNOON":
			return "大约 12:00-18:00"
		"NIGHT":
			return "大约 18:00-23:00"
	return "未知时段"


func _build_state_block() -> String:
	var game_manager: Node = _get_autoload("GameManager")
	if game_manager == null or not game_manager.has_method("get_llm_state_prompt"):
		return "当前人物状态：请以正在交往中的大学情侣日常相处为基准。"
	return str(game_manager.get_llm_state_prompt()).strip_edges()


func _build_story_guidance_block(session: Dictionary) -> String:
	return str(session.get("story_guidance_prompt", "")).strip_edges()


func _build_chat_history_block() -> String:
	var chat_manager: Node = _get_autoload("ChatManager")
	if chat_manager == null or not chat_manager.has_method("get_channel"):
		return ""
	var channel = chat_manager.get_channel("dm_lin_xia")
	if channel == null:
		return ""
	var messages: Array = channel.get_recent_messages(30)
	if messages.is_empty():
		return ""
	var typed_msgs: Array[Dictionary] = []
	for m in messages:
		typed_msgs.append(m)
	return ChatPromptBuilder._build_history(typed_msgs, 30)


func _merge_story_guidance(base_block: String, session: Dictionary) -> String:
	var guidance := _build_story_guidance_block(session)
	if guidance.is_empty():
		return base_block
	var merged := base_block.strip_edges()
	if not merged.is_empty():
		merged += "\n\n"
	merged += "[导演指导]\n%s" % guidance
	return merged.strip_edges()


## Common pipeline resolution: resolve template → inject lore → return final text.
## Returns empty string if PromptManager is unavailable or the key doesn't exist,
## so callers can fall back to inline text.
func _resolve_with_pipeline(prompt_key: String, ctx: Dictionary, session: Dictionary) -> String:
	var prompt_manager: Node = _get_autoload("PromptManager")
	if prompt_manager == null or not prompt_manager.has_method("resolve_with_vars"):
		push_warning("[AVGScenePromptBuilder] PromptManager unavailable")
		return ""
	ctx["lore_facts"] = ""
	ctx["lore_constraints"] = ""
	if prompt_manager.has_method("has_prompt") and prompt_manager.has_prompt(prompt_key):
		var pipeline_result := PromptPipelineScript.build_prompt(
			prompt_key,
			ctx,
			{"lore_mode": "avg", "lore_args": {"session": session}},
		)
		return str(pipeline_result.get("prompt", "")).strip_edges()
	return ""


## 构建 AVG 场景生成专用的「项目共享上下文」段，注入到外层 dsl_preview 模板的
## {{project_shared_context}} 占位符。包含：开发循环 + 工单状态 + KB 索引段。
##
## 与 ChatProjectContextBuilder.build_for_chat() 不同：本函数无 NPC scope 门槛
## （AVG 生成是导演视角，全部展开），且 scan_text 传空（无玩家输入，也命中不上）。
## LLM 需要某 KB 文档全文时通过工具 kb_read 主动取。
##
## 设计为 static 是因为外层 generator 不持有 builder 实例（不是 builder 子类）。
static func build_avg_project_shared_context() -> String:
	var builder := ChatProjectContextBuilderClass.new()
	var sections: PackedStringArray = [
		"## 项目共享上下文",
		"你正在为「玩家与女友林夏合作开发的项目」生成 AVG 场景。下面是项目当前进度和设定文档目录，写台词时注意与之保持一致——比如林夏不应该说出与项目实际状态矛盾的话。",
	]

	var dev_cycle: String = builder.build_dev_cycle_context().strip_edges()
	if not dev_cycle.is_empty():
		sections.append("### 开发循环\n%s" % dev_cycle)

	var work_orders: String = builder.build_work_order_context().strip_edges()
	if not work_orders.is_empty():
		sections.append("### 工单状态\n%s" % work_orders)

	# scan_text 传空 → 只输出索引段，命中段不会出现
	var kb_block: String = builder.build_kb_context("").strip_edges()
	if not kb_block.is_empty():
		sections.append(kb_block)
		sections.append("如需深读某 KB 文档全文，可调用 kb_read(doc_id=\"...\") 工具。仅在确实需要参考时调用，避免不必要的查询。")

	return "\n\n".join(sections).strip_edges()
