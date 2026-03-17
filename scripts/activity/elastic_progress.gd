class_name ElasticProgress
extends Node

signal progress_updated(session_id: String, progress: float, scene_ready: bool)
signal progress_completed(session_id: String, scene_ready: bool)

const DEFAULT_DURATION: float = 8.0
const THRESHOLD: float = 0.70
const CAP: float = 0.85
const FINISH_SPEED: float = 3.0

var _active_session_id: String = ""
var _progress: float = 0.0
var _duration: float = DEFAULT_DURATION
var _scene_ready: bool = false
var _scene_failed: bool = false
var _can_finish_override: bool = false


func _ready() -> void:
	set_process(false)


func start(session_id: String, duration: float = DEFAULT_DURATION) -> void:
	_active_session_id = session_id
	_progress = 0.0
	_duration = maxf(duration, 0.1)
	_scene_ready = false
	_scene_failed = false
	_can_finish_override = false
	set_process(true)


func stop() -> void:
	_active_session_id = ""
	set_process(false)


func is_active() -> bool:
	return not _active_session_id.is_empty()


func get_active_session_id() -> String:
	return _active_session_id


func get_progress() -> float:
	return _progress


func mark_scene_ready() -> void:
	_scene_ready = true


func mark_scene_failed() -> void:
	_scene_failed = true


func mark_can_finish() -> void:
	_can_finish_override = true


func _process(delta: float) -> void:
	if _active_session_id.is_empty():
		set_process(false)
		return
	_advance(delta)


func _advance(delta: float) -> void:
	var base_speed: float = 1.0 / _duration
	var can_finish: bool = _scene_ready or _scene_failed or _can_finish_override

	if can_finish or _progress < THRESHOLD:
		var speed_mult: float = FINISH_SPEED if (can_finish and _progress >= THRESHOLD) else 1.0
		_progress += delta * base_speed * speed_mult
	else:
		var room: float = maxf(CAP - _progress, 0.001)
		var full_room: float = CAP - THRESHOLD
		var decay: float = sqrt(room / full_room)
		_progress += delta * base_speed * decay * 0.8

	_progress = clampf(_progress, 0.0, 1.0)
	if not can_finish:
		_progress = minf(_progress, 0.99)

	progress_updated.emit(_active_session_id, _progress, _scene_ready)

	if _progress >= 1.0:
		var finished_session: String = _active_session_id
		var finished_scene_ready: bool = _scene_ready
		_active_session_id = ""
		set_process(false)
		progress_completed.emit(finished_session, finished_scene_ready)
