extends Node
## 测试 DSLRepairAgent：构造含已知错误的 DSL，验证修复效果

const DSLRepairAgentClass = preload("res://scripts/activity/dsl_repair_agent.gd")
const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")

var _repair_agent: Node = null
var _parser: RefCounted = ParserClass.new()
var _validator: RefCounted = ValidatorClass.new()
var _test_running: bool = false


func _ready() -> void:
	_repair_agent = DSLRepairAgentClass.new()
	_repair_agent.name = "DSLRepairAgent"
	add_child(_repair_agent)

	_repair_agent.repair_completed.connect(_on_repair_completed)
	_repair_agent.repair_failed.connect(_on_repair_failed)

	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== DSL Repair Agent Test ===\n")

	# 等 autoload 就绪
	await get_tree().process_frame
	await get_tree().process_frame

	if not _repair_agent.is_available():
		print("[TEST] FAIL: Repair agent not available (check ai_config.cfg has dsl_repair role)")
		return

	print("[TEST] Repair agent is available")

	# 获取运行时项目（含角色/资源定义）
	var project: Resource = _get_runtime_project()
	if project == null:
		print("[TEST] FAIL: Cannot get runtime project. NarrativeProjectManager not ready?")
		return

	var project_root_path: String = _get_project_root_path()
	var asset_manifest: String = _get_asset_manifest()

	print("[TEST] Project loaded | characters=%d" % project.characters.size())
	print("[TEST] Asset manifest preview: %s..." % asset_manifest.left(200))

	# 构造含已知错误的 DSL：
	# 1. emotion "smile" 不存在（应为 happy/soft_smile 等）
	# 2. outfit "school" 不存在（应为 casual/loungewear/maid）
	# 3. background "bg_beach" 不存在
	# 4. sfx "sfx_door_open" 不存在（无 SFX 可用）
	var broken_dsl: String = """screen.fade(direction="in", duration=0.35)
bg.show("bg_beach")
LinXia.show(position="center", outfit="school", emotion="smile")
sfx.play("sfx_door_open")
# => TextBlock(speaker="LinXia", expression="smile")
> 今天天气真好呢！
LinXia.expression = "excited"
# => TextBlock(speaker="LinXia", expression="excited")
> 我们去哪里玩好呢？
# => ChoiceBlock()
- 去公园散步
    LinXia.expression = "happy"
    # => TextBlock(speaker="LinXia", expression="happy")
    > 好呀，公园听起来不错！
- 去咖啡馆坐坐
    LinXia.expression = "soft_smile"
    # => TextBlock(speaker="LinXia", expression="soft_smile")
    > 咖啡馆也好，可以聊聊天。
""".strip_edges()

	print("\n[TEST] === BROKEN DSL ===")
	print(broken_dsl)
	print("[TEST] === END BROKEN DSL ===\n")

	# 先验证，确认确实有错
	var validation: Dictionary = _validate_dsl(broken_dsl, project, project_root_path)

	if bool(validation.get("ok", false)):
		print("[TEST] WARN: DSL passed validation unexpectedly. Test may not be useful.")
		return

	print("[TEST] Validation errors found:")
	for error in validation.get("errors", []):
		print("  - %s" % str(error))

	# 启动修复
	print("\n[TEST] Starting repair...")
	_test_running = true
	_repair_agent.attempt_repair(
		"test_repair_001",
		broken_dsl,
		validation,
		project,
		project_root_path,
		asset_manifest,
	)


func _on_repair_completed(session_id: String, repaired_dsl: String) -> void:
	if not _test_running:
		return
	_test_running = false

	print("\n[TEST] === REPAIR COMPLETED ===")
	print("[TEST] Session: %s" % session_id)
	print("\n[TEST] === REPAIRED DSL ===")
	print(repaired_dsl)
	print("[TEST] === END REPAIRED DSL ===\n")

	# 最终验证
	var project: Resource = _get_runtime_project()
	var final_validation: Dictionary = _validate_dsl(repaired_dsl, project, _get_project_root_path())
	if bool(final_validation.get("ok", false)):
		print("[TEST] PASS: Repaired DSL passes validation!")
	else:
		print("[TEST] FAIL: Repaired DSL still has errors:")
		for error in final_validation.get("errors", []):
			print("  - %s" % str(error))


func _on_repair_failed(session_id: String, error: String) -> void:
	if not _test_running:
		return
	_test_running = false

	print("\n[TEST] === REPAIR FAILED ===")
	print("[TEST] Session: %s" % session_id)
	print("[TEST] Error: %s" % error)


func _validate_dsl(dsl_text: String, project: Resource, project_root_path: String) -> Dictionary:
	var parse_result: Dictionary = _parser.parse(dsl_text)
	if not bool(parse_result.get("success", false)):
		var errors: Array = parse_result.get("errors", [])
		var first: String = "parse_failed"
		if not errors.is_empty() and errors[0] is Dictionary:
			first = "line %d: %s" % [int(errors[0].get("line", 0)), str(errors[0].get("message", ""))]
		return {"ok": false, "summary": first, "errors": [first]}

	var commands: Array = parse_result.get("commands", [])
	var semantic: Dictionary = _validator.validate_commands(
		commands, project, project_root_path,
		{"min_choice_count": 0, "max_choice_count": 0},
	)
	if not bool(semantic.get("ok", false)):
		return {
			"ok": false,
			"summary": str(semantic.get("summary", "")),
			"errors": semantic.get("errors", []),
		}
	return {"ok": true, "summary": "ok", "commands": commands, "errors": []}


func _get_runtime_project() -> Resource:
	var npm: Node = get_node_or_null("/root/NarrativeProjectManager")
	if npm != null and npm.has_method("duplicate_current_project"):
		return npm.duplicate_current_project()
	return null


func _get_project_root_path() -> String:
	var npm: Node = get_node_or_null("/root/NarrativeProjectManager")
	if npm != null:
		return str(npm.get("current_project_path")).strip_edges()
	return ""


func _get_asset_manifest() -> String:
	var npm: Node = get_node_or_null("/root/NarrativeProjectManager")
	if npm != null and npm.has_method("build_asset_prompt"):
		return str(npm.build_asset_prompt()).strip_edges()
	return "No asset manifest available."
