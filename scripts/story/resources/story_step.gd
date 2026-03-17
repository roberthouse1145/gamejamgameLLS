class_name StoryStep extends Resource
## 剧本步骤资源
## 每个 step 代表叙事流程中的一个节点：执行动作 → 等待条件 → 推进

## 步骤唯一 ID（如 "day1_02_gamejam_announce"）
@export var step_id: String = ""

## 步骤描述（编辑器/调试用）
@export var description: String = ""

## 要执行的动作列表（按顺序执行）
## 每个 action 是 Dictionary，必须包含 "type" 字段
## 支持的 type:
##   activate_topic  — 激活聊天话题
##   set_app_access  — 控制 APP 可用性
##   set_phase       — 设置天数/时段
##   modify_stats    — 修改数值
##   play_avg        — 播放 AVG 场景
##   open_browser    — 打开浏览器页面
##   post_moment     — 发朋友圈
##   set_variable    — 设置剧情变量
##   delay           — 延迟（秒）
@export var actions: Array[Dictionary] = []

## 等待条件 — 满足后才推进到下一步
## 必须包含 "type" 字段
## 支持的 type:
##   immediate       — 立即推进
##   topic_completed — 等待指定 topic 完成
##   url_opened      — 等待玩家打开指定 URL
##   form_submitted  — 等待表单提交
##   avg_scene_ended — 等待 AVG 场景结束
##   date_started    — 等待约会开始
##   date_completed  — 等待约会结束
##   app_opened      — 等待玩家打开指定 APP
##   variable_equals — 等待剧情变量达到指定值
##   phase_reached   — 等待到达指定时段
@export var wait_for: Dictionary = {"type": "immediate"}

## 从玩家行为中捕获变量（可选）
## key: 变量名, value: 数据路径表达式
@export var capture: Dictionary = {}

## 下一步的 step_id（简单线性推进）
@export var next: String = ""

## 条件分支（优先于 next）
## 每项: { "if": "条件表达式", "next": "step_id" }
## 最后一项可以是 { "default": true, "next": "step_id" }
@export var next_conditions: Array[Dictionary] = []


## 获取实际的下一步 ID（考虑条件分支）
func resolve_next(variables: Dictionary, game_state: Dictionary) -> String:
	if next_conditions.is_empty():
		return next

	for condition in next_conditions:
		if condition.get("default", false):
			return str(condition.get("next", ""))
		var expr: String = str(condition.get("if", ""))
		if _evaluate_condition(expr, variables, game_state):
			return str(condition.get("next", ""))

	return next


## 简单条件求值器
## 支持: "variable_name >= 50", "variable_name == true", "stress >= 50"
func _evaluate_condition(expr: String, variables: Dictionary, game_state: Dictionary) -> bool:
	var parts: PackedStringArray = expr.strip_edges().split(" ", false)
	if parts.size() < 3:
		return false

	var key: String = parts[0]
	var op: String = parts[1]
	var raw_value: String = parts[2]

	# 先从 story variables 查，再从 game_state 查
	var actual: Variant = variables.get(key, game_state.get(key, null))
	if actual == null:
		return false

	var expected: Variant = _parse_value(raw_value)
	var actual_num: float = float(actual)
	var expected_num: float = float(expected)

	match op:
		"==":
			return str(actual) == str(expected)
		"!=":
			return str(actual) != str(expected)
		">=":
			return actual_num >= expected_num
		"<=":
			return actual_num <= expected_num
		">":
			return actual_num > expected_num
		"<":
			return actual_num < expected_num

	return false


func _parse_value(raw: String) -> Variant:
	if raw == "true":
		return true
	if raw == "false":
		return false
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	return raw
