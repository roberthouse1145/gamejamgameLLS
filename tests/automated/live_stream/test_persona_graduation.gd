extends Node
## 毕业转生（策划案 §4.10）：残留规则、门控与状态切换的稳定契约。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")


func _ready() -> void:
	var manager: Node = get_node_or_null("/root/LiveStreamManager")
	assert(manager != null)

	# --- GameState 门控 ---
	assert(not GameState.graduation_transform("", 0.0, 0.0), "empty target must fail")
	assert(not GameState.graduation_transform(GameState.active_persona_id, 0.0, 0.0), "self switch must fail")

	# --- 残留规则：r×0.5 / m·w×0.2 / c 0.1 认出来 + 0.3 回踩 / b×0.5 跟随 ---
	GameState.fans = 10000
	GameState.set_fan_vector({"r": 40.0, "m": 30.0, "w": 10.0, "c": 15.0, "b": 5.0})
	var old_persona: String = GameState.active_persona_id
	var switched_to: Array[String] = []
	GameState.persona_changed.connect(func(_old: String, new_id: String) -> void:
		switched_to.append(new_id)
	)
	assert(GameState.graduation_transform("persona_second", 12.0, 3.0))
	assert(GameState.active_persona_id == "persona_second")
	assert(old_persona in GameState.graduated_personas)
	assert(switched_to == ["persona_second"])
	assert(not GameState.graduation_transform("persona_second", 0.0, 0.0), "graduated persona must not be playable again")
	assert(not GameState.graduation_transform(old_persona, 0.0, 0.0), "graduated target must fail")

	# 期望残留：r=40×0.5=20, m=30×0.2=6, w=10×0.2=2, c=15×0.1=1.5, b=5×0.5+15×0.3=7 → 总和 36.5
	var retained: float = 36.5
	var vector: Dictionary = GameState.fan_vector
	assert(is_equal_approx(float(vector["r"]), 20.0 / retained * 100.0))
	assert(is_equal_approx(float(vector["m"]), 6.0 / retained * 100.0))
	assert(is_equal_approx(float(vector["w"]), 2.0 / retained * 100.0))
	assert(is_equal_approx(float(vector["c"]), 1.5 / retained * 100.0))
	assert(is_equal_approx(float(vector["b"]), 7.0 / retained * 100.0))
	assert(GameState.fans == int(round(10000.0 * retained / 100.0)), "total fans must shrink by retained fraction")
	var progress: Dictionary = GameState.persona_progress.get("persona_second", {})
	assert(progress.get("proficiency") == 12.0 and progress.get("fixation") == 3.0, "new persona starts at initial values")

	# --- LiveStreamManager.perform_graduation 门控与落账 ---
	var second := StreamPersonaResource.new()
	second.content_id = &"persona_test_second"
	second.display_name = "测试二号"
	CATALOG.personas.append(second)

	assert(not manager.perform_graduation(&"persona_missing"), "unknown persona must fail")
	assert(not manager.perform_graduation(&"persona_second"), "graduated persona must fail")
	assert(not manager.perform_graduation(StringName(GameState.active_persona_id)), "self switch must fail")
	assert(manager.perform_graduation(&"persona_test_second"))
	assert(GameState.active_persona_id == "persona_test_second")
	assert(manager.get_draft().get("persona_id") == GameState.active_persona_id, "draft persona must follow the active persona")
	assert(manager.perform_graduation(&"persona_test_second") == false, "graduated persona must not be playable again")
	print("PERSONA_GRADUATION_TEST_PASS")
