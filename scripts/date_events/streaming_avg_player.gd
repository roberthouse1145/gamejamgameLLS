class_name StreamingAVGPlayer
extends Control

signal stream_finished(session_id: String, outcome: Dictionary)

const StreamingAVGDSLParserClass = preload("res://scripts/date_events/streaming_avg_dsl_parser.gd")
const STREAM_RESOLUTION: Vector2 = Vector2(1024, 768)
const OFFLINE_CG_PATH: String = "res://narrative_projects/main_story/Assets/background/bg_stream_offline_mirai.png"
const CONTENT_INSET: Vector2 = Vector2(24, 24)
const VIDEO_MAX_SIZE: Vector2 = Vector2(960, 720)
const VIDEO_MIN_SIZE: Vector2 = Vector2(400, 300)
const CHAT_TARGET_WIDTH: float = 460.0
const CHAT_MIN_WIDTH: float = 420.0
const CONTENT_GAP: float = 16.0
const SITE_BAR_HEIGHT: float = 30.0
const SITE_BAR_GAP: float = 18.0
const INFO_AREA_HEIGHT: float = 150.0
const INFO_AREA_GAP: float = 22.0
const VIDEO_INFO_HEIGHT: float = 48.0
const COLUMN_GAP: float = 8.0

@onready var title_label: Label = %StreamTitleLabel
@onready var stats_label: Label = %StreamStatsLabel
@onready var live_mark: Label = %LiveMark
@onready var site_bar: HBoxContainer = %SiteBar
@onready var stream_layout: HBoxContainer = %StreamLayout
@onready var left_column: VBoxContainer = %LeftColumn
@onready var aspect_root: Control = %AspectRoot
@onready var video_frame: Control = %VideoFrame
@onready var stage_clip: Control = %StageClip
@onready var stage_design: Control = %StageDesign
@onready var fallback_bg: ColorRect = %FallbackBackground
@onready var background_texture: TextureRect = %BackgroundTexture
@onready var character_display: Control = %CharacterDisplay
@onready var subtitle_panel: PanelContainer = %SubtitlePanel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var skip_button: Button = %SkipButton
@onready var chat_panel: PanelContainer = %ChatPanel
@onready var chat_header: Label = %ChatHeader
@onready var chat_scroll: ScrollContainer = %ChatScroll
@onready var chat_list: VBoxContainer = %ChatList
@onready var info_area: VBoxContainer = %InfoArea

var _session_id: String = ""
var _events: Array[Dictionary] = []
var _meta: Dictionary = {}
var _project: Resource = null
var _project_root_path: String = ""
var _playback_token: int = 0
var _playing: bool = false
var _finished: bool = false
var _skip_requested: bool = false
var _current_host: String = ""
var _chat_count: int = 0


func _ready() -> void:
	resized.connect(_fit_stream_layout)
	if skip_button != null:
		skip_button.pressed.connect(_on_skip_pressed)
	if aspect_root != null:
		aspect_root.resized.connect(_fit_video_frame)
	if stage_clip != null:
		stage_clip.clip_contents = true
	if character_display != null:
		character_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if character_display.has_method("set_design_resolution"):
			character_display.call("set_design_resolution", STREAM_RESOLUTION)
	_fit_stream_layout()
	show_idle()


func play(session_id: String, stream_package: Dictionary) -> void:
	_playback_token += 1
	_session_id = session_id
	_project = stream_package.get("project", null) as Resource
	_project_root_path = str(stream_package.get("project_root_path", "")).strip_edges()
	_events.clear()
	_meta.clear()
	_chat_count = 0
	_current_host = ""
	_finished = false
	_playing = true
	_skip_requested = false

	var raw_events: Array = stream_package.get("events", [])
	for raw_event in raw_events:
		if raw_event is Dictionary:
			_events.append((raw_event as Dictionary).duplicate(true))

	if _events.is_empty():
		var script_text := str(stream_package.get("stream_script", ""))
		var parser := StreamingAVGDSLParserClass.new()
		var parse_result := parser.parse(script_text)
		if not bool(parse_result.get("success", false)):
			_finish({
				"success": false,
				"error": "invalid_stream_script",
				"parse_errors": parse_result.get("errors", []),
			})
			return
		for raw_event in parse_result.get("events", []):
			if raw_event is Dictionary:
				_events.append((raw_event as Dictionary).duplicate(true))
		_meta = (parse_result.get("meta", {}) as Dictionary).duplicate(true)
	else:
		_meta = (stream_package.get("meta", {}) as Dictionary).duplicate(true)

	var title := str(stream_package.get("title", _meta.get("title", "直播"))).strip_edges()
	if title.is_empty():
		title = "直播"
	_update_header(title)
	_reset_ui()
	if live_mark != null:
		live_mark.text = "▶ live"
		live_mark.add_theme_color_override("font_color", Color(0.88, 0.22, 0.34, 1))
	if chat_header != null:
		chat_header.text = "留言"
	_setup_character_display()
	_fit_stream_layout()
	call_deferred("_run_stream", _playback_token)


func stop() -> void:
	_playback_token += 1
	_playing = false
	_finished = true
	_skip_requested = false
	if character_display != null and character_display.has_method("hide_all"):
		character_display.call("hide_all", 0.0)


func show_idle(title: String = "Mirai 的直播间", viewers: int = 0, day_label: String = "") -> void:
	_playback_token += 1
	_session_id = ""
	_events.clear()
	_meta = {
		"title": title,
		"viewers": viewers,
		"day_label": day_label,
	}
	_project = null
	_project_root_path = ""
	_chat_count = 0
	_current_host = ""
	_finished = true
	_playing = false
	_skip_requested = false
	_update_header(title)
	_reset_ui()
	_set_offline_art()
	if stats_label != null:
		stats_label.text = "直播准备中"
	if live_mark != null:
		live_mark.text = "■ standby"
		live_mark.add_theme_color_override("font_color", Color(0.45, 0.4, 0.62, 1))
	if chat_header != null:
		chat_header.text = "留言"
	_fit_stream_layout()


func is_playing() -> bool:
	return _playing and not _finished


func _run_stream(token: int) -> void:
	for event in _events:
		if not _is_token_active(token):
			return
		var event_type := str(event.get("type", ""))
		match event_type:
			"stream_meta":
				var incoming_meta: Dictionary = event.get("meta", {})
				_meta.merge(incoming_meta, true)
				_update_header(str(_meta.get("title", title_label.text if title_label != null else "直播")))
			"background":
				_set_background(str(event.get("asset_ref", "")))
			"host_show":
				_show_host(event)
				await _wait_seconds(float(event.get("duration", 0.2)), token)
			"host_emotion":
				_change_host_emotion(event)
				await _wait_seconds(float(event.get("duration", 0.2)), token)
			"subtitle":
				await _show_subtitle(event, token)
			"chat":
				await _show_chat(event, token)
			"wait":
				await _wait_seconds(float(event.get("duration", 0.0)), token)
			"end":
				_finish({"success": true, "completed": true})
				return
			_:
				push_warning("StreamingAVGPlayer: unknown event type '%s'" % event_type)
	_finish({"success": true, "completed": true})


func _reset_ui() -> void:
	if background_texture != null:
		background_texture.texture = null
	if fallback_bg != null:
		fallback_bg.visible = true
	if subtitle_panel != null:
		subtitle_panel.visible = false
	if subtitle_label != null:
		subtitle_label.text = ""
		subtitle_label.visible_characters = -1
	if skip_button != null:
		skip_button.disabled = not _playing
		skip_button.visible = _playing
	if chat_list != null:
		for child in chat_list.get_children():
			child.queue_free()
	if character_display != null and character_display.has_method("hide_all"):
		character_display.call("hide_all", 0.0)


func _update_header(title: String) -> void:
	if title_label != null:
		title_label.text = title
	if stats_label == null:
		return
	var viewers := int(_meta.get("viewers", 0))
	var day_label := str(_meta.get("day_label", "")).strip_edges()
	var parts: Array[String] = []
	if viewers > 0:
		parts.append("%d 人正在观看" % viewers)
	if not day_label.is_empty():
		parts.append(day_label)
	stats_label.text = " · ".join(PackedStringArray(parts))


func _set_background(asset_ref: String) -> void:
	var texture := load_texture_from_project(asset_ref)
	if background_texture != null:
		background_texture.texture = texture
	if fallback_bg != null:
		fallback_bg.visible = texture == null


func _set_offline_art() -> void:
	var texture: Texture2D = null
	if ResourceLoader.exists(OFFLINE_CG_PATH):
		var resource := ResourceLoader.load(OFFLINE_CG_PATH)
		if resource is Texture2D:
			texture = resource as Texture2D
	if texture == null:
		var image := Image.new()
		if image.load(OFFLINE_CG_PATH) == OK:
			texture = ImageTexture.create_from_image(image)
	if background_texture != null:
		background_texture.texture = texture
	if fallback_bg != null:
		fallback_bg.visible = texture == null


func _show_host(event: Dictionary) -> void:
	_current_host = str(event.get("character", "")).strip_edges()
	if _current_host.is_empty() or character_display == null:
		return
	if not character_display.has_method("show_character"):
		return
	var x := clampf(float(event.get("x", 0.5)), 0.0, 1.0)
	var y := clampf(float(event.get("y", 0.73)), 0.0, 1.0)
	var pos_name := "%f,%f" % [x, y]
	character_display.call(
		"show_character",
		_current_host,
		pos_name,
		str(event.get("emotion", "default")),
		float(event.get("duration", 0.2)),
		false,
		float(event.get("scale", 1.42)),
		1.0,
		str(event.get("outfit", ""))
	)


func _change_host_emotion(event: Dictionary) -> void:
	if _current_host.is_empty() or character_display == null:
		return
	if not character_display.has_method("change_expression"):
		return
	character_display.call(
		"change_expression",
		_current_host,
		str(event.get("emotion", "")),
		"crossfade",
		float(event.get("duration", 0.2)),
		str(event.get("outfit", ""))
	)


func _show_subtitle(event: Dictionary, token: int) -> void:
	if subtitle_panel == null or subtitle_label == null:
		await _wait_seconds(float(event.get("duration", 0.0)), token)
		return

	var text := str(event.get("text", ""))
	var speed := maxf(float(event.get("speed", 30.0)), 1.0)
	var hold := maxf(float(event.get("hold", 0.8)), 0.0)
	var char_count := text.length()
	var skipped := false
	subtitle_panel.visible = not text.is_empty()
	subtitle_label.text = text
	subtitle_label.visible_characters = 0

	var elapsed := 0.0
	var type_duration := float(char_count) / speed if char_count > 0 else 0.0
	while _is_token_active(token) and char_count > 0 and subtitle_label.visible_characters < char_count:
		if _skip_requested:
			_skip_requested = false
			skipped = true
			subtitle_label.visible_characters = -1
			break
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		subtitle_label.visible_characters = mini(char_count, int(floor(elapsed * speed)))

	if not _is_token_active(token):
		return
	if not skipped:
		subtitle_label.visible_characters = -1
		var explicit_duration := float(event.get("duration", type_duration + hold))
		var remaining_hold := maxf(explicit_duration - type_duration, hold)
		await _wait_seconds(remaining_hold, token)


func _show_chat(event: Dictionary, token: int) -> void:
	await _wait_seconds(float(event.get("delay", 0.25)), token)
	if not _is_token_active(token):
		return
	_add_chat_message(str(event.get("text", "")))


func _add_chat_message(text: String) -> void:
	if chat_list == null or text.strip_edges().is_empty():
		return
	_chat_count += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_list.add_child(row)

	const CHAT_COLORS: Array[Color] = [
		Color(0.48, 0.40, 0.72, 1.0),
		Color(0.35, 0.48, 0.78, 1.0),
		Color(0.74, 0.34, 0.47, 1.0),
	]
	var marker := ColorRect.new()
	marker.custom_minimum_size = Vector2(3, 11)
	marker.color = CHAT_COLORS[(_chat_count - 1) % 3]
	row.add_child(marker)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.24, 0.22, 0.34, 1))
	row.add_child(label)
	call_deferred("_scroll_chat_to_bottom")


func _scroll_chat_to_bottom() -> void:
	if chat_scroll == null:
		return
	var bar := chat_scroll.get_v_scroll_bar()
	if bar != null:
		chat_scroll.scroll_vertical = int(bar.max_value)


func _wait_seconds(seconds: float, token: int) -> void:
	var elapsed := 0.0
	var duration := maxf(seconds, 0.0)
	while _is_token_active(token) and elapsed < duration:
		if _skip_requested:
			_skip_requested = false
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _finish(outcome: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_playing = false
	_skip_requested = false
	if skip_button != null:
		skip_button.disabled = true
	stream_finished.emit(_session_id, outcome)


func _is_token_active(token: int) -> bool:
	return token == _playback_token and _playing and not _finished and is_inside_tree()


func _on_skip_pressed() -> void:
	if not _playing:
		return
	_skip_requested = true


func _fit_stream_layout() -> void:
	if site_bar == null or stream_layout == null or left_column == null or aspect_root == null or chat_panel == null or info_area == null:
		return
	var available := size - CONTENT_INSET * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		return

	var chat_width := minf(CHAT_TARGET_WIDTH, maxf(CHAT_MIN_WIDTH, available.x - VIDEO_MIN_SIZE.x - CONTENT_GAP))
	var video_width := minf(VIDEO_MAX_SIZE.x, available.x - chat_width - CONTENT_GAP)
	var video_height := minf(VIDEO_MAX_SIZE.y, video_width * 0.75)
	var max_video_height := available.y - SITE_BAR_HEIGHT - SITE_BAR_GAP - VIDEO_INFO_HEIGHT - COLUMN_GAP - INFO_AREA_GAP - INFO_AREA_HEIGHT
	video_height = minf(video_height, maxf(VIDEO_MIN_SIZE.y, max_video_height))
	video_width = minf(video_width, video_height * (4.0 / 3.0))

	var video_size := Vector2(floor(video_width), floor(video_height))
	var left_height := video_size.y + COLUMN_GAP + VIDEO_INFO_HEIGHT
	var layout_size := Vector2(video_size.x + CONTENT_GAP + chat_width, maxf(left_height, video_size.y))
	var content_height := SITE_BAR_HEIGHT + SITE_BAR_GAP + layout_size.y + INFO_AREA_GAP + INFO_AREA_HEIGHT

	var layout_position := Vector2(
		floor(maxf(CONTENT_INSET.x, (size.x - layout_size.x) * 0.5)),
		floor(maxf(CONTENT_INSET.y, (size.y - content_height) * 0.5 + SITE_BAR_HEIGHT + SITE_BAR_GAP))
	)
	site_bar.position = Vector2(layout_position.x, layout_position.y - SITE_BAR_GAP - SITE_BAR_HEIGHT)
	site_bar.size = Vector2(layout_size.x, SITE_BAR_HEIGHT)
	site_bar.custom_minimum_size = Vector2(layout_size.x, SITE_BAR_HEIGHT)
	stream_layout.position = layout_position
	stream_layout.size = layout_size
	info_area.position = Vector2(layout_position.x, layout_position.y + layout_size.y + INFO_AREA_GAP)
	info_area.size = Vector2(layout_size.x, INFO_AREA_HEIGHT)
	info_area.custom_minimum_size = Vector2(layout_size.x, INFO_AREA_HEIGHT)
	left_column.custom_minimum_size = Vector2(video_size.x, left_height)
	left_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	aspect_root.custom_minimum_size = video_size
	aspect_root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	aspect_root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chat_panel.custom_minimum_size = Vector2(chat_width, video_size.y)
	chat_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chat_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	call_deferred("_fit_video_frame")


func _fit_video_frame() -> void:
	if aspect_root == null or video_frame == null or stage_design == null:
		return
	var available := Vector2(
		minf(aspect_root.size.x, VIDEO_MAX_SIZE.x),
		minf(aspect_root.size.y, VIDEO_MAX_SIZE.y)
	)
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var ratio := 4.0 / 3.0
	var new_size := available
	if available.x / available.y > ratio:
		new_size.x = available.y * ratio
	else:
		new_size.y = available.x / ratio
	video_frame.size = new_size
	video_frame.position = (available - new_size) / 2.0

	stage_design.size = STREAM_RESOLUTION
	stage_design.position = Vector2.ZERO
	stage_design.scale = Vector2(new_size.x / STREAM_RESOLUTION.x, new_size.y / STREAM_RESOLUTION.y)
	if subtitle_panel != null:
		subtitle_panel.position = Vector2(152, 575)
		subtitle_panel.size = Vector2(720, 116)


func _setup_character_display() -> void:
	if character_display == null:
		return
	var char_data: Dictionary = {}
	if _project != null and ("characters" in _project):
		for character in _project.characters:
			if character == null:
				continue
			var char_id := str(character.character_id if "character_id" in character else "").strip_edges()
			if char_id.is_empty():
				continue
			char_data[char_id] = {
				"character_name": character.character_name if "character_name" in character else "",
				"display_name": character.display_name if "display_name" in character else "",
				"sprites": character.sprites if "sprites" in character else {},
				"default_outfit": character.default_outfit if "default_outfit" in character else "",
				"available_outfits": character.available_outfits if "available_outfits" in character else [],
				"emotion_slots": character.emotion_slots if "emotion_slots" in character else {},
				"sprite_prefix": character.sprite_prefix if "sprite_prefix" in character else "",
				"sprite_base_dir": character.sprite_base_dir if "sprite_base_dir" in character else "",
				"sprite_extension": character.sprite_extension if "sprite_extension" in character else "png",
				"display_offset": character.display_offset if "display_offset" in character else Vector2.ZERO,
				"display_scale": character.display_scale if "display_scale" in character else 1.0,
			}
	if character_display.has_method("set_design_resolution"):
		character_display.call("set_design_resolution", STREAM_RESOLUTION)
	if character_display.has_method("set_character_data"):
		character_display.call("set_character_data", char_data)
	if character_display.has_method("set_texture_loader"):
		character_display.call("set_texture_loader", Callable(self, "load_texture_from_project"))


func load_texture_from_project(asset_ref: String) -> Texture2D:
	var normalized := asset_ref.strip_edges()
	if normalized.is_empty():
		return null
	if ResourceLoader.exists(normalized):
		var resource := ResourceLoader.load(normalized)
		if resource is Texture2D:
			return resource as Texture2D
	var storage := get_node_or_null("/root/StorageManager")
	if storage != null and storage.has_method("load_texture_from_path"):
		var texture: Variant = storage.call("load_texture_from_path", normalized, _project, _project_root_path)
		if texture is Texture2D:
			return texture as Texture2D
	return null
