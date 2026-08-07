class_name StreamStage extends VBoxContainer
## 直播观看区。StreamScene 的显示与播放均独立于 AVGScene。

const DESIGN_RESOLUTION: Vector2 = Vector2(3840, 2160)

signal show_finished()
signal live_chat_event(event: Dictionary)

@export var streamer: StreamerCharacterResource = null

@onready var live_title: Label = %LiveTitle
@onready var live_viewers: Label = %LiveViewers
@onready var live_clock: Label = %LiveClock
@onready var avatar_rect: RoundedAvatar = %AvatarRect
@onready var channel_name: Label = %ChannelName
@onready var channel_tag: Label = %ChannelTag
@onready var fast_button: Button = %FastButton
@onready var skip_button: Button = %SkipButton

@onready var _video_frame: Control = %VideoFrame
@onready var _camera_clip: Control = %CameraClip
@onready var _preview_container: SubViewportContainer = %PreviewContainer
@onready var _stream_display: StreamSceneDisplay = %StreamSceneDisplay
@onready var _show_player: LiveShowPlayer = %LiveShowPlayer
@onready var _subtitle_panel: PanelContainer = %SubtitlePanel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _live_dot: Label = %LiveDot

## 观看人数由 obs_live_app 根据本场热度结算注入并实时刷新。
var viewers_target: int = 0:
	set(value):
		viewers_target = maxi(value, 0)
		if live_viewers != null:
			live_viewers.text = "%d 人在线" % viewers_target

var _playing: bool = false


func _ready() -> void:
	_camera_clip.resized.connect(_layout_preview)
	_show_player.setup(_stream_display, _subtitle_panel, _subtitle_label)
	_show_player.chat_event.connect(_on_live_chat_event)
	_show_player.finished.connect(_on_player_finished)
	_stream_display.setup(streamer)
	_start_live_dot_pulse()
	resized.connect(_update_video_height)
	call_deferred("_update_video_height")
	call_deferred("_layout_preview")


func refresh_channel_info() -> void:
	channel_name.text = _get_streamer_name()
	channel_tag.text = _format_subscribers()


func play_show(show_data: Dictionary, seed_value: int = 1) -> bool:
	var ops: Array = show_data.get("ops", [])
	if streamer == null or ops.is_empty():
		return false
	_show_player.stop()
	_stream_display.setup(streamer)
	_playing = _show_player.play(ops, seed_value)
	return _playing


func set_fast_forward(enabled: bool) -> void:
	_show_player.set_fast_forward(enabled)


func skip() -> void:
	_show_player.stop(true)


func is_playing() -> bool:
	return _playing


func _get_streamer_name() -> String:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null:
		var streamer_name: String = str(game_state.get("streamer_name"))
		if not streamer_name.is_empty():
			return streamer_name
	return streamer.display_name if streamer != null else "主播"


func _format_subscribers() -> String:
	var fans: int = 0
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null:
		fans = int(game_state.get("fans"))
	if fans >= 10000:
		return "%.1f 万位订阅者" % (float(fans) / 10000.0)
	return "%d 位订阅者" % fans


## 画面高度只由实际宽度按 16:9 决定，避免父级高度参与计算造成循环收缩。
func _update_video_height() -> void:
	var width: float = size.x
	if width < 2.0:
		return
	_video_frame.custom_minimum_size.y = width * 9.0 / 16.0


func _layout_preview() -> void:
	var view_size: Vector2 = _camera_clip.size
	if view_size.x < 2.0 or view_size.y < 2.0:
		return
	var aspect: float = DESIGN_RESOLUTION.x / DESIGN_RESOLUTION.y
	var container_aspect: float = view_size.x / view_size.y
	var new_size: Vector2
	if container_aspect > aspect:
		new_size = Vector2(view_size.y * aspect, view_size.y)
	else:
		new_size = Vector2(view_size.x, view_size.x / aspect)
	_preview_container.position = (view_size - new_size) * 0.5
	_preview_container.size = new_size


func _start_live_dot_pulse() -> void:
	var pulse := create_tween().set_loops()
	pulse.tween_property(_live_dot, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_live_dot, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _on_live_chat_event(event: Dictionary) -> void:
	live_chat_event.emit(event)


func _on_player_finished() -> void:
	_finish_show()


func _finish_show() -> void:
	if not _playing:
		return
	_playing = false
	show_finished.emit()
