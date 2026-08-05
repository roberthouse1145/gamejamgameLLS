extends Control
## 通过真实桌面、窗口管理和 TransitManager 验收全部行程动画。

const TRANSIT_CASES: Array[Dictionary] = [
	{"key": "commute", "title": "前往楼下咖啡厅", "activity": ""},
	{"key": "sleep", "title": "休息中", "activity": "sleep"},
	{"key": "work", "title": "正在打工", "activity": "work"},
	{"key": "game", "title": "游戏时间", "activity": "game"},
	{"key": "shopping", "title": "外出逛街", "activity": "shopping"},
]

@onready var state_label: Label = %StateLabel

var _queued_cases: Array[Dictionary] = []


func _ready() -> void:
	TransitManager.transit_started.connect(_on_transit_started)
	TransitManager.transit_finished.connect(_on_transit_finished)
	TransitManager.transit_cancelled.connect(_on_transit_cancelled)
	call_deferred("_play_all")


func _play_all() -> void:
	if TransitManager.has_active_transit():
		state_label.text = "当前行程尚未结束"
		return
	_queued_cases = TRANSIT_CASES.duplicate(true)
	_play_next()


func _play_single(case_index: int) -> void:
	if TransitManager.has_active_transit():
		state_label.text = "当前行程尚未结束"
		return
	_queued_cases.clear()
	_start_transit(TRANSIT_CASES[case_index])


func _play_next() -> void:
	if _queued_cases.is_empty():
		state_label.text = "全部 Transit 动画已播放，可单项重播"
		return
	var transit_case: Dictionary = _queued_cases.pop_front()
	_start_transit(transit_case)


func _start_transit(transit_case: Dictionary) -> void:
	var key: String = str(transit_case.get("key", "transit"))
	var request: Dictionary = {
		"id": "playtest_transit_%s_%d" % [key, Time.get_ticks_msec()],
		"window_title": "日程",
		"title": str(transit_case.get("title", "行程")),
		"duration": 4.0,
	}
	var activity_name: String = str(transit_case.get("activity", ""))
	if not activity_name.is_empty():
		request["activity"] = activity_name
	var transit_id: String = TransitManager.play_timed_transit(request)
	if transit_id.is_empty():
		_queued_cases.clear()
		state_label.text = "行程窗口启动失败"
		return
	print("[Playtest] TransitManager started: %s (%s)" % [key, transit_id])


func _on_play_all_pressed() -> void:
	_play_all()


func _on_commute_pressed() -> void:
	_play_single(0)


func _on_sleep_pressed() -> void:
	_play_single(1)


func _on_work_pressed() -> void:
	_play_single(2)


func _on_game_pressed() -> void:
	_play_single(3)


func _on_shopping_pressed() -> void:
	_play_single(4)


func _on_transit_started(_transit_id: String, payload: Dictionary) -> void:
	state_label.text = "正在验收：%s" % str(payload.get("title", "行程"))


func _on_transit_finished(_transit_id: String, _payload: Dictionary) -> void:
	call_deferred("_play_next")


func _on_transit_cancelled(_transit_id: String, _payload: Dictionary) -> void:
	_queued_cases.clear()
	state_label.text = "行程已取消，可重新播放"
