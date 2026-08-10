extends Node
## 通用行程转场管理器。
## 只负责显示行程、推进进度并发出完成信号，不绑定任何具体玩法系统。

signal transit_started(transit_id: String, payload: Dictionary)
signal transit_updated(transit_id: String, payload: Dictionary)
signal transit_finished(transit_id: String, payload: Dictionary)
signal transit_cancelled(transit_id: String, payload: Dictionary)

const TRANSIT_SCENE := preload("res://scenes/pseudo_os/transit_window_content.tscn")
const WINDOW_CONSTRAINTS_CLASS := preload("res://scripts/pseudo_os/window_constraints.gd")
const FINISH_HOLD_SECONDS: float = 0.42
const WINDOW_CLOSE_SECONDS: float = 0.14
const COMPLETION_RUSH_SECONDS: float = 0.48
const GATED_WAIT_LIMIT: float = 0.995

var _active_transit: Dictionary = {}
var _elapsed_seconds: float = 0.0
var _finishing: bool = false
var _window: Control = null
var _content: Control = null
var _gated: bool = false
var _ready_requested: bool = false
var _minimum_duration: float = 0.0
var _completion_elapsed: float = 0.0
var _completion_start_progress: float = 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _active_transit.is_empty():
		return
	if _finishing:
		_process_completion_rush(delta)
		return
	if _gated:
		_elapsed_seconds += delta
		_advance_gated_progress(delta)
		_refresh_window()
		transit_updated.emit(str(_active_transit["id"]), _active_transit.duplicate(true))
		if _ready_requested and _elapsed_seconds >= _minimum_duration:
			_begin_finish()
		return
	var duration: float = float(_active_transit.get("duration", 0.0))
	if duration <= 0.0:
		return
	_elapsed_seconds = minf(_elapsed_seconds + delta, duration)
	_active_transit["progress"] = _elapsed_seconds / duration
	_refresh_window()
	transit_updated.emit(str(_active_transit["id"]), _active_transit.duplicate(true))
	if _elapsed_seconds >= duration:
		_begin_finish()


func play_transit(request: Dictionary) -> String:
	if not _active_transit.is_empty():
		push_warning("[TransitManager] A transit is already active: %s" % str(_active_transit.get("id", "")))
		return ""

	_active_transit = _normalize_request(request)
	_elapsed_seconds = float(_active_transit["progress"]) * float(_active_transit["duration"])
	_finishing = false
	_gated = bool(_active_transit.get("gated", false))
	_ready_requested = false
	_minimum_duration = maxf(float(_active_transit.get("minimum_duration", 0.0)), 0.0)
	_completion_elapsed = 0.0
	_completion_start_progress = 0.0
	if not _open_window():
		_active_transit.clear()
		return ""

	set_process(_gated or float(_active_transit["duration"]) > 0.0)
	var transit_id: String = str(_active_transit["id"])
	transit_started.emit(transit_id, _active_transit.duplicate(true))
	return transit_id


func play_timed_transit(request: Dictionary) -> String:
	return play_transit(request)


func play_gated_transit(request: Dictionary) -> String:
	var gated_request: Dictionary = request.duplicate(true)
	gated_request["gated"] = true
	gated_request["minimum_duration"] = maxf(float(request.get("minimum_duration", 3.0)), 0.5)
	gated_request["duration"] = 0.0
	return play_transit(gated_request)


func mark_transit_ready(transit_id: String) -> bool:
	if not _matches_active(transit_id) or not _gated or _finishing:
		return false
	_ready_requested = true
	if _elapsed_seconds >= _minimum_duration:
		_begin_finish()
	return true


func update_transit(transit_id: String, progress: float, patch: Dictionary = {}) -> bool:
	if not _matches_active(transit_id) or _finishing:
		return false
	for key in patch:
		if key not in ["id", "duration", "progress", "completed"]:
			_active_transit[key] = patch[key]
	_active_transit["progress"] = clampf(progress, 0.0, 1.0)
	_elapsed_seconds = float(_active_transit["progress"]) * float(_active_transit["duration"])
	_refresh_window()
	transit_updated.emit(transit_id, _active_transit.duplicate(true))
	if progress >= 1.0:
		_begin_finish()
	return true


func finish_transit(transit_id: String) -> bool:
	if not _matches_active(transit_id) or _finishing:
		return false
	_begin_finish()
	return true


func cancel_transit(transit_id: String) -> bool:
	if not _matches_active(transit_id):
		return false
	var payload := _active_transit.duplicate(true)
	set_process(false)
	_close_window()
	_active_transit.clear()
	_elapsed_seconds = 0.0
	_finishing = false
	_gated = false
	_ready_requested = false
	_minimum_duration = 0.0
	_completion_elapsed = 0.0
	_completion_start_progress = 0.0
	transit_cancelled.emit(transit_id, payload)
	return true


func has_active_transit() -> bool:
	return not _active_transit.is_empty()


func get_active_transit() -> Dictionary:
	return _active_transit.duplicate(true)


func reset_runtime_state() -> void:
	if not _active_transit.is_empty():
		cancel_transit(str(_active_transit.get("id", "")))


func _normalize_request(request: Dictionary) -> Dictionary:
	var transit_id: String = str(request.get("id", "")).strip_edges()
	if transit_id.is_empty():
		transit_id = "transit_%d" % Time.get_ticks_msec()
	return {
		"id": transit_id,
		"window_title": str(request.get("window_title", "行程")),
		"title": str(request.get("title", "正在前往下一幕")),
		"activity": str(request.get("activity", "")).strip_edges().to_lower(),
		"duration": maxf(float(request.get("duration", 3.0)), 0.0),
		"progress": clampf(float(request.get("progress", 0.0)), 0.0, 1.0),
		"completed": false,
		"gated": bool(request.get("gated", false)),
		"minimum_duration": maxf(float(request.get("minimum_duration", 0.0)), 0.0),
	}


func _open_window() -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		push_warning("[TransitManager] AppManager not available")
		return false
	var window_manager: Node = app_manager.get("window_manager") as Node
	if window_manager == null:
		push_warning("[TransitManager] WindowManager not available")
		return false

	_content = TRANSIT_SCENE.instantiate() as Control
	if _content == null:
		return false
	_content.call("setup", _active_transit)

	var constraints: Resource = WINDOW_CONSTRAINTS_CLASS.new()
	constraints.set("min_size", Vector2(1200.0, 790.0))
	constraints.set("default_size", Vector2(1540.0, 980.0))
	constraints.set("resizable", false)
	_window = window_manager.call(
		"create_window",
		str(_active_transit["window_title"]),
		_content,
		constraints
	) as Control
	if _window == null:
		_content.queue_free()
		_content = null
		return false
	if _window.has_method("set_close_locked"):
		_window.call("set_close_locked", true)
	if _window.has_method("set_minimize_locked"):
		_window.call("set_minimize_locked", true)
	return true


func _refresh_window() -> void:
	if _content != null and is_instance_valid(_content):
		_content.call("update_transit", _active_transit)


func _begin_finish() -> void:
	if _active_transit.is_empty() or _finishing:
		return
	_finishing = true
	_completion_elapsed = 0.0
	_completion_start_progress = clampf(float(_active_transit.get("progress", 0.0)), 0.0, 1.0)
	if _completion_start_progress >= 1.0:
		_complete_progress_rush()
		return
	set_process(true)


func _process_completion_rush(delta: float) -> void:
	_completion_elapsed = minf(_completion_elapsed + delta, COMPLETION_RUSH_SECONDS)
	var ratio: float = _completion_elapsed / COMPLETION_RUSH_SECONDS
	var eased_ratio: float = 1.0 - pow(1.0 - ratio, 3.0)
	_active_transit["progress"] = lerpf(_completion_start_progress, 1.0, eased_ratio)
	_refresh_window()
	transit_updated.emit(str(_active_transit["id"]), _active_transit.duplicate(true))
	if ratio < 1.0:
		return
	_complete_progress_rush()


func _complete_progress_rush() -> void:
	set_process(false)
	_active_transit["progress"] = 1.0
	_active_transit["completed"] = true
	_refresh_window()
	_finish_after_presenting(str(_active_transit["id"]))


func _advance_gated_progress(delta: float) -> void:
	var progress: float = clampf(float(_active_transit.get("progress", 0.0)), 0.0, GATED_WAIT_LIMIT)
	var speed: float = 0.0
	if progress < 0.58:
		speed = lerpf(0.42, 0.18, progress / 0.58)
	elif progress < 0.82:
		speed = lerpf(0.12, 0.045, (progress - 0.58) / 0.24)
	elif progress < 0.94:
		speed = lerpf(0.026, 0.008, (progress - 0.82) / 0.12)
	else:
		speed = maxf(0.00018, (GATED_WAIT_LIMIT - progress) * 0.055)
	_active_transit["progress"] = minf(progress + speed * delta, GATED_WAIT_LIMIT)


func _finish_after_presenting(transit_id: String) -> void:
	await get_tree().create_timer(FINISH_HOLD_SECONDS).timeout
	if not _matches_active(transit_id) or not _finishing:
		return
	var payload := _active_transit.duplicate(true)
	_close_window()
	await get_tree().create_timer(WINDOW_CLOSE_SECONDS).timeout
	if not _matches_active(transit_id):
		return
	_active_transit.clear()
	_elapsed_seconds = 0.0
	_finishing = false
	_gated = false
	_ready_requested = false
	_minimum_duration = 0.0
	_completion_elapsed = 0.0
	_completion_start_progress = 0.0
	transit_finished.emit(transit_id, payload)


func _close_window() -> void:
	if _window != null and is_instance_valid(_window):
		var app_manager: Node = get_node_or_null("/root/AppManager")
		var window_manager: Node = app_manager.get("window_manager") as Node if app_manager != null else null
		if window_manager != null:
			window_manager.call("close_window", _window)
		else:
			_window.queue_free()
	_window = null
	_content = null


func _matches_active(transit_id: String) -> bool:
	return not _active_transit.is_empty() and str(_active_transit.get("id", "")) == transit_id
