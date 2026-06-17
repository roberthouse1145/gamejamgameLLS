extends Node
## GameManager Autoload
## 管理全局游戏状态：林夏三维数值、项目四维数值、玩家金钱等
## 被 GameLoopManager 的动作消耗、夜间结算等环节读写
##
## 注：原"高压力/低热情自动唠叨"被动 status_warning 系统已删除。
## 数值危险状态的反馈完全交给玩家"主动行动"路径：
##   - 玩家点 dev_work / part_time / community.contest 时由 NpcRefusalCenter 触发林夏拒绝
##   - 压力 ≥ 85 时由 GameLoopManager → HomeActivityManager.begin_forced_rest() 强制接管时段

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

## 初始数值 — 林夏状态
## affection 保留为隐藏的剧情/兼容字段，不参与当前主数值平衡。
const DEFAULT_AFFECTION: int = 70
const DEFAULT_STRESS: int = 5
const DEFAULT_PASSION: int = 70
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

# =============================================================================
# State Variables — 林夏三维
# =============================================================================

## 隐藏关系基线 (0-100)：当前不参与主玩法平衡，仅供剧情 / LLM 语气使用。
var affection: int = DEFAULT_AFFECTION:
	set(v):
		var old := affection
		affection = clampi(v, STAT_MIN, STAT_MAX)
		if old != affection:
			affection_changed.emit(old, affection)
			stats_changed.emit()

## 压力值 (0-100)：dev_work/part_time/contest 增加，sleep/date 降低。
## stress ≥ 85 时由 GameLoopManager 触发 forced_rest。
var stress: int = DEFAULT_STRESS:
	set(v):
		var old := stress
		stress = clampi(v, STAT_MIN, STAT_MAX)
		if old != stress:
			stress_changed.emit(old, stress)
			stats_changed.emit()

## 创作热情 (0-100)：dev_work/part_time 消耗，sbeam/learn/date 补充。
## passion ≤ 20 时玩家点 dev_work 会被林夏拒绝。
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


func _ready() -> void:
	call_deferred("_init_connections")
	print("[GameManager] Initialized. 隐藏好感:%d 压力:%d 激情:%d 金钱:%d | 完成:%d 质量:%d 稳定:%d 热度:%d" % [
		affection, stress, passion, money, completion, quality, stability, hype
	])


func _init_connections() -> void:
	_game_loop = get_node_or_null("/root/GameLoopManager")
	_work_order_manager = get_node_or_null("/root/WorkOrderManager")

	if _work_order_manager and _work_order_manager.has_signal("order_status_changed"):
		_work_order_manager.order_status_changed.connect(_on_order_completed)

	if _game_loop and _game_loop.has_signal("milestone_reached"):
		_game_loop.milestone_reached.connect(_on_milestone_reached)

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
	# 主状态恢复改由玩家选择的行动负责，避免隐藏日结规则稀释策略感。
	pass

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

	return "林夏当前状态: 压力 %d/100, 创作热情 %d/100。情绪: %s。%s。" % [
		stress, passion, mood, passion_desc
	]


func get_llm_state_prompt() -> String:
	return """## 林夏当前内心状态与属性（非常重要）
作为LLM，你必须将以下这些属性**融合在一起**来塑造林夏的反应，而不是孤立地看待它们。
关系基线是隐藏剧情字段，用来维持她与玩家的相处底色；当前玩家主要经营的是压力、创作热情、金钱与项目状态。
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
		return "- 【隐藏关系基线】%d/100（极高）：两人关系很稳。压力、缺钱或低热情会改变她的当下语气，但不会让她突然否定这段关系。" % affection
	if affection >= 65:
		return "- 【隐藏关系基线】%d/100（稳定）：感情底色偏暖，互动自然。当前压力和热情比关系数值更能决定她此刻的状态。" % affection
	if affection >= 45:
		return "- 【隐藏关系基线】%d/100（普通）：关系稳定但不夸张。压力大时她会更疲惫、更收敛。" % affection
	if affection >= 25:
		return "- 【隐藏关系基线】%d/100（偏低）：关系有些疏离。除非剧情明确推进，否则不要把它写成分手危机。" % affection
	return "- 【隐藏关系基线】%d/100（很低）：关系底色偏冷，但仍应优先结合当前压力、热情、金钱和剧情上下文来写反应。" % affection


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
		return "- 【团队资金】%d 元（紧张）：觉得穷了。会变得精打细算，提醒玩家别把钱花到不必要的地方。" % money
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

## 里程碑到达时检查完成度
func _on_milestone_reached(day: int) -> void:
	if not check_milestone(day):
		var glm: Node = get_node_or_null("/root/GameLoopManager")
		if glm != null and glm.has_signal("game_over"):
			print("[GameManager] 里程碑未达标，触发游戏结束")
			glm.game_over.emit()

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
	from_dict(data)
	return true


func reset_runtime_state() -> void:
	from_dict({})
