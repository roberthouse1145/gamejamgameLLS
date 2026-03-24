class_name MinigameBase extends Control
## 小游戏基类
## 所有开发小游戏继承此类，实现统一的启动/结算接口。
##
## 生命周期：
##   setup(config) → 小游戏初始化
##   _on_minigame_start() → 子类覆写，开始游戏逻辑
##   finish(result) → 子类调用，通知结算
##
## 子类必须覆写：
##   _on_minigame_start() — 启动小游戏的具体逻辑
##   _on_minigame_cleanup() — 清理资源（可选）

## 小游戏完成，携带结算数据
## result: { score: float (0.0~1.0), choices: Dictionary, ... }
signal minigame_finished(result: Dictionary)

## 玩家主动放弃
signal minigame_cancelled()

## 小游戏配置（由 MinigameManager 传入）
var config: Dictionary = {}

## 关联的任务数据（dev_work_tasks.json 中的条目）
var task_data: Dictionary = {}

## 是否正在运行
var _running: bool = false


## 由 MinigameManager 调用，初始化并启动小游戏
func setup(p_config: Dictionary) -> void:
	config = p_config
	task_data = config.get("task_data", {})
	_running = true
	_on_minigame_start()


## 子类覆写：小游戏开始时的逻辑
func _on_minigame_start() -> void:
	push_warning("[MinigameBase] _on_minigame_start() not implemented by subclass")


## 子类覆写：清理资源（可选）
func _on_minigame_cleanup() -> void:
	pass


## 子类调用：完成小游戏
## score: 0.0 ~ 1.0，影响数值结算的系数
func finish(result: Dictionary) -> void:
	if not _running:
		return
	_running = false
	if not result.has("score"):
		result["score"] = 1.0
	result["score"] = clampf(float(result.get("score", 1.0)), 0.0, 1.0)
	result["task_id"] = str(task_data.get("task_id", ""))
	result["minigame_type"] = str(config.get("minigame_type", ""))
	_on_minigame_cleanup()
	minigame_finished.emit(result)


## 子类调用：放弃小游戏
func cancel() -> void:
	if not _running:
		return
	_running = false
	_on_minigame_cleanup()
	minigame_cancelled.emit()


## 工具方法：获取林夏当前状态（子类可用于调整难度/提示）
func get_heroine_mood() -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return {}
	return {
		"affection": int(gm.get("affection")),
		"stress": int(gm.get("stress")),
		"passion": int(gm.get("passion")),
	}


## 工具方法：获取当前天数（子类可用于难度递增）
func get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return 1
	return int(glm.get("current_day"))
