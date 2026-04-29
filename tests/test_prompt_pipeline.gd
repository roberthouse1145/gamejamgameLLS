extends Node
const PromptPipelineScript = preload("res://scripts/prompt/prompt_pipeline.gd")
const LoreSystemScript = preload("res://scripts/chat/lore/lore_system.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager == null:
		print("[TEST] ERROR: PromptManager not found")
		return

	_test_no_lore()
	_test_browser_lore()
	_test_avg_lore()
	_test_chat_lore_expansion()
	_test_comment_strips_thinking_prompts(prompt_manager)


func _assert_true(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("[TEST][PASS] %s" % label)
		return
	push_error("[TEST][FAIL] %s :: %s" % [label, detail])


func _test_no_lore() -> void:
	var result := PromptPipelineScript.build_prompt(
		"chat_demo",
		{"name": "pipeline"},
		{"lore_mode": "none"}
	)
	var prompt: String = str(result.get("prompt", ""))
	print("[TEST] PromptPipeline none: has_prompt=%s" % str(not prompt.is_empty()))


func _test_browser_lore() -> void:
	var result := PromptPipelineScript.build_prompt(
		"browser_webpage",
		{},
		{
			"lore_mode": "browser",
			"lore_args": {
				"url": "gamejam://forum/theme",
				"design_prompt": "theme discussion page",
				"page_context": "ARCADE GRAND JAM 2025 rules discussion",
			},
		}
	)
	var lore_payload: Dictionary = result.get("lore_payload", {})
	print("[TEST] PromptPipeline browser: prompt=%d facts=%d constraints=%d" % [
		str(result.get("prompt", "")).length(),
		lore_payload.get("facts", []).size(),
		lore_payload.get("constraints", []).size(),
	])


func _test_avg_lore() -> void:
	var result := PromptPipelineScript.build_prompt(
		"date_scene_normal",
		{
			"date_scene_location": "Location: campus mall",
			"date_scene_activity": "Walk through stores and check game merchandise.",
			"date_scene_time": "Current time: competition day 12, afternoon.",
			"date_scene_state": "They are a college couple under recent GameJam pressure.",
			"date_scene_history": "Recent dates were quiet, avoid repeating them.",
			"lore_facts": "",
			"lore_constraints": "",
		},
		{
			"lore_mode": "avg",
			"lore_args": {
				"session": {
					"location": {
						"title": "Campus Mall",
						"subtitle": "A mid-size commercial complex",
						"description": "Close to school and good for a relaxed walk.",
						"detail_prompt": "Includes a game store and dessert shop.",
					},
					"activity_variant": "Browse merchandise and wander around",
					"event_seed": "Saw a competition promo screen near the game store",
				},
			},
		}
	)
	var lore_payload: Dictionary = result.get("lore_payload", {})
	print("[TEST] PromptPipeline avg: prompt=%d facts=%d constraints=%d" % [
		str(result.get("prompt", "")).length(),
		lore_payload.get("facts", []).size(),
		lore_payload.get("constraints", []).size(),
	])


func _test_chat_lore_expansion() -> void:
	var university_result := LoreSystemScript.resolve_chat(
		null,
		[],
		[],
		["蓝鲸大学最近怎么样"],
		null
	)
	var university_expanded: Array = university_result.get("expanded_ids", [])
	_assert_true(
		"蓝鲸大学可闭包扩展到澜京",
		university_expanded.has("geo_city_lanjing"),
		"expected expanded_ids to contain geo_city_lanjing, got %s" % [str(university_expanded)]
	)

	var apartment_result := LoreSystemScript.resolve_chat(
		null,
		[],
		[],
		["公寓离学校多远"],
		null
	)
	var apartment_expanded: Array = apartment_result.get("expanded_ids", [])
	_assert_true(
		"公寓可链式扩展到学校",
		apartment_expanded.has("geo_university_lanjing"),
		"expected expanded_ids to contain geo_university_lanjing, got %s" % [str(apartment_expanded)]
	)
	_assert_true(
		"公寓可链式扩展到澜京",
		apartment_expanded.has("geo_city_lanjing"),
		"expected expanded_ids to contain geo_city_lanjing, got %s" % [str(apartment_expanded)]
	)


func _test_comment_strips_thinking_prompts(prompt_manager: Node) -> void:
	var linkchat_prompt: String = str(prompt_manager.call("resolve_with_vars", "linkchat_system", {
		"player_identity": "测试玩家",
		"game_time": "Day 1 夜晚",
		"chat_history": "",
		"memories": "",
		"project_shared_context": "",
		"lore_facts": "",
		"lore_constraints": "",
		"topic": "",
		"topic_complete_hint": "",
		"speaker_ids": "npc_lin_xia",
		"characters": "",
	}))
	_assert_true("LinkChat prompt strips thinking block", not linkchat_prompt.contains("<thinking>"), linkchat_prompt)
	_assert_true("LinkChat prompt strips comment tag", not linkchat_prompt.contains("<注释>"), linkchat_prompt)

	var dsl_prompt: String = str(prompt_manager.call("resolve_with_vars", "story_scene_dsl_preview", {
		"story_scene_prompt": "测试剧情",
		"story_scene_context": "",
		"story_scene_history": "",
		"story_scene_project_context": "",
		"lore_facts": "",
		"lore_constraints": "",
	}))
	_assert_true("DSL preview prompt strips thinking block", not dsl_prompt.contains("<thinking>"), dsl_prompt)
	_assert_true("DSL preview prompt strips comment tag", not dsl_prompt.contains("<注释>"), dsl_prompt)
	_assert_true("DSL preview prompt keeps reasoning policy", dsl_prompt.contains("不要在 reasoning 中写完整 DSL"), dsl_prompt)
	_assert_true("DSL preview prompt bans reasoning dialogue draft", dsl_prompt.contains("不要在 reasoning 中逐句预演对白"), dsl_prompt)
