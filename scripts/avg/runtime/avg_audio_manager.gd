class_name AVGAudioManager extends Node
## Manages BGM and SFX playback for AVG games
## Supports fade in/out for BGM and volume control.
## Validates: Requirement 7.6

## Emitted when BGM starts playing
signal bgm_started(audio_path: String)
## Emitted when BGM stops
signal bgm_stopped
## Emitted when SFX plays
signal sfx_played(audio_path: String)

## AudioStreamPlayer for background music
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
## AudioStreamPlayer for sound effects
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
## AudioStreamPlayer for voice lines
@onready var voice_player: AudioStreamPlayer = $VoicePlayer

## Current BGM path
var _current_bgm_path: String = ""
## Target BGM volume (before fade)
var _target_bgm_volume: float = 1.0
## Active BGM tween for fade effects
var _bgm_tween: Tween = null
## Monotonic request id used to invalidate stale BGM operations
var _bgm_request_id: int = 0
## Project root used for alias resolution
var _project_root_path: String = ""


func _ready() -> void:
	# Create audio players if they don't exist
	if bgm_player == null:
		bgm_player = AudioStreamPlayer.new()
		bgm_player.name = "BGMPlayer"
		add_child(bgm_player)
	
	if sfx_player == null:
		sfx_player = AudioStreamPlayer.new()
		sfx_player.name = "SFXPlayer"
		add_child(sfx_player)

	if voice_player == null:
		voice_player = AudioStreamPlayer.new()
		voice_player.name = "VoicePlayer"
		add_child(voice_player)

	# Align AVG runtime playback with the project's shared bus layout.
	bgm_player.bus = "BGM"
	sfx_player.bus = "SFX"
	voice_player.bus = "SFX"


## Play background music with optional fade-in
## @param audio_path: Path to the audio file
## @param fade_duration: Duration of fade-in (0 for instant)
## @param volume: Target volume (0.0 to 1.0)
func play_bgm(audio_path: String, fade_duration: float = 1.0, volume: float = 1.0) -> void:
	if audio_path.is_empty():
		push_warning("AVGAudioManager: Cannot play BGM with empty path")
		return
	
	# Clamp volume
	volume = clampf(volume, 0.0, 1.0)
	_target_bgm_volume = volume
	
	# Load the audio stream
	var stream: AudioStream = _load_audio(audio_path)
	if stream == null:
		push_warning("AVGAudioManager: Failed to load BGM: %s" % audio_path)
		return
	
	var request_id: int = _begin_bgm_request()
	var was_playing: bool = bgm_player.playing

	_cancel_bgm_tween()
	
	# If same BGM is already playing, just adjust volume
	if _current_bgm_path == audio_path and bgm_player.playing:
		_fade_bgm_volume(volume, fade_duration, request_id)
		return
	
	if was_playing and fade_duration > 0.0:
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(bgm_player, "volume_db", -80.0, fade_duration / 2.0)
		_bgm_tween.tween_callback(func() -> void:
			_start_bgm_stream(stream, audio_path, volume, fade_duration / 2.0, request_id)
		)
		return

	_start_bgm_stream(stream, audio_path, volume, fade_duration, request_id)


## Stop background music with optional fade-out
## @param fade_duration: Duration of fade-out (0 for instant)
func stop_bgm(fade_duration: float = 1.0) -> void:
	var request_id: int = _begin_bgm_request()

	if not bgm_player.playing:
		_current_bgm_path = ""
		bgm_player.stream_paused = false
		return
	
	_cancel_bgm_tween()
	
	if fade_duration > 0.0:
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(bgm_player, "volume_db", -80.0, fade_duration)
		_bgm_tween.tween_callback(func() -> void:
			if request_id != _bgm_request_id:
				return
			_stop_bgm_now()
		)
		return

	_stop_bgm_now()


## Play a sound effect
## @param audio_path: Path to the audio file
## @param volume: Volume level (0.0 to 1.0)
func play_sfx(audio_path: String, volume: float = 1.0) -> void:
	if audio_path.is_empty():
		push_warning("AVGAudioManager: Cannot play SFX with empty path")
		return
	
	# Clamp volume
	volume = clampf(volume, 0.0, 1.0)
	
	# Load the audio stream
	var stream: AudioStream = _load_audio(audio_path)
	if stream == null:
		push_warning("AVGAudioManager: Failed to load SFX: %s" % audio_path)
		return
	
	# Play the sound effect
	sfx_player.stream = stream
	sfx_player.volume_db = linear_to_db(volume)
	sfx_player.play()
	
	sfx_played.emit(audio_path)


## Play a voice line (stops any previous voice)
## @param audio_path: Path to the voice audio file
## @param volume: Volume level (0.0 to 1.0)
func play_voice(audio_path: String, volume: float = 1.0) -> void:
	if audio_path.is_empty():
		push_warning("AVGAudioManager: Cannot play voice with empty path")
		return

	volume = clampf(volume, 0.0, 1.0)

	var stream: AudioStream = _load_audio(audio_path)
	if stream == null:
		push_warning("AVGAudioManager: Failed to load voice: %s" % audio_path)
		return

	voice_player.stream = stream
	voice_player.volume_db = linear_to_db(volume)
	voice_player.play()


## Stop voice playback
func stop_voice() -> void:
	voice_player.stop()


func stop_all_audio() -> void:
	_begin_bgm_request()
	_cancel_bgm_tween()
	var had_bgm: bool = bgm_player.playing
	bgm_player.stop()
	bgm_player.stream_paused = false
	bgm_player.stream = null
	bgm_player.volume_db = linear_to_db(_target_bgm_volume)
	_current_bgm_path = ""
	sfx_player.stop()
	voice_player.stop()
	if had_bgm:
		bgm_stopped.emit()


## Pause BGM playback
func pause_bgm() -> void:
	bgm_player.stream_paused = true


## Resume BGM playback
func resume_bgm() -> void:
	bgm_player.stream_paused = false


## Check if BGM is playing
func is_bgm_playing() -> bool:
	return bgm_player.playing and not bgm_player.stream_paused


## Get current BGM path
func get_current_bgm() -> String:
	return _current_bgm_path


func set_project_root_path(project_root_path: String) -> void:
	_project_root_path = project_root_path


## Set BGM volume (with optional fade)
## @param volume: Target volume (0.0 to 1.0)
## @param fade_duration: Duration of fade (0 for instant)
func set_bgm_volume(volume: float, fade_duration: float = 0.0) -> void:
	volume = clampf(volume, 0.0, 1.0)
	_target_bgm_volume = volume
	_fade_bgm_volume(volume, fade_duration, _bgm_request_id)


## Set SFX volume
## @param volume: Volume level (0.0 to 1.0)
func set_sfx_volume(volume: float) -> void:
	volume = clampf(volume, 0.0, 1.0)
	sfx_player.volume_db = linear_to_db(volume)


## Load an audio stream from path
## @param audio_path: Path to the audio file
## @return: AudioStream or null
func _load_audio(audio_path: String) -> AudioStream:
	return StorageManager.load_audio_from_path(audio_path, null, _project_root_path)


func _begin_bgm_request() -> int:
	_bgm_request_id += 1
	return _bgm_request_id


func _start_bgm_stream(stream: AudioStream, audio_path: String, volume: float, fade_duration: float, request_id: int) -> void:
	if request_id != _bgm_request_id:
		return

	_cancel_bgm_tween()
	_current_bgm_path = audio_path
	bgm_player.stream_paused = false
	bgm_player.stream = stream

	if fade_duration > 0.0:
		bgm_player.volume_db = -80.0
		bgm_player.play()
		_fade_bgm_volume(volume, fade_duration, request_id)
	else:
		bgm_player.volume_db = linear_to_db(volume)
		bgm_player.play()

	bgm_started.emit(audio_path)


func _stop_bgm_now() -> void:
	var had_bgm: bool = bgm_player.playing
	bgm_player.stop()
	bgm_player.stream_paused = false
	bgm_player.stream = null
	bgm_player.volume_db = linear_to_db(_target_bgm_volume)
	_current_bgm_path = ""
	if had_bgm:
		bgm_stopped.emit()


## Fade BGM volume to target
## @param target_volume: Target volume (0.0 to 1.0)
## @param duration: Fade duration
func _fade_bgm_volume(target_volume: float, duration: float, request_id: int) -> void:
	if request_id != _bgm_request_id:
		return

	_cancel_bgm_tween()
	
	if duration <= 0.0:
		bgm_player.volume_db = linear_to_db(target_volume)
		return
	
	var target_db: float = linear_to_db(target_volume)
	
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(bgm_player, "volume_db", target_db, duration)


## Cancel any active BGM tween
func _cancel_bgm_tween() -> void:
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
		_bgm_tween = null
