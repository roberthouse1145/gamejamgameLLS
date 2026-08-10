extends Node
## 直播标题中途生成链路：严格校验模型输出，以及 LLM 不可用时明确失败。

const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")

var _title_seen: String = ""


func _ready() -> void:
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"title_test"
	plan.title = "已有直播标题"

	var generator: Node = GENERATOR_SCRIPT.new()
	generator.llm_enabled = false
	add_child(generator)
	generator.setup(plan, null, null, null)
	generator.title_ready.connect(_on_title_ready)
	var show_ready: Array = []
	var generation_failures: Array[String] = []
	generator.show_ready.connect(func(ready_show: Dictionary) -> void: show_ready.append(ready_show))
	generator.generation_failed.connect(func(reason: String) -> void: generation_failures.append(reason))
	generator.generate()
	assert(_title_seen.is_empty(), "disabled LLM should not synthesize a replacement title")
	assert(show_ready.is_empty(), "disabled LLM must not produce a local template show")
	assert(generation_failures == ["llm_disabled"], "disabled LLM should report an explicit failure")
	assert(plan.title == "已有直播标题", "the existing plan title should remain unchanged")

	var valid_title: Dictionary = generator._validate_title("神作终章！最终 BOSS 决战")
	assert(bool(valid_title.get("success", false)), "a compliant title should pass unchanged")
	assert(valid_title.get("title") == "神作终章！最终 BOSS 决战", "validation must preserve compliant title text")
	assert(not bool(generator._validate_title("第一行\n额外解释").get("success", true)), "multi-line output must fail instead of keeping the first line")
	assert(not bool(generator._validate_title("\"带引号的标题\"").get("success", true)), "quoted output must fail instead of stripping quotation marks")
	assert(not bool(generator._validate_title("").get("success", true)), "empty title must fail validation")
	assert(
		not bool(generator._validate_title("长".repeat(49)).get("success", true)),
		"overlong title must fail instead of being truncated"
	)

	var invalid_plan := StreamPlanSnapshot.new()
	invalid_plan.title = "保留原题"
	var invalid_generator: Node = GENERATOR_SCRIPT.new()
	add_child(invalid_generator)
	invalid_generator.setup(invalid_plan, null, null, null)
	var invalid_failures: Array[String] = []
	invalid_generator.generation_failed.connect(func(reason: String) -> void: invalid_failures.append(reason))
	invalid_generator._apply_title("第一行\n额外解释")
	assert(invalid_failures == ["invalid_title"], "invalid generated title should fail explicitly")
	assert(invalid_plan.title == "保留原题", "invalid generated title must not replace existing content")
	print("LIVE_TITLE_GENERATION_TEST_PASS")


func _on_title_ready(title: String) -> void:
	_title_seen = title
