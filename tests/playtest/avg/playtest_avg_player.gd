extends Control
## 人工验证 AVG 播放器核心链路:
## 启动后自动播放一段内嵌 DSL,覆盖旁白、台词、选择块与播放完成回调。

const DEMO_DSL: String = """screen.fade(direction="in", duration=0.35)
# => TextBlock()
> 这是一段用于验证 AVG 播放器的基础演示剧情。
# => TextBlock(speaker="SpeakerA")
> 你好,我是发言者 A。如果你能看到这段话,说明台词块解析与显示正常。
# => TextBlock(speaker="SpeakerB", expression="happy")
> 我是发言者 B。请选择下方任意选项,验证选择块交互。
# => ChoiceBlock()
- 选择甲
	var[playtest_choice] = 1
	# => TextBlock()
	> 你选择了甲。
- 选择乙
	var[playtest_choice] = 2
	# => TextBlock()
	> 你选择了乙。
# => TextBlock()
> 播放结束,窗口稍后会自动返回等待界面。
screen.fade(direction="out", duration=0.5)
"""

@onready var player: Control = %AVGPlayer


func _ready() -> void:
	player.playback_finished.connect(_on_playback_finished)
	var started: bool = player.play_dsl("playtest_avg_player", DEMO_DSL, "播放器演示")
	print("[Playtest] play_dsl returned: %s" % started)


func _on_playback_finished(session_id: String, outcome: Dictionary) -> void:
	print(
		"[Playtest] playback_finished: session=%s success=%s choice_id=%s choice_text=%s"
		% [
			session_id,
			outcome.get("success", false),
			outcome.get("choice_id", "null"),
			outcome.get("choice_text", ""),
		]
	)
