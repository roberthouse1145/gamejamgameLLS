extends Node
## LoreSystem 只按显式元数据选择内容，并保持分组、预算和关系扩展契约。

const LoreSystemClass = preload("res://scripts/avg/generation/lore_system.gd")
const FIXTURE_INDEX: String = "res://tests/automated/avg/fixtures/test_lore_index.txt"

var _failures: int = 0


func _ready() -> void:
	_test_context_selection()
	_test_prompt_block()
	if _failures == 0:
		print("[PASS] lore system")
	else:
		push_error("[FAIL] lore system: %d checks failed" % _failures)


func _test_context_selection() -> void:
	var result: Dictionary = LoreSystemClass.resolve_context({
		"generation_type": "avg",
		"scan_text": "A quiet scene beside the riverside path.",
		"character_ids": ["traveler"],
	}, FIXTURE_INDEX, true)
	var facts: Array[String] = []
	facts.assign(result.get("facts", []))
	var constraints: Array[String] = []
	constraints.assign(result.get("constraints", []))
	var matched_ids: Array[String] = []
	matched_ids.assign(result.get("matched_ids", []))
	var skipped_by_group: Array[String] = []
	skipped_by_group.assign(result.get("skipped_by_group", []))

	_check(matched_ids.has("place_river"), "matching fact is selected")
	_check(matched_ids.has("place_district"), "allowed relation expands a selected fact")
	_check(matched_ids.has("river_rule"), "matching constraint is selected")
	_check(skipped_by_group.has("place_river_old"), "lower-priority entry in the same group is skipped")
	_check(not matched_ids.has("mountain_note"), "unmatched keyword entry is not injected")
	_check(facts.size() == 2, "fact and related expansion are returned")
	_check(constraints.size() == 1, "constraint is kept separate from facts")


func _test_prompt_block() -> void:
	var block: String = LoreSystemClass.build_prompt_block(["First fact", "", "Second fact"])
	_check(block == "- First fact\n- Second fact", "prompt block preserves selected content order")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)
