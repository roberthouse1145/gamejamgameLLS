extends Node
## repair 通过后的 DSL 必须走与首次生成成功相同的 show_ready 交付路径。

const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")
const MODEL: StreamerModelResource = preload("res://resources/live_stream/models/platinum.tres")


func _ready() -> void:
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"repair_delivery_test"
	plan.title = "修复交付测试"

	var generator: LiveShowGenerator = GENERATOR_SCRIPT.new()
	generator.summary_enabled = false
	add_child(generator)
	generator.setup(plan, null, null, MODEL)
	var received_shows: Array[Dictionary] = []
	generator.show_ready.connect(func(show: Dictionary) -> void: received_shows.append(show))

	var repaired_dsl := "\n".join([
		"expression: smile",
		"say: 晚上好，修复后的直播内容已经收到。",
		"chat: 收到了 | 可以正常播放",
	])
	generator.set("_repair_session_id", plan.session_id)
	generator._on_repair_completed(plan.session_id, repaired_dsl)

	assert(received_shows.size() == 1, "validated repair result must emit show_ready exactly once")
	assert(received_shows[0].get("dsl_text", "") == repaired_dsl, "show_ready must carry the repaired DSL")
	assert((received_shows[0].get("ops", []) as Array).size() == 3, "repaired DSL must be compiled before delivery")
	print("LIVE_DSL_REPAIR_DELIVERY_TEST_PASS")
