extends Node
const PromptPipelineScript = preload("res://scripts/prompt/prompt_pipeline.gd")


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
