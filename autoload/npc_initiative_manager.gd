extends Node

# =============================================================================
# NpcInitiativeManager — 林夏主动邀约系统
#
# 在自由时段中，由代码侧选择一个合法活动，通过 LinkChat Topic 邀请玩家。
# 玩家接受  → [TOPIC_COMPLETE] → 跳过 departure 直接进入 progress
# 玩家拒绝  → [TOPIC_FAILED]  → 回到自由时段
# =============================================================================

signal initiative_sent(initiative: Dictionary)
signal initiative_accepted(initiative: Dictionary)
signal initiative_declined(initiative: Dictionary)

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const ActivityUtilsClass = preload("res://scripts/activity/activity_utils.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")

const DM_CHANNEL_ID: String = "dm_lin_xia"
const NPC_ID: String = "npc_lin_xia"
const TOPIC_STAGE_KEY: String = "npc_initiative_stage"
const PROMPT_KEY: String = "npc_initiative_invite"

## 每天最多主动邀约次数
const MAX_INITIATIVES_PER_DAY: int = 1
## 基础触发概率 (0.0 ~ 1.0)
const BASE_TRIGGER_CHANCE: float = 0.35
## Topic 超时秒数
const INITIATIVE_TOPIC_TIMEOUT: int = 180

## 调试模式：设为 true 时 100% 触发、无冷却、无次数限制
var debug_force_trigger: bool = false

var _active_initiative: Dictionary = {}
var _initiatives_today: int = 0
var _last_initiative_day: int = -1
var _cooldown_phases: int = 0


func _ready() -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		if glm.has_signal("phase_changed"):
			glm.phase_changed.connect(_on_phase_changed)
		if glm.has_signal("day_changed"):
			glm.day_changed.connect(_on_day_changed)

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null:
		if chat.has_signal("topic_completed"):
			chat.topic_completed.connect(_on_topic_completed)
		if chat.has_signal("topic_cancelled"):
			chat.topic_cancelled.connect(_on_topic_cancelled)


# =============================================================================
# Public API
# =============================================================================

func has_active_initiative() -> bool:
	return not _active_initiative.is_empty()


func get_run_state() -> Dictionary:
	return {
		"initiatives_today": _initiatives_today,
		"last_initiative_day": _last_initiative_day,
		"cooldown_phases": _cooldown_phases,
	}


func load_run_state(data: Dictionary) -> bool:
	_initiatives_today = int(data.get("initiatives_today", 0))
	_last_initiative_day = int(data.get("last_initiative_day", -1))
	_cooldown_phases = int(data.get("cooldown_phases", 0))
	_active_initiative.clear()
	return true


func reset_runtime_state() -> void:
	_active_initiative.clear()
	_initiatives_today = 0
	_last_initiative_day = -1
	_cooldown_phases = 0


# =============================================================================
# Trigger Evaluation
# =============================================================================

func _on_phase_changed(_new_phase) -> void:
	if not debug_force_trigger and _cooldown_phases > 0:
		_cooldown_phases -= 1
		return
	if debug_force_trigger:
		_cooldown_phases = 0
	# 延迟评估，等其他系统完成状态更新
	call_deferred("_evaluate_initiative")


func _on_day_changed(new_day: int) -> void:
	if new_day != _last_initiative_day:
		_initiatives_today = 0
		_last_initiative_day = new_day


func _evaluate_initiative() -> void:
	if not _active_initiative.is_empty():
		return
	if not _can_trigger():
		return

	var candidate: Dictionary = _select_activity()
	if candidate.is_empty():
		return

	# 概率性跳过，体现角色自主性
	if randf() > _compute_trigger_chance():
		return

	_send_initiative(candidate)


func _can_trigger() -> bool:
	if not debug_force_trigger and _initiatives_today >= MAX_INITIATIVES_PER_DAY:
		return false
	if not ActivityLockUtilsClass.is_free_period():
		return false
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null or not glm.can_consume_ap(1):
		return false
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.has_method("has_active_topic") and chat.has_active_topic(DM_CHANNEL_ID):
		return false
	return true


func _compute_trigger_chance() -> float:
	if debug_force_trigger:
		return 1.0
	var chance: float = BASE_TRIGGER_CHANCE
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return chance
	# 高好感度提高主动性
	if int(gm.affection) >= 60:
		chance += 0.15
	# 高压力降低主动性
	if int(gm.stress) >= 60:
		chance -= 0.15
	return clampf(chance, 0.1, 0.7)


# =============================================================================
# Activity Selection (纯代码逻辑)
# =============================================================================

func _select_activity() -> Dictionary:
	var candidates: Array[Dictionary] = []
	_collect_date_candidates(candidates)
	_collect_sbeam_candidates(candidates)
	_collect_part_time_candidates(candidates)

	if candidates.is_empty():
		return {}

	return _weighted_pick(candidates)


func _collect_date_candidates(candidates: Array[Dictionary]) -> void:
	if not ActivityLockUtilsClass.get_narrative_blocking_reason("date").is_empty():
		return
	var dm: Node = get_node_or_null("/root/DateManager")
	if dm == null or not dm.has_method("get_available_events"):
		return
	var events: Array = dm.get_available_events()
	for evt in events:
		if not bool(evt.get("enabled", false)):
			continue
		candidates.append({
			"activity_type": "date",
			"entry_id": str(evt.get("event_id", evt.get("location_id", ""))),
			"title": str(evt.get("title", evt.get("location_title", "约会"))),
			"summary": str(evt.get("description", "")).left(60),
			"weight": _date_weight(),
		})


func _collect_sbeam_candidates(candidates: Array[Dictionary]) -> void:
	if not ActivityLockUtilsClass.get_narrative_blocking_reason("sbeam").is_empty():
		return
	var sm: Node = get_node_or_null("/root/SbeamManager")
	if sm == null or not sm.has_method("get_catalog"):
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	var catalog: Array = sm.get_catalog()
	for game_entry in catalog:
		if bool(game_entry.get("is_owned", false)):
			continue
		var price: int = int(game_entry.get("price", 0))
		if gm != null and int(gm.money) < price:
			continue
		var summary_parts: Array[String] = []
		var genre: String = str(game_entry.get("genre", "")).strip_edges()
		if not genre.is_empty():
			summary_parts.append("类型：%s" % genre)
		summary_parts.append("价格：¥%d" % price)
		var pitch: String = str(game_entry.get("pitch", "")).strip_edges()
		if not pitch.is_empty():
			summary_parts.append("简介：%s" % pitch)
		var hook_moment: String = str(game_entry.get("hook_moment", "")).strip_edges()
		if not hook_moment.is_empty():
			summary_parts.append("看点：%s" % hook_moment)
		candidates.append({
			"activity_type": "sbeam",
			"entry_id": str(game_entry.get("game_id", "")),
			"title": str(game_entry.get("title", "游戏")),
			"summary": "；".join(summary_parts),
			"weight": _sbeam_weight(),
		})


func _collect_part_time_candidates(candidates: Array[Dictionary]) -> void:
	if not ActivityLockUtilsClass.get_narrative_blocking_reason("part_time").is_empty():
		return
	var ptm: Node = get_node_or_null("/root/PartTimeJobManager")
	if ptm == null or not ptm.has_method("get_catalog"):
		return
	var catalog: Array = ptm.get_catalog()
	for job in catalog:
		var valid_phases: Array = job.get("valid_phases", [])
		if not valid_phases.is_empty():
			var current_phase: String = ActivityUtilsClass.get_phase_name()
			if not valid_phases.has(current_phase):
				continue
		candidates.append({
			"activity_type": "part_time",
			"entry_id": str(job.get("job_id", "")),
			"title": str(job.get("job_title", "兼职")),
			"summary": str(job.get("subtitle", "")).left(60),
			"weight": _part_time_weight(),
		})


func _date_weight() -> float:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return 1.0
	# 高好感更倾向约会
	if int(gm.affection) >= 50:
		return 2.0
	return 1.0


func _sbeam_weight() -> float:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return 1.0
	# 压力大时更想一起放松
	if int(gm.stress) >= 50:
		return 1.5
	return 1.0


func _part_time_weight() -> float:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return 1.0
	# 缺钱时更倾向兼职
	if int(gm.money) < 200:
		return 2.0
	return 0.8


func _weighted_pick(candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total_weight: float = 0.0
	for c in candidates:
		total_weight += float(c.get("weight", 1.0))
	if total_weight <= 0.0:
		return candidates[randi() % candidates.size()]
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for c in candidates:
		cumulative += float(c.get("weight", 1.0))
		if roll <= cumulative:
			return c
	return candidates[candidates.size() - 1]


# =============================================================================
# Topic 发起
# =============================================================================

func _send_initiative(candidate: Dictionary) -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("activate_topic") or not chat.has_method("request_topic_npc_reply"):
		return

	_active_initiative = candidate.duplicate(true)
	_initiatives_today += 1

	var topic := ChatTopicClass.new()
	topic.topic_id = "npc_initiative_%s_%s" % [str(candidate.get("activity_type", "")), str(candidate.get("entry_id", ""))]
	topic.topic_type = "npc_initiative"
	topic.npc_id = NPC_ID
	topic.channel_id = DM_CHANNEL_ID
	topic.display_title = "邀约_%s" % str(candidate.get("title", ""))
	topic.system_prompt = _build_invite_prompt(candidate)
	topic.goal_description = "邀请玩家参加活动"
	topic.timeout_seconds = INITIATIVE_TOPIC_TIMEOUT
	topic.context_data = {
		TOPIC_STAGE_KEY: "invite",
		"npc_initiative": true,
		"activity_type": str(candidate.get("activity_type", "")),
		"entry_id": str(candidate.get("entry_id", "")),
		"suppress_system_notice": true,
	}

	if not chat.activate_topic(topic):
		_active_initiative.clear()
		_initiatives_today -= 1
		return

	var seed_msg: String = "这是开场邀请，玩家还没有回复。现在只发送邀请内容本身，不要输出 [TOPIC_COMPLETE] 或 [TOPIC_FAILED]。"
	if not chat.request_topic_npc_reply(DM_CHANNEL_ID, seed_msg, false, false):
		# 回收刚激活的 topic，避免留下卡死的活跃 Topic
		var topic_mgr: Variant = chat.get("topic_manager")
		if topic_mgr != null:
			var active_topic = chat.get_active_topic(DM_CHANNEL_ID) if chat.has_method("get_active_topic") else null
			if active_topic != null and active_topic.topic_id == topic.topic_id:
				topic_mgr.cancel_topic(active_topic, "initial_invite_request_failed")
		_active_initiative.clear()
		_initiatives_today -= 1
		return

	initiative_sent.emit(_active_initiative.duplicate(true))
	print("[NpcInitiativeManager] Initiative sent: %s -> %s" % [
		str(candidate.get("activity_type", "")),
		str(candidate.get("title", "")),
	])


func _build_invite_prompt(candidate: Dictionary) -> String:
	var activity_type: String = str(candidate.get("activity_type", ""))
	var title: String = str(candidate.get("title", ""))
	var summary: String = str(candidate.get("summary", ""))

	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("resolve_with_vars"):
		var vars_dict: Dictionary = {
			"initiative_activity_type": activity_type,
			"initiative_activity_type_label": _get_type_label(activity_type),
			"initiative_title": title,
			"initiative_summary": summary,
		}
		var resolved: String = str(pm.resolve_with_vars(PROMPT_KEY, vars_dict)).strip_edges()
		if not resolved.is_empty() and resolved != PROMPT_KEY:
			return resolved

	# Inline fallback prompt
	var type_label: String = _get_type_label(activity_type)
	return (
		"你是林夏。你想邀请玩家一起去%s——「%s」。\n"
		% [type_label, title]
		+ "%s\n" % summary
		+ "【严禁虚构事实】只能使用上方给出的标题、类型、价格、简介、看点等信息。"
		+ "不要臆造价格、折扣、免费、限免、销量、评分、获奖、开发商等上方没有给出的属性。"
		+ "尤其不要说游戏是“免费”、“限免”、“打折”、“促销”，除非上方字段里明确写了这些字样。\n"
		+ "当前这是邀约对话的第一轮开场消息，玩家还没有回复你。\n"
		+ "你现在只能发出邀请本身。用你平时的语气发一条自然的邀请消息，不超过两句话。\n"
		+ "在邀请正文之后，必须额外给出 2 条推荐回复，格式为单独两行 `> ...`：一条表示愿意去，一条表示不想去；都要短、自然、像玩家会点的按钮文案。\n"
		+ "在这第一条开场邀请里，绝对不要输出 [TOPIC_COMPLETE] 或 [TOPIC_FAILED]。\n"
		+ "不要假设玩家已经答应或拒绝，也不要替玩家做决定。\n"
		+ "只有在玩家明确回复之后，如果玩家同意，在你最后一条消息末尾加 [TOPIC_COMPLETE]。\n"
		+ "只有在玩家明确回复之后，如果玩家拒绝或婉拒，在你最后一条消息末尾加 [TOPIC_FAILED]。\n"
		+ "如果聊天历史里已经出现“系统: [玩家较长时间未回复]”，默认视为玩家对这次邀约没兴趣；自然收口，并在最后一条消息末尾加 [TOPIC_FAILED]。\n"
		+ "玩家沉默时，不要把同一个邀请换着说法重复推销。\n"
		+ "这两条推荐回复只在玩家第一次表态前提供；一旦玩家已经明确回复，就不要再重复输出开场推荐回复。"
	)


func _get_type_label(activity_type: String) -> String:
	match activity_type:
		"date":
			return "约会"
		"sbeam":
			return "玩游戏"
		"part_time":
			return "做兼职"
	return "做点什么"


# =============================================================================
# Topic 回调
# =============================================================================

func _on_topic_completed(topic, result: Dictionary) -> void:
	if topic == null:
		return
	var context: Dictionary = topic.context_data
	if not bool(context.get("npc_initiative", false)):
		return

	var topic_failed: bool = bool(result.get("topic_failed", false))
	var initiative: Dictionary = _active_initiative.duplicate(true)
	_active_initiative.clear()

	if initiative.is_empty():
		return

	if topic_failed:
		initiative_declined.emit(initiative)
		# 拒绝后增加冷却，下一时段不再邀约
		_cooldown_phases = 1
		print("[NpcInitiativeManager] Initiative declined: %s" % str(initiative.get("title", "")))
		return

	# 玩家接受邀约 → 启动对应活动 (skip_departure)
	var start_result: Dictionary = _start_accepted_activity(initiative)
	if not bool(start_result.get("success", false)):
		var err: String = str(start_result.get("error", "活动启动失败"))
		push_warning("[NpcInitiativeManager] Activity start failed after acceptance: %s" % err)
		initiative_declined.emit(initiative)
		_cooldown_phases = 1
		return

	initiative_accepted.emit(initiative)
	print("[NpcInitiativeManager] Initiative accepted: %s -> %s" % [
		str(initiative.get("activity_type", "")),
		str(initiative.get("title", "")),
	])


func _on_topic_cancelled(topic, _reason: String) -> void:
	if topic == null:
		return
	var context: Dictionary = topic.context_data
	if not bool(context.get("npc_initiative", false)):
		return

	var initiative: Dictionary = _active_initiative.duplicate(true)
	_active_initiative.clear()

	if not initiative.is_empty():
		initiative_declined.emit(initiative)
		_cooldown_phases = 1
		print("[NpcInitiativeManager] Initiative cancelled: %s" % str(initiative.get("title", "")))


func _start_accepted_activity(initiative: Dictionary) -> Dictionary:
	var activity_type: String = str(initiative.get("activity_type", ""))
	var entry_id: String = str(initiative.get("entry_id", ""))
	var result: Dictionary = {}

	match activity_type:
		"date":
			var dm: Node = get_node_or_null("/root/DateManager")
			if dm != null and dm.has_method("begin_date"):
				result = dm.begin_date(entry_id, 20.0, true)
		"sbeam":
			var sm: Node = get_node_or_null("/root/SbeamManager")
			if sm != null and sm.has_method("begin_play_session"):
				result = sm.begin_play_session(entry_id, true)
		"part_time":
			var ptm: Node = get_node_or_null("/root/PartTimeJobManager")
			if ptm != null and ptm.has_method("begin_part_time"):
				result = ptm.begin_part_time(entry_id, 20.0, true)
		_:
			push_warning("[NpcInitiativeManager] Unknown activity type: %s" % activity_type)
			return {"success": false, "error": "未知活动类型: %s" % activity_type}

	return result if result is Dictionary else {"success": false, "error": "Manager 不可用"}
