extends Node
## 真实 LLM 逐拍联调入口：用正式卡池跑一遍导演，统计 LLM 命中率与兜底率。
## 需要已配置 API；未配置时全部走兜底，同样会输出统计。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")

var _director: StreamShowDirector = null
var _beats_seen: Array[Dictionary] = []
var _reported: bool = false


func _ready() -> void:
	var opening: BehaviorCardResource = _find_card(true)
	var middle: BehaviorCardResource = _find_card(false)
	if opening == null or middle == null:
		print("LAB_LIVE_BEAT_DONE error=卡池缺少可用行为卡")
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"lab_live_beat"
	plan.title = "【联调】今天也来杂谈回"
	plan.persona_id = CATALOG.personas[0].content_id if not CATALOG.personas.is_empty() else &""
	plan.behavior_card_ids = [opening.content_id, middle.content_id]
	plan.rng_seed = 20260806
	plan.state_snapshot = {
		"skill_levels": {"game": 1, "talk": 2, "song": 1, "act": 1, "tech": 1},
		"stress": 45,
		"otaku_desire": 60,
		"loneliness": 30,
		"fans": 1200,
		"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
		"material_instance": {
			"definition_id": String(CATALOG.materials[0].content_id) if not CATALOG.materials.is_empty() else "",
			"depth": 4.0,
			"freshness": 1.0,
		},
	}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, CATALOG, BALANCE)

	_director = StreamShowDirector.new()
	_director.llm_enabled = true
	_director.beat_interval = 1.0
	add_child(_director)
	_director.setup(plan, result, CATALOG)
	_director.beat_started.connect(_on_beat_started)
	_director.show_finished.connect(_on_show_finished)
	print("LAB_LIVE_BEAT_START beats=%d" % _director.get_beat_count())
	_director.start()


func _process(_delta: float) -> void:
	if _reported or _beats_seen.size() < _director.get_beat_count() or _beats_seen.is_empty():
		return
	_reported = true
	var llm_count: int = 0
	var fallback_count: int = 0
	for beat: Dictionary in _beats_seen:
		var line: String = String(beat.get("line", ""))
		var from_fallback: bool = false
		for pool: Array in StreamShowDirector.FALLBACK_LINES.values():
			if line in pool:
				from_fallback = true
				break
		if from_fallback:
			fallback_count += 1
		else:
			llm_count += 1
		print("LAB_BEAT %d %s emotion=%s danmaku=%d line=%s" % [
			int(beat.get("index", -1)),
			String(beat.get("card_name", "")),
			String(beat.get("emotion", "")),
			(beat.get("danmaku", []) as Array).size(),
			line,
		])
	print("LAB_LIVE_BEAT_DONE llm=%d fallback=%d" % [llm_count, fallback_count])


func _on_beat_started(beat: Dictionary) -> void:
	_beats_seen.append(beat)


func _on_show_finished() -> void:
	pass


func _find_card(want_opening: bool) -> BehaviorCardResource:
	for card: BehaviorCardResource in CATALOG.behavior_cards:
		if card == null:
			continue
		if want_opening and card.is_opening_card():
			return card
		if not want_opening and not card.is_opening_card() and not card.is_closing_card():
			return card
	return null
