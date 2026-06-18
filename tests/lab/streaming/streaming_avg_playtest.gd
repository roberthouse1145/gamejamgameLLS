extends Node

## Playtest 场景：绕过 AI 生成，直接用真实角色+背景资产播放 streaming AVG。
## 运行方式：mcp run_project 指定此场景，手动观察视觉效果后 stop_project 停止。

const PLAYER_SCENE: PackedScene = preload("res://scenes/date_events/date_event_player.tscn")

const AVGProjectClass = preload("res://scripts/avg/resources/avg_project.gd")
const CHARACTER_RES: String = "res://narrative_projects/main_story/characters/lin_xia_story.tres"
const PROJECT_ROOT: String = "res://narrative_projects/main_story/"

# 用于切换的多段剧本，按数字键 1-3 重新播放
const SCRIPTS: Array[String] = [
	"""
@stream "周三下午的直播" host=LinXia viewers=248 day="第3天"
bg bg_apartment_living
host LinXia default casual
say "大家好！今天准时开播了！" speed=30 hold=0.8
chat "好耶！" delay=0.2
chat "主播来了！" delay=0.5
emotion happy
say "上次直播说要做攻略的，今天终于来了。" speed=28 hold=1.0
chat "等了好久！" delay=0.3
say "我这里有个秘密存档点，普通攻略都没有的那种。" speed=25 hold=1.2
chat "真的假的" delay=0.2
chat "大神！" delay=0.6
emotion smirk
say "当然是真的，不然我开这个直播干嘛。" speed=30 hold=0.8
wait 0.5
say "好，开始。" speed=35 hold=0.6
end
""",
	"""
@stream "深夜唠嗑" host=LinXia viewers=51 day="第5天"
bg bg_apartment_bedroom
host LinXia soft_smile loungewear
say "今天人比较少，正好聊点平时不聊的。" speed=25 hold=1.0
chat "我在我在" delay=0.3
emotion thoughtful
say "最近有没有人觉得……自己做的东西没人看，还要不要继续？" speed=22 hold=1.5
chat "有过" delay=0.4
chat "我懂这种感觉" delay=0.8
say "我也是。上个月有段时间差点停更。" speed=24 hold=1.2
emotion sigh
say "后来是因为收到一条评论，说我的视频帮他熬过了一段很难的时间。" speed=20 hold=1.8
chat "谢谢你" delay=0.5
chat "别停更！" delay=0.9
emotion soft_smile
say "所以我就想，哪怕只有一个人，也值得做下去。" speed=26 hold=1.0
wait 0.8
say "好了，不说丧的了。" speed=30 hold=0.5
end
""",
	"""
@stream "商业街闲逛" host=LinXia viewers=132 day="第2天"
bg bg_commercial_street
host LinXia happy casual
say "今天在外面给大家直播，信号应该还行吧？" speed=30 hold=0.8
chat "听得到！" delay=0.2
chat "清楚清楚" delay=0.4
emotion laugh
say "太好了！这条街我特别喜欢，每次路过都忍不住逛。" speed=28 hold=1.0
chat "哪里啊" delay=0.3
say "就是那个……你们懂的，每家都在放音乐那种地方。" speed=26 hold=1.0
chat "hahaha" delay=0.2
chat "每家不同的歌好混乱" delay=0.5
emotion teasing
say "混乱才有意思嘛，等会我要去那家卖旧磁带的店。" speed=28 hold=0.9
chat "带我们一起！" delay=0.3
say "带你们一起！走了！" speed=35 hold=0.6
wait 0.3
end
""",
]

var _player: Control = null
var _current_script_index: int = 0


func _ready() -> void:
	print("\n=== Streaming AVG Playtest ===")
	print("  数字键 1/2/3 切换剧本并重新播放")
	print("  回车键重播当前剧本")
	print("  ESC 键停止当前播放")
	_build_player()
	await get_tree().process_frame
	_play_script(_current_script_index)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_play_script(0)
			KEY_2:
				_play_script(1)
			KEY_3:
				_play_script(2)
			KEY_ENTER, KEY_KP_ENTER:
				_play_script(_current_script_index)
			KEY_ESCAPE:
				if _player != null and _player.has_method("stop_playback"):
					_player.call("stop_playback")
					print("  [Playtest] 播放已停止")


func _build_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Control
	if _player == null:
		push_error("[Playtest] DateEventPlayer 实例化失败")
		return
	# 重置场景内置的 anchor_right/bottom=1.0，否则控件会撑满 viewport
	_player.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var vp_size := get_viewport().get_visible_rect().size
	_player.size = Vector2(1600, 900)
	_player.position = (vp_size - _player.size) / 2.0
	add_child(_player)
	_player.playback_finished.connect(_on_playback_finished)
	print("  [Playtest] DateEventPlayer 加载完成（1600x900）")


func _play_script(index: int) -> void:
	if _player == null:
		push_error("[Playtest] player 未初始化")
		return
	_current_script_index = index
	var script_text: String = SCRIPTS[index]

	var project: Resource = _build_project()
	var session_id := "playtest_%d" % index
	var package := {
		"session_id": session_id,
		"title": "Playtest %d" % (index + 1),
		"stream_script": script_text,
		"project": project,
		"project_root_path": PROJECT_ROOT,
	}
	print("\n  [Playtest] 播放剧本 %d..." % (index + 1))
	_player.call("play_stream_package", session_id, package, false)


func _build_project() -> Resource:
	var narrative_manager: Node = get_node_or_null("/root/NarrativeProjectManager")
	if narrative_manager != null and narrative_manager.has_method("duplicate_current_project"):
		var p: Resource = narrative_manager.duplicate_current_project()
		if p != null:
			return p

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage != null and storage.get("current_project") is Resource:
		return (storage.get("current_project") as Resource).duplicate(true)

	# 回退：手动加载角色资源组装一个最小 project
	var project: Resource = AVGProjectClass.new()
	if ResourceLoader.exists(CHARACTER_RES):
		var char_res: Resource = ResourceLoader.load(CHARACTER_RES)
		if char_res != null and "characters" in project:
			project.characters = [char_res]
			print("  [Playtest] 已加载角色资源: %s" % CHARACTER_RES)
		else:
			print("  [Playtest] AVGProject 没有 characters 属性，角色可能不显示")
	else:
		print("  [Playtest] 角色资源不存在: %s" % CHARACTER_RES)
	return project


func _on_playback_finished(session_id: String, outcome: Dictionary) -> void:
	print("  [Playtest] 播放结束: session=%s success=%s" % [session_id, str(outcome.get("success", false))])
	if not bool(outcome.get("success", true)):
		var errors: Array = outcome.get("parse_errors", [])
		for e in errors:
			print("    错误: %s" % str(e))
	print("  提示：按 1/2/3 换剧本，回车重播，ESC 停止")
