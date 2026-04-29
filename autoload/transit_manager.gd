extends Node

const SbeamUIBuilderClass = preload("res://scripts/apps/sbeam/sbeam_ui_builder.gd")
const UIIconLibraryClass = preload("res://scripts/ui/ui_icon_library.gd")

signal transit_started(transit_id: String, payload: Dictionary)
signal transit_updated(transit_id: String, progress: float, payload: Dictionary)
signal transit_finished(transit_id: String, payload: Dictionary)
signal transit_cancelled(transit_id: String, payload: Dictionary)

const NAVIGATION_STAGES: Array[String] = [
	"正在规划路线...",
	"步行前往站点  约 2 分钟",
	"正在等待进站...",
	"列车运行中",
	"途经 3 站",
	"下一站即为目的地",
	"请准备下车",
	"已到达  步行约 1 分钟",
]

const DOWNLOAD_STAGES: Array[String] = [
	"正在连接 SBEAM 内容服务器...",
	"正在校验本地共享运行库...",
	"正在下载游戏数据 (1/3)...",
	"正在下载游戏数据 (2/3)...",
	"正在下载游戏数据 (3/3)...",
	"正在校验文件完整性...",
	"正在解压并配置运行环境...",
	"准备启动...",
]

const PART_TIME_STAGES: Array[String] = [
	"订单已确认，正在呼叫车辆...",
	"司机正在赶来  预计 3 分钟",
	"已上车，前往目的地",
	"途经城市快速路",
	"预计还剩 8 分钟",
	"即将驶离快速路",
	"距目的地不足 1 公里",
	"已到达目的地附近",
]

const REST_STAGES: Array[String] = [
	"正在放松下来...",
	"呼吸慢慢平稳",
	"意识开始模糊",
	"睡眠正在修复状态",
	"身体逐渐放松",
	"梦境变得安静",
	"快要醒来了",
	"休息完成",
]

const DEFAULT_ACCENT_COLOR: String = "#34A853"
const DEFAULT_BG_COLOR: String = "#FFFFFF"
const DEFAULT_TEXT_COLOR: String = "#202124"
const DEFAULT_SUBTEXT_COLOR: String = "#5F6368"
const DEFAULT_WINDOW_WIDTH: float = 460.0
const DEFAULT_WINDOW_HEIGHT: float = 240.0

var _active_transit: Dictionary = {}
var _transit_window: Control = null
var _title_label: Label = null
var _stage_label: Label = null
var _meta_label: Label = null
var _progress_bar: ProgressBar = null
var _timed_elapsed: float = 0.0


func _ready() -> void:
	call_deferred("_connect_activity_sources")


func _process(delta: float) -> void:
	if _active_transit.is_empty():
		set_process(false)
		return
	if not bool(_active_transit.get("auto_drive", false)):
		set_process(false)
		return

	var duration: float = maxf(float(_active_transit.get("duration", 0.0)), 0.0)
	if duration <= 0.0:
		finish_transit(str(_active_transit.get("id", "")))
		return

	_timed_elapsed += delta
	var progress: float = clampf(_timed_elapsed / duration, 0.0, 1.0)
	update_transit(str(_active_transit.get("id", "")), progress)


func reset_runtime_state() -> void:
	cancel_transit()


func play_transit(request: Dictionary) -> String:
	var normalized: Dictionary = _normalize_request(request)
	if normalized.is_empty():
		return ""

	var request_id: String = str(normalized.get("id", "")).strip_edges()
	if request_id.is_empty():
		return ""

	if not _active_transit.is_empty():
		var active_id: String = str(_active_transit.get("id", "")).strip_edges()
		if active_id == request_id:
			_active_transit = normalized
			_refresh_window()
			return request_id
		cancel_transit(active_id)

	_active_transit = normalized
	_timed_elapsed = clampf(float(_active_transit.get("progress", 0.0)) * float(_active_transit.get("duration", 0.0)), 0.0, 99999.0)
	_open_window()
	_refresh_window()
	set_process(bool(_active_transit.get("auto_drive", false)))
	transit_started.emit(request_id, _active_transit.duplicate(true))
	return request_id


func play_timed_transit(request: Dictionary) -> String:
	var normalized: Dictionary = request.duplicate(true)
	normalized["auto_drive"] = true
	return play_transit(normalized)


func update_transit(transit_id: String, progress: float, patch: Dictionary = {}) -> void:
	if _active_transit.is_empty():
		return
	if not transit_id.is_empty() and transit_id != str(_active_transit.get("id", "")):
		return

	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	_active_transit["progress"] = clamped_progress
	for key in patch.keys():
		_active_transit[key] = patch[key]
	_refresh_window()
	transit_updated.emit(str(_active_transit.get("id", "")), clamped_progress, _active_transit.duplicate(true))

	if clamped_progress >= 1.0:
		finish_transit(str(_active_transit.get("id", "")))


func finish_transit(transit_id: String = "") -> void:
	if _active_transit.is_empty():
		return
	if not transit_id.is_empty() and transit_id != str(_active_transit.get("id", "")):
		return

	var finished_payload: Dictionary = _active_transit.duplicate(true)
	var finished_id: String = str(finished_payload.get("id", ""))
	_active_transit.clear()
	_timed_elapsed = 0.0
	set_process(false)
	_close_window()
	transit_finished.emit(finished_id, finished_payload)


func cancel_transit(transit_id: String = "") -> void:
	if _active_transit.is_empty():
		return
	if not transit_id.is_empty() and transit_id != str(_active_transit.get("id", "")):
		return

	var cancelled_payload: Dictionary = _active_transit.duplicate(true)
	var cancelled_id: String = str(cancelled_payload.get("id", ""))
	_active_transit.clear()
	_timed_elapsed = 0.0
	set_process(false)
	_close_window()
	transit_cancelled.emit(cancelled_id, cancelled_payload)


func has_active_transit() -> bool:
	return not _active_transit.is_empty()


func get_active_transit() -> Dictionary:
	return _active_transit.duplicate(true)


func _connect_activity_sources() -> void:
	_connect_signal("/root/DateManager", "transit_started", Callable(self, "_on_date_transit_started"))
	_connect_signal("/root/DateManager", "transit_progress_updated", Callable(self, "_on_date_transit_progress_updated"))
	_connect_signal("/root/DateManager", "important_event_started", Callable(self, "_on_date_transit_finished"))
	_connect_signal("/root/DateManager", "date_completed", Callable(self, "_on_date_transit_finished"))

	_connect_signal("/root/SbeamManager", "download_started", Callable(self, "_on_sbeam_transit_started"))
	_connect_signal("/root/SbeamManager", "download_progress_updated", Callable(self, "_on_sbeam_transit_progress_updated"))
	_connect_signal("/root/SbeamManager", "play_session_completed", Callable(self, "_on_sbeam_transit_finished"))
	_connect_signal("/root/SbeamManager", "play_session_failed", Callable(self, "_on_sbeam_transit_failed"))

	_connect_signal("/root/PartTimeJobManager", "transit_started", Callable(self, "_on_part_time_transit_started"))
	_connect_signal("/root/PartTimeJobManager", "transit_progress_updated", Callable(self, "_on_part_time_transit_progress_updated"))
	_connect_signal("/root/PartTimeJobManager", "job_completed", Callable(self, "_on_part_time_transit_finished"))

	_connect_signal("/root/HomeActivityManager", "progress_phase_started", Callable(self, "_on_home_transit_started"))
	_connect_signal("/root/HomeActivityManager", "progress_updated", Callable(self, "_on_home_transit_progress_updated"))
	_connect_signal("/root/HomeActivityManager", "activity_completed", Callable(self, "_on_home_transit_finished"))
	_connect_signal("/root/HomeActivityManager", "session_failed", Callable(self, "_on_home_transit_failed"))


func _connect_signal(node_path: String, signal_name: String, callback: Callable) -> void:
	var node: Node = get_node_or_null(node_path)
	if node == null or not node.has_signal(signal_name):
		return
	if not node.is_connected(signal_name, callback):
		node.connect(signal_name, callback)


func _on_date_transit_started(session_id: String, _payload: Dictionary) -> void:
	var manager: Node = get_node_or_null("/root/DateManager")
	var session: Dictionary = manager.get_session_snapshot(session_id) if manager != null and manager.has_method("get_session_snapshot") else {}
	var location: Dictionary = _as_dictionary(session.get("location", {}))
	play_transit({
		"id": "activity_date_%s" % session_id,
		"presentation": "map_navigation",
		"source": "activity_session",
		"source_manager": "DateManager",
		"session_id": session_id,
		"window_title": "导航",
		"title": str(location.get("title", "目的地")),
		"stages": NAVIGATION_STAGES,
		"icon": "metro",
		"accent_color": "#34A853",
		"eta_active": "前往中...",
		"eta_done": "即将到达",
		"progress": 0.0,
	})


func _on_date_transit_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	update_transit("activity_date_%s" % session_id, progress)


func _on_date_transit_finished(session_id: String, _payload: Dictionary) -> void:
	finish_transit("activity_date_%s" % session_id)


func _on_sbeam_transit_started(session_id: String, payload: Dictionary) -> void:
	var game: Dictionary = _as_dictionary(payload.get("game", {}))
	if game.is_empty():
		var manager: Node = get_node_or_null("/root/SbeamManager")
		var session: Dictionary = manager.get_session_snapshot(session_id) if manager != null and manager.has_method("get_session_snapshot") else {}
		game = _as_dictionary(session.get("game", {}))
	play_transit({
		"id": "activity_sbeam_%s" % session_id,
		"presentation": "sbeam_download",
		"source": "activity_session",
		"source_manager": "SbeamManager",
		"session_id": session_id,
		"window_title": "下载中",
		"title": str(game.get("title", "未命名作品")),
		"game": game.duplicate(true),
		"stages": DOWNLOAD_STAGES,
		"icon": "download",
		"accent_color": "#66c0f4",
		"eta_active": "下载中...",
		"eta_done": "准备启动",
		"progress": 0.0,
		"width": 580.0,
		"height": 300.0,
	})


func _on_sbeam_transit_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	update_transit("activity_sbeam_%s" % session_id, progress)


func _on_sbeam_transit_finished(session_id: String, _payload: Dictionary) -> void:
	finish_transit("activity_sbeam_%s" % session_id)


func _on_sbeam_transit_failed(_error_message: String) -> void:
	if str(_active_transit.get("source_manager", "")) == "SbeamManager":
		cancel_transit(str(_active_transit.get("id", "")))


func _on_part_time_transit_started(session_id: String, _payload: Dictionary) -> void:
	var manager: Node = get_node_or_null("/root/PartTimeJobManager")
	var session: Dictionary = manager.get_session_snapshot(session_id) if manager != null and manager.has_method("get_session_snapshot") else {}
	var job: Dictionary = _as_dictionary(session.get("job", {}))
	play_transit({
		"id": "activity_part_time_%s" % session_id,
		"presentation": "part_time_commute",
		"source": "activity_session",
		"source_manager": "PartTimeJobManager",
		"session_id": session_id,
		"window_title": "前往兼职",
		"title": str(job.get("job_title", job.get("title", "兼职地点"))),
		"stages": PART_TIME_STAGES,
		"icon": "bus",
		"accent_color": "#00BE6E",
		"eta_active": "前往中...",
		"eta_done": "即将到达",
		"progress": 0.0,
	})


func _on_part_time_transit_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	update_transit("activity_part_time_%s" % session_id, progress)


func _on_part_time_transit_finished(session_id: String, _payload: Dictionary) -> void:
	finish_transit("activity_part_time_%s" % session_id)


func _on_home_transit_started(session_id: String, payload: Dictionary) -> void:
	var manager: Node = get_node_or_null("/root/HomeActivityManager")
	var session: Dictionary = manager.get_session_snapshot(session_id) if manager != null and manager.has_method("get_session_snapshot") else {}
	var activity_id: String = str(session.get("activity_id", "")).strip_edges()
	if activity_id != "rest":
		return
	play_transit({
		"id": "activity_home_%s" % session_id,
		"presentation": "rest_night",
		"source": "activity_session",
		"source_manager": "HomeActivityManager",
		"session_id": session_id,
		"window_title": "休息",
		"title": "Good Night",
		"stages": REST_STAGES,
		"icon": "rest",
		"accent_color": "#8FA5FF",
		"bg_color": "#1A1F3A",
		"text_color": "#F5F7FF",
		"subtext_color": "#B6BEDA",
		"eta_active": "睡眠中...",
		"eta_done": "即将醒来",
		"progress": float(payload.get("progress", 0.0)),
	})


func _on_home_transit_progress_updated(session_id: String, progress: float, _scene_ready: bool) -> void:
	update_transit("activity_home_%s" % session_id, progress)


func _on_home_transit_finished(activity_id: String, payload: Dictionary) -> void:
	if activity_id != "rest":
		return
	finish_transit("activity_home_%s" % str(payload.get("session_id", "")))


func _on_home_transit_failed(_error_message: String) -> void:
	if str(_active_transit.get("source_manager", "")) == "HomeActivityManager":
		cancel_transit(str(_active_transit.get("id", "")))


func _normalize_request(request: Dictionary) -> Dictionary:
	var normalized: Dictionary = request.duplicate(true)
	var transit_id: String = str(normalized.get("id", "")).strip_edges()
	if transit_id.is_empty():
		var source: String = str(normalized.get("source", "generic")).strip_edges()
		transit_id = "transit_%s_%d" % [source, Time.get_unix_time_from_system()]
	normalized["id"] = transit_id
	normalized["window_title"] = str(normalized.get("window_title", "Transit"))
	normalized["title"] = str(normalized.get("title", "进行中"))
	normalized["presentation"] = str(normalized.get("presentation", "generic")).strip_edges()
	normalized["stages"] = _normalize_string_array(normalized.get("stages", []))
	if (normalized.get("stages", []) as Array[String]).is_empty():
		normalized["stages"] = ["进行中..."]
	normalized["progress"] = clampf(float(normalized.get("progress", 0.0)), 0.0, 1.0)
	normalized["auto_drive"] = bool(normalized.get("auto_drive", false))
	normalized["duration"] = maxf(float(normalized.get("duration", 0.0)), 0.0)
	normalized["accent_color"] = str(normalized.get("accent_color", DEFAULT_ACCENT_COLOR))
	normalized["bg_color"] = str(normalized.get("bg_color", DEFAULT_BG_COLOR))
	normalized["text_color"] = str(normalized.get("text_color", DEFAULT_TEXT_COLOR))
	normalized["subtext_color"] = str(normalized.get("subtext_color", DEFAULT_SUBTEXT_COLOR))
	normalized["eta_active"] = str(normalized.get("eta_active", "进行中..."))
	normalized["eta_done"] = str(normalized.get("eta_done", "即将完成"))
	normalized["icon"] = str(normalized.get("icon", ""))
	normalized["width"] = maxf(float(normalized.get("width", DEFAULT_WINDOW_WIDTH)), 320.0)
	normalized["height"] = maxf(float(normalized.get("height", DEFAULT_WINDOW_HEIGHT)), 180.0)
	return normalized


func _normalize_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var text: String = str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	return result


func _open_window() -> void:
	_close_window()
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_mgr.get("window_manager") if app_mgr != null else null
	if window_manager == null or not window_manager.has_method("create_window"):
		return

	var refs: Dictionary = _build_window_content(_active_transit)
	var outer: Control = refs.get("root")
	if outer == null:
		return

	_title_label = refs.get("title_label")
	_stage_label = refs.get("stage_label")
	_meta_label = refs.get("meta_label")
	_progress_bar = refs.get("progress_bar")

	_transit_window = window_manager.create_window(str(_active_transit.get("window_title", "Transit")), outer)
	if _transit_window != null:
		_transit_window.size = Vector2(float(_active_transit.get("width", DEFAULT_WINDOW_WIDTH)), float(_active_transit.get("height", DEFAULT_WINDOW_HEIGHT)))
		if _transit_window.has_method("set_close_locked"):
			_transit_window.set_close_locked(true)
		if _transit_window.has_method("set_minimize_locked"):
			_transit_window.set_minimize_locked(true)


func _refresh_window() -> void:
	if _active_transit.is_empty():
		return
	if _title_label != null:
		_title_label.text = str(_active_transit.get("title", "进行中"))
	if _stage_label != null:
		_stage_label.text = _resolve_stage_text(_active_transit, float(_active_transit.get("progress", 0.0)))
	if _progress_bar != null:
		_progress_bar.value = float(_active_transit.get("progress", 0.0)) * 100.0
	if _meta_label != null:
		_meta_label.text = _resolve_meta_text(_active_transit, float(_active_transit.get("progress", 0.0)))


func _resolve_stage_text(request: Dictionary, progress: float) -> String:
	var stages: Array[String] = request.get("stages", [])
	if stages.is_empty():
		return "进行中..."
	var index: int = clampi(int(floor(progress * float(stages.size()))), 0, stages.size() - 1)
	return stages[index]


func _resolve_meta_text(request: Dictionary, progress: float) -> String:
	var presentation: String = str(request.get("presentation", "generic")).strip_edges()
	if presentation == "sbeam_download":
		return "下载速度 %.1f MB/s · 磁盘可用 %d GB" % [24.0 + progress * 18.0, 256]
	return str(request.get("eta_done", "即将完成")) if progress >= 0.999 else str(request.get("eta_active", "进行中..."))


func _build_window_content(request: Dictionary) -> Dictionary:
	match str(request.get("presentation", "generic")).strip_edges():
		"map_navigation":
			return _build_navigation_window_content(request, {
				"title_color": Color("#202124"),
				"stage_color": Color("#5F6368"),
				"progress_bg": Color("#E8EAED"),
				"progress_fill": Color("#34A853"),
				"meta_color": Color("#34A853"),
				"icon_color": Color("#34A853"),
				"icon_text": "metro",
			})
		"part_time_commute":
			return _build_navigation_window_content(request, {
				"title_color": Color("#1F2329"),
				"stage_color": Color("#6B7280"),
				"progress_bg": Color("#E8EAED"),
				"progress_fill": Color("#00BE6E"),
				"meta_color": Color("#00BE6E"),
				"icon_color": Color("#00BE6E"),
				"icon_text": "bus",
			})
		"rest_night":
			return _build_rest_window_content(request)
		"sbeam_download":
			return _build_sbeam_window_content(request)
		_:
			return _build_generic_window_content(request)


func _build_navigation_window_content(request: Dictionary, style: Dictionary) -> Dictionary:
	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color("#FFFFFF")
	outer_style.corner_radius_top_left = 16
	outer_style.corner_radius_top_right = 16
	outer_style.corner_radius_bottom_left = 16
	outer_style.corner_radius_bottom_right = 16
	outer.add_theme_stylebox_override("panel", outer_style)
	outer.custom_minimum_size = Vector2(float(request.get("width", 460.0)), float(request.get("height", 240.0)))

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	content.add_child(box)

	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", style.get("title_color", Color("#202124")))
	box.add_child(title_label)

	var stage_label := Label.new()
	stage_label.add_theme_font_size_override("font_size", 14)
	stage_label.add_theme_color_override("font_color", style.get("stage_color", Color("#5F6368")))
	box.add_child(stage_label)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 6)
	var progress_bg_style := StyleBoxFlat.new()
	progress_bg_style.bg_color = style.get("progress_bg", Color("#E8EAED"))
	progress_bg_style.corner_radius_top_left = 3
	progress_bg_style.corner_radius_top_right = 3
	progress_bg_style.corner_radius_bottom_left = 3
	progress_bg_style.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("background", progress_bg_style)
	var progress_fill_style := StyleBoxFlat.new()
	progress_fill_style.bg_color = style.get("progress_fill", Color("#34A853"))
	progress_fill_style.corner_radius_top_left = 3
	progress_fill_style.corner_radius_top_right = 3
	progress_fill_style.corner_radius_bottom_left = 3
	progress_fill_style.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("fill", progress_fill_style)
	box.add_child(progress_bar)

	var meta_row := HBoxContainer.new()
	box.add_child(meta_row)

	var meta_icon := _create_meta_icon(
		str(style.get("icon_text", "")),
		style.get("icon_color", Color("#34A853"))
	)
	meta_row.add_child(meta_icon)

	var meta_label := Label.new()
	meta_label.add_theme_font_size_override("font_size", 14)
	meta_label.add_theme_color_override("font_color", style.get("meta_color", Color("#34A853")))
	meta_row.add_child(meta_label)

	return {
		"root": outer,
		"title_label": title_label,
		"stage_label": stage_label,
		"meta_label": meta_label,
		"progress_bar": progress_bar,
	}


func _build_rest_window_content(request: Dictionary) -> Dictionary:
	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color("#1A1F3A")
	outer_style.corner_radius_top_left = 16
	outer_style.corner_radius_top_right = 16
	outer_style.corner_radius_bottom_left = 16
	outer_style.corner_radius_bottom_right = 16
	outer.add_theme_stylebox_override("panel", outer_style)
	outer.custom_minimum_size = Vector2(float(request.get("width", 460.0)), float(request.get("height", 240.0)))

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	content.add_child(box)

	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	box.add_child(title_label)

	var stage_label := Label.new()
	stage_label.add_theme_font_size_override("font_size", 14)
	stage_label.add_theme_color_override("font_color", Color("#8392BA"))
	box.add_child(stage_label)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 6)
	var progress_bg_style := StyleBoxFlat.new()
	progress_bg_style.bg_color = Color("#2A3158")
	progress_bg_style.corner_radius_top_left = 3
	progress_bg_style.corner_radius_top_right = 3
	progress_bg_style.corner_radius_bottom_left = 3
	progress_bg_style.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("background", progress_bg_style)
	var progress_fill_style := StyleBoxFlat.new()
	progress_fill_style.bg_color = Color("#6B88E8")
	progress_fill_style.corner_radius_top_left = 3
	progress_fill_style.corner_radius_top_right = 3
	progress_fill_style.corner_radius_bottom_left = 3
	progress_fill_style.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("fill", progress_fill_style)
	box.add_child(progress_bar)

	var meta_row := HBoxContainer.new()
	box.add_child(meta_row)

	var meta_icon := _create_meta_icon("night", Color("#6B88E8"))
	meta_row.add_child(meta_icon)

	var meta_label := Label.new()
	meta_label.add_theme_font_size_override("font_size", 14)
	meta_label.add_theme_color_override("font_color", Color("#6B88E8"))
	meta_row.add_child(meta_label)

	return {
		"root": outer,
		"title_label": title_label,
		"stage_label": stage_label,
		"meta_label": meta_label,
		"progress_bar": progress_bar,
	}


func _build_sbeam_window_content(request: Dictionary) -> Dictionary:
	var game: Dictionary = _as_dictionary(request.get("game", {}))
	if game.is_empty():
		game = {"title": str(request.get("title", "未命名作品"))}
	var refs: Dictionary = SbeamUIBuilderClass.build_download_window_content(game, request.get("stages", []))
	return {
		"root": refs.get("root"),
		"title_label": refs.get("title_label"),
		"stage_label": refs.get("stage_label"),
		"meta_label": null,
		"progress_bar": refs.get("progress_bar"),
	}


func _build_generic_window_content(request: Dictionary) -> Dictionary:
	var bg_color: Color = Color(str(request.get("bg_color", DEFAULT_BG_COLOR)))
	var text_color: Color = Color(str(request.get("text_color", DEFAULT_TEXT_COLOR)))
	var subtext_color: Color = Color(str(request.get("subtext_color", DEFAULT_SUBTEXT_COLOR)))
	var accent_color: Color = Color(str(request.get("accent_color", DEFAULT_ACCENT_COLOR)))

	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = bg_color
	outer_style.corner_radius_top_left = 16
	outer_style.corner_radius_top_right = 16
	outer_style.corner_radius_bottom_left = 16
	outer_style.corner_radius_bottom_right = 16
	outer.add_theme_stylebox_override("panel", outer_style)
	outer.custom_minimum_size = Vector2(float(request.get("width", DEFAULT_WINDOW_WIDTH)), float(request.get("height", DEFAULT_WINDOW_HEIGHT)))

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	content.add_child(box)

	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", text_color)
	box.add_child(title_label)

	var stage_label := Label.new()
	stage_label.add_theme_font_size_override("font_size", 14)
	stage_label.add_theme_color_override("font_color", subtext_color)
	box.add_child(stage_label)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 6)
	var progress_bg_style := StyleBoxFlat.new()
	progress_bg_style.bg_color = bg_color.darkened(0.12) if bg_color.get_luminance() > 0.2 else bg_color.lightened(0.12)
	progress_bg_style.corner_radius_top_left = 3
	progress_bg_style.corner_radius_top_right = 3
	progress_bg_style.corner_radius_bottom_left = 3
	progress_bg_style.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("background", progress_bg_style)
	var progress_fill_style := StyleBoxFlat.new()
	progress_fill_style.bg_color = accent_color
	progress_fill_style.corner_radius_top_left = 3
	progress_fill_style.corner_radius_top_right = 3
	progress_fill_style.corner_radius_bottom_left = 3
	progress_fill_style.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("fill", progress_fill_style)
	box.add_child(progress_bar)

	var meta_row := HBoxContainer.new()
	box.add_child(meta_row)

	var meta_icon := _create_meta_icon(str(request.get("icon", "")).strip_edges(), accent_color)
	meta_row.add_child(meta_icon)

	var meta_label := Label.new()
	meta_label.add_theme_font_size_override("font_size", 14)
	meta_label.add_theme_color_override("font_color", accent_color)
	meta_row.add_child(meta_label)

	return {
		"root": outer,
		"title_label": title_label,
		"stage_label": stage_label,
		"meta_label": meta_label,
		"progress_bar": progress_bar,
	}


func _close_window() -> void:
	if _transit_window == null or not is_instance_valid(_transit_window):
		_transit_window = null
		_title_label = null
		_stage_label = null
		_meta_label = null
		_progress_bar = null
		return

	var app_mgr: Node = get_node_or_null("/root/AppManager")
	var window_manager: Node = app_mgr.get("window_manager") if app_mgr != null else null
	if window_manager != null and window_manager.has_method("close_window"):
		window_manager.close_window(_transit_window)
	else:
		_transit_window.queue_free()

	_transit_window = null
	_title_label = null
	_stage_label = null
	_meta_label = null
	_progress_bar = null


func _create_meta_icon(icon_token: String, tint: Color) -> Control:
	var icon_texture := UIIconLibraryClass.get_icon(icon_token)
	if icon_texture != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(16, 16)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = tint
		return icon_rect

	var fallback := Label.new()
	fallback.text = "•"
	fallback.add_theme_font_size_override("font_size", 14)
	fallback.add_theme_color_override("font_color", tint)
	return fallback


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}
