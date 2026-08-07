class_name LiveShowPlayer extends Node
## 线性播放直播 DSL 的操作序列。

signal chat_event(event: Dictionary)
signal finished()

const TYPEWRITER_CHARACTERS_PER_SECOND: float = 16.0
const FAST_MULTIPLIER: float = 4.0
const FAST_HOLD_SECONDS: float = 0.4

var _display: StreamSceneDisplay = null
var _subtitle_panel: Control = null
var _subtitle_label: Label = null
var _playing: bool = false
var _fast_forward: bool = false
var _run_id: int = 0
var _pending_bursts: int = 0
var _rng := RandomNumberGenerator.new()


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
	_pending_bursts = 0
	_fast_forward = false
	_rng.seed = seed_value
	_playing = true
	_run_show(ops.duplicate(true), _run_id)
	return true


func stop(emit_finished: bool = false) -> void:
	var was_playing: bool = _playing
	_run_id += 1
	_playing = false
	_pending_bursts = 0
	if _subtitle_panel != null:
		_subtitle_panel.visible = false
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
			"say":
				await _play_say(op, run_id)
			"chat", "sc":
				_start_message_burst(op, run_id)
			"wait":
				await _wait_duration(float(op.get("seconds", 0.0)), run_id)

	while run_id == _run_id and _pending_bursts > 0:
		await get_tree().process_frame
	if run_id != _run_id:
		return
	_playing = false
	_subtitle_panel.visible = false
	finished.emit()


func _play_say(op: Dictionary, run_id: int) -> void:
	var expression := StringName(str(op.get("expression", "")))
	if _display != null and not String(expression).is_empty():
		_display.set_expression(expression)
	var text: String = str(op.get("text", ""))
	_subtitle_label.text = text
	_subtitle_label.visible_characters = 0
	_subtitle_panel.visible = true

	var revealed: float = 0.0
	while run_id == _run_id and _subtitle_label.visible_characters < text.length():
		await get_tree().process_frame
		var speed: float = TYPEWRITER_CHARACTERS_PER_SECOND
		if _fast_forward:
			speed *= FAST_MULTIPLIER
		revealed += get_process_delta_time() * speed
		_subtitle_label.visible_characters = mini(int(revealed), text.length())
	if run_id != _run_id:
		return
	_subtitle_label.visible_characters = -1

	var hold_seconds: float = clampf(1.2 + float(text.length()) * 0.05, 1.5, 4.0)
	var elapsed: float = 0.0
	while run_id == _run_id:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var target: float = FAST_HOLD_SECONDS if _fast_forward else hold_seconds
		if elapsed >= target:
			break


func _wait_duration(seconds: float, run_id: int) -> void:
	var elapsed: float = 0.0
	while run_id == _run_id and elapsed < seconds:
		await get_tree().process_frame
		var multiplier: float = FAST_MULTIPLIER if _fast_forward else 1.0
		elapsed += get_process_delta_time() * multiplier


func _start_message_burst(op: Dictionary, run_id: int) -> void:
	var messages: Array = op.get("messages", [])
	var count: int = int(op.get("count", messages.size()))
	var drawn: Array[String] = draw_without_replacement(messages, count, _rng)
	if drawn.is_empty():
		return
	_pending_bursts += 1
	_emit_message_burst(str(op.get("op", "")), drawn, run_id)


func _emit_message_burst(kind: String, messages: Array[String], run_id: int) -> void:
	for index: int in range(messages.size()):
		if run_id != _run_id:
			break
		var text: String = messages[index]
		if kind == "sc":
			chat_event.emit({"kind": "sc", "text": text})
		else:
			chat_event.emit({"kind": "send", "entries": [{"text": text}]})
		if index + 1 < messages.size():
			await _wait_message_interval(kind, messages.size(), run_id)
	if run_id == _run_id:
		_pending_bursts = maxi(_pending_bursts - 1, 0)


func _wait_message_interval(kind: String, count: int, run_id: int) -> void:
	var min_seconds: float
	var max_seconds: float
	if kind == "sc":
		min_seconds = 0.35 if count <= 5 else 0.18
		max_seconds = 0.75 if count <= 5 else 0.4
	else:
		min_seconds = 0.3 if count <= 5 else 0.08
		max_seconds = 0.8 if count <= 5 else 0.25
	var target: float = _rng.randf_range(min_seconds, max_seconds)
	var elapsed: float = 0.0
	while run_id == _run_id and elapsed < target:
		await get_tree().process_frame
		var multiplier: float = FAST_MULTIPLIER if _fast_forward else 1.0
		elapsed += get_process_delta_time() * multiplier
