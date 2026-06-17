extends Node

enum TimePhase {
	MORNING,
	AFTERNOON,
	NIGHT,
}

enum ActionType {
	WORK_ORDER,
	DATE,
	PART_TIME,
	COMMUNITY,
	LIFE,
}

const ACTION_TYPE_MAP: Dictionary = {
	"work_order": ActionType.WORK_ORDER,
	"date": ActionType.DATE,
	"part_time": ActionType.PART_TIME,
	"community": ActionType.COMMUNITY,
	"life": ActionType.LIFE,
}

const MAX_DAYS: int = 45
const DEFAULT_MAX_AP: int = 1
const MILESTONE_DAYS: Array[int] = [15, 30, 45]

## 游戏起始日历日期：2027年5月5日（周一）
const START_YEAR: int = 2027
const START_MONTH: int = 5
const START_DAY: int = 5

var current_day: int = 1
var max_ap_per_day: int = DEFAULT_MAX_AP
var current_ap: int = DEFAULT_MAX_AP
var time_phase: TimePhase = TimePhase.MORNING

var _today_actions: Array[Dictionary] = []
var _forced_rest_queued: bool = false

signal day_changed(new_day: int)
signal ap_changed(current: int, max_ap: int)
signal phase_changed(new_phase: TimePhase)
signal milestone_reached(day: int)
signal ap_exhausted()
signal ap_consumed(action_type: String)
signal game_over()


func _ready() -> void:
	game_over.connect(_on_game_over)
	print("[GameLoopManager] Initialized. Day: %d, Action: %d/%d, Phase: %s" % [
		current_day, current_ap, max_ap_per_day, get_phase_name(time_phase)
	])


func consume_ap(amount: int, action_type: String = "", detail: String = "", label: String = "") -> bool:
	if amount <= 0:
		return false
	if _should_force_rest_before_action(action_type, detail):
		_request_forced_rest()
		return false
	if amount > max_ap_per_day:
		push_warning("[GameLoopManager] Amount exceeds phase action limit: %d" % amount)
		return false
	if current_ap < amount:
		push_warning("[GameLoopManager] No action slots left in this phase")
		return false

	var phase_before: TimePhase = time_phase
	current_ap -= amount

	_today_actions.append({
		"action_type": action_type,
		"detail": detail,
		"label": label,
		"day": current_day,
		"phase": get_phase_name(phase_before),
	})

	ap_consumed.emit(action_type)
	_log_action(action_type, detail)
	if action_type == "life" and detail == "forced_rest":
		_forced_rest_queued = false

	if current_ap <= 0:
		ap_exhausted.emit()
		call_deferred("_advance_phase", current_day, phase_before)

	ap_changed.emit(current_ap, max_ap_per_day)
	return true


func _advance_phase(expected_day: int = -1, expected_phase: int = -1) -> void:
	if _is_stale_phase_advance(expected_day, expected_phase):
		print("[GameLoopManager] Skip stale phase advance for Day %d / %s" % [
			expected_day,
			get_phase_name(expected_phase as TimePhase) if expected_phase >= 0 else "UNKNOWN",
		])
		return

	match time_phase:
		TimePhase.MORNING:
			time_phase = TimePhase.AFTERNOON
			current_ap = max_ap_per_day
			phase_changed.emit(time_phase)
			ap_changed.emit(current_ap, max_ap_per_day)
			print("[GameLoopManager] Phase advanced: MORNING -> AFTERNOON")
			call_deferred("_request_forced_rest_if_needed")
		TimePhase.AFTERNOON:
			time_phase = TimePhase.NIGHT
			current_ap = max_ap_per_day
			phase_changed.emit(time_phase)
			ap_changed.emit(current_ap, max_ap_per_day)
			print("[GameLoopManager] Phase advanced: AFTERNOON -> NIGHT")
			call_deferred("_request_forced_rest_if_needed")
		TimePhase.NIGHT:
			print("[GameLoopManager] Day %d complete — advancing to next day" % current_day)
			# 给玩家 1 秒阅读当晚行动反馈的时间，再切换日期
			await get_tree().create_timer(1.0).timeout
			if _is_stale_phase_advance(expected_day, expected_phase):
				print("[GameLoopManager] Skip stale next-day advance for Day %d / NIGHT" % expected_day)
				return
			advance_to_next_day()


func _is_stale_phase_advance(expected_day: int, expected_phase: int) -> bool:
	if expected_day > 0 and current_day != expected_day:
		return true
	if expected_phase >= 0 and int(time_phase) != expected_phase:
		return true
	return false


func set_day(day: int) -> void:
	var target_day: int = clampi(day, 1, MAX_DAYS)
	if current_day == target_day:
		return

	current_day = target_day
	current_ap = max_ap_per_day
	_today_actions.clear()
	_forced_rest_queued = false

	print("[GameLoopManager] ==== Set Day %d ====" % current_day)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("on_new_day"):
		gm.on_new_day()

	day_changed.emit(current_day)
	ap_changed.emit(current_ap, max_ap_per_day)
	_check_milestones()


func advance_to_next_day() -> void:
	if current_day >= MAX_DAYS:
		print("[GameLoopManager] Reached final day: %d" % MAX_DAYS)
		game_over.emit()
		return

	current_day += 1
	current_ap = max_ap_per_day
	time_phase = TimePhase.MORNING
	_today_actions.clear()
	_forced_rest_queued = false

	print("[GameLoopManager] ==== Enter Day %d ====" % current_day)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("on_new_day"):
		gm.on_new_day()

	day_changed.emit(current_day)
	ap_changed.emit(current_ap, max_ap_per_day)
	phase_changed.emit(time_phase)
	_check_milestones()


func can_consume_ap(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	if _should_force_rest_before_action("", ""):
		_request_forced_rest()
		return false
	return current_ap >= amount


func has_remaining_ap() -> bool:
	return current_ap > 0


func _check_milestones() -> void:
	if current_day in MILESTONE_DAYS:
		print("[GameLoopManager] Milestone reached: Day %d" % current_day)
		milestone_reached.emit(current_day)


func _on_game_over() -> void:
	print("[GameLoopManager] ===== 游戏结束 =====")
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		print("[GameLoopManager] 最终数值 — 完成度:%d 质量:%d 稳定:%d 热度:%d" % [
			int(gm.get("completion")),
			int(gm.get("quality")),
			int(gm.get("stability")),
			int(gm.get("hype")),
		])
	print("[GameLoopManager] Day: %d / %d" % [current_day, MAX_DAYS])


func _log_action(action_type: String, detail: String) -> void:
	var action_enum: int = ACTION_TYPE_MAP.get(action_type, -1)
	match action_enum:
		ActionType.WORK_ORDER:
			print("[GameLoopManager] > Work order: %s" % detail)
		ActionType.DATE:
			print("[GameLoopManager] > Date: %s" % detail)
		ActionType.PART_TIME:
			print("[GameLoopManager] > Part-time: %s" % detail)
		ActionType.COMMUNITY:
			print("[GameLoopManager] > Community: %s" % detail)
		ActionType.LIFE:
			print("[GameLoopManager] > Life: %s" % detail)
		_:
			print("[GameLoopManager] > Action: %s" % action_type)


func get_phase_name(phase: TimePhase) -> String:
	match phase:
		TimePhase.MORNING:
			return "MORNING"
		TimePhase.AFTERNOON:
			return "AFTERNOON"
		TimePhase.NIGHT:
			return "NIGHT"
	return "UNKNOWN"


func get_phase_display_name(phase: TimePhase) -> String:
	match phase:
		TimePhase.MORNING:
			return "上午"
		TimePhase.AFTERNOON:
			return "下午"
		TimePhase.NIGHT:
			return "晚上"
	return "未知"


func get_today_actions() -> Array[Dictionary]:
	return _today_actions


func get_run_state() -> Dictionary:
	return {
		"current_day": current_day,
		"max_ap_per_day": max_ap_per_day,
		"current_ap": current_ap,
		"time_phase": int(time_phase),
		"today_actions": _today_actions.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	current_day = max(1, int(data.get("current_day", 1)))
	max_ap_per_day = max(1, int(data.get("max_ap_per_day", DEFAULT_MAX_AP)))
	current_ap = clampi(int(data.get("current_ap", max_ap_per_day)), 0, max_ap_per_day)
	time_phase = _coerce_time_phase(data.get("time_phase", TimePhase.MORNING))
	_forced_rest_queued = false

	_today_actions.clear()
	for entry in data.get("today_actions", []):
		if entry is Dictionary:
			_today_actions.append((entry as Dictionary).duplicate(true))

	day_changed.emit(current_day)
	ap_changed.emit(current_ap, max_ap_per_day)
	phase_changed.emit(time_phase)
	return true


## 供 PromptManager 的 JSON 绑定调用，返回当前游戏时间的自然语言描述。
func get_time_prompt() -> String:
	var phase_name: String = get_phase_display_name(time_phase)
	var daylight_hint: String = ""
	match time_phase:
		TimePhase.MORNING:
			daylight_hint = "现在是上午，天是亮的，不是晚上。"
		TimePhase.AFTERNOON:
			daylight_hint = "现在是下午，天还亮着，不是晚上。"
		TimePhase.NIGHT:
			daylight_hint = "现在是夜晚。"
	var cal := get_calendar_date()
	var weekday := get_weekday_name()
	var base: String = "当前时间：%d年%d月%d日（%s）・%s，帧语·新星叙事大赛 2027 第 %d 天（总计 %d 天）。%s" % [
		cal["year"], cal["month"], cal["day"], weekday, phase_name, current_day, MAX_DAYS, daylight_hint]
	var summary: String = _build_today_actions_summary()
	if not summary.is_empty():
		base += "\n" + summary
	return base


func _build_today_actions_summary() -> String:
	if _today_actions.is_empty():
		return ""
	var labels: Array[String] = []
	for entry in _today_actions:
		if not entry is Dictionary:
			continue
		var d: Dictionary = entry as Dictionary
		var lbl: String = str(d.get("label", "")).strip_edges()
		if lbl.is_empty():
			lbl = "%s/%s" % [str(d.get("action_type", "")), str(d.get("detail", ""))]
		labels.append(lbl)
	if labels.is_empty():
		return ""
	return "今日已完成：%s" % ", ".join(labels)


## 获取当前游戏日对应的日历日期
func get_calendar_date() -> Dictionary:
	var days_since_start: int = current_day - 1
	# 从起始日期推算（简单实现，每月天数固定表）
	var days_in_month: Array[int] = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var y: int = START_YEAR
	var m: int = START_MONTH
	var d: int = START_DAY + days_since_start
	while d > days_in_month[m]:
		d -= days_in_month[m]
		m += 1
		if m > 12:
			m = 1
			y += 1
	return {"year": y, "month": m, "day": d}


## 获取当前游戏日的星期几
func get_weekday_name() -> String:
	var cal := get_calendar_date()
	# Zeller 公式简化：用 Godot 内置 Time 类计算
	var dict := {"year": cal["year"], "month": cal["month"], "day": cal["day"]}
	var unix := Time.get_unix_time_from_datetime_dict(dict)
	var dt := Time.get_datetime_dict_from_unix_time(int(unix))
	var weekday: int = dt.get("weekday", 0)
	var names: Array[String] = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
	return names[weekday] if weekday >= 0 and weekday < names.size() else "未知"


func reset_runtime_state() -> void:
	current_day = 1
	max_ap_per_day = DEFAULT_MAX_AP
	current_ap = DEFAULT_MAX_AP
	time_phase = TimePhase.MORNING
	_today_actions.clear()
	_forced_rest_queued = false
	day_changed.emit(current_day)
	ap_changed.emit(current_ap, max_ap_per_day)
	phase_changed.emit(time_phase)


func _coerce_time_phase(value: Variant) -> TimePhase:
	var phase_value: int = int(value)
	if phase_value < int(TimePhase.MORNING) or phase_value > int(TimePhase.NIGHT):
		return TimePhase.MORNING
	return phase_value as TimePhase


func _request_forced_rest_if_needed() -> void:
	if _should_force_rest_before_action("", ""):
		_request_forced_rest()


func _should_force_rest_before_action(action_type: String, detail: String) -> bool:
	if _forced_rest_queued:
		return false
	if current_ap <= 0:
		return false
	if action_type == "life" and detail == "forced_rest":
		return false
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return false
	return int(gm.get("stress")) >= 85


func _request_forced_rest() -> void:
	if _forced_rest_queued:
		return
	_forced_rest_queued = true
	var home: Node = get_node_or_null("/root/HomeActivityManager")
	if home == null or not home.has_method("begin_forced_rest"):
		push_warning("[GameLoopManager] Forced rest requested but HomeActivityManager is unavailable")
		_forced_rest_queued = false
		return
	var result: Dictionary = home.begin_forced_rest()
	if not bool(result.get("success", false)):
		push_warning("[GameLoopManager] Forced rest failed: %s" % str(result.get("error", "")))
		_forced_rest_queued = false
