extends Node
## 真实 LLM 歌回表达实验：检查演唱是否由可说/可唱文本和弹幕呈现，而不是塞进 say 的括号旁白。

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")
const GENERATOR_SCRIPT = preload("res://scripts/game/live_stream/live_show_generator.gd")

const PERSONA_ID: StringName = &"persona_default"
const MATERIAL_ID: StringName = &"material_midnight_setlist"

var _generator: LiveShowGenerator = null


func _ready() -> void:
	var persona: StreamPersonaResource = CATALOG.get_persona(PERSONA_ID)
	var material: LiveStreamMaterialResource = CATALOG.get_material(MATERIAL_ID)
	if persona == null or material == null:
		print("LAB_SONG_DIALOGUE_ALL_DONE ok=0 error=missing_content")
		return
	var plan := StreamPlanSnapshot.new()
	plan.session_id = &"lab_song_dialogue"
	plan.title = material.display_name
	plan.persona_id = PERSONA_ID
	plan.approach = {"approach_id": "midnight_performance", "approach_type": "performance", "display_name": "唱到夜里慢慢暖起来", "display_description": "让歌声从克制逐渐打开。", "director_prompt": "以实际可唱的歌词和短暂串场形成从克制到温暖释放的情绪弧线，用完成度最高的一段演唱收束。"}
	plan.rng_seed = 20260813
	plan.state_snapshot = {
		"skill_levels": {"game": 2, "talk": 3, "song": 3, "act": 2, "tech": 1},
		"stress": 16,
		"otaku_desire": 32,
		"loneliness": 20,
		"fans": 1200,
		"fan_vector": {"r": 60.0, "m": 25.0, "w": 10.0, "c": 4.0, "b": 1.0},
		"material_instance": {"definition_id": String(MATERIAL_ID)},
	}
	var result: StreamSettlementResult = LiveStreamCalculator.new().calculate(plan, CATALOG, BALANCE)
	_generator = GENERATOR_SCRIPT.new()
	_generator.llm_enabled = true
	_generator.summary_enabled = false
	add_child(_generator)
	_generator.setup(plan, result, CATALOG, persona.model)
	_generator.show_ready.connect(_on_show_ready)
	_generator.generation_failed.connect(_on_generation_failed)
	print("LAB_SONG_DIALOGUE_START")
	_generator.generate()


func _on_show_ready(show: Dictionary) -> void:
	var dsl_text: String = str(show.get("dsl_text", ""))
	var music_note_say_count: int = 0
	print("LAB_SONG_DIALOGUE_RESULT title=%s dsl=%s" % [
		str(show.get("title", "")),
		JSON.stringify(dsl_text),
	])
	for line: String in dsl_text.split("\n"):
		var normalized_line: String = line.strip_edges()
		if not normalized_line.begins_with("say:"):
			continue
		var body: String = normalized_line.trim_prefix("say:").strip_edges()
		if body.begins_with("♪") and body.ends_with("♪"):
			music_note_say_count += 1
		if (body.begins_with("（") and body.ends_with("）")) \
			or (body.begins_with("(") and body.ends_with(")")):
			print("LAB_SONG_DIALOGUE_PURE_PAREN_SAY %s" % normalized_line)
	print("LAB_SONG_DIALOGUE_MUSIC_NOTE_SAY count=%d" % music_note_say_count)
	print("LAB_SONG_DIALOGUE_ALL_DONE ok=1")


func _on_generation_failed(reason: String) -> void:
	print("LAB_SONG_DIALOGUE_ALL_DONE ok=0 reason=%s" % reason)
