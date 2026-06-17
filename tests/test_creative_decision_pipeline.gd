extends Control
## creative_decision 结果整理链路的轻量验证。
##
## 只验证同步 helper：提案 DSL 新字段、工单 brief JSON、最终 result payload。

const CreativeDecisionScript = preload("res://scripts/minigame/creative_decision.gd")

var _failures: int = 0


func _ready() -> void:
	_run_tests()


func _run_tests() -> void:
	var game = CreativeDecisionScript.new()
	add_child(game)

	var proposal: Dictionary = game._parse_proposal_response("\n".join([
		"title: 钟塔争执",
		"summary: 以互相揭穿制造关系反转",
		"core: 阿尔诺揭穿赛琳也查过钟塔",
		"node: 赛琳先质问",
		"node: 阿尔诺反击",
		"node: 钟塔回响打断",
		"decision: 结尾不直接和好",
		"locked: 不和好",
	]))
	_expect("proposal summary parsed", str(proposal.get("summary", "")) == "以互相揭穿制造关系反转")
	_expect("proposal decisions parsed", (proposal.get("decisions", []) as Array).size() == 1)

	var brief: String = game._parse_work_order_brief_response(JSON.stringify({
		"summary": "把钟塔争执写成互相揭穿的反转戏。",
		"deliverables": ["补完争执戏节拍", "保留关系裂缝"],
		"constraints": ["不能直接和好"],
		"evidence": ["玩家和林夏敲定反转点"],
		"risks_open_questions": [],
	}))
	_expect("brief formatted", brief.contains("## 交付物") and brief.contains("补完争执戏节拍"))

	game._goal_description = "敲定钟塔争执戏"
	game._discussion_state = "settled"
	game._round = 2
	game._current_proposal = proposal
	var conversation: Array[Dictionary] = [
		{"round": 1, "speaker": "linxia", "text": "我们先保留冲突。"},
		{"round": 2, "speaker": "player", "text": "让阿尔诺反过来揭穿赛琳。"},
	]
	game._conversation = conversation
	game._work_order_brief_text = brief
	var payload: Dictionary = game._build_summary_payload()
	var result: Dictionary = payload.get("result", {})
	_expect("work_order_brief present", str(result.get("work_order_brief", "")).contains("## 讨论结论"))
	_expect("creative_prompt uses brief", str(result.get("creative_prompt", "")) == str(result.get("work_order_brief", "")))
	_expect("proposal_document present", str(result.get("proposal_document", "")).contains("summary: 以互相揭穿制造关系反转"))

	if _failures == 0:
		print("[TestCreativeDecisionPipeline] PASS")
	else:
		push_error("[TestCreativeDecisionPipeline] FAIL count=%d" % _failures)


func _expect(label: String, passed: bool) -> void:
	if passed:
		print("[PASS] %s" % label)
		return
	_failures += 1
	push_error("[FAIL] %s" % label)
