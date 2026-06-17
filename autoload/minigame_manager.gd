extends Node
## MinigameManager Autoload
## 管理小游戏的注册、启动、结算。
## 衔接 DevWorkApp（任务选择）和 GameManager（数值结算）。
##
## 流程：
##   DevWorkApp 选择任务 → start_minigame(task_data)
##   → 弹出独立窗口运行小游戏
##   → 小游戏 finish(result) → 关闭窗口 → 结算数值 → 触发林夏回应 Topic
##   → Topic 完成 → 发出 review_completed → 外部消耗 AP / 推进时间

const MinigameBaseClass = preload("res://scripts/minigame/minigame_base.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const MinigameContentServiceClass = preload("res://scripts/minigame/minigame_content_service.gd")

const REVIEW_TYPE_DESC_FALLBACKS := {
	"typing_code": "搭档刚刚在 IDE 里清理飘落的代码关键字，努力稳住工程",
	"find_bugs": "搭档刚刚在做 QA 测试（查找和修复游戏中的 Bug）",
	"emotion_tag": "搭档刚刚给一批台词做了情绪标注，帮忙校准角色演出的情感基调",
	"script_fill": "搭档刚刚补完了这场戏里的几个关键空位，给剧本留下了自己的文字印记",
	"creative_decision": "搭档刚刚和林夏一起做了几轮创意决策，推进了关键方向的讨论",
	"structured_form": "搭档刚刚把一份结构化方案填完并提交给你确认",
}

## 给 LLM 规划层用的 minigame 目录。结构与 plan_generation.md / dev_planner_agent.md 共享。
## category: "output"（产出型，玩家输入会成为后续工单输入） / "atmosphere"（氛围型，仅装饰）
## work_order_policy: 决定该类型是否能挂 post_task_work_order
##   "required"  —— 必须挂工单（工单以玩家本次输入为输入材料）
##   "optional_independent" —— 氛围型；默认不挂；只有当工单通过"独立性测试"
##      （离开小游戏后仅靠 KB 就能交付）才可以挂
const MINIGAME_PROMPT_INFO := {
	"creative_decision": {
		"category": "output",
		"summary": "玩家在 N 个 AI 生成的方向选项中讨论并拍板",
		"use_case": "设计角色 / 世界观方向（需要玩家敲定设定）",
		"work_order_policy": "required",
	},
	"script_fill": {
		"category": "output",
		"summary": "玩家给 AVG 场景填台词 / 选择分支",
		"use_case": "撰写具体章节剧本",
		"work_order_policy": "required",
	},
	"typing_code": {
		"category": "atmosphere",
		"summary": "键盘敲落代码关键字的打字节奏游戏",
		"use_case": "埋头写代码 / 引擎侧集成 / 功能实装",
		"work_order_policy": "optional_independent",
	},
	"find_bugs": {
		"category": "atmosphere",
		"summary": "翻牌配对找出预设 Bug",
		"use_case": "检查 / 审查 / 校对 / 找问题",
		"work_order_policy": "optional_independent",
	},
	"code_puzzle": {
		"category": "atmosphere",
		"summary": "把打乱的流程步骤按正确顺序排好",
		"use_case": "理清流程 / 梳理顺序",
		"work_order_policy": "optional_independent",
	},
	"emotion_tag": {
		"category": "atmosphere",
		"summary": "给台词片段打情绪标签（选择被打分后丢弃，不持久化）",
		"use_case": "感受基调 / 体验角色情绪切片",
		"work_order_policy": "optional_independent",
	},
}

const DEFAULT_WINDOW_PROFILE := {
	"min": Vector2(960, 640),
	"preferred": Vector2(1280, 800),
}

const WINDOW_PROFILES := {
	"typing_code": {
		"min": Vector2(960, 640),
		"preferred": Vector2(1280, 800),
	},
	"find_bugs": {
		"min": Vector2(900, 620),
		"preferred": Vector2(1120, 760),
	},
	"code_puzzle": {
		"min": Vector2(1040, 620),
		"preferred": Vector2(1180, 760),
	},
	"creative_decision": {
		"min": Vector2(1080, 720),
		"preferred": Vector2(1280, 800),
	},
	"structured_form": {
		"min": Vector2(920, 620),
		"preferred": Vector2(980, 760),
	},
	"script_fill": {
		"min": Vector2(900, 660),
		"preferred": Vector2(1100, 780),
	},
	"emotion_tag": {
		"min": Vector2(1180, 840),
		"preferred": Vector2(1240, 900),
	},
}

#region 信号
## 小游戏启动
signal minigame_started(task_id: String, minigame_type: String)
## 小游戏完成（含结算结果）
signal minigame_completed(task_id: String, result: Dictionary)
## 小游戏被取消
signal minigame_cancelled(task_id: String)
## 林夏回应 Topic 完成（数值已结算），外部可安全消耗 AP
signal review_completed(task_id: String, result: Dictionary)
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
## 小游戏所在的独立窗口
var _minigame_window: Control = null
## 标记是否通过独立窗口运行（窗口关闭时由窗口负责释放子节点）
var _used_standalone_window: bool = false
## 等待回应 Topic 完成时暂存的数据
var _pending_review_topic_id: String = ""
var _pending_review_task_id: String = ""
var _pending_review_result: Dictionary = {}
## 产出型小游戏素材生成服务
var _content_service: Node = null
## 正在准备中的产出型小游戏任务
var _pending_generated_task: Dictionary = {}
var _pending_generated_request_id: String = ""
#endregion


func _ready() -> void:
	_register_default_minigames()
	_setup_content_service()
	ActivityLockUtilsClass.register_free_period_blocker(
		name,
		self,
		"is_running",
		"当前开发活动正在进行，请先完成眼前的工作。"
	)
	print("[MinigameManager] Initialized. %d minigame types registered." % _registry.size())


func _exit_tree() -> void:
	ActivityLockUtilsClass.unregister_free_period_blocker(name)


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


## 给 PromptManager 用：返回结构化的 minigame 目录文本，供规划层 prompt 注入。
## 由 res://config/prompt_providers.json 中 "minigames_prompt" 键绑定。
func get_prompt_summary() -> String:
	var output_lines: Array[String] = []
	var atmos_lines: Array[String] = []
	for type_id in MINIGAME_PROMPT_INFO.keys():
		var info: Dictionary = MINIGAME_PROMPT_INFO[type_id]
		var policy: String = str(info.get("work_order_policy", "")).strip_edges()
		var policy_hint: String = _format_work_order_policy_hint(policy)
		var line: String = "- `%s`：%s。用于「%s」。%s" % [type_id, info["summary"], info["use_case"], policy_hint]
		if info["category"] == "output":
			output_lines.append(line)
		else:
			atmos_lines.append(line)
	var parts: Array[String] = []
	parts.append("### 产出型（玩家输入会成为 LLM 后续工单的输入）")
	parts.append_array(output_lines)
	parts.append("")
	parts.append("### 氛围型（玩家操作不影响 LLM 后续产出，仅参与感装饰）")
	parts.append("默认**不挂** `post_task_work_order`——玩家玩不玩都不该影响 KB/场景落盘。")
	parts.append("只有当工单通过**独立性测试**时才可以挂：把工单 description 单独喂给 Worker，不给它任何小游戏上下文，它仍能仅凭 KB 素材交付。")
	parts.append("禁止在这些工单的【输入材料】里出现「玩家本次 XX 输入」之类的占位符——这些数据永远不会到达 Worker。")
	parts.append_array(atmos_lines)
	return "\n".join(parts)


func _format_work_order_policy_hint(policy: String) -> String:
	match policy:
		"required":
			return "工单策略：**必须**挂 `post_task_work_order`，以玩家本次输入为关键输入材料。"
		"optional_independent":
			return "工单策略：**默认省略** `post_task_work_order`；需要挂时必须通过独立性测试。"
		_:
			return ""


## 是否有小游戏正在运行
func is_running() -> bool:
	return (
		(_current_minigame != null and is_instance_valid(_current_minigame))
		or not _pending_generated_task.is_empty()
		or not _chat_task_data.is_empty()
	)


func _setup_content_service() -> void:
	_content_service = MinigameContentServiceClass.new()
	_content_service.name = "MinigameContentService"
	add_child(_content_service)
	_content_service.content_ready.connect(_on_generated_content_ready)


## 启动小游戏（在独立窗口中打开）
## task_data: 当前 DevCycleManager 下发的任务条目
## 返回是否成功启动
func start_minigame(task_data: Dictionary) -> bool:
	if is_running():
		push_warning("[MinigameManager] A minigame is already running")
		return false

	var busy_reason := ActivityLockUtilsClass.get_blocking_reason(self)
	if not busy_reason.is_empty():
		push_warning("[MinigameManager] Blocked by busy source: %s" % busy_reason)
		ActivityLockUtilsClass.notify_blocked(self, busy_reason)
		return false

	var narrative_reason := ActivityLockUtilsClass.get_narrative_blocking_reason("minigame")
	if not narrative_reason.is_empty():
		push_warning("[MinigameManager] Blocked by narrative lock: %s" % narrative_reason)
		ActivityLockUtilsClass.notify_blocked(self, narrative_reason)
		return false

	var minigame_type: String = str(task_data.get("minigame_type", ""))
	if minigame_type.is_empty():
		push_warning("[MinigameManager] Task has no minigame_type: %s" % str(task_data.get("task_id", "")))
		return false

	if not _registry.has(minigame_type):
		push_warning("[MinigameManager] Unknown minigame type: %s" % minigame_type)
		return false

	if _is_generated_minigame_type(minigame_type):
		return _start_generated_minigame(task_data)

	var launched: bool = _launch_minigame_instance(task_data, {})
	if launched:
		minigame_started.emit(str(task_data.get("task_id", "")), minigame_type)
	return launched


func _is_generated_minigame_type(minigame_type: String) -> bool:
	return minigame_type == "script_fill" or minigame_type == "emotion_tag"


func _start_generated_minigame(task_data: Dictionary) -> bool:
	var task_id: String = str(task_data.get("task_id", ""))
	var window_title: String = str(task_data.get("title", "开发任务"))
	var minigame_type: String = str(task_data.get("minigame_type", ""))
	if not _open_loading_window(window_title, "正在根据当前项目内容生成任务…", minigame_type):
		push_warning("[MinigameManager] Failed to open loading window")
		return false

	_pending_generated_task = task_data.duplicate(true)
	if _content_service == null:
		push_warning("[MinigameManager] Content service unavailable, using empty generated content")
		if not _launch_generated_minigame_from_content({}, true, "content_service_missing"):
			review_completed.emit(task_id, {"cancelled": true})
			return false
	else:
		_pending_generated_request_id = _content_service.request_content(_pending_generated_task)

	print("[MinigameManager] Preparing generated minigame: %s (type: %s)" % [task_id, str(task_data.get("minigame_type", ""))])
	minigame_started.emit(task_id, str(task_data.get("minigame_type", "")))
	return true


func _launch_minigame_instance(task_data: Dictionary, generated_content: Dictionary) -> bool:
	var minigame_type: String = str(task_data.get("minigame_type", ""))

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

	# 在独立窗口中打开小游戏
	var window_title: String = str(task_data.get("title", "开发任务"))
	if not _open_minigame_window(window_title, _current_minigame, minigame_type):
		push_warning("[MinigameManager] Failed to open minigame window")
		_current_minigame.queue_free()
		_current_minigame = null
		_current_task = {}
		return false

	# 启动
	var config: Dictionary = {
		"task_data": task_data,
		"minigame_type": minigame_type,
		"day": _get_current_day(),
		"heroine_mood": _get_heroine_mood(),
	}
	if not generated_content.is_empty():
		config["generated_content"] = generated_content
	_current_minigame.setup(config)

	var task_id: String = str(task_data.get("task_id", ""))
	print("[MinigameManager] Started minigame: %s (type: %s)" % [task_id, minigame_type])
	return true


## 在独立 PseudoWindow 中打开小游戏
func _open_minigame_window(title: String, content: Control, minigame_type: String = "") -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or app_manager.window_manager == null:
		push_warning("[MinigameManager] AppManager or WindowManager not available")
		return false

	var wm: Node = app_manager.window_manager
	if not wm.has_method("create_window"):
		push_warning("[MinigameManager] WindowManager has no create_window method")
		return false

	_minigame_window = wm.create_window(title, content, null)
	if _minigame_window == null:
		return false

	_used_standalone_window = true

	var profile := _get_window_profile(minigame_type)
	var min_size: Vector2 = profile.get("min", DEFAULT_WINDOW_PROFILE["min"])
	var preferred_size: Vector2 = profile.get("preferred", DEFAULT_WINDOW_PROFILE["preferred"])

	# 设置窗口大小并居中：不同小游戏使用各自舒适尺寸，再交给 WindowManager 按桌面可用区域兜底。
	_minigame_window.custom_minimum_size = min_size
	if "min_size" in _minigame_window:
		_minigame_window.min_size = min_size
	_minigame_window.size = preferred_size
	if wm.has_method("fit_window_to_container"):
		wm.fit_window_to_container(_minigame_window)
	else:
		if _minigame_window.has_method("center_in_screen"):
			_minigame_window.center_in_screen()

	# 锁定窗口：禁止关闭和最小化
	if _minigame_window.has_method("set_close_locked"):
		_minigame_window.set_close_locked(true)
	if _minigame_window.has_method("set_minimize_locked"):
		_minigame_window.set_minimize_locked(true)

	return true


func _get_window_profile(minigame_type: String) -> Dictionary:
	var normalized_type := minigame_type.strip_edges()
	if WINDOW_PROFILES.has(normalized_type):
		return WINDOW_PROFILES[normalized_type]
	return DEFAULT_WINDOW_PROFILE


func _open_loading_window(title: String, message: String, minigame_type: String = "") -> bool:
	var loading_root := Control.new()
	loading_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#101623")
	loading_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 220)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var headline := Label.new()
	headline.text = title
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 28)
	box.add_child(headline)

	var status := Label.new()
	status.text = message
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 15)
	box.add_child(status)

	return _open_minigame_window(title, loading_root, minigame_type)


## 关闭小游戏窗口
func _close_minigame_window() -> void:
	if _minigame_window == null or not is_instance_valid(_minigame_window):
		_minigame_window = null
		return

	# 解锁窗口
	if _minigame_window.has_method("set_close_locked"):
		_minigame_window.set_close_locked(false)
	if _minigame_window.has_method("set_minimize_locked"):
		_minigame_window.set_minimize_locked(false)

	# 通过 WindowManager 关闭
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null and app_manager.window_manager != null:
		var wm: Node = app_manager.window_manager
		if wm.has_method("close_window"):
			wm.close_window(_minigame_window)
		else:
			_minigame_window.queue_free()
	else:
		_minigame_window.queue_free()

	_minigame_window = null


## 强制停止当前小游戏
func force_stop() -> void:
	if not _pending_generated_task.is_empty():
		var task_id: String = str(_pending_generated_task.get("task_id", ""))
		_close_minigame_window()
		_used_standalone_window = false
		_cleanup_pending_generated_task()
		review_completed.emit(task_id, {"cancelled": true})
		return
	if _current_minigame != null and is_instance_valid(_current_minigame):
		_current_minigame.cancel()


#region 内部方法

func _on_minigame_finished(result: Dictionary) -> void:
	var task_id: String = str(_current_task.get("task_id", ""))
	var score: float = float(result.get("score", 1.0))

	# 先关闭小游戏窗口
	_close_minigame_window()

	# 根据 score 系数结算数值
	_settle_stats(score)

	print("[MinigameManager] Minigame finished: %s | score: %.2f" % [task_id, score])
	minigame_completed.emit(task_id, result)

	# 触发林夏回应 topic，等待 topic 完成后再发出 review_completed
	_trigger_review_topic_and_wait(task_id, result)

	_cleanup()


func _on_minigame_cancelled() -> void:
	var task_id: String = str(_current_task.get("task_id", ""))

	# 关闭窗口
	_close_minigame_window()

	print("[MinigameManager] Minigame cancelled: %s" % task_id)
	minigame_cancelled.emit(task_id)

	# 取消也发出 review_completed 以解除外部等待
	review_completed.emit(task_id, {"cancelled": true})
	_cleanup()


## 根据小游戏得分结算数值
func _settle_stats(score: float) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	var factor: float = lerpf(0.3, 1.0, score)
	var rewards: Dictionary = _build_task_reward_preview(_current_task, factor)
	if not rewards.is_empty():
		gm.modify_stats(rewards)

	# 好的表现额外奖励激情
	if score >= 0.8:
		gm.modify_stat("passion", 2)
	elif score < 0.4:
		gm.modify_stat("passion", -2)


func _cleanup() -> void:
	# 独立窗口模式下，小游戏实例由窗口关闭动画负责释放
	if not _used_standalone_window:
		if _current_minigame != null and is_instance_valid(_current_minigame):
			_current_minigame.queue_free()
	_current_minigame = null
	_current_task = {}
	_minigame_window = null
	_used_standalone_window = false


func _cleanup_pending_generated_task() -> void:
	_pending_generated_task = {}
	_pending_generated_request_id = ""


func _on_generated_content_ready(
	request_id: String,
	task_id: String,
	_minigame_type: String,
	content: Dictionary,
	used_fallback: bool,
	error_message: String
) -> void:
	if _pending_generated_request_id != request_id:
		return
	if str(_pending_generated_task.get("task_id", "")) != task_id:
		return
	_launch_generated_minigame_from_content(content, used_fallback, error_message)


func _launch_generated_minigame_from_content(content: Dictionary, used_fallback: bool, error_message: String) -> bool:
	var task_id: String = str(_pending_generated_task.get("task_id", ""))
	var task_data: Dictionary = _pending_generated_task.duplicate(true)
	_cleanup_pending_generated_task()
	_close_minigame_window()
	_used_standalone_window = false

	if used_fallback:
		push_warning("[MinigameManager] Generated content fallback used for %s: %s" % [task_id, error_message])

	var launched: bool = _launch_minigame_instance(task_data, content)
	if not launched:
		review_completed.emit(task_id, {"cancelled": true})
	return launched


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
	register_minigame("typing_code", "res://scenes/minigames/typing_code.tscn")
	register_minigame("find_bugs", "res://scenes/minigames/find_bugs.tscn")
	register_minigame("code_puzzle", "res://scenes/minigames/code_puzzle.tscn")
	register_minigame("emotion_tag", "res://scenes/minigames/emotion_tag.tscn")
	register_minigame("script_fill", "res://scenes/minigames/script_fill.tscn")
	register_minigame("creative_decision", "res://scenes/minigames/creative_decision.tscn")
	register_minigame("structured_form", "res://scenes/minigames/structured_form.tscn")
	# register_minigame("fill_dialogue", "res://scenes/minigames/fill_dialogue.tscn")
	# register_minigame("arrange_scene", "res://scenes/minigames/arrange_scene.tscn")
	# register_minigame("match_bgm", "res://scenes/minigames/match_bgm.tscn")
	# register_minigame("whack_bugs", "res://scenes/minigames/whack_bugs.tscn")


## 小游戏结算后触发林夏回应 Topic 并等待完成
func _trigger_review_topic_and_wait(task_id: String, result: Dictionary) -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("activate_topic"):
		# 无法触发 topic，直接完成
		review_completed.emit(task_id, result)
		return

	var score: float = float(result.get("score", 1.0))
	var task_title: String = str(_current_task.get("title", "开发任务"))
	var snippet_title: String = str(result.get("snippet_title", ""))
	var minigame_type: String = str(_current_task.get("minigame_type", ""))
	var performance_desc: String = _resolve_review_performance_desc(result, minigame_type, score)
	var type_desc: String = _resolve_review_type_desc(result, minigame_type)

	var work_desc: String = task_title
	if not snippet_title.is_empty():
		work_desc += "（%s）" % snippet_title
	var creative_summary: String = str(result.get("creative_prompt", "")).strip_edges()

	var topic := ChatTopicClass.new()
	topic.topic_id = "minigame_review_%d" % int(Time.get_unix_time_from_system())
	topic.topic_type = "casual_interaction"
	topic.display_title = "开发进度汇报"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "dm_lin_xia"
	topic.system_prompt = _build_review_prompt(work_desc, performance_desc, score, type_desc, creative_summary)
	topic.goal_description = "对玩家刚完成的开发工作做出回应"
	topic.context_data = {
		"linkchat_open_mode": "force",
		"complete_after_first_reply": true,
	}
	topic.timeout_seconds = 0

	if not chat.activate_topic(topic):
		push_warning("[MinigameManager] Failed to activate review topic")
		review_completed.emit(task_id, result)
		return

	# 暂存等待数据
	_pending_review_topic_id = topic.topic_id
	_pending_review_task_id = task_id
	_pending_review_result = result

	# 监听 topic_completed 信号
	if not chat.topic_completed.is_connected(_on_review_topic_completed):
		chat.topic_completed.connect(_on_review_topic_completed)

	# NPC 主动发言（auto_store=false 让 LinkChat UI 播放打字机动画）
	if chat.has_method("request_topic_npc_reply"):
		chat.request_topic_npc_reply(topic.channel_id, "", false, true)

	print("[MinigameManager] Review topic activated, waiting for completion: %s" % work_desc)


## 林夏回应 Topic 完成回调
func _on_review_topic_completed(topic, _result: Dictionary) -> void:
	if topic == null:
		return
	# 只处理我们发起的 review topic
	if str(topic.topic_id) != _pending_review_topic_id:
		return

	# 断开信号
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.topic_completed.is_connected(_on_review_topic_completed):
		chat.topic_completed.disconnect(_on_review_topic_completed)

	print("[MinigameManager] Review topic completed: %s" % _pending_review_topic_id)

	# 发出 review_completed，外部可安全消耗 AP
	review_completed.emit(_pending_review_task_id, _pending_review_result)

	_pending_review_topic_id = ""
	_pending_review_task_id = ""
	_pending_review_result = {}


func _resolve_review_type_desc(result: Dictionary, minigame_type: String) -> String:
	var explicit_desc: String = str(result.get("review_type_desc", _current_task.get("review_type_desc", ""))).strip_edges()
	if not explicit_desc.is_empty():
		return explicit_desc
	return str(REVIEW_TYPE_DESC_FALLBACKS.get(minigame_type, "搭档刚刚完成了一项开发工作"))


func _resolve_review_performance_desc(result: Dictionary, minigame_type: String, score: float) -> String:
	var explicit_desc: String = str(result.get("review_performance_desc", _current_task.get("review_performance_desc", ""))).strip_edges()
	if not explicit_desc.is_empty():
		return explicit_desc
	return _build_fallback_review_performance_desc(result, minigame_type, score)


func _build_fallback_review_performance_desc(result: Dictionary, minigame_type: String, score: float) -> String:
	var accuracy: float = float(result.get("accuracy", 1.0))
	var max_combo: int = int(result.get("max_combo", 0))
	var completed_lines: int = int(result.get("completed_lines", 0))
	var total_lines: int = int(result.get("total_lines", 0))
	var miss_count: int = int(result.get("miss_count", 0))
	match minigame_type:
		"typing_code":
			if score >= 0.9:
				return "表现非常出色，清掉了%d/%d个飘落关键字，准确率%.0f%%，最大连击%d，几乎没放过任何Bug" % [completed_lines, total_lines, accuracy * 100.0, max_combo]
			if score >= 0.7:
				return "表现还不错，清掉了%d/%d个飘落关键字，准确率%.0f%%" % [completed_lines, total_lines, accuracy * 100.0]
			if score >= 0.5:
				return "表现一般，清掉了%d/%d个飘落关键字，但漏掉了%d个" % [completed_lines, total_lines, miss_count]
			return "表现不太好，只清掉了%d/%d个飘落关键字，Bug 堆得有点快" % [completed_lines, total_lines]
		"find_bugs":
			var attempts_count: int = int(result.get("attempts", 0))
			if score >= 0.9:
				return "表现非常出色，修复了全部%d个Bug，只用了%d次尝试，连续修复%d次" % [total_lines, attempts_count, max_combo]
			if score >= 0.7:
				return "表现还不错，修复了%d个Bug，用了%d次尝试" % [total_lines, attempts_count]
			if score >= 0.5:
				return "表现一般，修复了%d个Bug，但用了%d次尝试" % [total_lines, attempts_count]
			return "表现不太好，修复了%d个Bug，效率不太高" % [total_lines]
		"emotion_tag":
			var total_items: int = int(result.get("total_items", 0))
			var correct_count: int = int(result.get("correct_count", 0))
			if score >= 0.9:
				return "你几乎把这批句子的情绪都听准了，%d/%d 句没有跑偏。" % [correct_count, total_items]
			if score >= 0.7:
				return "你大部分都判断对了，%d/%d 句抓到了情绪落点。" % [correct_count, total_items]
			if score >= 0.5:
				return "你先听出了 %d/%d 句的情绪，方向是对的，但还有几句更微妙。" % [correct_count, total_items]
			return "这批句子的情绪你还没完全听准，目前只有 %d/%d 句判断到位。" % [correct_count, total_items]
		"script_fill":
			var slot_count: int = int(result.get("blank_count", result.get("slot_count", 0)))
			var filled_slots: int = int(result.get("filled_blanks", result.get("filled_slots", 0)))
			if score >= 0.9:
				return "你把这场戏的%d/%d处关键空位都补上了，整页稿子已经像能直接排进工程里一样顺了" % [filled_slots, slot_count]
			if score >= 0.7:
				return "你补上了%d/%d处关键空位，这场戏已经开始有你自己的味道了" % [filled_slots, slot_count]
			if score >= 0.5:
				return "你先补了%d/%d处关键空位，方向有了，但还留着一点没落笔的地方" % [filled_slots, slot_count]
			return "你只补出了%d/%d处关键空位，像是刚把最难下手的那几处先试着写下来" % [filled_slots, slot_count]
		"creative_decision":
			var total_rounds: int = int(result.get("total_rounds", 0))
			var final_proposal: Dictionary = result.get("final_proposal", {}) if result.get("final_proposal", {}) is Dictionary else {}
			var final_title: String = str(final_proposal.get("title", "")).strip_edges()
			if final_title.is_empty():
				final_title = "未敲定方向"
			return "搭档和林夏在讨论室来回 %d 轮，最后落在「%s」这个方向" % [total_rounds, final_title]
		_:
			if score >= 0.9:
				return "表现非常出色，完成了%d/%d行代码，准确率%.0f%%，最大连击%d" % [completed_lines, total_lines, accuracy * 100.0, max_combo]
			if score >= 0.7:
				return "表现还不错，完成了%d/%d行代码，准确率%.0f%%" % [completed_lines, total_lines, accuracy * 100.0]
			if score >= 0.5:
				return "表现一般，只完成了%d/%d行代码，准确率%.0f%%" % [completed_lines, total_lines, accuracy * 100.0]
			return "表现不太好，只完成了%d/%d行代码，准确率%.0f%%" % [completed_lines, total_lines, accuracy * 100.0]


func _build_review_prompt(work_desc: String, performance_desc: String, score: float, type_desc: String, creative_summary: String = "") -> String:
	var mood_hint: String = ""
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_mood_summary"):
		mood_hint = "\n\n" + gm.get_mood_summary()

	var tone_hint: String = ""
	if score >= 0.9:
		tone_hint = "你对搭档的表现很满意，可以夸奖、调侃、或表达惊喜。"
	elif score >= 0.7:
		tone_hint = "搭档做得还行，你可以肯定但也可以随意吐槽一两句。"
	elif score >= 0.5:
		tone_hint = "搭档做得一般般，你可以鼓励但也可以表达一点小失望。"
	else:
		tone_hint = "搭档做得不太好，你可以吐槽、无奈、或者半开玩笑地嫌弃。"

	var creative_block: String = ""
	if not creative_summary.is_empty():
		creative_block = "\n【玩家刚写下的内容】\n%s\n" % creative_summary

	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_method("resolve_with_vars"):
		if pm.has_prompt("minigame_work_review"):
			var resolved := str(pm.resolve_with_vars("minigame_work_review", {
				"work_desc": work_desc,
				"type_desc": type_desc,
				"performance_desc": performance_desc,
				"creative_block": creative_block.strip_edges(),
				"tone_hint": tone_hint,
				"mood_hint": mood_hint.strip_edges(),
			})).strip_edges()
			if not resolved.is_empty():
				return resolved

	return """你是林夏，{player_name}的叙事大赛搭档。%s刚完成了一项工作，你要对此做出简短回应。

【工作内容】%s
【工作类型】%s
【表现】%s
%s

%s

【要求】
- 用1-2条消息回应，简短自然，像发微信一样
- 不要复述具体数据（准确率、连击数等），用感性的方式表达
- 可以评价工作内容本身（比如"存档系统终于搞定了"），也可以评价搭档的状态
- 如果上面给了“玩家刚写下的内容”，优先像搭档看到了新稿子一样，针对其中一两句做自然反馈
- 语气要符合你当前的心情和与搭档的关系
- 回复完毕后在最后一条消息末尾加 [TOPIC_COMPLETE]%s""" % [type_desc, work_desc, type_desc, performance_desc, creative_block, tone_hint, mood_hint]

#endregion

#region 聊天型任务（chat_topic）
## 聊天型任务：玩家与林夏讨论某个议题，对话完成后创建工单交给 Planner 处理

## 聊天型任务运行状态
var _chat_task_data: Dictionary = {}
var _chat_task_topic_id: String = ""
var _chat_task_channel_id: String = ""


## 启动聊天型任务
## task_data 中需要 topic_config 字段：
##   system_prompt: 林夏的对话系统提示词
##   kb_category: 注入的 KB 分类（world / characters / story / notes）
##   kb_entry_id: 注入的条目 ID（可选，world 类别不需要）
## 返回是否成功启动
func start_chat_task(task_data: Dictionary) -> bool:
	if is_running() or not _chat_task_data.is_empty():
		push_warning("[MinigameManager] A task is already running")
		return false

	var busy_reason := ActivityLockUtilsClass.get_blocking_reason(self)
	if not busy_reason.is_empty():
		push_warning("[MinigameManager] Blocked by busy source: %s" % busy_reason)
		ActivityLockUtilsClass.notify_blocked(self, busy_reason)
		return false

	var narrative_reason := ActivityLockUtilsClass.get_narrative_blocking_reason("minigame")
	if not narrative_reason.is_empty():
		push_warning("[MinigameManager] Blocked by narrative lock: %s" % narrative_reason)
		ActivityLockUtilsClass.notify_blocked(self, narrative_reason)
		return false

	var topic_config: Dictionary = task_data.get("topic_config", {})
	if topic_config.is_empty():
		push_warning("[MinigameManager] Chat task has no topic_config: %s" % str(task_data.get("task_id", "")))
		return false

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("activate_topic"):
		push_warning("[MinigameManager] ChatManager not available for chat task")
		return false

	_chat_task_data = task_data
	var task_id: String = str(task_data.get("task_id", ""))
	var task_title: String = str(task_data.get("title", "讨论"))
	var sys_prompt: String = str(topic_config.get("system_prompt", ""))
	var topic := ChatTopicClass.new()
	topic.topic_id = "chat_task_%s_%d" % [task_id, int(Time.get_unix_time_from_system())]
	topic.topic_type = "casual_interaction"
	topic.display_title = task_title
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "dm_lin_xia"
	topic.system_prompt = sys_prompt
	topic.goal_description = str(topic_config.get("goal_description", "与搭档讨论：%s" % task_title))
	topic.context_data = {
		"linkchat_open_mode": "force",
	}
	topic.timeout_seconds = 0

	if not chat.activate_topic(topic):
		push_warning("[MinigameManager] Failed to activate chat task topic: %s" % task_id)
		_chat_task_data = {}
		return false

	_chat_task_topic_id = topic.topic_id
	_chat_task_channel_id = topic.channel_id

	# 监听 topic 完成
	if not chat.topic_completed.is_connected(_on_chat_task_topic_completed):
		chat.topic_completed.connect(_on_chat_task_topic_completed)

	# NPC 先开口
	if chat.has_method("request_topic_npc_reply"):
		chat.request_topic_npc_reply(topic.channel_id, "", false, false)

	# 注意：数值结算在讨论成功后才进行（_on_chat_task_topic_completed 的成功路径）

	print("[MinigameManager] Chat task started: %s | topic: %s" % [task_id, topic.topic_id])
	minigame_started.emit(task_id, "chat_topic")
	return true


## 聊天型任务的数值结算
func _settle_chat_task_stats() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	var rewards: Dictionary = _build_task_reward_preview(_chat_task_data, 1.0)
	if not rewards.is_empty():
		gm.modify_stats(rewards)


func _build_task_reward_preview(task: Dictionary, positive_scale: float) -> Dictionary:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null and dcm.has_method("build_task_reward_preview"):
		return dcm.build_task_reward_preview(task, positive_scale)

	var rewards: Dictionary = {}
	var stat_changes: Dictionary = task.get("stat_changes", {})
	for key in stat_changes:
		var scaled_value: int = roundi(float(int(stat_changes[key])) * positive_scale)
		if scaled_value != 0:
			rewards[str(key)] = scaled_value
	return rewards


## 聊天型任务的 Topic 完成回调
func _on_chat_task_topic_completed(topic, _result: Dictionary) -> void:
	if topic == null:
		return
	if str(topic.topic_id) != _chat_task_topic_id:
		return

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.topic_completed.is_connected(_on_chat_task_topic_completed):
		chat.topic_completed.disconnect(_on_chat_task_topic_completed)

	var task_id: String = str(_chat_task_data.get("task_id", ""))
	var topic_failed: bool = bool(_result.get("topic_failed", false))
	print("[MinigameManager] Chat task topic completed: %s (failed: %s)" % [task_id, str(topic_failed)])

	# 讨论失败（林夏标记 [TOPIC_FAILED]）→ 跳过工单，不写 KB
	if topic_failed:
		push_warning("[MinigameManager] Chat task failed (off-topic/unproductive): %s" % task_id)
		review_completed.emit(task_id, {"chat_task": true, "topic_failed": true})
		_cleanup_chat_task()
		return

	# 讨论成功，结算数值奖励
	_settle_chat_task_stats()

	# 提取对话记录，创建工单交给 Planner 处理
	var conversation_log: String = _extract_conversation_log(_chat_task_channel_id)
	if conversation_log.is_empty():
		push_warning("[MinigameManager] No conversation log found for chat task: %s" % task_id)
		review_completed.emit(task_id, {"chat_task": true})
		_cleanup_chat_task()
		return

	_dispatch_kb_work_order(task_id, conversation_log)


## 从频道中提取最近的对话记录
func _extract_conversation_log(channel_id: String) -> String:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("get_channel"):
		return ""

	var channel = chat.get_channel(channel_id)
	if channel == null:
		return ""

	var messages: Array = channel.messages if "messages" in channel else []
	if messages.is_empty():
		return ""

	# 取最近 20 条消息（一般足够覆盖一次讨论）
	var recent: Array = messages.slice(maxi(0, messages.size() - 20))
	var log_parts: PackedStringArray = []
	for msg in recent:
		var sender: String = str(msg.get("sender_name", msg.get("sender_id", "???")))
		var content: String = str(msg.get("content", ""))
		if content.is_empty():
			continue
		log_parts.append("%s: %s" % [sender, content])
	return "\n".join(log_parts)


## 创建工单，将对话记录交给 Planner Agent 处理 KB 写入
func _dispatch_kb_work_order(task_id: String, conversation_log: String) -> void:
	var topic_config: Dictionary = _chat_task_data.get("topic_config", {})
	var kb_category: String = str(topic_config.get("kb_category", "world"))
	var kb_entry_id: String = str(topic_config.get("kb_entry_id", ""))
	var task_title: String = str(_chat_task_data.get("title", ""))
	var task_desc: String = str(_chat_task_data.get("description", ""))

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		push_warning("[MinigameManager] WorkOrderManager not available, skipping work order")
		review_completed.emit(task_id, {"chat_task": true, "work_order_created": false})
		_cleanup_chat_task()
		return

	# 构建工单描述：包含任务背景、KB 目标、对话记录
	var desc_parts: PackedStringArray = []
	desc_parts.append("## 任务背景")
	desc_parts.append("两位搭档刚刚完成了关于「%s」的讨论。" % task_title)
	if not task_desc.is_empty():
		desc_parts.append("任务描述：%s" % task_desc)
	desc_parts.append("")
	desc_parts.append("## KB 目标")
	desc_parts.append("- 分类：%s" % kb_category)
	if not kb_entry_id.is_empty():
		desc_parts.append("- 条目 ID：%s" % kb_entry_id)
	desc_parts.append("")
	desc_parts.append("## 要求")
	desc_parts.append("根据以下对话记录，提取关键决策和创意，写入 KnowledgeBase 对应分类。")
	desc_parts.append("只提取讨论中确定下来的内容，不要脑补。")
	desc_parts.append("")
	desc_parts.append("## 对话记录")
	desc_parts.append(conversation_log)

	var order_title: String = "整理讨论结果：%s" % task_title
	var order_desc: String = "\n".join(desc_parts)

	var order: Resource = wom.create_order(order_title, order_desc, {
		"source_type": "dev_task",
		"source_id": task_id,
	})
	order.priority = 3  # 高优先级，玩家刚完成讨论

	var requester_order_id: String = str(_chat_task_data.get("_requester_order_id", ""))
	if not requester_order_id.is_empty():
		order.parent_order_id = requester_order_id
		var parent_order: Resource = wom.get_order(requester_order_id) if wom.has_method("get_order") else null
		if parent_order != null and order.id not in parent_order.children_order_ids:
			parent_order.children_order_ids.append(order.id)
			parent_order.updated_at = int(Time.get_unix_time_from_system())

	var dispatched: bool = wom.dispatch_order(order.id)
	if dispatched:
		print("[MinigameManager] Work order dispatched: %s (id: %s, category: %s)" % [order_title, order.id, kb_category])
	else:
		push_warning("[MinigameManager] Failed to dispatch work order: %s" % order.id)

	review_completed.emit(task_id, {"chat_task": true, "work_order_created": dispatched, "work_order_id": order.id})
	_cleanup_chat_task()


## 清理聊天型任务状态
func _cleanup_chat_task() -> void:
	_chat_task_data = {}
	_chat_task_topic_id = ""
	_chat_task_channel_id = ""

#endregion
