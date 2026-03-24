extends Node
## MinigameManager Autoload
## 管理小游戏的注册、启动、结算。
## 衔接 DevWorkApp（任务选择）和 GameManager（数值结算）。
##
## 流程：
##   DevWorkApp 选择任务 → start_minigame(task_data)
##   → 实例化对应小游戏场景 → 小游戏运行
##   → 小游戏 finish(result) → 结算数值 → 通知完成

const MinigameBaseClass = preload("res://scripts/minigame/minigame_base.gd")

#region 信号
## 小游戏启动
signal minigame_started(task_id: String, minigame_type: String)
## 小游戏完成（含结算结果）
signal minigame_completed(task_id: String, result: Dictionary)
## 小游戏被取消
signal minigame_cancelled(task_id: String)
#endregion

#region 小游戏注册表
## minigame_type -> PackedScene path
var _registry: Dictionary = {}
#endregion

#region 运行状态
## 当前运行中的小游戏实例
var _current_minigame: Control = null
## 当前任务数据
var _current_task: Dictionary = {}
#endregion


func _ready() -> void:
	_register_default_minigames()
	print("[MinigameManager] Initialized. %d minigame types registered." % _registry.size())


## 注册小游戏类型
func register_minigame(minigame_type: String, scene_path: String) -> void:
	_registry[minigame_type] = scene_path


## 检查是否有对应的小游戏
func has_minigame(minigame_type: String) -> bool:
	return _registry.has(minigame_type)


## 获取所有已注册的小游戏类型
func get_registered_types() -> Array[String]:
	var result: Array[String] = []
	for key in _registry.keys():
		result.append(str(key))
	return result


## 是否有小游戏正在运行
func is_running() -> bool:
	return _current_minigame != null and is_instance_valid(_current_minigame)


## 启动小游戏
## task_data: dev_work_tasks.json 中的任务条目
## host_container: 小游戏场景将被添加到的容器节点
## 返回是否成功启动
func start_minigame(task_data: Dictionary, host_container: Control) -> bool:
	if is_running():
		push_warning("[MinigameManager] A minigame is already running")
		return false

	var minigame_type: String = str(task_data.get("minigame_type", ""))
	if minigame_type.is_empty():
		push_warning("[MinigameManager] Task has no minigame_type: %s" % str(task_data.get("task_id", "")))
		return false

	if not _registry.has(minigame_type):
		push_warning("[MinigameManager] Unknown minigame type: %s" % minigame_type)
		return false

	var scene_path: String = _registry[minigame_type]
	if not ResourceLoader.exists(scene_path):
		push_warning("[MinigameManager] Minigame scene not found: %s" % scene_path)
		return false

	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_warning("[MinigameManager] Failed to load minigame scene: %s" % scene_path)
		return false

	var instance: Node = scene.instantiate()
	if not (instance is MinigameBaseClass):
		push_warning("[MinigameManager] Scene root is not MinigameBase: %s" % scene_path)
		instance.queue_free()
		return false

	_current_task = task_data
	_current_minigame = instance as Control

	# 连接信号
	_current_minigame.minigame_finished.connect(_on_minigame_finished)
	_current_minigame.minigame_cancelled.connect(_on_minigame_cancelled)

	# 添加到宿主容器
	host_container.add_child(_current_minigame)
	_current_minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 启动
	var config: Dictionary = {
		"task_data": task_data,
		"minigame_type": minigame_type,
		"day": _get_current_day(),
		"heroine_mood": _get_heroine_mood(),
	}
	_current_minigame.setup(config)

	var task_id: String = str(task_data.get("task_id", ""))
	print("[MinigameManager] Started minigame: %s (type: %s)" % [task_id, minigame_type])
	minigame_started.emit(task_id, minigame_type)
	return true


## 强制停止当前小游戏
func force_stop() -> void:
	if _current_minigame != null and is_instance_valid(_current_minigame):
		_current_minigame.cancel()


#region 内部方法

func _on_minigame_finished(result: Dictionary) -> void:
	var task_id: String = str(_current_task.get("task_id", ""))
	var score: float = float(result.get("score", 1.0))

	# 根据 score 系数结算数值
	_settle_stats(score)

	print("[MinigameManager] Minigame finished: %s | score: %.2f" % [task_id, score])
	minigame_completed.emit(task_id, result)
	_cleanup()


func _on_minigame_cancelled() -> void:
	var task_id: String = str(_current_task.get("task_id", ""))
	print("[MinigameManager] Minigame cancelled: %s" % task_id)
	minigame_cancelled.emit(task_id)
	_cleanup()


## 根据小游戏得分结算数值
func _settle_stats(score: float) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	var stat_changes: Dictionary = _current_task.get("stat_changes", {})
	var scaled_changes: Dictionary = {}
	for key in stat_changes:
		# score 影响正面数值的获取量，最低保底 30%
		var base: int = int(stat_changes[key])
		var factor: float = lerpf(0.3, 1.0, score)
		scaled_changes[key] = roundi(float(base) * factor)

	if not scaled_changes.is_empty():
		gm.modify_stats(scaled_changes)

	# 压力固定增加（不受 score 影响）
	var stress_cost: int = int(_current_task.get("stress_cost", 0))
	if stress_cost > 0:
		gm.modify_stat("stress", stress_cost)

	# 好的表现额外奖励激情
	if score >= 0.8:
		gm.modify_stat("passion", 2)
	elif score < 0.4:
		gm.modify_stat("passion", -2)


func _cleanup() -> void:
	if _current_minigame != null and is_instance_valid(_current_minigame):
		_current_minigame.queue_free()
	_current_minigame = null
	_current_task = {}


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return 1
	return int(glm.get("current_day"))


func _get_heroine_mood() -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return {}
	return {
		"affection": int(gm.get("affection")),
		"stress": int(gm.get("stress")),
		"passion": int(gm.get("passion")),
	}


## 注册默认小游戏（后续添加新类型在这里注册）
func _register_default_minigames() -> void:
	# 占位：后续每实现一个小游戏就在这里注册
	# register_minigame("fill_dialogue", "res://scenes/minigames/fill_dialogue.tscn")
	# register_minigame("typing_code", "res://scenes/minigames/typing_code.tscn")
	# register_minigame("find_bugs", "res://scenes/minigames/find_bugs.tscn")
	# register_minigame("arrange_scene", "res://scenes/minigames/arrange_scene.tscn")
	# register_minigame("match_bgm", "res://scenes/minigames/match_bgm.tscn")
	# register_minigame("whack_bugs", "res://scenes/minigames/whack_bugs.tscn")
	pass

#endregion
