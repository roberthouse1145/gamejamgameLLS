extends Node
## TimeManager — 游戏内连续时钟 autoload（已禁用）
## 提供独立于现实的游戏时间系统（HH:MM 连续推进）
## 游戏内 1 天 = 现实 N 分钟（可配置）
##
## 注意：此系统已从 autoload 中移除。
## 当前游戏使用 GameLoopManager 的回合制 AP 系统（早/日/夜三阶段）驱动时间。
## 两套时间系统并行运行时会产生 day_changed 信号冲突，因此暂时禁用本系统。
## 如未来需要连续时钟（如任务栏显示 HH:MM），可重新启用并与 GameLoopManager 做同步对接。
##
## 用法（禁用前）：TimeManager.get_game_time(), TimeManager.format_time()

## 游戏时间变化时发出（每游戏分钟）
signal time_changed(hour: int, minute: int)
## 新的一天开始
signal day_changed(day: int)
## 每游戏分钟发出
signal minute_tick(total_minutes: int)
## 工作日开始（09:00）
signal work_day_started()
## 工作日结束（18:00）
signal work_day_ended()

const WORK_START_HOUR: int = 9
const WORK_END_HOUR: int = 18

## 游戏内 1 天对应的现实秒数（默认 24 分钟 = 1 天）
@export var real_seconds_per_game_day: float = 1440.0

## 游戏起始日期
var _current_day: int = 1
## 当前天内已过的游戏秒数（0 ~ 86400）
var _day_seconds: float = 0.0
## 是否暂停时间流逝
var _paused: bool = false
## 上一次发出信号时的分钟数
var _last_emitted_minute: int = -1

## 时间流速倍率（1.0 = 正常）
var time_scale: float = 1.0
## 上一帧是否处于工作时间（用于边界检测）
var _was_work_hours: bool = false


func _ready() -> void:
	# 默认从早上 9:00 开始
	set_time(9, 0)
	_was_work_hours = is_work_hours()


func _process(delta: float) -> void:
	if _paused:
		return

	# 现实 delta → 游戏秒数
	var game_seconds_per_real_second: float = 86400.0 / real_seconds_per_game_day
	_day_seconds += delta * game_seconds_per_real_second * time_scale

	# 检查是否过了一天
	if _day_seconds >= 86400.0:
		_day_seconds -= 86400.0
		_current_day += 1
		day_changed.emit(_current_day)

	# 每游戏分钟发信号
	var current_minute := get_total_minutes()
	if current_minute != _last_emitted_minute:
		_last_emitted_minute = current_minute
		time_changed.emit(get_hour(), get_minute())
		minute_tick.emit(current_minute)

		# 检测工作日边界
		var now_work: bool = is_work_hours()
		if not _was_work_hours and now_work:
			work_day_started.emit()
		elif _was_work_hours and not now_work:
			work_day_ended.emit()
		_was_work_hours = now_work


#region 公共 API

## 获取当前游戏小时（0-23）
func get_hour() -> int:
	return int(_day_seconds / 3600.0) % 24


## 获取当前游戏分钟（0-59）
func get_minute() -> int:
	return int(_day_seconds / 60.0) % 60


## 获取总分钟数（hour * 60 + minute）
func get_total_minutes() -> int:
	return get_hour() * 60 + get_minute()


## 获取当前游戏天数
func get_day() -> int:
	return _current_day


## 获取格式化时间字符串 "HH:MM"
func format_time() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


## 获取游戏时间戳（天数 * 86400 + 天内秒数），用于排序和比较
func get_game_timestamp() -> int:
	return (_current_day - 1) * 86400 + int(_day_seconds)


## 获取相对时间描述（"刚刚"、"5分钟前"、"2小时前"、"昨天"）
func get_relative_time(timestamp: int) -> String:
	var diff := get_game_timestamp() - timestamp
	if diff < 60:
		return "刚刚"
	elif diff < 3600:
		@warning_ignore("integer_division")
		return "%d分钟前" % (diff / 60)
	elif diff < 86400:
		@warning_ignore("integer_division")
		return "%d小时前" % (diff / 3600)
	elif diff < 172800:
		return "昨天"
	else:
		@warning_ignore("integer_division")
		return "%d天前" % (diff / 86400)


## 设置游戏时间
func set_time(hour: int, minute: int) -> void:
	var old_work: bool = is_work_hours()
	_day_seconds = float(hour * 3600 + minute * 60)
	_last_emitted_minute = get_total_minutes()
	time_changed.emit(get_hour(), get_minute())
	# 检测 set_time 导致的工作日边界跨越
	var new_work: bool = is_work_hours()
	if not old_work and new_work:
		work_day_started.emit()
	elif old_work and not new_work:
		work_day_ended.emit()
	_was_work_hours = new_work


## 设置游戏天数
func set_day(day: int) -> void:
	_current_day = day
	day_changed.emit(_current_day)


## 暂停/恢复时间
func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


## 快进到指定时间（同一天内）
func advance_to(hour: int, minute: int) -> void:
	var target := float(hour * 3600 + minute * 60)
	if target <= _day_seconds:
		# 目标在当前时间之前，跳到第二天
		_current_day += 1
		day_changed.emit(_current_day)
	_day_seconds = target
	_last_emitted_minute = get_total_minutes()
	time_changed.emit(get_hour(), get_minute())

## 当前是否处于工作时间（09:00 ~ 18:00）
func is_work_hours() -> bool:
	var hour: int = get_hour()
	return hour >= WORK_START_HOUR and hour < WORK_END_HOUR


## 设置时间倍速等级（0=暂停, 1=x1, 2=x2, 3=x3）
func set_time_scale_level(level: int) -> void:
	match level:
		0:
			set_paused(true)
			time_scale = 0.0
		1:
			set_paused(false)
			time_scale = 1.0
		2:
			set_paused(false)
			time_scale = 2.0
		3:
			set_paused(false)
			time_scale = 3.0

#endregion
