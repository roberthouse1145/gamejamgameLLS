extends MinigameBase
## 创意决策小游戏 · LinkChat 风双栏讨论室
##
## 左栏：活提案稿；右栏：可复用 IMThreadPanel。
## LLM 请求改用稳定 messages 结构，以复用 DeepSeek 硬盘缓存前缀。

const IMThreadPanelClass = preload("res://scripts/apps/linkchat/components/im_thread_panel.gd")
const LCTheme = preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const PromptPipelineScript = preload("res://scripts/prompt/prompt_pipeline.gd")
const ChatProjectContextBuilderClass = preload("res://scripts/chat/chat_project_context_builder.gd")
const ChatChannelClass = preload("res://scripts/chat/resources/chat_channel.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const ChatAgentScene = preload("res://scenes/llm/chat_agent.tscn")
const AVGDevKBToolsClass = preload("res://scripts/avg/dev_tools/kb_tools.gd")
const AVGDevWorkOrderToolsClass = preload("res://scripts/avg/dev_tools/work_order_tools.gd")

const DIALOG_LLM_ROLE: String = "creative_decision_dialog"
const DIALOG_LLM_FALLBACKS: Array[String] = ["creative_decision", "chat_default"]
const PROPOSAL_LLM_ROLE: String = "creative_decision_proposal"
const PROPOSAL_LLM_FALLBACKS: Array[String] = ["creative_decision", "chat_default"]
const WORK_ORDER_BRIEF_LLM_ROLE: String = "creative_decision_work_order"
const WORK_ORDER_BRIEF_FALLBACKS: Array[String] = ["work_order", "creative_decision", "chat_default"]
const DIALOG_PROMPT_KEY: String = "minigame_creative_decision_dialog"
const PROPOSAL_PROMPT_KEY: String = "minigame_creative_decision_proposal"
const WORK_ORDER_BRIEF_PROMPT_KEY: String = "minigame_creative_decision_work_order_brief"
const DEFAULT_MAX_ROUNDS: int = 12
const UNLIMITED_TOOL_ITERATIONS: int = 0

var _dialog_ai: ChatAgent = null
var _proposal_ai: ChatAgent = null
var _work_order_brief_ai: ChatAgent = null
var _project_context_builder = null

var _dialog_system_prompt: String = ""
var _proposal_system_prompt: String = ""
var _work_order_brief_system_prompt: String = ""
var _dialog_messages: Array[Dictionary] = []
var _pending_dialog_user_message: String = ""
var _pending_proposal_user_message: String = ""
var _pending_work_order_brief_user_message: String = ""

var _max_rounds: int = DEFAULT_MAX_ROUNDS
var _round: int = 0
var _discussion_state: String = "continue"
var _goal_description: String = ""
var _seed_proposal_text: String = ""
var _project_shared_context: String = ""
var _project_kb_context: String = ""

var _current_proposal: Dictionary = {"title": "", "summary": "", "core": "", "nodes": [], "decisions": [], "locked": []}
var _proposal_version: int = 0
var _last_update_round: int = 0
var _conversation: Array[Dictionary] = []

var _dialog_in_flight: bool = false
var _proposal_in_flight: bool = false
var _proposal_refresh_pending: bool = false
var _work_order_brief_in_flight: bool = false
var _npc_presentation_in_flight: bool = false
var _im_sequence_in_progress: bool = false
var _pending_dialog_request_id: String = ""
var _pending_proposal_request_id: String = ""
var _pending_work_order_brief_request_id: String = ""
var _pending_finalize_after_presentation: bool = false
var _has_finalized: bool = false
var _settle_after_proposal: bool = false
var _work_order_brief_text: String = ""

var _root_split: HSplitContainer = null
var _left_panel: PanelContainer = null
var _proposal_version_label: Label = null
var _proposal_meta_label: Label = null
var _proposal_title_label: Label = null
var _proposal_summary_label: Label = null
var _proposal_core_label: Label = null
var _proposal_nodes_box: VBoxContainer = null
var _proposal_decisions_box: VBoxContainer = null
var _proposal_locked_box: HFlowContainer = null
var _proposal_updating_label: Label = null
var _round_label: Label = null
var _thread_panel: IMThreadPanel = null

const COLOR_PROPOSAL_NODE := Color("#555555")
const COLOR_LOCKED_BG := Color("#E8F6DD")
const COLOR_LOCKED_FG := Color("#2B6B20")


func _on_minigame_start() -> void:
	_parse_config()
	_setup_context()
	_setup_ai_services()
	_build_prompts()
	_build_ui()
	_render_seed_proposal()
	_request_first_dialog()


func _on_minigame_cleanup() -> void:
	if _thread_panel != null:
		_thread_panel.cancel_presentation()
	if _dialog_ai != null:
		_dialog_ai.reset()
	if _proposal_ai != null:
		_proposal_ai.reset()
	if _work_order_brief_ai != null:
		_work_order_brief_ai.reset()


func _parse_config() -> void:
	_max_rounds = clampi(int(task_data.get("rounds", DEFAULT_MAX_ROUNDS)), 3, 20)
	var topic_config: Dictionary = task_data.get("topic_config", {})
	_goal_description = str(topic_config.get("goal_description", str(task_data.get("description", "")))).strip_edges()
	_seed_proposal_text = str(task_data.get("description", "")).strip_edges()
	if _seed_proposal_text.is_empty():
		_seed_proposal_text = _goal_description


func _setup_context() -> void:
	_project_context_builder = ChatProjectContextBuilderClass.new()
	var dialog_context: PackedStringArray = []
	var dev_cycle := str(_project_context_builder.build_dev_cycle_context()).strip_edges()
	var work_orders := str(_project_context_builder.build_work_order_context()).strip_edges()
	if not dev_cycle.is_empty():
		dialog_context.append("### 开发循环\n%s" % dev_cycle)
	if not work_orders.is_empty():
		dialog_context.append("### 工单状态\n%s" % work_orders)
	_project_shared_context = "\n\n".join(dialog_context)
	if _project_shared_context.is_empty():
		_project_shared_context = "当前没有额外项目摘要。"
	_project_kb_context = str(_project_context_builder.build_kb_context()).strip_edges()


func _setup_ai_services() -> void:
	_dialog_ai = ChatAgentScene.instantiate()
	_dialog_ai.name = "CreativeDecisionDialogAI"
	add_child(_dialog_ai)
	_dialog_ai.message_completed.connect(_on_dialog_ai_completed)
	_dialog_ai.message_failed.connect(_on_dialog_ai_failed)
	_configure_ai_service(_dialog_ai, DIALOG_LLM_ROLE, DIALOG_LLM_FALLBACKS)

	_proposal_ai = ChatAgentScene.instantiate()
	_proposal_ai.name = "CreativeDecisionProposalAI"
	add_child(_proposal_ai)
	_proposal_ai.message_completed.connect(_on_proposal_ai_completed)
	_proposal_ai.message_failed.connect(_on_proposal_ai_failed)
	_configure_ai_service(_proposal_ai, PROPOSAL_LLM_ROLE, PROPOSAL_LLM_FALLBACKS)

	_work_order_brief_ai = ChatAgentScene.instantiate()
	_work_order_brief_ai.name = "CreativeDecisionWorkOrderBriefAI"
	add_child(_work_order_brief_ai)
	_work_order_brief_ai.message_completed.connect(_on_work_order_brief_ai_completed)
	_work_order_brief_ai.message_failed.connect(_on_work_order_brief_ai_failed)
	_configure_ai_service(_work_order_brief_ai, WORK_ORDER_BRIEF_LLM_ROLE, WORK_ORDER_BRIEF_FALLBACKS)


func _configure_ai_service(agent: ChatAgent, role: String, fallbacks: Array[String]) -> bool:
	if agent == null:
		return false
	var config_mgr := AIConfigManager.get_instance()
	if config_mgr == null:
		return false
	var ai: AIService = agent.get_node_or_null("AIService") as AIService
	if ai == null:
		return false
	ai.auto_execute_tools = true
	ai.max_tool_iterations = UNLIMITED_TOOL_ITERATIONS
	AVGDevKBToolsClass.register_read_only(ai)
	AVGDevWorkOrderToolsClass.register_summary_read_only(ai)
	agent.register_tool(
		"get_dev_cycle_snapshot",
		"获取当前开发循环的简要状态，包括当前天数、可见任务、已完成任务数量、后台队列和计划状态。",
		{"type": "object", "properties": {}},
		func(_args: Dictionary) -> Variant: return _build_dev_cycle_snapshot()
	)
	if not config_mgr.get_config_for_role(role).is_empty() and config_mgr.apply_to_service(ai, role):
		return true
	for fallback in fallbacks:
		var fallback_role := str(fallback)
		if not config_mgr.get_config_for_role(fallback_role).is_empty() and config_mgr.apply_to_service(ai, fallback_role):
			return true
	return false


func _build_agent_options(role: String, prompt_key: String, temperature: float) -> Dictionary:
	return {
		"source": "CreativeDecision",
		"role": role,
		"prompt_key": prompt_key,
		"temperature": temperature,
	}


func _build_dev_cycle_snapshot() -> Dictionary:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		return {"success": false, "error": "DevCycleManager not available"}
	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	var visible_summary: Array = []
	for task in visible_tasks:
		if task is Dictionary:
			visible_summary.append({
				"task_id": str(task.get("task_id", "")),
				"title": str(task.get("title", "")),
				"status": str(task.get("status", "")),
				"minigame_type": str(task.get("minigame_type", "")),
			})
	return {
		"success": true,
		"completed_count": int(dcm.get_completed_count()) if dcm.has_method("get_completed_count") else 0,
		"queue_size": int(dcm.get_queue_size()) if dcm.has_method("get_queue_size") else 0,
		"order_active": bool(dcm.is_order_active()) if dcm.has_method("is_order_active") else false,
		"plan_generated": bool(dcm.get("_plan_generated")),
		"visible_tasks": visible_summary,
	}


func _build_prompts() -> void:
	_dialog_system_prompt = _build_dialog_system_prompt()
	_proposal_system_prompt = _build_proposal_system_prompt()
	_work_order_brief_system_prompt = _build_work_order_brief_system_prompt()


func _build_dialog_system_prompt() -> String:
	var channel := _make_lore_channel()
	var topic := _make_lore_topic()
	var npcs := _get_linxia_npcs()
	var shared_context := _project_shared_context
	if not _project_kb_context.is_empty():
		shared_context += "\n\n### 项目知识库\n%s" % _project_kb_context
	var pipeline_result := PromptPipelineScript.build_prompt(
		DIALOG_PROMPT_KEY,
		{
			"project_shared_context": shared_context,
		},
		{
			"lore_mode": "none",
		}
	)
	var prompt := str(pipeline_result.get("prompt", "")).strip_edges()
	if not prompt.is_empty():
		return prompt
	return _fallback_dialog_prompt()


func _build_proposal_system_prompt() -> String:
	var pipeline_result := PromptPipelineScript.build_prompt(
		PROPOSAL_PROMPT_KEY,
		{
			"project_kb_context": _project_kb_context,
		},
		{"lore_mode": "none"}
	)
	var prompt := str(pipeline_result.get("prompt", "")).strip_edges()
	if not prompt.is_empty():
		return prompt
	return _fallback_proposal_prompt()


func _build_work_order_brief_system_prompt() -> String:
	var pipeline_result := PromptPipelineScript.build_prompt(
		WORK_ORDER_BRIEF_PROMPT_KEY,
		{
			"project_kb_context": _project_kb_context,
		},
		{"lore_mode": "none"}
	)
	var prompt := str(pipeline_result.get("prompt", "")).strip_edges()
	if not prompt.is_empty():
		return prompt
	return _fallback_work_order_brief_prompt()


func _make_lore_channel() -> Resource:
	var channel := ChatChannelClass.new()
	channel.channel_id = "creative_decision_room"
	channel.display_name = "创意讨论室"
	channel.channel_type = ChatChannelClass.ChannelType.DM
	channel.members = ["player", "npc_lin_xia"]
	return channel


func _make_lore_topic() -> Resource:
	var topic := ChatTopicClass.new()
	topic.topic_id = "creative_decision_room"
	topic.topic_type = "casual_interaction"
	topic.display_title = "创意讨论"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "creative_decision_room"
	topic.goal_description = _goal_description
	return topic


func _get_linxia_npcs() -> Array:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.has_method("get_npc"):
		var npc = chat.get_npc("npc_lin_xia")
		if npc != null:
			return [npc]
	return []


func _fallback_dialog_prompt() -> String:
	return "你是林夏。严格输出平铺行协议：@player/@linxia/@reply a b c/@state/@update_proposal。推荐回复必须贴当前情境。"


func _fallback_proposal_prompt() -> String:
	return "你是提案稿沉淀员。严格输出 title/summary/core/node/decision/locked DSL。"


func _fallback_work_order_brief_prompt() -> String:
	return "你是工单整理助手。只输出 JSON：{\"summary\":\"\",\"deliverables\":[],\"constraints\":[],\"evidence\":[],\"risks_open_questions\":[]}。"


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = LCTheme.COLOR_BG_MAIN
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root_split = HSplitContainer.new()
	_root_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_split.split_offset = -200
	add_child(_root_split)

	_build_left_panel()
	_build_right_panel()


func _build_left_panel() -> void:
	_left_panel = PanelContainer.new()
	_left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := LCTheme.rounded_flat(LCTheme.COLOR_BG_SIDEBAR, 0, LCTheme.COLOR_BORDER, 1)
	_left_panel.add_theme_stylebox_override("panel", sb)
	_root_split.add_child(_left_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 24)
	outer_margin.add_theme_constant_override("margin_right", 24)
	outer_margin.add_theme_constant_override("margin_top", 20)
	outer_margin.add_theme_constant_override("margin_bottom", 20)
	_left_panel.add_child(outer_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_margin.add_child(scroll)

	var doc_card := PanelContainer.new()
	doc_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc_card.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_BG_MAIN, 14, LCTheme.COLOR_BORDER, 1, Color(0, 0, 0, 0.06), 4))
	scroll.add_child(doc_card)

	var doc_margin := MarginContainer.new()
	doc_margin.add_theme_constant_override("margin_left", 28)
	doc_margin.add_theme_constant_override("margin_right", 28)
	doc_margin.add_theme_constant_override("margin_top", 26)
	doc_margin.add_theme_constant_override("margin_bottom", 26)
	doc_card.add_child(doc_margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	doc_margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_proposal_version_label = Label.new()
	_proposal_version_label.text = "提案文档 v0"
	_proposal_version_label.add_theme_font_size_override("font_size", 15)
	_proposal_version_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	header.add_child(_proposal_version_label)

	_proposal_updating_label = Label.new()
	_proposal_updating_label.text = "林夏正在沉淀..."
	_proposal_updating_label.add_theme_font_size_override("font_size", 14)
	_proposal_updating_label.add_theme_color_override("font_color", LCTheme.COLOR_ACCENT_HOVER)
	_proposal_updating_label.visible = false
	header.add_child(_proposal_updating_label)

	_proposal_meta_label = Label.new()
	_proposal_meta_label.text = "状态：讨论中"
	_proposal_meta_label.add_theme_font_size_override("font_size", 13)
	_proposal_meta_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	vbox.add_child(_proposal_meta_label)

	_proposal_title_label = Label.new()
	_proposal_title_label.text = ""
	_proposal_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_proposal_title_label.add_theme_font_size_override("font_size", 30)
	_proposal_title_label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	vbox.add_child(_proposal_title_label)

	var divider := ColorRect.new()
	divider.color = LCTheme.COLOR_BORDER
	divider.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(divider)

	vbox.add_child(_make_doc_section_label("摘要"))

	_proposal_summary_label = _make_doc_body_label()
	vbox.add_child(_proposal_summary_label)

	vbox.add_child(_make_doc_section_label("核心方向"))

	_proposal_core_label = _make_doc_body_label()
	vbox.add_child(_proposal_core_label)

	vbox.add_child(_make_doc_section_label("方案正文"))

	_proposal_nodes_box = VBoxContainer.new()
	_proposal_nodes_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_proposal_nodes_box)

	vbox.add_child(_make_doc_section_label("已定决策"))

	_proposal_decisions_box = VBoxContainer.new()
	_proposal_decisions_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_proposal_decisions_box)

	vbox.add_child(_make_doc_section_label("约束标签"))

	_proposal_locked_box = HFlowContainer.new()
	_proposal_locked_box.add_theme_constant_override("h_separation", 6)
	_proposal_locked_box.add_theme_constant_override("v_separation", 6)
	vbox.add_child(_proposal_locked_box)


func _build_right_panel() -> void:
	_thread_panel = IMThreadPanelClass.new()
	_thread_panel.setup("npc_lin_xia", "KirbyMiku233")
	_thread_panel.reply_selected.connect(_on_reply_selected)
	_thread_panel.custom_submitted.connect(_on_custom_submitted)
	_thread_panel.presentation_started.connect(func() -> void:
		_npc_presentation_in_flight = true
	)
	_thread_panel.presentation_finished.connect(func() -> void:
		_npc_presentation_in_flight = false
		var allow_input := not _dialog_in_flight and not _im_sequence_in_progress and _discussion_state == "continue"
		_thread_panel.set_input_enabled(allow_input)
		if _pending_finalize_after_presentation:
			_pending_finalize_after_presentation = false
			_try_finalize()
	)
	_root_split.add_child(_thread_panel)
#endregion


#region LLM 调用
func _request_first_dialog() -> void:
	_send_dialog_request({})


func _on_reply_selected(reply: Dictionary) -> void:
	_send_dialog_request({
		"type": "reply",
		"key": str(reply.get("key", "")),
		"title": str(reply.get("title", "")),
		"subtitle": str(reply.get("subtitle", "")),
	})


func _on_custom_submitted(text: String) -> void:
	_send_dialog_request({"type": "custom", "text": text})


func _send_dialog_request(player_input: Dictionary) -> void:
	if _dialog_in_flight:
		return
	_dialog_in_flight = true
	if _thread_panel != null:
		_thread_panel.set_input_enabled(false)
	var user_msg := _build_dialog_user_message(player_input)
	_pending_dialog_user_message = user_msg
	if _dialog_messages.is_empty():
		_dialog_messages.append({"role": "system", "content": _dialog_system_prompt})
	_dialog_messages.append({"role": "user", "content": user_msg})
	_dialog_ai.set_system_prompt_override(_dialog_system_prompt)
	_pending_dialog_request_id = _dialog_ai.send_message_with_options(user_msg, _build_agent_options(DIALOG_LLM_ROLE, DIALOG_PROMPT_KEY, 0.85))
	if _pending_dialog_request_id.is_empty():
		_dialog_in_flight = false
		_apply_dialog_response(_fallback_dialog_response("对话 LLM 不可用"))


func _build_dialog_user_message(player_input: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("【讨论目标】\n%s" % _goal_description)
	parts.append("【当前提案稿】\n%s" % _format_proposal_for_prompt())
	parts.append("【当前轮次】第 %d / %d 轮" % [_round + 1, _max_rounds])
	if player_input.is_empty():
		parts.append("【本轮玩家输入】\n这是开场轮。请由林夏先开口，不要输出 @player 行。")
	else:
		match str(player_input.get("type", "")):
			"reply":
				parts.append("【本轮玩家选择的推荐回复】\n%s：%s\n副标题：%s\n请把它展开成玩家自然发言。" % [
					str(player_input.get("key", "")).to_upper(),
					str(player_input.get("title", "")),
					str(player_input.get("subtitle", "")),
				])
			"custom":
				parts.append("【本轮玩家自由输入】\n%s\n请稍微整理成玩家自然发言，不要改变原意。" % str(player_input.get("text", "")))
	if _round >= _max_rounds - 2:
		parts.append("【收束提示】这是最后一两轮，请自然收束讨论并标 @state | settled。")
	parts.append("请严格输出 DSL。")
	return "\n\n".join(parts)


func _on_dialog_ai_completed(request_id: String, raw_text: String) -> void:
	if request_id != _pending_dialog_request_id:
		return
	_pending_dialog_request_id = ""
	_dialog_in_flight = false
	raw_text = raw_text.strip_edges()
	_debug_log_raw("dialog", raw_text)
	_dialog_messages.append({"role": "assistant", "content": raw_text})
	var parsed := _parse_dialog_response(raw_text)
	if parsed.is_empty():
		parsed = _fallback_dialog_response(raw_text if not raw_text.is_empty() else "林夏刚刚走神了，我们换个说法再试。")
	_apply_dialog_response(parsed)


func _on_dialog_ai_failed(request_id: String, error_message: String) -> void:
	if request_id != _pending_dialog_request_id:
		return
	_pending_dialog_request_id = ""
	_dialog_in_flight = false
	_apply_dialog_response(_fallback_dialog_response(error_message))


func _apply_dialog_response(parsed: Dictionary) -> void:
	_round += 1
	var replies: Array = parsed.get("replies", [])
	var messages: Array = parsed.get("messages", [])
	var pending_state := str(parsed.get("state", "continue"))
	await _render_ordered_messages(messages, replies, pending_state)
	_discussion_state = pending_state
	if _round >= _max_rounds and _discussion_state != "settled":
		_discussion_state = "force_settle"
	if bool(parsed.get("update_proposal", false)):
		_send_proposal_request()
	_update_round_label()
	if _discussion_state == "settled" or _discussion_state == "force_settle":
		if _npc_presentation_in_flight:
			_pending_finalize_after_presentation = true
		else:
			_try_finalize()


func _render_ordered_messages(messages: Array, replies: Array, pending_discussion_state: String = "continue") -> void:
	if messages.is_empty():
		if _thread_panel != null:
			_thread_panel.set_replies(replies)
			_thread_panel.set_input_enabled(not _dialog_in_flight and pending_discussion_state == "continue")
		return

	_im_sequence_in_progress = true
	var pending_linxia: Array[Dictionary] = []
	for idx in range(messages.size()):
		var item = messages[idx]
		if not item is Dictionary:
			continue
		var msg: Dictionary = item
		var speaker := str(msg.get("speaker", "")).strip_edges()
		var text := str(msg.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		if speaker == "linxia":
			_conversation.append({"round": _round, "speaker": "linxia", "text": text})
			pending_linxia.append({
				"sender_id": "npc_lin_xia",
				"sender_name": "KirbyMiku233",
				"content": text,
			})
			continue
		if _thread_panel != null and not pending_linxia.is_empty():
			_thread_panel.present_npc_messages(pending_linxia, [])
			await _thread_panel.presentation_finished
			pending_linxia = []
		_conversation.append({"round": _round, "speaker": "player", "text": text})
		if _thread_panel != null:
			_thread_panel.present_player_message(text)
			await _thread_panel.presentation_finished

	if _thread_panel != null:
		if not pending_linxia.is_empty():
			_thread_panel.present_npc_messages(pending_linxia, replies)
			await _thread_panel.presentation_finished
		else:
			_thread_panel.set_replies(replies)

	_im_sequence_in_progress = false
	if _thread_panel != null:
		_thread_panel.set_input_enabled(not _dialog_in_flight and pending_discussion_state == "continue")


func _send_proposal_request() -> bool:
	if _proposal_in_flight:
		_proposal_refresh_pending = true
		return false
	_proposal_in_flight = true
	_set_proposal_updating(true)
	_pending_proposal_user_message = _build_proposal_user_message()
	_proposal_ai.reset()
	_proposal_ai.set_system_prompt_override(_proposal_system_prompt)
	_pending_proposal_request_id = _proposal_ai.send_message_with_options(
		_pending_proposal_user_message,
		_build_agent_options(PROPOSAL_LLM_ROLE, PROPOSAL_PROMPT_KEY, 0.4)
	)
	if _pending_proposal_request_id.is_empty():
		_proposal_in_flight = false
		_set_proposal_updating(false)
		return false
	return true


func _build_proposal_user_message() -> String:
	var lines: PackedStringArray = []
	lines.append("【讨论目标】\n%s" % _goal_description)
	lines.append("【当前提案稿】\n%s" % _format_proposal_for_prompt())
	var recent: PackedStringArray = []
	for entry in _conversation:
		if int(entry.get("round", 0)) <= _last_update_round:
			continue
		recent.append("%s：%s" % ["林夏" if str(entry.get("speaker", "")) == "linxia" else "玩家", str(entry.get("text", ""))])
	lines.append("【新增对话片段】\n%s" % ("\n".join(recent) if not recent.is_empty() else "（无）"))
	lines.append("请输出新版提案稿 DSL。")
	return "\n\n".join(lines)


func _on_proposal_ai_completed(request_id: String, raw_text: String) -> void:
	if request_id != _pending_proposal_request_id:
		return
	_pending_proposal_request_id = ""
	_proposal_in_flight = false
	_set_proposal_updating(false)
	raw_text = raw_text.strip_edges()
	_debug_log_raw("proposal", raw_text)
	var parsed := _parse_proposal_response(raw_text)
	if not parsed.is_empty():
		_current_proposal = parsed
		_proposal_version += 1
		_last_update_round = _round
		_render_proposal()
	if _proposal_refresh_pending:
		_proposal_refresh_pending = false
		if _send_proposal_request() or _proposal_in_flight:
			return
	if _settle_after_proposal:
		_settle_after_proposal = false
		_finalize_now()


func _on_proposal_ai_failed(request_id: String, error_message: String) -> void:
	if request_id != _pending_proposal_request_id:
		return
	_pending_proposal_request_id = ""
	_proposal_in_flight = false
	_set_proposal_updating(false)
	print("[CreativeDecision] proposal failed: %s" % error_message)
	if _proposal_refresh_pending:
		_proposal_refresh_pending = false
		if _send_proposal_request() or _proposal_in_flight:
			return
	if _settle_after_proposal:
		_settle_after_proposal = false
		_finalize_now()


func _request_work_order_brief() -> void:
	if _work_order_brief_in_flight:
		return
	var final_proposal: Dictionary = _current_proposal.duplicate(true)
	var settled: bool = _discussion_state == "settled"
	_pending_work_order_brief_user_message = _build_work_order_brief_user_message(final_proposal, settled)
	if _pending_work_order_brief_user_message.strip_edges().is_empty():
		_complete_finalize_after_work_order_brief("")
		return
	_work_order_brief_in_flight = true
	_set_proposal_updating(true)
	_work_order_brief_ai.reset()
	_work_order_brief_ai.set_system_prompt_override(_work_order_brief_system_prompt)
	_pending_work_order_brief_request_id = _work_order_brief_ai.send_message_with_options(
		_pending_work_order_brief_user_message,
		_build_agent_options(WORK_ORDER_BRIEF_LLM_ROLE, WORK_ORDER_BRIEF_PROMPT_KEY, 0.35)
	)
	if _pending_work_order_brief_request_id.is_empty():
		_work_order_brief_in_flight = false
		_set_proposal_updating(false)
		_complete_finalize_after_work_order_brief("")


func _build_work_order_brief_user_message(final_proposal: Dictionary, settled: bool) -> String:
	var parts: PackedStringArray = []
	parts.append("【任务标题】\n%s" % str(task_data.get("title", "创意决策任务")))
	parts.append("【任务描述】\n%s" % str(task_data.get("description", "")))
	parts.append("【讨论目标】\n%s" % _goal_description)
	parts.append("【收束状态】\n%s" % ("已自然达成共识" if settled else "轮次结束，使用最后一版"))
	parts.append("【最终文档】\n%s" % _build_proposal_document(final_proposal, settled))
	parts.append("【完整对话记录】\n%s" % _format_conversation_log())
	parts.append("请将以上内容整理为可注入后台工单 description 的 JSON。")
	return "\n\n".join(parts)


func _on_work_order_brief_ai_completed(request_id: String, raw_text: String) -> void:
	if request_id != _pending_work_order_brief_request_id:
		return
	_pending_work_order_brief_request_id = ""
	_work_order_brief_in_flight = false
	_set_proposal_updating(false)
	raw_text = raw_text.strip_edges()
	_debug_log_raw("work_order_brief", raw_text)
	var brief := _parse_work_order_brief_response(raw_text)
	_complete_finalize_after_work_order_brief(brief)


func _on_work_order_brief_ai_failed(request_id: String, error_message: String) -> void:
	if request_id != _pending_work_order_brief_request_id:
		return
	_pending_work_order_brief_request_id = ""
	_work_order_brief_in_flight = false
	_set_proposal_updating(false)
	print("[CreativeDecision] work order brief failed: %s" % error_message)
	_complete_finalize_after_work_order_brief("")
#endregion


#region DSL 解析与 prompt helpers
func _format_proposal_for_prompt() -> String:
	if _proposal_version == 0:
		return "（种子）%s" % _seed_proposal_text
	var lines: PackedStringArray = []
	lines.append("title: %s" % str(_current_proposal.get("title", "")))
	lines.append("summary: %s" % str(_current_proposal.get("summary", "")))
	lines.append("core: %s" % str(_current_proposal.get("core", "")))
	for n in _current_proposal.get("nodes", []):
		lines.append("node: %s" % str(n))
	for d in _current_proposal.get("decisions", []):
		lines.append("decision: %s" % str(d))
	for l in _current_proposal.get("locked", []):
		lines.append("locked: %s" % str(l))
	return "\n".join(lines)


func _parse_dialog_response(raw_text: String) -> Dictionary:
	var text := _strip_code_fence(raw_text)
	var messages: Array[Dictionary] = []
	var replies: Array[Dictionary] = []
	var state := "continue"
	var update_proposal := false
	var lines := text.split("\n")
	if text.to_lower().contains("@player_say") or text.to_lower().contains("@linxia_say"):
		return _parse_legacy_dialog_response(text)

	for raw_line in lines:
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		var lower := line.to_lower()
		if lower.begins_with("@player "):
			var content := line.substr("@player".length()).strip_edges()
			if not content.is_empty():
				messages.append({"speaker": "player", "text": content})
		elif lower.begins_with("@linxia "):
			var content2 := line.substr("@linxia".length()).strip_edges()
			if not content2.is_empty():
				messages.append({"speaker": "linxia", "text": content2})
		elif lower.begins_with("@reply") or lower.begins_with("@card"):
			var reply := _parse_reply_line(line)
			if not reply.is_empty():
				replies.append(reply)
		elif lower.begins_with("@state"):
			state = "settled" if _strip_inline_value(line, "@state").to_lower().contains("settled") else "continue"
		elif lower.begins_with("@update_proposal"):
			update_proposal = _strip_inline_value(line, "@update_proposal").to_lower().contains("true")
	while replies.size() < 3:
		replies.append({"key": ["a", "b", "c"][replies.size()], "title": "再说说看", "subtitle": "继续推进当前方向"})
	if messages.is_empty() and replies.is_empty():
		return {}
	return {"messages": messages, "replies": replies.slice(0, 3), "state": state, "update_proposal": update_proposal}


func _parse_legacy_dialog_response(text: String) -> Dictionary:
	var messages: Array[Dictionary] = []
	var replies: Array[Dictionary] = []
	var state := "continue"
	var update_proposal := false
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var line := str(lines[i]).strip_edges()
		var lower := line.to_lower()
		if lower == "@player_say":
			var collected: PackedStringArray = []
			i += 1
			while i < lines.size() and str(lines[i]).strip_edges().to_lower() != "@end":
				collected.append(str(lines[i]))
				i += 1
			var player_block := "\n".join(collected).strip_edges()
			for msg in _split_block_to_messages(player_block):
				messages.append({"speaker": "player", "text": msg})
		elif lower == "@linxia_say":
			var collected2: PackedStringArray = []
			i += 1
			while i < lines.size() and str(lines[i]).strip_edges().to_lower() != "@end":
				collected2.append(str(lines[i]))
				i += 1
			var linxia_block := "\n".join(collected2).strip_edges()
			for msg2 in _split_block_to_messages(linxia_block):
				messages.append({"speaker": "linxia", "text": msg2})
		elif lower.begins_with("@reply") or lower.begins_with("@card"):
			var reply := _parse_reply_line(line)
			if not reply.is_empty():
				replies.append(reply)
		elif lower.begins_with("@state"):
			state = "settled" if _strip_inline_value(line, "@state").to_lower().contains("settled") else "continue"
		elif lower.begins_with("@update_proposal"):
			update_proposal = _strip_inline_value(line, "@update_proposal").to_lower().contains("true")
		i += 1
	while replies.size() < 3:
		replies.append({"key": ["a", "b", "c"][replies.size()], "title": "再说说看", "subtitle": "继续推进当前方向"})
	return {"messages": messages, "replies": replies.slice(0, 3), "state": state, "update_proposal": update_proposal}


func _split_block_to_messages(block: String) -> Array[String]:
	var result: Array[String] = []
	for raw in block.split("\n", false):
		var line := str(raw).strip_edges()
		if line.is_empty():
			continue
		if line.to_lower().begins_with("@msg "):
			line = line.substr("@msg".length()).strip_edges()
		if not line.is_empty():
			result.append(line)
	return result


func _parse_reply_line(line: String) -> Dictionary:
	var body := line.replace("｜", "|")
	if body.to_lower().begins_with("@reply"):
		body = body.substr(6).strip_edges()
	elif body.to_lower().begins_with("@card"):
		body = body.substr(5).strip_edges()
	var parts := body.split("|", false)
	if parts.size() < 2:
		return {}
	var key := str(parts[0]).strip_edges().to_lower()
	if key.length() > 2:
		key = ""
	var title := str(parts[1]).strip_edges()
	var subtitle := ""
	if parts.size() >= 3:
		var rest: PackedStringArray = []
		for idx in range(2, parts.size()):
			rest.append(str(parts[idx]).strip_edges())
		subtitle = " ".join(rest).strip_edges()
	if title.is_empty():
		title = "继续聊"
	return {"key": key, "title": title, "subtitle": subtitle}


func _parse_proposal_response(raw_text: String) -> Dictionary:
	var text := _strip_code_fence(raw_text)
	var title := ""
	var summary := ""
	var core := ""
	var nodes: Array[String] = []
	var decisions: Array[String] = []
	var locked: Array[String] = []
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		var lower := line.to_lower()
		if lower.begins_with("title:") or lower.begins_with("title："):
			title = _strip_label_value(line, ["title:", "title："])
		elif lower.begins_with("summary:") or lower.begins_with("summary："):
			summary = _strip_label_value(line, ["summary:", "summary："])
		elif lower.begins_with("core:") or lower.begins_with("core："):
			core = _strip_label_value(line, ["core:", "core："])
		elif lower.begins_with("node:") or lower.begins_with("node："):
			var n := _strip_label_value(line, ["node:", "node："])
			if not n.is_empty():
				nodes.append(n)
		elif lower.begins_with("decision:") or lower.begins_with("decision："):
			var d := _strip_label_value(line, ["decision:", "decision："])
			if not d.is_empty():
				decisions.append(d)
		elif lower.begins_with("locked:") or lower.begins_with("locked："):
			var l := _strip_label_value(line, ["locked:", "locked："])
			if not l.is_empty():
				locked.append(l)
	if title.is_empty() and core.is_empty() and nodes.is_empty():
		return {}
	if summary.is_empty():
		summary = core
	return {
		"title": title if not title.is_empty() else "讨论方向",
		"summary": summary,
		"core": core,
		"nodes": nodes,
		"decisions": decisions,
		"locked": locked,
	}


func _parse_work_order_brief_response(raw_text: String) -> String:
	var text := _strip_code_fence(raw_text)
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return ""
	var data: Dictionary = parser.data
	return _format_work_order_brief(data)


func _format_work_order_brief(data: Dictionary) -> String:
	var lines: PackedStringArray = []
	var summary := str(data.get("summary", "")).strip_edges()
	if not summary.is_empty():
		lines.append("## 讨论结论")
		lines.append(summary)
		lines.append("")

	var deliverables := _variant_to_string_array(data.get("deliverables", []))
	if not deliverables.is_empty():
		lines.append("## 交付物")
		for item in deliverables:
			lines.append("- %s" % item)
		lines.append("")

	var constraints := _variant_to_string_array(data.get("constraints", []))
	if not constraints.is_empty():
		lines.append("## 约束条件")
		for item in constraints:
			lines.append("- %s" % item)
		lines.append("")

	var evidence := _variant_to_string_array(data.get("evidence", []))
	if not evidence.is_empty():
		lines.append("## 讨论依据")
		for item in evidence:
			lines.append("- %s" % item)
		lines.append("")

	var risks := _variant_to_string_array(data.get("risks_open_questions", data.get("risks", [])))
	if not risks.is_empty():
		lines.append("## 风险与待定")
		for item in risks:
			lines.append("- %s" % item)

	return "\n".join(lines).strip_edges()


func _variant_to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	else:
		var text := str(value).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _fallback_dialog_response(message: String) -> Dictionary:
	return {
		"messages": [{"speaker": "linxia", "text": message}],
		"replies": [
			{"key": "a", "title": "继续这个方向", "subtitle": "让林夏再展开一点"},
			{"key": "b", "title": "换个角度", "subtitle": "从另一个切入点聊"},
			{"key": "c", "title": "先这样定", "subtitle": "把当前方向收束"},
		],
		"state": "continue",
		"update_proposal": false,
	}


func _strip_code_fence(text: String) -> String:
	var result := text.strip_edges()
	if result.begins_with("```"):
		var first_newline := result.find("\n")
		if first_newline >= 0:
			result = result.substr(first_newline + 1)
		if result.ends_with("```"):
			result = result.substr(0, result.length() - 3).strip_edges()
	return result


func _strip_inline_value(line: String, tag: String) -> String:
	var body := line.substr(tag.length()).strip_edges() if line.to_lower().begins_with(tag.to_lower()) else line
	if body.begins_with("|"):
		body = body.substr(1).strip_edges()
	return body


func _strip_label_value(line: String, labels: Array) -> String:
	for label in labels:
		var label_str := str(label)
		if line.to_lower().begins_with(label_str.to_lower()):
			return line.substr(label_str.length()).strip_edges()
	return line.strip_edges()


func _debug_log_raw(tag: String, raw_text: String) -> void:
	var config_mgr := AIConfigManager.get_instance()
	if config_mgr != null and config_mgr.is_quiet_logs_enabled():
		return
	print("[CreativeDecision][%s] raw (round %d):\n%s" % [tag, _round, raw_text])
#endregion


#region UI 渲染：提案稿
func _render_seed_proposal() -> void:
	# 把种子描述显示为初始 core，title / nodes / locked 留空
	_proposal_title_label.text = "讨论目标"
	if _proposal_meta_label != null:
		_proposal_meta_label.text = "状态：讨论中 · 等待第一版沉淀"
	if _proposal_summary_label != null:
		_proposal_summary_label.text = "这是一份临时讨论稿。左侧会随着对话沉淀成可写入企划的正式 brief。"
	if _proposal_core_label != null:
		_proposal_core_label.text = _seed_proposal_text if not _seed_proposal_text.is_empty() else _goal_description
	_clear_box(_proposal_nodes_box)
	_clear_box(_proposal_decisions_box)
	_clear_box(_proposal_locked_box)
	_proposal_version_label.text = "提案文档 v0"


func _render_proposal() -> void:
	# 整段淡入淡出
	if _left_panel == null:
		return
	# 写新内容
	_proposal_title_label.text = str(_current_proposal.get("title", ""))
	if _proposal_meta_label != null:
		_proposal_meta_label.text = "状态：%s · 第 %d 轮更新" % ["已收束" if _discussion_state == "settled" else "讨论中", _round]
	if _proposal_summary_label != null:
		var summary := str(_current_proposal.get("summary", "")).strip_edges()
		if summary.is_empty():
			summary = str(_current_proposal.get("core", "")).strip_edges()
		_proposal_summary_label.text = summary
	_proposal_core_label.text = str(_current_proposal.get("core", ""))

	_clear_box(_proposal_nodes_box)
	var node_index := 1
	for n in _current_proposal.get("nodes", []):
		_proposal_nodes_box.add_child(_make_doc_numbered_row(node_index, str(n)))
		node_index += 1
	if node_index == 1:
		_proposal_nodes_box.add_child(_make_doc_empty_label("暂未沉淀具体正文节拍"))

	_clear_box(_proposal_decisions_box)
	var decisions: Array = _current_proposal.get("decisions", [])
	for d in decisions:
		_proposal_decisions_box.add_child(_make_doc_decision_row(str(d)))
	if decisions.is_empty():
		_proposal_decisions_box.add_child(_make_doc_empty_label("尚未形成明确决策"))

	_clear_box(_proposal_locked_box)
	for l in _current_proposal.get("locked", []):
		var chip := _make_locked_chip(str(l))
		_proposal_locked_box.add_child(chip)
	if _current_proposal.get("locked", []).is_empty():
		_proposal_locked_box.add_child(_make_locked_chip("待敲定"))

	_proposal_version_label.text = "提案文档 v%d" % _proposal_version

	# 淡入动画
	_left_panel.modulate = Color(1, 1, 1, 0.4)
	var tw := create_tween()
	tw.tween_property(_left_panel, "modulate", Color(1, 1, 1, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _make_locked_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_LOCKED_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "✓ %s" % text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_LOCKED_FG)
	chip.add_child(lbl)
	return chip


func _make_doc_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_SECONDARY)
	return label


func _make_doc_body_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_PRIMARY)
	return label


func _make_doc_empty_label(text: String) -> Label:
	var label := _make_doc_body_label()
	label.text = text
	label.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	return label


func _make_doc_numbered_row(index: int, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var idx := Label.new()
	idx.text = "%02d" % index
	idx.custom_minimum_size = Vector2(32, 0)
	idx.add_theme_font_size_override("font_size", 14)
	idx.add_theme_color_override("font_color", LCTheme.COLOR_TEXT_MUTED)
	row.add_child(idx)
	var body := _make_doc_body_label()
	body.text = text
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("font_color", COLOR_PROPOSAL_NODE)
	row.add_child(body)
	return row


func _make_doc_decision_row(text: String) -> Label:
	var label := _make_doc_body_label()
	label.text = "• %s" % text
	return label


func _set_proposal_updating(updating: bool) -> void:
	if _proposal_updating_label != null:
		_proposal_updating_label.visible = updating


func _clear_box(box: Container) -> void:
	if box == null:
		return
	for child in box.get_children():
		child.queue_free()
#endregion


func _update_round_label() -> void:
	if _round_label != null:
		_round_label.text = "第 %d / %d 轮" % [_round, _max_rounds]


#region 结算
func _try_finalize() -> void:
	if _has_finalized:
		return
	if _proposal_in_flight:
		_settle_after_proposal = true
		if _thread_panel != null:
			_thread_panel.set_input_enabled(false)
		return
	if _last_update_round < _round:
		_settle_after_proposal = true
		if _thread_panel != null:
			_thread_panel.set_input_enabled(false)
		if not _send_proposal_request() and not _proposal_in_flight:
			_settle_after_proposal = false
			_finalize_now()
		return
	_finalize_now()


func _finalize_now() -> void:
	if _has_finalized:
		return
	_has_finalized = true
	if _thread_panel != null:
		_thread_panel.set_input_enabled(false)
	_request_work_order_brief()

func _complete_finalize_after_work_order_brief(brief_text: String = "") -> void:
	_work_order_brief_text = brief_text.strip_edges()
	var summary_data: Dictionary = _build_summary_payload()
	present_summary_and_finish(summary_data)


func _build_summary_payload() -> Dictionary:
	var final_proposal: Dictionary = _current_proposal.duplicate(true)
	var final_title: String = str(final_proposal.get("title", "")).strip_edges()
	if final_title.is_empty():
		final_title = "未敲定方向"

	var settled: bool = _discussion_state == "settled"
	var score: float = 1.0

	var proposal_document: String = _build_proposal_document(final_proposal, settled)
	var fallback_creative_prompt: String = _build_creative_prompt(final_proposal, settled)
	var work_order_brief: String = _work_order_brief_text if not _work_order_brief_text.is_empty() else fallback_creative_prompt
	var review_perf: String = _build_review_performance_desc(final_title, settled)
	var review_type: String = "搭档刚和林夏在讨论室里把「%s」这场讨论的方向定下来了" % _goal_description

	var result: Dictionary = {
		"score": score,
		"final_proposal": final_proposal,
		"proposal_document": proposal_document,
		"work_order_brief": work_order_brief,
		"conversation_log": _conversation.duplicate(true),
		"total_rounds": _round,
		"discussion_state": _discussion_state,
		"goal_description": _goal_description,
		"creative_prompt": work_order_brief,
		"review_type_desc": review_type,
		"review_performance_desc": review_perf,
	}

	var stats: Array[String] = []
	stats.append("敲定方向：「%s」" % final_title)
	stats.append("和林夏来回 %d 轮" % _round)
	if not settled:
		stats.append("（讨论时间到了，先用这一版）")

	return {
		"title": "讨论收束",
		"subtitle": "你和林夏在讨论室里把方向定下来了",
		"stats": stats,
		"button_text": "把这个方向写进文档",
		"result": result,
	}


func _build_creative_prompt(final_proposal: Dictionary, settled: bool) -> String:
	return _build_proposal_document(final_proposal, settled)


func _build_proposal_document(final_proposal: Dictionary, settled: bool) -> String:
	var lines: PackedStringArray = []
	lines.append("【讨论目标】%s" % _goal_description)
	lines.append("【收束状态】%s" % ("玩家与林夏自然达成共识" if settled else "讨论时间到，使用最后一版"))
	lines.append("")
	lines.append("【最终提案稿】")
	lines.append("title: %s" % str(final_proposal.get("title", "")))
	var summary := str(final_proposal.get("summary", "")).strip_edges()
	if not summary.is_empty():
		lines.append("summary: %s" % summary)
	lines.append("core: %s" % str(final_proposal.get("core", "")))
	for n in final_proposal.get("nodes", []):
		lines.append("node: %s" % str(n))
	for d in final_proposal.get("decisions", []):
		lines.append("decision: %s" % str(d))
	for l in final_proposal.get("locked", []):
		lines.append("locked: %s" % str(l))

	# 关键对话节选：只抽"真正改变了提案的对话"——这里近似为 update_proposal 触发后的最近一轮
	# 由于 update_proposal 标记没保留进 _conversation，这里改为：抽出全部林夏发言里包含关键词（"那就/定了/这样/反差/改成"）的最近 3 句 + 对应玩家发言
	var key_excerpts: Array[String] = _extract_key_dialog_excerpts()
	if not key_excerpts.is_empty():
		lines.append("")
		lines.append("【关键讨论节选】")
		for ex in key_excerpts:
			lines.append(ex)

	return "\n".join(lines)


func _format_conversation_log() -> String:
	var lines: PackedStringArray = []
	for entry in _conversation:
		var speaker: String = "林夏" if str(entry.get("speaker", "")) == "linxia" else "玩家"
		var text: String = str(entry.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		lines.append("%s：%s" % [speaker, text])
	return "\n".join(lines)


func _extract_key_dialog_excerpts() -> Array[String]:
	# 简化策略：把最后 4 条对话抽出来作为关键节选（一般包含收束语境）
	var excerpts: Array[String] = []
	var start: int = maxi(0, _conversation.size() - 4)
	for i in range(start, _conversation.size()):
		var entry: Dictionary = _conversation[i]
		var speaker: String = "林夏" if str(entry.get("speaker", "")) == "linxia" else "玩家"
		var text: String = str(entry.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		excerpts.append("- %s：%s" % [speaker, text])
	return excerpts


func _build_review_performance_desc(final_title: String, settled: bool) -> String:
	if settled:
		return "你和林夏来回 %d 轮，最后落在「%s」这个方向" % [_round, final_title]
	return "讨论时间到了，你和林夏聊了 %d 轮，先用「%s」这一版" % [_round, final_title]
#endregion
