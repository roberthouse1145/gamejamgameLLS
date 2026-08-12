class_name LiveShowPlayer extends Node
## 线性播放直播 DSL 的操作序列。

signal chat_event(event: Dictionary)
signal finished()

const TYPEWRITER_CHARACTERS_PER_SECOND: float = 22.0
const FAST_MULTIPLIER: float = 4.0
const FAST_HOLD_SECONDS: float = 0.2
const NORMAL_HOLD_BASE_SECONDS: float = 0.45
const NORMAL_HOLD_SECONDS_PER_CHARACTER: float = 0.018
const NORMAL_HOLD_MIN_SECONDS: float = 0.65
const NORMAL_HOLD_MAX_SECONDS: float = 1.4
const SHORT_PAUSE_PUNCTUATION: String = "，,、：:；;"
const LONG_PAUSE_PUNCTUATION: String = "。.!！?？…"
const SILENT_PUNCTUATION: String = "，,、：:；;。.!！?？…“”‘’\"'（）()【】[]《》〈〉—-"
const CHAT_FLOOD_DURATION_MIN: float = 0.9
const CHAT_FLOOD_DURATION_MAX: float = 1.8
const SC_FLOOD_DURATION_MIN: float = 1.4
const SC_FLOOD_DURATION_MAX: float = 2.6
const MESSAGE_INTERVAL_JITTER_MIN: float = 0.7
const MESSAGE_INTERVAL_JITTER_MAX: float = 1.3

@export_group("Typewriter")
@export_range(0.0, 1.0, 0.01) var short_punctuation_pause: float = 0.07
@export_range(0.0, 1.5, 0.01) var long_punctuation_pause: float = 0.16

var _display: StreamSceneDisplay = null
var _subtitle_panel: Control = null
var _subtitle_label: Label = null
var _playing: bool = false
var _fast_forward: bool = false
var _run_id: int = 0
var _rng := RandomNumberGenerator.new()
var _speech_rng := RandomNumberGenerator.new()
var _speech_blip_pitch_variation: float = 0.0
var _speech_blip_character_interval: int = 2

@onready var _speech_blip_player: AudioStreamPlayer = $SpeechBlipPlayer


func configure_persona(persona: StreamPersonaResource) -> void:
	_speech_blip_player.stop()
	_speech_blip_player.max_polyphony = 4
	if persona == null:
		_speech_blip_player.stream = null
		return
	_speech_blip_player.stream = persona.speech_blip
	_speech_blip_player.volume_db = persona.speech_blip_volume_db
	_speech_blip_pitch_variation = persona.speech_blip_pitch_variation
	_speech_blip_character_interval = persona.speech_blip_character_interval


func setup(display: StreamSceneDisplay, subtitle_panel: Control, subtitle_label: Label) -> void:
	_display = display
	_subtitle_panel = subtitle_panel
	_subtitle_label = subtitle_label
	if _subtitle_panel != null:
		_subtitle_panel.visible = false


func play(ops: Array, seed_value: int = 1) -> bool:
	if _display == null or _subtitle_panel == null or _subtitle_label == null or ops.is_empty():
		return false
	_run_id += 1
	_fast_forward = false
	_rng.seed = seed_value
	_speech_rng.seed = seed_value ^ 0x51EE7
	_playing = true
	_run_show(ops.duplicate(true), _run_id)
	return true


func stop(emit_finished: bool = false) -> void:
	var was_playing: bool = _playing
	_run_id += 1
	_playing = false
	if _speech_blip_player != null:
		_speech_blip_player.stop()
	if _subtitle_panel != null:
		_subtitle_panel.visible = false
	if _display != null:
		_display.set_talking(false)
	if emit_finished and was_playing:
		finished.emit()


func set_fast_forward(enabled: bool) -> void:
	_fast_forward = enabled


func is_playing() -> bool:
	return _playing


static func draw_without_replacement(
	messages: Array,
	count: int,
	rng: RandomNumberGenerator
) -> Array[String]:
	var result: Array[String] = []
	var pool: Array[String] = []
	for item: Variant in messages:
		var text: String = str(item).strip_edges()
		if not text.is_empty():
			pool.append(text)
	if pool.is_empty() or count < 1 or rng == null:
		return result
	var bag: Array[String] = pool.duplicate()
	for _index: int in range(count):
		if bag.is_empty():
			bag = pool.duplicate()
		var pick_index: int = rng.randi_range(0, bag.size() - 1)
		result.append(bag[pick_index])
		bag.remove_at(pick_index)
	return result


func _run_show(ops: Array, run_id: int) -> void:
	for value: Variant in ops:
		if run_id != _run_id:
			return
		if not (value is Dictionary):
			continue
		var op: Dictionary = value
		match str(op.get("op", "")):
			"expression":
				_display.set_expression(StringName(str(op.get("value", ""))))
			"posture":
				_display.set_posture(StringName(str(op.get("value", ""))))
			"arm_pose":
				_display.set_arm_pose(StringName(str(op.get("value", ""))))
			"head_pose":
				_display.set_head_pose(StringName(str(op.get("value", ""))))
			"gesture":
				_display.play_gesture(StringName(str(op.get("value", ""))))
			"costume":
				_display.set_costume(StringName(str(op.get("value", ""))))
			"say":
				await _play_say(op, run_id)
			"chat", "sc":
				await _play_message_burst(op, run_id)
			"wait":
				await _wait_duration(float(op.get("seconds", 0.0)), run_id)

	if run_id != _run_id:
		return
	_playing = false
	_subtitle_panel.visible = false
	finished.emit()


func _play_say(op: Dictionary, run_id: int) -> void:
	var text: String = str(op.get("text", ""))
	_subtitle_label.text = text
	_subtitle_label.visible_characters = 0
	_subtitle_panel.visible = true

	for index: int in range(text.length()):
		if run_id != _run_id:
			break
		var character: String = text.substr(index, 1)
		_subtitle_label.visible_characters = index + 1
		if _display != null:
			_display.set_talking(_is_spoken_character(character))
		if _should_play_speech_blip(character, index):
			_play_speech_blip()
		var step_duration: float = 1.0 / TYPEWRITER_CHARACTERS_PER_SECOND
		step_duration += get_punctuation_pause(character)
		await _wait_duration(step_duration, run_id)
	if _display != null:
		_display.set_talking(false)
	if run_id != _run_id:
		return
	_subtitle_label.visible_characters = -1

	var hold_seconds: float = clampf(
		NORMAL_HOLD_BASE_SECONDS + float(text.length()) * NORMAL_HOLD_SECONDS_PER_CHARACTER,
		NORMAL_HOLD_MIN_SECONDS,
		NORMAL_HOLD_MAX_SECONDS
	)
	var elapsed: float = 0.0
	while run_id == _run_id:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var target: float = FAST_HOLD_SECONDS if _fast_forward else hold_seconds
		if elapsed >= target:
			break
	if _display != null:
		_display.set_talking(false)
	_speech_blip_player.stop()


func get_punctuation_pause(character: String) -> float:
	if character.is_empty():
		return 0.0
	if LONG_PAUSE_PUNCTUATION.contains(character):
		return long_punctuation_pause
	if SHORT_PAUSE_PUNCTUATION.contains(character):
		return short_punctuation_pause
	return 0.0


func _is_spoken_character(character: String) -> bool:
	if character.strip_edges().is_empty():
		return false
	if SILENT_PUNCTUATION.contains(character):
		return false
	return true


func _should_play_speech_blip(character: String, character_index: int) -> bool:
	if not _is_spoken_character(character):
		return false
	var interval: int = _speech_blip_character_interval * (2 if _fast_forward else 1)
	return character_index % interval == 0


func _play_speech_blip() -> void:
	if _speech_blip_player.stream == null:
		return
	var pitch_offset: float = _speech_rng.randf_range(
		-_speech_blip_pitch_variation,
		_speech_blip_pitch_variation
	)
	_speech_blip_player.pitch_scale = 1.0 + pitch_offset
	_speech_blip_player.play()


func _wait_duration(seconds: float, run_id: int) -> void:
	var elapsed: float = 0.0
	while run_id == _run_id and elapsed < seconds:
		await get_tree().process_frame
		var multiplier: float = FAST_MULTIPLIER if _fast_forward else 1.0
		elapsed += get_process_delta_time() * multiplier


func _play_message_burst(op: Dictionary, run_id: int) -> void:
	var messages: Array = op.get("messages", [])
	var count: int = int(op.get("count", messages.size()))
	var drawn: Array[String] = draw_without_replacement(messages, count, _rng)
	if drawn.is_empty():
		return
	await _emit_message_burst(str(op.get("op", "")), drawn, run_id)


func _emit_message_burst(kind: String, messages: Array[String], run_id: int) -> void:
	var base_interval: float = _get_message_base_interval(kind, messages.size())
	for index: int in range(messages.size()):
		if run_id != _run_id:
			break
		var text: String = messages[index]
		if kind == "sc":
			chat_event.emit({"kind": "sc", "text": text})
		else:
			chat_event.emit({"kind": "send", "entries": [{"text": text}]})
		if index + 1 < messages.size():
			await _wait_message_interval(base_interval, run_id)


func _get_message_base_interval(kind: String, count: int) -> float:
	var gap_count: int = count - 1
	if gap_count < 1:
		return 0.0
	var total_duration: float
	if count <= 5:
		var min_interval: float = 0.35 if kind == "sc" else 0.3
		var max_interval: float = 0.75 if kind == "sc" else 0.8
		total_duration = _rng.randf_range(min_interval, max_interval) * float(gap_count)
	elif kind == "sc":
		total_duration = _rng.randf_range(SC_FLOOD_DURATION_MIN, SC_FLOOD_DURATION_MAX)
	else:
		total_duration = _rng.randf_range(CHAT_FLOOD_DURATION_MIN, CHAT_FLOOD_DURATION_MAX)
	return total_duration / float(gap_count)


func _wait_message_interval(base_interval: float, run_id: int) -> void:
	var target: float = base_interval * _rng.randf_range(
		MESSAGE_INTERVAL_JITTER_MIN,
		MESSAGE_INTERVAL_JITTER_MAX
	)
	var elapsed: float = 0.0
	while run_id == _run_id and elapsed < target:
		await get_tree().process_frame
		var multiplier: float = FAST_MULTIPLIER if _fast_forward else 1.0
		elapsed += get_process_delta_time() * multiplier
