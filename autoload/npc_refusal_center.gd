extends Node
## NpcRefusalCenter Autoload
## 集中处理"林夏拒绝玩家行动"的 LLM topic 触发。
##
## 调用方只传入"为什么拒绝"的语义描述（warning_desc），具体措辞由
## prompts/linkchat_npc_refusal.md 模板 + GameManager 当前 mood_summary
## 喂给 ChatManager 的 LLM topic 自动生成。
##
## - LLM 不可用 / 已有 active topic / PromptManager 缺失时，会落到 fallback：
##   把 fallback_text 直接 store 到林夏 DM 频道，确保玩家至少看到一句反馈。
## - 行动按钮的禁用状态由各 Manager 自行维护，不依赖本中心是否触发成功。

const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const PROMPT_KEY: String = "linkchat_npc_refusal"
const DM_CHANNEL_ID: String = "dm_lin_xia"
const NPC_ID: String = "npc_lin_xia"


## 触发一次"被林夏拒绝"的对话。
## refusal_id: 用于 topic_id 去重 + 调试日志，例如 "dev_work_passion_low"
## warning_desc: 给 LLM 的拒绝起因语义描述（不是最终对话）
## fallback_text: ChatManager / PromptManager / topic 激活失败时的本地兜底句
##
## 返回 true 表示 LLM topic 已激活，false 表示走了本地 fallback 或彻底失败。
func trigger_refusal(refusal_id: String, warning_desc: String, fallback_text: String) -> bool:
	var clean_id := refusal_id.strip_edges()
	if clean_id.is_empty():
		clean_id = "generic"
	var clean_desc := warning_desc.strip_edges()
	if clean_desc.is_empty():
		push_warning("[NpcRefusalCenter] empty warning_desc for %s" % clean_id)
		return _store_local_fallback(fallback_text)

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		return _store_local_fallback(fallback_text)

	# 已有别的 topic 占用 DM 频道时，不抢占；走本地兜底，避免冲突
	if chat.has_method("has_active_topic") and chat.has_active_topic(DM_CHANNEL_ID):
		print("[NpcRefusalCenter] DM topic busy, fallback for %s" % clean_id)
		return _store_local_fallback(fallback_text)

	var prompt_text := _resolve_prompt(clean_desc)
	if prompt_text.is_empty():
		return _store_local_fallback(fallback_text)

	var topic := ChatTopicClass.new()
	topic.topic_id = "npc_refusal_%s_%d" % [clean_id, int(Time.get_unix_time_from_system())]
	topic.topic_type = "casual_interaction"
	topic.display_title = "林夏的拒绝"
	topic.npc_id = NPC_ID
	topic.channel_id = DM_CHANNEL_ID
	topic.system_prompt = prompt_text
	topic.goal_description = "拒绝玩家本次行动：%s" % clean_id
	topic.context_data = {
		"linkchat_open_mode": "force",
		"complete_after_first_reply": true,
		"suppress_system_notice": true,
		"npc_refusal": true,
		"refusal_id": clean_id,
	}
	topic.timeout_seconds = 0

	if not chat.activate_topic(topic):
		push_warning("[NpcRefusalCenter] activate_topic failed for %s" % clean_id)
		return _store_local_fallback(fallback_text)

	if chat.has_method("request_topic_npc_reply"):
		chat.request_topic_npc_reply(DM_CHANNEL_ID, "", false, true)
	print("[NpcRefusalCenter] LLM refusal topic activated: %s" % clean_id)
	return true


## 公共方法：根据 warning_desc 渲染拒绝 prompt 模板（注入当前 mood_summary）。
## 复用给其他需要"林夏拒绝/强制"语境但流程不同的活动（如 forced_rest 仍要走自己的进度条）。
## 渲染失败返回空字符串。
func build_refusal_prompt(warning_desc: String) -> String:
	return _resolve_prompt(warning_desc.strip_edges())


func _resolve_prompt(warning_desc: String) -> String:
	if warning_desc.is_empty():
		return ""
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null or not pm.has_method("resolve_with_vars"):
		return ""
	if pm.has_method("has_prompt") and not pm.has_prompt(PROMPT_KEY):
		push_warning("[NpcRefusalCenter] missing prompt: %s" % PROMPT_KEY)
		return ""
	var mood_summary := _get_mood_summary()
	var resolved: String = str(pm.resolve_with_vars(PROMPT_KEY, {
		"warning_desc": warning_desc,
		"mood_summary": mood_summary,
	})).strip_edges()
	if resolved.is_empty() or resolved == PROMPT_KEY:
		return ""
	return resolved


func _get_mood_summary() -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("get_mood_summary"):
		return ""
	return str(gm.get_mood_summary()).strip_edges()


func _store_local_fallback(fallback_text: String) -> bool:
	var clean := fallback_text.strip_edges()
	if clean.is_empty():
		return false
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("store_npc_message"):
		return false
	chat.store_npc_message(DM_CHANNEL_ID, NPC_ID, clean)
	return false
