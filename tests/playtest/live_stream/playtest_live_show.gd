extends Control
## 真实 Desktop + PseudoWindow 壳验收直播 DSL 放映。
## 入口：tests/playtest/live_stream/playtest_live_show.tscn

const OBS_APP_PATH: String = "res://resources/apps/obs_live_app.tres"
const DEMO_DSL: String = """posture: idle
expression: strained
gesture: wave
say: 大家晚上好……今天来打那个卡了我一星期的 BOSS。
chat: 来了来了 | 终于打这个了 | 前排围观受难 | 加油柚柚
wait: 0.35
posture: lean_forward
expression: serious
say: 好，深呼吸一下。这一次应该……能过吧。
chat: 稳住 | 我信你 | 草我紧张了
sc: 加油！今晚必须过！
wait: 0.25
posture: thinking
expression: shocked
gesture: shake_head
say: 等一下，血量怎么还剩这么多——啊啊啊！
chat 25: 翻车预警 | 别慌 | 哈哈哈 | 节目效果 | 草
sc 4: 节目效果有了 | 打赏压惊 | 再来一次
wait: 0.8
posture: slump
expression: sad
say: 又没过……让我缓一会儿。
chat: 摸摸 | 心疼 | 下把一定行
wait: 0.5
posture: proud
expression: laugh
gesture: cheer
say: 骗你们的，刚才其实过了！哈哈哈哈！
chat 20: ？？？ | 好家伙 | 被骗了 | 牛的牛的
sc: 恭喜过关！
posture: idle
expression: smile
gesture: bow
say: 今天先到这里，谢谢大家陪我挨打。下次见。
chat: 辛苦了 | 下次见 | 下播打卡
"""

@onready var state_label: Label = %StateLabel

var _app: Control = null
var _chat_event_count: int = 0


func _ready() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		_set_state("AppManager 不可用")
		return
	if not app_manager.is_app_registered("obs_live"):
		app_manager.install_app_from_path(OBS_APP_PATH)
	var window: Control = app_manager.launch_app("obs_live", true)
	if window == null:
		_set_state("打开直播姬失败")
		return
	_app = window.get("content") as Control
	if _app == null or not _app.has_method("play_test_show"):
		_set_state("直播姬实例无效")
		return
	var stream_stage: Node = _app.get_node_or_null("%StreamStage")
	if stream_stage != null:
		if not stream_stage.is_connected("live_chat_event", _on_chat_event):
			stream_stage.connect("live_chat_event", _on_chat_event)
		if not stream_stage.is_connected("show_finished", _on_show_finished):
			stream_stage.connect("show_finished", _on_show_finished)
	var ok: bool = bool(_app.play_test_show(DEMO_DSL))
	_set_state("编译并开播" if ok else "DSL 编译失败，请看输出")
	print("[Playtest] play_test_show returned: %s" % ok)


func _on_replay_pressed() -> void:
	if _app == null or not is_instance_valid(_app):
		_boot()
		return
	var ok: bool = bool(_app.play_test_show(DEMO_DSL))
	_set_state("重播中" if ok else "重播失败")


func _on_fast_pressed() -> void:
	if _app == null:
		return
	var fast_button: Button = _app.get("fast_button") if _app.get("fast_button") != null else _app.get_node_or_null("%FastButton")
	if fast_button != null:
		fast_button.pressed.emit()
		_set_state("已切换快进/原速")


func _on_skip_pressed() -> void:
	if _app == null:
		return
	var skip_button: Button = _app.get("skip_button") if _app.get("skip_button") != null else _app.get_node_or_null("%SkipButton")
	if skip_button != null:
		skip_button.pressed.emit()
		_set_state("已请求跳过")


func _on_chat_event(event: Dictionary) -> void:
	_chat_event_count += 1
	print("[Playtest] chat_event #%d kind=%s" % [_chat_event_count, str(event.get("kind", ""))])


func _on_show_finished() -> void:
	call_deferred("_report_show_finished")


func _report_show_finished() -> void:
	var settlement: Control = _app.get_node_or_null("%SettlementPanel") if _app != null else null
	var settlement_visible: bool = settlement != null and settlement.visible
	print("[Playtest] scene_ended chat_events=%d settlement_visible=%s" % [
		_chat_event_count,
		str(settlement_visible),
	])
	_set_state("播放结束，结算已显示" if settlement_visible else "播放结束")


func _set_state(text: String) -> void:
	if state_label != null:
		state_label.text = text
	print("[Playtest] %s" % text)
