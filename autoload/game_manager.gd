extends Node
## GameManager Autoload
## 管理全局游戏状态：林夏三维数值、项目四维数值、玩家金钱等
## 被 GameLoopManager 的动作消耗、夜间结算等环节读写

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
const DEFAULT_AFFECTION: int = 30
const DEFAULT_STRESS: int = 20
const DEFAULT_PASSION: int = 60
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

func _ready() -> void:
	call_deferred("_init_connections")
	print("[GameManager] Initialized. 好感:%d 压力:%d 激情:%d 金钱:%d | 完成:%d 质量:%d 稳定:%d 热度:%d" % [
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
	return "林夏和玩家当前的关系状态：%s 当前精神状态：%s 当前创作状态：%s 当前生活条件：%s 项目整体状态：%s" % [
		_describe_relationship(),
		_describe_stress_prompt(),
		_describe_passion_prompt(),
		_describe_money_prompt(),
		_describe_project_progress_prompt()
	]


func _describe_relationship() -> String:
	if affection >= 85:
		return "两人已经非常亲密，默契很强，很多话不用说透也能互相接住。"
	if affection >= 65:
		return "两人关系稳定亲近，相处自然，已经能在约会和创作之间找到舒服的节奏。"
	if affection >= 45:
		return "两人已经熟悉，也有明确好感，但偶尔还是会在表达和节奏上小心试探。"
	if affection >= 25:
		return "两人刚进入恋爱关系不久，彼此有好感，但还在摸索怎么更自然地相处。"
	return "两人虽然在交往，但关系还偏生涩，很多相处方式都没有真正稳定下来。"


func _describe_stress_prompt() -> String:
	if stress >= 80:
		return "她正处在很强的焦虑和消耗中，稍微一点压力都可能让她情绪绷紧。"
	if stress >= 60:
		return "她最近压力明显偏高，容易疲惫，也容易对比赛和进度变得敏感。"
	if stress >= 40:
		return "她有一些疲惫和压迫感，但还在努力维持状态，不至于立刻失控。"
	if stress >= 20:
		return "她整体状态还算稳定，虽然有比赛压力，但暂时还能正常消化。"
	return "她现在相当放松，精神上没有太重的负担。"


func _describe_passion_prompt() -> String:
	if passion >= 80:
		return "她对共同创作这件事很有冲劲，容易被新的点子和交流点燃。"
	if passion >= 50:
		return "她对项目仍然有稳定热情，只要节奏别太糟，状态就能维持住。"
	if passion >= 20:
		return "她还没有完全失去动力，但已经有点提不起劲，需要被带动。"
	return "她对项目明显有些倦，容易把创作当成负担而不是期待。"


func _describe_money_prompt() -> String:
	if money >= 1200:
		return "你们手头比较宽裕，普通外出和日常花销不会形成明显压力。"
	if money >= 500:
		return "你们的花销还算能撑住，但不会毫无顾忌地乱花。"
	if money >= 200:
		return "你们手头有点紧，外出和消费会下意识考虑成本。"
	return "你们手头相当拮据，很多约会和日常安排都会被花销影响。"


func _describe_project_progress_prompt() -> String:
	if completion >= 80:
		return "项目已经接近完成（完成度%d%%，质量%d，稳定%d，热度%d），主要压力来自收尾和最终呈现。" % [completion, quality, stability, hype]
	if completion >= 50:
		return "项目已经进入中后段（完成度%d%%，质量%d，稳定%d，热度%d），成果开始变得可见。" % [completion, quality, stability, hype]
	if completion >= 20:
		return "项目还在搭主体的阶段（完成度%d%%，质量%d，稳定%d，热度%d），方向逐渐清晰。" % [completion, quality, stability, hype]
	return "项目仍处在早期阶段（完成度%d%%，质量%d，稳定%d，热度%d），很多内容还只是雏形。" % [completion, quality, stability, hype]

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
