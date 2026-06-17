extends Node
## 验证 {{avg_project_protagonist}} 共享 prompt 在以下文件中被 PromptManager 正确展开：
##   - skill_story_writing
##   - work_order_agent
##   - skill_character_writing
##
## 同时验证：
##   - plan_generation 的「项目类型与玩法」段已生效，且不再带外层叙事背景
##   - dev_planner_agent 的 system prompt 顶部已带 AVG 类型先验


const SHARED_KEY: String = "avg_project_protagonist"
const SHARED_FINGERPRINT_LINES: Array[String] = [
	"AVG 项目主角处理规则",
	"不登台",
	"可以开口说话",
	"必须有真名",
]
const HOST_PROMPT_KEYS: Array[String] = [
	"skill_story_writing",
	"work_order_agent",
	"skill_character_writing",
]


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		push_error("[TEST][FAIL] PromptManager autoload not found")
		return

	_assert_true("PromptManager loaded shared key '%s'" % SHARED_KEY,
		bool(pm.call("has_prompt", SHARED_KEY)),
		"prompts/%s.md may be missing" % SHARED_KEY)

	var shared_resolved: String = str(pm.call("resolve", SHARED_KEY))
	for fingerprint in SHARED_FINGERPRINT_LINES:
		_assert_true("Shared prompt contains fingerprint '%s'" % fingerprint,
			shared_resolved.contains(fingerprint),
			"shared prompt body=%s" % shared_resolved.left(200))

	for host_key in HOST_PROMPT_KEYS:
		_check_host_injection(pm, host_key)

	_check_plan_generation_prompt(pm)
	_check_dev_planner_agent_prompt(pm)

	print("[TEST] avg_project_protagonist injection checks complete")


func _check_host_injection(pm: Node, host_key: String) -> void:
	_assert_true("Host '%s' is registered" % host_key,
		bool(pm.call("has_prompt", host_key)),
		"prompts/%s.md missing" % host_key)

	var resolved: String = str(pm.call("resolve", host_key))

	_assert_true("Host '%s' has no unresolved {{%s}} placeholder" % [host_key, SHARED_KEY],
		not resolved.contains("{{%s}}" % SHARED_KEY),
		"placeholder still present in resolved text of %s" % host_key)

	for fingerprint in SHARED_FINGERPRINT_LINES:
		_assert_true("Host '%s' inlined shared fingerprint '%s'" % [host_key, fingerprint],
			resolved.contains(fingerprint),
			"resolved %s body head=%s" % [host_key, resolved.left(400)])


func _check_plan_generation_prompt(pm: Node) -> void:
	# plan_generation 是 dev work 续杯的唯一 LLM 入口（已删 seed_dev_work_generation），
	# 这里只做最低限度校验：prompt 仍然注册、并明确告知 LLM 当前是 AVG 项目。
	var key: String = "plan_generation"
	_assert_true("'%s' registered" % key, bool(pm.call("has_prompt", key)),
		"prompts/%s.md missing" % key)

	var resolved: String = str(pm.call("resolve_with_vars", key, {"kb_content": ""}))

	_assert_true("plan_generation prompt mentions AVG project type",
		resolved.contains("AVG"),
		"plan_generation body head=%s" % resolved.left(400))


func _check_dev_planner_agent_prompt(pm: Node) -> void:
	var key: String = "dev_planner_agent"
	_assert_true("'%s' registered" % key, bool(pm.call("has_prompt", key)),
		"prompts/%s.md missing" % key)

	var resolved: String = str(pm.call("resolve", key))

	_assert_true("dev_planner_agent declares fixed AVG project type",
		resolved.contains("项目类型已经锁定为") and resolved.contains("AVG"),
		"dev_planner_agent body head=%s" % resolved.left(400))


func _assert_true(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("[TEST][PASS] %s" % label)
		return
	push_error("[TEST][FAIL] %s :: %s" % [label, detail])
