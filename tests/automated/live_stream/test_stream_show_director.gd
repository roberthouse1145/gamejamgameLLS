extends Node
## 逐拍导演契约：节拍序列、模板兜底、播放节奏与跳过。

var _director: StreamShowDirector = null
var _started_beats: Array[Dictionary] = []
var _first_resolved: bool = false
var _finished: bool = false
var _skip_director: StreamShowDirector = null
var _skip_finished: bool = false
var _reported: bool = false


func _ready() -> void:
	var catalog := LiveStreamCatalog.new()
	var balance := LiveStreamBalance.new()
	var material := _make_material()
	var persona := StreamPersonaResource.new()
	persona.content_id = &"persona_test"
	persona.display_name = "测试人设"
	var opening: BehaviorCardResource = _make_card(&"opening_a", [], [1, 3], &"game")
	var middle: BehaviorCardResource = _make_card(&"middle_b", [1, 2], [2, 4], &"talk")
	var closing: BehaviorCardResource = _make_card(&"closing_c", [2, 4], [], &"song")
	catalog.behavior_cards = [opening, middle, closing]
	catalog.materials = [material]
	catalog.personas = [persona]

	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"director_test"
	plan.title = "导演测试直播"
	plan.persona_id = &"persona_test"
	plan.material_instance_id = &"material_instance_test"
	plan.behavior_card_ids = [&"opening_a", &"", &"middle_b", &"closing_c"]
	plan.rng_seed = 314159
	plan.state_snapshot = {
		"skill_levels": {"game": 1, "talk": 1, "song": 1, "act": 1, "tech": 1},
		"stress": 0,
		"otaku_desire": 0,
		"loneliness": 0,
		"fans": 0,
		"fan_vector": {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0},
		"material_instance": {"definition_id": "material_test", "depth": 4.0, "freshness": 1.0},
	}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, catalog, balance)

	_director = StreamShowDirector.new()
	_director.llm_enabled = false
	_director.beat_interval = 0.1
	_director.fast_interval = 0.05
	add_child(_director)
	_director.setup(plan, result, catalog)

	assert(_director.get_beat_count() == 5, "beats = 非空卡槽 3 + 开场 + 收尾")
	var kinds: Array = _director.get_beats().map(func(beat: Dictionary) -> StringName: return beat.get("kind"))
	assert(kinds == [
		StreamShowDirector.KIND_OPENING, StreamShowDirector.KIND_CARD,
		StreamShowDirector.KIND_CARD, StreamShowDirector.KIND_CARD,
		StreamShowDirector.KIND_CLOSING,
	], "空槽必须被节拍序列跳过")
	assert(String(_director.get_beats()[2].get("card_id")) == "middle_b")
	assert(int(_director.get_beats()[2].get("slot_index")) == 2, "节拍必须保留原槽位编号")
	assert(is_equal_approx(float(_director.get_beats()[2].get("fill_ratio")), 0.5), "填充率必须来自预结算 interface_trace")

	_director.beat_started.connect(_on_beat_started)
	_director.first_beat_resolved.connect(func() -> void: _first_resolved = true)
	_director.show_finished.connect(_on_show_finished)
	_director.start()


func _process(_delta: float) -> void:
	if _reported:
		return
	if _finished and _skip_director == null:
		_run_skip_test()
		return
	if _finished and _skip_finished:
		_reported = true
		assert(_first_resolved, "首拍就绪信号必须先于播放")
		assert(_started_beats.size() == 5, "所有节拍都必须播放")
		for beat: Dictionary in _started_beats:
			assert(not String(beat.get("line", "")).is_empty(), "兜底台词必须非空")
			assert(String(beat.get("emotion", "")) in StreamShowDirector.EMOTION_KEYS, "emotion 必须在词表内")
			assert((beat.get("danmaku", []) as Array).size() >= 1, "兜底弹幕必须非空")
		print("STREAM_SHOW_DIRECTOR_TEST_PASS")


func _on_beat_started(beat: Dictionary) -> void:
	_started_beats.append(beat)
	if _started_beats.size() == 2:
		_director.set_fast_forward(true)
	elif _started_beats.size() == 3:
		assert(_director._beat_timer.wait_time <= _director.fast_interval + 0.001, "快进必须缩短拍间隔")


func _on_show_finished() -> void:
	_finished = true


func _run_skip_test() -> void:
	var plan := StreamPlanSnapshot.new()
	plan.rng_seed = 7
	plan.behavior_card_ids = []
	plan.state_snapshot = {}
	_skip_director = StreamShowDirector.new()
	_skip_director.llm_enabled = false
	add_child(_skip_director)
	_skip_director.setup(plan, StreamSettlementResult.new(), LiveStreamCatalog.new())
	assert(_skip_director.get_beat_count() == 2, "无卡节目单也应保留开场与收尾")
	_skip_director.show_finished.connect(func() -> void: _skip_finished = true)
	_skip_director.start()
	_skip_director.skip()


func _make_card(card_id: StringName, left_slots: Array, right_slots: Array, family: StringName) -> BehaviorCardResource:
	var card := BehaviorCardResource.new()
	card.content_id = card_id
	card.display_name = String(card_id)
	card.family = family
	card.left_slots.assign(left_slots)
	card.right_slots.assign(right_slots)
	card.axes = StreamAxisValues.new()
	card.axes.quality = 2.0
	return card


func _make_material() -> LiveStreamMaterialResource:
	var material := LiveStreamMaterialResource.new()
	material.content_id = &"material_test"
	material.display_name = "测试素材"
	material.material_type = LiveStreamMaterialResource.TYPE_CONTINUOUS
	material.initial_depth = 4.0
	material.affinity = StreamFamilyValues.new()
	material.axes = StreamAxisValues.new()
	material.base_popularity = 100.0
	return material
