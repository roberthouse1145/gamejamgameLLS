extends Node

const PromptBuilderClass = preload("res://scripts/avg/generation/avg_scene_prompt_builder.gd")


func _ready() -> void:
	var builder := PromptBuilderClass.new()
	var prompt := builder.build_prompt_from_session({
		"title": "示例场景",
		"scene_prompt": "生成一段最短可播放场景。",
		"setting_context": "只使用调用方显式提供的设定。",
		"constraints": "以场景目标完成结束。",
	})
	_assert(prompt.contains("## 场景标题\n示例场景"), "title is included")
	_assert(prompt.contains("## 场景需求"), "scene brief is included")
	_assert(prompt.contains("## 角色与世界设定"), "setting context is included")
	_assert(prompt.contains("## 演出约束"), "constraints are included")
	_assert(builder.build_prompt_from_session({}).is_empty(), "empty input does not invent a scene")


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		push_error("[FAIL] %s" % message)
