extends Control

const ScriptFillScene = preload("res://scenes/minigames/script_fill.tscn")


func _ready() -> void:
	print("[TestScriptFill] Starting script_fill minigame test...")

	var instance: Node = ScriptFillScene.instantiate()
	if instance == null:
		print("[TestScriptFill] ERROR: Failed to instantiate scene")
		return

	add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	instance.minigame_finished.connect(_on_finished)
	instance.minigame_cancelled.connect(_on_cancelled)
	instance.setup({
		"task_data": {
			"task_id": "test_script_fill",
			"title": "补完争执戏的关键台词",
			"description": "先把这场争执戏里最重要的几句补出来，让后续工单能够沿着你的输入继续细化。",
			"minigame_type": "script_fill",
			"post_task_work_order": {
				"kb_sources": ["characters", "story", "notes"],
			},
		},
		"minigame_type": "script_fill",
		"generated_content": {
			"scene_brief": "天台之上，少年和少女刚吵完一轮，可谁都没把真正的话说透。",
			"blocks": [
				{
					"type": "narration",
					"text": "天台上风很大，少女摸了一下肩上的伤。",
				},
				{
					"type": "dialogue",
					"speaker": "少女",
					"text": "「你下次还敢自己跑，我就不拦了。」",
				},
				{
					"type": "narration",
					"text": "少年没有回应，望着远处的楼顶。",
				},
				{
					"type": "dialogue",
					"speaker": "少女",
					"text": "「你倒是说句话啊。」",
				},
				{
					"type": "narration",
					"text": "她走近一步，语气变了。",
				},
				{
					"type": "dialogue",
					"speaker": "少女",
					"text": "「我拦你的时候磕了一下，你连看都不看。」",
				},
				{
					"type": "blank",
					"speaker": "少年",
					"hint": "关心 / 顶嘴 / 逼问",
					"suggestions": [
						"你的手怎么了？是拦我的时候磕的？",
						"那你就别拦啊，谁让你多管闲事。",
						"你到底在怕什么？",
					],
				},
				{
					"type": "narration",
					"text": "少女咬了一下嘴唇，低头看着自己的手。",
				},
				{
					"type": "stage_blank",
					"target": "少女",
					"hint": "心软 / 赌气 / 试探",
					"suggestions": [
						"攥紧了拳头又慢慢松开。",
						"偏过头去，不想让他看见自己的表情。",
						"往前走了一步，声音却先低了下来。",
					],
				},
				{
					"type": "dialogue",
					"speaker": "少女",
					"text": "「你管那叫有分寸？」",
				},
				{
					"type": "dialogue",
					"speaker": "少年",
					"text": "「我说了，你不用管我。」",
				},
				{
					"type": "narration",
					"text": "少女没有接话，风吹过天台，头发遮住了她的表情。",
				},
				{
					"type": "narration",
					"text": "很久之后。",
				},
				{
					"type": "dialogue",
					"speaker": "少女",
					"text": "「……我就是觉得，你至少应该说一声。」",
				},
				{
					"type": "narration",
					"text": "她的声音很轻，几乎被风吹散。",
				},
				{
					"type": "dialogue",
					"speaker": "少女",
					"text": "「每次都让人猜来猜去的……我也会累啊。」",
				},
				{
					"type": "blank",
					"speaker": "少年",
					"hint": "留白 / 认真 / 不服输",
					"suggestions": [
						"下次要跑，我会先告诉你。",
						"……反正我不会再让你一个人拦。",
						"剩下的话，等我想清楚再说。",
					],
				},
				{
					"type": "narration",
					"text": "少女听到他的声音，停下了脚步，但没有回头。",
				},
			],
		},
	})
	print("[TestScriptFill] Minigame started successfully!")


func _on_finished(result: Dictionary) -> void:
	print("[TestScriptFill] Minigame FINISHED!")
	print("[TestScriptFill]   score: %.2f" % float(result.get("score", 0.0)))
	print("[TestScriptFill]   filled_blanks: %d" % int(result.get("filled_blanks", result.get("filled_slots", 0))))
	print("[TestScriptFill]   blank_count: %d" % int(result.get("blank_count", result.get("slot_count", 0))))
	print("[TestScriptFill]   creative_prompt: %s" % str(result.get("creative_prompt", "")))


func _on_cancelled() -> void:
	print("[TestScriptFill] Minigame CANCELLED")
