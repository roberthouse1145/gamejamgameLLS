class_name AVGAudioAdapter extends Node
## AVG DSL 的音频适配层。资源路径与 DSL 信号保留在 AVG 域，实际播放统一交给全局 AudioManager。

const AVGResourceLoaderClass = preload("res://scripts/avg/assets/avg_resource_loader.gd")

signal bgm_started(audio_path: String)
signal bgm_stopped
signal sfx_played(audio_path: String)

var _audio_manager: Node = null
var _current_bgm_path: String = ""
var _target_bgm_volume: float = 1.0
var _sfx_volume: float = 1.0


func _ready() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	if _audio_manager == null:
		push_error("AVGAudioAdapter: global AudioManager is unavailable")


func play_bgm(audio_path: String, fade_duration: float = 1.0, volume: float = 1.0) -> void:
	if audio_path.is_empty():
		push_warning("AVGAudioAdapter: Cannot play BGM with empty path")
		return
	var stream: AudioStream = _load_audio(audio_path)
	if stream == null:
		push_warning("AVGAudioAdapter: Failed to load BGM: %s" % audio_path)
		return
	if _audio_manager == null:
		return

	_target_bgm_volume = clampf(volume, 0.0, 1.0)
	_current_bgm_path = audio_path
	_audio_manager.call("play_bgm", stream, maxf(fade_duration, 0.0), _target_bgm_volume)
	bgm_started.emit(audio_path)


func stop_bgm(fade_duration: float = 1.0) -> void:
	if _audio_manager == null:
		_current_bgm_path = ""
		return
	var had_bgm: bool = bool(_audio_manager.call("is_bgm_playing"))
	_audio_manager.call("stop_bgm", maxf(fade_duration, 0.0))
	_current_bgm_path = ""
	if had_bgm:
		bgm_stopped.emit()


func play_sfx(audio_path: String, volume: float = 1.0) -> void:
	if audio_path.is_empty():
		push_warning("AVGAudioAdapter: Cannot play SFX with empty path")
		return
	var stream: AudioStream = _load_audio(audio_path)
	if stream == null:
		push_warning("AVGAudioAdapter: Failed to load SFX: %s" % audio_path)
		return
	if _audio_manager == null:
		return
	_audio_manager.call("play_sfx", stream, clampf(volume, 0.0, 1.0) * _sfx_volume)
	sfx_played.emit(audio_path)


func play_voice(audio_path: String, volume: float = 1.0) -> void:
	if audio_path.is_empty():
		push_warning("AVGAudioAdapter: Cannot play voice with empty path")
		return
	var stream: AudioStream = _load_audio(audio_path)
	if stream == null:
		push_warning("AVGAudioAdapter: Failed to load voice: %s" % audio_path)
		return
	if _audio_manager != null:
		_audio_manager.call("play_voice", stream, clampf(volume, 0.0, 1.0) * _sfx_volume)


func stop_voice() -> void:
	if _audio_manager != null:
		_audio_manager.call("stop_voice")


func stop_all_audio() -> void:
	stop_bgm(0.0)
	stop_voice()


func pause_bgm() -> void:
	if _audio_manager != null:
		_audio_manager.call("pause_bgm")


func resume_bgm() -> void:
	if _audio_manager != null:
		_audio_manager.call("resume_bgm")


func is_bgm_playing() -> bool:
	return _audio_manager != null and bool(_audio_manager.call("is_bgm_playing"))


func get_current_bgm() -> String:
	return _current_bgm_path


func set_bgm_volume(volume: float, fade_duration: float = 0.0) -> void:
	_target_bgm_volume = clampf(volume, 0.0, 1.0)
	if _audio_manager != null:
		_audio_manager.call("set_bgm_content_volume", _target_bgm_volume, maxf(fade_duration, 0.0))


func set_sfx_volume(volume: float) -> void:
	_sfx_volume = clampf(volume, 0.0, 1.0)


func _load_audio(audio_path: String) -> AudioStream:
	return AVGResourceLoaderClass.load_audio(audio_path)
