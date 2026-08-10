extends Node
## Chat 与直播 DSL 共用同一份内容密度和节奏约束。

var _failures: int = 0


func _ready() -> void:
	var shared: String = PromptManager.resolve("dsl_generation_pacing")
	_check(shared.contains("最短可播放链路"), "共享节奏模板已加载")
	_check(shared.contains("角色性格通过用词、句式和一次直接反应体现"), "性格不会被解释为额外篇幅")
	_check(shared.contains("目标或结果已经明确后"), "共享模板要求结果明确后推进或结束")

	var chat_prompt: String = PromptManager.resolve_with_vars("chat_dsl_generator", {
		"topic_prompt": "完成一次简短确认。",
		"allowed_speakers": "friend\nplayer",
		"allowed_variable_paths": "",
		"runtime_context": "{}",
	})
	_check(chat_prompt.contains("最短可播放链路"), "Chat DSL 注入共享节奏模板")
	_check(chat_prompt.contains("通常使用 4～8 个消息气泡"), "Chat DSL 默认采用紧凑气泡数量")
	_check(chat_prompt.contains("目标达成后立即 `END`"), "Chat DSL 明确结束时机")

	var live_prompt: String = PromptManager.resolve_with_vars("live_stream/live_show", {
		"expression_list": "default",
		"posture_list": "idle",
		"arm_pose_list": "default",
		"head_pose_list": "default",
		"gesture_list": "wave",
		"persona_block": "测试主播",
		"stream_title": "测试直播",
		"stream_count": "1",
		"fans": "0",
		"state_block": "平稳",
		"material_block": "测试素材",
		"program_block": "- 测试节目",
		"outcome_block": "平稳完成",
	})
	_check(live_prompt.contains("最短可播放链路"), "直播 DSL 注入共享节奏模板")
	_check(live_prompt.contains("每个重点段落使用 2 至 4 条 `say`"), "直播段落限制内容密度")
	_check(live_prompt.contains("一个互动闭环"), "直播互动完成一次闭环后推进")

	if _failures == 0:
		print("[PASS] dsl generation pacing prompts")
	else:
		push_error("[FAIL] dsl generation pacing prompts: %d checks failed" % _failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)
