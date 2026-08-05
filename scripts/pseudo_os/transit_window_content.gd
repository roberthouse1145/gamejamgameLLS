class_name TransitWindowContent extends Control
## 行程转场窗口内容。视觉动画与业务进度彼此独立。

const SUPPORTED_ACTIVITIES: PackedStringArray = ["sleep", "work", "game", "shopping"]

@onready var title_label: Label = %TransitTitle
@onready var status_label: Label = %StatusLabel
@onready var progress_bar: ProgressBar = %TransitProgress
@onready var road_sticker: TextureRect = %RoadSticker
@onready var bus_sticker: TextureRect = %BusSticker
@onready var schedule_animation: ScheduleActivityAnimation = %ScheduleAnimation
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var _payload: Dictionary = {}
var _active_activity: String = ""


func _ready() -> void:
	_apply_payload()


func setup(payload: Dictionary) -> void:
	_payload = payload.duplicate(true)
	if is_node_ready():
		_apply_payload()


func update_transit(payload: Dictionary) -> void:
	_payload = payload.duplicate(true)
	if is_node_ready():
		_apply_payload()


func _apply_payload() -> void:
	if _payload.is_empty():
		return
	var progress: float = clampf(float(_payload.get("progress", 0.0)), 0.0, 1.0)
	var completed: bool = bool(_payload.get("completed", false))
	var activity_name: String = str(_payload.get("activity", "")).strip_edges().to_lower()
	var uses_activity_illustration: bool = _apply_illustration(activity_name)
	title_label.text = str(_payload.get("title", "正在前往下一幕"))
	if uses_activity_illustration:
		status_label.text = "已完成" if completed else "进行中"
	else:
		status_label.text = "已抵达" if completed else "正在前往"
	progress_bar.value = progress * 100.0
	if uses_activity_illustration:
		schedule_animation.set_activity_paused(completed)
	elif completed:
		animation_player.pause()


func _apply_illustration(activity_name: String) -> bool:
	var uses_activity_illustration: bool = activity_name in SUPPORTED_ACTIVITIES
	road_sticker.visible = not uses_activity_illustration
	bus_sticker.visible = not uses_activity_illustration
	schedule_animation.visible = uses_activity_illustration

	if uses_activity_illustration:
		animation_player.pause()
		if _active_activity != activity_name:
			schedule_animation.play_activity_by_name(activity_name)
			_active_activity = activity_name
	else:
		_active_activity = ""
		if not animation_player.is_playing():
			animation_player.play("drive")
	return uses_activity_illustration
