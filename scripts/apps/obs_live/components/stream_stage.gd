class_name StreamStage extends VBoxContainer
## 直播观看区。StreamScene 的显示与播放均独立于 AVGScene。

const DESIGN_RESOLUTION: Vector2 = Vector2(3840, 2160)
const SUPERCHAT_COLORS: Array[Color] = [
	Color("#3F8FE8"),
	Color("#7A62D3"),
	Color("#D45A92"),
	Color("#E06A3F"),
	Color("#C89B32"),
]

signal show_finished()
signal live_chat_event(event: Dictionary)

@onready var live_title: Label = %LiveTitle
@onready var live_viewers: Label = %LiveViewers
@onready var live_clock: Label = %LiveClock
@onready var avatar_rect: RoundedAvatar = %AvatarRect
@onready var channel_name: Label = %ChannelName
@onready var channel_tag: Label = %ChannelTag
@onready var fast_button: Button = %FastButton
@onready var skip_button: Button = %SkipButton
@onready var room_status: Label = %RoomStatus

@onready var _video_frame: Control = %VideoFrame
@onready var _camera_clip: Control = %CameraClip
@onready var _preview_container: SubViewportContainer = %PreviewContainer
@onready var _stream_display: StreamSceneDisplay = %StreamSceneDisplay
@onready var _show_player: LiveShowPlayer = %LiveShowPlayer
@onready var _reaction_overlay: LiveReactionOverlay = %LiveReactionOverlay
@onready var _subtitle_panel: PanelContainer = %SubtitlePanel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _live_dot: Label = %LiveDot
@onready var entrance_overlay: EntranceOverlay = %EntranceOverlay

## 观看人数由 obs_live_app 根据本场热度结算注入并实时刷新。
var viewers_target: int = 0:
	set(value):
		viewers_target = maxi(value, 0)
		if live_viewers != null:
			live_viewers.text = "%d 人在线" % viewers_target

var _playing: bool = false
var _persona: StreamPersonaResource = null
var _room_theme: StreamRoomThemeResource = null
var _resting: bool = true
var _screen_chat_enabled: bool = true
var _donation_animation_enabled: bool = true
var _reaction_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_camera_clip.resized.connect(_layout_preview)
	_show_player.setup(_stream_display, _subtitle_panel, _subtitle_label)
	_show_player.chat_event.connect(_on_live_chat_event)
	_show_player.finished.connect(_on_player_finished)
	_reaction_overlay.set_screen_chat_enabled(_screen_chat_enabled)
	_reaction_overlay.set_donation_animation_enabled(_donation_animation_enabled)
	_start_live_dot_pulse()
	resized.connect(_update_video_height)
	call_deferred("_update_video_height")
	call_deferred("_layout_preview")


func apply_room_theme(room_theme: StreamRoomThemeResource) -> void:
	_room_theme = room_theme
	if _resting:
		show_resting()
	else:
		show_live()


func show_resting() -> void:
	_resting = true
	if _persona != null and _persona.resting_background != null:
		_stream_display.set_background(_persona.resting_background)
	_stream_display.set_avatar_visible(false)
	if _subtitle_panel != null:
		_subtitle_panel.visible = false
	if _reaction_overlay != null:
		_reaction_overlay.clear()
	if room_status != null:
		room_status.text = "等待开播"


func show_live() -> void:
	_resting = false
	if _room_theme != null and _room_theme.live_background != null:
		_stream_display.set_background(_room_theme.live_background)
	_stream_display.set_avatar_visible(true)
	if room_status != null:
		room_status.text = "直播中"


func set_elapsed_text(value: String) -> void:
	live_clock.text = value


func refresh_channel_info() -> void:
	if _persona == null:
		return
	channel_name.text = _persona.channel_name
	channel_tag.text = _format_subscribers()
	avatar_rect.set_avatar(_persona.channel_avatar, _persona.channel_name)


func setup_persona(persona: StreamPersonaResource) -> bool:
	_persona = persona
	_show_player.configure_persona(_persona)
	if _persona == null or not _persona.is_valid():
		return false
	refresh_channel_info()
	var ok: bool = _stream_display.setup(_persona.model)
	if _resting:
		show_resting()
	return ok


func get_model_resource() -> StreamerModelResource:
	return _persona.model if _persona != null else null


func play_show(show_data: Dictionary, seed_value: int = 1) -> bool:
	var ops: Array = show_data.get("ops", [])
	if _persona == null or _persona.model == null or ops.is_empty():
		return false
	_show_player.stop()
	_reaction_rng.seed = seed_value ^ 0x5C01A7
	_reaction_overlay.reset(seed_value)
	show_live()
	if not _stream_display.setup(_persona.model):
		return false
	_stream_display.set_avatar_visible(true)
	_start_show_after_avatar_ready(ops, seed_value)
	return true


func _start_show_after_avatar_ready(ops: Array, seed_value: int) -> void:
	await _stream_display.wait_for_avatar_ready()
	if _persona == null or _persona.model == null:
		return
	_playing = _show_player.play(ops, seed_value)


func set_fast_forward(enabled: bool) -> void:
	_show_player.set_fast_forward(enabled)


func set_screen_chat_enabled(enabled: bool) -> void:
	_screen_chat_enabled = enabled
	if _reaction_overlay != null:
		_reaction_overlay.set_screen_chat_enabled(enabled)


func is_screen_chat_enabled() -> bool:
	return _screen_chat_enabled


func set_donation_animation_enabled(enabled: bool) -> void:
	_donation_animation_enabled = enabled
	if _reaction_overlay != null:
		_reaction_overlay.set_donation_animation_enabled(enabled)


func is_donation_animation_enabled() -> bool:
	return _donation_animation_enabled


func skip() -> void:
	_show_player.stop(true)


func is_playing() -> bool:
	return _playing


func _format_subscribers() -> String:
	var fans: int = 0
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null:
		fans = int(game_state.get("fans"))
	if fans >= 10000:
		return "%.1f 万位订阅者" % (float(fans) / 10000.0)
	return "%d 位订阅者" % fans


## 视频区使用父容器已经分配给舞台的宽度，再按 16:9 计算高度。
## 宽度不能由高度反推后写回最小尺寸，否则会与右侧弹幕栏形成横向溢出循环。
func _update_video_height() -> void:
	var container_width: float = size.x
	var stage_height: float = size.y
	if container_width < 2.0 or stage_height < 2.0:
		return
	var fixed_height: float = 0.0
	var control_count: int = 0
	for child: Node in get_children():
		var control := child as Control
		if control == null:
			continue
		control_count += 1
		if child != _video_frame:
			fixed_height += control.size.y
	fixed_height += (control_count - 1) * get_theme_constant("separation")
	var available_height: float = maxf(stage_height - fixed_height, 0.0)
	var height: float = minf(available_height, container_width * 9.0 / 16.0)
	if height < 2.0:
		return
	_video_frame.custom_minimum_size = Vector2(0.0, height)


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
	var display_event: Dictionary = event.duplicate(true)
	if str(display_event.get("kind", "")) == "sc":
		display_event["color"] = SUPERCHAT_COLORS[
			_reaction_rng.randi_range(0, SUPERCHAT_COLORS.size() - 1)
		]
	_reaction_overlay.handle_live_chat_event(display_event)
	live_chat_event.emit(display_event)


func _on_player_finished() -> void:
	_finish_show()


func _finish_show() -> void:
	if not _playing:
		return
	_playing = false
	show_resting()
	room_status.text = "已下播"
	show_finished.emit()
