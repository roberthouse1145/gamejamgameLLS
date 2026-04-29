extends Node
## GameManager Autoload
## 管理全局游戏状态：林夏三维数值、项目四维数值、玩家金钱等
## 被 GameLoopManager 的动作消耗、夜间结算等环节读写

const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")

# =============================================================================
# Signals
# =============================================================================

signal stats_changed() ## 任何数值变化时触发（UI 刷新用）
signal affection_changed(old_val: int, new_val: int)
signal stress_changed(old_val: int, new_val: int)
signal passion_changed(old_val: int, new_val: int)
signal money_changed(old_val: int, new_val: int)
signal completion_changed(old_val: int, new_val: int)
signal quality_changed(old_val: int, new_val: int)
signal stability_changed(old_val: int, new_val: int)
signal hype_changed(old_val: int, new_val: int)
signal milestone_failed(day: int, required: int, actual: int)

# =============================================================================
# Constants
# =============================================================================

## 数值上下限
const STAT_MIN: int = 0
const STAT_MAX: int = 100

## 初始数值 — 林夏三维
const DEFAULT_AFFECTION: int = 100
const DEFAULT_STRESS: int = 10
const DEFAULT_PASSION: int = 100
const DEFAULT_MONEY: int = 500

## 初始数值 — 项目四维
const DEFAULT_COMPLETION: int = 0
const DEFAULT_QUALITY: int = 0
const DEFAULT_STABILITY: int = 0
const DEFAULT_HYPE: int = 0

## 里程碑完成度阈值: {day: required_completion}
const MILESTONE_THRESHOLDS: Dictionary = {
	15: 20,
	30: 50,
	45: 80,
}
const STRESS_DANGER_THRESHOLD: int = 80
const PASSION_DANGER_THRESHOLD: int = 20
const STATUS_WARNING_CHANNEL_ID: String = "dm_lin_xia"

# =============================================================================
# State Variables — 林夏三维
# =============================================================================

## 好感度 (0-100): 约会/聊天提升，过度派工降低
var affection: int = DEFAULT_AFFECTION:
	set(v):
		var old := affection
		affection = clampi(v, STAT_MIN, STAT_MAX)
		if old != affection:
			affection_changed.emit(old, affection)
			stats_changed.emit()

## 压力值 (0-100): 派发工单增加，约会/休息降低。过高会触发特殊剧情
var stress: int = DEFAULT_STRESS:
	set(v):
		var old := stress
		stress = clampi(v, STAT_MIN, STAT_MAX)
		if old != stress:
			stress_changed.emit(old, stress)
			stats_changed.emit()

## 激情值 (0-100): 好的设计讨论提升，重复工作/压力过高降低
var passion: int = DEFAULT_PASSION:
	set(v):
		var old := passion
		passion = clampi(v, STAT_MIN, STAT_MAX)
		if old != passion:
			passion_changed.emit(old, passion)
			stats_changed.emit()

# =============================================================================
# State Variables — 项目四维
# =============================================================================

## 完成度 (0-100): 任何工作都会增加，里程碑检查用
var completion: int = DEFAULT_COMPLETION:
	set(v):
		var old := completion
		completion = clampi(v, STAT_MIN, STAT_MAX)
		if old != completion:
			completion_changed.emit(old, completion)
			stats_changed.emit()

## 质量 (0-100): 通过开发工作中的"质量类"任务提升
var quality: int = DEFAULT_QUALITY:
	set(v):
		var old := quality
		quality = clampi(v, STAT_MIN, STAT_MAX)
		if old != quality:
			quality_changed.emit(old, quality)
			stats_changed.emit()

## 稳定性 (0-100): 通过开发工作中的"稳定类"任务提升
var stability: int = DEFAULT_STABILITY:
	set(v):
		var old := stability
		stability = clampi(v, STAT_MIN, STAT_MAX)
		if old != stability:
			stability_changed.emit(old, stability)
			stats_changed.emit()

## 热度 (0-100): 通过浏览器互联网活动提升
var hype: int = DEFAULT_HYPE:
	set(v):
		var old := hype
		hype = clampi(v, STAT_MIN, STAT_MAX)
		if old != hype:
			hype_changed.emit(old, hype)
			stats_changed.emit()

# =============================================================================
# State Variables — 其他
# =============================================================================

## 玩家零花钱（打工赚取，约会消耗）
var money: int = DEFAULT_MONEY:
	set(v):
		var old := money
		money = max(0, v)
		if old != money:
			money_changed.emit(old, money)
			stats_changed.emit()

## 累计完成的工单数
var completed_orders_count: int = 0

## 累计约会次数（用于触发里程碑事件）
var total_dates: int = 0

## 向后兼容: game_completion 映射到 completion (0.0~1.0 → 0~100)
var game_completion: float:
	get: return float(completion) / 100.0
	set(v): completion = roundi(clampf(v, 0.0, 1.0) * 100.0)

# =============================================================================
# Autoload references
# =============================================================================

var _game_loop: Node = null
var _work_order_manager: Node = null
var _chat_manager: Node = null
var _story_director: Node = null
var _status_warning_eval_queued: bool = false
var _status_warning_checks_suppressed: bool = true
var _pending_status_warning_type: String = ""
var _last_status_warning_type_sent: String = ""

@export var auto_request_status_warning_reply: bool = true

func _ready() -> void:
	call_deferred("_init_connections")
	print("[GameManager] Initialized. 好感:%d 压力:%d 激情:%d 金钱:%d | 完成:%d 质量:%d 稳定:%d 热度:%d" % [
		affection, stress, passion, money, completion, quality, stability, hype
	])


func _init_connections() -> void:
	_game_loop = get_node_or_null("/root/GameLoopManager")
	_work_order_manager = get_node_or_null("/root/WorkOrderManager")
	_chat_manager = get_node_or_null("/root/ChatManager")
	_story_director = get_node_or_null("/root/StoryDirector")

	if _work_order_manager and _work_order_manager.has_signal("order_status_changed"):
		_work_order_manager.order_status_changed.connect(_on_order_completed)

	if _game_loop and _game_loop.has_signal("milestone_reached"):
		_game_loop.milestone_reached.connect(_on_milestone_reached)
	if _game_loop and _game_loop.has_signal("day_changed"):
		_game_loop.day_changed.connect(_on_status_warning_timing_changed)
	if _game_loop and _game_loop.has_signal("phase_changed"):
		_game_loop.phase_changed.connect(_on_status_warning_timing_changed)
	if stress_changed.is_connected(_on_stress_changed) == false:
		stress_changed.connect(_on_stress_changed)
	if passion_changed.is_connected(_on_passion_changed) == false:
		passion_changed.connect(_on_passion_changed)
	if _chat_manager and _chat_manager.has_signal("topic_completed"):
		_chat_manager.topic_completed.connect(_on_chat_topic_released)
	if _chat_manager and _chat_manager.has_signal("topic_cancelled"):
		_chat_manager.topic_cancelled.connect(_on_chat_topic_cancelled)
	if _story_director and _story_director.has_signal("chapter_completed"):
		_story_director.chapter_completed.connect(_on_story_released)
	if _story_director and _story_director.has_signal("all_chapters_completed"):
		_story_director.all_chapters_completed.connect(_on_story_released)

	_status_warning_checks_suppressed = false
	_queue_status_warning_evaluation()

# =============================================================================
# Public API — 直接修改数值（供其他系统调用）
# =============================================================================

## 统一修改接口
func modify_stat(stat_name: String, delta: int) -> void:
	match stat_name:
		"affection": affection += delta
		"stress": stress += delta
		"passion": passion += delta
		"money": money += delta
		"completion": completion += delta
		"quality": quality += delta
		"stability": stability += delta
		"hype": hype += delta
		_: push_warning("[GameManager] Unknown stat: %s" % stat_name)

## 批量修改（一次修改多个数值）
func modify_stats(changes: Dictionary) -> void:
	for key in changes:
		modify_stat(str(key), int(changes[key]))

## 每日重置（由 GameLoopManager 调用）
func on_new_day() -> void:
	# 高压力每天自动降低少量激情
	if stress > 70:
		passion -= 3
	# 自然压力恢复（每天稍微降一点）
	if stress > 0:
		stress -= 2

## 里程碑检查
func check_milestone(day: int) -> bool:
	if not MILESTONE_THRESHOLDS.has(day):
		return true
	var required: int = MILESTONE_THRESHOLDS[day]
	if completion >= required:
		print("[GameManager] Milestone Day %d PASSED: completion %d >= %d" % [day, completion, required])
		return true
	print("[GameManager] Milestone Day %d FAILED: completion %d < %d" % [day, completion, required])
	milestone_failed.emit(day, required, completion)
	return false

# =============================================================================
# Mood / LLM Prompt
# =============================================================================

## 获取林夏的情绪描述（供 LLM prompt 注入）
func get_mood_summary() -> String:
	var mood: String = ""
	if stress >= 80: mood = "非常焦虑，接近崩溃"
	elif stress >= 60: mood = "压力很大，有些烦躁"
	elif stress >= 40: mood = "有点疲惫但还在坚持"
	elif stress >= 20: mood = "状态不错"
	else: mood = "心情很好，轻松愉快"

	var passion_desc: String = ""
	if passion >= 80: passion_desc = "创作热情高涨"
	elif passion >= 50: passion_desc = "有一定创作兴趣"
	elif passion >= 20: passion_desc = "有些提不起劲"
	else: passion_desc = "对项目感到倦怠"

	return "林夏当前状态: 好感度 %d/100, 压力 %d/100, 激情 %d/100。情绪: %s。%s。" % [
		affection, stress, passion, mood, passion_desc
	]


func get_llm_state_prompt() -> String:
	return """## 林夏当前内心状态与属性（非常重要）
作为LLM，你必须将以下这些属性**融合在一起**来塑造林夏的反应，而不是孤立地看待它们。
例如：即使【压力极高】，如果【好感度也极高】，她表现出的绝不是对玩家的攻击性，而是极度的脆弱、向玩家哭诉求安慰；
又例如：如果【没钱】但【好感高】，她会跟你半撒娇地诉苦，而不是冷冰冰地指责。
请像调色板一样将以下状态混合，计算出一个整体的情绪色彩：

%s
%s
%s
%s
%s
""" % [
		_describe_relationship(),
		_describe_stress_prompt(),
		_describe_passion_prompt(),
		_describe_money_prompt(),
		_describe_project_progress_prompt()
	]


func _describe_relationship() -> String:
	if affection >= 85:
		return "- 【核心羁绊】亲密度 %d/100（极高）：热恋且极度依赖。不论她此时多有压力或多缺钱，底色都是爱你的。她会对你撒娇，哪怕发脾气也是想让你哄，遇到困难第一反应是抱紧你。" % affection
	if affection >= 65:
		return "- 【核心羁绊】亲密度 %d/100（高）：感情很好且有默契。大部分时候相处自然，把你当自己人，吐槽也是透着亲昵的。" % affection
	if affection >= 45:
		return "- 【核心羁绊】亲密度 %d/100（中）：普通的交往状态。态度温和但有些收敛，在压力大时可能顾不上关心你。" % affection
	if affection >= 25:
		return "- 【核心羁绊】亲密度 %d/100（低）：关系处于冷战边缘。她对你很有防备，说话客气生硬。此时如果压力大或没钱，她可能会直接把火撒在你身上，或者表现出明显的失望。" % affection
	return "- 【核心羁绊】亲密度 %d/100（很低）：严重危机。她现在极度失望，态度冷漠抗拒。哪怕别的属性再好，她也不想给你好脸色。" % affection


func _describe_stress_prompt() -> String:
	if stress >= 80:
		return "- 【当前压力】%d/100（极高）：处于崩溃和极度疲惫状态。她像被抽干了所有精力，**不可能表现出任何元气、活泼或开心**。高亲密下她极度脆弱、疯狂向你撒娇喊累（例如“呜呜好累站不起来了”、“真的要去吗我不想动…”）；低亲密下是易怒的火药桶，对任何要求都很不耐烦。" % stress
	if stress >= 60:
		return "- 【当前压力】%d/100（高）：明显焦虑疲惫。精神状态不佳，经常叹气，容易烦躁。此时她非常需要你来分担工作或者哄她放松，不会像平时那样活跃。" % stress
	if stress >= 40:
		return "- 【当前压力】%d/100（中等）：能感觉到压力但不致命。工作时偏严肃，偶尔流露疲惫，但还能理智沟通。" % stress
	if stress >= 20:
		return "- 【当前压力】%d/100（低）：状态还算轻松。情绪稳定，理智且有耐心应对一切。" % stress
	return "- 【当前压力】%d/100（很低）：完全没有任何压力。心情大好，思维活跃，充满活力。" % stress


func _describe_passion_prompt() -> String:
	if passion >= 80:
		return "- 【创作热情】%d/100（极高）：对你们的游戏极度兴奋，像打了鸡血，满脑子都是好点子和表达欲。" % passion
	if passion >= 50:
		return "- 【创作热情】%d/100（较高）：态度积极，很愿意深入探讨游戏细节，对项目有信心。" % passion
	if passion >= 20:
		return "- 【创作热情】%d/100（低迷）：对项目开始怀疑，讨论时兴致缺缺敷衍了事。如果此时压力也很大，她会把做这游戏当成纯粹的折磨。" % passion
	return "- 【创作热情】%d/100（很低）：极其厌恶当前的项目，极度消极且回避所有干活的提议。" % passion


func _describe_money_prompt() -> String:
	if money >= 1200:
		return "- 【团队资金】%d 元（富裕）：算是小富婆状态。完全不担心钱，爽快答应各种消费提议。" % money
	if money >= 500:
		return "- 【团队资金】%d 元（一般）：日常够用，但遇到大额开销会犹豫。" % money
	if money >= 200:
		return "- 【团队资金】%d 元（紧张）：觉得穷了。会变得精打细算，根据好感度她可能会温柔提醒你省点花，或者刻薄地吐槽你乱花钱。" % money
	return "- 【团队资金】%d 元（吃土）：极度缺钱。经常为此焦虑，暗示或明示需要搞点钱，严重影响她的安全感。" % money


func _describe_project_progress_prompt() -> String:
	if completion >= 80:
		return "【项目进度】：即将大功告成（完成度%d%%，质量%d，稳定%d，热度%d）。她可能在纠结收尾细节，或憧憬发布后的成功。" % [completion, quality, stability, hype]
	if completion >= 50:
		return "【项目进度】：开发中局（完成度%d%%，质量%d，稳定%d，热度%d）。游戏能看出大概，正在攻坚具体的实现。" % [completion, quality, stability, hype]
	if completion >= 20:
		return "【项目进度】：刚起步没多久（完成度%d%%，质量%d，稳定%d，热度%d）。还在搭框架、讨论概念方向的阶段。" % [completion, quality, stability, hype]
	return "【项目进度】：一张白纸（完成度%d%%，质量%d，稳定%d，热度%d）。基本上啥也没做，只有初步的想法。" % [completion, quality, stability, hype]

# =============================================================================
# Event Handlers
# =============================================================================

## 工单完成时更新完成度
func _on_order_completed(_order_id: String, _old_status: String, new_status: String) -> void:
	if new_status == "completed":
		completed_orders_count += 1
		completion += 7
		passion += 5
		affection += 2

## 里程碑到达时检查完成度
func _on_milestone_reached(day: int) -> void:
	if not check_milestone(day):
		var glm: Node = get_node_or_null("/root/GameLoopManager")
		if glm != null and glm.has_signal("game_over"):
			print("[GameManager] 里程碑未达标，触发游戏结束")
			glm.game_over.emit()


func _on_stress_changed(_old_val: int, _new_val: int) -> void:
	_queue_status_warning_evaluation()


func _on_passion_changed(_old_val: int, _new_val: int) -> void:
	_queue_status_warning_evaluation()


func _on_status_warning_timing_changed(_value: Variant = null) -> void:
	_queue_status_warning_evaluation()


func _on_chat_topic_released(_topic: Resource, _result: Dictionary) -> void:
	_queue_status_warning_evaluation()


func _on_chat_topic_cancelled(_topic: Resource, _reason: String) -> void:
	_queue_status_warning_evaluation()


func _on_story_released(_value: Variant = null) -> void:
	_queue_status_warning_evaluation()


func _queue_status_warning_evaluation() -> void:
	if _status_warning_checks_suppressed or _status_warning_eval_queued:
		return
	_status_warning_eval_queued = true
	call_deferred("_evaluate_status_warning_state")


func _evaluate_status_warning_state() -> void:
	_status_warning_eval_queued = false
	if _status_warning_checks_suppressed:
		return

	var warning_type := _get_current_status_warning_type()
	if warning_type.is_empty():
		_pending_status_warning_type = ""
		_last_status_warning_type_sent = ""
		return

	if warning_type == _last_status_warning_type_sent and _pending_status_warning_type.is_empty():
		return

	if not _can_trigger_status_warning_topic():
		_pending_status_warning_type = warning_type
		return

	if _trigger_status_warning_topic(warning_type):
		_last_status_warning_type_sent = warning_type
		_pending_status_warning_type = ""


func _get_current_status_warning_type() -> String:
	var stress_danger := stress >= STRESS_DANGER_THRESHOLD
	var passion_danger := passion <= PASSION_DANGER_THRESHOLD
	if stress_danger and passion_danger:
		return "both"
	if stress_danger:
		return "stress"
	if passion_danger:
		return "passion"
	return ""


func _can_trigger_status_warning_topic() -> bool:
	if not _is_free_period_for_status_warning():
		return false
	if _chat_manager == null:
		_chat_manager = get_node_or_null("/root/ChatManager")
	if _chat_manager == null:
		return false
	if _chat_manager.has_method("has_active_topic") and _chat_manager.has_active_topic(STATUS_WARNING_CHANNEL_ID):
		return false
	return true


func _is_free_period_for_status_warning() -> bool:
	return ActivityLockUtilsClass.is_free_period()


func _trigger_status_warning_topic(warning_type: String) -> bool:
	if _chat_manager == null:
		return false

	var topic := ChatTopicClass.new()
	topic.topic_id = "status_warning_%s_%d" % [warning_type, int(Time.get_unix_time_from_system())]
	topic.topic_type = "casual_interaction"
	topic.display_title = "林夏有点撑不住了"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = STATUS_WARNING_CHANNEL_ID
	topic.system_prompt = _build_status_warning_prompt(warning_type)
	topic.goal_description = "提醒玩家当前开发安排已经让林夏进入危险状态"
	topic.context_data = {
		"linkchat_open_mode": "force",
		"complete_after_first_reply": true,
		"suppress_system_notice": true,
		"status_warning_type": warning_type,
		"free_period_warning": true,
	}
	topic.timeout_seconds = 0

	if not _chat_manager.activate_topic(topic):
		return false

	if auto_request_status_warning_reply and _chat_manager.has_method("request_topic_npc_reply"):
		_chat_manager.request_topic_npc_reply(topic.channel_id, "", false, true)
	return true


func _build_status_warning_prompt(warning_type: String) -> String:
	var warning_desc := ""
	match warning_type:
		"stress":
			warning_desc = "你的压力已经高到危险值了。你想认真提醒搭档，别再一直安排开发了，你真的有点扛不住。"
		"passion":
			warning_desc = "你的创作激情已经掉到危险值了。你想提醒搭档，再这样一直开发下去，你会越来越提不起劲。"
		"both":
			warning_desc = "你的压力和创作激情都到了危险值。你既累又没劲，真的需要搭档意识到问题，别再一味推进开发。"
		_:
			warning_desc = "你现在的状态很危险，需要提醒搭档先缓一缓。"

	var mood_summary := get_mood_summary()
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_method("resolve_with_vars"):
		if pm.has_prompt("linkchat_status_warning"):
			var resolved := str(pm.resolve_with_vars("linkchat_status_warning", {
				"warning_desc": warning_desc,
				"mood_summary": mood_summary,
			})).strip_edges()
			if not resolved.is_empty():
				return resolved

	return """你是林夏，现在是在 LinkChat 私聊里主动找搭档说话。
这不是剧情强制事件，而是自由时段里的状态提醒。

【提醒原因】
%s

【当前状态】
%s

【要求】
- 主动发送 1-2 条短消息，像平时聊天一样自然
- 语气要像真实的抱怨和提醒，不要像系统公告
- 重点是让玩家意识到：继续一味开发，会让你更难受
- 可以表达累、烦、没灵感、想休息、想换换脑子，但不要直接替玩家做完整规划
- 不要开启新工单，不要谈底层工具，不要写成长篇分析
- 最后一条消息末尾必须加 [TOPIC_COMPLETE]""" % [warning_desc, mood_summary]

# =============================================================================
# Persistence (save/load)
# =============================================================================

func to_dict() -> Dictionary:
	return {
		"affection": affection,
		"stress": stress,
		"passion": passion,
		"money": money,
		"completion": completion,
		"quality": quality,
		"stability": stability,
		"hype": hype,
		"completed_orders_count": completed_orders_count,
		"total_dates": total_dates,
	}

func from_dict(data: Dictionary) -> void:
	affection = data.get("affection", DEFAULT_AFFECTION)
	stress = data.get("stress", DEFAULT_STRESS)
	passion = data.get("passion", DEFAULT_PASSION)
	money = data.get("money", DEFAULT_MONEY)
	completion = data.get("completion", DEFAULT_COMPLETION)
	quality = data.get("quality", DEFAULT_QUALITY)
	stability = data.get("stability", DEFAULT_STABILITY)
	hype = data.get("hype", DEFAULT_HYPE)
	completed_orders_count = data.get("completed_orders_count", 0)
	total_dates = data.get("total_dates", 0)


func get_run_state() -> Dictionary:
	return to_dict()


func load_run_state(data: Dictionary) -> bool:
	_status_warning_checks_suppressed = true
	from_dict(data)
	_pending_status_warning_type = ""
	_last_status_warning_type_sent = ""
	_status_warning_eval_queued = false
	_status_warning_checks_suppressed = false
	return true


func reset_runtime_state() -> void:
	_status_warning_checks_suppressed = true
	from_dict({})
	_pending_status_warning_type = ""
	_last_status_warning_type_sent = ""
	_status_warning_eval_queued = false
	_status_warning_checks_suppressed = false
