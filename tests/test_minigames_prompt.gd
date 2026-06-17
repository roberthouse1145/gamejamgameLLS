extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		push_error("[TEST] PromptManager not found")
		return
	var mm: Node = get_node_or_null("/root/MinigameManager")
	if mm == null:
		push_error("[TEST] MinigameManager not found")
		return

	# 1. provider 直接调用
	var summary: String = mm.get_prompt_summary()
	print("=== get_prompt_summary() ===")
	print(summary)
	_assert("contains 产出型 header", summary.contains("### 产出型"))
	_assert("contains 氛围型 header", summary.contains("### 氛围型"))
	_assert("lists creative_decision", summary.contains("creative_decision"))
	_assert("lists script_fill", summary.contains("script_fill"))
	_assert("lists typing_code", summary.contains("typing_code"))
	_assert("lists find_bugs", summary.contains("find_bugs"))
	_assert("lists code_puzzle", summary.contains("code_puzzle"))
	_assert("lists emotion_tag", summary.contains("emotion_tag"))

	# 2. PromptManager 通过 provider 解析
	# 新分工：minigame 目录仅在 system prompt（dev_planner_agent）中出现，
	# plan_generation（user turn）只负责战术规则与节奏，不再重复目录。
	var resolved_dev: String = pm.resolve("dev_planner_agent")
	print("=== resolve(dev_planner_agent) ===")
	print(resolved_dev)
	_assert("dev_planner_agent has 产出型", resolved_dev.contains("### 产出型"))
	_assert("dev_planner_agent has 氛围型", resolved_dev.contains("### 氛围型"))
	_assert("dev_planner_agent placeholder consumed", not resolved_dev.contains("{{minigames_prompt}}"))
	_assert("dev_planner_agent exposes work_order policy", resolved_dev.contains("工单策略"))
	_assert("dev_planner_agent has independence test", resolved_dev.contains("独立性测试"))

	var resolved_plan: String = pm.resolve("plan_generation")
	print("=== resolve(plan_generation) head ===")
	print(resolved_plan.substr(0, mini(2000, resolved_plan.length())))
	_assert("plan_generation no catalog duplication (产出型 header absent)", not resolved_plan.contains("### 产出型（玩家输入会成为"))
	_assert("plan_generation placeholder absent", not resolved_plan.contains("{{minigames_prompt}}"))
	_assert("plan_generation 节奏循环 retained", resolved_plan.contains("节奏循环"))
	_assert("plan_generation 选择规则 retained", resolved_plan.contains("选择规则"))
	_assert("plan_generation has workorder-first ordering", resolved_plan.contains("工单为本"))
	_assert("plan_generation has independence test", resolved_plan.contains("独立性测试"))

	print("[TEST] done. waiting (no auto-quit).")


func _assert(label: String, cond: bool) -> void:
	if cond:
		print("[TEST][PASS] %s" % label)
	else:
		push_error("[TEST][FAIL] %s" % label)
