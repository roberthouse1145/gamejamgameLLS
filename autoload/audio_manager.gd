## AudioManager —— 全局音频管理单例
## 功能：
##   - SFX 音效池（支持并发播放，互不打断）
##   - BGM 管理（循环播放、交叉淡入淡出切换；非原生 loop 的流会自动重播）
##   - 音量控制（分 SFX / BGM 两轨）
##   - key-based 音效注册（集中管理路径，避免到处 load()）
##
## 用法：
##   AudioManager.play_sfx_key("ui_click")          # 播放已注册的短音效
##   AudioManager.play_sfx(preload("res://...wav")) # 直接传 AudioStream
##   AudioManager.play_bgm(preload("res://...ogg")) # 播放背景音乐
##   AudioManager.stop_bgm(1.5)                     # 1.5s 淡出后停止
##   AudioManager.sfx_volume_db = -6.0              # 调整 SFX 音量

extends Node

# ==================== 信号 ====================
signal bgm_changed(stream: AudioStream)
signal bgm_finished(stream: AudioStream)

# ==================== SFX 音效池大小 ====================
const SFX_POOL_SIZE: int = 8

# ==================== 音量属性 ====================
var sfx_volume_db: float = 0.0:
	set(v):
		sfx_volume_db = v
		for player in _sfx_pool:
			player.volume_db = v

var bgm_volume_db: float = 0.0:
	set(v):
		bgm_volume_db = v
		_bgm_player_a.volume_db = v
		_bgm_player_b.volume_db = v

# ==================== 已注册的 SFX 表 ====================
## 在这里集中维护所有音效的路径映射
## key: 逻辑名称，value: res:// 路径（延迟加载，首次使用时 load）
var _sfx_registry: Dictionary = {
	# UI
	"ui_click":        "res://Assets/sounds/ui/cursor_click.wav",
	"ui_hover":        "res://Assets/sounds/ui/hover.ogg",
	"ui_window_open":  "res://Assets/sounds/ui/window_open.ogg",
	"ui_window_close": "res://Assets/sounds/ui/window_close.ogg",
	# 系统
	"sys_boot":        "res://Assets/sounds/system/boot.ogg",
	"sys_confirm":     "res://Assets/sounds/system/confirm.ogg",
	"sys_notify":      "res://Assets/sounds/system/notify.ogg",
	# 聊天
	"chat_send":       "res://Assets/sounds/chat/message_send.wav",
	"chat_receive":    "res://Assets/sounds/chat/message_send.wav",
	"chat_typing":     "res://Assets/sounds/chat/typing.ogg",
}

## 已加载的 AudioStream 缓存
var _sfx_cache: Dictionary = {}

# ==================== 内部节点 ====================
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

## 两个 BGM 播放器，用于交叉淡入淡出
var _bgm_player_a: AudioStreamPlayer
var _bgm_player_b: AudioStreamPlayer
var _bgm_active_player: AudioStreamPlayer  # 当前主播放器
var _bgm_current_stream: AudioStream = null

## 当前正在进行的 BGM 淡变 tween
var _bgm_tween: Tween = null


func _ready() -> void:
	# 创建 SFX 音效池
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = sfx_volume_db
		add_child(p)
		_sfx_pool.append(p)

	# 创建两个 BGM 播放器
	_bgm_player_a = AudioStreamPlayer.new()
	_bgm_player_a.bus = "BGM"
	_bgm_player_a.volume_db = bgm_volume_db
	_bgm_player_a.finished.connect(_on_bgm_player_finished.bind(_bgm_player_a))
	add_child(_bgm_player_a)

	_bgm_player_b = AudioStreamPlayer.new()
	_bgm_player_b.bus = "BGM"
	_bgm_player_b.volume_db = bgm_volume_db
	_bgm_player_b.volume_db = -80.0  # 初始静音
	_bgm_player_b.finished.connect(_on_bgm_player_finished.bind(_bgm_player_b))
	add_child(_bgm_player_b)

	_bgm_active_player = _bgm_player_a


# ==================== SFX 接口 ====================

## 通过逻辑 key 播放已注册的音效
## 文件不存在时静默跳过（不报错），方便在资源未就绪阶段开发
func play_sfx_key(key: String) -> void:
	if not _sfx_registry.has(key):
		push_warning("AudioManager: unknown sfx key '%s'" % key)
		return

	if not _sfx_cache.has(key):
		var path: String = _sfx_registry[key]
		if not ResourceLoader.exists(path):
			# 文件还没有导入，静默忽略
			return
		_sfx_cache[key] = load(path)

	play_sfx(_sfx_cache[key])


## 直接传入 AudioStream 播放（单次）
func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	# 从池中轮询一个空闲播放器（若全忙则抢占最旧的）
	var player: AudioStreamPlayer = _sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = sfx_volume_db
	player.play()


# ==================== BGM 接口 ====================

## 播放背景音乐（默认循环）
## crossfade_time: 交叉淡入淡出时长（秒），0 = 立即切换
func play_bgm(stream: AudioStream, crossfade_time: float = 1.0) -> void:
	if stream == null:
		return
	if _bgm_current_stream == stream and _bgm_active_player.playing:
		return  # 已在播放，跳过

	_bgm_current_stream = stream
	bgm_changed.emit(stream)

	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()

	# 确定新/旧播放器
	var incoming: AudioStreamPlayer
	var outgoing: AudioStreamPlayer
	if _bgm_active_player == _bgm_player_a:
		incoming = _bgm_player_b
		outgoing = _bgm_player_a
	else:
		incoming = _bgm_player_a
		outgoing = _bgm_player_b

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_bgm_active_player = incoming

	if crossfade_time <= 0.0:
		incoming.volume_db = bgm_volume_db
		outgoing.stop()
		outgoing.volume_db = bgm_volume_db
		return

	_bgm_tween = create_tween().set_parallel(true)
	_bgm_tween.tween_property(incoming, "volume_db", bgm_volume_db, crossfade_time)
	_bgm_tween.tween_property(outgoing, "volume_db", -80.0, crossfade_time)
	_bgm_tween.chain().tween_callback(func() -> void:
		outgoing.stop()
		outgoing.volume_db = bgm_volume_db
	)


## 停止背景音乐
func stop_bgm(fade_time: float = 0.5) -> void:
	if not _bgm_active_player.playing:
		return

	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()

	if fade_time <= 0.0:
		_bgm_active_player.stop()
		_bgm_current_stream = null
		return

	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm_active_player, "volume_db", -80.0, fade_time)
	_bgm_tween.tween_callback(func() -> void:
		_bgm_active_player.stop()
		_bgm_active_player.volume_db = bgm_volume_db
		_bgm_current_stream = null
	)


## 暂停 / 恢复 BGM
func pause_bgm() -> void:
	_bgm_active_player.stream_paused = true

func resume_bgm() -> void:
	_bgm_active_player.stream_paused = false


func seek_bgm(position_seconds: float) -> void:
	if _bgm_active_player == null or _bgm_active_player.stream == null:
		return
	_bgm_active_player.seek(maxf(position_seconds, 0.0))


func get_current_bgm_stream() -> AudioStream:
	return _bgm_current_stream


func get_bgm_playback_position() -> float:
	if _bgm_active_player == null or not _bgm_active_player.playing:
		return 0.0
	return _bgm_active_player.get_playback_position()


func is_bgm_paused() -> bool:
	if _bgm_active_player == null:
		return false
	return _bgm_active_player.stream_paused


func is_bgm_playing() -> bool:
	if _bgm_active_player == null:
		return false
	return _bgm_active_player.playing and not _bgm_active_player.stream_paused


## 动态注册新的音效 key（运行时也可调用）
func register_sfx(key: String, path: String) -> void:
	_sfx_registry[key] = path
	_sfx_cache.erase(key)  # 清除旧缓存


## 判断音频流是否自身已开启循环
## - AudioStreamOggVorbis / AudioStreamMP3: `loop` (bool)
## - AudioStreamWAV: `loop_mode` (enum，0 = LOOP_DISABLED)
func _stream_loops_natively(stream: AudioStream) -> bool:
	if stream == null:
		return false
	if "loop" in stream:
		return bool(stream.get("loop"))
	if "loop_mode" in stream:
		return int(stream.get("loop_mode")) != 0
	return false


func _on_bgm_player_finished(player: AudioStreamPlayer) -> void:
	if player != _bgm_active_player:
		return
	var finished_stream: AudioStream = _bgm_current_stream
	# 非原生 loop 的 BGM：自动重头播放，保持循环语义
	if finished_stream != null and not _stream_loops_natively(finished_stream):
		player.stream = finished_stream
		player.volume_db = bgm_volume_db
		player.play()
		return
	_bgm_current_stream = null
	if finished_stream != null:
		bgm_finished.emit(finished_stream)
